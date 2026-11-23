#!/usr/bin/env bash
# board-mode.sh — 관제판의 devFSD 칸이 "어느 명령이 도는가"에 맞춰 그릴 자료를 낸다 (읽기 전용 · 관제판용)
# Usage: board-mode.sh [<FID>]      (cwd = .specops 가 있는 폴더)
# Exit: 항상 0 — 판정할 수 없으면 아무것도 내지 않는다(관제판은 종전 표시로 떨어진다).
#
# 출력 — 탭으로 나눈 줄. 첫 줄이 MODE 다. 그 밖의 줄은 없을 수 있다.
#   MODE  <kind>  <제목>              kind = init · foundation · batch · start · maintain · quick
#   STEP  <mark>  <이름>              명령 흐름의 한 단계. mark = done · cur · todo · skip · fail
#                                     STEP 이 없으면 관제판은 이 작업(FID)의 단계 막대를 흐름으로 쓴다.
#   FR    <mark>  <FR-ID>  <설명>  <비고>   일괄 묶음의 FR 한 줄. mark = done · cur · todo · hold · block
#   ROW   <왼쪽>  <오른쪽>            명령별 추가 줄. 조각은 `{k|…}`(명령 색) · `{d|…}`(흐리게) · `{g|…}`(통과) ·
#                                     `{w|…}`(경고) · `{b|…}`(굵게) 로 감싸고, 그 밖은 보통 글자다.
#   SINCE <epoch 초>                  지금 단계가 시작된 시각(초기화) — 관제판이 경과 시계를 그린다.
#
# 왜 스크립트인가: 큐·진행 기록·초기화 표시를 읽는 규칙을 관제판 코드(TS)에 한 벌 더 두지 않는다(batch-progress.sh 와 같은 이유).
#   큐는 queue-lib.sh 의 qnorm 으로, 범위 상한은 quick-scope.sh 의 상수로 읽는다 — 수치·표기 규칙의 정의는 그쪽이다.
# 관찰만 한다: 아무것도 쓰지 않고, 실패해도 조용히 끝난다. 설명 글자에서 탭·중괄호·세로줄은 지운다(줄·조각 형식 보호).
# awk 정규식에 구간 반복({n})을 쓰지 않는다 — mawk 에서 매칭 0건이다(test-hooks.sh T8.q).
set -u
export LC_ALL=C
# git 이 조회만 하게 한다 — 이 값이 없으면 `git diff` 가 stat 만 바뀐 파일을 보고 index 를 다시 쓰며 index.lock 을 잡는다
#   (주 세션의 git add·commit 과 겹칠 수 있다 — 독립 리뷰 20261118 재현). quick-scope.sh 에도 그대로 전해진다.
export GIT_OPTIONAL_LOCKS=0
FID="${1:-}"
SPECOPS="${SPECOPS_ROOT:-.specops}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEDGER="$SPECOPS/session-progress.md"
TIMING="$SPECOPS/.init-timing"
[ -d "$SPECOPS" ] && [ ! -L "$SPECOPS" ] || exit 0

_clean() { printf '%s' "$1" | tr -d '\t{}|\r' | tr '\n' ' '; }

# 표시 파일의 마지막 표시 시각(epoch 초) — 없거나 깨졌으면 빈 값
_init_last() {
  [ -f "$TIMING" ] && [ ! -L "$TIMING" ] || return 0
  awk -F'\t' '$1 ~ /^[0-9]+$/ && $2 != "" { last = $1 } END { if (last != "") print last }' "$TIMING"
}
INIT_STALE_SEC=21600   # 6시간 — 중단돼 남은 표시 파일을 "돌고 있다"로 보지 않는다(종결이 지우지 못한 경우)
# 초기화가 지금 돌고 있는가 — 마지막 표시가 6시간 안이고, 이 작업의 최근 기록(분 단위)보다 늦다
_init_live() {
  local last now rec
  last=$(_init_last); [ -n "$last" ] || return 1
  now=$(date +%s)
  [ $((now - last)) -le "$INIT_STALE_SEC" ] || return 1
  rec="${1:-}"
  [ -n "$rec" ] || return 0
  # 기록 시각은 분 단위다. 초를 `:00` 으로 못 박아 읽는다 — macOS 의 `date -j -f` 는 형식에 초가 없으면 **지금의 초**로 채워,
  #   같은 입력이 호출마다 다른 값이 되고 표시와 같은 분이면 판정이 뒤집혀 관제판이 깜빡였다(20261123 재현).
  rec=$(date -j -f '%Y-%m-%d %H:%M:%S' "$rec:00" +%s 2>/dev/null || date -d "$rec:00" +%s 2>/dev/null) || return 0
  [ "$last" -gt "$rec" ]
}

