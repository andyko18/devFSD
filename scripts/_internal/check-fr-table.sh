#!/usr/bin/env bash
# check-fr-table.sh — requirements.md FR 표의 **실 FR** 판정 + batch 분류 (20260806 / 시드 SKIP 20260812)
# Usage:
#   check-fr-table.sh [requirements 경로]           # 인간 요약 (현행)
#   check-fr-table.sh --classify [requirements 경로] # 기계 레코드 (ELIGIBLE|SKIP|UNPARSED|SUMMARY)
#     UNPARSED|<첫 칸 원문> — FR 처럼 보이나 읽지 못한 행(ID 형식이 다르거나 행이 들여쓰였다 — 뒤쪽은 ` (들여쓴 행)` 을 붙인다).
#       있을 때만 SUMMARY 끝에 `|unparsed=N`.
#     ID 는 장식(굵게·백틱)을 벗겨 낸 값이다. 접미 ID(FR-11b)도 FR 이다.
# Exit: 0 = 실 FR ≥1 · 1 = 실 FR 0건 · 2 = 파일 부재
#
# 왜 필요한가: `/start-all` Phase 0 는 `grep -E '^\| FR-[0-9]+ \|'` 로 FR 을 기계 파싱하고
#   **"FR 행 0건이면 중단"** 만 검사한다. 그런데 `templates/requirements.md` 는
#   `| FR-1 | <한 줄> | M1 | must | (TBD) |` placeholder 행 3건을 담고 배포되고,
#   init 의 `_seed_fr_row` 는 PRD 마일스톤이 비면 그 행을 그대로 둔다.
#   → 사용자가 FR 을 하나도 안 썼는데 `/start-all` 이 **3개 기능을 구현하겠다며 진입**하고,
#     Phase 1 이 specifying-ko 에 넘기는 "FR 원문" 이 `<한 줄>` 이 된다.
#
# 시드 SKIP (20260812): init 가 FR-1~3 을 M1~M3 시드로 넣고 세부 FR-4+ 를 붙인 뒤에도
#   시드 행이 실 FR 로 남아 batch PENDING 에 들어가면 이중 구현된다(attendance·Argus 실측).
#   문서에 시드 마커가 있고 같은 마일스톤에 비시드 실 FR(≥FR-4) 이 있으면 FR-1|2|3 만 SKIP.
#
# 공통부 SKIP (20260812): 설명 선두 [공통] 또는 <!-- foundation-fr: FR-N,... --> 목록에
#   있으면 SKIP|…|foundation-scope — /start-all 이 공통 FR 을 PENDING 에 넣지 않는다(선택 A).
#   bash 3.2 호환 (연관 배열 미사용 — macOS /bin/bash).
#
# 마일스톤 범위 (20261116): `--milestone <이름|first>` 를 주면 그 마일스톤의 FR 만 ELIGIBLE 로 남기고
#   다른 마일스톤의 적격 FR 은 `SKIP|<id>|later-milestone|<M>` 으로 낸다(사유 이름은 `later` 지만 이름으로 고른 범위의 앞 마일스톤도 같다).
#   SUMMARY 끝에 `|milestone=<M>|milestone_skip=<N>|milestone_match=<그 마일스톤의 적격 FR 수>`.
#   `first` = 적격 FR 이 있는 가장 이른 마일스톤(값이 전부 `<글자><숫자>` 꼴이면 숫자가 가장 작은 것 · 아니면 표에 먼저 나온 것).
#   마일스톤 칸이 빈 FR 은 범위와 무관하게 ELIGIBLE 이다(거를 근거가 없다). 옵션이 없으면 종전대로 전부 본다.
#   왜: `/init-project` 는 M1 범위만 설계를 끝내는데 `/start-all` 은 M2·M3 FR("M2 시점에 분해"·`<미확정>`)까지
#   한 batch 에 넣었다(하류 실측 20261116 — M1 5건을 돌리려는데 대상 10건).
set -u

