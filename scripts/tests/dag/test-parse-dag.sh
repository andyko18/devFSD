#!/usr/bin/env bash
# v0.4a W1 — parse-dag.sh 단위 테스트
# 6 fixture × 4 함수 검증 + malformed fallback
# 컨벤션: templates/test-conventions-bash.md (PASS=N FAIL=N 카운터)

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
FIXTURES="$PLUGIN/scripts/tests/dag/fixtures/tasks-md"

# shellcheck disable=SC1091
source "$PLUGIN/scripts/dag/parse-dag.sh"

# --- T1: extract_yaml ---
# T1.a — fixture 01에서 yaml block 추출 시 'tasks:' 라인 포함
yaml=$(dag::extract_yaml "$FIXTURES/01-two-leaves-disjoint.md")
if echo "$yaml" | grep -q "^tasks:"; then
  PASS=$((PASS+1)); echo "PASS T1.a extract_yaml fixture 01 → tasks: 라인 포함"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a — yaml=$yaml"
fi

# T1.b — fixture 03 (single leaf)
yaml=$(dag::extract_yaml "$FIXTURES/03-single-leaf.md")
if echo "$yaml" | grep -q "id: T1"; then
  PASS=$((PASS+1)); echo "PASS T1.b extract_yaml fixture 03 → id: T1 포함"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b"
fi

# T1.c — 헤더 부재 + tasks: 키 펜스 → 추출 성공 (AC-1)
#   후보가 1개뿐이면 stderr 는 비어 있어야 한다 — WARN 조건 `-gt 1` 잠금
#   (조건을 `-gt 0` 으로 느슨하게 바꾸면 여기서 잡힌다).
err=$(mktemp)
yaml=$(dag::extract_yaml "$FIXTURES/08-no-header.md" 2>"$err")
if printf '%s' "$yaml" | grep -q 'id: T1' && printf '%s' "$yaml" | grep -q 'test_command' \
   && [ ! -s "$err" ]; then
  PASS=$((PASS+1)); echo "PASS T1.c 헤더 부재 fixture → tasks: 펜스 채택 (stderr 무오염)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.c 헤더 부재 fixture 추출 실패 — stderr=$(cat "$err")"
fi
rm -f "$err"

# T1.d — 헤더 부재 + tasks: 키 없는 펜스 → 빈 출력 (AC-3 오탐 차단)
yaml=$(dag::extract_yaml "$FIXTURES/09-no-header-no-taskskey.md")
if [ -z "$yaml" ]; then
  PASS=$((PASS+1)); echo "PASS T1.d tasks: 키 없는 펜스는 미채택"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.d 무관 펜스를 DAG 로 오인"
fi

# T1.e — 후보 복수 → 첫 번째 채택 + stderr WARN, stdout 무오염 (AC-4)
#   WARN 은 **정확히 1회** — 줄 수가 아니라 등장 횟수로 센다 (한 줄에 2회 출력하는
#   변이는 `grep -c` 로는 잡히지 않는다).
err=$(mktemp)
yaml=$(dag::extract_yaml "$FIXTURES/10-no-header-multi.md" 2>"$err")
if printf '%s' "$yaml" | grep -q 'id: FIRST' \
   && ! printf '%s' "$yaml" | grep -q 'id: SECOND' \
   && [ "$(grep -o 'WARN' "$err" | wc -l | tr -d ' ')" -eq 1 ]; then
  PASS=$((PASS+1)); echo "PASS T1.e 복수 후보 → 첫 펜스 + stderr WARN 정확히 1회"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.e 복수 후보 처리"
fi
rm -f "$err"

# T1.f — 헤더 있으면 기존 경로 우선 (AC-2 회귀)
yaml=$(dag::extract_yaml "$FIXTURES/01-two-leaves-disjoint.md")
if printf '%s' "$yaml" | grep -q 'tasks:' && ! printf '%s' "$yaml" | grep -q '^## '; then
  PASS=$((PASS+1)); echo "PASS T1.f 헤더 경로 우선 유지"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.f 헤더 경로 회귀"
fi

