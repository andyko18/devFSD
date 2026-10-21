#!/usr/bin/env bash
# specops-ko skill 별 활성화·행동 eval 러너 — skills/<name>/{trigger-queries,evals}.json
# 사용: bash scripts/tests/llm-eval/run-skill-evals.sh --trigger|--evals [skill...]
# 환경: CLAUDE_BIN(기본 claude) · SKILL_EVAL_DIR(기본 이 디렉터리의 skills/) · SKILL_EVAL_MODE(routed 강제)
#       ANTHROPIC_API_KEY(있으면 isolated) · LLM_EVAL_MAX_TURNS(기본 4) · LLM_EVAL_TIMEOUT(기본 300초)
#       SKILL_EVAL_INJECT=1(케이스 `agent` 필드의 agent 본문을 그 케이스 질의에만 --append-system-prompt 로 주입 — with/without 비교용)
#         케이스 `knowledge`(플러그인 기준 .md 경로 목록)가 있으면 그 파일 내용을 본문 뒤 "보조 지식 파일" 절로 함께 주입한다 —
#         평가는 Read 를 막아(DENY) 에이전트가 지식 파일(DB 엔진·구조 패턴)을 스스로 읽을 수 없기 때문이다(20261021 실측: 3회 모두 엔진 파일 미독).
#         파일이 없으면 그 케이스는 SKIP(지식 없는 무음 측정 금지). SKILL_EVAL_KNOWLEDGE_ROOT(기본 플러그인 루트 — 테스트용)
#       SKILL_EVAL_AGENTS_DIR(agent 파일 디렉터리, 기본 플러그인 agents/ — 테스트용)
#       SKILL_EVAL_EFFORT=<low|medium|high|xhigh|max> · SKILL_EVAL_MODEL=<모델 별칭/ID>(candidate 질의에만 --effort/--model — 채점기 제외, effort·model arm 비교용 · CLAUDE_CODE_EFFORT_LEVEL 설정 시 EFFORT 노브는 거절)
#       SKILL_EVAL_CASES=<id,id,…>(--evals 전용 — 지정 id 의 케이스만 질의·채점, 파일럿 비용 절감용. 선택 안 된 케이스는 집계하지 않는다)
# ⚠️ 실 claude 실행은 토큰 비용 발생(~$0.9/질의) — run-all/CI 비포함, 수동 전용. 질의당 1회, 재시도·N-run 없음.
# 측정 모드:
#   isolated — `--bare --plugin-dir <플러그인>`: 훅(SessionStart 메타 주입 포함)을 끄고 description 만으로
#              Skill 을 고르게 하려는 경로. --bare 는 OAuth 를 읽지 않아 ANTHROPIC_API_KEY 가 필요하다.
#              훅 차단·description 해석은 **실측 미확인**이라 요약줄에 `isolated(unverified)` 로 적는다
#              (20260929-skill-behavior-eval IQ-1 — 첫 키 보유 실행에서 확인 후 이 표기를 뗀다).
#   routed   — 현행 run-evals.sh 와 같은 인자: 메타 skill 라우팅이 섞인 측정. `--plugin-dir` 가 없으므로
#              사용자 전역에 specops-ko 가 설치·활성이어야 skill 이 존재하고, 사용자 훅도 그대로 발화한다.
# claude 가 result 이벤트 없이 끝나면(인증 실패·플래그 미지원 등) SKIP(error) — FAIL·PASS 로 세지 않는다.
# 통과율은 max_turns=4 편향을 상속한다(run-evals.sh 헤더) — 감지율이 아니라 신호로만 읽는다.
# 조사·우회 도구 차단(DENY): `--allowedTools Skill` 은 허용 목록일 뿐이라 모델이 Bash 로 빈 sandbox 를 조사하고
#   "코드 없음"으로 끝내 Skill 을 부르지 않았다(2026-09-30 라이브 1회 · 20260930-skill-eval-tool-lock). 두 모드 모두
#   조사·우회 도구를 막아 "Skill 을 부를지"만으로 응답하게 한다 — 이 변경 전 라이브 결과와는 측정 의미가 달라 비교 불가.
#   `--tools Skill` 은 Skill 이 내장 목록 밖이라 전 도구가 꺼져 쓰지 않는다(실측).
#   `--strict-mcp-config`: routed 는 사용자 전역 MCP 도구(실측 31개 · filesystem 포함)가 노출돼 차단을 우회한다 — MCP 서버를 올리지 않는다.
# 픽스처 repo(SKILL_EVAL_FIXTURE · 기본 skill-eval-fixture-repo/): 빈 sandbox 는 system 컨텍스트의 git status 로 드러나
#   기존 코드를 전제하는 질의가 "파일 없음"으로 끝났다(실측 빈 2/3 · 픽스처 커밋 3/3 — 20260930-skill-eval-fixture-repo).
#   질의마다 픽스처를 복사해 CLAUDE.md 까지 커밋한다(git status clean). 픽스처가 없으면 종전 빈 sandbox.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN=$(cd "$HERE/../../.." && pwd)
# shellcheck disable=SC1091
source "$HERE/eval-lib.sh"
# shellcheck disable=SC1091
source "$HERE/skill-evals-lib.sh"

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
DATA_DIR="${SKILL_EVAL_DIR:-$HERE/skills}"
MAX_TURNS="${LLM_EVAL_MAX_TURNS:-4}"
TIMEOUT_S="${LLM_EVAL_TIMEOUT:-300}"
FIXTURE_DIR="${SKILL_EVAL_FIXTURE:-$HERE/skill-eval-fixture-repo}"
# 호출자 셸의 git 위치 변수는 sandbox 의 git·claude(자식 프로세스)를 sandbox 밖으로 끌고 간다(git 훅 안 실행 등) — 러너는 호출자
#   repo 를 쓰지 않으므로 전부 해제한다(pre-commit 은 GIT_INDEX_FILE 을 설정한다 — 실측)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
FIXTURE_NOTED=0

