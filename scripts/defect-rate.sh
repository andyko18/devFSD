#!/usr/bin/env bash
# defect-rate.sh — FID 별 "머지 후 N일 안 결함 fix" 수를 git 기록만으로 집계한다 (읽기 전용 관측)
# Usage: bash scripts/defect-rate.sh [--repo DIR] [--base REF] [--window-days N] [--since YYYYMMDD]
# rc: 0 = 집계 성공(대상 0건이어도 원인을 표시) · 2 = git 저장소 아님·base 없음·얕은 복제·잘못된 인자
#
# FID = base 의 first-parent 머지 중 제목이 "from <owner>/<prefix>/<YYYYMMDD-slug>" 꼴인 것 (머지^1..머지^2 가 그 FID 의 커밋).
# fix = base 에서 닿는 머지 아닌 커밋 중 제목이 fix: · fix(…) · fix! 로 시작하는 것.
# 귀속: fix 가 지우거나 바꾼 줄(테스트·CHANGELOG·.specops 제외)을 부모 시점에서 git blame 해 그 줄을 마지막으로 쓴 커밋의 FID 에 1건.
#   머지(committer 시각) 초과 ~ 머지+N일 이하만. 기준 시각 = base 끝 커밋의 committer 시각(벽시계 아님 — 같은 base 면 같은 결과).
# 근사치다: 줄을 추가만 하는 fix 는 귀속되지 않고, fix 규약을 안 지킨 수정은 세지 않는다.
set -u
export LC_ALL=C

REPO="."; BASE=""; WIN=30; SINCE=0

die() { echo "defect-rate: $1" >&2; exit 2; }
need_val() { [ "$#" -ge 2 ] && [ -n "${2:-}" ] || die "$1 값 필요"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) need_val "$@"; REPO="$2"; shift 2 ;;
    --base) need_val "$@"; BASE="$2"; shift 2 ;;
    --window-days)
      need_val "$@"
      printf '%s' "$2" | grep -qE '^[1-9][0-9]{0,2}$' && [ "$2" -le 365 ] || die "--window-days 는 1~365 정수여야 합니다: $2"
      WIN="$2"; shift 2 ;;
    --since)
      need_val "$@"
      printf '%s' "$2" | grep -qE '^[0-9]{8}$' || die "--since 는 YYYYMMDD 여야 합니다: $2"
      SINCE="$2"; shift 2 ;;
    *) die "알 수 없는 인자: $1" ;;
  esac
done

G() { git -C "$REPO" "$@"; }
G rev-parse --git-dir >/dev/null 2>&1 || die "git 저장소가 아닙니다: $REPO"
[ "$(G rev-parse --is-shallow-repository 2>/dev/null)" = "true" ] && die "얕은 복제입니다 — blame 이 틀려지므로 git fetch --unshallow 후 다시 실행하세요"
if [ -z "$BASE" ]; then
  for c in origin/main main; do G rev-parse --verify -q "$c^{commit}" >/dev/null 2>&1 && { BASE="$c"; break; }; done
  [ -n "$BASE" ] || die "base 를 찾지 못했습니다 (origin/main·main 없음) — --base 로 지정하세요"
else
  G rev-parse --verify -q "$BASE^{commit}" >/dev/null 2>&1 || die "base 가 없습니다: $BASE"
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/defect-rate.XXXXXX") || die "임시 폴더를 만들 수 없습니다"
trap 'rm -rf "$TMP"' EXIT
SECS=$((WIN * 86400))
NOW=$(G log -1 --format=%ct "$BASE")
BASE_SHA=$(G rev-parse --short=8 "$BASE")
# 결함 집계에서 뺄 경로 (전체 경로 기준) — 테스트 보강·기록 정리는 결함이 아니다
EXCL='(^|/)(tests?|__tests__)/|(^|/)(test[-_][^/]*|[^/]*\.test\.[^/]*|[^/]*\.spec\.[^/]*)$|(^|/)CHANGELOG[^/]*$|^\.specops/'

# ── 1. FID 머지 → 커밋·코드변경 여부 ─────────────────────────────────────────
: > "$TMP/c2f"; : > "$TMP/merges"; UNREC=0
while IFS='|' read -r h ct day subj; do
  fid=$(printf '%s' "$subj" | sed -nE 's#.* from [^/ ]+/[A-Za-z0-9._-]+/([0-9]{8}-[^ ]+).*#\1#p')
  if [ -z "$fid" ]; then UNREC=$((UNREC + 1)); continue; fi
  G rev-list "$h^1..$h^2" 2>/dev/null | sed "s/\$/ $fid $ct/" >> "$TMP/c2f"
  code=$(G diff --name-only "$h^1" "$h" 2>/dev/null | grep -vcE "$EXCL")
  echo "$fid $ct $day $code" >> "$TMP/merges"
done < <(G log --merges --first-parent "$BASE" --date=short --format='%H|%ct|%cd|%s')

