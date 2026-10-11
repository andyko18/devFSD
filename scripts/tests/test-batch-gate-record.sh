#!/usr/bin/env bash
# batch 레벨 게이트(Step A/B/C) verdict 전파 — 20260806 /start-all 정밀분석
#
# 결함: Phase 3 완료 Step A/B/C(security·integration·performance)는 batch 전체를 **1회**
#   실행하고, 각 skill 은 `.specops/<FID>/evidence.md` — 즉 **호출된 대표 FID 1곳** — 에만
#   verdict 를 append 한다. 그런데 v1.60 RELEASE_READY 는 `gh pr create` 시 ACTIVE batch 의
#   **전 IMPL_DONE FID** 각각에 security/integration/performance = PASS|SKIP 을 요구한다
#   (하나라도 MISSING → NOT_READY → **hard deny**, 인라인 BYPASS 불가).
#   → 정직한 /start-all 완주가 구조적으로 batch PR 에서 막힌다 (F1 과 동류의 설계 간 충돌).
# 수정: record-batch-gate.sh 가 batch verdict 를 전 IMPL_DONE FID 의 evidence.md 로 전파.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
REC="$PLUGIN/scripts/_internal/record-batch-gate.sh"
RR="$PLUGIN/scripts/_internal/release-ready.sh"
STATE="$PLUGIN/scripts/_internal/verification-state.sh"

_mk_batch() {  # $1=dir — batch(2 FID IMPL_DONE) + 대표 FID1 에만 게이트 기록된 정직한 흐름
  local d="$1"
  mkdir -p "$d/.specops/batch-20260806-0900" "$d/src"
  printf 'x\n' > "$d/src/a.sh"
  (cd "$d" && git init -q && git add src && git -c user.name=t -c user.email=t@e.com commit -qm init)
  cat > "$d/.specops/batch-20260806-0900/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260806-fr-one | one | IMPL_DONE |
| FR-2 | 20260806-fr-two | two | IMPL_DONE |
EOF
  : > "$d/.specops/batch-20260806-0900/ACTIVE"
  local fid
  for fid in 20260806-fr-one 20260806-fr-two; do
    mkdir -p "$d/.specops/$fid/reviews"
    printf '# tasks\n' > "$d/.specops/$fid/tasks.md"
    printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$d/.specops/$fid/evidence.md"
    cat > "$d/.specops/$fid/dispatch-log.md" <<'DL'
| # | 시각 | Phase | agent | 결과 | feedback |
|---|---|---|---|---|---|
| 1 | ts | B:T1 | spec-reviewer-ko | PASS | reviews/T1-B-report.md |
| 2 | ts | C:T1 | code-reviewer-ko | PASS | reviews/T1-C-report.md |
DL
    printf '# B\nREADY_TO_MERGE\n' > "$d/.specops/$fid/reviews/T1-B-report.md"
    printf '# C\nREADY_TO_MERGE\n' > "$d/.specops/$fid/reviews/T1-C-report.md"
    printf 'end-loaded: covered\n' > "$d/.specops/$fid/review-skip.md"
    (cd "$d" && bash "$STATE" record "$fid" PASS --executed 1) >/dev/null
  done
  # 실제 Phase 3 흐름과 동일한 진행 줄 — requesting-code-review-ko 가 /request-review 를 남긴다
  # (없으면 reconcile 이 증거 frontier(review-skip.md) > 기록 frontier 로 DESYNC 를 낸다)
  printf '<!-- active-fid: 20260806-fr-two -->\n## 20260806-fr-one\n- 2026-08-06 10:00 /verify PASS\n- 2026-08-06 10:05 /request-review 완료 "review-skip.md (end-loaded)"\n## 20260806-fr-two\n- 2026-08-06 11:00 /verify PASS\n- 2026-08-06 11:05 /request-review 완료 "review-skip.md (end-loaded)"\n' \
    > "$d/.specops/session-progress.md"
  # 대표 FID(fr-one)에만 batch 게이트 3종 기록 — 현행 Step A/B/C 실동작
  cat >> "$d/.specops/20260806-fr-one/evidence.md" <<'EOF'

## /security-review PASS
**결과**: PASS

## /integration-test PASS
**결과**: PASS

## /performance-test SKIP
**결과**: SKIP
EOF
}

