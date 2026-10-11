#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$PLUGIN/scripts/show-fid-status.sh"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# T1 — AC-1: 잘못된 FID 형식 → stderr 오류 + exit 1
stdout_out=$("$SCRIPT" "invalid" 2>/dev/null); rc=$?
stderr_out=$("$SCRIPT" "invalid" 2>&1 1>/dev/null)
if [ "$rc" -ne 0 ] && [ -z "$stdout_out" ] && [ -n "$stderr_out" ]; then
  PASS=$((PASS+1)); echo "PASS T1 invalid-fid-format"
else
  FAIL=$((FAIL+1)); echo "FAIL T1 (rc=$rc stdout='$stdout_out' stderr='$stderr_out')"
fi

# T2 — AC-2: 올바른 FID 형식이지만 디렉토리 없음 → exit 1
stdout_out=$("$SCRIPT" "20991231-nonexistent" 2>/dev/null); rc=$?
stderr_out=$("$SCRIPT" "20991231-nonexistent" 2>&1 1>/dev/null)
if [ "$rc" -ne 0 ] && [ -z "$stdout_out" ] && [ -n "$stderr_out" ]; then
  PASS=$((PASS+1)); echo "PASS T2 fid-dir-missing"
else
  FAIL=$((FAIL+1)); echo "FAIL T2 (rc=$rc stdout='$stdout_out' stderr='$stderr_out')"
fi

# T3 — AC-3: 디렉토리 + session-progress 섹션 존재 → exit 0 + FID 헤더 + 이력
T3_FID="20260101-test-feature"
mkdir -p "$TMPDIR_TEST/.specops/$T3_FID"
T3_PROGRESS="$TMPDIR_TEST/.specops/session-progress.md"
printf '## %s · test feature\n\n- 2026-01-01T00:00:00Z /specify 완료 (spec.md)\n' "$T3_FID" > "$T3_PROGRESS"