# ── 2. fix 커밋 → 고친 줄의 마지막 작성 커밋 → FID ───────────────────────────
: > "$TMP/hits"; UNATTR=0; BLAMEFAIL=0
while IFS=' ' read -r fh fct; do
  G rev-parse --verify -q "$fh^" >/dev/null 2>&1 || continue
  G diff -U0 --no-renames "$fh^" "$fh" 2>/dev/null | awk '
    /^diff --git /{hdr=1; o=""; next}
    hdr && /^--- /{o=substr($0,7); if ($0=="--- /dev/null") o=""; next}
    /^@@/{ hdr=0; if (o=="") next; split($2,a,","); s=substr(a[1],2); n=(a[2]==""?1:a[2]); if (n>0) print o "\t" s "\t" s+n-1 }' |
  cat > "$TMP/hunks"
  : > "$TMP/blamed"
  # 파일마다 blame 1회 (-L 여러 개) — hunk 마다 부르면 외부 프로세스가 곱으로 늘어난다
  prev=""; largs=()
  flush() {
    [ -n "$prev" ] || return 0
    G blame --porcelain "${largs[@]}" "$fh^" -- "$prev" 2>/dev/null | grep -E '^[0-9a-f]{40} ' | cut -d' ' -f1 >> "$TMP/blamed"
    [ "${PIPESTATUS[0]}" -eq 0 ] || BLAMEFAIL=$((BLAMEFAIL + 1))
  }
  while IFS=$'\t' read -r file a b; do
    [ -n "$file" ] || continue
    printf '%s' "$file" | grep -qE "$EXCL" && continue
    if [ "$file" != "$prev" ]; then flush; prev="$file"; largs=(); fi
    largs+=(-L "$a,$b")
  done < <(sort -t$'\t' -k1,1 -s "$TMP/hunks")
  flush
  [ -s "$TMP/blamed" ] || continue
  sort -u "$TMP/blamed" > "$TMP/blamed.u"
  # 커밋 → FID 조인 (c2f: 커밋 fid 머지시각)
  attributed=$(awk -v fct="$fct" -v secs="$SECS" 'NR==FNR{b[$1]=1; next} ($1 in b){ print $2, $3 }' "$TMP/blamed.u" "$TMP/c2f" | sort -u)
  if [ -z "$attributed" ]; then UNATTR=$((UNATTR + 1)); continue; fi
  echo "$attributed" | while read -r fid mct; do
    [ "$fct" -gt "$mct" ] && [ "$fct" -le $((mct + SECS)) ] && echo "$fid $fh"
  done >> "$TMP/hits"
done < <(G log --no-merges "$BASE" --format='%H %ct %s' | grep -E '^[0-9a-f]+ [0-9]+ fix(\(|:|!)' | cut -d' ' -f1,2)
sort -u "$TMP/hits" -o "$TMP/hits"

# ── 3. 표·요약 ────────────────────────────────────────────────────────────────
echo "defect-rate: base=$BASE@$BASE_SHA 기간=${WIN}일 기준시각=$(date -u -r "$NOW" +%Y-%m-%d 2>/dev/null || date -u -d "@$NOW" +%Y-%m-%d)"
awk -v since="$SINCE" -v now="$NOW" -v secs="$SECS" -v unrec="$UNREC" -v unattr="$UNATTR" -v bf="$BLAMEFAIL" '
  FILENAME==ARGV[1] { h[$1]++; next }
  { fid=$1; ct=$2; day=$3; code=$4
    d=day; gsub(/-/,"",d); if (d+0 < since+0) { skipped++; next }
    if (!(fid in first) || ct < fct[fid]) { first[fid]=day; fct[fid]=ct }
    if (ct > last[fid]) last[fid]=ct
    c[fid]+=code
    if (!(fid in seen)) { seen[fid]=1; order[++n]=fid } }
  END {
    if (n==0) { print (skipped>0 ? "대상 없음: --since 로 전부 제외 (" skipped "건)" : "대상 없음: FID 머지 0건 (squash·rebase 머지는 인식하지 못함)"); exit }
    printf "%-44s %-11s %-12s %s\n", "FID", "머지일", "상태", "결함fix"
    for (i=1;i<=n;i++) { f=order[i]
      if (last[f] + secs > now) { st="관찰중"; v="-"; obs++ }
      else if (c[f]==0) { st="코드변경없음"; v="-"; nocode++ }
      else { st="완료"; v=h[f]+0; done++; sum+=v; if (v>0) bad++ }
      printf "%-44s %-11s %-12s %s\n", f, first[f], st, v }
    print "---"
    printf "완료 FID %d · 결함 있는 FID %d (%.0f%%) · FID 당 평균 %.1f\n", done, bad, (done>0?100*bad/done:0), (done>0?sum/done:0)
    printf "관찰중 %d · 코드변경없음 %d · 인식 못 한 머지 %d · 귀속 못 한 fix %d · blame 실패 %d\n", obs, nocode, unrec, unattr, bf
    if (obs == n) print "대상 없음: 전부 관찰중 (" obs "건 — 머지 뒤 " secs/86400 "일이 지나지 않음)"
    print "※ 근사치: 줄 추가만 하는 fix 와 fix 규약을 안 지킨 수정은 세지 않는다."
  }' <(cut -d' ' -f1 "$TMP/hits") "$TMP/merges" 2>/dev/null