# T1: ★ 버그 실증 — 대표 아닌 FID(fr-two)는 게이트 MISSING → NOT_READY
TD=$(mktemp -d); _mk_batch "$TD"
out=$(cd "$TD" && bash "$RR" 20260806-fr-two 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'security=MISSING' \
  && ok "T1 배경 실증 — 비대표 FID NOT_READY(security=MISSING)" || nope "T1" "rc=$rc out=$out"
rm -rf "$TD"

# T2: record-batch-gate — batch verdict 를 전 IMPL_DONE FID 로 전파
TD=$(mktemp -d); _mk_batch "$TD"
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" security PASS) >/dev/null 2>&1
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" integration PASS) >/dev/null 2>&1
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" performance SKIP "NFR 없음 §requirements L1") >/dev/null 2>&1
out=$(cd "$TD" && bash "$RR" 20260806-fr-two 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'RELEASE_READY: OK' \
  && ok "T2 전파 후 비대표 FID READY" || nope "T2" "rc=$rc out=$out"
rm -rf "$TD"

# T3: 멱등 — 재실행해도 섹션 중복 없음
TD=$(mktemp -d); _mk_batch "$TD"
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" security PASS) >/dev/null 2>&1
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" security PASS) >/dev/null 2>&1
n=$(grep -c '^## /security-review' "$TD/.specops/20260806-fr-two/evidence.md")
[ "$n" -eq 1 ] && ok "T3 멱등 — 중복 섹션 없음" || nope "T3" "n=$n"
rm -rf "$TD"

# T4: 대표 FID(이미 기록됨)는 건드리지 않음 — 기존 섹션 보존 + 중복 없음
TD=$(mktemp -d); _mk_batch "$TD"
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" security PASS) >/dev/null 2>&1
n=$(grep -c '^## /security-review' "$TD/.specops/20260806-fr-one/evidence.md")
[ "$n" -eq 1 ] && ok "T4 대표 FID 기존 기록 보존(중복 0)" || nope "T4" "n=$n"
rm -rf "$TD"

# T5: FAIL verdict 는 전파 거부 — FAIL 은 systematic-debugging 후 재실행이 정도이지
#     전 FID 로 낙인 찍는 것이 아니다 (사용 오류 방지)
TD=$(mktemp -d); _mk_batch "$TD"
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" security FAIL) >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ! grep -q 'security-review FAIL' "$TD/.specops/20260806-fr-two/evidence.md" \
  && ok "T5 FAIL 전파 거부" || nope "T5" "rc=$rc"
rm -rf "$TD"

# T6: SKIP 은 근거 필수 (skip-tracker CITED 규약 정합)
TD=$(mktemp -d); _mk_batch "$TD"
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" performance SKIP) >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "T6 SKIP 무근거 거부" || nope "T6" "rc=$rc"
rm -rf "$TD"

# T7: queue 부재·IMPL_DONE 0건 → 오류 (조용한 no-op 금지)
TD=$(mktemp -d); mkdir -p "$TD/.specops/batch-x"
(cd "$TD" && bash "$REC" ".specops/batch-x" security PASS) >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "T7 queue 부재 → 오류" || nope "T7" "rc=$rc"
rm -rf "$TD"

# T8: start-all.md 배선 — Step A/B/C 가 전파 스크립트를 지시 (게이트 3종 각각)
_t8=0
for g in security integration performance; do
  grep -E "record-batch-gate\.sh .* $g " "$PLUGIN/commands/start-all.md" >/dev/null 2>&1 || _t8=1
done
[ "$_t8" -eq 0 ] && ok "T8 start-all Step A/B/C 배선(게이트 3종)" || nope "T8" "게이트별 배선 누락"

# ── T9: Status 라벨 장식 흡수 (FID 20260828-queue-label-drift) ──
#   계기: argus batch-20260729 — 모델이 `**IMPL_DONE**` 로 손편집하자 이 스크립트의
#   `|IMPL_DONE|` 리터럴 매칭이 전건 불일치 → "IMPL_DONE FID 0건" exit 1.
#   Step A/B/C 를 정상 수행해도 verdict 전파가 실패해 batch PR 이 막힌다.
TN=$(mktemp -d); trap 'rm -rf "$TN"' EXIT
_mk_batch "$TN"
# Status 를 굵게 표기로 오염시킨다 (모델 손편집 재현)
sed -i.bak 's/| IMPL_DONE |/| **IMPL_DONE** |/' "$TN/.specops/batch-20260806-0900/queue.md"
out=$(cd "$TN" && bash "$REC" ".specops/batch-20260806-0900" security PASS 2>&1); rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'IMPL_DONE FID 0건'; then
  ok "T9 **IMPL_DONE** 손편집에도 전 FID 전파 (정규화)"
else
  nope "T9 라벨 장식 미흡수" "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ')"
fi
# 전파가 실제로 됐는지 — 두 FID evidence 모두에 기록돼야 한다 (0건 무음 통과 구분)
_t9b=0
for fid in 20260806-fr-one 20260806-fr-two; do
  grep -q 'security' "$TN/.specops/$fid/evidence.md" 2>/dev/null || _t9b=1
done
[ "$_t9b" -eq 0 ] && ok "T9.b 전파 실측 — 2 FID evidence 모두 기록" \
  || nope "T9.b 전파 누락" "대상 0건 무음 통과 의심"

# ── T10~T13: SKIP 근거 형식 · 보완 · 전파 현황 (20261009-startall-tail) ──
#   쓰는 쪽(record-batch-gate)은 아무 근거나 받고, 읽는 쪽(release-ready)은 줄 번호 인용이 없으면 BARE 로 거부했다.
#   start-all.md 의 예시(`[SKIP근거]`)는 형식을 말하지 않아, 문서대로 하면 기록은 되는데 batch PR 이 hard deny 됐다.
#   한 번 기록되면 "기존 기록 보존" 이라 다시 불러도 고쳐지지 않았다(실측 20261008).

# T10: 인용 없는 근거는 쓰는 시점에 거부한다 — 형식과 예시를 알려 준다
TD=$(mktemp -d); _mk_batch "$TD"
out=$(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" integration SKIP "통합 표면 없음 — CLI 단일 프로세스" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ! grep -q 'integration-test SKIP' "$TD/.specops/20260806-fr-two/evidence.md" \
  && printf '%s' "$out" | grep -q 'L12' \
  && ok "T10 ★ 줄 번호 인용 없는 SKIP 근거 → 기록 전에 거부(예시 안내)" || nope "T10" "rc=$rc out=$out"
out=$(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" integration SKIP "§범위 L12-15 — 통합 표면 없음" 2>&1); rc=$?
rr=$(cd "$TD" && bash "$RR" 20260806-fr-two 2>&1)
[ "$rc" -eq 0 ] && grep -q '§범위 L12-15' "$TD/.specops/20260806-fr-two/evidence.md" \
  && ! printf '%s' "$rr" | grep -q 'BARE:.*integration' \
  && ok "T10b 인용 있는 근거 → 기록 · release-ready 가 BARE 로 보지 않는다" || nope "T10b" "rc=$rc rr=$(printf '%s' "$rr" | tr '\n' ' ')"
rm -rf "$TD"

# T11: 이미 기록된 인용 없는 SKIP 은 인용 있는 근거로 다시 부르면 보완된다(종전 근거는 남긴다)
TD=$(mktemp -d); _mk_batch "$TD"
cat >> "$TD/.specops/20260806-fr-two/evidence.md" <<'EOF'

## /integration-test SKIP
**결과**: SKIP
**근거**: 통합 표면 없음
**출처**: batch batch-20260806-0900 Step 게이트 1회 실행 — record-batch-gate.sh 전파
EOF
before=$(cd "$TD" && bash "$RR" 20260806-fr-two 2>&1)
out=$(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" integration SKIP "§범위 L12-15 — 통합 표면 없음" 2>&1); rc=$?
after=$(cd "$TD" && bash "$RR" 20260806-fr-two 2>&1)
n=$(grep -c '^## /integration-test' "$TD/.specops/20260806-fr-two/evidence.md")
printf '%s' "$before" | grep -q 'BARE:.*integration' && [ "$rc" -eq 0 ] && [ "$n" -eq 1 ] \
  && ! printf '%s' "$after" | grep -q 'BARE:.*integration' \
  && grep -q '^\*\*종전 근거\*\*: 통합 표면 없음' "$TD/.specops/20260806-fr-two/evidence.md" \
  && printf '%s' "$out" | grep -q '보완' \
  && ok "T11 ★ 인용 없는 기존 SKIP → 다시 부르면 근거 보완(섹션 1개 유지 · 종전 근거 보존)" \
  || nope "T11" "rc=$rc n=$n out=$out after=$(printf '%s' "$after" | tr '\n' ' ')"
#   인용이 이미 있는 기록·PASS 기록은 건드리지 않는다(대표 FID 원본 보존)
h1=$(cksum < "$TD/.specops/20260806-fr-one/evidence.md")
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" security PASS) >/dev/null 2>&1
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" integration SKIP "§범위 L1 — 다른 근거") >/dev/null 2>&1
h2=$(cksum < "$TD/.specops/20260806-fr-one/evidence.md")
[ "$h1" = "$h2" ] && ! grep -q '다른 근거' "$TD/.specops/20260806-fr-two/evidence.md" \
  && ok "T11b 인용 있는 SKIP·PASS 기록은 불변(멱등 유지)" || nope "T11b" "대표 FID 또는 보완된 기록이 바뀜"
rm -rf "$TD"

# T12: status — 전 IMPL_DONE FID 의 게이트 3종 현황. 빠졌거나 인용이 없으면 rc 1 로 닫지 못하게 한다
#   실기록(20261008): batch 6건 중 2건이 전파 없이 닫히거나 멈췄다. PR 게이트는 `gh pr create` 에서만 돌아
#   로컬 병합으로 닫으면 한 번도 평가되지 않는다 — 닫기 직전에 직접 묻는 수단이 필요하다.
TD=$(mktemp -d); _mk_batch "$TD"
out=$(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" status 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '20260806-fr-two' && printf '%s' "$out" | grep -q 'security=MISSING' \
  && printf '%s' "$out" | grep -q 'performance=SKIP(BARE)' && printf '%s' "$out" | grep -q 'INCOMPLETE' \
  && ok "T12 status: 미전파(MISSING)·근거 미인용(BARE) → rc 1 + FID·게이트별 현황" || nope "T12" "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ')"
h1=$(cd "$TD" && find .specops -type f | sort | xargs cksum | cksum)
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" status) >/dev/null 2>&1
h2=$(cd "$TD" && find .specops -type f | sort | xargs cksum | cksum)
[ "$h1" = "$h2" ] && ok "T12b status 는 읽기 전용(파일 무변경)" || nope "T12b" "status 가 파일을 바꿈"
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" security PASS) >/dev/null 2>&1
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" integration PASS) >/dev/null 2>&1
(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" performance SKIP "§NFR L8-12 — 성능 임계값 없음") >/dev/null 2>&1
out=$(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" status 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'BATCH-GATE-STATUS: OK' && ! printf '%s' "$out" | grep -q 'MISSING\|BARE' \
  && ok "T12c 전파·보완 뒤 status → rc 0 (대표 FID 의 인용 없는 SKIP 도 보완됨)" || nope "T12c" "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ')"
rm -rf "$TD"

# T13: evidence.md 가 없는 IMPL_DONE FID 는 status 가 따로 알린다(전파할 곳이 없다)
TD=$(mktemp -d); _mk_batch "$TD"; rm -f "$TD/.specops/20260806-fr-two/evidence.md"
out=$(cd "$TD" && bash "$REC" ".specops/batch-20260806-0900" status 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '20260806-fr-two.*evidence.md 부재' \
  && ok "T13 status: evidence.md 부재 FID 를 밝힌다" || nope "T13" "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ')"
rm -rf "$TD"

# ── T14~T17: 독립 리뷰가 찾은 구멍 (20261009) ──
B=".specops/batch-20260806-0900"

# T14: 보완은 **그 게이트의 인용 없는 SKIP** 만 건드린다 — 판정 파서와 같은 우선순위로 본다
TD=$(mktemp -d); _mk_batch "$TD"
cat >> "$TD/.specops/20260806-fr-two/evidence.md" <<'EOF'

## /integration-test PASS
**결과**: PASS (SKIP 0건)
**근거**: 모두 통과

## /security-review SKIP
**결과**: SKIP
**근거**: 표면 없음

## 메모
- 이 절은 게이트가 아니다
**근거**: 손대면 안 되는 줄
EOF
h1=$(cksum < "$TD/.specops/20260806-fr-two/evidence.md")
out=$(cd "$TD" && bash "$REC" "$B" integration SKIP "§범위 L12-15 — x" 2>&1); rc=$?
h2=$(cksum < "$TD/.specops/20260806-fr-two/evidence.md")
[ "$rc" -eq 0 ] && [ "$h1" = "$h2" ] \
  && ok "T14a ★ PASS 섹션(본문에 'SKIP' 글자) · 다른 게이트의 인용 없는 SKIP · 비게이트 절 → 불변" \
  || nope "T14a" "rc=$rc out=$out — $(grep -n '근거' "$TD/.specops/20260806-fr-two/evidence.md" | tr '\n' ' ')"
(cd "$TD" && bash "$REC" "$B" security SKIP "§범위 L3 — 표면 없음") >/dev/null 2>&1
grep -q '^\*\*근거\*\*: 모두 통과' "$TD/.specops/20260806-fr-two/evidence.md" \
  && grep -q '^\*\*근거\*\*: 손대면 안 되는 줄' "$TD/.specops/20260806-fr-two/evidence.md" \
  && grep -q '^\*\*근거\*\*: §범위 L3 — 표면 없음' "$TD/.specops/20260806-fr-two/evidence.md" \
  && grep -q '^\*\*종전 근거\*\*: 표면 없음' "$TD/.specops/20260806-fr-two/evidence.md" \
  && ok "T14b 해당 게이트(security)를 부르면 그 섹션만 보완 · 앞뒤 섹션의 근거 줄은 그대로" || nope "T14b" "$(grep -n '근거' "$TD/.specops/20260806-fr-two/evidence.md" | tr '\n' ' ')"
rm -rf "$TD"

# T15: 근거 글자는 보완 경로에서도 그대로 남는다(awk -v 는 `\1`·`\\`·`\t` 를 해석해 바꿨다) · 줄바꿈은 거부
TD=$(mktemp -d); _mk_batch "$TD"
R='§범위 L12 — a&b \1 \\n /x/ %s $0 "q" \t 끝'
(cd "$TD" && bash "$REC" "$B" performance SKIP "$R") >/dev/null 2>&1
grep -qF "**근거**: $R" "$TD/.specops/20260806-fr-one/evidence.md" && grep -qF "**근거**: $R" "$TD/.specops/20260806-fr-two/evidence.md" \
  && ok "T15a 역슬래시·&·%·\$0 가 든 근거 → 보완 경로(fr-one)와 신규 경로(fr-two) 모두 원문 그대로" \
  || nope "T15a" "one=$(grep -n '^\*\*근거' "$TD/.specops/20260806-fr-one/evidence.md" | tr '\n' ' ')"
h1=$(cd "$TD" && find .specops -type f | sort | xargs cksum | cksum)
out=$(cd "$TD" && bash "$REC" "$B" integration SKIP "$(printf '§범위 L1 — 첫 줄\n## /security-review PASS')" 2>&1); rc=$?
h2=$(cd "$TD" && find .specops -type f | sort | xargs cksum | cksum)
[ "$rc" -ne 0 ] && [ "$h1" = "$h2" ] && printf '%s' "$out" | grep -q '줄바꿈' \
  && ok "T15b 줄바꿈이 든 근거 → 거부(가짜 섹션 주입 불가 · 파일 무변경)" || nope "T15b" "rc=$rc out=$out"
rm -rf "$TD"

# T16: status 의 rc 는 사유마다 따로 성립한다(한 사유가 다른 사유의 검사를 가려 주지 않게 fixture 를 나눈다)
TD=$(mktemp -d); _mk_batch "$TD"
(cd "$TD" && bash "$REC" "$B" performance SKIP "§NFR L8-12 — 임계값 없음") >/dev/null 2>&1
out=$(cd "$TD" && bash "$REC" "$B" status 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '누락 2 · 근거 미인용 0 · FAIL 0 · evidence 부재 0 · FID 미기재 0' \
  && ok "T16a status: MISSING 만 있어도 rc 1 (BARE 없음)" || nope "T16a" "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ')"
(cd "$TD" && bash "$REC" "$B" security PASS && bash "$REC" "$B" integration PASS) >/dev/null 2>&1
rm -f "$TD/.specops/20260806-fr-two/evidence.md"
out=$(cd "$TD" && bash "$REC" "$B" status 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '누락 0 · 근거 미인용 0 · FAIL 0 · evidence 부재 1' \
  && ok "T16b status: evidence.md 부재만 있어도 rc 1" || nope "T16b" "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ')"
rm -rf "$TD"
#   IMPL_DONE 인데 FID 칸이 TBD 인 행 — 확인할 수 없는 FR 을 "OK" 에 섞지 않는다
TD=$(mktemp -d); _mk_batch "$TD"
(cd "$TD" && bash "$REC" "$B" security PASS && bash "$REC" "$B" integration PASS && bash "$REC" "$B" performance SKIP "§NFR L8-12 — x") >/dev/null 2>&1
printf '| FR-3 | TBD | three | IMPL_DONE |\n' >> "$TD/$B/queue.md"
out=$(cd "$TD" && bash "$REC" "$B" status 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'FID 미기재 1' && printf '%s' "$out" | grep -q 'IMPL_DONE 행 3개 중 1개' \
  && ok "T16c status: FID 칸이 TBD 인 IMPL_DONE 행 → rc 1 (OK 로 가리지 않는다)" || nope "T16c" "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ')"
rm -rf "$TD"
#   FAIL 판정은 사유로 집계된다
TD=$(mktemp -d); _mk_batch "$TD"
(cd "$TD" && bash "$REC" "$B" security PASS && bash "$REC" "$B" performance SKIP "§NFR L8-12 — x") >/dev/null 2>&1
printf '\n## /integration-test FAIL\n**결과**: FAIL\n' >> "$TD/.specops/20260806-fr-two/evidence.md"
out=$(cd "$TD" && bash "$REC" "$B" status 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'integration=FAIL' && printf '%s' "$out" | grep -q 'FAIL 1' \
  && ok "T16d status: FAIL 판정 → rc 1 + 사유 집계" || nope "T16d" "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ')"
rm -rf "$TD"

# T17: 헤더만 있고 판정이 없는 섹션은 기록이 아니다 — 전파하면 채워진다(종전: "이미 있다" 며 영구히 MISSING)
TD=$(mktemp -d); _mk_batch "$TD"
printf '\n## /security-review\n(작성 중)\n' >> "$TD/.specops/20260806-fr-two/evidence.md"
(cd "$TD" && bash "$REC" "$B" security PASS) >/dev/null 2>&1
out=$(cd "$TD" && bash "$RR" 20260806-fr-two 2>&1)
printf '%s' "$out" | grep -q 'security=PASS' \
  && ok "T17 판정 없는 헤더뿐인 섹션 → 전파가 판정을 채운다" || nope "T17" "$(printf '%s' "$out" | tr '\n' ' ')"
rm -rf "$TD"

finish
