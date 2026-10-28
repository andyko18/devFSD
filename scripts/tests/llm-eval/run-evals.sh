#!/usr/bin/env bash
# specops-ko LLM eval runner — 메타 skill 신호 감지 + 체인 진입 smoke eval
# 사용: bash scripts/tests/llm-eval/run-evals.sh [fixtures.jsonl]
# 환경: CLAUDE_BIN(기본 claude) · LLM_EVAL_MAX_TURNS(기본 4) · LLM_EVAL_TIMEOUT(기본 300초)
# ⚠️ 실 claude 실행은 토큰 비용 발생 (실측 ~$0.9/fixture — 재시도 cap=1 포함) — run-all/CI 비포함, 수동 전용
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FIXTURES="${1:-$HERE/fixtures.jsonl}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
# 기본 4 — ★ 올리지 마라. 20260813 에 4→12 로 올렸다가 실측으로 반증하고 되돌렸다.
#   함정: `--allowedTools Skill` 은 **배타 제한이 아니다**. CLI 의미는 "권한 프롬프트 면제 목록"이고
#   deny 는 `--disallowedTools` 다. 그래서 모델은 Bash·Read·**Write** 를 자유롭게 쓴다.
#   그 상태에서 FAIL 이 `error_max_turns` 로 끝나면 "턴이 모자라다"로 읽히지만, transcript 를 뜨면
#   정반대다 — 턴 여유를 주면 모델은 Skill 을 부르는 대신 **직접 다 만들어버린다**:
#     · maint-1 @4턴  → ls/find → Read → git log+버그재현 → locale 대조 → error_max_turns, Skill 0회
#     · new-1  @12턴 → 조사 3턴 후 "TDD 순서. 테스트 먼저" → Write ×8 + npm test, Skill 0회,
#                       thinking·text 에 specops/skill 언급 **0회**, 비용 $0.41 → $1.41 (3.4배)
#   `new-1` 은 4턴에서 PASS 하던 fixture 다. 즉 **낮은 max_turns 가 우연히 강제력으로 작동**하고 있다.
#   ⚠️ 그래서 이 eval 의 통과율은 "신호 감지율"이 아니라 "시간 없을 때 뭘 먼저 하나"에 가깝다.
#      실사용은 턴 무제한이므로 실제 감지율은 이 숫자보다 낮다 — 해석 시 주의.
#   조사를 `--disallowedTools` 로 봉쇄하지도 않는다 — "볼 게 없으니 Skill 부름"이 되어 더 왜곡된다.
MAX_TURNS="${LLM_EVAL_MAX_TURNS:-4}"
# 기본 300 — 이건 유지한다(max_turns 되돌림과 무관하게 독립적으로 유효).
#   구 120 초는 조사 도중 끊어 **판정 실패를 TIMEOUT 으로 가렸다**. 실측: 같은 fixture 6건이
#   120s=TIMEOUT → 300s=판정 결과 노출(`got=none`)로 뒤집혔다. TIMEOUT 은 원인을 감추는 층이었다.
TIMEOUT_S="${LLM_EVAL_TIMEOUT:-300}"

# N-run 신뢰성 모드 (LLM_EVAL_RUNS>1) — wshobson PluginEval Layer3 이식
RUNS="${LLM_EVAL_RUNS:-1}"
case "$RUNS" in
  ''|*[!0-9]*|0*)   # 빈값·비숫자·선행0(0·01·10줄바꿈 등) → 폴백
    [ "${LLM_EVAL_RUNS:-1}" != "1" ] && echo "경고: LLM_EVAL_RUNS='${LLM_EVAL_RUNS:-}' 비정수/0/음수 — 1로 폴백" >&2
    RUNS=1 ;;
esac
FLAKY_THRESHOLD=80   # 성공률 % 하한 — 미만이면 FLAKY (AC-S-2, 관찰용·비차단)

# I-1: fixtures 부재 시 false green 차단
[ -f "$FIXTURES" ] || { echo "FAIL: fixtures 없음: $FIXTURES"; exit 1; }