# T1.g — 헤더 **앞**에도 tasks: 펜스가 있으면 헤더 섹션이 이긴다 (AC-2)
#   1단(`## 의존 그래프` awk)을 무력화하면 2단이 문서 첫 펜스(id: EARLY)를 집는다.
#   T1.f 의 fixture 는 tasks: 펜스가 하나뿐이라 1단/2단을 구분하지 못한다 — 이 케이스가 그 결손을 메운다.
err=$(mktemp)
yaml=$(dag::extract_yaml "$FIXTURES/11-header-with-early-fence.md" 2>"$err")
if printf '%s' "$yaml" | grep -q 'id: HEADER' \
   && ! printf '%s' "$yaml" | grep -q 'id: EARLY' \
   && [ ! -s "$err" ]; then
  PASS=$((PASS+1)); echo "PASS T1.g 헤더 앞 펜스 무시 → 헤더 섹션 블록 채택 (1단 우선 잠금)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.g 1단 우선 붕괴 — yaml=$(printf '%s' "$yaml" | tr '\n' '|') stderr=$(cat "$err")"
fi
rm -f "$err"

# T1.h — 골든 파일 무결성 (39 bytes)
#   골든은 펜스 끝 빈 줄 2개를 담는다. 편집기·lint 가 trailing 개행을 정규화하면
#   T1.i 가 애매하게 깨지므로, 여기서 먼저 loud 하게 잡는다.
GOLDEN="$PLUGIN/scripts/tests/dag/fixtures/golden/12-header-trailing-blank.yaml"
gsize=$(wc -c < "$GOLDEN" | tr -d ' ')
if [ "$gsize" -eq 39 ]; then
  PASS=$((PASS+1)); echo "PASS T1.h 골든 파일 39B 유지"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.h 골든 파일 ${gsize}B (기대 39B) — trailing 빈 줄 정규화 의심"
fi

# T1.i — 펜스 끝 빈 줄까지 바이트 동일 (AC-2)
#   $() 캡처는 검사 대상인 trailing 개행을 정확히 삭제하므로 **파일 리다이렉트**로 받는다.
#   1단을 처방 코드(out=$(awk …); printf '%s\n' "$out")로 되돌리면 개행 3 → 1 로 줄어 cmp 가 깨진다.
outf=$(mktemp)
dag::extract_yaml "$FIXTURES/12-header-trailing-blank.md" > "$outf" 2>/dev/null
if cmp -s "$outf" "$GOLDEN"; then
  PASS=$((PASS+1)); echo "PASS T1.i 펜스 끝 빈 줄 보존 → 골든과 바이트 동일"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.i 바이트 불일치 ($(wc -c < "$outf" | tr -d ' ')B vs 39B) — X sentinel 소실 의심"
fi
rm -f "$outf"

# --- T2: list_leaves ---
# T2.a — fixture 01 두 leaf
yaml=$(dag::extract_yaml "$FIXTURES/01-two-leaves-disjoint.md")
out=$(dag::list_leaves "$yaml" | sort | tr '\n' ',')
if [ "$out" = "T1,T2," ]; then
  PASS=$((PASS+1)); echo "PASS T2.a list_leaves fixture 01 → T1,T2"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.a (out=$out)"
fi

# T2.b — fixture 04 chain (T1만 절대 leaf)
yaml=$(dag::extract_yaml "$FIXTURES/04-chain.md")
out=$(dag::list_leaves "$yaml" | sort | tr '\n' ',')
if [ "$out" = "T1," ]; then
  PASS=$((PASS+1)); echo "PASS T2.b list_leaves fixture 04 → T1만"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.b (out=$out)"
fi

# T2.c — fixture 05 diamond (T1·T2 절대 leaf)
yaml=$(dag::extract_yaml "$FIXTURES/05-diamond.md")
out=$(dag::list_leaves "$yaml" | sort | tr '\n' ',')
if [ "$out" = "T1,T2," ]; then
  PASS=$((PASS+1)); echo "PASS T2.c list_leaves fixture 05 → T1,T2"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.c (out=$out)"
fi

# --- T3: outputs_disjoint ---
# T3.a — fixture 01 T1·T2 disjoint
yaml=$(dag::extract_yaml "$FIXTURES/01-two-leaves-disjoint.md")
if dag::outputs_disjoint "$yaml" T1 T2; then
  PASS=$((PASS+1)); echo "PASS T3.a outputs_disjoint fixture 01 T1·T2 → disjoint (exit 0)"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.a (exit $?)"
fi

# T3.b — fixture 02 T1·T2 overlap (같은 src/shared.sh 수정)
yaml=$(dag::extract_yaml "$FIXTURES/02-two-leaves-overlap.md")
if ! dag::outputs_disjoint "$yaml" T1 T2; then
  PASS=$((PASS+1)); echo "PASS T3.b outputs_disjoint fixture 02 T1·T2 → overlap (exit 1)"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.b — overlap 인데 disjoint 판정"
