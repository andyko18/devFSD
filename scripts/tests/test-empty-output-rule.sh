#!/usr/bin/env bash
# test-empty-output-rule.sh — 빈 출력 오진 방지 규칙 정적 잠금 (FID 20261003-empty-output-rule · AC-1~AC-7)
#
# 계기: 출력 필터가 `ps` 출력을 삼키자 서브에이전트가 "죽었다"고 오진해 포그라운드 재실행을 걸었고, 그 재실행이 사본 삭제와
#   겹쳐 무효값 39/6 이 나왔다(유효값 45/0 — 2026-09-06). 빈 출력은 부재의 증거가 아니다. 규칙은 verifying-evidence-ko 에
#   한 번 정의하고(`## 빈 출력 규칙`), tools: 에 Bash 가 있는 에이전트 정의마다 같은 요지 절을 둬 위임 때마다 자동 적용한다.
#
# 한계: 문구의 존재·위치·길이·도구 중립만 잠근다. 모델이 규칙을 실제로 따르는지는 잠글 수 없다(수동 llm-eval 몫).
# 단언 원칙: 모든 양성 단언은 음성 대조 사본(T7)이 짝으로 걸려 검사가 헛돌지 않음을 보인다. 사본은 mktemp 안에서만 만든다.
# NFR-3 시계·세션 독립: 정적 파일 읽기와 fixture 사본만 쓴다 — 시각·CLAUDE_CODE_SESSION_ID·실 ~/.claude 를 읽지 않는다
#   (T8 이 자기 자신을 적대 환경에서 재실행해 출력 동일을 잠근다).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SELF="$PLUGIN/scripts/tests/test-empty-output-rule.sh"
SKILL="$PLUGIN/skills/verifying-evidence-ko/SKILL.md"
AGDIR="$PLUGIN/agents"
SH="${BASH:-bash}"
SB=$(mktemp -d) || { echo "FATAL: mktemp 실패" >&2; exit 1; }
trap 'rm -rf "$SB"' EXIT
[ -f "$SKILL" ] || { echo "FATAL: verifying-evidence-ko SKILL.md 부재" >&2; exit 1; }

H='## 빈 출력 규칙'
LABEL='[검증 불가 — 출력 비어 있음]'
# 필터 없는 경로는 파이프 선두만 보호하지 않는다 — 출력 필터가 파이프 후단 명령을 재작성하므로 "각 단계" 를 요구한다(Phase C Important 1)
PIPE='파이프라인이면 각 단계'
# 현재 Bash 보유 에이전트 8개 — 도출 목록이 이걸 포함하는지만 본다(도출이 공회전해 0개를 돌려주는 것을 막는 하한)
KNOWN="auditor-ko blue-team-ko code-reviewer-ko design-reviewer-ko implementer-ko plan-reviewer-ko red-team-ko spec-reviewer-ko"
EVAL7="auditor-ko blue-team-ko code-reviewer-ko design-reviewer-ko plan-reviewer-ko red-team-ko spec-reviewer-ko"

# ── helpers ──────────────────────────────────────────────────────────
# "## 이름" 으로 시작하는 절을 다음 "## " 직전까지 뽑는다(제목 포함)
sec() { awk -v h="$2" 'index($0, h) == 1 { on = 1; print; next } /^## / { on = 0 } on' "$1"; }
# 텍스트에 리터럴이 있나 → y/n
has() { if printf '%s\n' "$1" | grep -qF -- "$2"; then printf y; else printf n; fi; }
# 모든 리터럴을 한 줄에 함께 가진 줄이 있나 → y/n  (lha <텍스트> <리터럴>...)
lha() {
  local cur="$1" n; shift
  for n in "$@"; do
    cur=$(printf '%s\n' "$cur" | grep -F -- "$n")
    [ -n "$cur" ] || { printf n; return; }
  done
  printf y
}
# 파일 literal 첫 1회 치환 사본. 대상이 없으면 NOOP 으로 FAIL — 헛도는 음성 대조 금지 (awk 3종 공통: 전체를 한 레코드로)
mk() { # <src> <dst> <old> <new>
  OLD="$3" NEW="$4" awk 'BEGIN { RS = "\001"; ORS = ""; old = ENVIRON["OLD"]; new = ENVIRON["NEW"] }
    { i = index($0, old); if (i == 0) { miss = 1; print $0; next } print substr($0, 1, i - 1) new substr($0, i + length(old)) }
    END { exit miss }' "$1" > "$2" || { nope "NOOP: ${2##*/}" "치환 대상 없음 — $3"; return 1; }
}
dropsec() { awk -v h="$2" 'index($0, h) == 1 { skip = 1; next } /^## / { skip = 0 } !skip' "$1" > "$3"; }
fm_of() { awk 'NR == 1 && $0 == "---" { on = 1; next } on && $0 == "---" { exit } on' "$1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else nope "$1" "기대='$3' 실제='$2'"; fi; }
# "name=value ..." 토큰열에서 기대값과 다른 이름들 (cnt·pre 는 1, 나머지는 y 가 기대)
bad() {
  local out="" t k v
  for t in $1; do
    k=${t%%=*}; v=${t#*=}
    case "$k" in cnt|pre) [ "$v" = 1 ] || out="$out $k" ;; *) [ "$v" = y ] || out="$out $k" ;; esac
  done
  printf '%s' "${out# }"
}
cnt_pre() { grep -c -- '^## 빈 출력 규칙' "$1" || true; }
cnt_ex() { grep -cx -- '## 빈 출력 규칙' "$1" || true; }
# 절 길이: 제목 포함 비공백 줄 수와 물리 줄 수(끝 공백 줄 제외)가 둘 다 상한 이하인가
len_ok() { # <절 텍스트> <상한>
  local nb ph
  nb=$(printf '%s\n' "$1" | grep -c '[^[:space:]]'); ph=$(printf '%s\n' "$1" | wc -l | tr -d ' ')
  if [ "$nb" -le "$2" ] && [ "$ph" -le "$2" ]; then printf y; else printf n; fi
}
has_ps() { printf '%s\n' "$1" | grep -qE '(^|[^A-Za-z0-9_])ps([^A-Za-z0-9_]|$)'; }
has_3906() { printf '%s\n' "$1" | grep -qE '(^|[^0-9])39/6([^0-9]|$)'; }
has_4500() { printf '%s\n' "$1" | grep -qE '(^|[^0-9])45/0([^0-9]|$)'; }