# ── 초기화 — 표시 파일이 있으면 지금 /init-project 가 돌고 있다(종결이 지운다) ──
_init_running() {
  [ -f "$TIMING" ] && [ ! -L "$TIMING" ] || return 1
  awk -F'\t' '
    $1 ~ /^[0-9]+$/ && $2 != "" { if (!($2 in t)) t[$2] = $1; last = $1 }
    END {
      if (last == "") exit 1
      n = split("준비 답변 골격 인터뷰 보강 리뷰 승인 종결", name, " ")
      split("phase0 answers bash-end interview enrich review approved -", mk, " ")
      printf "MODE\tinit\t프로젝트 초기화\n"
      cur = 0; prev = ""; times = ""
      for (i = 1; i <= n; i++) {
        if (mk[i] in t) {
          printf "STEP\tdone\t%s\n", name[i]
          if (prev != "" && t[mk[i]] >= prev) { s = t[mk[i]] - prev; times = times (times == "" ? "" : " · ") name[i] " " (s < 60 ? s "초" : int(s / 60) "분") }
          prev = t[mk[i]]
        } else if (!cur) { cur = 1; printf "STEP\tcur\t%s\n", name[i] }
        else printf "STEP\ttodo\t%s\n", name[i]
      }
      if (times != "") printf "ROW\t{d|%s}\t\n", times
      printf "SINCE\t%s\n", last
    }' "$TIMING"
}

# ── 진행 기록에서 이 FID 의 줄(새 줄이 위)만: "<명령> <첫 낱말>" ──
_recs() {
  [ -f "$LEDGER" ] && [ ! -L "$LEDGER" ] || return 0
  awk -v F="$FID" '
    /^## / { on = ($2 == F); next }
    on && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9] \// { print $4, $5 }' "$LEDGER"
}
_has() { printf '%s\n' "$RECS" | grep -q "^$1 "; }
_word() { printf '%s\n' "$RECS" | sed -n "s#^$1 ##p" | head -1; }
_done_word() { case "$1" in 완료|DONE|PASS|SKIP) return 0 ;; esac; return 1; }

# 계획 안쪽 단계 — 풀 경로에서 계획이 도는 동안만(가장 오래 걸리는 구간이다)
_plan_row() {
  _has /plan-draft || _has /plan-expert || _has /plan-review || return 0
  _has /tasks && return 0
  local out="" s w
  for s in "/plan-draft:초안" "/plan-expert:전문가" "/plan-review:리뷰" "/plan:확정"; do
    w=$(_word "${s%%:*}")
    if [ -z "$w" ]; then out="$out {d|${s#*:}○}"
    elif _done_word "$w"; then out="$out ${s#*:}{k|✓}"
    else out="$out {k|${s#*:}●}"; fi
  done
  printf 'ROW\t{d|계획 │}%s\t\n' "$out"
}

_lane_row() {  # 갈래와 켜진 단계 — 기본 경로는 steps.txt(판정 기록)에서
  local d="$SPECOPS/$FID" t s
  if [ -e "$d/basic-draft" ]; then printf 'ROW\t{d|갈래} 기본→풀 승격\t\n'
  elif [ -f "$d/intent.md" ]; then printf 'ROW\t{d|갈래} 풀\t\n'
  elif [ -f "$d/steps.txt" ] && [ ! -L "$d/steps.txt" ]; then
    t=$(sed -n 's/^tasks=\([0-9][0-9]*\)$/\1/p' "$d/steps.txt" | head -1)
    s=$(sed -n 's/^signals=//p' "$d/steps.txt" | head -1 | tr -cd 'a-z_')
    # 신호 이름은 싣지 않는다 — 있다/없다만
    if [ -n "$s" ]; then s="신호 있음"; else s="위험 신호 없음"; fi
    printf 'ROW\t{d|갈래} 기본 {d|· %s%s}\t\n' "$s" "${t:+ · 태스크 $t}"
  else printf 'ROW\t{d|갈래} 기본\t\n'; fi
}

