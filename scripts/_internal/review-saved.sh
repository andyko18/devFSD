#!/usr/bin/env bash
# review-saved.sh — 리뷰 보고서가 이번 dispatch 뒤 저장됐는지 판정한다 (부모 fallback 중복 저장 방지 · 20261023-speed-l1-single)
# Usage: review-saved.sh mark <FID> <B|C>
#        review-saved.sh check <FID> <B|C> <tid>...
# mark : .specops/<FID>/reviews/.dispatched-<phase> 표지를 만든다(B/C dispatch 직전).
# check: tid 마다 reviews/<tid>-<phase>-report.md 가 표지보다 새것이면 rc 0 · 하나라도 없거나 낡았으면 rc 1 + 빠진 tid 를 한 줄씩.
#        표지가 없으면 rc 1 + 전 tid. 인자 오류·FID 디렉터리 없음 rc 2. 파일을 지우거나 고치지 않는다.
# 기준 디렉터리: SPECOPS_ROOT = `.specops` 디렉터리 자체(저장소 관례 — 기본 `.specops`). bash 3.2 의 -nt 는 초 단위 비교다(같은 초면 낡은 것으로 본다 — 안전 방향).
set -u
die() { echo "review-saved: $1" >&2; exit 2; }
cmd=${1:-}; fid=${2:-}; phase=${3:-}
case "$cmd" in mark|check) ;; *) die "usage: $0 mark <FID> <B|C> | check <FID> <B|C> <tid>..." ;; esac
[[ "$fid" =~ ^[0-9]{8}-[a-z0-9-]+$ ]] || die "FID 형식 오류: ${fid:-없음}"
case "$phase" in B|C) ;; *) die "phase 는 B 또는 C: ${phase:-없음}" ;; esac
dir="${SPECOPS_ROOT:-.specops}/$fid"
[ -d "$dir" ] || die "FID 디렉터리 없음: $dir"
rev="$dir/reviews"; marker="$rev/.dispatched-$phase"
if [ "$cmd" = mark ]; then
  mkdir -p "$rev" 2>/dev/null || die "reviews 디렉터리 생성 실패"
  : > "$marker" 2>/dev/null || die "표지 생성 실패"
  exit 0
fi
shift 3
[ $# -gt 0 ] || die "tid 가 없다"
missing=""
for tid in "$@"; do
  [[ "$tid" =~ ^T[0-9]+$ ]] || die "tid 형식 오류: $tid"
  f="$rev/$tid-$phase-report.md"
  if [ ! -f "$marker" ] || [ ! -f "$f" ] || [ ! "$f" -nt "$marker" ]; then missing="$missing $tid"; fi
done
[ -z "$missing" ] && exit 0
for tid in $missing; do echo "$tid"; done
exit 1
