#!/usr/bin/env bash
# prepush-related.sh — 작업 브랜치 push 를 전체 스위트 대신 관련 스위트로 판정한다 (20261113 speed)
#
# Usage: prepush-related.sh   (cwd = repo 안 · stdin = pre-push 가 받은 ref 줄 그대로: <local ref> <local sha> <remote ref> <remote sha>)
# Exit:  0 = 관련 스위트 통과(또는 같은 트리의 통과 기록) — push 허용
#        1 = 관련 스위트 실패 — push 차단
#        3 = 이 경로로 판정하지 않는다 — 호출자(.githooks/pre-push)가 전체 스위트를 돈다. 사유는 stderr 1줄.
#
# 왜: 전체 스위트는 1회 약 6분이고 `/basic` 기계 시간의 절반이었다(20261113 실측 — 11.8분 중 6.2분). 작업 브랜치는
#   PR 의 CI `run-all` 통과가 머지 필수(브랜치 보호 20261010)라 push 전의 전체 실행은 그 검사와 겹친다.
# 대가: CI 는 리눅스다. 맥 전체 스위트(`run-all-macos`)는 main 에 들어간 뒤에만 돈다 — 이 경로를 타면 관련 스위트 밖의
#   맥 전용 결함은 머지 뒤에 발견된다. 발행 전에는 release.sh pre-flight 가 로컬 전체 스위트를 돈다.
# **애매하면 전체다**(rc 3): 기본 브랜치로 push · 브랜치가 아닌 ref(태그) · push 하는 커밋이 체크아웃된 HEAD 가 아님 ·
#   추적 파일에 커밋하지 않은 변경(스위트는 작업 트리에서 돈다) · origin 의 기본 브랜치를 모름 · 기본 브랜치와 차이 없음 ·
#   관련 스위트를 고를 수 없음(run-related.sh --list rc≠0 — 상한 초과 포함) · SPECOPS_FORCE_FULL(값 무관, 비어 있지 않음).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES

_full() { echo "▶ pre-push: $1 — 전체 스위트로 판정합니다." >&2; exit 3; }

[ -z "${SPECOPS_FORCE_FULL:-}" ] || _full "SPECOPS_FORCE_FULL 지정"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || _full "git 저장소가 아님"
cd "$ROOT" 2>/dev/null || _full "저장소 루트로 이동 실패"
RR="scripts/tests/run-related.sh"
[ -f "$RR" ] || _full "run-related.sh 부재"

base=""
for _r in refs/remotes/origin/main refs/remotes/origin/master; do
  git show-ref --verify --quiet "$_r" && { base="$_r"; break; }
done
[ -n "$base" ] || _full "origin 의 기본 브랜치를 모름"
head_sha=$(git rev-parse -q --verify HEAD 2>/dev/null) || _full "HEAD 없음"

n=0
while read -r _lref lsha rref _rsha; do
  [ -n "${lsha:-}" ] || continue
  case "$lsha" in *[!0]*) ;; *) continue ;; esac   # all-zero = 삭제
  case "${rref:-}" in
    refs/heads/main|refs/heads/master) _full "기본 브랜치로 push" ;;
    refs/heads/*) ;;
    *) _full "브랜치가 아닌 ref push(${rref:-?})" ;;
  esac
  [ "$lsha" = "$head_sha" ] || _full "push 하는 커밋이 체크아웃된 HEAD 가 아님"
  n=$((n + 1))
done
[ "$n" -ge 1 ] || _full "보낼 브랜치 없음"

_st=$(git status --porcelain --untracked-files=no 2>/dev/null) || _full "git status 실패"
[ -z "$_st" ] || _full "추적 파일에 커밋하지 않은 변경"

mb=$(git merge-base "$base" "$head_sha" 2>/dev/null) || _full "기본 브랜치와 공통 조상 없음"
files=$(git diff --name-only "$mb" "$head_sha" 2>/dev/null) || _full "변경 파일 목록 실패"
[ -n "$files" ] || _full "기본 브랜치와 차이 없음"

_err=$(mktemp 2>/dev/null) || _full "임시 파일 생성 실패"
trap 'rm -f "$_err"' EXIT
list=$(printf '%s\n' "$files" | bash "$RR" --list 2>"$_err") || _full "관련 스위트를 고를 수 없음($(head -1 "$_err" 2>/dev/null))"
[ -n "$list" ] || _full "관련 스위트 목록이 비었음"
cnt=$(printf '%s\n' "$list" | awk 'END { print NR }')

# 같은 트리에서 이 스위트들이 이미 통과했으면 다시 돌지 않는다 — 기록은 run-related.sh 가 전부 통과했을 때만 쓴다.
#   지문 산출 불가(NO_GIT·UNHASHABLE·헬퍼 부재)는 기록을 믿지 않고 그냥 돈다.
MARK="$ROOT/${SPECOPS_ROOT:-.specops}/.related-suite-pass"
VS_LIB="scripts/_internal/verification-state.sh"
if [ -f "$MARK" ] && [ -f "$VS_LIB" ]; then
  # shellcheck source=/dev/null
  now=$( { . "$VS_LIB" && vs::nondoc_fingerprint; } 2>/dev/null ) || now=""
  if [ -n "$now" ] && [ "$now" != "NO_GIT" ] && [ "$now" != "UNHASHABLE" ] && [ "$(head -1 "$MARK" 2>/dev/null)" = "$now" ]; then
    miss=$(printf '%s\n' "$list" | grep -Fxv -f <(sed 1d "$MARK" 2>/dev/null) || true)
    if [ -z "$miss" ]; then
      cat >&2 <<EOF
▶ pre-push: 같은 트리에서 관련 스위트 ${cnt}개가 이미 통과해 건너뜁니다. 전체 스위트는 PR 의 CI(run-all)가 봅니다.
  전체로 강제: SPECOPS_FORCE_FULL=1 git push
EOF
      exit 0
    fi
  fi
fi

echo "▶ pre-push: 작업 브랜치 — 관련 스위트 ${cnt}개 실행 중 (전체 스위트는 PR 의 CI 가 봅니다)…" >&2
# shellcheck disable=SC2086  # 목록은 공백 없는 repo 상대 경로다(run-related.sh --list 출력)
out=$(bash "$RR" $list 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  cat >&2 <<EOF
✋ push 차단 — 관련 스위트 실패
$(printf '%s' "$out" | grep -E '^(FAILED|====|FAIL)' | head -20)

재현: bash $RR $(printf '%s' "$list" | tr '\n' ' ')
의도적으로 넘기려면(주권): git push --no-verify
EOF
  exit 1
fi
printf '%s\n' "$out" | tail -1 >&2
echo "  전체로 강제: SPECOPS_FORCE_FULL=1 git push" >&2
exit 0
