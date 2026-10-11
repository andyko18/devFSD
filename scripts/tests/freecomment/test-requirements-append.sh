#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
HELPER="$PLUGIN/scripts/requirements-append-fr.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# fixture: requirements.md (FR-1~3 표 + NFR 섹션)
make_req() {
  cat > "$1" <<'EOF'
# 테스트 요구사항 설계서

## 2. 기능 요구사항 (FR)

| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | 기존 기능 1 | M1 | must | (TBD) |
| FR-2 | 기존 기능 2 | M1 | should | (TBD) |
| FR-3 | 기존 기능 3 | M2 | nice | (TBD) |

## 3. 비기능 요구사항 (NFR)

| ID | 항목 | 기준 | 검증 방법 |
|---|---|---|---|
| NFR-1 | 성능 | x | y |
EOF
}

# T1.a 기존 FR-3 뒤 → FR-4 채번 + append
req="$TMP/req-a.md"; make_req "$req"
out=$(bash "$HELPER" "$req" "새 자유작업 기능" --milestone M3 --priority should 2>&1)
if echo "$out" | grep -q 'APPENDED: FR-4' && grep -q '| FR-4 | 새 자유작업 기능 |' "$req"; then
  PASS=$((PASS+1)); echo "PASS T1.a FR-4 채번+append"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a (out=$out)"
fi

# T1.b NFR 표 무손상 (FR 표에만 삽입)
if grep -q '| NFR-1 | 성능 |' "$req" && [ "$(grep -c '^| FR-' "$req")" = "4" ]; then
  PASS=$((PASS+1)); echo "PASS T1.b NFR 무손상 + FR 4행"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b"
fi

# T1.c 멱등 — 동일 desc 재호출 → SKIP, 행 수 불변
out=$(bash "$HELPER" "$req" "새 자유작업 기능" --milestone M3 --priority should 2>&1)
if echo "$out" | grep -q 'SKIP' && [ "$(grep -c '^| FR-' "$req")" = "4" ]; then
  PASS=$((PASS+1)); echo "PASS T1.c 멱등 SKIP"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.c (out=$out)"
fi

# T1.d escape — desc 에 | 포함 → 표 구조 안 깨짐 (escape 후 1행만 추가)
req2="$TMP/req-d.md"; make_req "$req2"
bash "$HELPER" "$req2" "파이프 a | b 처리" --milestone M1 --priority must >/dev/null 2>&1
# 추가된 FR-4 행이 정확히 5컬럼 유지 (escape 로 | 가 셀 구분자로 안 샘)
fr4_line=$(grep '| FR-4 |' "$req2")
if grep -q 'FR-4' "$req2" && printf '%s' "$fr4_line" | grep -qF 'a \| b'; then
  PASS=$((PASS+1)); echo "PASS T1.d escape (| → \\|)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.d (line=$fr4_line)"
fi

# T1.f 채번 — FR-10 존재 시 FR-11 (문자열 정렬 회귀 방지: sort -n)
req3="$TMP/req-f.md"; make_req "$req3"
# FR-10 행 주입 (FR-3 뒤)
sed -i.bak 's/| FR-3 | 기존 기능 3 | M2 | nice | (TBD) |/| FR-3 | 기존 기능 3 | M2 | nice | (TBD) |\
| FR-10 | 열 번째 | M1 | must | (TBD) |/' "$req3" && rm -f "$req3.bak"
out=$(bash "$HELPER" "$req3" "열한 번째" --milestone M1 --priority must 2>&1)
if echo "$out" | grep -q 'APPENDED: FR-11'; then
  PASS=$((PASS+1)); echo "PASS T1.f 채번 FR-10→FR-11 (수치정렬)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.f (out=$out)"
fi

# T1.e req-path 부재 → exit 1
bash "$HELPER" "$TMP/nonexistent.md" "x" >/dev/null 2>&1
if [ "$?" -ne 0 ]; then
  PASS=$((PASS+1)); echo "PASS T1.e 부재 exit 1"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.e"
fi

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
