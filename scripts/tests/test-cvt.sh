#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CVT="$PLUGIN/scripts/cvt.py"


TMP=$(mktemp -d /tmp/cvt-test-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

echo '{"name":"Alice","age":30}' > "$TMP/valid.json"
printf 'name: Alice\nage: 30\n'  > "$TMP/valid.yaml"
echo 'not { valid json'          > "$TMP/bad.json"

# T1.a: --to 누락 → exit 2 (AC-5)
python3 "$CVT" "$TMP/valid.json" > /dev/null 2>&1; CODE=$?
[ "$CODE" -eq 2 ] && ok "T1.a --to 누락 exit 2" || fail "T1.a (expected 2, got $CODE)"

# T2.a: 파일 인자 JSON → YAML exit 0 (AC-1)
OUT_FILE=$(python3 "$CVT" --to yaml "$TMP/valid.json" 2>/dev/null); CODE=$?
[ "$CODE" -eq 0 ] && ok "T2.a exit 0" || fail "T2.a (expected 0, got $CODE)"

# T2.b: stdout 이 유효한 YAML (AC-1)
echo "$OUT_FILE" | python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)" 2>/dev/null \
  && ok "T2.b stdout valid YAML" || fail "T2.b stdout not valid YAML"

# T2.c: stdin 파이프 JSON → YAML (AC-3)
OUT_PIPE=$(python3 "$CVT" --to yaml < "$TMP/valid.json" 2>/dev/null); CODE=$?
[ "$CODE" -eq 0 ] && ok "T2.c stdin pipe exit 0" || fail "T2.c stdin (expected 0, got $CODE)"

# T2.c-2: stdin 파이프 출력이 파일 인자 출력과 동일 (AC-3)
[ "$OUT_PIPE" = "$OUT_FILE" ] && ok "T2.c-2 stdin pipe content == file arg output" \
  || fail "T2.c-2 stdin output differs: pipe='$OUT_PIPE' file='$OUT_FILE'"

# T2.d: 정상 변환 시 stderr 없음 (AC-8)
ERR=$(python3 "$CVT" --to yaml "$TMP/valid.json" 2>&1 1>/dev/null)
[ -z "$ERR" ] && ok "T2.d stderr empty" || fail "T2.d stderr not empty: $ERR"

# T3.a: 파일 인자 YAML → JSON exit 0 (AC-2)
OUT=$(python3 "$CVT" --to json "$TMP/valid.yaml" 2>/dev/null); CODE=$?
[ "$CODE" -eq 0 ] && ok "T3.a YAML→JSON exit 0" || fail "T3.a (expected 0, got $CODE)"

# T3.b: stdout 이 유효한 JSON (AC-2)
echo "$OUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null \
  && ok "T3.b stdout valid JSON" || fail "T3.b stdout not valid JSON"

# T4.a: 깨진 JSON → exit 1 (AC-4)
python3 "$CVT" --to yaml "$TMP/bad.json" > /dev/null 2>&1; CODE=$?
[ "$CODE" -eq 1 ] && ok "T4.a bad JSON exit 1" || fail "T4.a (expected 1, got $CODE)"

# T4.b: 깨진 JSON → stderr ParseError: (AC-4)
ERR=$(python3 "$CVT" --to yaml "$TMP/bad.json" 2>&1 1>/dev/null)
echo "$ERR" | grep -q "^ParseError:" && ok "T4.b stderr ParseError:" || fail "T4.b: $ERR"

# T4.c: 빈 JSON 입력 → exit 1 (AC-6)
echo -n "" | python3 "$CVT" --to yaml > /dev/null 2>&1; CODE=$?
[ "$CODE" -eq 1 ] && ok "T4.c empty JSON→YAML exit 1" || fail "T4.c (expected 1, got $CODE)"

# T4.d: 빈 JSON 입력 → stderr ParseError: (AC-6)
ERR=$(echo -n "" | python3 "$CVT" --to yaml 2>&1 1>/dev/null)
echo "$ERR" | grep -q "^ParseError:" && ok "T4.d stderr ParseError:" || fail "T4.d: $ERR"

# T4.e: 빈 YAML 입력 → JSON → exit 1 (AC-9)
echo -n "" | python3 "$CVT" --to json > /dev/null 2>&1; CODE=$?
[ "$CODE" -eq 1 ] && ok "T4.e empty YAML→JSON exit 1" || fail "T4.e (expected 1, got $CODE)"

# T4.f: 빈 YAML 입력 → JSON → stderr ParseError: (AC-9)
ERR=$(echo -n "" | python3 "$CVT" --to json 2>&1 1>/dev/null)
echo "$ERR" | grep -q "^ParseError:" && ok "T4.f stderr ParseError:" || fail "T4.f: $ERR"

# T5.a: --indent 4 적용 확인 (AC-7, should)
OUT=$(python3 "$CVT" --to json --indent 4 "$TMP/valid.yaml" 2>/dev/null)
SECOND=$(printf '%s\n' "$OUT" | sed -n '2p')
case "$SECOND" in
    "    "*) ok "T5.a --indent 4 applied" ;;
    *) fail "T5.a indent not 4: '$SECOND'" ;;
esac

# T5.b: --indent 4 출력이 유효한 JSON
echo "$OUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null \
  && ok "T5.b --indent 4 valid JSON" || fail "T5.b not valid JSON"

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