# ── 일괄 묶음 — 이 FID 가 든 진행 중 묶음의 큐 ──
_batch() {
  local q d lib="$HERE/queue-lib.sh"
  [ -f "$lib" ] || return 1
  # shellcheck source=/dev/null
  . "$lib"
  for q in "$SPECOPS"/batch-*/queue.md; do
    [ -f "$q" ] && [ ! -L "$q" ] || continue
    d="${q%/queue.md}"
    [ -f "$d/ACTIVE" ] || continue
    grep -qF "$FID" "$q" || continue
    awk -F'|' -v fid="$FID" -v PR="$([ -f "$d/plan-review.md" ] && echo 1 || echo 0)" -v DR="$([ -f "$d/design-review.md" ] && echo 1 || echo 0)" \
        -v IMPL="$(_has /implement && echo 1 || echo 0)" "$QUEUE_AWK_QNORM"'
      function clean(s) { gsub(/[\t{}|\r]/, "", s); sub(/ — .*/, "", s); gsub(/^[ ]+|[ ]+$/, "", s); return s }
      /^\|/ {
        id = qnorm($2)
        if (id == "FR-ID") { for (i = 2; i <= NF; i++) { h = qnorm($i); if (h == "Status") sc = i; if (h == "FID") fc = i; if (h ~ /^FR 설명/) dc = i } next }
        if (id !~ /^FR-[0-9]/ || !sc) next
        st = qnorm($sc); if (st == "SKIP") next
        n++; fr[n] = id; desc[n] = (dc ? clean($dc) : ""); stt[n] = st; isme[n] = (fc && qnorm($fc) == fid)
        if (st == "IMPL_DONE" || st == "MERGED") done++
        if (st == "PENDING") pend++
        if (isme[n]) found = 1
      }
      END {
        if (!found || n == 0) exit 1
        printf "MODE\tbatch\t일괄 묶음 %d/%d\n", done + 0, n
        # 묶음 흐름 — 준비 · FR 명세 · 계획 리뷰 · 통합 설계 · 구현 · 통합 · PR
        if (pend > 0) cur = 2; else if (!PR) cur = 3; else if (!DR && !IMPL && done == 0) cur = 4; else if (done < n) cur = 5; else cur = 6
        split("준비 FR명세 계획리뷰 통합설계 구현 통합 PR", nm, " "); nm[2] = "FR 명세"; nm[3] = "계획 리뷰"; nm[4] = "통합 설계"
        for (i = 1; i <= 7; i++) {
          m = (i < cur ? "done" : i == cur ? "cur" : "todo")
          if (i == 4 && cur > 4 && !DR) m = "skip"
          printf "STEP\t%s\t%s\n", m, nm[i]
        }
        for (i = 1; i <= n; i++) {
          m = (stt[i] == "IMPL_DONE" || stt[i] == "MERGED") ? "done" : isme[i] ? "cur" : stt[i] == "HELD" ? "hold" : stt[i] == "BLOCKED" ? "block" : "todo"
          note = (m == "hold" ? "보류" : m == "block" ? "막힘" : "")
          printf "FR\t%s\t%s\t%s\t%s\n", m, fr[i], desc[i], note
        }
      }' "$q" && return 0
  done
  return 1
}

# ── quick-fix — 명세 없이 태스크 문서만 있는 작업 ──
_quick() {
  local d="$SPECOPS/$FID" cur=2 i m mf ml verdict
  [ -f "$d/receipts/T1.json" ] && cur=4
  [ "$cur" = 2 ] && _has /implement && cur=4
  [ -f "$d/reviews/T1-C-report.md" ] && cur=5
  [ "$(_word /lifecycle)" = DONE ] && cur=6
  if [ "$cur" = 2 ] && git diff --quiet HEAD 2>/dev/null; then cur=2; elif [ "$cur" = 2 ]; then cur=3; fi
  printf 'MODE\tquick\t몇 줄 수정\n'
  i=1
  for m in 시작 수정 테스트 리뷰 커밋; do
    if [ "$i" -lt "$cur" ]; then printf 'STEP\tdone\t%s\n' "$m"; elif [ "$i" = "$cur" ]; then printf 'STEP\tcur\t%s\n' "$m"; else printf 'STEP\ttodo\t%s\n' "$m"; fi
    i=$((i + 1))
  done
  [ "$cur" = 6 ] && return 0          # 끝난 작업에는 범위 줄을 붙이지 않는다(판정기는 지금 스테이징을 본다)
  # 범위 상한은 판정기의 상수가 유일한 정의다 — 여기서는 읽어 보이기만 한다
  mf=$(sed -n 's/^QUICK_MAX_IMPL_FILES=\([0-9][0-9]*\)$/\1/p' "$HERE/quick-scope.sh" 2>/dev/null | head -1)
  ml=$(sed -n 's/^QUICK_MAX_LINES=\([0-9][0-9]*\)$/\1/p' "$HERE/quick-scope.sh" 2>/dev/null | head -1)
  [ -n "$mf" ] && [ -n "$ml" ] || return 0
  # 판정기는 스테이징된 변경을 본다 — 스테이징이 없으면 "판정 불가"를 OVER 로 내므로 그때는 판정을 보이지 않는다(거짓 경고)
  verdict=""
  if ! git diff --cached --quiet 2>/dev/null; then
    verdict=$(SPECOPS_ROOT="$SPECOPS" bash "$HERE/quick-scope.sh" "$FID" 2>/dev/null | sed -n 's/^QUICK-SCOPE: \([A-Z]*\).*/\1/p' | head -1)
  fi
  case "$verdict" in
    OVER) printf 'ROW\t{d|범위 상한} 파일 %s · 줄 %s\t{w|범위 초과}\n' "$mf" "$ml" ;;
    OK|NOREVIEW) printf 'ROW\t{d|범위 상한} 파일 %s · 줄 %s\t{g|범위 안}\n' "$mf" "$ml" ;;
    *) printf 'ROW\t{d|범위 상한} 파일 %s · 줄 %s\t\n' "$mf" "$ml" ;;
  esac
}