out=$(SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$T3_FID" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "$T3_FID" && printf '%s' "$out" | grep -q "/specify"; then
  PASS=$((PASS+1)); echo "PASS T3 lifecycle-stages-output"
else
  FAIL=$((FAIL+1)); echo "FAIL T3 (rc=$rc out='$out')"
fi

# T4 — AC-4: spec.md 있음, plan.md 없음 → ✅ / ❌ 표시
T4_FID="20260102-test-artifacts"
mkdir -p "$TMPDIR_TEST/.specops/$T4_FID"
touch "$TMPDIR_TEST/.specops/$T4_FID/spec.md"
printf '## %s\n\n- 2026-01-02T00:00:00Z /specify 완료\n' "$T4_FID" >> "$T3_PROGRESS"

out=$(SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$T4_FID" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "✅ spec.md" && printf '%s' "$out" | grep -qF "❌ plan.md"; then
  PASS=$((PASS+1)); echo "PASS T4 artifact-check-display"
else
  FAIL=$((FAIL+1)); echo "FAIL T4 (rc=$rc out='$out')"
fi

# T5 — AC-5: 디렉토리 있지만 session-progress에 섹션 없음 → exit 0 + "(진행 이력 없음)"
T5_FID="20260103-no-history"
mkdir -p "$TMPDIR_TEST/.specops/$T5_FID"

out=$(SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$T5_FID" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "진행 이력 없음"; then
  PASS=$((PASS+1)); echo "PASS T5 no-history"
else
  FAIL=$((FAIL+1)); echo "FAIL T5 (rc=$rc out='$out')"
fi

# T6 — reconcile: session-progress 는 /tasks 인데 dispatch-log(implement) + evidence.md(verify)
#   증거 존재 → DESYNC 경고 + 진짜 frontier 보고 (20260718-status-reconcile, dogfood test1 FR-3)
T6_FID="20260104-stalled"
mkdir -p "$TMPDIR_TEST/.specops/$T6_FID"
printf '## %s · stalled feature\n\n- 2026-01-04T00:00:00Z /tasks 완료 (tasks.md)\n' "$T6_FID" >> "$T3_PROGRESS"
touch "$TMPDIR_TEST/.specops/$T6_FID/spec.md" "$TMPDIR_TEST/.specops/$T6_FID/plan.md" "$TMPDIR_TEST/.specops/$T6_FID/tasks.md"
printf '| 1 | ts | A:T1 | implementer-ko | DONE | x |\n' > "$TMPDIR_TEST/.specops/$T6_FID/dispatch-log.md"
printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$TMPDIR_TEST/.specops/$T6_FID/evidence.md"
out=$(SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$T6_FID" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qiE 'DESYNC|불일치|과소보고' \
   && printf '%s' "$out" | grep -qi 'verify' && printf '%s' "$out" | grep -qi 'tasks'; then
  PASS=$((PASS+1)); echo "PASS T6 reconcile-desync 경고 (기록<증거)"
else
  FAIL=$((FAIL+1)); echo "FAIL T6 (rc=$rc out='$out')"
fi

# T7 — reconcile: 기록 frontier == 증거 frontier → DESYNC 경고 없음 (오탐 0)
T7_FID="20260105-aligned"
mkdir -p "$TMPDIR_TEST/.specops/$T7_FID"
printf '## %s · aligned\n\n- 2026-01-05T00:00:00Z /verify PASS (evidence.md)\n- 2026-01-05T00:00:00Z /implement DONE\n' "$T7_FID" >> "$T3_PROGRESS"
touch "$TMPDIR_TEST/.specops/$T7_FID/spec.md" "$TMPDIR_TEST/.specops/$T7_FID/plan.md" "$TMPDIR_TEST/.specops/$T7_FID/tasks.md"
printf '| 1 | ts | A:T1 | implementer-ko | DONE | x |\n' > "$TMPDIR_TEST/.specops/$T7_FID/dispatch-log.md"
printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$TMPDIR_TEST/.specops/$T7_FID/evidence.md"
out=$(SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$T7_FID" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qiE 'DESYNC|불일치|과소보고'; then
  PASS=$((PASS+1)); echo "PASS T7 reconcile-정합 (경고 없음)"
else
  FAIL=$((FAIL+1)); echo "FAIL T7 (rc=$rc out='$out')"
fi

# T8 — reconcile: 재개 힌트(다음 단계) 제시
out=$(SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$T6_FID" 2>&1)
if printf '%s' "$out" | grep -qiE '재개|다음|resume|권장'; then
  PASS=$((PASS+1)); echo "PASS T8 reconcile-재개 힌트"
else
  FAIL=$((FAIL+1)); echo "FAIL T8 (out='$out')"
fi

# T9 — 유지보수 흐름: /analyze 단계 인식 (20260718 실측 결함 — dogfood test2 scanner-blockcomment-fix)
#   analyze 완료 + current-state/impact-analysis 산출물만 있는 상태 = 정합(경고 없음).
#   구버전은 사다리에 analyze 부재 → recorded=0·evidence=0 우연정합 + '기록: -' 오라벨.
T9_FID="20260106-maint-analyze"
mkdir -p "$TMPDIR_TEST/.specops/$T9_FID"
printf '## %s · maint\n\n- 2026-01-06T00:00:00Z /analyze 완료 (current-state.md, impact-analysis.md)\n' "$T9_FID" >> "$T3_PROGRESS"
touch "$TMPDIR_TEST/.specops/$T9_FID/current-state.md" "$TMPDIR_TEST/.specops/$T9_FID/impact-analysis.md"
out=$(SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$T9_FID" 2>&1); rc=$?
# reconcile 섹션만 스코프 (상단 이력 echo 의 analyze 로 인한 tautology 차단)
recon=$(printf '%s' "$out" | sed -n '/reconcile/,$p')
if [ "$rc" -eq 0 ] && ! printf '%s' "$recon" | grep -qiE 'DESYNC|과소보고' \
   && printf '%s' "$recon" | grep -qi 'analyze'; then
  PASS=$((PASS+1)); echo "PASS T9 analyze 단계 인식 (유지보수 정합·경고 0)"
else
  FAIL=$((FAIL+1)); echo "FAIL T9 (rc=$rc recon='$recon')"
fi

# T10 — 유지보수 흐름 desync: analyze 기록인데 spec.md 존재(specify 미기록) → DESYNC + 재개 specify
T10_FID="20260107-maint-desync"
mkdir -p "$TMPDIR_TEST/.specops/$T10_FID"
printf '## %s · maint2\n\n- 2026-01-07T00:00:00Z /analyze 완료 (current-state.md)\n' "$T10_FID" >> "$T3_PROGRESS"
touch "$TMPDIR_TEST/.specops/$T10_FID/current-state.md" "$TMPDIR_TEST/.specops/$T10_FID/impact-analysis.md" "$TMPDIR_TEST/.specops/$T10_FID/spec.md"
out=$(SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$T10_FID" 2>&1); rc=$?
recon=$(printf '%s' "$out" | sed -n '/reconcile/,$p')
# 기록 frontier 가 analyze 로 라벨돼야 함 ('기록 frontier: analyze' — 구버전은 '-')
if [ "$rc" -eq 0 ] && printf '%s' "$recon" | grep -qiE 'DESYNC|과소보고' \
   && printf '%s' "$recon" | grep -qiE '기록 frontier: analyze'; then
  PASS=$((PASS+1)); echo "PASS T10 analyze→specify 미기록 desync + 기록 frontier=analyze"
else
  FAIL=$((FAIL+1)); echo "FAIL T10 (rc=$rc recon='$recon')"
fi


# === 단계 소요 표 (20260911-stage-timing-derive) ===
_TS_FID=20260911-tsfix
mkdir -p "$TMPDIR_TEST/.specops/$_TS_FID"
# 원장은 **역순**(최신 우선)으로 쓰인다 — 정렬 없이 계산하면 음수가 나온다.
# 자정 경계(23:59 → 00:09)를 일부러 포함한다 — 직전 FID 에 실재하는 형태다.
cat > "$TMPDIR_TEST/.specops/session-progress.md" <<TSEOF
<!-- active-fid: $_TS_FID -->
## $_TS_FID
- 2026-09-11 00:09 /security-review DONE (x)
- 2026-09-10 23:59 /verify PASS (x)
- 2026-09-10 21:09 /implement DONE (x)
- 2026-09-10 20:12 /implement 진행 (x)
- 2026-09-10 19:12 /specify 완료 (x)
TSEOF
out=$(SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$_TS_FID" 2>&1)

# AC-1: 인접 구간이 나온다 (specify→implement 60m · implement→implement 57m
#       · implement→verify 170m · verify→security-review 10m)
# ★ 출력 전체를 grep 하면 **공허하다** — `/specify`·`/implement` 토큰은 소요 표 위의
#   '진행 이력' 섹션에 이미 있어서, 소요 표가 통째로 없어도 통과한다(T1 구현자 실측:
#   RED 에서 이 케이스만 PASS). 소요 표 섹션으로 스코프를 좁히고 화살표 쌍을 요구한다.
_ts_sec=$(printf '%s\n' "$out" | awk '/^## 단계 소요/{f=1} f && /^## 아티팩트/{exit} f')
if printf '%s' "$_ts_sec" | grep -qE '/specify +→ +/implement'; then
  PASS=$((PASS+1)); echo "PASS T-ts.a 소요 표에 단계 쌍 출력"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.a 단계 쌍 없음"; fi

# AC-5: 자정 경계 — 23:59 → 00:09 는 10m 이어야 한다 (음수·거대값 금지)
if printf '%s' "$out" | grep -qE '/verify +→ +/security-review +10m'; then
  PASS=$((PASS+1)); echo "PASS T-ts.b 자정 경계 10m"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.b 자정 경계: $(printf '%s' "$out" | grep -E '/verify.*security' || echo '(행 없음)')"; fi

# AC-8: 60분 미만 = Nm · 이상 = XhYm
if printf '%s' "$out" | grep -qE '/implement +→ +/implement +57m'; then
  PASS=$((PASS+1)); echo "PASS T-ts.c 60분 미만 = 57m"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.c 57m 표기"; fi
if printf '%s' "$out" | grep -qE '/implement +→ +/verify +2h50m'; then
  PASS=$((PASS+1)); echo "PASS T-ts.d 60분 이상 = 2h50m"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.d 2h50m 표기: $(printf '%s' "$out" | grep -E '/implement.*verify' || echo '(행 없음)')"; fi
# 경계값 정확히 60분 → 1h0m (specify 19:12 → implement 20:12)
if printf '%s' "$out" | grep -qE '/specify +→ +/implement +1h0m'; then
  PASS=$((PASS+1)); echo "PASS T-ts.e 경계 60분 = 1h0m"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.e 1h0m 표기"; fi

# AC-7: 플래그 없이 기본 출력 + 헤더가 측정 기준·해상도·경과시간 단서를 말한다
if printf '%s' "$out" | grep -q '인접 행 차이' \
   && printf '%s' "$out" | grep -q '분 해상도' \
   && printf '%s' "$out" | grep -q '경과 시간'; then
  PASS=$((PASS+1)); echo "PASS T-ts.f 헤더가 측정 기준·해상도·경과시간 명시"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.f 헤더 단서 누락"; fi

# AC-4: 행 1건 → 표 생략 + 사유 1줄 (빈 표 금지)
_TS1=20260911-tsone
mkdir -p "$TMPDIR_TEST/.specops/$_TS1"
cat > "$TMPDIR_TEST/.specops/session-progress.md" <<TS1EOF
## $_TS1
- 2026-09-11 00:09 /analyze 완료 (x)
TS1EOF
out1=$(SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$_TS1" 2>&1)
if printf '%s' "$out1" | grep -q '구간 없음'; then
  PASS=$((PASS+1)); echo "PASS T-ts.g 1행 → 표 생략 + 사유"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.g 1행 처리"; fi
# AC-4 는 "0행·1행 2종" 을 요구한다 — 0행도 잠근다(진행 이력 자체가 없는 FID).
_TS0=20260911-tszero
mkdir -p "$TMPDIR_TEST/.specops/$_TS0"
: > "$TMPDIR_TEST/.specops/session-progress.md"
out0=$(SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$_TS0" 2>&1)
if printf '%s' "$out0" | grep -q '구간 없음'; then
  PASS=$((PASS+1)); echo "PASS T-ts.g0 0행 → 표 생략 + 사유"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.g0 0행 처리"; fi

# === 측정 불가 구간 (20260911-stage-timing-derive Task 2) ===
# ★ 원장을 **다시 쓴다** — Task 1 의 T-ts.g·T-ts.g0 이 같은 경로를
#   (`$TMPDIR_TEST/.specops/session-progress.md`) 1행·0행으로 덮어썼다. 재작성 없이
#   `$_TS_FID` 를 다시 돌리면 섹션이 없어 T-ts.h·T-ts.j 가 **GREEN 에서도 FAIL** 한다
#   (plan-reviewer 실측: `PASS=20 FAIL=3`). 픽스처는 Task 1 선두와 동일 내용이다.
cat > "$TMPDIR_TEST/.specops/session-progress.md" <<TS2EOF
<!-- active-fid: $_TS_FID -->
## $_TS_FID
- 2026-09-11 00:09 /security-review DONE (x)
- 2026-09-10 23:59 /verify PASS (x)
- 2026-09-10 21:09 /implement DONE (x)
- 2026-09-10 20:12 /implement 진행 (x)
- 2026-09-10 19:12 /specify 완료 (x)
TS2EOF

# AC-3: fid-start 기록이 없으면 첫 단계 이전 구간을 '측정 불가'로 **명시**한다.
#   0m·공백으로 두면 "첫 단계는 즉시 끝났다"로 오독된다 — 계기판이 거짓말하면 안 된다.
out2=$(SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$_TS_FID" 2>&1)
# ★ 소요 표 섹션으로 스코프를 좁히고, 기대 branch 를 **같은 행**으로 고정한다.
#   `측정 불가` 를 내는 branch 는 3개(시각 불일치·ts 파싱 실패·fid-start 미기록)라
#   전체 grep 이면 (c) 대신 (b) 로 잘못 빠져도 통과한다. `$out` 이 아니라 `$out2` 에서
#   새로 추출해야 한다 — T1 의 `_ts_sec` 를 재사용하면 T1 출력을 단언하게 된다.
_ts_sec2=$(printf '%s\n' "$out2" | awk '/^## 단계 소요/{f=1} f && /^## 아티팩트/{exit} f')
if printf '%s' "$_ts_sec2" | grep 'FID 시작' | grep -q '측정 불가'; then
  PASS=$((PASS+1)); echo "PASS T-ts.h fid-start 부재 → 측정 불가 명시"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.h 측정 불가 표기 없음"; fi
# 그 구간을 0m 으로 내지 않는다 (음성 단언 — 양성 대조는 위 T-ts.b~e 가 담당)
# plan-reviewer 적발: 초안은 `'이전 +0m'` 을 봤는데 출력에 `이전` 토큰이 없어 **공허**했다.
#   실제 출력 행(`(FID 시작) → …`)을 한정해서 본다.
if printf '%s' "$out2" | grep 'FID 시작' | grep -qE ' 0m'; then
  FAIL=$((FAIL+1)); echo "FAIL T-ts.i 측정 불가 구간을 0m 으로 표기"
else PASS=$((PASS+1)); echo "PASS T-ts.i 0m 오표기 없음"; fi
# fid-start 가 있으면 그 구간이 실제 값으로 나온다
# ★ TZ 를 **비UTC로 고정**해 오프셋 결함을 노출시킨다. 둘 다 UTC 인 픽스처는 결함을 가린다
#   (plan-reviewer 실측: UTC 픽스처는 통과하는데 실 시계로는 5m 이 9h5m 으로 나왔다).
#   fid-start 는 UTC(record-metric 계약), 원장 행은 로컬(session-progress 계약)이다.
#   TZ=Asia/Seoul(+0900) 에서 로컬 19:12 = UTC 10:12 이므로, 30m 전은 UTC 09:42 다.
mkdir -p "$TMPDIR_TEST/.specops/$_TS_FID"
printf '{"ts":"2026-09-10T09:42:00Z","fid":"%s","phase":"fid-start","schema_version":2}\n' "$_TS_FID" \
  > "$TMPDIR_TEST/.specops/$_TS_FID/metrics.jsonl"
out3=$(TZ=Asia/Seoul SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$_TS_FID" 2>&1)
if printf '%s' "$out3" | grep -qE 'fid-start +→ +/specify +30m'; then
  PASS=$((PASS+1)); echo "PASS T-ts.j fid-start 있으면 첫 구간 측정"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.j 첫 구간: $(printf '%s' "$out3" | grep -E 'fid-start' || echo '(행 없음)')"; fi
# TZ 보정이 빠지면 +0900 만큼 틀린다 — 그 값을 음성 단언으로 직접 막는다(오프셋 회귀 잠금).
if printf '%s' "$out3" | grep -qE 'fid-start.*9h30m'; then
  FAIL=$((FAIL+1)); echo "FAIL T-ts.j2 TZ 오프셋 미보정 (9h30m)"
else PASS=$((PASS+1)); echo "PASS T-ts.j2 TZ 오프셋 보정됨"; fi
# AC-3/AC-4 경계: 원장 1행 + fid-start 기록 → **측정 가능한 구간이 1개 있다**.
#   종전 `_ts_n -lt 2` 게이트는 이 경우 표를 통째로 닫아 '구간 없음' 이라 **거짓말**했다
#   (T2 구현자 실측 발견). T3 이 진입 시점에 fid-start 를 기록하기 시작하면 신규 FID 의
#   첫 `/status` 마다 나오는 상태다. 아래 두 케이스가 게이트의 양쪽을 잠근다.
_TSG1=20260911-tsg1
mkdir -p "$TMPDIR_TEST/.specops/$_TSG1"
cat > "$TMPDIR_TEST/.specops/session-progress.md" <<TSG1EOF
<!-- active-fid: $_TSG1 -->
## $_TSG1
- 2026-09-11 09:30 /analyze 완료 (x)
TSG1EOF
printf '{"ts":"2026-09-11T00:00:00Z","fid":"%s","phase":"fid-start","schema_version":2}\n' "$_TSG1" \
  > "$TMPDIR_TEST/.specops/$_TSG1/metrics.jsonl"
outg1=$(TZ=Asia/Seoul SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$_TSG1" 2>&1)
_ts_secg1=$(printf '%s\n' "$outg1" | awk '/^## 단계 소요/{f=1} f && /^## 아티팩트/{exit} f')
if printf '%s' "$_ts_secg1" | grep -qE 'fid-start +→ +/analyze +30m'; then
  PASS=$((PASS+1)); echo "PASS T-ts.g1 1행+fid-start → 구간 1개 출력"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.g1 1행+fid-start: $(printf '%s' "$_ts_secg1" | tr '\n' '|')"; fi
# 그 경우 '구간 없음' 이라고 말하면 안 된다 (음성 단언 — 게이트가 닫혀 있으면 격추)
if printf '%s' "$_ts_secg1" | grep -q '구간 없음'; then
  FAIL=$((FAIL+1)); echo "FAIL T-ts.g2 측정 가능한 구간을 '구간 없음' 으로 보고"
else PASS=$((PASS+1)); echo "PASS T-ts.g2 '구간 없음' 오보 없음"; fi
# 반대쪽: 0행 + fid-start → 잴 대상(첫 행)이 없으므로 표를 열지 않는다.
#   열면 대상 칸이 빈 행이 찍힌다(advisor 적발 — hoist 로 도달 가능해진 상태).
_TSG3=20260911-tsg3
mkdir -p "$TMPDIR_TEST/.specops/$_TSG3"
: > "$TMPDIR_TEST/.specops/session-progress.md"
printf '{"ts":"2026-09-11T00:00:00Z","fid":"%s","phase":"fid-start","schema_version":2}\n' "$_TSG3" \
  > "$TMPDIR_TEST/.specops/$_TSG3/metrics.jsonl"
outg3=$(TZ=Asia/Seoul SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$_TSG3" 2>&1)
_ts_secg3=$(printf '%s\n' "$outg3" | awk '/^## 단계 소요/{f=1} f && /^## 아티팩트/{exit} f')
if printf '%s' "$_ts_secg3" | grep -q '구간 없음' \
   && ! printf '%s' "$_ts_secg3" | grep -q 'fid-start  *→'; then
  PASS=$((PASS+1)); echo "PASS T-ts.g3 0행+fid-start → 표 미개방 (빈 대상 행 없음)"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.g3 0행+fid-start: $(printf '%s' "$_ts_secg3" | tr '\n' '|')"; fi

# AC-9: 두 진입 경로 모두 fid-start 를 남긴다. 한쪽만 있으면 그 경로의 FID 는
#   첫 구간이 영구 미측정이 되어 AC-6 의 가치가 절반이다.
_ts_miss=0
for _sk in analyzing-ko specifying-ko; do
  if ! grep -q 'phase fid-start' "$PLUGIN/skills/$_sk/SKILL.md" 2>/dev/null; then
    _ts_miss=$((_ts_miss+1)); echo "  누락: skills/$_sk/SKILL.md"
  fi
done
if [ "$_ts_miss" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T-ts.k 두 진입 경로에 fid-start 지시 기재"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.k fid-start 지시 누락 ${_ts_miss}건"; fi

# === 첫 구간 branch 잠금 (Phase C 추가) — 같은 fixture 디렉토리를 재사용한다 ===
_TSC=20260911-tsc
mkdir -p "$TMPDIR_TEST/.specops/$_TSC"
_tsc_run() { # <TZ> <fid-start ts> → 소요 표 섹션
  cat > "$TMPDIR_TEST/.specops/session-progress.md" <<TSCEOF
## $_TSC
- 2026-09-10 11:00 /specify 완료 (x)
- 2026-09-10 10:00 /analyze 완료 (x)
TSCEOF
  printf '{"ts":"%s","fid":"%s","phase":"fid-start","schema_version":2}\n' "$2" "$_TSC" \
    > "$TMPDIR_TEST/.specops/$_TSC/metrics.jsonl"
  TZ="$1" SPECOPS_ROOT="$TMPDIR_TEST/.specops" "$SCRIPT" "$_TSC" 2>&1 \
    | awk '/^## 단계 소요/{f=1} f && /^## 아티팩트/{exit} f'
}
# AC-8 경계 60분 — 첫 구간에도 적용된다(M11 잠금: `-ge 60`→`-gt` 면 `60m` 이 나온다)
if _tsc_run UTC '2026-09-10T09:00:00Z' | grep -qE 'fid-start +→ +/analyze +1h0m'; then
  PASS=$((PASS+1)); echo "PASS T-ts.l 첫 구간 경계 60분 = 1h0m"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.l 첫 구간 60분 경계"; fi
# 음수 오프셋 TZ — 부호 처리(`_ts_zs`)가 빠지면 -0400 을 +0400 으로 읽어 8h 틀린다
if _tsc_run America/New_York '2026-09-10T12:00:00Z' | grep -qE 'fid-start +→ +/analyze +2h0m'; then
  PASS=$((PASS+1)); echo "PASS T-ts.m 음수 오프셋 TZ(-0400) 첫 구간 2h0m"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.m 음수 오프셋: $(_tsc_run America/New_York '2026-09-10T12:00:00Z' | grep fid-start)"; fi
# AC-3 branch (b): fid-start 가 첫 행보다 뒤 → 음수 분을 내지 않고 사유를 밝힌다
_tsc_neg=$(_tsc_run UTC '2026-09-10T11:30:00Z')
if printf '%s' "$_tsc_neg" | grep 'fid-start' | grep -q '측정 불가.*시각 불일치' \
   && ! printf '%s' "$_tsc_neg" | grep -qE 'fid-start.* -[0-9]+m'; then
  PASS=$((PASS+1)); echo "PASS T-ts.n fid-start 역전 → 측정 불가(시각 불일치)"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.n 역전 처리: $(printf '%s' "$_tsc_neg" | grep fid-start)"; fi
# AC-3 branch (c): ts 파싱 실패 → 행이 사라지지 않고 '파싱 실패' 를 밝힌다
_tsc_bad=$(_tsc_run UTC 'not-a-ts')
if printf '%s' "$_tsc_bad" | grep 'fid-start' | grep -q '측정 불가.*파싱 실패: not-a-ts'; then
  PASS=$((PASS+1)); echo "PASS T-ts.o fid-start ts 파싱 실패 → 측정 불가(파싱 실패)"
else FAIL=$((FAIL+1)); echo "FAIL T-ts.o 파싱 실패 처리: $(printf '%s' "$_tsc_bad" | grep fid-start)"; fi
# ── T-na: 인자 없는 조회 — 스크립트가 FID 를 정한다 ──────────────────────────
# 왜: 부트스트랩 직후 진행 기록의 최상단은 `<날짜>-init-project` 인데 그 디렉토리는 없다(init 은 FID 가 아니다).
#   종전에는 명령 문서가 "최상단 헤더를 뽑아 넘겨라" 고 했고, 그 값으로 부르면 Error·rc=1 이었다 —
#   플러그인을 처음 쓰는 사람이 /status 를 치면 오류부터 봤다.
_na="$TMPDIR_TEST/na"; mkdir -p "$_na/.specops"
# T-na.a: 진행 기록에 init-project 뿐 → 안내 + rc 0
printf '# Session Progress\n\n## 20261009-init-project\n\n- 2026-10-09 10:00 /init-project 완료 (부트스트랩)\n' > "$_na/.specops/session-progress.md"
out=$(SPECOPS_ROOT="$_na/.specops" "$SCRIPT" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '진행 중인 FID 가 없습니다' && printf '%s' "$out" | grep -q '/start'; then
  PASS=$((PASS+1)); echo "PASS T-na.a 인자 없음 + FID 없음 → 안내·rc 0"
else FAIL=$((FAIL+1)); echo "FAIL T-na.a (rc=$rc out='$out')"; fi
# T-na.b: 디렉토리가 있는 첫 FID 를 고른다 (디렉토리 없는 앞선 헤더는 건너뛴다)
mkdir -p "$_na/.specops/20261008-real-one"
printf '# Session Progress\n\n## 20261009-init-project\n\n- 2026-10-09 10:00 /init-project 완료 (x)\n\n## 20261008-real-one\n\n- 2026-10-08 09:00 /specify 완료 (spec.md)\n' > "$_na/.specops/session-progress.md"
out=$(SPECOPS_ROOT="$_na/.specops" "$SCRIPT" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '=== FID: 20261008-real-one ==='; then
  PASS=$((PASS+1)); echo "PASS T-na.b 인자 없음 → 디렉토리가 있는 첫 FID"
else FAIL=$((FAIL+1)); echo "FAIL T-na.b (rc=$rc out='$out')"; fi
# T-na.c: active-fid 표지가 있고 그 디렉토리가 있으면 표지가 우선
mkdir -p "$_na/.specops/20261007-marked"
printf '<!-- active-fid: 20261007-marked -->\n\n# Session Progress\n\n## 20261008-real-one\n\n- 2026-10-08 09:00 /specify 완료 (x)\n\n## 20261007-marked\n\n- 2026-10-07 09:00 /plan 완료 (x)\n' > "$_na/.specops/session-progress.md"
out=$(SPECOPS_ROOT="$_na/.specops" "$SCRIPT" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '=== FID: 20261007-marked ==='; then
  PASS=$((PASS+1)); echo "PASS T-na.c 인자 없음 → active-fid 표지 우선"
else FAIL=$((FAIL+1)); echo "FAIL T-na.c (rc=$rc out='$out')"; fi
# T-na.c2: 진행 기록이 없어도 FID 디렉토리가 있으면 이름이 가장 늦은 것을 고른다 ("없다" 고 하지 않는다)
_nb="$TMPDIR_TEST/nb"; mkdir -p "$_nb/.specops/20261001-older" "$_nb/.specops/20261009-newer" "$_nb/.specops/memory"
out=$(SPECOPS_ROOT="$_nb/.specops" "$SCRIPT" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '=== FID: 20261009-newer ==='; then
  PASS=$((PASS+1)); echo "PASS T-na.c2 진행 기록 없음 + FID 디렉토리 → 가장 늦은 FID"
else FAIL=$((FAIL+1)); echo "FAIL T-na.c2 (rc=$rc out='$out')"; fi
# T-na.d: .specops 자체가 없음 → 안내 + rc 0
out=$(SPECOPS_ROOT="$TMPDIR_TEST/none/.specops" "$SCRIPT" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'specops 미사용'; then
  PASS=$((PASS+1)); echo "PASS T-na.d .specops 부재 → 안내·rc 0"
else FAIL=$((FAIL+1)); echo "FAIL T-na.d (rc=$rc out='$out')"; fi
# T-na.e: 인자를 준 경우의 계약은 그대로 — 형식 오류·디렉토리 부재는 rc 1 (T1·T2 가 잠근 것과 같은 계약)
"$SCRIPT" "20261009-init-project" >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then
  PASS=$((PASS+1)); echo "PASS T-na.e 인자 명시 + 디렉토리 부재 → rc 1 유지"
else FAIL=$((FAIL+1)); echo "FAIL T-na.e (rc=$rc)"; fi
echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