fi

# --- T4: find_independent_batch ---
# T4.a — fixture 01 → batch [T1, T2]
yaml=$(dag::extract_yaml "$FIXTURES/01-two-leaves-disjoint.md")
out=$(dag::find_independent_batch "$yaml" | sort | tr '\n' ',')
if [ "$out" = "T1,T2," ]; then
  PASS=$((PASS+1)); echo "PASS T4.a find_independent_batch fixture 01 → T1,T2"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.a (out=$out)"
fi

# T4.b — fixture 02 overlap → batch 빈
yaml=$(dag::extract_yaml "$FIXTURES/02-two-leaves-overlap.md")
out=$(dag::find_independent_batch "$yaml")
if [ -z "$out" ]; then
  PASS=$((PASS+1)); echo "PASS T4.b find_independent_batch fixture 02 → 빈 batch (overlap)"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.b (out=$out)"
fi

# T4.c — fixture 03 single leaf → batch 빈
yaml=$(dag::extract_yaml "$FIXTURES/03-single-leaf.md")
out=$(dag::find_independent_batch "$yaml")
if [ -z "$out" ]; then
  PASS=$((PASS+1)); echo "PASS T4.c find_independent_batch fixture 03 → 빈 batch (leaf 1개)"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.c (out=$out)"
fi

# T4.d — fixture 04 chain → batch 빈 (T1만 leaf)
yaml=$(dag::extract_yaml "$FIXTURES/04-chain.md")
out=$(dag::find_independent_batch "$yaml")
if [ -z "$out" ]; then
  PASS=$((PASS+1)); echo "PASS T4.d find_independent_batch fixture 04 → 빈 batch (chain)"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.d (out=$out)"
fi

# T4.e — fixture 05 diamond → batch [T1, T2]
yaml=$(dag::extract_yaml "$FIXTURES/05-diamond.md")
out=$(dag::find_independent_batch "$yaml" | sort | tr '\n' ',')
if [ "$out" = "T1,T2," ]; then
  PASS=$((PASS+1)); echo "PASS T4.e find_independent_batch fixture 05 → T1,T2"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.e (out=$out)"
fi

# T4.f — fixture 06 malformed YAML → 빈 batch + stderr WARN (fallback)
yaml=$(dag::extract_yaml "$FIXTURES/06-malformed-yaml.md")
out=$(dag::find_independent_batch "$yaml" 2>/dev/null)
if [ -z "$out" ]; then
  PASS=$((PASS+1)); echo "PASS T4.f find_independent_batch fixture 06 malformed → 빈 batch (fallback)"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.f (out=$out)"
fi

# --- T5: get_task_test_command (Wave 2 U2 — FID 20260514) ---
# 인라인 yaml string (dag::extract_yaml 호출 없이 직접 dag::get_task_test_command 검증)
yaml='tasks:
  - id: T1
    test_command: "bash scripts/tests/test-foo.sh"
    depends_on: []
    inputs: []
    outputs: [src/foo.sh]
    ac: [AC-1]
  - id: T2
    depends_on: []
    inputs: []
    outputs: [src/bar.sh]
    ac: [AC-2]
'