CLASSIFY=0
REQ=""
MS_SCOPE=""
_want_ms=0
for arg in "$@"; do
  if [ "$_want_ms" -eq 1 ]; then MS_SCOPE="$arg"; _want_ms=0; continue; fi
  case "$arg" in
    --classify) CLASSIFY=1 ;;
    --milestone) _want_ms=1 ;;
    --milestone=*) MS_SCOPE="${arg#--milestone=}" ;;
    -*) echo "FR-TABLE: unknown option: $arg" >&2; exit 2 ;;
    *) REQ="$arg" ;;
  esac
done
[ "$_want_ms" -eq 1 ] && { echo "FR-TABLE: --milestone 값 필요" >&2; exit 2; }
# 범위 값은 SUMMARY·queue 표에 그대로 실린다 — 칸 구분자·줄바꿈이 든 값은 받지 않는다.
case "$MS_SCOPE" in *"|"*|*"
"*) echo "FR-TABLE: --milestone 값에 | 나 줄바꿈을 쓸 수 없다" >&2; exit 2 ;; esac

if [ -z "$REQ" ]; then
  for c in ".specops/memory/requirements.md" "requirements.md"; do
    [ -f "$c" ] && { REQ="$c"; break; }
  done
fi
[ -n "$REQ" ] && [ -f "$REQ" ] || {
  echo "FR-TABLE: MISSING (requirements.md 부재)"
  exit 2
}

_is_placeholder_desc() {
  local desc="$1"
  [ -z "$desc" ] && return 0
  printf '%s' "$desc" | grep -qE '^<[^>]*>$' && return 0
  printf '%s' "$desc" | grep -qE '^(TBD|tbd|N/A|n/a|-|—|\(미정\)|미정|미확정|\(TBD\))$' && return 0
  return 1
}

_is_seed_id() {
  case "$1" in FR-1|FR-2|FR-3) return 0 ;; *) return 1 ;; esac
}

_has_seed_marker() {
  grep -qE '<!--[[:space:]]*seed-fr:[[:space:]]*FR-1[[:space:]]*,[[:space:]]*FR-2[[:space:]]*,[[:space:]]*FR-3[[:space:]]*-->' "$REQ" 2>/dev/null && return 0
  grep -q '마일스톤 시드' "$REQ" 2>/dev/null && return 0
  grep -qE 'PRD §4 마일스톤' "$REQ" 2>/dev/null && grep -q '시드' "$REQ" 2>/dev/null && return 0
  return 1
}

_has_nonseed_sibling() {
  local ms="$1"
  [ -n "$nonseed_ms_list" ] || return 1
  printf '%s\n' "$nonseed_ms_list" | grep -qxF "$ms"
}

# 설명 선두 [공통] / **[공통]** (앞 공백·볼드 허용)
_is_common_desc() {
  printf '%s' "$1" | grep -qE '^[[:space:]]*(\*\*)?\[공통\]'
}

# HTML <!-- foundation-fr: FR-4, FR-27 --> 목록에 id 포함 여부
_in_foundation_fr_list() {
  local id="$1" list
  # 표지가 여러 개면 모두 합쳐 읽는다(20261115) — init 이 만든 빈 표지가 먼저 있고 ID 를 적은 표지를 아래에 더하면 첫 것만 읽혀 무시됐다.
  list=$(grep -oE '<!--[[:space:]]*foundation-fr:[[:space:]]*[^>]*-->' "$REQ" 2>/dev/null | tr '\n' ' ') || true
  [ -n "$list" ] || return 1
  printf '%s' "$list" | grep -qE "(^|[^A-Za-z0-9-])${id}([^0-9]|$)"
}

_is_foundation_scope() {
  local id="$1" desc="$2"
  _is_common_desc "$desc" && return 0
  _in_foundation_fr_list "$id" && return 0
  return 1
}

tmp=$(mktemp)
classify_out=$(mktemp)