# ── verifying-evidence-ko 절 플래그 ──────────────────────────────────
# 6요소 + 러너(6번째 적용 대상) + 가공 계층 — 길이·개수·rtk 표기는 뺀 "내용" 플래그
skill_core() { # <file>
  local t; t=$(sec "$1" "$H")
  printf 'e1=%s layer=%s a1=%s a2=%s a3=%s a4=%s a5=%s run=%s rc1=%s rc2=%s rc3=%s pipe=%s lab=%s nc=%s act=%s case=%s' \
    "$(has "$t" '증거가 아니다')" \
    "$(lha "$t" '증거가 아니다' '필터 훅' '파이프' '2>/dev/null' '부재와 구별되지 않는다')" \
    "$(lha "$t" '적용 대상' '프로세스 생존')" "$(lha "$t" '적용 대상' '파일/경로 존재')" "$(lha "$t" '적용 대상' '건수')" \
    "$(lha "$t" '적용 대상' '변경 유무')" "$(lha "$t" '적용 대상' '로그 부재')" \
    "$(lha "$t" '적용 대상' '러너' '아무것도 출력하지 않' '0건' '통과가 아니라 미실행' 'NOT_RUN')" \
    "$(lha "$t" '재확인 수단' '종료 코드')" "$(lha "$t" '재확인 수단' '필터 없는 경로')" "$(lha "$t" '재확인 수단' '교차 확인')" \
    "$(lha "$t" '재확인 수단' '필터 없는 경로' "$PIPE")" \
    "$(has "$t" "$LABEL")" "$(lha "$t" "$LABEL" '결론을 내리지 않는다')" \
    "$(lha "$t" '행동' '재확인 전' '재실행' '삭제' '재시도' '하지 않는다')" \
    "$(lha "$t" '사례' '`ps`' '`39/6`' '`45/0`' '2026-09-06')"
}
# rtk 줄: 모두 "예:" 표기·필수 전제 어휘 없음 / 재확인 수단 줄에 rtk 없음 / rtk 를 지워도 내용 플래그 전부 성립
skill_rtk() { # <file>
  local t rl mark rcfree free one; t=$(sec "$1" "$H")
  rl=$(printf '%s\n' "$t" | grep -i 'rtk' || true)
  mark=y
  if [ -n "$rl" ]; then
    # 모든 rtk 줄이 "예:" 를 갖고, 필수 전제 어휘(반드시·필수·항상·해야)가 없다
    [ "$(printf '%s\n' "$rl" | grep -vc '예:')" = 0 ] || mark=n
    printf '%s\n' "$rl" | grep -qE '반드시|필수|항상|해야' && mark=n
  fi
  rcfree=y
  printf '%s\n' "$t" | grep '재확인 수단' | grep -qi 'rtk' && rcfree=n
  sed 's/rtk proxy/proxy/g; s/rtk//g' "$1" > "$SB/rtkfree.$$.md"
  free=y
  [ "$(skill_core "$SB/rtkfree.$$.md" | tr ' ' '\n' | grep -c '=n')" = 0 ] || free=n
  rm -f "$SB/rtkfree.$$.md"
  # rtk 는 사례 줄 단 1곳에서만 등장한다(clarify Q3) — 다른 줄에 "예:" 만 붙여 rtk 를 끌어들이는 우회를 막는다
  one=n; [ -n "$rl" ] && [ "$(printf '%s\n' "$rl" | wc -l | tr -d ' ')" = 1 ] && [ "$(lha "$rl" '사례' '2026-09-06')" = y ] && one=y
  printf 'rtkmark=%s rtk1=%s rcfree=%s rtkfree=%s rtkex=%s' "$mark" "$one" "$rcfree" "$free" "$(lha "$t" '사례' '예: rtk 훅')"
}
skill_flags() { # <file> — 전체(내용 + 개수 + 길이 + rtk)
  local t; t=$(sec "$1" "$H")
  printf 'cnt=%s pre=%s len=%s %s %s' "$(cnt_ex "$1")" "$(cnt_pre "$1")" "$(len_ok "$t" 16)" "$(skill_core "$1")" "$(skill_rtk "$1")"
}
# 합리화 차단표: 헤더·전 행 2열·새 행·행 수·절 개수·discipline marker
table_flags() { # <file>
  local rows t hdr two new n disc one
  t=$(sec "$1" '## 합리화 차단표'); rows=$(printf '%s\n' "$t" | grep '^|' || true)
  hdr=n; [ "$(printf '%s\n' "$rows" | sed -n 1p)" = '| 변명 | 실제 |' ] && hdr=y
  two=y; [ -n "$rows" ] && [ "$(printf '%s\n' "$rows" | grep -vcE '^\|[^|]+\|[^|]+\|$')" = 0 ] || two=n
  new=$(printf '%s\n' "$rows" | awk -F'|' 'NF == 4 && index($2, "출력이 비었으니") && index($3, "구별되지 않는다") && index($3, "재확인") { f = 1 } END { print f ? "y" : "n" }')
  n=$(printf '%s\n' "$rows" | grep -c '^|[^-]' || true); n=$((n - 1))   # 헤더 제외 데이터 행 수(구분선은 -로 시작해 위 패턴에서 빠진다)
  one=$(grep -c -- '^## 합리화 차단표' "$1" || true)
  disc=$(fm_of "$1" | grep -qx 'discipline: true' && echo y || echo n)
  printf 'hdr=%s two=%s new=%s rows=%s one=%s disc=%s' "$hdr" "$two" "$new" "$([ "$n" -ge 9 ] && echo y || echo n)" "$([ "$one" = 1 ] && echo y || echo n)" "$disc"
}

