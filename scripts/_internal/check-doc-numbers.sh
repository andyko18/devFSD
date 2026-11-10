#!/usr/bin/env bash
# 문서의 테스트 집합 수 주장이 실측과 맞는지 검사한다 (doc-lock).
# Usage: bash scripts/_internal/check-doc-numbers.sh
#   대상 트리: $DOC_NUMBERS_ROOT (미설정 시 git rev-parse --show-toplevel)
# exit 0=위반 0 · 1=위반 존재 · 2=판정 불가(대상 트리가 git 저장소 아님/읽기 불가 · 잠금 마커 0건)
#
# 왜 트리를 인자로 받는가: 동종 checker(check-propagation.sh·check-matrix-patterns.sh)는
#   BASH_SOURCE 로 실 트리를 고정하는데, 그러면 되돌려-관찰(변이 주입)이 실 트리 쓰기가 되어
#   repo 관례(find-tree-writes.sh 탐지 대상)를 위반한다. 기본값은 cwd 기준 show-toplevel 이라
#   사용자 경험은 동종과 같다.
#
# 한계 (과대 주장 금지):
#   1. 마커 문자열이 코드 리터럴 안에 있어도 마커로 본다 — 주석 문법을 파싱하지 않는다.
#      check-matrix-patterns.sh 가 자인한 것과 같은 클래스다.
#   2. 검출 패턴은 "수치 + 단위어" 한 형태뿐이다 — 어순 반전·조사 결합·영문 표기는 못 잡는다.
#      영문은 test-doc-stamp-sync.sh AC-1 이 README·CLAUDE.md 2파일에서만 금지한다.
#   3. 경로에 콜론이 든 파일은 grep 출력 파싱이 어긋난다(현재 트리 해당 0건).
set -uo pipefail
# 로케일 고정 — 조건부(:-)가 아니다. 주변 환경의 LC_ALL 을 존중하면 한글 바이트 패턴이
#   조용히 매치를 멈출 수 있고, 그 실패는 이 검사 자신의 테스트로는 관측되지 않는다.
export LC_ALL=C.UTF-8

ROOT="${DOC_NUMBERS_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
# ★ 훅 환경 변수를 떼어낸다 — git 은 훅에 GIT_DIR 를, git commit 은 pre-commit·commit-msg 훅에
#   GIT_INDEX_FILE 까지 export 하고, run-all 은 pre-push 훅에서 돈다. 그대로 두면 cd 로 대상
#   트리에 들어가도 git ls-files 가 **실 저장소의 인덱스**를 열거해 대상 트리 스캔이 0건이 되고,
#   검사가 조용히 공허 통과한다. 3종을 모두 떼는 이유: GIT_DIR 만 떼면 GIT_INDEX_FILE 누출이
#   같은 공허 통과를 그대로 재생산한다(실측 — 오답 sandbox 가 OK rc=0). ROOT 기본값 해석
#   **뒤에** 떼므로 훅 환경에서의 저장소 자동 탐지는 그대로 유지된다.
#   이 가드의 판별력은 test-doc-numbers.sh T4.a·T4.b 가 변이 주입으로 잠근다 —
#   가드를 지운 사본은 누출 env 에서 불일치를 놓친다(rc=1 → rc=2).
#   ※ 종전 주석의 "GIT_DIR 주입 시 스위트가 PASS=2 FAIL=8" 은 **테스트 쪽에 같은 unset 이
#     생기기 전(2026-09-25 이전)** 관측이다. 지금은 테스트가 먼저 env 를 씻어 재현되지 않는다 —
#     현재형으로 읽지 말 것(이 FID 가 잡는 낡은 수치 클래스라 시점을 부기한다).
#     ※ 이 부기에서 날짜 뒤에 단위어를 붙이지 않는다 — 붙이면 "…-25 <단위어>" 가 이 검사
#       자신의 패턴에 걸려 FAIL 한다(실측: 스캔 9파일/27줄로 늘고 rc=1).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
# .git 은 디렉터리이거나(일반 클론) 파일이다(linked worktree 의 gitdir 포인터).
#   rev-parse --is-inside-work-tree 로 바꾸지 않는다 — 상위 저장소까지 걸어올라가
#   비-git 트리를 통과시키고 rc=2 가 비결정적이 된다.
{ [ -n "$ROOT" ] && { [ -d "$ROOT/.git" ] || [ -f "$ROOT/.git" ]; }; } || {
  echo "DOC-NUMBERS: FAIL 대상 트리가 git 저장소가 아니다 (ROOT='${ROOT:-}')" >&2; exit 2; }