# FR 행 읽기 (20261009) — 첫 칸의 장식(굵게 `**`·백틱·공백)을 벗겨 ID 를 얻는다. 접미 ID(`FR-11b`)도 FR 이다.
#   종전 정규식은 `| FR-<숫자> |` 만 읽어, `| **FR-10** |`·`| FR-11b |` 행이 건수·경고·분류 어디에도 없이 사라졌다
#   (사용자가 적은 기능이 batch 에서 조용히 빠진다 — 실측 20261008). FR 처럼 보이는데 못 읽은 행은 UNP 로 따로 모아 알린다.
#   칸 구분은 US(\037)다 — 탭·공백은 공백류 IFS 라 `read` 가 빈 칸을 접는다. 설명이 빈 행에서 마일스톤이 설명 자리로
#   밀려 placeholder 가 적격 FR 로 둔갑했다(독립 리뷰가 재현). `|` 는 표 구분자라 칸 안에 올 수 없지만 awk 쪽 printf 와
#   읽는 쪽 IFS 를 한 글자로 맞추기 쉬운 US 를 쓴다.
real=0; ph=0; ph_ids=""; unparsed=0; unparsed_ids=""
unp_tmp=$(mktemp)
trap 'rm -f "$tmp" "$classify_out" "$unp_tmp"' EXIT
while IFS=$'\037' read -r rk id desc ms; do
  [ -z "$rk" ] && continue
  if [ "$rk" = "UNP" ]; then
    unparsed=$((unparsed + 1)); unparsed_ids="${unparsed_ids}${unparsed_ids:+ · }${id}"
    printf '%s\n' "$id" >>"$unp_tmp"
    continue
  fi
  if _is_placeholder_desc "$desc"; then
    ph=$((ph + 1)); ph_ids="${ph_ids}${ph_ids:+, }${id}"
    printf 'placeholder|%s|%s|%s\n' "$id" "$desc" "$ms" >>"$tmp"
  else
    real=$((real + 1))
    printf 'real|%s|%s|%s\n' "$id" "$desc" "$ms" >>"$tmp"
  fi
done <<EOF
$(awk -F'|' '
  function trim(v) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); return v }
  # 줄 시작 `|` 인 표 행만 본다(batch-state.sh 의 FR_RE 와 같은 범위). 첫 칸에서 굵게·백틱 장식과 바깥 공백만 벗긴다.
  #   읽는 ID: FR-<숫자로 시작하는 영숫자> — batch-state.sh 와 같은 꼴(FR-10 · FR-11b).
  #   UNP 는 **칸 전체가 ID 하나처럼 생겼는데** 꼴이 다른 것만이다(`FR 6`·`FR6`·`FR_1`·`FR-x7`).
  #   `FRAME 2`·`FR-1, FR-2`·`FR-3 → T4` 같은 칸은 FR 행이 아니다 — 경고하지 않는다.
  /^\|/ {
    c = $2; gsub(/[`*]/, "", c); c = trim(c)
    if (c ~ /^FR-[0-9][0-9A-Za-z]*$/) { printf "ROW\037%s\037%s\037%s\n", c, trim($3), trim($4) }
    else if (c ~ /^FR[-_ ]?[A-Za-z]?[0-9]+[A-Za-z]*$/ || c ~ /^FR[-_ ][A-Za-z0-9][A-Za-z0-9._-]*$/) { printf "UNP\037%s\n", c }   # 둘째 꼴(20261115): FR-1.1·FR-AUTH-01·FR-M1-02 — 구분자 뒤에 점·낱말이 든 ID
  }
  # 들여쓴 표 행 — 마크다운은 표로 그리지만 이 판정기와 batch-state.sh 는 줄 시작 `|` 만 읽는다(종전부터).
  #   읽는 범위를 넓히면 queue 를 읽는 쪽들과 어긋나므로 넓히지 않는다. 대신 FR 꼴이면 알린다 — 말없이 빠지지 않게.
  /^[ \t]+\|/ {
    c = $2; gsub(/[`*]/, "", c); c = trim(c)
    if (c ~ /^FR-[0-9][0-9A-Za-z]*$/ || c ~ /^FR[-_ ]?[A-Za-z]?[0-9]+[A-Za-z]*$/) { printf "UNP\037%s (들여쓴 행)\n", c }
  }' "$REQ" 2>/dev/null)
