#!/usr/bin/env bash
# find-tree-writes.sh — 스위트의 숨은 실 트리 쓰기 탐지 (수동 도구 · run-all 비포함)
# 사용: bash scripts/tests/find-tree-writes.sh [--root <repo>] [-j <N>] [스위트 경로...]
#   스위트 경로 생략 시 scripts/tests 아래 test-*.sh 전부(fixtures 제외) + scripts/_internal/validate-structure.sh.
# 출력: 확정 `WRITE-ATTEMPT <스위트>: <메시지>` · 검토 `REVIEW <스위트>: <메시지>`(상대경로 — 사람이 판정)
#       끝에 `TREE-WRITES: 확정 <n>건 · 검토 <m>건 · 스위트 <k>/<검사수>`
# rc: 0=확정·검토 모두 0 · 1=하나라도 있음 · 2=사용법 오류/사본 실패/쓰기 금지 무력(root 등)
#
# 왜 (FID 20260911-run-all-parallel): #39 가 "실 트리에 쓰는 스위트 0" 을 선언했으나 병렬 실행에서
#   2건(skill-size-ratchet T4 · run-all-glob-completeness T3)이 드러났다. 수기 grep 은 **범주**를 놓친다 —
#   tracked 변이만 봤고 신규 파일 생성·변수 경유 경로는 못 봤다. 여기서는 grep 대신 **쓰기 금지 사본**에서
#   실제로 돌려 운영체제가 거부한 지점을 모은다. 상대경로 쓰기(cwd=루트)도 같이 잡힌다.
# 한계: 스위트가 쓰기 실패를 `2>/dev/null` 로 삼키면 메시지가 없어 못 잡는다 — 그 경우 스위트 결과 변화로만 드러난다.
#   사본에는 .git 이 없어 git 을 쓰는 스위트는 다른 이유로 실패할 수 있다(보고 대상은 쓰기 거부 메시지뿐).
#   스위트 이름에 ':' 가 있으면 요약의 스위트 수가 어긋날 수 있다(보고 줄 자체는 온전).
set -uo pipefail
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ROOT="$PLUGIN"; JOBS=4; LIST=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root|-j) [ $# -ge 2 ] || { echo "사용법 오류: $1 값 필요" >&2; exit 2; }
      if [ "$1" = -j ]; then JOBS=$2; else ROOT=$2; fi; shift 2 ;;
    -h|--help) sed -n '2,6p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) LIST+=("$1"); shift ;;
  esac
done
case "$JOBS" in ''|*[!0-9]*|0*) echo "사용법 오류: -j 는 1 이상 정수" >&2; exit 2 ;; esac
# shellcheck source=/dev/null
. "$PLUGIN/scripts/tests/lib/isolated-tree.sh" 2>/dev/null
command -v iso::make_tree >/dev/null 2>&1 || { echo "FATAL: isolated-tree 미로드" >&2; exit 2; }
C=$(iso::make_tree "$ROOT") || { echo "FATAL: 사본 생성 실패 ($ROOT)" >&2; exit 2; }
W=$(mktemp -d) || { rm -rf "$C"; exit 2; }
# 쓰기 금지 사본은 그대로 rm 이 안 된다 — 권한을 되돌린 뒤 지운다
trap 'chmod -R u+w "$C" 2>/dev/null; rm -rf "$C" "$W"' EXIT
# 없는 스위트를 넘기면 "0건" 이 안전처럼 보인다 — 검사 전에 사용법 오류로 끊는다.
#   기준은 **실행 지점인 사본**이다 — 사본은 git 추적 파일만 담아, 방금 쓴 미추적 스위트는 원본엔 있고 사본엔 없다
for s in ${LIST[@]+"${LIST[@]}"}; do
  [ -f "$C/$s" ] || { echo "사용법 오류: 사본에 없는 스위트(없거나 git 추적 전 — git add 필요) — $s" >&2; exit 2; }
done