case "${1:-}" in
  --trigger) KIND=trigger; FILE=trigger-queries.json ;;
  --evals)   KIND=evals;   FILE=evals.json ;;
  *) echo "사용: bash run-skill-evals.sh --trigger|--evals [skill...]" >&2; exit 0 ;;  # spec FR-8 — 항상 exit 0
esac
shift

MODE=routed; LABEL=routed
if [ "${SKILL_EVAL_MODE:-}" = routed ]; then
  echo "NOTE: SKILL_EVAL_MODE=routed 강제 — 메타 라우팅 혼합 측정"
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  MODE=isolated; LABEL="isolated(unverified)"
else
  echo "NOTE: isolated 불가(ANTHROPIC_API_KEY 부재) — routed: 메타 라우팅 혼합 측정 (전역 설치 플러그인·사용자 훅 의존)"
fi
INJECT="${SKILL_EVAL_INJECT:-0}"
AGENTS_DIR="${SKILL_EVAL_AGENTS_DIR:-$PLUGIN/agents}"
KNOW_ROOT="${SKILL_EVAL_KNOWLEDGE_ROOT:-$PLUGIN}"
INJ_N=0; INJ_CAND=0   # 주입한 케이스 수 / 주입 대상(agent 필드 보유 · 주입 on 일 때만 집계)
[ "$INJECT" = 1 ] && LABEL="${LABEL}+inject"
# arm 노브(20261007-eval-effort-knob) — candidate 질의(ask())에만 --effort/--model 을 건다. 채점기는 eval::judge_rubric 이 별도 호출하므로
#   구조적으로 격리된다(arm 마다 채점 모델이 바뀌면 비교가 오염). 형식 오류는 비용이 나가기 전에 사유 1줄 + exit 0 으로 거절(FR-8)
ARM_EFFORT="${SKILL_EVAL_EFFORT:-}"; ARM_MODEL="${SKILL_EVAL_MODEL:-}"
_arm_safe() { printf '%s' "${1:0:40}" | LC_ALL=C tr -d '\000-\037\177'; }
case "$ARM_EFFORT" in
  ''|low|medium|high|xhigh|max) ;;
  *) echo "ERROR: SKILL_EVAL_EFFORT 형식 오류: $(_arm_safe "$ARM_EFFORT") (허용: low|medium|high|xhigh|max) — 실행하지 않음"; exit 0 ;;