EOF

nonseed_ms_list=""
while IFS='|' read -r kind id desc ms; do
  [ "$kind" = "real" ] || continue
  _is_seed_id "$id" && continue
  [ -n "$ms" ] || continue
  if ! printf '%s\n' "$nonseed_ms_list" | grep -qxF "$ms" 2>/dev/null; then
    if [ -z "$nonseed_ms_list" ]; then
      nonseed_ms_list="$ms"
    else
      nonseed_ms_list="$nonseed_ms_list
$ms"
    fi
  fi
done <"$tmp"

# 못 읽은 행이 있을 때만 SUMMARY 끝에 건수를 붙인다(없으면 종전 형식 그대로 — 소비자는 real=·eligible= 만 읽는다).
unp_sfx=""; [ "$unparsed" -gt 0 ] && unp_sfx="|unparsed=${unparsed}"
unp_warn=""
[ "$unparsed" -gt 0 ] && unp_warn="  경고: 해석하지 못한 FR 행 ${unparsed}건 (${unparsed_ids}) — FR 처럼 보이나 ID 형식이 다르거나 행이 들여쓰여 batch 대상에서 빠진다. 줄 맨 앞에서 시작하는 | FR-<숫자> | 꼴로 고치세요"

if [ "$real" -eq 0 ]; then
  if [ "$CLASSIFY" -eq 1 ]; then
    while IFS='|' read -r kind id desc ms; do
      [ "$kind" = "placeholder" ] && echo "SKIP|${id}|placeholder|"
    done <"$tmp"
    while IFS= read -r u; do [ -n "$u" ] && echo "UNPARSED|${u}"; done <"$unp_tmp"
    echo "SUMMARY|real=0|eligible=0|seed_skip=0|placeholder=${ph}|foundation_skip=0${unp_sfx}"
  fi
  cat <<EOF
FR-TABLE: FAIL — 실 FR 0건 (placeholder ${ph}건: ${ph_ids:-none})
  $REQ 의 FR 행이 전부 미작성 상태입니다 — 골격 그대로면 /start-all 이
  존재하지 않는 기능을 구현하려 시도합니다.
  해법: requirements.md FR 표에 실제 기능 설명을 작성한 뒤 재실행하세요.
EOF
  [ -n "$unp_warn" ] && echo "$unp_warn"
  exit 1
fi

seed_marker=0
_has_seed_marker && seed_marker=1

eligible=0; seed_skip=0; seed_ids=""
foundation_skip=0; foundation_ids=""
while IFS='|' read -r kind id desc ms; do
  if [ "$kind" = "placeholder" ]; then
    echo "SKIP|${id}|placeholder|" >>"$classify_out"
    continue
  fi
  if [ "$seed_marker" -eq 1 ] && _is_seed_id "$id" && [ -n "$ms" ] && _has_nonseed_sibling "$ms"; then
    seed_skip=$((seed_skip + 1))
    seed_ids="${seed_ids}${seed_ids:+, }${id}"
    echo "SKIP|${id}|seed-decomposed|${ms}" >>"$classify_out"
    continue
  fi
  if _is_foundation_scope "$id" "$desc"; then
    foundation_skip=$((foundation_skip + 1))
    foundation_ids="${foundation_ids}${foundation_ids:+, }${id}"
    echo "SKIP|${id}|foundation-scope|${ms}" >>"$classify_out"
    continue
  fi
  eligible=$((eligible + 1))
  echo "ELIGIBLE|${id}|${desc}|${ms}" >>"$classify_out"
done <"$tmp"

