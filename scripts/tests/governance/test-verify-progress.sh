#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
. "$PLUGIN/hooks/governance-lib.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; mkdir -p .specops
sp=".specops/session-progress.md"

# T1: verify PASS 최신(위) > /implement → 유효(0)
cat > "$sp" <<'EOF'
## 20260625-x · 기능
- 2026-06-25 16:36 /verify PASS (evidence.md, AC 12/12)
- 2026-06-25 16:34 /implement DONE (T1~T5)
EOF
_verify_passed_in_progress 20260625-x && { PASS=$((PASS+1)); echo "PASS T1 verify최신→유효"; } || { FAIL=$((FAIL+1)); echo "FAIL T1"; }

# T2: /implement 가 verify 보다 최신(위) → 무효(1)
cat > "$sp" <<'EOF'
## 20260625-x · 기능
- 2026-06-25 16:40 /implement DONE (재구현)
- 2026-06-25 16:36 /verify PASS (AC 12/12)
EOF
_verify_passed_in_progress 20260625-x && { FAIL=$((FAIL+1)); echo "FAIL T2"; } || { PASS=$((PASS+1)); echo "PASS T2 implement최신→무효"; }

# T3: verify 없음 → 무효(1)
cat > "$sp" <<'EOF'
## 20260625-x · 기능
- 2026-06-25 16:34 /implement DONE
EOF
_verify_passed_in_progress 20260625-x && { FAIL=$((FAIL+1)); echo "FAIL T3"; } || { PASS=$((PASS+1)); echo "PASS T3 verify없음→무효"; }

# T4: 무수정 리뷰(신규 0)는 코드변경 아님 → verify 유효(0)
cat > "$sp" <<'EOF'
## 20260625-x · 기능
- 2026-06-25 16:37 /receive-review 완료 (Critical 0, 신규 0)
- 2026-06-25 16:36 /verify PASS (AC 12/12)
EOF
_verify_passed_in_progress 20260625-x && { PASS=$((PASS+1)); echo "PASS T4 무수정리뷰→유효"; } || { FAIL=$((FAIL+1)); echo "FAIL T4"; }

# T5: 수정흔적 리뷰(fix 1라운드)가 verify 보다 최신 → 무효(1)
cat > "$sp" <<'EOF'
## 20260625-x · 기능
- 2026-06-25 16:38 /receive-review 완료 (Important 1 수용, fix 1라운드)
- 2026-06-25 16:36 /verify PASS (AC 12/12)
EOF
_verify_passed_in_progress 20260625-x && { FAIL=$((FAIL+1)); echo "FAIL T5"; } || { PASS=$((PASS+1)); echo "PASS T5 수정리뷰최신→무효"; }

# T7(I-2): verify 줄 memo 에 "/implement" 문자열 있어도 명령앵커로 무시 → verify 유효(0)
cat > "$sp" <<'EOF'
## 20260625-x · 기능
- 2026-06-25 16:36 /verify PASS (/implement 단계 검증)
EOF
_verify_passed_in_progress 20260625-x && { PASS=$((PASS+1)); echo "PASS T7 memo명령언급무시→유효"; } || { FAIL=$((FAIL+1)); echo "FAIL T7"; }

# T6: session-progress 부재 → 무효(1, fallback)
rm -f "$sp"
_verify_passed_in_progress 20260625-x && { FAIL=$((FAIL+1)); echo "FAIL T6"; } || { PASS=$((PASS+1)); echo "PASS T6 부재→무효"; }

# === _verify_evidence_stamp (AC-2/4) ===
mkdir -p .specops/test-fid
_verify_evidence_stamp test-fid && { FAIL=$((FAIL+1)); echo "FAIL: AC-4 stamp 부재 면제됨"; } || PASS=$((PASS+1))
printf 'RUN-VERIFICATION-RESULT: PASS\n' > .specops/test-fid/evidence.md
_verify_evidence_stamp test-fid && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: AC-2 PASS stamp 면제"; }
printf 'RUN-VERIFICATION-RESULT: FAIL\n' > .specops/test-fid/evidence.md
_verify_evidence_stamp test-fid && { FAIL=$((FAIL+1)); echo "FAIL: AC-4 FAIL stamp 면제됨"; } || PASS=$((PASS+1))
rm -rf .specops/test-fid