# 목록은 NUL 구분 — 개행 구분이면 xargs 가 공백·따옴표 이름에서 abort 해 그 스위트를 **무음 스킵**한다
if [ ${#LIST[@]} -eq 0 ]; then
  ( cd "$C" && { printf '%s\0' scripts/_internal/validate-structure.sh
                 find scripts/tests -name 'test-*.sh' -not -path '*/fixtures/*' -print0 | sort -z; } ) > "$W/list"
else
  printf '%s\0' "${LIST[@]}" > "$W/list"
fi
chmod -R a-w "$C"
# 쓰기 금지가 쓰기를 막지 못하면(root·ACL 등) 모든 스위트가 "0건" 으로 나온다 — 0건으로 위장하지 않고 판정 불가로 끝낸다
if ( : > "$C/.ftw-probe" ) 2>/dev/null; then
  rm -f "$C/.ftw-probe"
  echo "판정 불가: 쓰기 금지 사본이 쓰기를 막지 못한다(root·ACL 등) — 이 환경에서는 실 트리 쓰기를 탐지할 수 없다" >&2
  exit 2
fi

read -r -d '' _FTW_ONE <<'ONE'
c=$1; w=$2; s=$3
key="k_$(printf '%s' "$s" | tr '/' '_')"   # 접두 — ./ 입력이 점파일(._…)이 되면 아래 *.hit glob 이 못 본다
( cd "$c" && SPECOPS_RUN_ALL=1 SPECOPS_SAST_EXTERNAL=0 bash "$s" ) > "$w/$key.out" 2>&1 < /dev/null
# 같은 거부가 루프에서 수십 번 반복된다 — 사본 경로를 가리고 중복을 접는다(/private 실경로 형태도 같은 사본)
grep -E 'Permission denied|Read-only file system|Operation not permitted' "$w/$key.out" \
  | sed -e "s#/private$c#{사본}#g" -e "s#$c#{사본}#g" | sort -u > "$w/$key.all"
# 분류 — 쓰기 금지 속성은 스위트가 만든 **자기 임시 사본**(tar·cp 가 모드를 보존)에도 번진다(전수 실측 628건).
#   확정: 거부 대상이 탐지기 사본 경로  → 실 트리 쓰기
#   검토: 거부 대상에 절대경로가 없음  → cwd 기준 상대경로 쓰기(cwd 가 루트면 실 트리, 스위트가 cd 했으면 오탐)
#   무시: 그 밖의 절대경로            → 스위트 자신의 임시 사본
#   보고 줄은 printf 로 붙인다 — sed 치환에 이름을 넣으면 '#' 같은 문자가 구분자와 충돌해 그 스위트가 빠진다
grep -F '{사본}' "$w/$key.all" | while IFS= read -r l; do printf 'WRITE-ATTEMPT %s: %s\n' "$s" "$l"; done > "$w/$key.hit"
grep -vF '{사본}' "$w/$key.all" | grep -vE "(^|[ :'\"])/" | while IFS= read -r l; do printf 'REVIEW %s: %s\n' "$s" "$l"; done > "$w/$key.rev"
exit 0
ONE
xargs -0 -n 1 -P "$JOBS" bash -c "$_FTW_ONE" _ "$C" "$W" < "$W/list"

n_scan=$(tr -cd '\0' < "$W/list" | wc -c | tr -d ' ')
cat "$W"/*.hit "$W"/*.rev 2>/dev/null
n_hit=$(cat "$W"/*.hit 2>/dev/null | wc -l | tr -d ' ')
n_rev=$(cat "$W"/*.rev 2>/dev/null | wc -l | tr -d ' ')
n_suite=$(cat "$W"/*.hit "$W"/*.rev 2>/dev/null | sed -E 's/^(WRITE-ATTEMPT|REVIEW) ([^:]+):.*/\2/' | sort -u | grep -c . || true)
echo "TREE-WRITES: 확정 ${n_hit}건 · 검토 ${n_rev}건 · 스위트 ${n_suite}/${n_scan}"
[ "$n_hit" -eq 0 ] && [ "$n_rev" -eq 0 ]