# 마일스톤 범위 — 적격 판정이 끝난 뒤에 건다(시드·공통부·placeholder 는 범위와 무관하게 종전 사유 그대로).
ms_sfx=""; ms_skip=0; ms_skip_ids=""; ms_resolved=""; ms_match=0
if [ -n "$MS_SCOPE" ]; then
  ms_resolved="$MS_SCOPE"
  if [ "$MS_SCOPE" = "first" ]; then
    # 적격 FR 의 마일스톤(빈 칸 제외)을 나온 순서대로. 전부 <글자><숫자> 꼴이면 숫자가 가장 작은 것, 아니면 첫 번째.
    ms_resolved=$(awk -F'|' '$1 == "ELIGIBLE" && $NF != "" { if (!($NF in seen)) { seen[$NF] = 1; order[++n] = $NF } }
      END {
        if (n == 0) exit
        allnum = 1
        for (i = 1; i <= n; i++) if (order[i] !~ /^[^0-9]*[0-9]+$/) allnum = 0
        best = order[1]
        if (allnum) {
          bv = order[1]; gsub(/[^0-9]/, "", bv); bv += 0
          for (i = 2; i <= n; i++) { v = order[i]; gsub(/[^0-9]/, "", v); v += 0; if (v < bv) { bv = v; best = order[i] } }
        }
        print best
      }' "$classify_out")
  fi
  if [ -n "$ms_resolved" ]; then
    scoped=$(mktemp)
    # 설명 칸에는 `|` 가 올 수 없다(표 구분자) — 마지막 칸이 마일스톤이다.
    awk -F'|' -v want="$ms_resolved" 'BEGIN { OFS = "|" }
      $1 == "ELIGIBLE" && $NF != "" && $NF != want { print "SKIP", $2, "later-milestone", $NF; next }
      { print }' "$classify_out" >"$scoped"
    cat "$scoped" >"$classify_out"; rm -f "$scoped"
    ms_skip=$(grep -c '^SKIP|[^|]*|later-milestone|' "$classify_out" || true)
    ms_skip_ids=$(awk -F'|' '$1 == "SKIP" && $3 == "later-milestone" { printf "%s%s(%s)", (n++ ? ", " : ""), $2, $4 }' "$classify_out")
    eligible=$(grep -c '^ELIGIBLE|' "$classify_out" || true)
    # 그 마일스톤에 실제로 걸린 적격 FR 수 — 0 이면 이름이 표에 없다(오타). 마일스톤 칸이 빈 FR 은 세지 않는다.
    ms_match=$(awk -F'|' -v want="$ms_resolved" '$1 == "ELIGIBLE" && $NF == want { n++ } END { print n + 0 }' "$classify_out")
  fi
  # `first` 인데 마일스톤 칸이 전부 비었으면 거를 것이 없다 — 범위 표시는 `-`.
  ms_sfx="|milestone=${ms_resolved:--}|milestone_skip=${ms_skip}|milestone_match=${ms_match}"
fi

if [ "$CLASSIFY" -eq 1 ]; then
  cat "$classify_out"
  while IFS= read -r u; do [ -n "$u" ] && echo "UNPARSED|${u}"; done <"$unp_tmp"
  echo "SUMMARY|real=${real}|eligible=${eligible}|seed_skip=${seed_skip}|placeholder=${ph}|foundation_skip=${foundation_skip}${unp_sfx}${ms_sfx}"
  exit 0
fi

echo "FR-TABLE: PASS — 실 FR ${real}건"
[ "$ph" -gt 0 ] && echo "  경고: placeholder ${ph}건 (${ph_ids}) — batch 대상에서 제외하거나 채우세요"
[ "$seed_skip" -gt 0 ] && echo "  시드 SKIP ${seed_skip}건: ${seed_ids} (같은 마일스톤 세부 FR 존재 — batch PENDING 제외)"
[ "$foundation_skip" -gt 0 ] && echo "  공통부 SKIP ${foundation_skip}건: ${foundation_ids} (/start-foundation 담당 — batch PENDING 제외)"
[ "$ms_skip" -gt 0 ] && echo "  마일스톤 범위 ${ms_resolved}: 대상 ${eligible}건 · 다른 마일스톤 SKIP ${ms_skip}건 — ${ms_skip_ids}"
[ -n "$unp_warn" ] && echo "$unp_warn"
exit 0