# T5.a — T1 test_command 추출 (기재된 경우) + stderr 0줄
_b1=$(mktemp -d)   # 고정 /tmp 경로는 동시에 도는 run-all 끼리 덮어쓴다
dag::get_task_test_command "$yaml" "T1" >"$_b1/stdout" 2>"$_b1/stderr"
out=$(cat "$_b1/stdout")
err_lines=$(grep -c . "$_b1/stderr" || true)
if [ "$out" = "bash scripts/tests/test-foo.sh" ] && [ "$err_lines" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T5.a get_task_test_command T1 → stdout 정상 + stderr 0줄"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.a (out='$out' err_lines=$err_lines)"
fi

# T5.b — test_command 미기재 task → stdout 빈 + stderr warn 1줄 + exit 0
out=$(dag::get_task_test_command "$yaml" "T2" 2>"$_b1/stderr")
exit_code=$?
err_lines=$(grep -c . "$_b1/stderr" || true)
if [ -z "$out" ] && [ "$err_lines" -eq 1 ] && [ "$exit_code" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T5.b get_task_test_command T2 → stdout 빈 + stderr 1줄 + exit 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.b (out='$out' err_lines=$err_lines exit=$exit_code)"
fi

# T5.c — 존재하지 않는 task → stdout 빈 + stderr warn 1줄 + exit 0 (graceful)
out=$(dag::get_task_test_command "$yaml" "Tnoexist" 2>"$_b1/stderr")
exit_code=$?
err_lines=$(grep -c . "$_b1/stderr" || true)
if [ -z "$out" ] && [ "$err_lines" -eq 1 ] && [ "$exit_code" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T5.c get_task_test_command Tnoexist → stdout 빈 + stderr 1줄 + exit 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.c (out='$out' err_lines=$err_lines exit=$exit_code)"
fi

# --- T5.d: get_task_outputs (P0-2 task receipt) ---
out=$(dag::get_task_outputs "$yaml" "T1" 2>"$_b1/stderr")
err_lines=$(grep -c . "$_b1/stderr" || true)
if [ "$out" = "src/foo.sh" ] && [ "$err_lines" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T5.d get_task_outputs T1 → stdout 1줄"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.d (out='$out' err_lines=$err_lines)"
fi
out=$(dag::get_task_outputs "$yaml" "Tnoexist" 2>"$_b1/stderr")
exit_code=$?
err_lines=$(grep -c . "$_b1/stderr" || true)
if [ -z "$out" ] && [ "$err_lines" -eq 1 ] && [ "$exit_code" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T5.e get_task_outputs 미존재 → warn+exit0"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.e (out='$out' err_lines=$err_lines exit=$exit_code)"
fi

# --- T6: find_ready (다단계 wave — find_ready 신설 함수) ---
# 기반 fixture: 05-diamond (T1·T2 leaf, T3 depends T1, T4 depends T2)
#              07-three-wave-chain (T1·T2 leaf, T3·T4 wave2, T5 wave3)

# T6.a — done="" → wave 0 = 절대 leaf (diamond: T1·T2)
yaml=$(dag::extract_yaml "$FIXTURES/05-diamond.md")
out=$(dag::find_ready "$yaml" | sort | tr '\n' ',')
if [ "$out" = "T1,T2," ]; then
  PASS=$((PASS+1)); echo "PASS T6.a find_ready diamond done='' → T1,T2"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.a (out=$out)"
fi

# T6.b — done="T1 T2" → wave 2 (diamond: T3·T4 ready)
out=$(dag::find_ready "$yaml" T1 T2 | sort | tr '\n' ',')
if [ "$out" = "T3,T4," ]; then
  PASS=$((PASS+1)); echo "PASS T6.b find_ready diamond done='T1 T2' → T3,T4"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.b (out=$out)"
fi

# T6.c — done="T1 T2 T3 T4" → wave 3 empty (diamond: 전부 완료)
out=$(dag::find_ready "$yaml" T1 T2 T3 T4)
if [ -z "$out" ]; then
  PASS=$((PASS+1)); echo "PASS T6.c find_ready diamond done='T1 T2 T3 T4' → empty"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.c (out=$out)"
fi

# T6.d — three-wave done="" → wave 1 = T1,T2
yaml=$(dag::extract_yaml "$FIXTURES/07-three-wave-chain.md")
out=$(dag::find_ready "$yaml" | sort | tr '\n' ',')
if [ "$out" = "T1,T2," ]; then
  PASS=$((PASS+1)); echo "PASS T6.d find_ready three-wave done='' → T1,T2"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.d (out=$out)"
fi

# T6.e — three-wave done="T1 T2" → wave 2 = T3,T4
out=$(dag::find_ready "$yaml" T1 T2 | sort | tr '\n' ',')
if [ "$out" = "T3,T4," ]; then
  PASS=$((PASS+1)); echo "PASS T6.e find_ready three-wave done='T1 T2' → T3,T4"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.e (out=$out)"
fi

# T6.f — three-wave done="T1 T2 T3 T4" → wave 3 = T5
out=$(dag::find_ready "$yaml" T1 T2 T3 T4)
if [ "$out" = "T5" ]; then
  PASS=$((PASS+1)); echo "PASS T6.f find_ready three-wave done='T1 T2 T3 T4' → T5"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.f (out=$out)"
fi

# T6.g — three-wave 전부 완료 → empty
out=$(dag::find_ready "$yaml" T1 T2 T3 T4 T5)
if [ -z "$out" ]; then
  PASS=$((PASS+1)); echo "PASS T6.g find_ready three-wave done='T1..T5' → empty (수렴)"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.g (out=$out)"
fi

# T6.h — chain(04) done="T1" → T2 ready
yaml=$(dag::extract_yaml "$FIXTURES/04-chain.md")
out=$(dag::find_ready "$yaml" T1)
if [ "$out" = "T2" ]; then
  PASS=$((PASS+1)); echo "PASS T6.h find_ready chain done='T1' → T2"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.h (out=$out)"
fi

# --- T-shadow: cwd 의 yaml.py 가 진짜 yaml 을 가리지 못한다 (20261007-yaml-cwd-shadow) ---
# python3 stdin/-c 는 sys.path[0]='' 라 cwd 의 가짜 yaml 을 import 한다 — 가짜는 항상 단일 leaf 'FAKE' 를 돌려준다.
_sh=$(mktemp -d); printf 'def safe_load(s):\n    return {"tasks": [{"id": "FAKE", "depends_on": []}]}\n' > "$_sh/yaml.py"
_yaml_real=$(dag::extract_yaml "$FIXTURES/01-two-leaves-disjoint.md")
_leaves=$(cd "$_sh" && dag::list_leaves "$_yaml_real" 2>/dev/null)
_yaml_tc=$(printf 'tasks:\n  - id: T1\n    depends_on: []\n    test_command: "bash real-test.sh"\n')
_tc=$(cd "$_sh" && dag::get_task_test_command "$_yaml_tc" T1 2>/dev/null)
if ! printf '%s' "$_leaves" | grep -q 'FAKE' && printf '%s' "$_leaves" | grep -q 'T1'; then
  PASS=$((PASS+1)); echo "PASS T-shadow.a list_leaves 가 cwd 가짜 yaml 에 속지 않음"
else
  FAIL=$((FAIL+1)); echo "FAIL T-shadow.a — leaves=$_leaves"
fi
if [ "$_tc" = "bash real-test.sh" ]; then
  PASS=$((PASS+1)); echo "PASS T-shadow.b get_task_test_command 가 실 YAML 로 동작"
else
  FAIL=$((FAIL+1)); echo "FAIL T-shadow.b — test_command 빈 값(가짜 yaml 에 속음)"
fi
rm -rf "$_sh"

# --- T-mut: extract_yaml 의 종료 코드 계약 (20261010-mutation-survivors-rest — 변이 생존 2건) ---
# 왜: emit-context.sh 는 `set -euo pipefail` 아래에서 `yaml=$(dag::extract_yaml …)` 로 부르고, check-tdd-red.sh 는
#   `… || yaml=""` 로 rc 를 본다. 성공과 "yaml 없음" 이 0 이 아니면 앞쪽은 그 자리에서 죽고 뒤쪽은 읽은 yaml 을 버린다.
#   T1 은 출력만 단언해서 `return 0 → 1` 변이 2곳(1단 성공 · 2단 후보 없음)이 살아남았다.
_my=$(dag::extract_yaml "$FIXTURES/01-two-leaves-disjoint.md" 2>/dev/null); _mrc=$?
if [ "$_mrc" -eq 0 ] && [ -n "$_my" ]; then
  PASS=$((PASS+1)); echo "PASS T-mut.a extract_yaml 1단 성공 → rc 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T-mut.a rc=$_mrc (0 이어야 한다 — set -e 호출부가 죽는다)"
fi
_mnf=$(mktemp); printf '# 제목\n\n본문만 있고 yaml 펜스가 없다.\n' > "$_mnf"
_my=$(dag::extract_yaml "$_mnf" 2>/dev/null); _mrc=$?
_my9=$(dag::extract_yaml "$FIXTURES/09-no-header-no-taskskey.md" 2>/dev/null); _mrc9=$?
if [ "$_mrc" -eq 0 ] && [ -z "$_my" ] && [ "$_mrc9" -eq 0 ] && [ -z "$_my9" ]; then
  PASS=$((PASS+1)); echo "PASS T-mut.b extract_yaml 후보 없음(펜스 없음 · tasks: 키 없음) → 빈 출력 + rc 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T-mut.b rc=$_mrc/$_mrc9 out='${_my}${_my9}' (빈 출력 + rc 0 이어야 한다)"
fi
rm -f "$_mnf"

# cleanup
rm -rf "$_b1"

echo ""
echo "==== Results: PASS=$PASS FAIL=$FAIL ===="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