# 구조화 상태가 있으면 이를 우선하고, 코드 변경으로 STALE이면 PASS stamp가 남아도 면제하지 않는다.
STATE_GIT="$TMP/state-git"
mkdir -p "$STATE_GIT"; git -C "$STATE_GIT" init -q
printf 'base\n' > "$STATE_GIT/app.sh"
git -C "$STATE_GIT" add app.sh
git -C "$STATE_GIT" -c user.name=test -c user.email=test@example.com commit -qm init
mkdir -p "$STATE_GIT/.specops/20260803-governance"
(cd "$STATE_GIT" && bash "$PLUGIN/scripts/_internal/verification-state.sh" record 20260803-governance PASS)
(cd "$STATE_GIT" && _verify_evidence_stamp 20260803-governance) \
  && { PASS=$((PASS+1)); echo "PASS T-state 구조화 PASS 면제"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T-state 구조화 PASS 불인정"; }
printf 'changed\n' >> "$STATE_GIT/app.sh"
(cd "$STATE_GIT" && _verify_evidence_stamp 20260803-governance) \
  && { FAIL=$((FAIL+1)); echo "FAIL T-state STALE이 PASS로 면제됨"; } \
  || { PASS=$((PASS+1)); echo "PASS T-state STALE 면제 거부"; }

# === 3-state affirmative-stale 보존 (T39 정합) ===
mkdir -p .specops/stale-fid
printf '## stale-fid\n- 2026-06-26 10:10 /implement DONE (재구현)\n- 2026-06-26 10:05 /verify PASS (AC 5/5)\n' >> .specops/session-progress.md
printf 'RUN-VERIFICATION-RESULT: PASS\n' > .specops/stale-fid/evidence.md
_verify_passed_in_progress stale-fid; vp=$?
[ "$vp" -eq 2 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: 3-state affirmative-stale return 2 아님 (vp=$vp)"; }
rm -rf .specops/stale-fid

# === H2: 타임스탬프 비교 — 줄 순서와 타임스탬프 불일치 케이스 ===
# T-H2a: implement 물리적 위 + verify 타임스탬프 더 최신 → allow (구 코드=deny, 신 코드=allow)
cat > "$sp" <<'EOF'
## 20260701-h2a
- 2026-07-01 10:00 /implement DONE (T1)
- 2026-07-01 10:05 /verify PASS (AC 5/5)
EOF
_verify_passed_in_progress 20260701-h2a && { PASS=$((PASS+1)); echo "PASS T-H2a implement물리적위+verify타임스탬프최신→allow"; } || { FAIL=$((FAIL+1)); echo "FAIL T-H2a (줄순서가 아닌 타임스탬프 기준 판정 실패)"; }

# T-H2b: verify 물리적 위 + implement 타임스탬프 더 최신 → deny (구 코드=allow, 신 코드=deny)
cat > "$sp" <<'EOF'
## 20260701-h2b
- 2026-07-01 10:36 /verify PASS (AC 5/5)
- 2026-07-01 10:40 /implement DONE (재구현)
EOF
_verify_passed_in_progress 20260701-h2b; vp=$?
[ "$vp" -eq 2 ] && { PASS=$((PASS+1)); echo "PASS T-H2b verify물리적위+implement타임스탬프최신→deny(stale)"; } || { FAIL=$((FAIL+1)); echo "FAIL T-H2b (vp=$vp, 줄순서 우선 false-allow 회귀)"; }

# T-H2c: 동일 타임스탬프 → deny (tie = safe-side stale)
cat > "$sp" <<'EOF'
## 20260701-h2c
- 2026-07-01 10:05 /verify PASS (AC 5/5)
- 2026-07-01 10:05 /implement DONE (T1)
EOF
_verify_passed_in_progress 20260701-h2c; vp=$?
[ "$vp" -eq 2 ] && { PASS=$((PASS+1)); echo "PASS T-H2c 동일타임스탬프→deny(tie=safe-side)"; } || { FAIL=$((FAIL+1)); echo "FAIL T-H2c (vp=$vp, tie 동률 안전측 deny 실패)"; }

# === R6: log_friction_sev 대칭화 (AC-1~3) ===
# T8: log_friction_sev 잘못된 fid 형식 → 거부(non-zero) (AC-2)
log_friction_sev "../evil" R-1 '"P1"' "snippet" 0 warn 2>/dev/null \
  && { FAIL=$((FAIL+1)); echo "FAIL T8 잘못된 fid 면제됨"; } \
  || { PASS=$((PASS+1)); echo "PASS T8 잘못된 fid 거부"; }

# T9: _specops_fid_dir_safe 빈 fid → 통과(0) (AC-1)
_specops_fid_dir_safe "" \
  && { PASS=$((PASS+1)); echo "PASS T9 빈 fid 통과"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T9 빈 fid 거부됨"; }

# T10: per-FID 디렉토리 symlink → log_friction_sev 거부 (AC-3)
mkdir -p "$TMP/ext-target"
ln -s "$TMP/ext-target" ".specops/20260630-symtest"
log_friction_sev "20260630-symtest" R-1 '"P1"' "s" 0 warn 2>/dev/null \
  && { FAIL=$((FAIL+1)); echo "FAIL T10 per-FID symlink 면제됨"; } \
  || { PASS=$((PASS+1)); echo "PASS T10 per-FID symlink 거부"; }
rm -f ".specops/20260630-symtest"

# T10b: per-FID 디렉토리 symlink → log_friction 도 거부 (AC-3 — 양 함수 대칭)
mkdir -p "$TMP/ext-target2"
ln -s "$TMP/ext-target2" ".specops/20260630-symtest2"
log_friction "20260630-symtest2" R-1 '"P1"' "s" 0 2>/dev/null \
  && { FAIL=$((FAIL+1)); echo "FAIL T10b log_friction per-FID symlink 면제됨"; } \
  || { PASS=$((PASS+1)); echo "PASS T10b log_friction per-FID symlink 거부"; }
rm -f ".specops/20260630-symtest2"

# T11: log_friction_sev 정상 fid + 정상 dir → append 성공(0) (AC-R-2 대칭)
log_friction_sev "20260630-okfid" R-1 '"P1"' "ok" 0 warn \
  && { PASS=$((PASS+1)); echo "PASS T11 정상 fid append"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T11 정상 fid 거부됨"; }

# === N1: apply_lookback _vp=2(stale)+stamp → 차단 유지 불변식 (AC-4) ===
# 프로덕션 코드 무변경 — 기존 L229 차단 로직 회귀 잠금(characterization).
_rule='{"id":"R-1","trigger_tool":"Bash","trigger_pattern":"git commit","negative_lookback":20,"negative_skill_pattern":"verifying-evidence"}'
printf '' > "$TMP/empty-transcript.jsonl"

# T12: _vp=2(stale — implement 가 verify 보다 최신=상단) + stamp → 면제 안 함(차단 JSON 출력)
# 불변식(governance-lib.sh L49/L57): 최신=상단(작은 줄번호). stale 유도 = implement 를 verify 위에 배치.
cat > "$sp" <<'PROG'
<!-- active-fid: 20260630-staletest -->
## 20260630-staletest
- 2026-06-30 11:00 /implement DONE (T1)
- 2026-06-30 10:00 /verify PASS (evidence.md)
PROG
mkdir -p ".specops/20260630-staletest"
printf 'RUN-VERIFICATION-RESULT: PASS\n' > ".specops/20260630-staletest/evidence.md"
out=$(apply_lookback_rule "$_rule" "$TMP/empty-transcript.jsonl" "Bash" "git commit -m x")
if [ -n "$out" ]; then
  PASS=$((PASS+1)); echo "PASS T12 vp=2+stamp 차단 유지"
else
  FAIL=$((FAIL+1)); echo "FAIL T12 vp=2+stamp 면제됨(stale stamp 우회)"
fi

# T13: _vp=1(verify 줄 부재) + stamp → 면제(빈 출력) 보존 — 대조군
cat > "$sp" <<'PROG'
<!-- active-fid: 20260630-incltest -->
## 20260630-incltest
- 2026-06-30 11:00 /implement DONE (T1)
PROG
mkdir -p ".specops/20260630-incltest"
printf 'RUN-VERIFICATION-RESULT: PASS\n' > ".specops/20260630-incltest/evidence.md"
out=$(apply_lookback_rule "$_rule" "$TMP/empty-transcript.jsonl" "Bash" "git commit -m x")
if [ -z "$out" ]; then
  PASS=$((PASS+1)); echo "PASS T13 vp=1+stamp 면제 보존"
else
  FAIL=$((FAIL+1)); echo "FAIL T13 vp=1+stamp 차단됨(면제 회귀)"
fi

# === _receipt_window_open (AC-1, FR-1) — verdict 6종 진리표 ===
# 왜 이 함수인가: 종전 창 조건은 `evidence.md 부재` 였다. /verify 가 아니라 **구현 중 태스크**가
#   그 파일을 쓰면 남은 태스크의 receipt 경로가 스스로 닫혔다(20260910 실측 — BYPASS 2건).
_RWO_SB=$(mktemp -d) || exit 1
mkdir -p "$_RWO_SB/.specops/20260910-x"
: > "$_RWO_SB/.specops/20260910-x/tasks.md"
_rwo_case() {   # $1=verdict $2=기대rc $3=라벨
  cat > "$_RWO_SB/.specops/20260910-x/verification-state.json" <<JSON
{"verdict":"$1","tree_hash":"NO_GIT","executed":1,"skipped":0,"failed":0}
JSON
  if [ "$1" = "WAIVED" ]; then
    cat > "$_RWO_SB/.specops/20260910-x/verification-state.json" <<JSON
{"verdict":"WAIVED","tree_hash":"NO_GIT","waiver":{"reason":"r","approved_by":"a","expires_at":"2099-01-01T00:00:00Z"}}
JSON
  fi
  (cd "$_RWO_SB" && _receipt_window_open 20260910-x); local got=$?
  if [ "$got" -eq "$2" ]; then PASS=$((PASS+1)); echo "PASS T-rwo.$3 $1 → rc=$2"
  else FAIL=$((FAIL+1)); echo "FAIL T-rwo.$3 $1 → rc=$got (기대 $2)"; fi
}
_rwo_case NOT_RUN 0 a
_rwo_case PARTIAL 0 b
_rwo_case FAIL    0 c
_rwo_case PASS    1 d
_rwo_case WAIVED  1 e
# STALE: verdict=PASS 인데 기록 tree_hash 가 현재와 다르면 vs::current 가 STALE 을 낸다.
#   NO_GIT 은 vs::current 가 STALE 판정에서 제외하므로 실제 해시를 심어야 한다(가짜 값이면 STALE).
cat > "$_RWO_SB/.specops/20260910-x/verification-state.json" <<'JSON'
{"verdict":"PASS","tree_hash":"0000000000000000000000000000000000000000","executed":1,"skipped":0,"failed":0}
JSON
(cd "$_RWO_SB" && git init -q . 2>/dev/null; _receipt_window_open 20260910-x); _rwo_rc=$?
[ "$_rwo_rc" -eq 1 ] && { PASS=$((PASS+1)); echo "PASS T-rwo.f STALE → rc=1 (닫힘)"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T-rwo.f STALE → rc=$_rwo_rc (기대 1)"; }
# 빈 FID → 닫힘 (보수)
_receipt_window_open "" && { FAIL=$((FAIL+1)); echo "FAIL T-rwo.g 빈 FID 열림"; } \
  || { PASS=$((PASS+1)); echo "PASS T-rwo.g 빈 FID → 닫힘"; }

# === FR-7 캐시 공유 — _verify_evidence_stamp 가 같은 FID 캐시를 재사용한다 ===
# 왜: vs::current 는 PASS 경로에서 write-tree 를 돌려 ~109 ms. 훅 hot path 에서 2회 호출 금지.
_VS_VERDICT_CACHE_FID="20260910-x"; _VS_VERDICT_CACHE="PASS"
(cd "$_RWO_SB" && rm -f .specops/20260910-x/verification-state.json
 cat > .specops/20260910-x/verification-state.json <<'JSON'
{"verdict":"FAIL","tree_hash":"NO_GIT","executed":1,"skipped":0,"failed":1}
JSON
 _verify_evidence_stamp 20260910-x) \
  && { PASS=$((PASS+1)); echo "PASS T-rwo.h 캐시(PASS) 재사용 — 디스크 FAIL 무시"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T-rwo.h 캐시 미재사용"; }
# 다른 FID 면 캐시를 쓰지 않는다 (오염 차단)
_VS_VERDICT_CACHE_FID="other-fid"; _VS_VERDICT_CACHE="PASS"
(cd "$_RWO_SB" && _verify_evidence_stamp 20260910-x) \
  && { FAIL=$((FAIL+1)); echo "FAIL T-rwo.i 타 FID 캐시 오염"; } \
  || { PASS=$((PASS+1)); echo "PASS T-rwo.i 타 FID 캐시 무시 — 디스크 FAIL 반영"; }
_VS_VERDICT_CACHE_FID=""; _VS_VERDICT_CACHE=""

# === FR-7 캐시 **쓰기** 경로 — 창 판정이 실제로 캐시를 채운다 ===
# 왜 톱레벨 호출인가: 위 진리표는 `( cd … && _receipt_window_open … )` 서브셸이라 캐시 대입이
#   호출자로 전파되지 않는다. h·i 는 캐시를 손으로 세팅해 **읽기** 쪽만 쟀고, 그래서 쓰기 경로가
#   프로덕션에서 한 번도 동작하지 않는데도 green 이었다(Phase C I-1 — 공허한 테스트).
# 캐시를 먼저 비운다 — h·i 의 잔여값이 남으면 이 단언이 항상통과로 위장된다.
cat > "$_RWO_SB/.specops/20260910-x/verification-state.json" <<'JSON'
{"verdict":"FAIL","tree_hash":"NO_GIT","executed":1,"skipped":0,"failed":1}
JSON
_VS_VERDICT_CACHE=""; _VS_VERDICT_CACHE_FID=""
cd "$_RWO_SB" || { echo "FAIL T-rwo.j cd 실패"; exit 1; }
_receipt_window_open 20260910-x; _rwo_wrc=$?
cd "$TMP" || { echo "FAIL T-rwo.j cd 복귀 실패"; exit 1; }
# FID 만 보면 하드코딩 대입도 통과한다 — verdict 값까지 함께 단언한다.
if [ "$_rwo_wrc" -eq 0 ] && [ "${_VS_VERDICT_CACHE_FID:-}" = "20260910-x" ] \
   && [ "${_VS_VERDICT_CACHE:-}" = "FAIL" ]; then
  PASS=$((PASS+1)); echo "PASS T-rwo.j 창 판정이 캐시를 채운다(FID+verdict)"
else
  FAIL=$((FAIL+1))
  echo "FAIL T-rwo.j 캐시 미기록 — rc=$_rwo_wrc fid='${_VS_VERDICT_CACHE_FID:-}' verdict='${_VS_VERDICT_CACHE:-}'"
fi
_VS_VERDICT_CACHE_FID=""; _VS_VERDICT_CACHE=""
rm -rf "$_RWO_SB"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
