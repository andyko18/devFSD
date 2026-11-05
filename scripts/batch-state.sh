#!/usr/bin/env bash
# batch-state.sh — batch queue ↔ requirements parity 검사 (read-only 감지 도구)
# 사용: batch-state.sh <batch-dir> [requirements-path]
#   exit 0 = clean (batch 대상 FR 전부 완료 + 드리프트 0 + 중복 0)
#     SKIP 행(시드·공통부 — init-batch-queue.sh 가 쓴다)과 requirements 의 placeholder FR 은 batch 대상이 아니다:
#     미완·드리프트로 세지 않고 [제외] 로 밝힌다(20261009). HELD·BLOCKED 는 멈춘 것이라 여전히 미완이다.
#     단 queue 의 SKIP 글자만으로 빼지 않는다 — check-fr-table.sh --classify 가 batch 대상이 아니라고 한 FR 만 뺀다.
#     분류기가 적격이라는 FR 을 SKIP 으로 둔 행은 미완이다(못 끝낸 FR 을 SKIP 으로 바꿔 완료를 만드는 경로 차단).
#   exit 1 = 불일치 (미완·드리프트·중복 목록 출력 — 차단 결정은 호출측 게이트 소관)
#   exit 2 = 사용 오류
# 완료 토큰: IMPL_DONE | MERGED (Status 마지막 컬럼 기준 — 설명 컬럼 오탐 방지)
# 파싱: 행 단위 grep — 2-테이블 분할 queue 견딤. FR suffix 변형(FR-3b) 허용
set -u

# --gate (20260721-batch-pr-teeth): 훅이 batch PR 을 **차단할지** 판정하는 모드.
#   기본 모드와 판정 기준이 다르다. 드리프트·중복·미완은 batch 운영 판단이다 —
#   M1 batch → M2·M3 batch 로 나눠 진행하면 드리프트는 정상이고, 이것으로 PR 을 막으면
#   정당한 부분 batch 를 차단하는 false-block 이 된다(dogfood 20260721 test1 이 정확히 이 형태였다).
#   게이트가 보는 것은 **뭉개짐 신호**뿐이다: 산출물 부재 · 진행기록 부재 · 라벨 오염.
#   운영 신호는 gate 모드에서도 참고 출력하되 exit code 에 반영하지 않는다.
# Status 라벨 정규화 단일 출처 (20260828-queue-label-drift) — 모델 손편집의 표기 장식 흡수
_BS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # 안내문에 싣는 경로의 기준 — 하류 저장소에는 scripts/ 가 없다
. "$_BS_DIR/_internal/queue-lib.sh"
. "$_BS_DIR/_internal/task-ids.sh"

GATE=0
if [ "${1:-}" = "--gate" ]; then GATE=1; shift; fi

BATCH_DIR="${1:-}"
if [ -z "$BATCH_DIR" ] || [ ! -d "$BATCH_DIR" ]; then
  echo "Usage: $0 <batch-dir> [requirements-path]" >&2; exit 2
fi
QUEUE="$BATCH_DIR/queue.md"
[ -f "$QUEUE" ] || { echo "Error: $QUEUE 없음" >&2; exit 2; }

REQ="${2:-}"
if [ -z "$REQ" ]; then
  # start-all Phase 0 동일 fallback (clarify Q1)
  if [ -f ".specops/memory/requirements.md" ]; then REQ=".specops/memory/requirements.md"
  elif [ -f "requirements.md" ]; then REQ="requirements.md"
  else echo "Error: requirements.md 미발견 — 경로 인자로 지정" >&2; exit 2; fi
fi
[ -f "$REQ" ] || { echo "Error: $REQ 없음" >&2; exit 2; }

# ID 칸의 장식(굵게 `**`·백틱)은 벗겨 낸다 — check-fr-table.sh 와 같은 규칙(20261009).
#   종전 정규식은 `| **FR-10** |` 을 FR 행으로 보지 않아, 그 FR 은 드리프트 대조에서 통째로 빠졌다.
FR_RE='^\| *[*`]*FR-[0-9][0-9A-Za-z]*[*`]* *\|'
_FR_ID_SED='s/^\| *[*`]*(FR-[0-9][0-9A-Za-z]*)[*`]* *\|.*/\1/'
queue_rows=$(grep -E "$FR_RE" "$QUEUE" || true)
queue_ids=$(printf '%s\n' "$queue_rows" | sed -E "$_FR_ID_SED")
req_ids=$(grep -E "$FR_RE" "$REQ" | sed -E "$_FR_ID_SED" || true)

