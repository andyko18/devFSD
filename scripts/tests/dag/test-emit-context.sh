#!/usr/bin/env bash
# Wave 2 U2 — emit-context.sh fail-fast atomic 검증
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
FIXTURES="$PLUGIN/scripts/tests/dag/fixtures/emit-context"
EMIT="$PLUGIN/scripts/dag/emit-context.sh"

# 격리: temp 작업 디렉토리에 fixture 복사 후 실행 (.specops/<FID> 구조 시뮬레이션)
run_emit() {
  local fixture_dir="$1"
  local fid; fid=$(basename "$fixture_dir")
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/.specops/$fid"
  cp "$fixture_dir"/*.md "$tmp/.specops/$fid/"
  (cd "$tmp" && bash "$EMIT" "$fid" 2>"$tmp/emit.err"; echo "exit=$?")   # 고정 /tmp 경로는 동시에 도는 run-all 끼리 덮어쓴다
  echo "[STDERR]"
  cat "$tmp/emit.err"
  echo "[DISPATCH_DIR]"
  ls "$tmp/.specops/$fid/dispatch/" 2>/dev/null || echo "(empty)"
  rm -rf "$tmp"
}

# T1.a: PASS fixture → exit 0 + 2 files 생성 + dispatch/ 디렉토리 존재
out=$(run_emit "$FIXTURES/ok-fid")
if echo "$out" | grep -q "EMIT: 2 files" && echo "$out" | grep -q "exit=0"; then
  PASS=$((PASS+1)); echo "PASS T1.a ok-fid → EMIT 2 files + exit 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a"; echo "out=$out"
fi

# T1.b: missing-tc fixture → fail-fast exit 1 + stderr 에 task-id 출력 + dispatch/ 비어있음
out=$(run_emit "$FIXTURES/missing-tc")
if echo "$out" | grep -q "exit=1" && echo "$out" | grep -q "T1" && echo "$out" | grep -q "(empty)"; then
  PASS=$((PASS+1)); echo "PASS T1.b missing-tc → fail-fast atomic"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b"; echo "out=$out"
fi

# T1.c: bad-ac fixture → fail-fast exit 1 + stderr 에 AC-99 + dispatch/ 비어있음
out=$(run_emit "$FIXTURES/bad-ac")
if echo "$out" | grep -q "exit=1" && echo "$out" | grep -q "AC-99" && echo "$out" | grep -q "(empty)"; then
  PASS=$((PASS+1)); echo "PASS T1.c bad-ac → fail-fast atomic"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.c"; echo "out=$out"
fi

# T1.d: ok-fid 산출물 5 섹션 모두 비-빈 (간단 정합 확인)
tmp=$(mktemp -d)
mkdir -p "$tmp/.specops/ok-fid"
cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/ok-fid/"
(cd "$tmp" && bash "$EMIT" ok-fid >/dev/null 2>&1)
ctx="$tmp/.specops/ok-fid/dispatch/T1-context.md"
if [ -f "$ctx" ] \
  && grep -q "1. 담당 AC" "$ctx" \
  && grep -q "2. 관련 spec" "$ctx" \
  && grep -q "3. 테스트 명령" "$ctx" \
  && grep -q "4. 수정 허용 파일" "$ctx" \
  && grep -q "5. 작업 디렉터리" "$ctx"; then
  PASS=$((PASS+1)); echo "PASS T1.d ctx 5 섹션 정합"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.d"
fi
rm -rf "$tmp"

# T1.e: decomposing-ko Step 10b 명시 (C1 leaf 가 본 케이스를 PASS 시킴)
if grep -qE "Step 10b" "$PLUGIN/skills/decomposing-ko/SKILL.md" \
  && grep -q "emit-context" "$PLUGIN/skills/decomposing-ko/SKILL.md"; then
  PASS=$((PASS+1)); echo "PASS T1.e decomposing-ko Step 10b 본문 명시"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.e decomposing-ko Step 10b 부재"
fi

# T1.f: §6 설계 계약 — memory/data-model.md 존재 시 §6 섹션 + 경로 emit (#4 design-first 배선)
tmp=$(mktemp -d)
mkdir -p "$tmp/.specops/ok-fid" "$tmp/.specops/memory"
cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/ok-fid/"
echo "# data-model" > "$tmp/.specops/memory/data-model.md"
(cd "$tmp" && bash "$EMIT" ok-fid >/dev/null 2>&1)
ctx="$tmp/.specops/ok-fid/dispatch/T1-context.md"
if grep -q "6. 설계 계약" "$ctx" && grep -q "data-model.md" "$ctx"; then
  PASS=$((PASS+1)); echo "PASS T1.f §6 설계 계약 (memory 존재 시 emit)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.f §6 미생성/경로누락"
fi
rm -rf "$tmp"

# T1.f2: §6 설계 계약 — api-spec-consumer.md(소비 IF, KIND 1·5) 도 계약에 포함 (C2 — 소비 축 정·역 쌍 복원)
tmp=$(mktemp -d)
mkdir -p "$tmp/.specops/ok-fid" "$tmp/.specops/memory"
cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/ok-fid/"
echo "# consumer" > "$tmp/.specops/memory/api-spec-consumer.md"
(cd "$tmp" && bash "$EMIT" ok-fid >/dev/null 2>&1)
ctx="$tmp/.specops/ok-fid/dispatch/T1-context.md"
if grep -q "6. 설계 계약" "$ctx" && grep -q "api-spec-consumer.md" "$ctx"; then
  PASS=$((PASS+1)); echo "PASS T1.f2 §6 소비 IF 계약 (api-spec-consumer emit)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.f2 §6 api-spec-consumer 미포함"
fi
rm -rf "$tmp"

# T1.g: memory 부재 시 §6 미생성 (graceful — 순수 로직/CLI 회귀 보호)
tmp=$(mktemp -d)
mkdir -p "$tmp/.specops/ok-fid"
cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/ok-fid/"
(cd "$tmp" && bash "$EMIT" ok-fid >/dev/null 2>&1)
ctx="$tmp/.specops/ok-fid/dispatch/T1-context.md"
if ! grep -q "6. 설계 계약" "$ctx"; then
  PASS=$((PASS+1)); echo "PASS T1.g §6 미생성 (memory 부재 graceful)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.g §6 생성됨 (graceful 위반)"
fi
rm -rf "$tmp"

# T4.a: intent 게이트 — 날짜 FID + intent 부재 → rc=1 · dispatch 미생성 (원자성)
#   ★ id 는 T4.a — T1.h 는 이미 스코프 이관 배선 케이스가 쓴다(:146-157, plan-review 1회차 I-5)
#   stderr 를 단언하는 이유(AC-5 Then "stderr 에 intent 안내"): rc=1 만 보면 상류 게이트
#   6종 중 무엇이 막았는지 구분 못 해, intent 게이트가 죽어도 케이스가 통과한다.
tmp=$(mktemp -d)
mkdir -p "$tmp/.specops/20991231-gate"
cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/20991231-gate/"
err=$(cd "$tmp" && bash "$EMIT" 20991231-gate 2>&1 >/dev/null); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$err" | grep -q 'intent\.md' \
   && [ ! -d "$tmp/.specops/20991231-gate/dispatch" ]; then
  PASS=$((PASS+1)); echo "PASS T4.a intent 부재 → rc=1 · stderr intent 안내 · dispatch 미생성"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.a (rc=$rc err=$(printf '%s' "$err" | head -1) dispatch=$(ls "$tmp/.specops/20991231-gate/dispatch" 2>/dev/null | wc -l))"
fi
rm -rf "$tmp"

# T4.b: intent 를 채우면 정상 산출 (AC-5 Then 둘째 문장 — plan-review 2회차 I-F)
tmp=$(mktemp -d)
mkdir -p "$tmp/.specops/20991231-gate"
cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/20991231-gate/"
printf '# Intent: 게이트 픽스처\n\n**작성자**: 사용자 · **Status**: accepted\n\n## 문제\n게이트 통과 경로 확인\n\n## 기대 결과\ndispatch 산출\n\n## 영향 사용자·시스템\n- 구현자\n\n## 제약\n- 해당 없음\n\n## 열린 질문\n- 없음\n' > "$tmp/.specops/20991231-gate/intent.md"
out=$(cd "$tmp" && bash "$EMIT" 20991231-gate 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'EMIT:' && [ -d "$tmp/.specops/20991231-gate/dispatch" ]; then
  PASS=$((PASS+1)); echo "PASS T4.b intent 채움 → EMIT · dispatch 생성"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.b (rc=$rc out=$out)"
fi
rm -rf "$tmp"

# T1.j: AC bullet 포맷 겸용 (20260716 trivial dogfood 발견 #2) — `- **AC-1**: ...` 도 요약 추출
tmp=$(mktemp -d)
mkdir -p "$tmp/.specops/ok-fid"
cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/ok-fid/"
# AC.md 를 bullet 포맷으로 교체 (기존 fixture 의 AC-id 유지 필요 — 원본에서 id 추출)
acids=$(grep -oE 'AC-[A-Za-z0-9-]+' "$tmp/.specops/ok-fid/acceptance-criteria.md" | sort -u)
{ echo "# AC"; for a in $acids; do echo "- **$a**: bullet 포맷 설명 ($a)"; done; } > "$tmp/.specops/ok-fid/acceptance-criteria.md"
(cd "$tmp" && bash "$EMIT" ok-fid >/dev/null 2>&1)
ctx="$tmp/.specops/ok-fid/dispatch/T1-context.md"
if grep -qE '^- AC-[A-Za-z0-9-]+: bullet 포맷 설명' "$ctx"; then
  PASS=$((PASS+1)); echo "PASS T1.j AC bullet 포맷 요약 추출"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.j bullet 요약 빈 문자열 (조용한 degrade)"
fi
rm -rf "$tmp"

# T1.k: AC 요약 추출 실패 시 stderr WARN (조용한 품질 저하 가시화)
tmp=$(mktemp -d)
mkdir -p "$tmp/.specops/ok-fid"
cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/ok-fid/"
acids=$(grep -oE 'AC-[A-Za-z0-9-]+' "$tmp/.specops/ok-fid/acceptance-criteria.md" | sort -u)
# id 는 존재하나(검증 통과) 요약 추출 불가한 포맷 — 표/인라인 언급만
{ echo "# AC"; for a in $acids; do echo "| $a | must | 표 안에만 존재 |"; done; } > "$tmp/.specops/ok-fid/acceptance-criteria.md"
err=$(cd "$tmp" && bash "$EMIT" ok-fid 2>&1 >/dev/null)
if echo "$err" | grep -q "WARN.*요약 추출 실패"; then
  PASS=$((PASS+1)); echo "PASS T1.k AC 요약 실패 stderr WARN"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.k WARN 미발화 (err='$(echo "$err" | head -1)')"
fi
rm -rf "$tmp"

# T1.h: 스코프 이관 규약 배선 (verify-exec-gate 잔여 backlog) — implementing-ko 에
#   tasks.md-SoT 이관 규약 + emit-context 재실행 + disjoint 재판정 + SCOPE-MOVED 기록이 명문화돼 있어야
#   트리거 5(whitelist 외 파일) 처리가 dispatch 파일 수기 보강(→ R11 race)으로 새지 않는다.
IMPL_SKILL="$PLUGIN/skills/implementing-ko/SKILL.md"
n=$(grep -c "스코프 이관 규약" "$IMPL_SKILL")
if [ "$n" -eq 1 ] && grep -q "SCOPE-MOVED" "$IMPL_SKILL" \
   && grep -q "outputs-disjoint 재판정" "$IMPL_SKILL" \
   && grep -A8 "스코프 이관 규약" "$IMPL_SKILL" | grep -q "emit-context.sh"; then
  PASS=$((PASS+1)); echo "PASS T1.h 스코프 이관 규약 배선 (SoT+재emit+재판정+기록)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.h 스코프 이관 규약 배선 (n=$n)"
fi

# T1.i: 재실행 멱등 — 같은 FID 로 2회 실행 시 context 재생성 (이관 규약 스텝 2 의 전제)
tmp=$(mktemp -d)
mkdir -p "$tmp/.specops/ok-fid"
cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/ok-fid/"
(cd "$tmp" && bash "$EMIT" ok-fid >/dev/null 2>&1)
ctx="$tmp/.specops/ok-fid/dispatch/T1-context.md"
sum1=$(cksum < "$ctx")
echo "manual edit" >> "$ctx"
(cd "$tmp" && bash "$EMIT" ok-fid >/dev/null 2>&1)
sum2=$(cksum < "$ctx")
if [ "$sum1" = "$sum2" ] && ! grep -q "manual edit" "$ctx"; then
  PASS=$((PASS+1)); echo "PASS T1.i 재실행 멱등 — 수기 편집 증발(덮어쓰기) 실증"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.i 재실행 멱등"
fi
rm -rf "$tmp"

# ── FID 20260723-lifecycle-robustness (C) — h2 헤더 구제 + fail-closed ──

# T2.a (AC-4): ## (h2) 헤더 AC.md → 요약 정상 추출 (관찰된 drift 구제, 빈 요약 아님)
tmp=$(mktemp -d)
mkdir -p "$tmp/.specops/h2-header"
cp "$FIXTURES/h2-header"/*.md "$tmp/.specops/h2-header/"
rc=$(cd "$tmp" && bash "$EMIT" h2-header >/dev/null 2>&1; echo $?)
ctx="$tmp/.specops/h2-header/dispatch/T1-context.md"
if [ "$rc" = "0" ] && [ -f "$ctx" ] && grep -qE '^- AC-1: parser 추출' "$ctx"; then
  PASS=$((PASS+1)); echo "PASS T2.a h2 헤더 → 요약 정상 추출 + exit 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.a h2 요약 추출 실패 (rc=$rc)"
fi
rm -rf "$tmp"

# T2.b (AC-5): AC-id 토큰 존재하나 헤더/불릿 전무(진짜 drift) → exit 1 + dispatch 비어있음 (fail-closed atomic)
tmp=$(mktemp -d)
mkdir -p "$tmp/.specops/ac-no-header"
cp "$FIXTURES/ac-no-header"/*.md "$tmp/.specops/ac-no-header/"
rc=$(cd "$tmp" && bash "$EMIT" ac-no-header 2>"$tmp/emit-drift.err" >/dev/null; echo $?)
empty=$([ -z "$(ls "$tmp/.specops/ac-no-header/dispatch/" 2>/dev/null)" ] && echo yes || echo no)
if [ "$rc" = "1" ] && [ "$empty" = "yes" ] && grep -q "요약 추출 실패" "$tmp/emit-drift.err"; then
  PASS=$((PASS+1)); echo "PASS T2.b 추출 실패 drift → exit 1 + 부분잔류 0 (fail-closed)"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.b fail-closed 미작동 (rc=$rc empty=$empty)"
fi
rm -rf "$tmp"

# ── T3: must AC 역방향 커버리지 (20260806 /maintain 정밀분석) ────────────────
# 종전 검증은 task→AC 한 방향(ac 배열의 id 가 AC.md 에 존재)뿐이었다.
# 역방향(모든 must AC 가 ≥1 task 에 매핑)은 decomposing 산문뿐 — AC-R-1 을 채워도
# 어느 태스크에도 안 매핑하면 회귀 테스트가 영영 구현되지 않는 구멍.
out=$(run_emit "$FIXTURES/must-uncovered")
# ★ 커버리지 검사 **자신의 문안**을 본다 ("must AC 미커버 — AC-R-1"). "AC-R-1" 만 찾으면 앞 단계 게이트의 문안에도
#   그 글자가 있어, 커버리지 검사를 지워도 통과한다(20261009 변이 실측 — 전체 스위트 통과). 픽스처는 기준선 문서를 갖춰
#   앞 단계(MAINTAIN-BASELINE)를 지나게 했다.
if echo "$out" | grep -q "exit=1" && echo "$out" | grep -q "must AC 미커버 — AC-R-1" \
   && echo "$out" | grep -q "(empty)"; then
  PASS=$((PASS+1)); echo "PASS T3.a must AC 미커버 → exit 1 + 미커버 id 지목 + 부분잔류 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.a"; echo "out=$out"
fi
# should AC(AC-2) 미커버는 차단하지 않는다 — 오류 메시지에 AC-2 가 나오면 과잉
if ! echo "$out" | grep -E "커버.*AC-2|AC-2.*커버" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS T3.b should AC 미커버는 비차단"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.b should 과잉 차단"
fi

# T3.c 대조 — 같은 픽스처에서 AC-R-1 을 태스크에 매핑하면 통과한다 (T3.a 가 픽스처의 다른 결함에 반응한 것이 아님)
_t3=$(mktemp -d); mkdir -p "$_t3/.specops/must-uncovered"; cp "$FIXTURES/must-uncovered"/*.md "$_t3/.specops/must-uncovered/"
sed -i.bak 's/ac: \[AC-1\]/ac: [AC-1, AC-R-1]/' "$_t3/.specops/must-uncovered/tasks.md"
if (cd "$_t3" && bash "$EMIT" must-uncovered >/dev/null 2>&1); then
  PASS=$((PASS+1)); echo "PASS T3.c 대조 — must AC 를 매핑하면 통과"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.c 매핑했는데도 실패 — T3.a 의 원인이 커버리지가 아니다"
fi
rm -rf "$_t3"

# ── T3.d~i: 태스크 필드 검증과 앞 단계 게이트의 **배선** (20261009 변이 실측 — 아래 6건은 검사를 꺼도 어떤 스위트도 실패하지 않았다) ──
#   판정기 단독 스위트는 판정기를 잠근다. 여기서는 emit-context 가 그 판정기를 **실제로 부르고 그 결과로 멈추는지**를 잠근다 —
#   소스에 호출 문자열이 있는지만 보는 테스트는 `if false` 로 감싸도 통과한다.
_emit_case() {  # $1=id $2=픽스처 $3=기대 문안(ERE)
  local o; o=$(run_emit "$FIXTURES/$2")
  if echo "$o" | grep -q "exit=1" && echo "$o" | grep -Eq "$3" && echo "$o" | grep -q "(empty)"; then
    PASS=$((PASS+1)); echo "PASS $1"
  else FAIL=$((FAIL+1)); echo "FAIL $1"; echo "out=$o"; fi
}
_emit_case "T3.d ac 배열이 빈 태스크 → exit 1 + 그 태스크 지목"            empty-ac                  'T2: ac 배열 빈 값'
_emit_case "T3.e outputs 키가 없는 태스크 → exit 1"                        no-outputs                'T1: inputs/outputs 키 부재'
# T3.f 의 픽스처에는 must AC 가 없다 — 있으면 "must AC 미커버" 가 대신 멈춰 줘서, 빈 배열 검사를 꺼도 통과한다.
_emit_case "T3.f tasks 배열이 빈 문서 → exit 1 (0 파일 성공이 아니다)"      no-tasks                  'tasks 배열 비어있음'
if run_emit "$FIXTURES/no-tasks" | grep -q 'must AC 미커버'; then
  FAIL=$((FAIL+1)); echo "FAIL T3.f2 no-tasks 픽스처에 must AC 가 있다 — T3.f 가 다른 검사에 기대게 된다"
else PASS=$((PASS+1)); echo "PASS T3.f2 no-tasks 픽스처는 빈 배열 검사만으로 멈춘다"; fi
_emit_case "T3.g foundation+batch 동시 라벨 → emit 이 멈춘다"              hybrid-label              'hybrid 라벨'
_emit_case "T3.h 기준선 문서 없는 유지보수 FID → emit 이 멈춘다"           maintain-no-baseline      'MAINTAIN-BASELINE: FAIL'
_emit_case "T3.i 회귀 AC 없는 유지보수 FID → emit 이 멈춘다"               maintain-no-regression-ac 'REGRESSION-AC'
# T3.j FID 에 경로 구분자 — 형식 검사에서 멈춘다 (".specops/a/b/tasks.md not found" 로 흘러가지 않는다)
_o=$(cd "$(mktemp -d)" && bash "$EMIT" 'a/b' 2>&1; echo "exit=$?")
if echo "$_o" | grep -q "exit=1" && echo "$_o" | grep -q "invalid FID"; then
  PASS=$((PASS+1)); echo "PASS T3.j FID 의 '/' → invalid FID"
else FAIL=$((FAIL+1)); echo "FAIL T3.j"; echo "out=$_o"; fi

# ── 20261001-task-id-guard — check-task-ids.sh (판정기 단독) ──
CHK="$PLUGIN/scripts/_internal/check-task-ids.sh"
_pf() { if [ "$2" = ok ]; then PASS=$((PASS+1)); echo "PASS $1"; else FAIL=$((FAIL+1)); echo "FAIL $1${3:+ — $3}"; fi; }
# mk_tid_fixture TMPDIR FID ID값... — tasks.md YAML 만 있는 최소 FID (id 값은 따옴표 포함 원문)
mk_tid_fixture() {
  local d="$1" fid="$2"; shift 2
  mkdir -p "$d/.specops/$fid"
  { echo '# tasks'; echo; echo '## 의존 그래프'; echo; echo '```yaml'; echo 'tasks:'
    for v in "$@"; do echo "  - id: $v"; echo '    depends_on: []'; echo '    ac: [AC-1]'; done
    echo '```'; } > "$d/.specops/$fid/tasks.md"
}

# T1.t1 숫자 id 만 있는 신규 FID → PASS (AC-1)
tmp=$(mktemp -d); mk_tid_fixture "$tmp" 20261001-ok T1 T2 T10
out=$(cd "$tmp" && bash "$CHK" 20261001-ok 2>&1); rc=$?
_pf "T1.t1 숫자 id → TASK-IDS: PASS" "$([ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'TASK-IDS: PASS (3 tasks)' && echo ok || echo no)" "rc=$rc out=$out"
rm -rf "$tmp"

# T1.t2 접미사·비 T숫자·숫자형·따옴표 접미사 → FAIL + 위반 목록 + 사유 (AC-2·AC-10)
#   위반 id 는 '규격 위반:' 목록 줄에서 찾는다 — 안내 문구에도 'T1a' 가 있어 전체 출력 grep 은 공허하다.
#   '1'(숫자형)은 목록 안의 독립 토큰으로 확인한다(AC-10 — 순서 무관). 정상 id T1 은 목록에 없어야 한다.
tmp=$(mktemp -d); mk_tid_fixture "$tmp" 20261001-bad T1 T1a task-3 1 '"T1b"'
out=$(cd "$tmp" && bash "$CHK" 20261001-bad 2>&1); rc=$?
vl=$(printf '%s\n' "$out" | grep '규격 위반:')
_pf "T1.t2 위반 id → rc=1·목록·숫자 전용 사유" "$([ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'TASK-IDS: FAIL' && printf '%s' "$vl" | grep -q 'T1a' && printf '%s' "$vl" | grep -q 'task-3' && printf '%s' "$vl" | grep -qE '(: |, )1(,|$)' &&printf '%s' "$vl" | grep -q 'T1b' && ! printf '%s' "$vl" | grep -qE '(: |, )T1(,|$)' && printf '%s' "$out" | grep -q '숫자 전용' && echo ok || echo no)" "rc=$rc out=$out"
rm -rf "$tmp"

# T1.t3 레거시(cutoff 미만)·비날짜 FID → SKIP, 막지 않는다 (AC-3)
tmp=$(mktemp -d); mk_tid_fixture "$tmp" 20260902-legacy N1 FIRST; mk_tid_fixture "$tmp" fid-test N1
o1=$(cd "$tmp" && bash "$CHK" 20260902-legacy 2>&1); r1=$?; o2=$(cd "$tmp" && bash "$CHK" fid-test 2>&1); r2=$?
_pf "T1.t3 레거시·비날짜 FID → SKIP rc=0" "$([ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && printf '%s' "$o1" | grep -q 'SKIP' && printf '%s' "$o2" | grep -q 'SKIP' && echo ok || echo no)" "o1=$o1 o2=$o2"
rm -rf "$tmp"

# T1.t4 YAML 파싱 불가 → SKIP + 사유(검증하지 못했다는 사실을 숨기지 않는다), rc=0 (AC-8)
tmp=$(mktemp -d); mkdir -p "$tmp/.specops/20261001-broken"
printf '```yaml\ntasks:\n  - id: "T1\n    depends_on: []\n```\n' > "$tmp/.specops/20261001-broken/tasks.md"
out=$(cd "$tmp" && bash "$CHK" 20261001-broken 2>&1); rc=$?
_pf "T1.t4 깨진 YAML → SKIP + 파싱 불가 사유" "$([ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'SKIP' && printf '%s' "$out" | grep -q '파싱 불가' && echo ok || echo no)" "rc=$rc out=$out"
rm -rf "$tmp"

# T1.t5 어떤 env 로도 신규 FID 의 거부가 풀리지 않는다 (AC-3 후단) — 실제 우회 경로 SPECOPS_ROOT 포함
tmp=$(mktemp -d); mk_tid_fixture "$tmp" 20261001-bad T1a
okv=ok
for e in "SPECOPS_TASK_IDS_CUTOFF=20300101" "SPECOPS_ROOT=/nonexistent" "SPECOPS_ROOT=" "SPECOPS_GOVERNANCE_BYPASS=1"; do
  out=$(cd "$tmp" && env "$e" bash "$CHK" 20261001-bad 2>&1); rc=$?
  { [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'TASK-IDS: FAIL'; } || { okv=no; echo "  (풀림: $e rc=$rc out=$out)"; }
done
_pf "T1.t5 env 우회 4종 프로브 → FAIL 유지" "$okv"
rm -rf "$tmp"

# ── emit-context 통합 (20261001-task-id-guard T2) — 라벨 T2.t* (기존 T2.a·T2.b 는 h2 헤더·drift 케이스) ──
_ok_spec_ac() { cp "$FIXTURES/ok-fid/spec.md" "$FIXTURES/ok-fid/acceptance-criteria.md" "$1/.specops/$2/"; }
# _tid_line ERR — 판정기의 'TASK-IDS: FAIL' 줄만. '숫자 전용' 은 emit 의 안내 echo 에도, 'T1a' 는 판정기 안내 줄에도
#   있어 전체 stderr grep 은 공허하다 — 위반 목록이 정확히 T1a 인지를 이 한 줄에서 본다.
_tid_line() { printf '%s\n' "$1" | grep '^TASK-IDS: FAIL'; }
# T2.t_a 접미사 id → emit exit 1 · 위반 목록=T1a · dispatch 미생성(원자성) (AC-2)
#   intent.md 부재 fixture 라 intent 게이트 안내가 stderr 에 없어야 한다 — 게이트가 intent 보다 앞에 있고
#   위반 시 자기가 exit 한다는 증거(`exit 1` 삭제 시 intent 게이트로 낙하해 rc=1 이 유지되는 변이를 잡는다).
tmp=$(mktemp -d); mk_tid_fixture "$tmp" 20261001-tid-bad T1a; _ok_spec_ac "$tmp" 20261001-tid-bad
err=$(cd "$tmp" && bash "$EMIT" 20261001-tid-bad 2>&1 >/dev/null); rc=$?
_pf "T2.t_a 접미사 id → emit exit 1·위반 목록 T1a·intent 낙하 없음·dispatch 0" "$([ "$rc" -eq 1 ] && _tid_line "$err" | grep -qE '숫자 전용.*규격 위반: T1a$' && ! printf '%s' "$err" | grep -q 'intent\.md' && [ ! -d "$tmp/.specops/20261001-tid-bad/dispatch" ] && echo ok || echo no)" "rc=$rc err=$(printf '%s' "$err" | head -3)"
# T2.t_a4 SPECOPS_ROOT 로 면제되지 않는다 (AC-3 후단)
err=$(cd "$tmp" && SPECOPS_ROOT=/nonexistent bash "$EMIT" 20261001-tid-bad 2>&1 >/dev/null); rc=$?
_pf "T2.t_a4 SPECOPS_ROOT=/nonexistent 로도 거부 유지" "$([ "$rc" -eq 1 ] && _tid_line "$err" | grep -qE '규격 위반: T1a$' && echo ok || echo no)" "rc=$rc err=$(printf '%s' "$err" | head -3)"
rm -rf "$tmp"
# T2.t_a2 깨진 YAML(AC-8 후단) → check 는 SKIP(차단 안 함), emit 은 다른 게이트·YAML 오류로 exit 1, TASK-IDS: FAIL 은 없음
tmp=$(mktemp -d); mkdir -p "$tmp/.specops/20261001-tid-broken"; _ok_spec_ac "$tmp" 20261001-tid-broken
printf '```yaml\ntasks:\n  - id: "T1\n    depends_on: []\n```\n' > "$tmp/.specops/20261001-tid-broken/tasks.md"
err=$(cd "$tmp" && bash "$EMIT" 20261001-tid-broken 2>&1 >/dev/null); rc=$?
_pf "T2.t_a2 깨진 YAML → emit exit 1 · TASK-IDS: FAIL 없음" "$([ "$rc" -eq 1 ] && ! printf '%s' "$err" | grep -q 'TASK-IDS: FAIL' && echo ok || echo no)" "rc=$rc err=$(printf '%s' "$err" | head -2)"
rm -rf "$tmp"
# T2.t_c 레거시 FID(cutoff 미만, 비 T숫자 id) → emit 정상 산출 (AC-3 · 회귀)
tmp=$(mktemp -d); mkdir -p "$tmp/.specops/20260902-legacy"; cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/20260902-legacy/"
sed -i.bak 's/id: T1$/id: N1/; s/id: T2$/id: N2/' "$tmp/.specops/20260902-legacy/tasks.md"; rm -f "$tmp/.specops/20260902-legacy/tasks.md.bak"
out=$(cd "$tmp" && bash "$EMIT" 20260902-legacy 2>&1); rc=$?
_pf "T2.t_c 레거시 FID(N1·N2) → EMIT 정상" "$([ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'EMIT: 2 files' && echo ok || echo no)" "rc=$rc out=$out"
rm -rf "$tmp"
# T1.t6 PYTHONPATH 로 주입한 **조건부** 가짜 yaml 모듈로 판정기를 속이지 못한다 (AC-3 후단 · Phase C Important)
#   가짜는 SPECOPS_TI_YAML(판정기가 python 에 넘기는 env) 이 있을 때만 tasks=[T1] 을 돌려주고 그 외에는 실 pyyaml 로
#   위임한다 — 판정기만 속고 emit 의 자체 파싱은 실 YAML 을 봐서 T1a-context.md 를 디스크에 쓰던 경로(리뷰 실측).
#   무조건 가짜는 emit 도 함께 깨져 이 결함을 못 잡는다. 판정기의 `python3 -E` 가 PYTHON* env 를 무시해 막는다.
_fk=$(mktemp -d); mkdir -p "$_fk/yaml"
cat > "$_fk/yaml/__init__.py" <<'FKEOF'
import os, sys, importlib
_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def _load_real():
    saved_path, saved_mod = sys.path[:], sys.modules.pop("yaml", None)
    try:
        sys.path[:] = [p for p in sys.path if os.path.abspath(p or ".") != _root]
        return importlib.import_module("yaml")
    finally:
        sys.path[:] = saved_path
        if saved_mod is not None:
            sys.modules["yaml"] = saved_mod
_REAL = _load_real()
def safe_load(s):
    if os.environ.get("SPECOPS_TI_YAML") is not None:
        return {"tasks": [{"id": "T1"}]}
    return _REAL.safe_load(s)
def __getattr__(name):
    return getattr(_REAL, name)
FKEOF
# 선검사 — 가짜가 실제로 조건부로 동작하는가(트리거 시 T1 · 미트리거 시 실 pyyaml 위임). 아니면 아래 단언이 다른 것을 잰다.
_fk0=$(PYTHONPATH="$_fk" SPECOPS_TI_YAML=1 python3 -c 'import yaml;print(yaml.safe_load("tasks: [{id: T1a}]"))' 2>&1)
_fk1=$(env -u SPECOPS_TI_YAML PYTHONPATH="$_fk" python3 -c 'import yaml;print(yaml.safe_load("tasks: [{id: T1a}]"))' 2>&1)
_pf "T1.t6-0 픽스처: 조건부 가짜 yaml 성립(트리거 T1 · 그 외 실 pyyaml 위임)" "$([ "$_fk0" = "{'tasks': [{'id': 'T1'}]}" ] && [ "$_fk1" = "{'tasks': [{'id': 'T1a'}]}" ] && echo ok || echo no)" "fk0=$_fk0 fk1=$_fk1"
tmp=$(mktemp -d); mk_tid_fixture "$tmp" 20261001-fake T1a
out=$(cd "$tmp" && PYTHONPATH="$_fk" SPECOPS_TI_YAML=1 bash "$CHK" 20261001-fake 2>&1); rc=$?
_pf "T1.t6 가짜 yaml(PYTHONPATH) 주입에도 FAIL 유지·위반 목록 T1a" "$([ "$rc" -eq 1 ] && _tid_line "$out" | grep -qE '규격 위반: T1a$' && echo ok || echo no)" "rc=$rc out=$(printf '%s' "$out" | head -2)"
rm -rf "$tmp"
# T1.t6b 같은 주입에서 emit 도 exit 1 · dispatch 미생성 — intent 까지 갖춘 fixture 라 판정기가 속으면 실제로 산출된다
tmp=$(mktemp -d); mkdir -p "$tmp/.specops/20261001-fake"; cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/20261001-fake/"
sed -i.bak 's/id: T1$/id: T1a/' "$tmp/.specops/20261001-fake/tasks.md"; rm -f "$tmp/.specops/20261001-fake/tasks.md.bak"
printf '# Intent: 게이트 픽스처\n\n**작성자**: 사용자 · **Status**: accepted\n\n## 문제\n게이트 통과 경로 확인\n\n## 기대 결과\ndispatch 산출\n\n## 영향 사용자·시스템\n- 구현자\n\n## 제약\n- 해당 없음\n\n## 열린 질문\n- 없음\n' > "$tmp/.specops/20261001-fake/intent.md"
err=$(cd "$tmp" && env -u SPECOPS_TI_YAML PYTHONPATH="$_fk" bash "$EMIT" 20261001-fake 2>&1 >/dev/null); rc=$?
_pf "T1.t6b 가짜 yaml 주입 → emit exit 1·위반 목록 T1a·dispatch 0" "$([ "$rc" -eq 1 ] && _tid_line "$err" | grep -qE '규격 위반: T1a$' && [ ! -d "$tmp/.specops/20261001-fake/dispatch" ] && echo ok || echo no)" "rc=$rc err=$(printf '%s' "$err" | head -2) dispatch=$(ls "$tmp/.specops/20261001-fake/dispatch" 2>/dev/null | tr '\n' ' ')"
rm -rf "$tmp" "$_fk"
# (정상 숫자 id 날짜 FID 의 EMIT 은 기존 T4.b(FID 20991231-gate, ok-fid ids T1·T2)가 이미 잠근다 — 새 게이트가 앞에 있어도 통과해야 한다)


# ── T5 test_command whitelist 사전 경고 (FID 20261005-implement-bookkeeping) ──
# whitelist 밖 test_command 는 구현 뒤에야 VERIFY: PARTIAL·R-1 커밋 거부로 드러난다 — 분해 시점에 경고한다.
# 경고는 fail-open: 종료 코드와 EMIT 산출은 그대로여야 한다(docs-only FID 의 비코드 명령을 막지 않는다).
# wl_run <test_command> → "rc|warn|emit" (ok-fid 사본의 T1 test_command 를 교체해 실행. 날짜형 FID 는 intent 게이트가 걸려 비날짜 FID 를 쓴다)
wl_run() {
  local tmp out rc w e
  tmp=$(mktemp -d); mkdir -p "$tmp/.specops/wl-fid"; cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/wl-fid/"
  python3 - "$tmp/.specops/wl-fid/tasks.md" "$1" <<'PYE'
import sys
p, c = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
old = 'test_command: "bash scripts/tests/test-parser.sh"'
assert old in s
open(p, "w", encoding="utf-8").write(s.replace(old, 'test_command: "' + c + '"', 1))
PYE
  out=$(cd "$tmp" && bash "$EMIT" wl-fid 2>"$tmp/err"); rc=$?
  w=$(grep -c 'WARN T[0-9]* test_command whitelist 밖' "$tmp/err")
  e=$(printf '%s\n' "$out" | grep -c '^EMIT: 2 files')
  rm -rf "$tmp"
  printf '%s|%s|%s' "$rc" "$w" "$e"
}
wl_ok_n=0; wl_bad_n=0; wl_miss=""
for c in "bash scripts/tests/test-x.sh" "bash tests/test-x.sh" "bash test/test-x.sh" "pytest tests/" "python -m pytest -q" "npm test" "npm run test:unit" "go test ./pkg/foo" "cargo test" "npx vitest run"; do
  r=$(wl_run "$c"); [ "$r" = "0|0|1" ] && wl_ok_n=$((wl_ok_n+1)) || wl_miss="$wl_miss [허용 '$c' → $r]"
done
for c in "bash test-greet.sh" "bash ./scripts/x.sh" "ls commands/x.md" "git ls-files examples | wc -l" "sed -n '1,3p' CHANGELOG.md" "bash scripts/tests/a.sh && bash scripts/tests/b.sh" "bash scripts/../x.sh" "make test" "node test.js" "bash /abs/test.sh"; do
  r=$(wl_run "$c"); [ "$r" = "0|1|1" ] && wl_bad_n=$((wl_bad_n+1)) || wl_miss="$wl_miss [불허 '$c' → $r]"
done
if [ "$wl_ok_n" -eq 10 ] && [ "$wl_bad_n" -eq 10 ]; then
  PASS=$((PASS+1)); echo "PASS T5.a whitelist 허용 10종 경고 0 · 불허 10종 경고 1 · 전부 rc 0 + EMIT 2 files (fail-open)"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.a ok=$wl_ok_n bad=$wl_bad_n miss=$wl_miss"
fi
# T5.b 판정 근거 단일화: run-verification.sh 의 _WHITELIST_PAT 와 같은 판정(복제 금지) — 같은 sed 추출로 대조한다
RVPAT=$(grep -m1 '^_WHITELIST_PAT=' "$PLUGIN/scripts/_internal/run-verification.sh" | sed -E "s/^_WHITELIST_PAT='(.*)'\$/\1/")
par_miss=""
for c in "bash scripts/tests/test-x.sh" "bash test-greet.sh" "pytest tests/" "make test" "npx vitest run" "bash scripts/../x.sh" "cd apps/web && npx vitest run" "bash a.sh && bash b.sh"; do
  if [[ "$c" =~ $RVPAT ]] && [[ "$c" != *..* ]]; then want="0|0|1"; else want="0|1|1"; fi
  got=$(wl_run "$c"); [ "$got" = "$want" ] || par_miss="$par_miss [$c want=$want got=$got]"
done
if [ -n "$RVPAT" ] && [ -z "$par_miss" ]; then
  PASS=$((PASS+1)); echo "PASS T5.b emit-context 경고 판정 = run-verification.sh whitelist 판정 (8종 일치)"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.b parity miss=$par_miss pat-len=${#RVPAT}"
fi
# T5.c 정규식 리터럴을 emit-context 에 복제하지 않는다(이미 run-verification·record-task-receipt 두 곳 — 세 번째 금지)
if ! grep -q "^_WHITELIST_PAT='" "$EMIT" && ! grep -q 'poetry|uv|pdm|rye' "$EMIT"; then
  PASS=$((PASS+1)); echo "PASS T5.c emit-context 에 whitelist 정규식 리터럴 없음(단일 근거 읽기)"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.c whitelist 정규식이 emit-context 에 복제됨"
fi
# T5.c2 변수명·내용을 바꾼 복제도 잡는다 — whitelist 정규식의 특징 토큰([[:blank:]] 클래스)이 emit-context 에 한 번도 없어야 한다
if [ "$(grep -c '\[\[:blank:\]\]' "$EMIT")" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T5.c2 emit-context 에 정규식 특징 토큰([[:blank:]]) 없음"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.c2 emit-context 에 정규식 조각이 있음"
fi
# T5.d 실제 러너와 대조 — T5.b 는 같은 패턴으로 기대값을 재계산해 반쯤 동어반복이다. 실제 run-verification.sh 가 그 명령을 건너뛰는지(WARN: SKIP) 와 비교한다
RUNV="$PLUGIN/scripts/_internal/run-verification.sh"
rv_skips() {  # $1=test_command → y(러너가 whitelist 로 건너뜀)|n
  local tmp
  tmp=$(mktemp -d); mkdir -p "$tmp/.specops/rv-fid"
  printf '%s\n' '## 의존 그래프' '' '```yaml' 'tasks:' '  - id: T1' "    test_command: \"$1\"" '    depends_on: []' '    inputs: []' '    outputs: []' '    ac: [AC-1]' '```' > "$tmp/.specops/rv-fid/tasks.md"
  (cd "$tmp" && bash "$RUNV" rv-fid >/dev/null 2>"$tmp/err"; true)
  if grep -q 'WARN: SKIP' "$tmp/err"; then printf y; else printf n; fi
  rm -rf "$tmp"
}
rv_miss=""
for c in "bash test-greet.sh" "make test" "bash scripts/../x.sh" "bash scripts/tests/a.sh && bash scripts/tests/b.sh" "bash scripts/tests/nonexist-wl.sh" "bash tests/nonexist-wl.sh" "cd sub && bash tests/nonexist-wl.sh"; do
  rv=$(rv_skips "$c"); w=$(wl_run "$c" | cut -d'|' -f2); [ "$w" = 1 ] && em=y || em=n
  [ "$rv" = "$em" ] || rv_miss="$rv_miss [$c runner=$rv emit=$em]"
done
if [ -z "$rv_miss" ]; then
  PASS=$((PASS+1)); echo "PASS T5.d emit-context 경고 유무 = 실제 run-verification.sh 의 WARN: SKIP (7종 일치)"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.d runner 대조 불일치:$rv_miss"
fi
# T5.e 정규식 사본 동기 — run-verification 과 record-task-receipt 가 각자 복제본을 갖는다. 한쪽만 바뀌면 분해 경고 없음 → receipt 거부가 재발한다
if [ -n "$RVPAT" ] && [ "$(grep -m1 '^_WHITELIST_PAT=' "$PLUGIN/scripts/_internal/record-task-receipt.sh")" = "$(grep -m1 '^_WHITELIST_PAT=' "$RUNV")" ]; then
  PASS=$((PASS+1)); echo "PASS T5.e record-task-receipt·run-verification 의 _WHITELIST_PAT 사본 동일"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.e whitelist 정규식 사본이 갈라짐(run-verification ≠ record-task-receipt)"
fi
# T5.f 경고 안내 줄 잠금 — 불허 명령 경고 뒤에 허용 형태·docs-only 안내가 한 번 나와야 한다
gtmp=$(mktemp -d); mkdir -p "$gtmp/.specops/wl-fid"; cp "$FIXTURES/ok-fid"/*.md "$gtmp/.specops/wl-fid/"
sed -i.bak 's#test_command: "bash scripts/tests/test-parser.sh"#test_command: "bash test-greet.sh"#' "$gtmp/.specops/wl-fid/tasks.md"; rm -f "$gtmp/.specops/wl-fid/tasks.md.bak"
gerr=$(cd "$gtmp" && bash "$EMIT" wl-fid 2>&1 >/dev/null); rm -rf "$gtmp"
if [ "$(printf '%s\n' "$gerr" | grep -c '허용 형태')" -eq 1 ] && printf '%s' "$gerr" | grep -q 'docs-only FID 면 무시해도 됩니다' \
   && printf '%s\n' "$gerr" | grep -qxF "emit-context: WARN T1 test_command whitelist 밖 — 'bash test-greet.sh'"; then
  PASS=$((PASS+1)); echo "PASS T5.f 경고 줄(task id·명령 에코 정확 일치) + 허용 형태·docs-only 안내가 정확히 한 번"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.f 안내 줄 누락/중복: $gerr"
fi

# ── 20261007-fid-size-gate — check-fid-size.sh (FID 스코프 게이트) ──
FSZ="$PLUGIN/scripts/_internal/check-fid-size.sh"
# mk_fs_fixture TMPDIR FID N PLAN(y|n) [SPEC본문] — N 태스크 tasks.md(+선택 분할 계획행)·spec.md 만 있는 최소 FID
mk_fs_fixture() {
  local d="$1" fid="$2" n="$3" plan="$4" spec="${5:-# spec}" i
  mkdir -p "$d/.specops/$fid"
  { echo '```yaml'; echo 'tasks:'
    for i in $(seq 1 "$n"); do echo "  - id: T$i"; echo '    depends_on: []'; echo '    ac: [AC-1]'; done
    echo '```'
    [ "$plan" = y ] && printf '\n**분할 계획**: T1~T6 이번 FID, 나머지는 후속 FID 후보\n'; } > "$d/.specops/$fid/tasks.md"
  printf '%s\n' "$spec" > "$d/.specops/$fid/spec.md"
}
# fs_run TMPDIR FID — 판정기 단독 실행. out·rc 를 전역에 남긴다
fs_run() { out=$(cd "$1" && bash "$FSZ" "$2" 2>&1); rc=$?; }

tmp=$(mktemp -d)
# T6.a 6 태스크 → PASS (경계: 권장 상한)
mk_fs_fixture "$tmp" 20261007-fs6 6 n; fs_run "$tmp" 20261007-fs6
_pf "T6.a 6 태스크 → PASS rc=0" "$([ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'FID-SIZE: PASS (6 tasks)' && echo ok || echo no)" "rc=$rc out=$out"
# T6.b 7 태스크·계획행 없음 → FAIL (경계: 7 부터 의무) + 계획행 형식 안내
mk_fs_fixture "$tmp" 20261007-fs7n 7 n; fs_run "$tmp" 20261007-fs7n
_pf "T6.b 7 태스크 계획행 없음 → FAIL rc=1·형식 안내" "$([ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'FID-SIZE: FAIL' && printf '%s' "$out" | grep -q '\*\*분할 계획\*\*' && echo ok || echo no)" "rc=$rc out=$out"
# T6.c 7 태스크·계획행 있음 → WARN 통과 + 정확한 경고 줄
mk_fs_fixture "$tmp" 20261007-fs7y 7 y; fs_run "$tmp" 20261007-fs7y
_pf "T6.c 7 태스크 계획행 있음 → WARN rc=0·경고 줄" "$([ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'FID-SIZE: WARN' && printf '%s\n' "$out" | grep -qxF '⚠️ FID-SIZE: 7 태스크 (권장 ≤6) — 다중 세션에 걸칠 수 있음. 중간 이탈 시 재개는 /status (reconcile) 로.' && echo ok || echo no)" "rc=$rc out=$out"
# T6.d 9 태스크·계획행 있음 → 통과(경계: 10 미만), 10 태스크·대화형 → 계획행이 있어도 FAIL
mk_fs_fixture "$tmp" 20261007-fs9y 9 y; fs_run "$tmp" 20261007-fs9y; r9=$rc
mk_fs_fixture "$tmp" 20261007-fs10y 10 y; fs_run "$tmp" 20261007-fs10y
_pf "T6.d 9 태스크 통과 · 10 태스크 대화형은 계획행이 있어도 FAIL" "$([ "$r9" -eq 0 ] && [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '≥10' && echo ok || echo no)" "r9=$r9 rc=$rc out=$out"
# T6.e 10 태스크 + 줄 선두 §auto·§batch + 계획행 → WARN 통과 (분할을 물을 사용자 채널이 없다)
oke=ok
for lab in '**§auto**: true' '**§batch**: batch-20261007'; do
  mk_fs_fixture "$tmp" 20261007-fs10x 10 y "# spec
$lab"; fs_run "$tmp" 20261007-fs10x
  { [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'FID-SIZE: WARN' && printf '%s' "$out" | grep -q '⚠️ FID-SIZE: 10 태스크'; } || { oke=no; echo "  (예외 미작동: $lab rc=$rc out=$out)"; }
done
_pf "T6.e 10 태스크 + 예외 라벨 2종(§auto·§batch) + 계획행 → WARN 통과" "$oke"
# T6.f 예외 라벨이어도 10 태스크에 계획행이 없으면 FAIL (예외는 계획행 의무를 면하지 않는다)
mk_fs_fixture "$tmp" 20261007-fs10xn 10 n '**§auto**: true'; fs_run "$tmp" 20261007-fs10xn
_pf "T6.f 10 태스크 §auto 계획행 없음 → FAIL" "$([ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'FID-SIZE: FAIL' && echo ok || echo no)" "rc=$rc out=$out"
# T6.g 줄 중간 §auto 언급·§auto: false 는 예외가 아니다 (오탐 방지)
okg=ok
for sp in '참고: **§auto**: true 모드는 자동통과한다' '**§auto**: false'; do
  mk_fs_fixture "$tmp" 20261007-fs10m 10 y "$sp"; fs_run "$tmp" 20261007-fs10m
  { [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'FID-SIZE: FAIL'; } || { okg=no; echo "  (오탐: $sp rc=$rc out=$out)"; }
done
_pf "T6.g 줄 중간 §auto·§auto: false → 예외 아님(FAIL)" "$okg"
# T6.h 계획행 내용이 비면 없는 것으로 본다 · 줄 중간 `**분할 계획**:` 도 인정하지 않는다
mk_fs_fixture "$tmp" 20261007-fs7e 7 n; printf '\n**분할 계획**:\n' >> "$tmp/.specops/20261007-fs7e/tasks.md"; fs_run "$tmp" 20261007-fs7e; re=$rc
mk_fs_fixture "$tmp" 20261007-fs7m 7 n; printf '\n설명: **분할 계획**: T1 만\n' >> "$tmp/.specops/20261007-fs7m/tasks.md"; fs_run "$tmp" 20261007-fs7m
_pf "T6.h 빈 계획행·줄 중간 계획행 → FAIL" "$([ "$re" -eq 1 ] && [ "$rc" -eq 1 ] && echo ok || echo no)" "re=$re rc=$rc"
# T6.i 레거시(cutoff 미만)·비날짜 FID·YAML 부재/파싱 불가 → SKIP rc=0, 막지 않는다
mk_fs_fixture "$tmp" 20260902-fsold 12 n; fs_run "$tmp" 20260902-fsold; o1=$out; r1=$rc
mk_fs_fixture "$tmp" fs-fixture 12 n; fs_run "$tmp" fs-fixture; o2=$out; r2=$rc
mkdir -p "$tmp/.specops/20261007-fsbroken"; printf '```yaml\ntasks:\n  - id: "T1\n    depends_on: []\n```\n' > "$tmp/.specops/20261007-fsbroken/tasks.md"; fs_run "$tmp" 20261007-fsbroken; o3=$out; r3=$rc
_pf "T6.i 레거시·비날짜·깨진 YAML → SKIP rc=0" "$([ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$r3" -eq 0 ] && printf '%s\n%s\n%s\n' "$o1" "$o2" "$o3" | grep -c 'FID-SIZE: SKIP' | grep -q '^3$' && echo ok || echo no)" "o1=$o1 o2=$o2 o3=$o3"
# T6.j 어떤 env 로도 신규 FID 의 거부가 풀리지 않는다 (check-task-ids T1.t5 와 같은 계약)
okj=ok
for e in "SPECOPS_FID_SIZE_CUTOFF=20300101" "SPECOPS_ROOT=/nonexistent" "SPECOPS_ROOT=" "SPECOPS_GOVERNANCE_BYPASS=1"; do
  out=$(cd "$tmp" && env "$e" bash "$FSZ" 20261007-fs7n 2>&1); rc=$?
  { [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'FID-SIZE: FAIL'; } || { okj=no; echo "  (풀림: $e rc=$rc out=$out)"; }
done
_pf "T6.j env 우회 4종 프로브 → FAIL 유지" "$okj"
rm -rf "$tmp"

# ── 리뷰 지적 반영 프로브 (T6.k~q) ──
tmp=$(mktemp -d)
# T6.k 스칼라 리스트 tasks(- T1 …)도 항목 수로 센다 — dict 필터로 0 태스크 PASS 가 되지 않는다
mkdir -p "$tmp/.specops/20261007-fsscalar"
{ echo '```yaml'; echo 'tasks:'; for i in $(seq 1 11); do echo "  - T$i"; done; echo '```'; } > "$tmp/.specops/20261007-fsscalar/tasks.md"; printf '# spec\n' > "$tmp/.specops/20261007-fsscalar/spec.md"
fs_run "$tmp" 20261007-fsscalar
_pf "T6.k 스칼라 리스트 11 항목 → FAIL(0 tasks PASS 아님)" "$([ "$rc" -eq 1 ] && ! printf '%s' "$out" | grep -q '0 tasks' && echo ok || echo no)" "rc=$rc out=$out"
# T6.l cwd 의 yaml.py 가짜 모듈로 판정기를 속이지 못한다 (python3 -I — -E 는 sys.path[0]='' 라 cwd 를 못 막는다)
mk_fs_fixture "$tmp" 20261007-fsshadow 12 n
printf 'def safe_load(s):\n    return {"tasks": []}\n' > "$tmp/yaml.py"
fs_run "$tmp" 20261007-fsshadow; rm -f "$tmp/yaml.py"
_pf "T6.l cwd yaml.py 가짜 주입에도 FAIL 유지" "$([ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'FID-SIZE: FAIL' && echo ok || echo no)" "rc=$rc out=$out"
# T6.m placeholder 원문·코드펜스 안 계획행은 계획행이 아니다
mk_fs_fixture "$tmp" 20261007-fsph 7 n; printf '\n**분할 계획**: <이번 FID 범위·후속 FID 후보>\n' >> "$tmp/.specops/20261007-fsph/tasks.md"; fs_run "$tmp" 20261007-fsph; rp=$rc
mk_fs_fixture "$tmp" 20261007-fsfence 7 n; printf '\n```\n**분할 계획**: T1~T6 이번 FID\n```\n' >> "$tmp/.specops/20261007-fsfence/tasks.md"; fs_run "$tmp" 20261007-fsfence
_pf "T6.m placeholder·펜스 안 계획행 → FAIL" "$([ "$rp" -eq 1 ] && [ "$rc" -eq 1 ] && echo ok || echo no)" "rp=$rp rc=$rc"
# T6.n 하이픈 없는 FID 도 날짜 FID 로 본다 / cutoff 직전(20261006)은 SKIP·20261007 은 적용
mk_fs_fixture "$tmp" 20261007_big 7 n; fs_run "$tmp" 20261007_big; rh=$rc; oh=$out
mk_fs_fixture "$tmp" 20261007x 7 n; fs_run "$tmp" 20261007x; rx=$rc
mk_fs_fixture "$tmp" 20261006-fsedge 12 n; fs_run "$tmp" 20261006-fsedge; re6=$rc; o6=$out
mk_fs_fixture "$tmp" 20261007 7 n; fs_run "$tmp" 20261007; r7=$rc
_pf "T6.n 하이픈 없는 FID 적용·20261006 SKIP·20261007 적용" "$([ "$rh" -eq 1 ] && [ "$rx" -eq 1 ] && [ "$r7" -eq 1 ] && [ "$re6" -eq 0 ] && printf '%s' "$o6" | grep -q 'SKIP' && echo ok || echo no)" "rh=$rh rx=$rx r7=$r7 re6=$re6 o6=$o6"
# T6.o 예외 라벨은 각각 단독으로도 계획행 의무를 면하지 않는다 · trueish·빈 §batch 값은 예외가 아니다
oko=ok
for lab in '**§batch**: batch-20261007' '**§유형**: foundation' '**§auto**: true'; do
  mk_fs_fixture "$tmp" 20261007-fs10lab 10 n "$lab"; fs_run "$tmp" 20261007-fs10lab
  { [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'FID-SIZE: FAIL'; } || { oko=no; echo "  (계획행 없이 통과: $lab rc=$rc)"; }
done
for lab in '**§auto**: trueish' '**§batch**:'; do
  mk_fs_fixture "$tmp" 20261007-fs10lax 10 y "$lab"; fs_run "$tmp" 20261007-fs10lax
  { [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'FID-SIZE: FAIL'; } || { oko=no; echo "  (느슨한 라벨이 예외로 통과: $lab rc=$rc)"; }
done
_pf "T6.o 예외 라벨 단독 계획행 의무 · trueish·빈 §batch 는 예외 아님" "$oko"
# T6.p CRLF tasks.md 도 계획행·태스크 수를 정상 판정한다 (회귀 잠금)
mk_fs_fixture "$tmp" 20261007-fscrlf 7 y; sed -i.bak $'s/$/\r/' "$tmp/.specops/20261007-fscrlf/tasks.md"; rm -f "$tmp/.specops/20261007-fscrlf/tasks.md.bak"
fs_run "$tmp" 20261007-fscrlf
_pf "T6.p CRLF tasks.md 7 태스크+계획행 → WARN" "$([ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'FID-SIZE: WARN' && echo ok || echo no)" "rc=$rc out=$out"
rm -rf "$tmp"

# ── emit-context 통합 (20261007-fid-size-gate) — 라벨 T7.* ──
# T7.a 7 태스크·계획행 없음 → emit exit 1·FID-SIZE: FAIL·intent 낙하 없음·dispatch 0 (게이트가 자기가 exit 한다는 증거)
tmp=$(mktemp -d); mk_fs_fixture "$tmp" 20261007-fs7n 7 n; _ok_spec_ac "$tmp" 20261007-fs7n
err=$(cd "$tmp" && bash "$EMIT" 20261007-fs7n 2>&1 >/dev/null); rc=$?
_pf "T7.a 7 태스크 계획행 없음 → emit exit 1·FID-SIZE: FAIL·intent 낙하 없음·dispatch 0" "$([ "$rc" -eq 1 ] && printf '%s' "$err" | grep -q '^FID-SIZE: FAIL' && printf '%s' "$err" | grep -q 'FID 스코프 초과' && ! printf '%s' "$err" | grep -q 'intent\.md' && [ ! -d "$tmp/.specops/20261007-fs7n/dispatch" ] && echo ok || echo no)" "rc=$rc err=$(printf '%s' "$err" | head -3)"
# T7.b 7 태스크·계획행 있음 → 경고가 stderr 로 중계된다(이후 다른 게이트가 막아도 경고는 이미 나갔다)
mk_fs_fixture "$tmp" 20261007-fs7y 7 y; _ok_spec_ac "$tmp" 20261007-fs7y
err=$(cd "$tmp" && bash "$EMIT" 20261007-fs7y 2>&1 >/dev/null)
_pf "T7.b 7 태스크 계획행 있음 → emit 이 FID-SIZE 경고를 stderr 로 중계" "$(printf '%s\n' "$err" | grep -qxF '⚠️ FID-SIZE: 7 태스크 (권장 ≤6) — 다중 세션에 걸칠 수 있음. 중간 이탈 시 재개는 /status (reconcile) 로.' && ! printf '%s' "$err" | grep -q '^FID-SIZE: FAIL' && echo ok || echo no)" "err=$(printf '%s' "$err" | head -3)"
# T7.c 레거시 FID 는 영향 없음 — ok-fid(2 태스크)는 새 게이트로 회귀하지 않는다
tmp2=$(mktemp -d); mkdir -p "$tmp2/.specops/20260902-fsleg"; cp "$FIXTURES/ok-fid"/*.md "$tmp2/.specops/20260902-fsleg/"
out=$(cd "$tmp2" && bash "$EMIT" 20260902-fsleg 2>&1); rc=$?
_pf "T7.c 레거시 2 태스크 FID → EMIT 정상(게이트 회귀 없음)" "$([ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'EMIT: 2 files' && echo ok || echo no)" "rc=$rc out=$out"
rm -rf "$tmp" "$tmp2"

# ── 20261007-yaml-cwd-shadow — cwd 의 yaml.py 가 진짜 yaml 을 가리지 못한다 (python3 stdin/-c 는 sys.path[0]='' 라 cwd 를 import) ──
_shadow() { printf 'def safe_load(s):\n    return {"tasks": [{"id": "T1", "depends_on": [], "ac": ["AC-1"], "inputs": [], "outputs": [], "test_command": "bash x"}]}\n' > "$1/yaml.py"; }
# T8.a check-task-ids: 접미사 id(T1a) tasks.md + cwd 가짜 yaml(T1 만 돌려줌) → 여전히 FAIL
tmp=$(mktemp -d); mk_tid_fixture "$tmp" 20261007-shadow-tid T1a; _shadow "$tmp"
out=$(cd "$tmp" && bash "$CHK" 20261007-shadow-tid 2>&1); rc=$?
_pf "T8.a cwd yaml.py 가짜 주입에도 task id 거부 유지" "$([ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'TASK-IDS: FAIL' && echo ok || echo no)" "rc=$rc out=$out"
rm -rf "$tmp"
# T8.b emit-context(+parse-dag): 정상 FID + cwd 가짜 yaml(안 맞는 단일 task) → 실 YAML 로 EMIT: 2 files
tmp=$(mktemp -d); mkdir -p "$tmp/.specops/20260902-shadow-emit"; cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/20260902-shadow-emit/"; _shadow "$tmp"
out=$(cd "$tmp" && bash "$EMIT" 20260902-shadow-emit 2>&1); rc=$?
_pf "T8.b cwd yaml.py 가짜 주입에도 emit 이 실 YAML 로 산출" "$([ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'EMIT: 2 files' && echo ok || echo no)" "rc=$rc out=$out"
rm -rf "$tmp"

# ── 20261007-fid-size-exempt-log — 예외 라벨 사용을 friction-log 에 남긴다 (자기발급 면제의 측정 가능성) ──
# T9.a 10+ 태스크 + 예외 라벨 → WARN 통과하면서 FID 의 friction-log 에 FID-SIZE-EXEMPT 1건(라벨·태스크 수 포함)
tmp=$(mktemp -d); mk_fs_fixture "$tmp" 20261007-fsx-log 10 y '**§auto**: true'; fs_run "$tmp" 20261007-fsx-log
fl="$tmp/.specops/20261007-fsx-log/friction-log.jsonl"
_pf "T9.a 예외 라벨 사용 → friction-log FID-SIZE-EXEMPT 기록" "$([ "$rc" -eq 0 ] && [ -f "$fl" ] && [ "$(jq -sr '[.[]|select(.rule_id=="FID-SIZE-EXEMPT")]|length' "$fl")" -eq 1 ] && jq -sr '.[0].evidence_snippet' "$fl" | grep -q '§auto' && jq -sr '.[0].evidence_snippet' "$fl" | grep -q '10' && echo ok || echo no)" "rc=$rc fl=$(cat "$fl" 2>/dev/null | head -2)"
# T9.b 같은 FID 재실행해도 중복 기록 없음(dedup) · 비예외 경로(PASS·WARN 7~9·FAIL)는 기록 없음
fs_run "$tmp" 20261007-fsx-log
n1=$(jq -sr '[.[]|select(.rule_id=="FID-SIZE-EXEMPT")]|length' "$fl" 2>/dev/null)
mk_fs_fixture "$tmp" 20261007-fs-nolog 7 y; fs_run "$tmp" 20261007-fs-nolog; r7=$rc
mk_fs_fixture "$tmp" 20261007-fs-nolog2 10 y; fs_run "$tmp" 20261007-fs-nolog2; r10=$rc
_pf "T9.b 재실행 dedup · 7~9 WARN·대화형 FAIL 은 기록 없음" "$([ "$n1" = "1" ] && [ "$r7" -eq 0 ] && [ "$r10" -eq 1 ] && [ ! -f "$tmp/.specops/20261007-fs-nolog/friction-log.jsonl" ] && [ ! -f "$tmp/.specops/20261007-fs-nolog2/friction-log.jsonl" ] && echo ok || echo no)" "n1=$n1 r7=$r7 r10=$r10"
# T9.c 기록 실패(.specops/FID 가 symlink)여도 판정은 불변 — WARN rc=0 유지(기록은 부수효과)
rm -rf "$tmp"; tmp=$(mktemp -d); mk_fs_fixture "$tmp" 20261007-fsx-sym 10 y '**§batch**: batch-20261007'
mv "$tmp/.specops/20261007-fsx-sym" "$tmp/real-fid"; ln -s "$tmp/real-fid" "$tmp/.specops/20261007-fsx-sym"
fs_run "$tmp" 20261007-fsx-sym
_pf "T9.c friction 기록 거부(symlink)여도 판정 불변 WARN rc=0" "$([ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'FID-SIZE: WARN' && echo ok || echo no)" "rc=$rc out=$out"
rm -rf "$tmp"

# ── 20261007-fable-tips — dispatch-context §7 실행 모드 (리프 서브에이전트에 무인 계약 전달) ──
# T10.a 모드 판정: spec.md 줄 선두 라벨 → single|auto|batch (줄 중간 언급은 라벨이 아니다)
okm=ok
for case in 'single|# spec' 'auto|**§auto**: true' 'batch|**§batch**: batch-20261007' 'single|참고: **§auto**: true 모드는 자동통과한다'; do
  want=${case%%|*}; lab=${case#*|}
  tmp=$(mktemp -d); mkdir -p "$tmp/.specops/20260902-mode"; cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/20260902-mode/"
  printf '\n%s\n' "$lab" >> "$tmp/.specops/20260902-mode/spec.md"
  (cd "$tmp" && bash "$EMIT" 20260902-mode >/dev/null 2>&1); f="$tmp/.specops/20260902-mode/dispatch/T1-context.md"
  got=$(sed -n 's/^- 모드: \([a-z]*\).*/\1/p' "$f" 2>/dev/null | head -1)
  [ "$got" = "$want" ] || { okm=no; echo "  (모드 오판: want=$want got=$got label=$lab)"; }
  rm -rf "$tmp"
done
_pf "T10.a 실행 모드 라벨 판정(single·auto·batch·줄 중간 무시)" "$okm"
# T10.b §7 본문 계약: 사용자 채널 없음 · 질문은 시작 시 한 번에 · 나머지 끝까지 · 비가역은 먼저 NEEDS_APPROVAL
tmp=$(mktemp -d); mkdir -p "$tmp/.specops/20260902-mode"; cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/20260902-mode/"
(cd "$tmp" && bash "$EMIT" 20260902-mode >/dev/null 2>&1); f="$tmp/.specops/20260902-mode/dispatch/T1-context.md"
sec=$(awk '/^## 7\. 실행 모드/{on=1;print;next} /^## /{on=0} on' "$f" 2>/dev/null)
miss=""; for t in '사용자와 직접 대화할 수 없다' '한 번에' '의존 없는 나머지' 'NEEDS_APPROVAL' 'repo 밖에 흔적을 남기는 실행'; do printf '%s' "$sec" | grep -qF -- "$t" || miss="$miss [$t]"; done
_pf "T10.b §7 본문 계약 5항목(repo 밖 흔적 포함)" "$([ -n "$sec" ] && [ -z "$miss" ] && echo ok || echo no)" "누락=$miss"
# T10.c §7 이 있어도 validate-context(5 컨텍스트 검증)는 통과한다
# 부모(implementing-ko)가 dispatch 직전 §5 의 <repo-root> 를 sed 갱신한 뒤의 상태를 흉내낸다
sed -i.bak "s#<repo-root>#$tmp#" "$f"; rm -f "$f.bak"
(cd "$tmp" && bash "$PLUGIN/scripts/dag/validate-context.sh" ".specops/20260902-mode/dispatch/T1-context.md" >/dev/null 2>&1); rcv=$?
_pf "T10.c §7 포함 context 가 validate-context 통과" "$([ "$rcv" -eq 0 ] && echo ok || echo no)" "rc=$rcv"
rm -rf "$tmp"

# ── 20261009 /start-foundation 점검 묶음 B — 공통부 재사용 선언을 구현자 컨텍스트에 싣는다 ──
# 결함: 재사용 게이트는 tasks.md 에 선언이 적혔는지만 봤고, dispatch 컨텍스트(§6)에는 api-spec·data-model·screens 뿐이라
#   구현자·리뷰어는 manifest(경로·사용법)를 받지 못했다 — 선언은 강제하는데 실제 사용으로는 이어지지 않았다.
fnd_mk() {  # $1=tmp $2=fid $3=§유형 $4=manifest(y|n) $5=T1 선언 줄
  mkdir -p "$1/.specops/$2" "$1/.specops/memory"; cp "$FIXTURES/ok-fid"/*.md "$1/.specops/$2/"
  printf '\n**§유형**: %s\n' "$3" >> "$1/.specops/$2/spec.md"
  [ "$4" = y ] && printf '# Foundation Manifest\n\n| 모듈 | 경로 | 역할 | 재사용 방법 |\n|---|---|---|---|\n| 라우팅 | `src/router.ts` | 경로 표 | `import { router }` |\n' \
    > "$1/.specops/memory/foundation-manifest.md"
  python3 -I - "$1/.specops/$2/tasks.md" "$5" <<'PYEOF'
import sys
p, decl = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
head = "## Task 1: parser\n\n" + (decl + "\n\n" if decl else "") + "## Task 2: writer\n\n**미재사용 근거**: 출력 전용 — 공통부 범위 밖\n\n"
open(p, "w", encoding="utf-8").write(s.replace("## 의존 그래프", head + "## 의존 그래프", 1))
PYEOF
}
# T11.a manifest 가 있고 비-foundation FID → 각 태스크 컨텍스트에 manifest 경로와 **그 태스크의** 선언
tmp=$(mktemp -d); fnd_mk "$tmp" 20260902-fnd 신규 y '**재사용 foundation**: 라우팅'
out=$(cd "$tmp" && bash "$EMIT" 20260902-fnd 2>&1); rc=$?
c1="$tmp/.specops/20260902-fnd/dispatch/T1-context.md"; c2="$tmp/.specops/20260902-fnd/dispatch/T2-context.md"
_pf "T11.a manifest 경로 + 태스크별 선언이 컨텍스트에 실린다" \
  "$([ "$rc" -eq 0 ] && grep -qF '.specops/memory/foundation-manifest.md' "$c1" && grep -qF '**재사용 foundation**: 라우팅' "$c1" \
     && grep -qF '**미재사용 근거**: 출력 전용 — 공통부 범위 밖' "$c2" && ! grep -qF '라우팅' "$c2" && echo ok || echo no)" "rc=$rc out=$out"
# T11.b 설계 계약 문서가 하나도 없어도(§6 이 원래 생략되는 프로젝트) manifest 가 있으면 §6 이 나온다
_pf "T11.b api-spec·data-model·screens 없이도 §6 emit" "$(grep -q '^## 6\. ' "$c1" 2>/dev/null && echo ok || echo no)"
# T11.c validate-context 는 그대로 통과한다
sed -i.bak "s#<repo-root>#$tmp#" "$c1"; rm -f "$c1.bak"
(cd "$tmp" && bash "$PLUGIN/scripts/dag/validate-context.sh" ".specops/20260902-fnd/dispatch/T1-context.md" >/dev/null 2>&1); rcv=$?
_pf "T11.c manifest 블록이 있어도 validate-context 통과" "$([ "$rcv" -eq 0 ] && echo ok || echo no)" "rc=$rcv"
rm -rf "$tmp"
# T11.d foundation FID(생산자)·manifest 부재 → 컨텍스트에 manifest 언급 없음
okd=ok
for case in 'foundation|y' '신규|n'; do
  tmp=$(mktemp -d); fnd_mk "$tmp" 20260902-fnd "${case%%|*}" "${case#*|}" '**재사용 foundation**: 라우팅'
  (cd "$tmp" && bash "$EMIT" 20260902-fnd >/dev/null 2>&1) || okd="no(emit 실패 $case)"
  grep -qF 'foundation-manifest' "$tmp/.specops/20260902-fnd/dispatch/T1-context.md" 2>/dev/null && okd="no($case)"
  rm -rf "$tmp"
done
_pf "T11.d 생산자·manifest 부재에는 싣지 않는다" "$okd"
# T11.e 선언값에 모듈명이 없으면 emit 은 성공하되 경고가 stderr 로 중계된다 (게이트의 통과 출력은 원래 삼켜진다)
tmp=$(mktemp -d); fnd_mk "$tmp" 20260902-fnd 신규 y '**재사용 foundation**: 존재하지않는모듈XYZ'
out=$(cd "$tmp" && bash "$EMIT" 20260902-fnd 2>&1 >/dev/null); rc=$?
_pf "T11.e 모듈명 없는 선언 → EMIT 성공 + WARN 중계" "$([ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'FOUNDATION-REUSE: WARN' && echo ok || echo no)" "rc=$rc out=$out"
rm -rf "$tmp"
# T11.f 선언이 없는 태스크는 재사용 게이트가 emit 전에 막는다 — 컨텍스트 0건(원자성 유지)
tmp=$(mktemp -d); fnd_mk "$tmp" 20260902-fnd 신규 y ''
(cd "$tmp" && bash "$EMIT" 20260902-fnd >/dev/null 2>&1); rc=$?
_pf "T11.f 선언 누락 → emit 거부·dispatch 0건" "$([ "$rc" -ne 0 ] && [ ! -d "$tmp/.specops/20260902-fnd/dispatch" ] && echo ok || echo no)" "rc=$rc"
rm -rf "$tmp"

# T11.g 절 번호와 task id 가 어긋나면(절 2·3 · id T1·T2) 다른 태스크의 선언을 싣지 않는다 — manifest 경로와 사유만
tmp=$(mktemp -d); fnd_mk "$tmp" 20260902-fnd 신규 y '**재사용 foundation**: 라우팅'
sed -i.bak 's/^## Task 2: writer/## Task 3: writer/; s/^## Task 1: parser/## Task 2: parser/' "$tmp/.specops/20260902-fnd/tasks.md"; rm -f "$tmp/.specops/20260902-fnd/tasks.md.bak"
out=$(cd "$tmp" && bash "$EMIT" 20260902-fnd 2>&1 >/dev/null); rc=$?
c2="$tmp/.specops/20260902-fnd/dispatch/T2-context.md"
_pf "T11.g 번호 불일치 → 선언 미대응(잘못된 선언을 싣지 않는다) + 경고 중계" \
  "$([ "$rc" -eq 0 ] && grep -qF 'foundation-manifest.md' "$c2" && grep -qF '대응시키지 못했다' "$c2" && ! grep -qF '**재사용 foundation**: 라우팅' "$c2" \
     && printf '%s' "$out" | grep -q '번호가 어긋' && echo ok || echo no)" "rc=$rc out=$out"
rm -rf "$tmp"

# T6.q foundation 은 예외가 아니다 (20261009) — /start-foundation 은 대화형이라 나눌 수 있다.
#   실기록 foundation FID 3건이 10·11·21 태스크였고 21건짜리는 32시간이 걸리고 plan 리뷰가 2회 FAIL 했다.
#   manifest 가 행을 더하는 문서가 되어(같은 릴리즈) 공통부를 층별 FID 로 나눌 수 있다.
tmp=$(mktemp -d); mk_fs_fixture "$tmp" 20261007-fsq 10 y "# spec
**§유형**: foundation"; fs_run "$tmp" 20261007-fsq
_pf "T6.q foundation 10 태스크 → 계획행이 있어도 FAIL · 층별 분할 안내" \
  "$([ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'FID-SIZE: FAIL' && printf '%s' "$out" | grep -q '층별' && printf '%s' "$out" | grep -q '/start-foundation' && echo ok || echo no)" "rc=$rc out=$out"
[ ! -f "$tmp/.specops/20261007-fsq/friction-log.jsonl" ] && _pf "T6.s 차단된 foundation 은 예외 사용 기록을 남기지 않는다" ok || _pf "T6.s 차단된 foundation 은 예외 사용 기록을 남기지 않는다" no "friction-log 생성됨"
# 9 태스크까지는 종전대로 계획행 + 경고로 통과한다 (경계)
mk_fs_fixture "$tmp" 20261007-fsq9 9 y "# spec
**§유형**: foundation"; fs_run "$tmp" 20261007-fsq9
_pf "T6.t foundation 9 태스크 + 계획행 → WARN 통과(경계)" "$([ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'FID-SIZE: WARN' && echo ok || echo no)" "rc=$rc out=$out"
# 무인 표지가 함께 있으면 물을 채널이 없으므로 종전 예외 그대로다
mk_fs_fixture "$tmp" 20261007-fsqa 10 y "# spec
**§유형**: foundation
**§auto**: true"; fs_run "$tmp" 20261007-fsqa
_pf "T6.u foundation + §auto 10 태스크 → §auto 예외로 WARN 통과" "$([ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '§auto 예외' && echo ok || echo no)" "rc=$rc out=$out"
mk_fs_fixture "$tmp" 20261007-fsq2 10 y "# spec
**§auto**: true"; fs_run "$tmp" 20261007-fsq2
_pf "T6.r §auto 예외는 종전 사유(사용자 채널 없음) 그대로 · 층별 분할 안내 없음" \
  "$([ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '사용자 채널이 없어' && ! printf '%s' "$out" | grep -q '층별로 나눠' && echo ok || echo no)" "rc=$rc out=$out"
rm -rf "$tmp"

# T12.a foundation FID · 아키텍처 문서 없음 · 스택 근거 없음 → emit 은 성공하고 알림(STACK-DECIDED: NOTE)이 stderr 로 중계된다
#   (게이트의 통과 출력은 삼켜지므로 중계하지 않으면 "검사하지 않았다" 는 사실이 보이지 않는다)
tmp=$(mktemp -d); mkdir -p "$tmp/.specops/20260902-fstk" "$tmp/.specops/memory"; cp "$FIXTURES/ok-fid"/*.md "$tmp/.specops/20260902-fstk/"
printf '\n**§유형**: foundation\n' >> "$tmp/.specops/20260902-fstk/spec.md"
err=$(cd "$tmp" && bash "$EMIT" 20260902-fstk 2>&1 >/dev/null); rc=$?
_pf "T12.a 스택 미검사 알림이 emit stderr 로 중계" "$([ "$rc" -eq 0 ] && printf '%s' "$err" | grep -q '^STACK-DECIDED: NOTE' && [ -f "$tmp/.specops/20260902-fstk/dispatch/T1-context.md" ] && echo ok || echo no)" "rc=$rc err=$err"
# 근거가 있으면 조용하다
printf '| DECISION-ID | 주제 | 확정값 | 출처 | 갱신일 |\n|---|---|---|---|---|\n| D-002 | 구현 언어 | Python 3.12 | init | 2026-10-09 |\n' > "$tmp/.specops/memory/decisions.md"
err=$(cd "$tmp" && bash "$EMIT" 20260902-fstk 2>&1 >/dev/null); rc=$?
_pf "T12.b 원장에 스택 근거가 있으면 알림 없음" "$([ "$rc" -eq 0 ] && ! printf '%s' "$err" | grep -q 'STACK-DECIDED' && echo ok || echo no)" "rc=$rc err=$err"
rm -rf "$tmp"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