esac
# 허용 문자를 직접 나열 — A-Z 범위식은 bash 3.2 UTF-8 로케일에서 é·전각 문자까지 포함한다
case "$ARM_MODEL" in
  '') ;;
  [!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]*|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-]*) echo "ERROR: SKILL_EVAL_MODEL 형식 오류: $(_arm_safe "$ARM_MODEL") (허용: 영숫자로 시작하는 [A-Za-z0-9._-]) — 실행하지 않음"; exit 0 ;;
esac
if [ -n "$ARM_EFFORT" ] && [ -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" ]; then   # env 가 --effort 를 무력화 → arm 무구분(AC-5)
  echo "ERROR: SKILL_EVAL_EFFORT 와 CLAUDE_CODE_EFFORT_LEVEL 이 함께 설정됨 — env 가 --effort 를 무력화해 effort arm 이 구분되지 않는다(/doctor effort_env 참조). CLAUDE_CODE_EFFORT_LEVEL 을 해제하고 다시 실행 — 실행하지 않음"; exit 0
fi
[ -n "$ARM_EFFORT" ] && LABEL="${LABEL}+effort=$ARM_EFFORT"
[ -n "$ARM_MODEL" ] && LABEL="${LABEL}+model=$ARM_MODEL"
# 케이스 필터(20261008-eval-case-filter) — --evals 에서 지정한 id 만 질의·채점한다. 선택 안 된 케이스는 열거·SKIP 집계 없음.
#   형식은 허용 문자 나열(문자 범위는 UTF-8 로케일 bash 3.2 에서 비ASCII 를 통과시킨다 — PR #132 C 리뷰 I-1). 오류는 비용 전 사유 1줄 + exit 0
CASES_RAW="${SKILL_EVAL_CASES:-}"; CASES_N=0; CASES_MATCHED=","
case "$CASES_RAW" in
  '') ;;
  [!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]*|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._,-]*|*,|*,[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]*)
    echo "ERROR: SKILL_EVAL_CASES 형식 오류: $(_arm_safe "$CASES_RAW") (허용: 쉼표 구분 id — 각 id 는 영숫자로 시작, [영숫자 . _ -] 만) — 실행하지 않음"; exit 0 ;;
esac
if [ -n "$CASES_RAW" ] && [ "$KIND" = trigger ]; then
  echo "NOTE: SKILL_EVAL_CASES 는 --evals 전용 — --trigger 에서는 무시한다"; CASES_RAW=""
fi
DENY=(Bash Read Glob Grep Agent Edit Write NotebookEdit WebFetch WebSearch ToolSearch)
EXTRA=(--max-turns "$MAX_TURNS" --allowedTools Skill --disallowedTools "${DENY[@]}" --strict-mcp-config)
[ "$MODE" = isolated ] && EXTRA+=(--bare --plugin-dir "$PLUGIN")