fail=0        # 전체(기본 모드 exit code)
fail_gate=0   # 뭉개짐 신호만 (--gate exit code) — 운영 신호는 불포함

# 0) 라벨 오염 (gate 전용) — Status 가 인식 라벨이 아니면 하류 teeth 가 통째로 vacuous 해진다.
#    산출물·진행기록 검사는 IMPL_DONE 행만 수집하므로(아래 4·5), `DONE` 처럼 비슷하지만 다른 라벨을
#    쓰면 **검사 대상 0건 → 조용히 통과**한다. dogfood 20260721 test1 이 정확히 그랬다(FR-4~8 전부 `DONE`).
#    기본 모드에서는 검사하지 않는다 — 기존 호출자의 판정을 바꾸지 않기 위해서다(회귀 불변식).
#    ★ 기본 모드로 승격 (20260828): 종전엔 `--gate` 전용이었다. 그래서 하류 teeth 가
#      꺼진 사실을 **PR 시도 전까지 아무도 몰랐다** — 조용한 통과를 막으려고 만든 검사가
#      정작 조용한 구간에서 안 돌았다(argus 실측: FR 31건이 그 상태로 방치).
if [ -n "$queue_rows" ]; then
  bad_labels=$(printf '%s\n' "$queue_rows" | awk -F'|' "$QUEUE_AWK_QNORM"'
  {
    st = ""
    for (i = NF; i >= 1; i--) { if (qnorm($i) != "") { st = qnorm($i); break } }
    id = qnorm($2)
    if (st !~ /^('"$QUEUE_KNOWN_LABELS"')([^A-Za-z0-9_]|$)/) print "  - " id ": " st
  }')
  if [ -n "$bad_labels" ]; then
    echo "[라벨] queue.md Status 가 인식 라벨이 아님 — 완료 판정 teeth 가 무력화됩니다:"
    printf '%s\n' "$bad_labels"
    echo "  인식 라벨: IMPL_DONE | MERGED | TODO | WIP | DOING | PENDING | HELD | SKIP | BLOCKED | PLAN_DONE | CODE_DONE"
    fail=1; fail_gate=1
  fi
fi

# 1) queue FR-ID 중복
dups=$(printf '%s\n' "$queue_ids" | sort | uniq -d | grep -v '^$' || true)
if [ -n "$dups" ]; then
  echo "[중복] queue.md FR-ID 중복 — 상태 오갱신 위험:"
  printf '%s\n' "$dups" | sed 's/^/  - /'
  fail=1
fi

# 2) 드리프트 — requirements 에 있으나 queue 미추적
# batch 대상이 아닌 FR 은 **분류기가 그렇다고 한 것만** 뺀다 (판정 SoT = check-fr-table.sh --classify).
#   - placeholder FR(`| FR-9 | <한 줄> | …`): init-batch-queue.sh 가 queue 에서 의도적으로 뺀다 → 드리프트가 아니다.
#   - 시드·공통부 FR: init-batch-queue.sh 가 `SKIP` 행으로 쓴다 → 미완이 아니다.
#   queue 의 `SKIP` 글자만 보고 빼지 않는다 — 그러면 모델이 못 끝낸 적격 FR 을 SKIP 으로 바꿔 "완료" 를 만들 수 있다
#   (`--gate` 와 RELEASE_READY 는 IMPL_DONE 행만 보므로 막지 못하고, 무인은 exit code 만 본다 · 독립 리뷰가 재현).
#   분류기를 못 돌리면(부재·출력 없음) 아무것도 빼지 않고 종전대로 센다 — 판정 불가를 "문제 없음" 으로 읽지 않는다.
placeholder_ids=""; skip_ok_ids=""; cls_out=""
_chk="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_internal/check-fr-table.sh"
if [ -f "$_chk" ]; then
  cls_out=$(bash "$_chk" --classify "$REQ" 2>/dev/null | grep -E '^(ELIGIBLE|SKIP)\|' || true)
fi
if [ -n "$cls_out" ]; then
  # 같은 id 가 ELIGIBLE 로도 나오면(표에 실 행과 placeholder 행이 겹침) batch 대상이다 — 빼지 않는다.
  _elig=$(printf '%s\n' "$cls_out" | awk -F'|' '$1=="ELIGIBLE" {print $2}')
  placeholder_ids=$(printf '%s\n' "$cls_out" | awk -F'|' '$1=="SKIP" && $3=="placeholder" {print $2}' \
    | while IFS= read -r id; do [ -n "$id" ] && ! printf '%s\n' "$_elig" | grep -qx "$id" && printf '%s\n' "$id"; done | sort -u)
  skip_ok_ids=$(printf '%s\n' "$cls_out" | awk -F'|' '$1=="SKIP" {print $2}' \
    | while IFS= read -r id; do [ -n "$id" ] && ! printf '%s\n' "$_elig" | grep -qx "$id" && printf '%s\n' "$id"; done | sort -u)
fi
excluded_ph=""
drift=$(printf '%s\n' "$req_ids" | while IFS= read -r id; do
  [ -z "$id" ] && continue
  printf '%s\n' "$queue_ids" | grep -qx "$id" && continue
  printf '%s\n' "$placeholder_ids" | grep -qx "$id" && continue
  printf '%s\n' "$id"
done)
excluded_ph=$(printf '%s\n' "$req_ids" | while IFS= read -r id; do
  [ -z "$id" ] && continue
  printf '%s\n' "$queue_ids" | grep -qx "$id" && continue
  printf '%s\n' "$placeholder_ids" | grep -qx "$id" && printf '%s\n' "$id"
done)
if [ -n "$drift" ]; then
  echo "[드리프트] requirements 에 있으나 queue 미추적:"
  printf '%s\n' "$drift" | sed 's/^/  - /'
  fail=1
fi

# 3) 미완 — Status(마지막 컬럼)가 IMPL_DONE|MERGED 아님
incomplete=""
if [ -n "$queue_rows" ]; then  # 빈 queue 가드 — awk 빈 줄 유입 시 "  - : " phantom 차단
incomplete=$(printf '%s\n' "$queue_rows" | SKIP_OK=" $(printf '%s' "$skip_ok_ids" | tr '\n' ' ') " awk -F'|' "$QUEUE_AWK_QNORM"'
{
  # 마지막 비어있지 않은 필드 = Status. qnorm 이 CRLF·공백·표기 장식을 함께 흡수한다.
  st = ""
  for (i = NF; i >= 1; i--) { if (qnorm($i) != "") { st = qnorm($i); break } }
  id = qnorm($2)
  if (st ~ /^(IMPL_DONE|MERGED)/) next
  # SKIP 행은 분류기가 batch 대상이 아니라고 한 FR(시드·공통부)일 때만 미완에서 뺀다.
  #   종전엔 모든 SKIP 이 미완이라, 적격 FR 이 전부 끝나도 항상 exit 1 이었다(대화형은 매번 질문 · 무인은 PR 직전 정지).
  if (st ~ /^SKIP([^A-Za-z0-9_]|$)/) {
    if (index(ENVIRON["SKIP_OK"], " " id " ")) next
    print "  - " id ": " st " — requirements 에서는 batch 대상 FR 이다(시드·공통부·placeholder 가 아님). 끝내거나 HELD 로 두고 사유를 남긴다"
    next
  }
  print "  - " id ": " st
}')
fi
if [ -n "$incomplete" ]; then
  echo "[미완] 완료(IMPL_DONE|MERGED) 아님:"
  printf '%s\n' "$incomplete"
  fail=1
fi

# 제외한 것은 숨기지 않는다 — 무엇을 빼고 완료라 했는지 남긴다(exit code 에는 반영하지 않는다).
skipped=""
if [ -n "$queue_rows" ]; then
  skipped=$(printf '%s\n' "$queue_rows" | SKIP_OK=" $(printf '%s' "$skip_ok_ids" | tr '\n' ' ') " awk -F'|' "$QUEUE_AWK_QNORM"'
  {
    st = ""
    for (i = NF; i >= 1; i--) { if (qnorm($i) != "") { st = qnorm($i); break } }
    id = qnorm($2)
    if (st ~ /^SKIP([^A-Za-z0-9_]|$)/ && index(ENVIRON["SKIP_OK"], " " id " ")) print "  - " id ": SKIP (시드·공통부 — 분류기 판정)"
  }')
fi
if [ -n "$skipped" ] || [ -n "$excluded_ph" ]; then
  echo "[제외] batch 대상이 아닌 FR (미완·드리프트로 세지 않는다):"
  [ -n "$skipped" ] && printf '%s\n' "$skipped"
  [ -n "$excluded_ph" ] && printf '%s\n' "$excluded_ph" | sed 's/^/  - /; s/$/: placeholder (requirements 미작성 행)/'
fi

# 4) 산출물 뭉개짐 방지 teeth — IMPL_DONE FID 마다 per-FR 검증·리뷰 산출물 3종 필수
#    Phase 3 는 FR 당:
#      - review-base.sha    : review.diff 격리 base (부재→requesting-code-review 가 HEAD~1 로 silent
#                             fallback → 직전 FR 변경까지 끌어들여 내용 뭉개짐. layer 2 강제)
#      - evidence.md        : per-FR verify 산출 (layer 3 존재)
#      - review-request.md 또는 review-skip.md
#           : per-FR code-review 산출 (layer 3). review-skip.md 허용 조건 둘 중 하나:
#             (a) lite+단일태스크+batch-review-skip allowlist (기존)
#             (b) 사유에 end-loaded: + 전 tid 의 reviews/<tid>-[BC]-report.md 존재
#             (skip-only 시 사유 비공백 필수)
#    를 개별 생성해야 한다. 하나라도 없으면 verify/review 가 뭉개졌거나 미실행 → batch PR 전 차단.
#    MERGED(타 사이클서 이미 shipped)는 batch 전용 review-base.sha 미보유 가능 → 제외(IMPL_DONE 한정).
#    FID = 첫 두 비어있지 않은 필드 중 둘째.
SPECOPS_ROOT=$(dirname "$BATCH_DIR")
done_pairs=""
if [ -n "$queue_rows" ]; then
  done_pairs=$(printf '%s\n' "$queue_rows" | awk -F'|' "$QUEUE_AWK_QNORM"'
  {
    # FID 는 표의 FID 칸(둘째 칸 = $3)에서 읽는다. 종전엔 "비어 있지 않은 둘째 값" 을 써서, FID 칸이 빈 행은
    #   설명 칸의 글자가 FID 로 읽혔다(메시지에 엉뚱한 값이 찍혔다).
    st = ""
    for (i = NF; i >= 1; i--) { if (qnorm($i) != "") { st = qnorm($i); break } }
    if (st ~ /^IMPL_DONE/) print qnorm($2) "|" qnorm($3)
  }')
fi
missing_artifacts=""
invalid_skip=""
nofid=""; checked_n=0
if [ -n "$done_pairs" ]; then
  while IFS='|' read -r fr_id fid; do
    [ -z "$fr_id" ] && continue
    # FID 미확정 placeholder 는 미완 검사(3)가 이미 잡음 — 여기선 skip
    # FID 칸이 FID 가 아니면(TBD·—·빈칸) 이 FR 의 산출물을 찾을 수 없다. 종전엔 **말없이 건너뛰고** 검사 건수에는 넣었다 —
    #   모델이 FID 칸 갱신을 빠뜨리면 그 FR 은 검사를 통째로 피하고 게이트는 OK 를 냈다(실측 20261008). 이제 뭉개짐 신호다.
    if ! printf '%s' "$fid" | grep -qE '^[0-9]{8}-[a-z0-9-]+$'; then
      nofid="${nofid}  - ${fr_id}: FID 칸 '${fid:-(빈칸)}'"$'\n'
      continue
    fi
    checked_n=$((checked_n + 1))
    for art in review-base.sha evidence.md; do
      [ -f "$SPECOPS_ROOT/$fid/$art" ] || \
        missing_artifacts="${missing_artifacts}  - ${fr_id} (${fid}): ${art} 없음"$'\n'
    done
    # review-request.md 또는 lite skip 산출 review-skip.md 중 하나 필수
    if [ ! -f "$SPECOPS_ROOT/$fid/review-request.md" ] && [ ! -f "$SPECOPS_ROOT/$fid/review-skip.md" ]; then
      missing_artifacts="${missing_artifacts}  - ${fr_id} (${fid}): review-request.md|review-skip.md 없음"$'\n'
    fi
    # review-skip.md only — (a) lite+단일태스크 또는 (b) end-loaded+B/C reports (남용 차단)
    # review-request.md 가 있으면 정식 리뷰 경로로 보고 skip 메타는 검사하지 않는다.
    if [ -f "$SPECOPS_ROOT/$fid/review-skip.md" ] && [ ! -f "$SPECOPS_ROOT/$fid/review-request.md" ]; then
      skip_file="$SPECOPS_ROOT/$fid/review-skip.md"
      rp_file="$SPECOPS_ROOT/$fid/risk-profile.json"
      tasks_file="$SPECOPS_ROOT/$fid/tasks.md"
      reason_raw=$(cat "$skip_file" 2>/dev/null || true)
      reason=$(printf '%s' "$reason_raw" | tr -d ' \t\r\n')
      if [ -z "$reason" ]; then
        invalid_skip="${invalid_skip}  - ${fr_id} (${fid}): review-skip.md 사유 비어 있음"$'\n'
      elif printf '%s' "$reason_raw" | grep -qiE 'end-loaded'; then
        # (b) end-loaded: Phase B/C 가 이미 커버 — requesting 중복 skip
        if [ ! -f "$tasks_file" ]; then
          invalid_skip="${invalid_skip}  - ${fr_id} (${fid}): end-loaded skip 인데 tasks.md 부재"$'\n'
        else
          missing_bc=""
          while IFS= read -r tid; do
            [ -z "$tid" ] && continue
            [ -f "$SPECOPS_ROOT/$fid/reviews/${tid}-B-report.md" ] || \
              missing_bc="${missing_bc}${tid}-B "
            [ -f "$SPECOPS_ROOT/$fid/reviews/${tid}-C-report.md" ] || \
              missing_bc="${missing_bc}${tid}-C "
          done <<TIDS
$(tasks_md_ids "$tasks_file")
TIDS
          if [ "$(tasks_md_ids "$tasks_file" | wc -l | tr -d ' ')" -eq 0 ]; then
            invalid_skip="${invalid_skip}  - ${fr_id} (${fid}): end-loaded skip 인데 tasks.md 에 task id 없음"$'\n'
          elif [ -n "$missing_bc" ]; then
            invalid_skip="${invalid_skip}  - ${fr_id} (${fid}): end-loaded skip 인데 reviews 누락 (${missing_bc% })"$'\n'
          fi
        fi
      else
        # (a) lite+단일태스크+batch-review-skip
        if [ ! -f "$rp_file" ]; then
          invalid_skip="${invalid_skip}  - ${fr_id} (${fid}): review-skip 인데 risk-profile.json 부재"$'\n'
        else
          eff=$(jq -r '.effective // empty' "$rp_file" 2>/dev/null || true)
          if [ "$eff" != "lite" ]; then
            invalid_skip="${invalid_skip}  - ${fr_id} (${fid}): review-skip 인데 effective=${eff:-?} (lite 아님)"$'\n'
          fi
          if ! jq -e '.reductions_allowed | index("batch-review-skip")' "$rp_file" >/dev/null 2>&1; then
            invalid_skip="${invalid_skip}  - ${fr_id} (${fid}): review-skip 인데 reductions_allowed에 batch-review-skip 없음"$'\n'
          fi
        fi
        if [ ! -f "$tasks_file" ]; then
          invalid_skip="${invalid_skip}  - ${fr_id} (${fid}): review-skip 인데 tasks.md 부재"$'\n'
        else
          task_n=$(tasks_md_ids "$tasks_file" | wc -l | tr -d ' ')
          if [ "${task_n:-0}" -ne 1 ]; then
            invalid_skip="${invalid_skip}  - ${fr_id} (${fid}): review-skip 인데 태스크 수=${task_n:-0} (단일 태스크만 허용)"$'\n'
          fi
        fi
      fi
    fi
  done <<EOF
$done_pairs
EOF
fi
if [ -n "$nofid" ]; then
  echo "[FID 미기재] IMPL_DONE 인데 queue 의 FID 칸이 FID 가 아니다 — 그 FR 의 산출물·진행기록을 찾을 수 없다(검사 불가):"
  printf '%s' "$nofid"
  echo "  해법: bash \"$_BS_DIR/_internal/queue-set-status.sh\" <queue.md> <FR-ID> IMPL_DONE <FID> 로 FID 칸을 채운다."
  fail=1; fail_gate=1
fi
if [ -n "$missing_artifacts" ]; then
  echo "[산출물 누락] IMPL_DONE FID 의 per-FR 검증·리뷰 산출물 부재 (뭉개짐 방지 teeth):"
  printf '%s' "$missing_artifacts"
  fail=1; fail_gate=1
fi
if [ -n "$invalid_skip" ]; then
  echo "[review-skip 무효] lite+단일태스크 또는 end-loaded+B/C reports 메타 미충족 (남용·오분류 차단):"
  printf '%s' "$invalid_skip"
  fail=1; fail_gate=1
fi

# 5) 진행기록 teeth — IMPL_DONE FID 마다 session-progress.md FID 섹션에 /verify PASS 줄 필수
#    (dogfood 20260716: batch 가 skill 미호출 인라인 진행으로 session-progress 0줄 → R-1/R-2 면제 신호
#     (_verify_passed_in_progress) 부재 → 게이트 차단 → BYPASS 관성 남발. 이 줄은 verifying-evidence-ko
#     실호출의 흔적이자 세션 재개 맥락의 유일 경로. 앵커·섹션 추출은 governance-lib.sh
#     _verify_passed_in_progress 와 동일 포맷 — 행 선두 `- YYYY-MM-DD HH:MM /verify PASS`, memo 언급 무매칭)
PROGRESS="$SPECOPS_ROOT/session-progress.md"
missing_progress=""
if [ -n "$done_pairs" ]; then
  while IFS='|' read -r fr_id fid; do
    [ -z "$fr_id" ] && continue
    printf '%s' "$fid" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || continue   # FID 미기재는 위에서 이미 보고했다
    has_line=0
    if [ -f "$PROGRESS" ]; then
      awk -v f="## $fid" '$0 ~ "^"f"( |$)" {insec=1; next} insec && /^## / {exit} insec {print}' "$PROGRESS" \
        | grep -Eq '^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} /verify PASS' && has_line=1
    fi
    [ "$has_line" -eq 1 ] || \
      missing_progress="${missing_progress}  - ${fr_id} (${fid}): session-progress /verify PASS 줄 없음"$'\n'
  done <<EOF
$done_pairs
EOF
fi
if [ -n "$missing_progress" ]; then
  echo "[진행기록 누락] IMPL_DONE FID 의 session-progress /verify PASS 줄 부재 (verifying-evidence-ko 실호출 흔적·R-1/R-2 면제 신호):"
  printf '%s' "$missing_progress"
  fail=1; fail_gate=1
fi

if [ "$GATE" -eq 1 ]; then
  if [ "$fail_gate" -eq 0 ]; then
    # ★ 건수를 함께 낸다 (20260828-vacuity-claim). 이 경로가 `gh pr create` 를 여는 훅
    #   판정이라 기본 모드보다 파급이 크다 — 0건 검사로 "뭉개짐 신호 없음" 을 선언하면
    #   batch PR 이 무검증으로 나간다. 0 은 정상일 수 있으나 **보이지 않으면 안 된다**.
    _gchecked=$checked_n   # 실제로 산출물을 검사한 FID 수(FID 미기재 행은 세지 않는다)
    echo "BATCH-GATE: OK (뭉개짐 신호 없음 — ${_gchecked} FID 검사. 드리프트·미완은 운영 판단이라 차단 대상 아님)"
    exit 0
  fi
  echo "BATCH-GATE: BLOCK — per-FR 산출물·진행기록·라벨 결함 (위 목록 참조)" >&2
  exit 1
fi

if [ "$fail" -eq 0 ]; then
  # ★ "완비" 라고 말하지 않고 **몇 건을 검사했는지** 말한다 (20260828-vacuity-claim).
  #   종전엔 검사 대상이 0건이어도 — FID 디렉터리가 하나도 없어도 — 똑같이 "완비" 를
  #   주장했다. 0건 자체는 정상이지만(갓 시작한 batch·전건 MERGED 는 teeth 제외),
  #   **아무것도 확인하지 않고 완비를 주장하는 것**은 다른 문제다. argus batch-20260729 가
  #   라벨 드리프트로 그 상태였고, 31 FR 이 무검증인 채 "완비" 로 보고됐다.
  #   건수를 노출하면 0 이 눈에 띄어 사람이 물을 수 있다 — 차단이 아니라 가시성이다.
  _checked=$checked_n
  echo "BATCH-STATE: OK (batch 대상 FR 전부 완료 · 드리프트 0 · 중복 0 · 산출물·진행기록 ${_checked} FID 검사)"
  exit 0
fi
echo "BATCH-STATE: MISMATCH — batch PR 전 확인 필요" >&2
exit 1