# ── 에이전트 ─────────────────────────────────────────────────────────
# frontmatter tools: 에 Bash 가 있는 에이전트(파일명 stem). tools: 줄이 없거나 `*` 면 전체 도구 상속이라 Bash 를 갖는다.
bash_agents() { # <dir>
  local f fm tl nm
  for f in "$1"/*.md; do
    [ -f "$f" ] || continue
    fm=$(fm_of "$f"); tl=$(printf '%s\n' "$fm" | grep '^tools:' | head -1 || true)
    nm=$(basename "$f" .md)
    if [ -z "$tl" ] || printf '%s' "$tl" | grep -qE '^tools:[[:space:]]*\*[[:space:]]*$'; then echo "$nm"
    elif printf '%s' "$tl" | grep -qE '(^|[^A-Za-z0-9_])Bash([^A-Za-z0-9_]|$)'; then echo "$nm"
    elif printf '%s' "$tl" | grep -qE '^tools:[[:space:]]*$' && printf '%s\n' "$fm" | grep -qE '^[[:space:]]*-[[:space:]]*Bash[[:space:]]*$'; then echo "$nm"
    fi
  done
}
agent_flags() { # <file>
  local t np; t=$(sec "$1" "$H")
  np=y; { has_ps "$t" || has_3906 "$t" || has_4500 "$t"; } && np=n
  printf 'cnt=%s pre=%s len=%s ev=%s rc1=%s rc2=%s rc3=%s pipe=%s lab=%s act=%s ref=%s nocase=%s nortk=%s' \
    "$(cnt_ex "$1")" "$(cnt_pre "$1")" "$(len_ok "$t" 8)" \
    "$(has "$t" '증거가 아니다')" "$(has "$t" '종료 코드')" "$(has "$t" '필터 없는 경로')" "$(has "$t" '교차 확인')" \
    "$(lha "$t" '필터 없는 경로' "$PIPE")" "$(has "$t" "$LABEL")" "$(lha "$t" '재실행' '삭제' '재시도' '바꾸지 않는다' '재확인')" "$(has "$t" 'verifying-evidence-ko')" \
    "$np" "$(printf '%s\n' "$t" | grep -qi 'rtk' && echo n || echo y)"
}
# 디렉터리의 Bash 보유 에이전트 각각의 위반 플래그 → "name:flag ..." (빈 문자열 = 전부 정상)
agents_verdict() { # <dir>
  local nm b out=""
  for nm in $(bash_agents "$1"); do
    b=$(bad "$(agent_flags "$1/$nm.md")")
    for f in $b; do out="$out $nm:$f"; done
  done
  printf '%s' "${out# }"
}
# 불변식 플래그 — frontmatter 무결·name·model·tools·평가자 쓰기 도구 박탈·절이 frontmatter 밖(절이 없으면 y — 부재는 T4 가 잡는다)
inv_flags() { # <file>
  local f="$1" fm first close hl base tl evl wr
  first=$(sed -n 1p "$f"); close=$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$f"); hl=$(awk 'index($0, "## 빈 출력 규칙") == 1 { print NR; exit }' "$f")
  fm=$(fm_of "$f"); base=$(basename "$f" .md); tl=$(printf '%s\n' "$fm" | grep '^tools:' | head -1 || true)
  evl=$(printf '%s\n' "$fm" | grep -qx 'role: evaluator' && echo 1 || echo 0)
  wr=y; if [ "$evl" = 1 ] && printf '%s' "$tl" | grep -qE 'Write|Edit|NotebookEdit'; then wr=n; fi
  printf 'fm=%s name=%s model=%s tools=%s nowrite=%s infm=%s' \
    "$([ "$first" = '---' ] && [ -n "$close" ] && echo y || echo n)" \
    "$(printf '%s\n' "$fm" | grep -qx "name: $base" && echo y || echo n)" \
    "$(printf '%s\n' "$fm" | grep -q '^model:' && echo y || echo n)" \
    "$([ -n "$tl" ] && echo y || echo n)" "$wr" \
    "$([ -z "$hl" ] && echo y || { [ -n "$close" ] && [ "$hl" -gt "$close" ] && echo y || echo n; })"
}
role_flags() { # <file> <기대 evaluator 여부 1|0>
  local evl; evl=$(fm_of "$1" | grep -qx 'role: evaluator' && echo 1 || echo 0)
  [ "$evl" = "$2" ] && echo y || echo n
}
# SubagentStop 저장 계약(spec=B·code=C): 절 1개·<<<REVIEW fid=·phase=·<<<END>>>
contract_flags() { # <file> <B|C>
  local t; t=$(sec "$1" '## 최종 메시지 형식')
  printf 'one=%s mk=%s ph=%s end=%s nohole=%s' "$([ "$(grep -c -- '^## 최종 메시지 형식' "$1" || true)" = 1 ] && echo y || echo n)" \
    "$(has "$t" '<<<REVIEW fid=')" "$(has "$t" "phase=$2")" "$(has "$t" '<<<END>>>')" \
    "$([ "$(printf '%s\n' "$t" | grep -c '^## 빈 출력 규칙' || true)" = 0 ] && echo y || echo n)"
}

# ══ T1 (AC-1): verifying-evidence-ko 의 빈 출력 규칙 절이 핵심 6요소를 갖는다 ══
SF=$(skill_flags "$SKILL"); ST=$(sec "$SKILL" "$H")
eq "T1.a 절이 정확히 1개(제목 줄 정확 일치 1 · 접두 일치 1)" "$(printf '%s' "$SF" | tr ' ' '\n' | grep -E '^(cnt|pre)=' | tr '\n' ' ')" "cnt=1 pre=1 "
eq "T1.b 절 길이 ≤16줄(제목 포함 비공백 줄·물리 줄 둘 다)" "$(len_ok "$ST" 16)" "y"
eq "T1.c ① 빈 출력은 증거가 아니다 + 가공 계층(필터 훅·파이프·2>/dev/null)이 부재와 구별되지 않는다" "$(bad "$SF" | tr ' ' '\n' | grep -E '^(e1|layer)$' | tr '\n' ' ')" ""
eq "T1.d ② 적용 대상 5종(프로세스 생존·파일/경로 존재·건수·변경 유무·로그 부재)이 모두 적용 대상 줄에 있다" "$(bad "$SF" | tr ' ' '\n' | grep -E '^a[1-5]$' | tr '\n' ' ')" ""
eq "T1.e ③ 재확인 수단 3종(종료 코드·필터 없는 경로·교차 확인)" "$(bad "$SF" | tr ' ' '\n' | grep -E '^rc[1-3]$' | tr '\n' ' ')" ""
eq "T1.f ④ 라벨 $LABEL 정확 표기 + 결론을 내리지 않는다" "$(bad "$SF" | tr ' ' '\n' | grep -E '^(lab|nc)$' | tr '\n' ' ')" ""
eq "T1.g ⑤ 재확인 전 행동 변경 금지(재실행·삭제·재시도)" "$(bad "$SF" | tr ' ' '\n' | grep -E '^act$' | tr '\n' ' ')" ""
eq "T1.h ⑥ 사례 1줄에 2026-09-06 · ps · 39/6 · 45/0" "$(bad "$SF" | tr ' ' '\n' | grep -E '^case$' | tr '\n' ' ')" ""
eq "T1.j ③' 필터 없는 경로는 파이프라인이면 각 단계에 적용(재확인 수단 줄 — 후단 명령 재작성 대비)" "$(bad "$SF" | tr ' ' '\n' | grep -E '^pipe$' | tr '\n' ' ')" ""
eq "T1.i 절이 ## 다음 skill 터미널 블록보다 앞에 있다(chain 말미를 밀어내지 않는다)" \
   "$([ "$(awk -v h="$H" 'index($0, h) == 1 { print NR; exit }' "$SKILL")" -lt "$(awk 'index($0, "## 다음 skill") == 1 { print NR; exit }' "$SKILL")" ] && echo y || echo n)" "y"

# ══ T2 (AC-7): 러너 빈 출력은 통과가 아니라 미실행 · 에이전트 절에는 사례가 없다 ══
eq "T2.a verifying 절 적용 대상 6번째 — 러너가 아무것도 출력하지 않거나 0건 → 통과가 아니라 미실행(NOT_RUN) (같은 적용 대상 줄)" "$(bad "$SF" | tr ' ' '\n' | grep -E '^run$' | tr '\n' ' ')" ""
eq "T2.b 사례 줄에 \"예: rtk 훅\" 표기(clarify Q3 결정)" "$(bad "$SF" | tr ' ' '\n' | grep -E '^rtkex$' | tr '\n' ' ')" ""

# ══ T3 (AC-2): 합리화 차단표 — 빈 출력 변명 행 + 표 형식 유지 ══
TF=$(table_flags "$SKILL")
eq "T3.a 차단표 헤더 | 변명 | 실제 | · 모든 행 2열 · 절 1개 · discipline: true 유지" "$(bad "$TF" | tr ' ' '\n' | grep -E '^(hdr|two|one|disc)$' | tr '\n' ' ')" ""
eq "T3.b 빈 출력 변명 행(\"출력이 비었으니 …\" ↔ \"구별되지 않는다 … 재확인\") + 데이터 행 ≥9(기존 8 + 신규 1)" "$(bad "$TF" | tr ' ' '\n' | grep -E '^(new|rows)$' | tr '\n' ' ')" ""

# ══ T4 (AC-3): Bash 보유 에이전트 모두 빈 출력 규칙 절을 갖는다(목록은 frontmatter 에서 도출) ══
DERIVED=$(bash_agents "$AGDIR" | tr '\n' ' ')
miss=""; for a in $KNOWN; do case " $DERIVED" in *" $a "*) ;; *) miss="$miss $a" ;; esac; done
eq "T4.a frontmatter 도출 목록이 알려진 8개를 모두 포함한다(도출 공회전 방지 · 신규 Bash 에이전트는 아래 T4.b~T4.g 가 자동 편입)" "${miss# }" ""
for a in $(bash_agents "$AGDIR"); do
  AFL=$(agent_flags "$AGDIR/$a.md"); AB=$(bad "$AFL")
  eq "T4.b $a: 절 정확히 1개" "$(printf '%s' "$AB" | tr ' ' '\n' | grep -E '^(cnt|pre)$' | tr '\n' ' ')" ""
  eq "T4.c $a: 절 길이 ≤8줄(제목 포함)" "$(printf '%s' "$AB" | tr ' ' '\n' | grep -E '^len$' | tr '\n' ' ')" ""
  eq "T4.d $a: 핵심 요지 — 증거가 아니다 · 재확인 수단 3종 · $LABEL · 재확인 전 행동 변경 금지 · verifying-evidence-ko 참조" "$(printf '%s' "$AB" | tr ' ' '\n' | grep -E '^(ev|rc1|rc2|rc3|lab|act|ref)$' | tr '\n' ' ')" ""
  eq "T4.h $a: 필터 없는 경로는 파이프라인이면 각 단계에 적용(같은 줄)" "$(printf '%s' "$AB" | tr ' ' '\n' | grep -E '^pipe$' | tr '\n' ' ')" ""
  eq "T4.e $a: 에이전트 절에는 사례(ps · 39/6 · 45/0)가 없다(AC-7)" "$(printf '%s' "$AB" | tr ' ' '\n' | grep -E '^nocase$' | tr '\n' ' ')" ""
  eq "T4.f $a: 에이전트 절에 rtk 언급이 없다(도구 중립)" "$(printf '%s' "$AB" | tr ' ' '\n' | grep -E '^nortk$' | tr '\n' ' ')" ""
done
# 8개 문구는 한 정규 문구에서 파생 — 절 본문이 서로 같다(드리프트 방지)
UNIQ=$(for a in $(bash_agents "$AGDIR"); do sec "$AGDIR/$a.md" "$H" | cksum; done | sort -u | wc -l | tr -d ' ')
set -- $(bash_agents "$AGDIR")   # 첫 에이전트 이름 — head -1 파이프는 bash_agents 쪽에 SIGPIPE 를 남기므로 쓰지 않는다
FIRSTSEC=$(sec "$AGDIR/${1:-none}.md" "$H")
eq "T4.g 에이전트 절 본문이 전부 비어 있지 않고 서로 동일하다(정규 문구 1종에서 파생)" "$UNIQ|$([ -n "$FIRSTSEC" ] && echo y || echo n)" "1|y"

# ══ T5 (AC-4): 도구 중립 ══
eq "T5.a verifying 절의 rtk 줄은 사례 줄 단 1곳이고(2026-09-06 사례) 전부 \"예:\" 표기이며 필수 전제 어휘(반드시·필수·항상·해야)가 없다" "$(bad "$SF" | tr ' ' '\n' | grep -E '^(rtkmark|rtk1)$' | tr '\n' ' ')" ""
eq "T5.b 재확인 수단 줄에는 rtk 가 없다" "$(bad "$SF" | tr ' ' '\n' | grep -E '^rcfree$' | tr '\n' ' ')" ""
eq "T5.c rtk 를 전부 지워도 6요소(+러너·라벨·행동·사례)가 그대로 성립한다" "$(bad "$SF" | tr ' ' '\n' | grep -E '^rtkfree$' | tr '\n' ' ')" ""

# ══ T6 (AC-5): 기존 평가자 계약 불변 ══
for a in $(bash_agents "$AGDIR"); do
  eq "T6.a $a: frontmatter 무결(--- 쌍·name=파일명·model·tools) · 평가자 쓰기 도구 박탈 · 절이 frontmatter 밖" "$(bad "$(inv_flags "$AGDIR/$a.md")")" ""
done
ev=""; for a in $EVAL7; do [ "$(role_flags "$AGDIR/$a.md" 1)" = y ] || ev="$ev $a"; done
eq "T6.b 평가자 7개는 role: evaluator 유지, implementer-ko 는 평가자가 아니다" "${ev# }|$(role_flags "$AGDIR/implementer-ko.md" 0)" "|y"
eq "T6.c spec-reviewer-ko SubagentStop 저장 계약(<<<REVIEW fid= · phase=B · <<<END>>>)이 그대로이고 절 안에 빈 출력 규칙이 끼지 않는다" "$(bad "$(contract_flags "$AGDIR/spec-reviewer-ko.md" B)")" ""
eq "T6.d code-reviewer-ko SubagentStop 저장 계약(<<<REVIEW fid= · phase=C · <<<END>>>)이 그대로이고 절 안에 빈 출력 규칙이 끼지 않는다" "$(bad "$(contract_flags "$AGDIR/code-reviewer-ko.md" C)")" ""

# ══ T7 (AC-6): 음성 대조 — 검사가 헛돌지 않는다. 각 사본은 의도한 플래그만 뒤집는다 ══
N="$SB/neg"; mkdir -p "$N"
CR="$AGDIR/code-reviewer-ko.md"
# --- verifying 절 ---
dropsec "$SKILL" "$H" "$N/s-del.md"
eq "T7.a 절을 지운 사본 → 개수 0 + 6요소 전부 사라진다(절 삭제가 걸린다)" "$([ "$(cnt_ex "$N/s-del.md")" = 0 ] && echo y || echo n)|$(skill_core "$N/s-del.md" | tr ' ' '\n' | grep -c '=y')" "y|0"
mk "$SKILL" "$N/s-phrase.md" '증거가 아니다' '증거일 수 있다' && \
eq "T7.b 핵심 구를 바꾼 사본(증거가 아니다 → 증거일 수 있다) → e1·layer 만 걸린다(rtk 를 지워도 성립 검사는 e1 도 잡는다)" "$(bad "$(skill_flags "$N/s-phrase.md")")" "e1 layer rtkfree"
mk "$SKILL" "$N/s-label.md" "$LABEL" '[미확인]' && \
eq "T7.c 라벨을 바꾼 사본 → lab·nc 가 걸린다" "$(bad "$(skill_flags "$N/s-label.md")")" "lab nc rtkfree"
mk "$SKILL" "$N/s-run.md" '⑥ 테스트·검증 러너가 아무것도 출력하지 않거나 0건을 실행한 것 — 통과가 아니라 미실행(`NOT_RUN`)이다.' '⑥ 기타.' && \
eq "T7.d 러너 적용 대상(6번째)을 지운 사본 → run 만 걸린다(rtk 를 지워도 성립 검사는 run 도 잡는다)" "$(bad "$(skill_flags "$N/s-run.md")")" "run rtkfree"
mk "$SKILL" "$N/s-case.md" '(유효값 `45/0`)' '' && \
eq "T7.e 사례에서 45/0 을 지운 사본 → case 가 걸린다" "$(bad "$(skill_flags "$N/s-case.md")")" "case rtkfree"
FILL=$(printf '%s\n' '- 군더더기 1' '- 군더더기 2' '- 군더더기 3' '- 군더더기 4' '- 군더더기 5' '- 군더더기 6' '- 군더더기 7' '- 군더더기 8')
mk "$SKILL" "$N/s-long.md" '- **행동 금지**' "${FILL}
- **행동 금지**" && \
eq "T7.f 상한(16줄)을 넘긴 사본 → len 이 걸린다" "$(bad "$(skill_flags "$N/s-long.md")")" "len"
{ cat "$SKILL"; printf '\n'; sec "$SKILL" "$H"; } > "$N/s-dup.md"
eq "T7.g 절이 두 번 있는 사본 → cnt·pre·len 이 걸린다" "$(bad "$(skill_flags "$N/s-dup.md")" | tr ' ' '\n' | grep -E '^(cnt|pre|len)$' | tr '\n' ' ')" "cnt pre len "
mk "$SKILL" "$N/s-req.md" '필터 없는 경로(절대경로 바이너리·환경이 제공하는 raw 실행 수단 — 파이프라인이면 각 단계 모두; 출력 필터는 파이프 후단 명령도 재작성하므로 선두만으론 부족하다. 파이프 없이 단계별로 따로 실행해 중간 출력을 봐도 된다)' '`rtk proxy <cmd>` 를 반드시 쓴다' && \
eq "T7.h rtk 를 필수 전제로 쓴 사본(재확인 수단을 rtk proxy 로 대체) → rc2·pipe·rtkmark·rtk1·rcfree·rtkfree 가 걸린다" "$(bad "$(skill_flags "$N/s-req.md")")" "rc2 pipe rtkmark rtk1 rcfree rtkfree"
mk "$SKILL" "$N/s-unmark.md" '사례**(2026-09-06): 예: rtk 훅이' '사례**(2026-09-06): rtk 훅이' && \
eq "T7.i rtk 사례의 \"예:\" 표기를 지운 사본 → rtkmark·rtkex 가 걸린다" "$(bad "$(skill_flags "$N/s-unmark.md")")" "rtkmark rtkex"
mk "$SKILL" "$N/s-tbl3.md" '| "부분 검사로 충분" | 부분은 아무것도 증명 못 함 |' '| "부분 검사로 충분" | 부분은 아무것도 증명 못 함 |
| "x" | y | z |' && \
eq "T7.j 차단표에 3열 행을 끼운 사본 → two 가 걸린다" "$(bad "$(table_flags "$N/s-tbl3.md")")" "two"
grep -vF '출력이 비었으니' "$SKILL" > "$N/s-norow.md"
eq "T7.k 빈 출력 변명 행을 지운 사본 → new·rows 가 걸린다" "$(bad "$(table_flags "$N/s-norow.md")")" "new rows"
mk "$SKILL" "$N/s-noend.md" ' — **재확인** |' ' — **재확인**' && \
eq "T7.l 새 행의 닫는 파이프가 빠진 사본 → two 가 걸린다" "$(bad "$(table_flags "$N/s-noend.md")")" "two new"
mk "$SKILL" "$N/s-rtk2.md" '- **행동 금지**' '- 예: 재확인은 `rtk proxy` 로만 한다.
- **행동 금지**' && \
eq "T7.x rtk 를 별도 줄에 \"예:\" 만 붙여 끌어들인 사본 → rtk1 이 걸린다(어휘 검사로는 못 잡는 우회 — 사례 줄 단 1곳 잠금)" "$(bad "$(skill_flags "$N/s-rtk2.md")")" "rtk1"
mk "$SKILL" "$N/s-pipe.md" "$PIPE" '파이프라인이면 선두' && \
eq "T7.z 파이프라인 각 단계 구를 선두로 바꾼 사본 → pipe 가 걸린다(rtk 를 지워도 성립 검사는 pipe 도 잡는다)" "$(bad "$(skill_flags "$N/s-pipe.md")")" "pipe rtkfree"
# --- 에이전트 절 ---
dropsec "$CR" "$H" "$N/a-del.md"
eq "T7.m 에이전트 1개의 절을 지운 사본 → cnt·pre·핵심 요지 전부 걸린다" "$(bad "$(agent_flags "$N/a-del.md")")" "cnt pre ev rc1 rc2 rc3 pipe lab act ref"
# 원본이 읽기 전용(a-w)인 트리에서도 돈다 — cp 는 모드를 따라가 사본이 읽기 전용이면 덮어쓰기가 거부되므로 사본 디렉터리를 쓰기 가능으로 만든다
cpag() { mkdir -p "$1"; cp "$AGDIR"/*.md "$1/" && chmod u+w "$1"/*.md; }
cpag "$N/ag-one"; cp "$N/a-del.md" "$N/ag-one/code-reviewer-ko.md"
eq "T7.n 디렉터리 판정 — 에이전트 1개 누락 사본은 그 에이전트만 걸린다(나머지 7개는 통과)" "$(agents_verdict "$N/ag-one" | tr ' ' '\n' | sed 's/:.*//' | sort -u | tr '\n' ' ')" "code-reviewer-ko "
# code-reviewer-ko 는 증거 규칙 절에도 "증거가 아니다" 가 있어 빈 출력 절 고유 앞뒤("실패 없음"의 …)로 앵커한다
mk "$CR" "$N/a-phrase.md" '"실패 없음"의 증거가 아니다' '"실패 없음"의 증거일 수 있다' && \
eq "T7.o 에이전트 핵심 구를 바꾼 사본 → ev 가 걸린다" "$(bad "$(agent_flags "$N/a-phrase.md")")" "ev"
mk "$CR" "$N/a-case.md" '- 정본:' '- 사례: `ps` 가 비어 39/6 대신 45/0 이었다.
- 정본:' && \
eq "T7.p 에이전트 절에 사례(ps·39/6·45/0)를 넣은 사본 → nocase 만 걸린다(1줄 추가는 8줄 한도 이내라 len 은 그대로 — 사례 금지는 길이와 독립)" "$(bad "$(agent_flags "$N/a-case.md")")" "nocase"
mk "$CR" "$N/a-rtk.md" '(절대경로 바이너리' '(절대경로 바이너리·rtk proxy' && \
eq "T7.q 에이전트 절에 rtk 를 언급한 사본 → nortk 가 걸린다" "$(bad "$(agent_flags "$N/a-rtk.md")")" "nortk"
mk "$CR" "$N/a-pipe.md" "$PIPE" '파이프라인이면 선두' && \
eq "T7.aa 에이전트 절의 파이프라인 각 단계 구를 선두로 바꾼 사본 → pipe 만 걸린다" "$(bad "$(agent_flags "$N/a-pipe.md")")" "pipe"
mk "$CR" "$N/a-long.md" '- 정본:' '- 군더더기 1
- 군더더기 2
- 정본:' && \
eq "T7.r 에이전트 절이 8줄을 넘긴 사본 → len 이 걸린다" "$(bad "$(agent_flags "$N/a-long.md")")" "len"
mk "$CR" "$N/a-noact.md" ' — 재확인이 먼저다' '' && \
eq "T7.y 에이전트 절에서 \"재확인이 먼저다\" 를 지운 사본 → act 가 걸린다(행동 변경 금지의 이유 구)" "$(bad "$(agent_flags "$N/a-noact.md")")" "act"
mk "$CR" "$N/a-noref.md" '- 정본: `verifying-evidence-ko` 의 `## 빈 출력 규칙`.' '- 정본: 없음.' && \
eq "T7.s verifying-evidence-ko 참조를 지운 사본 → ref 가 걸린다" "$(bad "$(agent_flags "$N/a-noref.md")")" "ref"
# --- 도출: 새 Bash 에이전트가 절 없이 추가되면 걸린다 ---
cpag "$N/ag-new"
printf -- '---\nname: zz-new-bash-ko\ndescription: fixture\ntools: Read, Grep, Bash\n---\n\n본문.\n' > "$N/ag-new/zz-new-bash-ko.md"
printf -- '---\nname: zz-new-readonly-ko\ndescription: fixture\ntools: Read, Grep\n---\n\n본문.\n' > "$N/ag-new/zz-new-readonly-ko.md"
printf -- '---\nname: zz-new-inherit-ko\ndescription: fixture\n---\n\n본문.\n' > "$N/ag-new/zz-new-inherit-ko.md"
NV=$(agents_verdict "$N/ag-new" | tr ' ' '\n' | sed 's/:.*//' | sort -u | tr '\n' ' ')
eq "T7.t 새 에이전트 fixture — Bash 보유(tools: …, Bash)·tools 줄 없음(전체 상속)은 절이 없어 걸리고, Bash 없는 에이전트는 걸리지 않는다" "$NV" "zz-new-bash-ko zz-new-inherit-ko "
# --- 평가자 계약 ---
mkdir -p "$N/c-write" "$N/c-infm"   # inv_flags 는 name: 이 파일명과 같은지도 보므로 사본을 원래 파일명으로 둔다
mk "$AGDIR/spec-reviewer-ko.md" "$N/c-write/spec-reviewer-ko.md" 'tools: Read, Grep, Glob, Bash' 'tools: Read, Write, Grep, Glob, Bash' && \
eq "T7.u 평가자에게 Write 를 준 사본 → nowrite 가 걸린다" "$(bad "$(inv_flags "$N/c-write/spec-reviewer-ko.md")")" "nowrite"
sed 's/<<<END>>>/<<<FIN>>>/g' "$CR" > "$N/c-end.md"   # 마커가 여러 곳에 있어 전부 바꾼다(첫 1회 치환으론 절 안의 마커가 남는다)
eq "T7.v 저장 계약 종료 마커를 바꾼 사본 → end 가 걸린다(사본이 실제로 달라졌는지도 확인)" "$(cmp -s "$CR" "$N/c-end.md" && echo same || echo diff)|$(bad "$(contract_flags "$N/c-end.md" C)")" "diff|end"
mk "$AGDIR/red-team-ko.md" "$N/c-infm/red-team-ko.md" 'tools: Read, Grep, Glob, Bash' 'tools: Read, Grep, Glob, Bash
## 빈 출력 규칙' && \
eq "T7.w 절 제목이 frontmatter 안으로 들어간 사본 → infm 이 걸린다" "$(bad "$(inv_flags "$N/c-infm/red-team-ko.md")")" "infm"

# ══ T8 (NFR-3): 시계·세션 독립 — 적대 환경(가짜 date·세션 ID·빈 HOME)에서 자기 자신을 재실행해 출력이 같다 ══
if [ -z "${SPECOPS_EO_INNER:-}" ]; then
  mkdir -p "$SB/shim" "$SB/home"
  printf '#!/bin/sh\necho "2026-12-31T15:59:59Z"\nexit 97\n' > "$SB/shim/date"; chmod +x "$SB/shim/date"
  SHIM_RC=$(PATH="$SB/shim:$PATH" date >/dev/null 2>&1; echo $?)
  eq "T8.a (사전) date shim 이 실제로 가로챈다 — rc 97(헛도는 스윕 방지)" "$SHIM_RC" "97"
  # 내부 재실행은 stdout(결과 줄)만 비교한다 — CI 러너는 SIGPIPE 를 무시해 조기 종료 파이프(`printf | grep -q`)가 stderr 로
  #   `printf: write error: Broken pipe` 를 흘리고(타이밍 의존·경로 길이만큼 길어짐) 그 잡음이 cksum 에 섞여 간헐 실패했다(20261004).
  #   환경 의존성은 결과 줄(stdout)로 드러나고, 내부 실행이 깨지면 T8.d(BASE 종결 줄 FAIL=0)가 잡는다.
  BASE=$(SPECOPS_EO_INNER=1 "$SH" "$SELF" 2>/dev/null)
  HOST=$(SPECOPS_EO_INNER=1 PATH="$SB/shim:$PATH" CLAUDE_CODE_SESSION_ID="hostile-T15-session" HOME="$SB/home" "$SH" "$SELF" 2>/dev/null)
  BARE=$(SPECOPS_EO_INNER=1 env -u CLAUDE_CODE_SESSION_ID HOME="$SB/home" "$SH" "$SELF" 2>/dev/null)
  eq "T8.b 가짜 date(UTC 15시·rc 97)·세션 ID 설정·빈 HOME 에서 재실행해도 출력이 동일하다" "$(printf '%s' "$HOST" | cksum)" "$(printf '%s' "$BASE" | cksum)"
  eq "T8.c 세션 ID 미설정·빈 HOME 에서도 출력이 동일하다" "$(printf '%s' "$BARE" | cksum)" "$(printf '%s' "$BASE" | cksum)"
  eq "T8.d 재실행 결과가 FAIL 0 으로 끝난다(동일하게 실패한 것이 아니다)" "$(printf '%s\n' "$BASE" | tail -1 | grep -c ' FAIL=0$')" "1"
fi

finish