cd "$ROOT" || exit 2

# 한글 단위어를 리터럴로 두지 않는다 — 두면 이 파일이 자기 스캔에 걸려
#   검사가 자기 자신 때문에 FAIL 한다.
SUITE_WORD=$(printf '\xec\x8a\xa4\xec\x9c\x84\xed\x8a\xb8')
RE="[0-9]{2,4}[[:space:]]*${SUITE_WORD}"

# ── 실측: run-all.sh:71-81 과 같은 수집 목록 ──────────────────────
# ★ brace 확장으로 쓰지 않는다 — 디렉터리를 중괄호로 묶어 한 줄로 적으면 닫는 괄호가
#   경로 중간에 박혀 원장 앵커(마지막 수집 디렉터리의 test- 접두)에 매치가 0 이 된다(실측).
#   ★ 그 앵커 문자열을 이 주석에 리터럴로 적지 않는다 — 적으면 아래 수집 루프를 통째로
#     지워도 주석이 앵커를 만족시켜 edge 가 green 인 채 실측값만 거짓이 된다(공허 앵커).
#   아래 리터럴 경로는 propagation edge 앵커를 겸한다 — run-all.sh 와 이 블록의
#   디렉터리 집합이 어긋나면 실측값이 거짓이 되고 잠금이 틀린 값을 강제한다.
_measure() {
  local n=1 f   # validate-structure.sh 는 무조건 1건 — run-all.sh:71 이 파일 존재를
                # 확인하지 않고 SUITES+= 한다. 검사도 동형이어야 값이 같다.
  for f in "scripts/tests/test-"*.sh \
           "scripts/tests/dag/test-"*.sh \
           "scripts/tests/governance/test-"*.sh \
           "scripts/tests/llm-eval/test-"*.sh \
           "scripts/tests/test-convention/test-"*.sh \
           "scripts/tests/freecomment/test-"*.sh \
           "scripts/tests/promote/test-"*.sh; do
    [ -f "$f" ] || continue
    n=$((n+1))
  done
  printf '%s' "$n"
}

