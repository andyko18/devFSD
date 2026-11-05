#!/usr/bin/env bash
# dev-decision.sh — 개발 구간에서 묻지 않고 정한 결정의 기록·끝 보고 (20261008-dev-no-ask)
# Usage:
#   dev-decision.sh add  <FID> <종류> "<결정>" ["<근거>"]
#   dev-decision.sh show <FID> [--backlog]
# 종류: fixed(리뷰 지적을 이번 FID 에서 고침) · backlog(다음 작업으로 넘김) · order(순서·진행 방식 선택)
#       retry(한도 초과 뒤 자동 재시도) · skip(게이트·단계 건너뜀) · approval(사전 일괄 승인 받은 작업)
# Exit: 0 = 기록·출력 완료(0건 포함) · 1 = 사용 오류·쓰기 거부
#
# 왜 스크립트인가: 개발 구간(구현 ~ PR 게이트 직전)에서는 사용자에게 묻지 않고 기본값으로 진행한다
#   (skills/implementing-ko/dev-autonomy.md). 그 대가로 사용자가 무엇이 대신 정해졌는지 보는 지점은
#   PR 게이트의 끝 보고 하나다. 기록이 모델 재량이면 빠진 결정은 영영 보이지 않는다 —
#   기록 형식(1건 = 1줄)과 출력(전 줄 + 건수)을 고정해 과소보고를 막는다.
set -u

KINDS="fixed backlog order retry skip approval"
KIND_RE="fixed|backlog|order|retry|skip|approval"
# worktree 에서 불러도 FID 기록이 메인에만 있으면 메인을 쓴다 (SPECOPS_ROOT 만 내보낸다 — 아래 세 갈래가 그대로 받는다)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_internal/specops-root.sh" 2>/dev/null && specops_root_export "${2:-}"
# 하위 디렉터리에서 불러도 repo 의 .specops 를 찾는다 (SPECOPS_ROOT 가 있으면 그것이 우선)
if [ -n "${SPECOPS_ROOT:-}" ]; then SPECOPS="$SPECOPS_ROOT"
elif [ -d .specops ]; then SPECOPS=".specops"
else _top=$(git rev-parse --show-toplevel 2>/dev/null || true); SPECOPS="${_top:+$_top/}.specops"; fi

die() { echo "dev-decision: $*" >&2; exit 1; }

cmd="${1:-}"; fid="${2:-}"
case "$cmd" in add|show) ;; *) die "usage: $0 add <FID> <종류> \"<결정>\" [\"<근거>\"] | show <FID> [--backlog]" ;; esac
printf '%s' "$fid" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || die "invalid FID: $fid"

dir="$SPECOPS/$fid"
file="$dir/dev-decisions.md"
[ -d "$dir" ] || die "FID 디렉터리 부재: $dir"
[ ! -L "$SPECOPS" ] && [ ! -L "$dir" ] && [ ! -L "$file" ] || die "symlink 거부: $file"

# 한 줄로 접는다 — 기록 1건이 여러 줄이 되면 끝 보고의 건수가 틀어지고, 줄머리 `- ` 로 가짜 기록을 끼울 수 있다.
oneline() { printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ //' -e 's/ $//'; }

if [ "$cmd" = add ]; then
  [ "$#" -le 5 ] || die "인자가 너무 많다 — 결정·근거는 각각 따옴표로 묶는다"
  kind="${3:-}"; decision=$(oneline "${4:-}"); reason=$(oneline "${5:-}")
  case " $KINDS " in *" $kind "*) ;; *) die "종류는 다음 중 하나: $KINDS (받은 값: ${kind:-없음})" ;; esac
  [ -n "$decision" ] || die "결정 내용이 비어 있다"
  if [ ! -f "$file" ]; then
    printf '# 개발 중 결정 — %s\n\n> 개발 구간에서 **묻지 않고** 정한 것. PR 게이트에서 사용자에게 보여 준다 (dev-decision.sh 가 기록 — 손으로 고치지 않는다).\n\n' "$fid" > "$file" \
      || die "쓰기 실패: $file"
  fi
  printf -- '- %s [%s] %s%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$kind" "$decision" "${reason:+ — $reason}" >> "$file" \
    || die "쓰기 실패: $file"
  exit 0
fi

# show
case "${3:-}" in ""|--backlog) ;; *) die "알 수 없는 옵션: $3 (show <FID> [--backlog])" ;; esac
[ "$#" -le 3 ] || die "인자가 너무 많다"
# 이 스크립트가 쓴 형식(시각 + 허용 종류)의 줄만 기록으로 센다 — 건수와 종류별 요약이 어긋나지 않게.
lines=""
[ -f "$file" ] && lines=$(grep -E "^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z \[($KIND_RE)\] " "$file" || true)
if [ "${3:-}" = "--backlog" ]; then
  [ -n "$lines" ] && printf '%s\n' "$lines" | grep -E '^- [^ ]+ \[backlog\] ' || true
  exit 0
fi
n=0; [ -n "$lines" ] && n=$(printf '%s\n' "$lines" | grep -c .)
printf '## 개발 중 결정 %s건 — %s\n\n' "$n" "$fid"
if [ "$n" = 0 ]; then
  echo "(없음 — 개발 구간에서 묻지 않고 정한 것이 기록되지 않았다)"
  exit 0
fi
summary=""
for k in $KINDS; do
  c=$(printf '%s\n' "$lines" | grep -cE "^- [^ ]+ \[$k\] " || true)
  [ "$c" -gt 0 ] && summary="${summary}${summary:+ · }$k $c"
done
printf '%s\n\n%s\n' "$summary" "$lines"