total=$(grep -c . "$FIXTURES" || true)
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  echo "SKIP: claude CLI 부재 (CLAUDE_BIN=$CLAUDE_BIN)"
  echo "PASS=0 FAIL=0 SKIP=$total BORDERLINE=0 COST=\$0.00"
  exit 0
fi

PASS=0; FAIL=0; BORDER=0; COST=0
FLAKY=0; NRUN_FIXTURES=0; NRUN_RATE_SUM=0   # N-run 집계 (AC-3, AC-4)

# sandbox 격리 — headless lifecycle 부작용 (브랜치 생성·체크아웃·.specops 오염) 을 temp repo 에 가둠
# fixture별 sandbox_seed 에 맞춰 재시드 (both=정상 specifying 진입 / none·specops-only=부트스트랩 안내 유도)
SANDBOX=""
setup_sandbox() {  # $1=seed(both|none|specops-only) $2=fixture json(선택) → 전역 SANDBOX 재구성 (fixture별 격리)
  [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"
  SANDBOX=$(mktemp -d)
  git -C "$SANDBOX" init -q
  case "$1" in
    none) ;;                                          # 둘 다 미시드 → 전체 부트스트랩 안내
    specops-only) mkdir -p "$SANDBOX/.specops" ;;     # .specops만 → 부분 안내
    *) mkdir -p "$SANDBOX/.specops"; printf '# sandbox\n' > "$SANDBOX/CLAUDE.md" ;;  # both(기본)
  esac
  seed_fixture_files "${2:-}"
}