# 경로 allowlist — 정확히 3종 (clarify Q1 확정).
#   날짜 병기는 allowlist 가 아니다 — 날짜 규칙이면 가장 낡은 값이 통과한다.
_allowlisted() {
  case "$1" in
    CHANGELOG.md)                              return 0 ;;
    docs/audit/*)                              return 0 ;;
    docs/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*) return 0 ;;
  esac
  return 1
}

MEASURED=$(_measure)
files=0 lines=0 locked=0 hist=0 fail=0
prev_path=""

# grep -H 를 쓴다 — xargs 가 마지막 배치에 파일 1개만 넘기면 -n 만으로는 파일명 접두가
#   빠져 path 자리에 줄 번호가 들어온다(대형 트리에서만 발현하는 무음 오파싱).
while IFS= read -r rec; do
  [ -n "$rec" ] || continue
  path=${rec%%:*}; rest=${rec#*:}; lno=${rest%%:*}; text=${rest#*:}
  lines=$((lines+1))
  [ "$path" = "$prev_path" ] || { files=$((files+1)); prev_path="$path"; }

  if _allowlisted "$path"; then hist=$((hist+1)); continue; fi

  case "$text" in
    *"doc-lock: historical"*) hist=$((hist+1)); continue ;;
    *"doc-lock: suite-count"*)
      locked=$((locked+1))
      # 한 줄에 수치가 2개 이상이면 첫 매치를 판정하고 나머지도 별도 FAIL 로 보고한다 —
      #   침묵하면 뒤쪽 수치가 영구 무검증이 된다.
      hits=$(printf '%s' "$text" | grep -oE "$RE" | wc -l | tr -d ' ')
      if [ "${hits:-0}" -gt 1 ]; then
        echo "DOC-NUMBERS: FAIL $path:$lno 같은 줄에 수치가 2개 이상(${hits}개) — 한 줄에 하나만 두세요" >&2
        fail=$((fail+1))
      fi
      got=$(printf '%s' "$text" | grep -oE "$RE" | head -1 | grep -oE '[0-9]{2,4}' | head -1)
      if [ "$got" != "$MEASURED" ]; then
        echo "DOC-NUMBERS: FAIL $path:$lno 기대=$MEASURED 실제=$got — 마커 줄의 수치를 $MEASURED 로 고치세요" >&2
        fail=$((fail+1))
      fi
      ;;
    *)
      echo "DOC-NUMBERS: FAIL $path:$lno 마커 없음 — 'doc-lock: suite-count' 로 잠그거나 과거 기록이면 'doc-lock: historical' 을 다세요" >&2
      fail=$((fail+1))
      ;;
  esac
#   -I: 바이너리는 건너뛴다 — GNU grep 은 "Binary file X matches" 를 stdout 에 내 파싱 루프가
#       가짜 경로로 FAIL 한다(BSD 는 무출력 — CI 가 ubuntu+macos 양쪽이라 동작 차이 씨앗).
#   ★ `xargs … grep … </dev/null` 은 **채택하지 않았다**(리뷰 Suggestion 기각). 파이프라인에서
#     그 리다이렉트는 grep 이 아니라 **xargs** 에 붙어 xargs 가 파일 목록 대신 /dev/null 을
#     읽는다 — 실측: 실 트리 스캔이 26줄에서 0줄로 떨어졌다(아래 locked=0 가드가 그 회귀를
#     rc=2 로 잡아냈다). GNU xargs 의 빈 입력 stdin 흡수는 그 가드가 이미 덮는다(tracked 0건
#     트리 → locked 0 → rc=2). 고치려면 `xargs -0 sh -c 'grep … "$@" </dev/null' _` 처럼
#     grep 쪽에 붙여야 하는데, 그건 이 한 줄의 복잡도를 그 이득보다 크게 만든다.
done < <(git ls-files -z | xargs -0 grep -IHnE -e "$RE" -- 2>/dev/null || true)

# ── 개수 잠금: 종류별 개수 마커 줄의 수치를 실측 개수와 대조한다 (20261110) ─────────────
#   마커 = "doc-lock: " + "count:" + 종류(skills·commands·agents·templates). 이 파일과 테스트는 그 문자열을
#   이어 붙인 리터럴로 두지 않는다 — 두면 tracked 되는 순간 자기 스캔에 걸린다(위 SUITE_WORD 와 같은 이유).
#   스위트 수 정규식과 **별개로** 수집한다 — 단위어가 없고 한 자리 수여도 잡힌다.
#   실측 정의는 scripts/_internal/.structure-baseline 의 glob 과 같다(validate-structure file_counts — 파일시스템 기준).
#   수치 = 주석(<!-- … -->)을 뺀 본문의 첫 정수 토큰: 앞뒤 글자가 숫자·마침표·쉼표가 아닌 1~4자리
#   (버전 문자열·천 단위 쉼표 수의 조각은 수치가 아니다). 한계: 문장 끝 마침표가 바로 붙은 수("31.")는 토큰이 아니다.
CMARK='doc-lock: ''count:'
_count_kind() {
  local n=0 f
  case "$1" in
    skills)    set -- skills/*/SKILL.md ;;
    commands)  set -- commands/*.md ;;
    agents)    set -- agents/*.md ;;
    templates) set -- templates/*.md ;;
    *) return 1 ;;
  esac
  for f in "$@"; do [ -f "$f" ] && n=$((n+1)); done
  printf '%s' "$n"
}
clocked=0
while IFS= read -r rec; do
  [ -n "$rec" ] || continue
  path=${rec%%:*}; rest=${rec#*:}; lno=${rest%%:*}; text=${rest#*:}
  if _allowlisted "$path"; then hist=$((hist+1)); continue; fi
  clocked=$((clocked+1))
  nmark=$(printf '%s' "$text" | grep -oF -e "$CMARK" | wc -l | tr -d ' ')
  if [ "${nmark:-0}" -gt 1 ]; then
    echo "DOC-NUMBERS: FAIL $path:$lno 같은 줄에 개수 마커가 ${nmark}개 — 한 줄에 하나만 두세요" >&2
    fail=$((fail+1)); continue
  fi
  kind=${text#*"$CMARK"}; kind=$(printf '%s' "$kind" | sed -E 's/^([a-z]*).*$/\1/')
  want=$(_count_kind "$kind") || {
    echo "DOC-NUMBERS: FAIL $path:$lno 모르는 개수 종류 '${kind}' — skills·commands·agents·templates 중 하나" >&2
    fail=$((fail+1)); continue; }
  body=$(printf '%s' "$text" | sed -E 's/<!--[^>]*-->//g')
  got=$(printf '%s' "$body" | grep -oE '(^|[^0-9.,])[0-9]{1,4}([^0-9.,]|$)' | head -1 | grep -oE '[0-9]+' | head -1)
  if [ -z "$got" ]; then
    echo "DOC-NUMBERS: FAIL $path:$lno 개수 마커 줄에 수치가 없다 (종류 $kind · 기대=$want)" >&2
    fail=$((fail+1)); continue
  fi
  if [ "$got" != "$want" ]; then
    echo "DOC-NUMBERS: FAIL $path:$lno 종류 $kind 기대=$want 실제=$got — 마커 줄의 수치를 $want 로 고치세요" >&2
    fail=$((fail+1))
  fi
done < <(git ls-files -z | xargs -0 grep -IHnF -e "$CMARK" -- 2>/dev/null || true)
locked=$((locked+clocked))

if [ "$fail" -gt 0 ]; then
  echo "DOC-NUMBERS: FAIL 위반 ${fail}건 (스캔 ${files}파일/${lines}줄)" >&2
  exit 1
fi
# 도달 가드 — 잠금 마커가 0건이면 이 검사는 아무것도 대조하지 않았다. 그 상태를 OK 로 내면
#   판정 불가가 통과로 위장된다(실측 3경로: GIT_DIR 누출 · GIT_INDEX_FILE 누출 · tracked 0건 트리
#   — 전부 "스캔 0파일/0줄 · locked 0" 로 rc=0 을 냈다). 위반 판정(fail>0)보다 **뒤에** 둔다:
#   미마커 위반만 있는 트리는 판정 불가가 아니라 위반이므로 rc=1 을 유지해야 한다.
#   FAIL 문면에 suite-count 를 유지한다 — 실측값은 이 경로에서도 산출되며, 값을 숨기면
#   단독 실행자가 "몇을 기대하는지" 를 못 본다.
if [ "$locked" -eq 0 ]; then
  echo "DOC-NUMBERS: FAIL 잠금 마커 0건 — 판정 불가 (suite-count=$MEASURED · 스캔 ${files}파일/${lines}줄 · historical $hist)" >&2
  exit 2
fi
echo "DOC-NUMBERS: OK (suite-count=$MEASURED · 스캔 ${files}파일/${lines}줄 · locked $locked · historical $hist)"
