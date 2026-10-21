#!/usr/bin/env bash
# test-reconcile-check.sh — reconcile-check.sh (재개 desync 자동표면화 공유 로직) 단위 테스트
# 배경: show-fid-status FR-6 reconcile 로직을 공유 스크립트로 추출 → show-fid-status·SessionStart 훅 공용.
#   default 모드 = 기존 reconcile 블록(show-fid-status 위임, 출력 동일), --hook 모드 = DESYNC 시 간결 경고/정합 시 무출력.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$PLUGIN/scripts/_internal/reconcile-check.sh"

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# ── fixture 헬퍼 ──
# desync FID: session-progress=/tasks, 증거=implement(dispatch DONE)+verify(evidence.md) → evidence>recorded
mk_desync() {
  local fid="$1" root="$TMP/.specops"
  mkdir -p "$root/$fid"
  printf '## %s · stalled\n\n- 2026-01-04T00:00:00Z /tasks 완료 (tasks.md)\n' "$fid" >> "$root/session-progress.md"
  touch "$root/$fid/spec.md" "$root/$fid/plan.md" "$root/$fid/tasks.md"
  printf '| 1 | ts | A:T1 | implementer-ko | DONE | x |\n' > "$root/$fid/dispatch-log.md"
  printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$root/$fid/evidence.md"
}
# in-sync FID: session-progress=/specify, 증거=spec.md → recorded==evidence
mk_sync() {
  local fid="$1" root="$TMP/.specops"
  mkdir -p "$root/$fid"
  printf '## %s · ok\n\n- 2026-01-05T00:00:00Z /specify 완료 (spec.md)\n' "$fid" >> "$root/session-progress.md"
  touch "$root/$fid/spec.md"
}

ok() { PASS=$((PASS+1)); echo "PASS $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL $1 — $2"; }

# R1 — default 모드 DESYNC: reconcile 블록 헤더 + DESYNC + 재개점 힌트
mk_desync "20260104-desync"
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260104-desync" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF '실제 진행 대조 (reconcile)' \
   && printf '%s' "$out" | grep -qiE 'DESYNC|과소보고' \
   && printf '%s' "$out" | grep -qi '재개점'; then
  ok "R1 default-desync 블록+재개점"
else no "R1" "rc=$rc out=[$out]"; fi

# R2 — default 모드 정합: DESYNC 없음, '정합' 표기
mk_sync "20260105-sync"
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260105-sync" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qiE 'DESYNC|과소보고' \
   && printf '%s' "$out" | grep -qi '정합'; then
  ok "R2 default-정합 (경고 0)"
else no "R2" "rc=$rc out=[$out]"; fi

# R3 — --hook 모드 DESYNC: 비어있지 않음 + DESYNC + 재개점, exit 0
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260104-desync" --hook 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -n "$out" ] \
   && printf '%s' "$out" | grep -qiE 'DESYNC|과소보고' \
   && printf '%s' "$out" | grep -qi '재개점'; then
  ok "R3 hook-desync 간결경고"
else no "R3" "rc=$rc out=[$out]"; fi

# R4 — --hook 모드 정합: 무출력, exit 0 (훅 노이즈 0)
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260105-sync" --hook 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "R4 hook-정합 무출력"
else no "R4" "rc=$rc out=[$out]"; fi

# R5 — --hook 잘못된 FID 형식: 무출력 + exit 0 (훅 오염 금지 — silent)
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "invalid_fid" --hook 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "R5 hook-invalid-fid silent"
else no "R5" "rc=$rc out=[$out]"; fi

# R6 — --hook FID 디렉토리 없음: 무출력 + exit 0
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20991231-nonexistent" --hook 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "R6 hook-missing-dir silent"
else no "R6" "rc=$rc out=[$out]"; fi