# ── 판정 ──
if ! printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$'; then
  [ -z "$FID" ] && _init_live && _init_running
  exit 0
fi
D="$SPECOPS/$FID"
RECS=$(_recs)
# 초기화가 돌고 있고 이 작업의 최근 기록이 그보다 앞서면(=앞선 작업이 활성으로 남아 있다) 초기화를 보인다
REC_AT=""
[ -f "$LEDGER" ] && [ ! -L "$LEDGER" ] && REC_AT=$(awk -v F="$FID" '
  /^## / { on = ($2 == F); next }
  on && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9] \// { print $2, $3; exit }' "$LEDGER")
case "$FID" in *-init-project) ;; *) if _init_live "$REC_AT"; then _init_running; exit 0; fi ;; esac
case "$FID" in
  *-init-project)
    printf 'MODE\tinit\t프로젝트 초기화\n'
    for m in 준비 답변 골격 인터뷰 보강 리뷰 승인 종결; do printf 'STEP\tdone\t%s\n' "$m"; done
    exit 0 ;;
esac
[ -d "$D" ] && [ ! -L "$D" ] || exit 0
SPEC=""; [ -f "$D/spec.md" ] && [ ! -L "$D/spec.md" ] && SPEC="$D/spec.md"

if [ -z "$SPEC" ]; then
  if [ -f "$D/tasks.md" ] || _has /quick-fix; then _quick; fi
  exit 0
fi
if grep -q '^\*\*§batch\*\*:' "$SPEC" 2>/dev/null; then
  _batch && exit 0
fi
TYPE=$(sed -n 's/^\*\*§유형\*\*:[[:space:]]*//p' "$SPEC" | head -1)
case "$TYPE" in
  foundation*)
    fr=$(awk -v F="$FID" '/^## / && $2 == F { if (match($0, /FR-[0-9]+[a-z]?/)) print substr($0, RSTART, RLENGTH); exit }' "$LEDGER" 2>/dev/null)
    printf 'MODE\tfoundation\t공통부%s\n' "${fr:+ $(_clean "$fr")}"
    _plan_row ;;
  유지보수*)
    printf 'MODE\tmaintain\t유지보수\n'
    n=$(cat "$D/acceptance-criteria.md" "$SPEC" 2>/dev/null | grep -E '^### AC-R-[0-9]+' | sed 's/:.*//' | sort -u | grep -c . || true)
    if [ "${n:-0}" -gt 0 ]; then
      if [ "$(_word /verify)" = PASS ]; then printf 'ROW\t{d|기존 동작 보존} 회귀 기준 %s건\t{g|✓ 검증됨}\n' "$n"
      else printf 'ROW\t{d|기존 동작 보존} 회귀 기준 %s건\t{d|○ 검증 전}\n' "$n"; fi
    fi
    _lane_row; _plan_row ;;
  *)
    if _has /analyze || [ -f "$D/current-state.md" ] || [ -f "$D/analysis.md" ]; then printf 'MODE\tmaintain\t유지보수\n'
    else printf 'MODE\tstart\t신규 기능\n'; fi
    _lane_row; _plan_row ;;
esac
exit 0