seed_fixture_files() {  # $1=fixture json → .seed_files(경로→내용 맵)를 sandbox 에 생성 + git tracked
  # 유지보수 fixture 는 prompt 가 참조하는 대상 파일이 sandbox 에 실재해야 측정이 성립한다.
  # 부재 시 모델은 "고칠 대상이 없다"고 정직하게 중단하고, eval 은 그걸 신호 미감지로 오판한다 (선재 결함).
  # ★ git tracked 필수: 모델이 `git ls-files` 로 존재를 확인한다 (실측 — 무시드 sandbox 에 "추적 파일 0개" 라 답했다).
  local fx="$1" n k
  [ -z "$fx" ] && return 0
  n=$(printf '%s' "$fx" | jq -r '(.seed_files // {}) | length' 2>/dev/null || echo 0)
  [ "${n:-0}" -gt 0 ] || return 0   # AC-3: seed_files 미기재 fixture 는 현재 동작 그대로 (커밋조차 만들지 않음)
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    case "$k" in                    # sandbox 밖 경로 차단 (절대경로·상위참조)
      /*|*..*) echo "경고: seed_files 경로 무시 (sandbox 이탈): $k" >&2; continue ;;
    esac
    mkdir -p "$SANDBOX/$(dirname "$k")"
    printf '%s' "$fx" | jq -r --arg k "$k" '.seed_files[$k]' > "$SANDBOX/$k"
    case "$k" in *.sh) chmod +x "$SANDBOX/$k" ;; esac
  done < <(printf '%s' "$fx" | jq -r '(.seed_files // {}) | keys[]')
  # sandbox 는 임시 디렉터리 — git identity 부재 가능 → 인라인 지정 (전역 config 미오염)
  git -C "$SANDBOX" add -A >/dev/null 2>&1
  git -C "$SANDBOX" -c user.email=eval@specops.invalid -c user.name=specops-eval \
      commit -q -m "seed: fixture 참조 대상 파일" >/dev/null 2>&1
}
cleanup() {  # M-4: mktemp trap — sandbox + attempt 잔여 임시파일 정리
  rm -rf "$SANDBOX"
  [ -n "${R_MARK:-}" ] && rm -f "$R_MARK"
  [ -n "${R_ERR:-}" ] && rm -f "$R_ERR"
  return 0
}
trap cleanup EXIT

run_once() {  # $1=prompt → stdout=stream-json. LLM_EVAL_TIMEOUT 워치독 (bash 3.2, GNU timeout 미의존)
  # I-2: stderr 는 R_ERR 에 보존, timeout kill 은 R_MARK 마커 기록 (호출자 attempt 가 경로 준비)
  # < /dev/null: while 루프의 fixtures FD 0 상속 차단 / cd "$SANDBOX": 부작용 격리 (exec 으로 pid=claude 유지)
  local out_f pid flag
  out_f=$(mktemp)
  (cd "$SANDBOX" && exec "$CLAUDE_BIN" -p "$1" --output-format stream-json --verbose \
    --max-turns "$MAX_TURNS" --allowedTools Skill) < /dev/null > "$out_f" 2>"$R_ERR" &
  pid=$!
  # 워치독 stdout/stderr 차단 필수 — 미차단 시 자식 sleep 이 명령치환 파이프를 물고 EOF 지연 (hang)
  # 워치독은 신호로 정리하지 않는다 — 부모는 flag 만 지우고 워치독이 1초 안에 스스로 끝난다(run-bounded.sh 와 같은 방식).
  #   종전 `kill watcher` → `pkill -P watcher` 는 sleep 이 재부모화돼 질의마다 고아 `sleep $TIMEOUT_S` 를 남겼고,
  #   TERM trap 대안은 신호가 trap 설치 전후 창에 떨어지면 워치독이 살아남아 부모가 멈췄다(20260929-run-evals-orphan-sleep 실측).
  # timeout 시 claude 가 띄운 자식 프로세스까지 정리 (pkill -P) 후 본체 kill · 마커는 flag 재확인 뒤 기록(정상 종료 후 거짓 마커 차단)
  flag=$(mktemp)
  ( lim=$TIMEOUT_S; case "$lim" in ''|*[!0-9]*) lim=${lim%%.*}; case "$lim" in ''|*[!0-9]*) lim=0 ;; esac; lim=$((lim + 1)) ;; esac
    n=0; while [ "$n" -lt "$lim" ]; do [ -e "$flag" ] || exit 0; sleep 1; n=$((n + 1)); done
    [ -e "$flag" ] || exit 0; : > "$R_MARK"; pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  wait "$pid" 2>/dev/null || true
  rm -f "$flag"
  cat "$out_f"; rm -f "$out_f"
}

parse_first_skill() {  # stdin=stream-json → "<skill>\t<args 첫 줄>" (없으면 빈)
  jq -r 'select(.type=="assistant") | .message.content[]?
         | select(.type=="tool_use" and .name=="Skill")
         | [.input.skill, ((.input.args // "") | split("\n")[0])] | @tsv' 2>/dev/null | head -1
}

extract_cost() {  # stdin=stream-json → 비용 (없으면 0)
  jq -r 'select(.type=="result") | .total_cost_usd // 0' 2>/dev/null | head -1 | grep . || echo 0
}

# $1=expect_skill $2=expect_flag $3=got_skill $4=got_args_l1 $5=expect_bootstrap $6=texts
# → PASS | FAIL:<사유>  (사유 구분 — 20260713: got 만 출력하면 skill 정답인데 flag 로 떨어진 경우를
#   skill 오답처럼 보여줘 진단이 불가능했다. maint-1/maint-3 가 실제로 그 케이스였다.)
judge() {
  local want="$1" flag="$2" got="$3" l1="$4" boot="$5" texts="$6"
  if [ -n "$boot" ]; then  # 부트스트랩 차원 — text 발화만 검사, Skill 차원 완전 분리 (early-return)
    printf '%s' "$texts" | grep -Eq "$boot" && echo PASS || echo "FAIL:boot"
    return
  fi
  if [ "$want" = "none" ]; then
    [ -z "$got" ] && echo PASS || echo "FAIL:unexpected"
    return
  fi
  if [ "$got" != "devfsd:$want" ] && [ "$got" != "$want" ]; then
    echo "FAIL:skill"; return
  fi
  if [ "$flag" = "maintain" ]; then
    case "$l1" in
      *"<!-- entry: maintain -->"*) ;;
      *) echo "FAIL:flag"; return ;;   # skill 은 정답 — args 첫 줄 약속어만 누락
    esac
  fi
  echo PASS
}

attempt() {  # $1=prompt → 전역 G_SKILL/G_L1/G_TIMEOUT/G_ERR1 설정 + COST 누적
  local out res c
  R_MARK=$(mktemp); rm -f "$R_MARK"   # 부재 = timeout 없음
  R_ERR=$(mktemp)
  out=$(run_once "$1")
  G_TIMEOUT=0; [ -f "$R_MARK" ] && G_TIMEOUT=1
  G_ERR1=$(head -1 "$R_ERR" 2>/dev/null || true)
  rm -f "$R_MARK" "$R_ERR"
  c=$(printf '%s\n' "$out" | extract_cost)
  COST=$(awk -v a="$COST" -v b="$c" 'BEGIN{printf "%.4f", a+b}')
  res=$(printf '%s\n' "$out" | parse_first_skill)
  G_SKILL="${res%%$'\t'*}"
  G_L1="${res#*$'\t'}"; [ "$res" = "$G_SKILL" ] && G_L1=""
  G_TEXTS=$(printf '%s\n' "$out" | jq -r 'select(.type=="assistant")|.message.content[]?|select(.type=="text")|.text' 2>/dev/null | paste -sd' ' -)
}

_fixture_nrun() {  # $1=id $2=prompt $3=want $4=flag $5=boot — retry 없이 N회, 성공률 집계 (AC-1·2·3·6)
  local id="$1" prompt="$2" want="$3" flag="$4" boot="$5" i=0 pass=0 v rate
  while [ "$i" -lt "$RUNS" ]; do
    i=$((i+1))
    attempt "$prompt"
    v=$(judge "$want" "$flag" "$G_SKILL" "$G_L1" "$boot" "$G_TEXTS")
    [ "$G_TIMEOUT" = "1" ] && v=TIMEOUT     # AC-6: TIMEOUT=실패 카운트
    [ "$v" = "PASS" ] && pass=$((pass+1))
  done
  rate=$(( pass * 100 / RUNS ))
  NRUN_FIXTURES=$((NRUN_FIXTURES+1)); NRUN_RATE_SUM=$((NRUN_RATE_SUM+rate))
  if [ "$rate" -lt "$FLAKY_THRESHOLD" ]; then
    FLAKY=$((FLAKY+1)); echo "FLAKY $id  $pass/$RUNS (${rate}%) ⚠️"
  else
    PASS=$((PASS+1)); echo "PASS $id  $pass/$RUNS (${rate}%)"
  fi
}

_borderline_nrun() {  # $1=id $2=prompt $3=any — 성공률/FLAKY 미집계, 매칭 표기 (AC-7)
  local id="$1" prompt="$2" any="$3" i=0 match=0 short
  while [ "$i" -lt "$RUNS" ]; do
    i=$((i+1))
    attempt "$prompt"
    [ "$G_TIMEOUT" = "1" ] && continue
    short="${G_SKILL#devfsd:}"; [ -z "$G_SKILL" ] && short="none"
    case ",$any," in *",$short,"*) match=$((match+1)) ;; esac
  done
  BORDER=$((BORDER+1)); echo "BORDERLINE $id  매칭 $match/$RUNS"
}

run_fixture() {  # $1=fixture json 1줄
  local fx="$1" id prompt want flag any short verdict retry=""
  id=$(printf '%s' "$fx" | jq -r '.id')
  prompt=$(printf '%s' "$fx" | jq -r '.prompt')
  any=$(printf '%s' "$fx" | jq -r '(.expect_any // []) | join(",")')
  want=$(printf '%s' "$fx" | jq -r '.expect_skill // "none"')
  flag=$(printf '%s' "$fx" | jq -r '.expect_flag // "none"')
  local seed boot
  seed=$(printf '%s' "$fx" | jq -r '.sandbox_seed // "both"')
  boot=$(printf '%s' "$fx" | jq -r '.expect_bootstrap // ""')
  setup_sandbox "$seed" "$fx"

  if [ "$RUNS" -gt 1 ]; then                      # N-run 신뢰성 모드
    if [ -n "$any" ]; then _borderline_nrun "$id" "$prompt" "$any"
    else _fixture_nrun "$id" "$prompt" "$want" "$flag" "$boot"; fi
    return
  fi

  attempt "$prompt"

  if [ -n "$any" ]; then  # 경계 케이스 — judge 전 처리, 비차단·재시도 없음 (AC-11)
    if [ "$G_TIMEOUT" = "1" ]; then  # I-2: timeout 빈 출력의 'none' 가양성 차단 (비차단 유지)
      BORDER=$((BORDER+1)); echo "BORDERLINE $id (TIMEOUT ${TIMEOUT_S}s)"; return
    fi
    short="${G_SKILL#devfsd:}"; [ -z "$G_SKILL" ] && short="none"
    case ",$any," in
      *",$short,"*) PASS=$((PASS+1)); echo "PASS $id (borderline-allowed)" ;;
      *) BORDER=$((BORDER+1)); echo "BORDERLINE $id (got=$short allow=[$any])" ;;
    esac
    return
  fi

  verdict=$(judge "$want" "$flag" "$G_SKILL" "$G_L1" "$boot" "$G_TEXTS")
  [ "$G_TIMEOUT" = "1" ] && verdict=TIMEOUT  # I-2: timeout 시도는 판정 불성립 — none PASS 차단
  if [ "$verdict" != "PASS" ]; then  # 재시도 cap=1 (AC-6)
    attempt "$prompt"
    verdict=$(judge "$want" "$flag" "$G_SKILL" "$G_L1" "$boot" "$G_TEXTS")
    [ "$G_TIMEOUT" = "1" ] && verdict=TIMEOUT
    retry=" retry"
  fi
  if [ "$verdict" = "PASS" ]; then
    PASS=$((PASS+1)); echo "PASS $id$retry"
  elif [ "$verdict" = "TIMEOUT" ]; then
    FAIL=$((FAIL+1)); echo "FAIL $id$retry (TIMEOUT ${TIMEOUT_S}s)${G_ERR1:+ — stderr: $G_ERR1}"
  else
    local why
    case "$verdict" in
      FAIL:flag)       why="skill 정답(${G_SKILL}) — args 첫 줄 '<!-- entry: maintain -->' 누락" ;;
      FAIL:unexpected) why="want=none 인데 ${G_SKILL} 호출" ;;
      FAIL:boot)       why="부트스트랩 안내 문구 미발화" ;;
      *)               why="want=$want got=${G_SKILL:-none}" ;;
    esac
    FAIL=$((FAIL+1)); echo "FAIL $id$retry ($why)${G_ERR1:+ — stderr: $G_ERR1}"
  fi
}

while IFS= read -r fx; do
  [ -z "$fx" ] && continue
  run_fixture "$fx"
done < "$FIXTURES"

# B층 신호: 실행 완주 시각 기록 (SKIP 경로 제외 — release.sh pre-flight staleness 경고가 소비)
# LLM_EVAL_STAMP_DIR: 테스트 격리용 override (기본 repo root .specops-cache/)
STAMP_DIR="${LLM_EVAL_STAMP_DIR:-$HERE/../../../.specops-cache}"
mkdir -p "$STAMP_DIR" 2>/dev/null || true
date -u +%Y-%m-%dT%H:%M:%SZ > "$STAMP_DIR/llm-eval-last-run" 2>/dev/null || true

if [ "$RUNS" -gt 1 ]; then
  avg=0; [ "$NRUN_FIXTURES" -gt 0 ] && avg=$(( NRUN_RATE_SUM / NRUN_FIXTURES ))
  printf 'PASS=%d FLAKY=%d BORDERLINE=%d 평균활성률=%d%% RUNS=%d COST=$%.2f\n' \
    "$PASS" "$FLAKY" "$BORDER" "$avg" "$RUNS" "$COST"
  # N-run 은 리포트 전용 — 비차단 (exit 0). 성공지표: FLAKY 관찰용
else
  printf 'PASS=%d FAIL=%d SKIP=0 BORDERLINE=%d COST=$%.2f\n' "$PASS" "$FAIL" "$BORDER" "$COST"
  [ "$FAIL" -eq 0 ]
fi