# R7 — evidence 파일 존재만으로 verify 완료로 보지 않는다. 구조화 FAIL이면 implement frontier 유지.
fid="20260803-failed-verify"; root="$TMP/.specops"
mkdir -p "$root/$fid"
printf '## %s\n- 2026-08-03 10:00 /implement DONE\n' "$fid" >> "$root/session-progress.md"
touch "$root/$fid/spec.md" "$root/$fid/tasks.md"
printf 'RUN-VERIFICATION-RESULT: FAIL\n' > "$root/$fid/evidence.md"
printf '| 1 | ts | A:T1 | implementer-ko | DONE | x |\n' > "$root/$fid/dispatch-log.md"
SPECOPS_ROOT="$root" bash "$PLUGIN/scripts/_internal/verification-state.sh" record "$fid" FAIL
out=$(SPECOPS_ROOT="$root" bash "$SCRIPT" "$fid" --hook 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "R7 구조화 FAIL은 verify frontier 아님"
else no "R7" "rc=$rc out=[$out]"; fi

# R8 — Phase B/C reviews/ 만으로는 review=70(finishing) 과대보고 금지
fid="20260804-reviews-only"; root="$TMP/.specops"
mkdir -p "$root/$fid/reviews"
printf '## %s\n- 2026-08-04 10:00 /verify PASS (evidence.md)\n- 2026-08-04 09:00 /implement DONE\n' "$fid" >> "$root/session-progress.md"
touch "$root/$fid/spec.md" "$root/$fid/tasks.md"
printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$root/$fid/evidence.md"
printf '| 1 | ts | A:T1 | implementer-ko | DONE | x |\n' > "$root/$fid/dispatch-log.md"
echo "# T1 Phase B" > "$root/$fid/reviews/T1-B-report.md"
out=$(SPECOPS_ROOT="$root" bash "$SCRIPT" "$fid" --hook 2>&1); rc=$?
out_def=$(SPECOPS_ROOT="$root" bash "$SCRIPT" "$fid" 2>&1)
if [ "$rc" -eq 0 ] && [ -z "$out" ] \
   && ! printf '%s' "$out_def" | grep -qiE 'finishing|재개점:[[:space:]]*finishing'; then
  ok "R8 reviews/ alone ≠ review frontier (finishing 금지)"
else no "R8" "rc=$rc hook=[$out] def=[$out_def]"; fi

# R9 — review-skip.md 있으면 review=70 → finishing 재개점
fid="20260804-review-skip"; root="$TMP/.specops"
mkdir -p "$root/$fid/reviews"
printf '## %s\n- 2026-08-04 11:00 /verify PASS (evidence.md)\n' "$fid" >> "$root/session-progress.md"
touch "$root/$fid/spec.md" "$root/$fid/tasks.md"
printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$root/$fid/evidence.md"
printf '| 1 | ts | A:T1 | implementer-ko | DONE | x |\n' > "$root/$fid/dispatch-log.md"
echo "# T1 Phase B" > "$root/$fid/reviews/T1-B-report.md"
echo "lite skip: single-task + Phase C PASS" > "$root/$fid/review-skip.md"
out=$(SPECOPS_ROOT="$root" bash "$SCRIPT" "$fid" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qiE 'DESYNC|과소보고' \
   && printf '%s' "$out" | grep -qiE '증거 frontier:[[:space:]]*review|evidence frontier:[[:space:]]*review' \
   && printf '%s' "$out" | grep -qi '재개점:[[:space:]]*finishing'; then
  ok "R9 review-skip → review frontier + finishing 재개점"
else no "R9" "rc=$rc out=[$out]"; fi

# ── 산출물 완결성 경고 (20260807-reconcile-completeness) ──
# 판정 함수는 내부 전용이라 직접 호출하지 않고, FID fixture 로 관찰 가능한 경고를 검사한다.
mk_incomplete() {  # $1=fid $2=파일명 $3=내용(printf %b)
  local fid="$1" root="$TMP/.specops"
  mkdir -p "$root/$fid"
  printf '## %s · x\n\n- 2026-01-06T00:00:00Z /specify 완료 (spec.md)\n' "$fid" >> "$root/session-progress.md"
  touch "$root/$fid/spec.md"
  printf '%b' "$3" > "$root/$fid/$2"
}

# R10 — heading-end: 마지막 비어있지 않은 줄이 헤딩 → 경고 + 신호명 (AC-1, AC-7)
mk_incomplete "20260106-head" "plan.md" '# plan\n## 1. 가정\n'
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260106-head" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'plan.md' \
   && printf '%s' "$out" | grep -qF 'heading-end' \
   && printf '%s' "$out" | grep -qF '확인 요망'; then
  ok "R10 heading-end 탐지 + 신호명"
else no "R10" "rc=$rc out=[$out]"; fi

# R11 — odd-fence: ``` 시작 줄 홀수 → 경고 + 신호명 (AC-2, AC-7)
mk_incomplete "20260106-fence" "tasks.md" '# tasks\n\n```yaml\ntasks:\n  - id: T1\n'
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260106-fence" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'tasks.md' \
   && printf '%s' "$out" | grep -qF 'odd-fence'; then
  ok "R11 odd-fence 탐지 + 신호명"
else no "R11" "rc=$rc out=[$out]"; fi

# R12 — table-hdr: 끝 3줄에 표 구분행만, 데이터 행 없음 → 경고 + 신호명 (AC-3, AC-7)
mk_incomplete "20260106-tbl" "plan.md" '# plan\n## 2. 파일 구조\n\n| 파일 | 역할 |\n|---|---|\n'
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260106-tbl" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'plan.md' \
   && printf '%s' "$out" | grep -qF 'table-hdr'; then
  ok "R12 table-hdr 탐지 + 신호명"
else no "R12" "rc=$rc out=[$out]"; fi

# R13 — 완결 산출물: 경고 없음 (오탐 금지)
mk_incomplete "20260106-ok" "plan.md" '# plan\n\n## 1. 가정\n\n- 전제 A\n\n| 파일 | 역할 |\n|---|---|\n| a.sh | 판정 |\n\n```bash\necho ok\n```\n\n마무리 문장.\n'
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260106-ok" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qF '불완전 가능'; then
  ok "R13 완결 산출물 무경고 (오탐 0)"
else no "R13" "rc=$rc out=[$out]"; fi

# R14 — 파일 부재는 불완전이 아니다 (AC-6): spec.md 만 존재
mk_sync "20260106-absent"
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260106-absent" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qF '불완전 가능'; then
  ok "R14 plan/tasks 부재 → 경고 없음"
else no "R14" "rc=$rc out=[$out]"; fi

# R15 — --hook 모드: 정합이어도 불완전이면 경고 1줄 + rc=0 (AC-5)
mk_incomplete "20260106-hook" "plan.md" '# plan\n## 1. 가정\n'
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260106-hook" --hook 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -n "$out" ] && printf '%s' "$out" | grep -qF 'plan.md' \
   && printf '%s' "$out" | grep -qF '확인 요망'; then
  ok "R15 --hook 불완전 경고 (정합 상태)"
else no "R15" "rc=$rc out=[$out]"; fi

# R16 — 다중 불완전: plan+tasks 각각 1줄, 각 줄에 파일명+신호명 (AC-9)
mk_incomplete "20260106-multi" "plan.md" '# plan\n## 1. 가정\n'
printf '%b' '# tasks\n\n```yaml\ntasks:\n' > "$TMP/.specops/20260106-multi/tasks.md"
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260106-multi" --hook 2>&1); rc=$?
n=$(printf '%s\n' "$out" | grep -cF '불완전 가능')
if [ "$rc" -eq 0 ] && [ "$n" -eq 2 ] \
   && printf '%s' "$out" | grep -qF 'plan.md' && printf '%s' "$out" | grep -qF 'heading-end' \
   && printf '%s' "$out" | grep -qF 'tasks.md' && printf '%s' "$out" | grep -qF 'odd-fence'; then
  ok "R16 다중 불완전 파일별 1줄 (2줄)"
else no "R16" "rc=$rc n=$n out=[$out]"; fi

# R17 — evidence < recorded 오표기 제거 (AC-8): 기록=clarify, 증거=specify
r17_root="$TMP/.specops"; r17_fid="20260106-behind"
mkdir -p "$r17_root/$r17_fid"
printf '## %s · x\n\n- 2026-01-06T00:00:00Z /clarify 완료 (clarifications.md)\n' "$r17_fid" >> "$r17_root/session-progress.md"
touch "$r17_root/$r17_fid/spec.md"
out=$(SPECOPS_ROOT="$r17_root" bash "$SCRIPT" "$r17_fid" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qF '정합' \
   && printf '%s' "$out" | grep -qF '기록이 증거보다 앞섬'; then
  ok "R17 evidence<recorded 오표기 제거"
else no "R17" "rc=$rc out=[$out]"; fi

# R18 — 실 산출물 오탐 0 (AC-R-3): .specops/*/plan.md·tasks.md 동적 순회.
# 고정 수치 비교 금지 — 산출물 수는 FID 가 늘 때마다 변한다. 0건이면 graceful skip.
real_root="$PLUGIN/.specops"
fp=0; scanned=0
if [ -d "$real_root" ]; then
  for f in "$real_root"/*/plan.md "$real_root"/*/tasks.md; do
    [ -f "$f" ] || continue
    scanned=$((scanned+1))
    real_fid=$(basename "$(dirname "$f")"); base=$(basename "$f")
    o=$(SPECOPS_ROOT="$real_root" bash "$SCRIPT" "$real_fid" 2>&1)
    printf '%s' "$o" | grep -qF "$base 불완전 가능" && { fp=$((fp+1)); echo "  FP: $f"; }
  done
fi
if [ "$scanned" -eq 0 ]; then
  ok "R18 실 산출물 오탐 스캔 SKIP (산출물 0건)"
elif [ "$fp" -eq 0 ]; then
  ok "R18 실 산출물 오탐 0 (스캔 $scanned 건)"
else no "R18" "오탐 $fp/$scanned 건"; fi

# R19 — show-fid-status byte-동일 위임 보존 (AC-R-4): 완결+정합 FID 에서 두 출력 동일
mk_incomplete "20260106-delegate" "plan.md" '# plan\n\n## 1. 가정\n\n- 전제 A\n\n마무리 문장.\n'
a=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260106-delegate" 2>&1)
b=$(SPECOPS_ROOT="$TMP/.specops" bash "$PLUGIN/scripts/show-fid-status.sh" "20260106-delegate" 2>&1 \
    | awk '/^## 실제 진행 대조/{f=1} f{print}')
if [ -n "$a" ] && [ "$(printf '%s' "$a" | grep -vE '^[[:space:]]*$')" = "$(printf '%s' "$b" | grep -vE '^[[:space:]]*$')" ]; then
  ok "R19 show-fid-status byte-동일 위임 보존"
else no "R19" "delegate-mismatch a=[$a] b=[$b]"; fi

# R20 — pipeless 데이터 행도 데이터다 (Phase C Minor): `|---|---|` 뒤 `a | b` → 오탐 금지
mk_incomplete "20260106-pipeless" "plan.md" '# plan\n\n| 파일 | 역할 |\n|---|---|\na.sh | 판정\n'
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260106-pipeless" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qF 'table-hdr'; then
  ok "R20 pipeless 표 데이터 행 오탐 없음"
else no "R20" "rc=$rc out=[$out]"; fi

# R21 — 읽기 권한 없는 파일: stderr 누출 없이 fail-open (Phase C Minor)
#   root 는 chmod 000 을 읽어 버려 권한 오류가 나지 않는다 — 통과가 공허하므로 SKIP
if [ "$(id -u)" -eq 0 ]; then
  echo "SKIP R21 권한 없는 파일 — root 로 실행 중(권한 검사 무의미)"
else
  mk_incomplete "20260106-noperm" "plan.md" '# plan\n## 1. 가정\n'
  chmod 000 "$TMP/.specops/20260106-noperm/plan.md" 2>/dev/null
  err=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260106-noperm" 2>&1 >/dev/null); rc=$?
  chmod 644 "$TMP/.specops/20260106-noperm/plan.md" 2>/dev/null
  if [ "$rc" -eq 0 ] && ! printf '%s' "$err" | grep -qiE 'permission denied|No such file'; then
    ok "R21 권한 없는 파일 stderr 무누출"
  else no "R21" "rc=$rc err=[$err]"; fi
fi

# R22 — CRLF 산출물에서도 heading-end 탐지 (Phase C Minor — 회귀 고정)
mk_incomplete "20260106-crlf" "plan.md" '# plan\r\n## 1. 가정\r\n'
out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260106-crlf" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'heading-end'; then
  ok "R22 CRLF heading-end 탐지"
else no "R22" "rc=$rc out=[$out]"; fi

# ── review-skip-pass.sh (20261005-skill-progressive-disclosure) ──────────────────
# end-loaded 로 B/C 를 끝낸 FID 의 requesting·receiving-code-review 기계적 통과를 스크립트가 대신한다.
# 조건 충족 → 종전 skill 과 같은 산출물(review-skip.md·session-progress 두 줄), 불충족 → rc 1 + 쓰기 0.
RSP="$PLUGIN/scripts/_internal/review-skip-pass.sh"
mk_rs() {  # $1=fid — 2 태스크 · B/C 리포트 완비 · end-loaded · 단일 모드 (모든 조건 충족 픽스처)
  local fid="$1" root="$TMP/.specops"
  mkdir -p "$root/$fid/reviews"
  printf '**§유형**: 유지보수\n' > "$root/$fid/spec.md"
  printf 'review_mode: end-loaded\ntasks:\n  - id: T1\n  - id: T2\n' > "$root/$fid/tasks.md"
  local t
  for t in T1 T2; do
    printf 'B\n' > "$root/$fid/reviews/$t-B-report.md"
    printf 'C\n' > "$root/$fid/reviews/$t-C-report.md"
  done
  printf '## %s · rs\n\n- 2026-01-07T00:00:00Z /verify PASS (evidence.md)\n' "$fid" >> "$root/session-progress.md"
}
rs_run() { ( cd "$TMP" && SPECOPS_ROOT="$TMP/.specops" bash "$RSP" "$@" ); }
rs_sum() { cat "$TMP/.specops/session-progress.md" 2>/dev/null | cksum; }

# R23 — 조건 충족: rc 0 · review-skip.md 첫 줄 · session-progress 두 줄(최신 줄이 위)
mk_rs "20260107-rs-pass"
out=$(rs_run "20260107-rs-pass" 2>&1); rc=$?
sk="$TMP/.specops/20260107-rs-pass/review-skip.md"
ln_rcv=$(grep -n '/receive-review 완료' "$TMP/.specops/session-progress.md" | head -1 | cut -d: -f1)
ln_req=$(grep -n '/request-review 완료' "$TMP/.specops/session-progress.md" | head -1 | cut -d: -f1)
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'review-skip-pass: OK' \
   && [ "$(head -1 "$sk" 2>/dev/null)" = 'end-loaded: Phase B/C already covered full FID diff' ] \
   && [ -n "$ln_rcv" ] && [ -n "$ln_req" ] && [ "$ln_rcv" -lt "$ln_req" ]; then
  ok "R23 조건 충족 → review-skip.md + session-progress 두 줄"
else no "R23" "rc=$rc out=[$out] first=[$(head -1 "$sk" 2>/dev/null)] rcv=$ln_rcv req=$ln_req"; fi

# R23b — 표준 템플릿 줄(`review_mode: end-loaded   # 기본 ...` 인라인 주석)도 통과해야 한다 — 화이트리스트가 정상 형태를 막지 않는 양성 대조
mk_rs "20260107-rs-cmt-ok"; printf 'review_mode: end-loaded   # 기본 — 레거시: per-task\ntasks:\n  - id: T1\n  - id: T2\n' > "$TMP/.specops/20260107-rs-cmt-ok/tasks.md"
out=$(rs_run "20260107-rs-cmt-ok" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'review-skip-pass: OK'; then ok "R23b end-loaded + 인라인 주석 → 통과"; else no "R23b" "rc=$rc out=[$out]"; fi

# R24 — 소비자 호환(reconcile-check 가 읽는 마커·review-skip.md 와 batch-state 가 grep 하는 end-loaded 사유. 스크립트는 §batch FID 를 거부하고
#   batch-state 는 batch 큐의 FID 만 읽으므로 batch-state 를 직접 돌리는 대신 사유 문구 계약(test-batch-state T2.a7 이 잠금)만 대조한다): reconcile-check --hook 이 이 산출물을 정합으로 본다(DESYNC 무출력) + batch-state 의 end-loaded 사유 문구
hook_out=$(SPECOPS_ROOT="$TMP/.specops" bash "$SCRIPT" "20260107-rs-pass" --hook 2>&1)
if [ -z "$hook_out" ] && head -1 "$sk" | grep -qiE 'end-loaded'; then
  ok "R24 reconcile 정합 + batch-state 가 읽는 end-loaded 사유"
else no "R24" "hook=[$hook_out]"; fi

# R25~R31 — 불충족·판정 불가: rc 1 · stderr 사유 · 쓰기 0 (review-skip.md 부재/불변 + session-progress cksum 불변)
rs_neg() {  # $1=id $2=desc $3=fid  — 호출 전에 픽스처를 깨뜨려 둔다. review-skip.md 는 사전 존재 여부와 무관하게 내용 불변이어야 한다
  local id="$1" desc="$2" fid="$3" before after rc err pre_skip post_skip
  before=$(rs_sum); pre_skip=$(cat "$TMP/.specops/$fid/review-skip.md" 2>/dev/null || echo ABSENT)
  err=$(rs_run "$fid" 2>&1 >/dev/null); rc=$?
  after=$(rs_sum); post_skip=$(cat "$TMP/.specops/$fid/review-skip.md" 2>/dev/null || echo ABSENT)
  if [ "$rc" -eq 1 ] && [ -n "$err" ] && [ "$before" = "$after" ] && [ "$pre_skip" = "$post_skip" ]; then
    ok "$id $desc → rc 1 · 쓰기 0"
  else no "$id $desc" "rc=$rc err=[$err] progress-same=$([ "$before" = "$after" ] && echo y || echo n) skip-same=$([ "$pre_skip" = "$post_skip" ] && echo y || echo n)"; fi
}
mk_rs "20260107-rs-pertask"; printf 'review_mode: per-task\ntasks:\n  - id: T1\n  - id: T2\n' > "$TMP/.specops/20260107-rs-pertask/tasks.md"
rs_neg R25 "per-task 모드" "20260107-rs-pertask"
mk_rs "20260107-rs-pt-cmt"; printf 'review_mode: per-task   # 레거시\ntasks:\n  - id: T1\n  - id: T2\n' > "$TMP/.specops/20260107-rs-pt-cmt/tasks.md"
rs_neg R25b "per-task + 인라인 주석(templates/tasks.md 표준 형태)" "20260107-rs-pt-cmt"
mk_rs "20260107-rs-pt-quote"; printf 'review_mode: "per-task"\ntasks:\n  - id: T1\n  - id: T2\n' > "$TMP/.specops/20260107-rs-pt-quote/tasks.md"
rs_neg R25c "per-task 따옴표" "20260107-rs-pt-quote"
mk_rs "20260107-rs-mode2"; printf 'review_mode: end-loaded\nreview_mode: per-task\ntasks:\n  - id: T1\n  - id: T2\n' > "$TMP/.specops/20260107-rs-mode2/tasks.md"
rs_neg R25d "review_mode 줄 중복" "20260107-rs-mode2"
mk_rs "20260107-rs-mode0"; printf 'tasks:\n  - id: T1\n  - id: T2\n' > "$TMP/.specops/20260107-rs-mode0/tasks.md"
rs_neg R25e "review_mode 줄 부재(skill 은 end-loaded 로 취급하나 스크립트는 더 엄격하게 rc 1)" "20260107-rs-mode0"
mk_rs "20260107-rs-missing"; rm -f "$TMP/.specops/20260107-rs-missing/reviews/T2-C-report.md"
rs_neg R26 "C 리포트 누락" "20260107-rs-missing"
mk_rs "20260107-rs-batch"; printf '**§유형**: 신규\n**§batch**: B-1\n' > "$TMP/.specops/20260107-rs-batch/spec.md"
rs_neg R27 "§batch FID" "20260107-rs-batch"
mk_rs "20260107-rs-notasks"; rm -f "$TMP/.specops/20260107-rs-notasks/tasks.md"
rs_neg R28 "tasks.md 부재" "20260107-rs-notasks"
mk_rs "20260107-rs-request"; printf 'x\n' > "$TMP/.specops/20260107-rs-request/review-request.md"
rs_neg R29 "review-request.md 이미 존재" "20260107-rs-request"
mk_rs "20260107-rs-already"; printf 'manual\n' > "$TMP/.specops/20260107-rs-already/review-skip.md"
rs_neg R30 "review-skip.md 이미 존재(내용 불변)" "20260107-rs-already"
mk_rs "20260107-rs-notid"; printf 'review_mode: end-loaded\ntasks: []\n' > "$TMP/.specops/20260107-rs-notid/tasks.md"
rs_neg R31 "task id 0건" "20260107-rs-notid"
mk_rs "20260107-rs-nospec"; rm -f "$TMP/.specops/20260107-rs-nospec/spec.md"
rs_neg R33 "spec.md 부재(§batch 판정 불가 — 스킵 방향 금지)" "20260107-rs-nospec"
err=$(rs_run "bad-fid" 2>&1 >/dev/null); rc=$?
if [ "$rc" -eq 1 ] && [ -n "$err" ]; then ok "R32 잘못된 FID 인자 → rc 1"; else no "R32" "rc=$rc err=[$err]"; fi

# R34~R36 — 쓰기 단계 실패 경로와 SPECOPS_ROOT 일관성. 실패는 session-progress-append.sh 스텁(N 번째 호출에서 실패)으로 유도해 실 트리를 건드리지 않는다
mk_stub() {  # $1=실패시킬 호출 번호 — 스크립트 사본 + 스텁 append 를 $TMP/stub$1 아래 두고 경로를 출력한다
  local n="$1" d="$TMP/stub$1"
  mkdir -p "$d/_internal"
  cp "$RSP" "$d/_internal/review-skip-pass.sh"
  # shellcheck disable=SC2016  # 스텁 본문은 의도적으로 단일 따옴표(생성되는 스크립트 안에서 전개된다)
  printf '#!/usr/bin/env bash\nc=$(cat "%s/count" 2>/dev/null || echo 0); c=$((c+1)); echo "$c" > "%s/count"\n[ "$c" -eq %s ] && exit 1\nexit 0\n' "$d" "$d" "$n" > "$d/session-progress-append.sh"
  printf '%s' "$d"
}
stub_run() { ( cd "$TMP" && SPECOPS_ROOT="$TMP/.specops" bash "$1/_internal/review-skip-pass.sh" "$2" 2>&1 ); }

# R34 — 첫 append 실패: review-skip.md 를 되돌리고 rc 1
mk_rs "20260108-rs-fail1"; sd=$(mk_stub 1)
out=$(stub_run "$sd" "20260108-rs-fail1"); rc=$?
if [ "$rc" -eq 1 ] && [ ! -e "$TMP/.specops/20260108-rs-fail1/review-skip.md" ] && printf '%s' "$out" | grep -qF 'session-progress 기록 실패' \
   && [ "$(cat "$sd/count" 2>/dev/null)" = 1 ]; then
  ok "R34 첫 append 실패 → review-skip.md 제거 · rc 1"
else no "R34" "rc=$rc skip-exists=$([ -e "$TMP/.specops/20260108-rs-fail1/review-skip.md" ] && echo y || echo n) out=[$out]"; fi

# R35 — 두 번째 append 실패: review-skip.md 는 남고 rc 1 (종전 skill 이 이어받는다 — NFR-2)
mk_rs "20260108-rs-fail2"; sd=$(mk_stub 2)
out=$(stub_run "$sd" "20260108-rs-fail2"); rc=$?
if [ "$rc" -eq 1 ] && [ "$(head -1 "$TMP/.specops/20260108-rs-fail2/review-skip.md" 2>/dev/null)" = 'end-loaded: Phase B/C already covered full FID diff' ] \
   && printf '%s' "$out" | grep -qF '두 번째 기록 실패' && [ "$(cat "$sd/count" 2>/dev/null)" = 2 ]; then
  ok "R35 두 번째 append 실패 → review-skip.md 잔존 · rc 1"
else no "R35" "rc=$rc first=[$(head -1 "$TMP/.specops/20260108-rs-fail2/review-skip.md" 2>/dev/null)] out=[$out]"; fi

# R36 — SPECOPS_ROOT 가 cwd 의 .specops 와 다르면 rc 1 · 쓰기 0 (양성 대조는 R23 — 같은 디렉터리 절대경로)
mk_rs "20260108-rs-root"; mkdir -p "$TMP/alt"; cp -R "$TMP/.specops/20260108-rs-root" "$TMP/alt/"
before=$(rs_sum)
out=$( ( cd "$TMP" && SPECOPS_ROOT="$TMP/alt" bash "$RSP" "20260108-rs-root" 2>&1 ) ); rc=$?
if [ "$rc" -eq 1 ] && [ ! -e "$TMP/alt/20260108-rs-root/review-skip.md" ] && [ "$(rs_sum)" = "$before" ] \
   && printf '%s' "$out" | grep -qF 'SPECOPS_ROOT'; then
  ok "R36 SPECOPS_ROOT 불일치 → rc 1 · 쓰기 0"
else no "R36" "rc=$rc out=[$out]"; fi

# R37 — 정상 운영 형태의 SPECOPS_ROOT(미설정·상대·./ 접두·끝 슬래시)는 가드가 막지 않는다 (R23 의 절대경로 양성 대조를 보완)
i=0
for form in UNSET ".specops" "./.specops" "$TMP/.specops/"; do
  i=$((i+1)); fid="20260108-rs-form$i"; mk_rs "$fid"
  if [ "$form" = UNSET ]; then out=$( ( cd "$TMP" && env -u SPECOPS_ROOT bash "$RSP" "$fid" 2>&1 ) ); rc=$?
  else out=$( ( cd "$TMP" && SPECOPS_ROOT="$form" bash "$RSP" "$fid" 2>&1 ) ); rc=$?; fi
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'review-skip-pass: OK'; then ok "R37.$i SPECOPS_ROOT=[$form] → 통과"; else no "R37.$i" "form=[$form] rc=$rc out=[$out]"; fi
done

echo "── test-reconcile-check: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