if [ "$#" -gt 0 ]; then SKILLS=("$@")
else SKILLS=(); for d in "$DATA_DIR"/*/; do [ -d "$d" ] && SKILLS+=("$(basename "$d")"); done; fi

PASS=0; FAIL=0; SKIP=0; COST=0
summary() { echo "SKILL-EVAL: mode=$LABEL $KIND pass=$PASS fail=$FAIL skip=$SKIP cost=\$$(awk -v c="$COST" 'BEGIN{printf "%.2f", c}')"; }

if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  echo "SKIP: claude CLI 부재 (CLAUDE_BIN=$CLAUDE_BIN)"
  SKIP=${#SKILLS[@]}; summary; exit 0
fi

emit() {  # <skill> <id> <verdict> [사유]
  printf 'MODE=%s  %s  %s  %s%s\n' "$MODE" "$1" "$2" "$3" "${4:+  ($4)}"
  case "$3" in PASS) PASS=$((PASS+1)) ;; FAIL) FAIL=$((FAIL+1)) ;; *) SKIP=$((SKIP+1)) ;; esac
}

agent_body() {  # <이름> → frontmatter(첫 줄 --- ~ 다음 ---) 를 뺀 agent 본문. 파일 부재 rc 1
  local f="$AGENTS_DIR/$1.md"
  [ -f "$f" ] || return 1
  awk 'NR==1 && $0=="---"{fm=1; next} fm && $0=="---"{fm=0; next} !fm' "$f"
}

knowledge_append() {  # <케이스 json> <본문> → 본문 + 보조 지식 파일 절. 파일 부재면 그 경로를 출력하고 rc 1
  local o="$1" out="$2" k first=1
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    [ -f "$KNOW_ROOT/$k" ] || { printf '%s' "$k"; return 1; }
    if [ "$first" = 1 ]; then out="$out"$'\n\n'"## 보조 지식 파일 (평가 주입 — 실제 dispatch 에서는 에이전트가 직접 Read 한다)"; first=0; fi
    out="$out"$'\n\n'"### $k"$'\n\n'"$(cat "$KNOW_ROOT/$k")"
  done < <(printf '%s' "$o" | jq -r '.knowledge // [] | .[]')
  printf '%s' "$out"
}

ask() {  # <prompt> [agent 본문] → 전역 OUT(stream-json) · ERR(stderr 첫 줄 ≤120자) · rc 124=timeout · 3=result 없음. 질의마다 격리 sandbox(부트스트랩 안내 회피용 시드)
  local sb rc ef fx_note=""
  local -a xa=("${EXTRA[@]}")   # 이 호출 전용 사본 — 주입 플래그가 전역 EXTRA·후속 케이스·채점기로 새지 않게 한다 (EXTRA 는 항상 --max-turns 등 비어 있지 않아 bash 3.2 의 빈 배열 확장 문제 없음)
  ERR=""
  sb=$(mktemp -d) || { OUT=""; return 3; }
  # stderr 는 sandbox 밖에 받는다 — sandbox 안이면 claude 가 보는 git status 에 untracked 로 드러나 측정을 오염시킨다
  ef=$(mktemp) || ef=/dev/null
  # 픽스처는 git init **전에** 복사하고 그 .git 은 버린다 — init 뒤 cp -R 은 픽스처의 .git 을 sandbox .git 에 병합해 이력이 섞인다
  [ -d "$FIXTURE_DIR" ] && { cp -R "$FIXTURE_DIR/." "$sb/" 2>/dev/null || fx_note="픽스처 복사 실패"; rm -rf "$sb/.git"; }
  git -C "$sb" init -q; mkdir -p "$sb/.specops"; printf '# sandbox\n' > "$sb/CLAUDE.md"
  if [ -d "$FIXTURE_DIR" ]; then  # 전부 커밋 — 실패해도 판정 경로는 그대로(sandbox 는 그대로 쓴다) · 실패는 NOTE 1회로 알린다
    # 사용자 git 설정에 흔들리지 않게: ignore 규칙 전부(전역 gitignore·templateDir 의 info/exclude) 무시(add -f) · hooksPath/templateDir 훅 · 서명을 끈다
    if ! { git -C "$sb" add -Af \
        && git -C "$sb" -c user.email=eval@local -c user.name=skill-eval -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm fixture; } >/dev/null 2>&1; then
      [ -n "$fx_note" ] || fx_note="픽스처 커밋 실패"
    elif [ "$(git -C "$sb" ls-files | wc -l | tr -d ' ')" -le 1 ]; then  # CLAUDE.md 뿐 — 빈 픽스처·복사 결과 없음
      [ -n "$fx_note" ] || fx_note="픽스처가 비어 있음"
    fi
    # 근본 원인 우선(복사 실패 > 커밋 실패 > 빈 픽스처 — 앞 두 개는 if/elif 로 배타) · run 당 첫 발생 원인 1회만 알린다
    [ -z "$fx_note" ] || [ "$FIXTURE_NOTED" = 1 ] || { echo "NOTE: $fx_note — 픽스처가 온전히 반영되지 않은 sandbox 로 측정 ($FIXTURE_DIR)"; FIXTURE_NOTED=1; }
  fi
  [ -n "$ARM_EFFORT" ] && xa+=(--effort "$ARM_EFFORT")
  [ -n "$ARM_MODEL" ] && xa+=(--model "$ARM_MODEL")
  [ -n "${2:-}" ] && xa+=(--append-system-prompt "$2")
  OUT=$(eval::run_claude "$CLAUDE_BIN" "$sb" "$TIMEOUT_S" "$1" "${xa[@]}" 2>"$ef"); rc=$?
  # 첫 줄만 · ANSI 색 시퀀스 → 나머지 제어문자 제거(≥0x80 바이트 보존) · 120자 절단(UTF-8 로케일 전제 — C 로케일이면 바이트 절단)
  ERR=$(head -1 "$ef" 2>/dev/null | sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g' | LC_ALL=C tr -d '\000-\037\177'); ERR=${ERR:0:120}
  [ "$ef" = /dev/null ] || rm -f "$ef"
  rm -rf "$sb"
  COST=$(awk -v a="$COST" -v b="$(printf '%s\n' "$OUT" | eval::extract_cost)" 'BEGIN{printf "%.6f", a+b}')  # 반올림은 요약에서 1회
  return "$rc"
}

skip_reason() {  # <ask rc> [stderr 첫 줄] → SKIP 문구 (stderr 가 있으면 실행 실패 사유로 덧붙인다)
  case "$1" in 124) echo "SKIP(timeout)" ;; *) echo "SKIP(error: result 이벤트 없음 — 실행 실패)${2:+ — stderr: $2}" ;; esac
}

run_trigger() {  # <skill> <file> — 질의는 jq -c 한 줄 객체로 읽는다(@tsv 는 탭·개행·백슬래시를 이스케이프 문자열로 바꾼다)
  local s="$1" f="$2" o id q want calls rc
  while IFS= read -r o; do
    want=$(printf '%s' "$o" | jq -r .w); id=$(printf '%s' "$o" | jq -r .id); q=$(printf '%s' "$o" | jq -r .query)
    ask "$q"; rc=$?
    [ "$rc" -eq 0 ] || { emit "$s" "$id" "$(skip_reason "$rc" "$ERR")"; continue; }
    calls=$(printf '%s\n' "$OUT" | eval::all_skills)
    if [ "$want" = pos ]; then
      skill_evals::called "$s" "$calls" && emit "$s" "$id" PASS || emit "$s" "$id" FAIL "불려야 하는데 미호출"
    else
      skill_evals::called "$s" "$calls" && emit "$s" "$id" FAIL "불리면 안 되는데 호출됨" || emit "$s" "$id" PASS
    fi
  done < <(jq -c '(.should_trigger[] | {w:"pos", id, query}), (.should_not_trigger[] | {w:"neg", id, query})' "$f")
}

run_evals() {  # <skill> <file>
  local s="$1" f="$2" o id p asserts a t v verdict text rawtext cost first jerr rc ag body
  while IFS= read -r o; do
    id=$(printf '%s' "$o" | jq -r .id); p=$(printf '%s' "$o" | jq -r .prompt)
    if [ -n "$CASES_RAW" ]; then
      case ",$CASES_RAW," in *",$id,"*) CASES_N=$((CASES_N+1)); CASES_MATCHED="${CASES_MATCHED}${id}," ;; *) continue ;; esac
    fi
    ag=$(printf '%s' "$o" | jq -r '.agent // empty'); body=""
    if [ "$INJECT" = 1 ] && [ -n "$ag" ]; then
      INJ_CAND=$((INJ_CAND+1))
      if ! body=$(agent_body "$ag") || [ -z "$body" ]; then emit "$s" "$id" "SKIP(agent 부재·빈 본문: $ag)"; continue; fi
      if ! body=$(knowledge_append "$o" "$body"); then emit "$s" "$id" "SKIP(knowledge 부재: $body)"; continue; fi
      INJ_N=$((INJ_N+1))
    fi
    ask "$p" "$body"; rc=$?
    [ "$rc" -eq 0 ] || { emit "$s" "$id" "$(skip_reason "$rc" "$ERR")"; continue; }
    text=$(printf '%s\n' "$OUT" | eval::extract_text)
    rawtext=$(printf '%s\n' "$OUT" | eval::extract_text_raw)   # 채점용 — 개행 보존(코드 블록·목록이 한 줄로 뭉개지지 않게)
    cost=$(printf '%s\n' "$OUT" | eval::extract_cost)
    first=""; jerr=""
    asserts=$(printf '%s' "$o" | jq -c '.asserts[]')
    while IFS= read -r a; do
      [ -z "$a" ] && continue
      t=$(printf '%s' "$a" | jq -r .type); v=$(printf '%s' "$a" | jq -r '.value|tostring')
      if [ "$t" = cost_lt ]; then verdict=$(eval::assert cost_lt "$cost" "$v")
      elif [ "$t" = llm_rubric ]; then  # 진짜 채점기 — 서브셸 밖 직접 호출(비용·근거를 전역으로). ERROR 는 앞선 FAIL 이 없을 때만 케이스를 SKIP 한다
        eval::judge_rubric "$CLAUDE_BIN" "$rawtext" "$v" "$TIMEOUT_S" "$p"
        COST=$(awk -v a="$COST" -v b="$JUDGE_COST" 'BEGIN{printf "%.6f", a+b}')
        case "$JUDGE_VERDICT" in
          PASS) verdict=PASS ;;
          FAIL) verdict=FAIL; [ -n "$first" ] || first="llm_rubric:${JUDGE_REASON:-근거 없음}" ;;
          *) jerr="${JUDGE_REASON:-알 수 없음}"; verdict=ERROR ;;  # 뒤 단언도 계속 평가 — 결정적 FAIL 이 뒤에 있어도 놓치지 않는다
        esac
      else verdict=$(eval::assert "$t" "$text" "$v" "$CLAUDE_BIN"); fi
      [ "$verdict" = FAIL ] && [ -z "$first" ] && first="$t:$v"
    done <<EOF
$asserts
EOF
    # 채점 ERROR 는 판정 불가일 때만 SKIP — 앞선 결정적 단언이 이미 FAIL 이면 그 확정 FAIL 을 SKIP 으로 덮지 않는다
    if [ -n "$jerr" ] && [ -z "$first" ]; then emit "$s" "$id" "SKIP(error: 채점 실패 — $jerr)"; continue; fi
    [ -z "$first" ] && emit "$s" "$id" PASS || emit "$s" "$id" FAIL "첫 실패 $first${jerr:+ · 채점 실패 — $jerr}"
  done < <(jq -c '.cases[]' "$f")
}

for s in "${SKILLS[@]+"${SKILLS[@]}"}"; do
  f="$DATA_DIR/$s/$FILE"
  if [ ! -f "$f" ]; then emit "$s" - "SKIP(데이터 파일 부재: $FILE)"; continue; fi
  if ! why=$(skill_evals::check "$KIND" "$f" "$PLUGIN/skills"); then emit "$s" - "SKIP(스키마 위반: $why)"; continue; fi
  if [ "$KIND" = trigger ]; then run_trigger "$s" "$f"; else run_evals "$s" "$f"; fi
done
if [ -n "$CASES_RAW" ]; then
  _miss=""; _IFS="$IFS"; IFS=,; for _c in $CASES_RAW; do case "$CASES_MATCHED" in *",$_c,"*) ;; *) _miss="${_miss:+$_miss,}$_c" ;; esac; done; IFS="$_IFS"
  [ -z "$_miss" ] || echo "NOTE: SKILL_EVAL_CASES 에 지정한 id 가 실행 대상 skill 의 케이스에 없음: $_miss"
  [ "$CASES_N" -gt 0 ] || echo "NOTE: SKILL_EVAL_CASES 매칭 0건 — claude 를 호출하지 않았다"
  LABEL="${LABEL}+cases=$CASES_N"
fi
if [ "$INJECT" = 1 ]; then
  echo "INJECT: $INJ_N/$INJ_CAND"
  [ "$INJ_N" -gt 0 ] || echo "NOTE: SKILL_EVAL_INJECT=1 이지만 주입된 케이스 0건 — agent 필드가 있는 케이스가 없거나 전부 SKIP (--trigger 에는 적용되지 않는다)"
fi
summary
exit 0
