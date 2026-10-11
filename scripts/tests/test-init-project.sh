#!/usr/bin/env bash
# T19 — /init-project 통합 테스트 (FID 20260507-start-project-bootstrap)
# 14 테스트: KIND 매트릭스 (T1~T4) + skip/conflict/git (T5~T7) + deprecate (T8)
#          + 인용 검증 (T9~T11) + screens (T12) + memory 재실행 (T13) + DB 분기 (T14)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

SCRIPT="$PLUGIN/scripts/_internal/init-project.sh"

# ── 헬퍼 ──────────────────────────────────────
TMPDIR=""
setup_fixture() {
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  git init -q
  git config user.email test@test
  git config user.name test
}
teardown_fixture() {
  cd /tmp
  rm -rf "$TMPDIR"
  TMPDIR=""
}

# 활성 산출물 카운트
count_active() {
  local n=0 f
  for f in PRD.md CLAUDE.md README.md DESIGN.md \
    .specops/memory/{process-design,constitution,requirements,test-strategy,architecture,frontend-architecture,backend-architecture,api-spec,api-spec-consumer,data-model,screens-overview}.md; do
    [ -f "$f" ] && n=$((n+1))
  done
  echo "$n"
}

# 표준 풀스택 stdin (KIND=4) — 14종 모두 활성
fullstack_stdin() {
  printf "4\np1\np2\np3\np4\np5\n"
  printf "1. 한 줄: 풀스택 데모\n2. 페르소나: dev\n3. 가치: a, b, c\n4. M1: m1\n5. M2: m2\n6. M3: m3\n\n"
  printf "1\nhome, login\ny\n2\n"  # direction=1, screens, DB=y, API=OpenAPI
}

# ── T1.a UI (KIND=1) ──────────────────────────
setup_fixture
{
  printf "1\np1\np2\np3\np4\np5\n"
  printf "1. UI app\n2. user\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "1\nhome\nn\nn\n"  # 방향=1, screens=home, DB=n, consumer=n
} | bash "$SCRIPT" >/dev/null 2>&1
if [ -f DESIGN.md ] && [ -f .specops/memory/frontend-architecture.md ] \
   && [ -f .specops/memory/screens-overview.md ] \
   && [ ! -f .specops/memory/backend-architecture.md ] \
   && [ ! -f .specops/memory/api-spec.md ] \
   && [ ! -f .specops/memory/api-spec-consumer.md ]; then
  ok "T1.a UI(KIND=1) → DESIGN/frontend/screens-overview 활성, backend/api/consumer 부재"
else
  nope "T1.a UI" "활성 매트릭스 mismatch (count=$(count_active))"
fi
teardown_fixture

# ── T1.b UI(KIND=1) consumer=y → api-spec-consumer.md 생성 + git 추적 (M1 회귀) ──
setup_fixture
{
  printf "1\np1\np2\np3\np4\np5\n"
  printf "1. UI app\n2. user\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "1\nhome\nn\ny\n"  # 방향=1, screens=home, DB=n, consumer=y
} | bash "$SCRIPT" >/dev/null 2>&1
if [ -f .specops/memory/api-spec-consumer.md ] \
   && git ls-files --error-unmatch .specops/memory/api-spec-consumer.md >/dev/null 2>&1; then
  ok "T1.b UI consumer=y → api-spec-consumer.md 생성 + git 추적 (고아 방지 M1)"
else
  nope "T1.b consumer 고아" "consumer.md 미생성 또는 git 미추적 (phase_10 memory add 누락)"
fi
teardown_fixture

# ── T2.a 백엔드 (KIND=2) ──────────────────────
setup_fixture
{
  printf "2\np1\np2\np3\np4\np5\n"
  printf "1. BE\n2. dev\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "y\n2\n"  # DB=y, API=OpenAPI
} | bash "$SCRIPT" >/dev/null 2>&1
if [ -f .specops/memory/backend-architecture.md ] \
   && [ -f .specops/memory/api-spec.md ] \
   && [ -f .specops/memory/data-model.md ] \
   && [ ! -f DESIGN.md ] \
   && [ ! -f .specops/memory/screens-overview.md ]; then
  ok "T2.a BE(KIND=2) → backend/api/data 활성, DESIGN/screens 부재"
else
  nope "T2.a BE" "매트릭스 mismatch"
fi
teardown_fixture

# ── T3.a CLI (KIND=3) ─────────────────────────
setup_fixture
{
  printf "3\np1\np2\np3\np4\np5\n"
  printf "1. CLI\n2. dev\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "n\n"  # DB=n
} | bash "$SCRIPT" >/dev/null 2>&1
# CLI: PRD/CLAUDE/README/constitution/requirements/test-strategy/process-design = 7종
n=$(count_active)
if [ "$n" = "7" ] && [ -f .specops/memory/process-design.md ] \
   && [ ! -f DESIGN.md ] \
   && [ ! -f .specops/memory/architecture.md ] \
   && [ ! -f .specops/memory/frontend-architecture.md ] \
   && [ ! -f .specops/memory/backend-architecture.md ]; then
  ok "T3.a CLI(KIND=3) → 7종 (PRD/CLAUDE/README/constitution/requirements/test-strategy/process-design)"
else
  nope "T3.a CLI" "활성 카운트=${n} (기대 7), architecture 부재 검증"
fi
teardown_fixture

# ── T4.a 풀스택 (KIND=4) → 14종 ───────────────
setup_fixture
fullstack_stdin | bash "$SCRIPT" >/dev/null 2>&1
n=$(count_active)
if [ "$n" = "14" ] && ! grep -q "<프로젝트명>" .specops/memory/process-design.md; then
  ok "T4.a Full(KIND=4) → 14종 모두 활성 (process-design 골격 포함·프로젝트명 치환)"
else
  nope "T4.a Full" "활성=${n} (기대 14)"
fi
teardown_fixture

# ── T5.a 헌법 'skip' → constitution placeholder 유지 ──
setup_fixture
{
  printf "3\nskip\n"  # KIND=CLI, 헌법=skip
  printf "1. x\n2. y\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "n\n"
} | bash "$SCRIPT" >/dev/null 2>&1
if [ -f .specops/memory/constitution.md ] \
   && grep -q '<PRINCIPLE_1_NAME>' .specops/memory/constitution.md; then
  ok "T5.a 헌법 'skip' → constitution.md placeholder 유지"
else
  nope "T5.a skip" "constitution placeholder 미유지"
fi
teardown_fixture

# ── T6.a git init 안 된 디렉토리 → exit 1 ─────
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
out=$(bash "$SCRIPT" 2>&1)
ec=$?
cd /tmp && rm -rf "$TMPDIR"
if [ "$ec" = "1" ] && echo "$out" | grep -q "git 저장소가 아닙니다"; then
  ok "T6.a git 미초기화 → exit 1 + stderr 메시지"
else
  nope "T6.a git" "exit=${ec}, out=$(echo "$out" | head -1)"
fi

# ── T7.a 기존 PRD.md + skip 정책 → 보존 ───────
setup_fixture
echo "# 보존 마커" > PRD.md
echo "기존 내용" >> PRD.md
{
  printf "3\nskip\n"  # KIND=CLI
  printf "skip\n"   # CONFLICT_POLICY=skip (1개 충돌)
  printf "\n"       # phase_4 numbered list 빈 입력 — 즉시 sentinel
  printf "n\n"      # DB=n
} | bash "$SCRIPT" >/dev/null 2>&1
if grep -q "보존 마커" PRD.md; then
  ok "T7.a 기존 PRD.md + skip 정책 → 보존 (마커 유지)"
else
  nope "T7.a skip-policy" "PRD.md 덮어써짐 또는 손상"
fi
teardown_fixture

# ── T8.a start-design.md 삭제 확인 (/init-project 통합 완료) ──
if [ ! -f "$PLUGIN/commands/start-design.md" ]; then
  ok "T8.a commands/start-design.md 삭제됨 (/init-project 통합 완료)"
else
  nope "T8.a start-design 잔존" "start-design.md 가 아직 존재함 — 삭제 필요"
fi

# ── T9.a constitution 5원칙 → CLAUDE.md §컨벤션 인용 ──
setup_fixture
fullstack_stdin | bash "$SCRIPT" >/dev/null 2>&1
got=$(grep -c '^- 원칙 [1-5]:' CLAUDE.md 2>/dev/null || echo 0)
if [ "$got" = "5" ]; then
  ok "T9.a CLAUDE.md §코딩 컨벤션 → 원칙 5개 인용"
else
  nope "T9.a CLAUDE 인용" "원칙 라인 ${got}개 (기대 5)"
fi
teardown_fixture

# ── T10.a PRD §1 → CLAUDE.md + README.md 동일 인용 ──
setup_fixture
fullstack_stdin | bash "$SCRIPT" >/dev/null 2>&1
prd=$(grep -m1 '^\*\*한 줄 설명\*\*:' PRD.md | sed 's/^\*\*한 줄 설명\*\*: *//')
in_claude=$(grep -c "$prd" CLAUDE.md 2>/dev/null || echo 0)
in_readme=$(grep -c "$prd" README.md 2>/dev/null || echo 0)
if [ -n "$prd" ] && [ "$in_claude" -ge 1 ] && [ "$in_readme" -ge 1 ]; then
  ok "T10.a PRD §1 한 줄 → CLAUDE/README 모두 인용"
else
  nope "T10.a 인용" "prd='$prd' claude=${in_claude} readme=${in_readme}"
fi
teardown_fixture

# ── T11.a api-spec.md (KIND=2, m=2) → OpenAPI 섹션만 포함, GraphQL 제거 ──
setup_fixture
{
  printf "2\np1\np2\np3\np4\np5\n"
  printf "1. BE\n2. dev\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "n\n2\n"  # DB=n, API=OpenAPI
} | bash "$SCRIPT" >/dev/null 2>&1
if grep -q 'openapi: 3.1' .specops/memory/api-spec.md 2>/dev/null \
   && ! grep -q 'type Query {' .specops/memory/api-spec.md 2>/dev/null \
   && ! grep -q 'type Mutation {' .specops/memory/api-spec.md 2>/dev/null; then
  ok "T11.a api-spec.md OpenAPI 섹션만 포함 (GraphQL·RPC 제거됨)"
else
  nope "T11.a api-spec 섹션 스트리핑" "OpenAPI 전용 섹션 분리 실패"
fi
teardown_fixture

# ── T11.b api-spec.md (KIND=2, m=2) → §2 체크박스 활성 + 라벨 ──
setup_fixture
{
  printf "2\np1\np2\np3\np4\np5\n"
  printf "1. BE\n2. dev\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "n\n2\n"  # DB=n, API=OpenAPI(2)
} | bash "$SCRIPT" >/dev/null 2>&1
if grep -q '\[x\] §2 ' .specops/memory/api-spec.md 2>/dev/null \
   && grep -q 'OpenAPI 3.1 YAML (§2)' .specops/memory/api-spec.md 2>/dev/null \
   && grep -q '\[ \] §1 ' .specops/memory/api-spec.md 2>/dev/null; then
  ok "T11.b api-spec.md §2 체크박스 활성 + 라벨 주입, §1 미선택"
else
  cb=$(grep '§2' .specops/memory/api-spec.md 2>/dev/null | head -1)
  nope "T11.b api-spec 체크박스/라벨" "got: $cb"
fi
teardown_fixture

# ── T11.c api-spec.md (KIND=2, m=3) → GraphQL 섹션만 포함, §5·§6·§7 유지 ──
setup_fixture
{
  printf "2\np1\np2\np3\np4\np5\n"
  printf "1. BE\n2. dev\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "n\n3\n"  # DB=n, API=GraphQL
} | bash "$SCRIPT" >/dev/null 2>&1
if grep -q 'GraphQL' .specops/memory/api-spec.md 2>/dev/null \
   && ! grep -q 'openapi: 3.1' .specops/memory/api-spec.md 2>/dev/null \
   && grep -q '§5\. 인증' .specops/memory/api-spec.md 2>/dev/null; then
  ok "T11.c api-spec.md GraphQL 섹션만 포함 + §5 유지"
else
  nope "T11.c api-spec GraphQL 스트리핑" "GraphQL 전용 섹션 분리 실패"
fi
teardown_fixture

# ── T12.a 화면 이름 목록 → screens-overview 표만 (screens/* 껍데기 미생성) ──
setup_fixture
{
  printf "1\np1\np2\np3\np4\np5\n"
  printf "1. x\n2. y\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "1\nhome, dashboard\nn\n"
} | bash "$SCRIPT" >/dev/null 2>&1
if [ ! -f screens/home.md ] && [ ! -f screens/home.html ] \
   && [ ! -f screens/dashboard.md ] \
   && grep -qE '^\| home \|.*예정' .specops/memory/screens-overview.md \
   && grep -qE '^\| dashboard \|.*예정' .specops/memory/screens-overview.md \
   && grep -q 'stateDiagram' .specops/memory/screens-overview.md; then
  ok "T12.a 화면 입력 → overview 목록만 (screens/* 미생성)"
else
  nope "T12.a screens" "overview 누락 또는 screens 껍데기 생성됨"
fi
teardown_fixture

# ── T13.a .specops/memory/ 이미 존재 + n → 종료 ──
setup_fixture
mkdir -p .specops/memory
echo "기존" > .specops/memory/marker.md
out=$(printf "n\n" | bash "$SCRIPT" 2>&1)
ec=$?
if [ "$ec" = "0" ] && echo "$out" | grep -q "이미 존재" && [ -f .specops/memory/marker.md ]; then
  ok "T13.a .specops/memory/ 존재 + n → 안내 후 종료, marker 보존"
else
  nope "T13.a memory 재실행" "exit=${ec}, marker $([ -f .specops/memory/marker.md ] && echo 존재 || echo 손실)"
fi
teardown_fixture

# ── T14.a Phase 8e DB y vs n 응답별 ───────────
setup_fixture
{
  printf "3\np1\np2\np3\np4\np5\n"
  printf "1. CLI\n2. y\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "y\n"  # DB=y
} | bash "$SCRIPT" >/dev/null 2>&1
y_present=0
[ -f .specops/memory/data-model.md ] && y_present=1
teardown_fixture

setup_fixture
{
  printf "3\np1\np2\np3\np4\np5\n"
  printf "1. CLI\n2. y\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "n\n"  # DB=n
} | bash "$SCRIPT" >/dev/null 2>&1
n_absent=0
[ ! -f .specops/memory/data-model.md ] && n_absent=1
teardown_fixture

if [ "$y_present" = "1" ] && [ "$n_absent" = "1" ]; then
  ok "T14.a Phase 8e DB → y 시 data-model.md 생성, n 시 부재"
else
  nope "T14.a 8e DB" "y_present=${y_present} n_absent=${n_absent}"
fi

# ── 코드 리뷰 fix 회귀 테스트 (C1, C2, I1) ────

# ── T15.a (C1) overwrite 정책 → 기존 PRD.md 덮어쓰기 ──
setup_fixture
echo "# OLD MARKER" > PRD.md
# stdin 순서: phase_1 충돌 정책 → phase_2 KIND → phase_3 헌법 skip → phase_4 PRD 6필드 + sentinel → phase_8e DB
#   (20261009) PRD 를 빈 sentinel 로만 주던 종전 입력은 "필드 0개 + 터미널 없음" 이라 이제 rc=2 로 멈춘다 —
#   그때는 `<TODO>` PRD 가 조용히 만들어져 통과했다. 이 테스트의 대상은 overwrite 이므로 유효한 PRD 를 준다.
{
  printf "overwrite\n"  # 충돌 정책
  printf "3\n"          # KIND=CLI
  printf "skip\n"       # 헌법 skip
  printf "1. 한 줄: 새 PRD\n2. 페르소나: dev\n3. 가치: a, b, c\n4. M1: m1\n5. M2: m2\n6. M3: m3\n\n"
  printf "n\n"          # 8e DB
} | bash "$SCRIPT" >/dev/null 2>&1
if grep -q "OLD MARKER" PRD.md; then
  nope "T15.a overwrite" "기존 OLD MARKER 가 보존됨 — overwrite 미작동"
else
  ok "T15.a (C1) overwrite 정책 → 기존 PRD.md 덮어쓰기 (마커 제거)"
fi
teardown_fixture

# ── T16.a (C1) merge → skip fallback 안내 + 보존 ─
setup_fixture
echo "# MERGE PRESERVED" > PRD.md
out=$({
  printf "merge\n"      # 충돌 정책 = merge → skip fallback
  printf "3\n"
  printf "skip\n"
  printf "\n"
  printf "n\n"
} | bash "$SCRIPT" 2>&1)
if grep -q "MERGE PRESERVED" PRD.md && echo "$out" | grep -q "merge 정책 미구현\|merge 미구현"; then
  ok "T16.a (C1) merge → skip fallback 안내 + 기존 파일 보존 (데이터 손실 차단)"
else
  nope "T16.a merge" "PRD 보존 또는 fallback 안내 부재 (out=$(echo \"$out\" | grep -i merge | head -1))"
fi
teardown_fixture

# ── T17.a (C2) screens path traversal 차단 ─────
setup_fixture
echo "# ROOT README" > README.md
{
  printf "1\np1\np2\np3\np4\np5\n"
  printf "1. x\n2. y\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "1\n"
  printf "../README\n"  # path traversal 시도
  printf "n\n"
} | bash "$SCRIPT" 2>/dev/null >/dev/null
# README.md 가 보존돼야 함 (사용자 입력으로 덮어써지지 않음)
# 단, phase_9_readme 가 README.md 를 덮어쓸 수 있음 → 그 검증 분리
if [ ! -f screens/../README.md ] || grep -q "ROOT README" screens/../README.md 2>/dev/null; then
  # 다른 검증: screens/ 안에 traversal 흔적 0
  traversal_files=$(find screens -name "*README*" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$traversal_files" = "0" ]; then
    ok "T17.a (C2) screens 입력 '../README' → 거부 + traversal 흔적 0"
  else
    nope "T17.a path traversal" "screens/ 안에 README 흔적 ${traversal_files}개"
  fi
else
  nope "T17.a path traversal" "README.md 손상"
fi
teardown_fixture

# ── T18.a (C2) 모든 invalid 화면명 → placeholder 유지 ──
setup_fixture
{
  printf "1\np1\np2\np3\np4\np5\n"
  printf "1. x\n2. y\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "1\n"
  printf "../foo, /etc/bar\n"  # 모두 invalid
  printf "n\n"
} | bash "$SCRIPT" 2>/dev/null >/dev/null
# screens/ 안에 0 file (또는 디렉토리 자체 부재)
n_files=$(find screens -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$n_files" = "0" ]; then
  ok "T18.a (C2) 모두 invalid 화면명 → screens/ 파일 0개 (placeholder 유지)"
else
  nope "T18.a invalid screens" "screens/ 안 ${n_files}개 (기대 0)"
fi
teardown_fixture

# ── I2 회귀: screens-table fence 안정성 ──

# T19.a (I2) fence 내부 행이 home/login/dashboard 가 아닌 다른 이름으로 바뀌어도
# _rebuild_screens_table 이 정상 동작 (예시 행 이름 비의존)
setup_fixture
# 사용자가 templates/screens-overview.md 의 예시 행을 변경한 환경 시뮬:
# fence 내부 행을 임의 이름으로 변조 후 phase_7 호출
{
  printf "1\np1\np2\np3\np4\np5\n"
  printf "1. x\n2. y\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "1\nproductlist\nn\n"
} | bash "$SCRIPT" >/dev/null 2>&1
# 새 화면 productlist 만 표에 존재 + 기존 예시 (home/login/dashboard) 행 부재
if grep -qE '^\| productlist \| productlist \| 예정' .specops/memory/screens-overview.md \
   && ! grep -E '^\| (home|login|dashboard) \| (홈|로그인|대시보드)' .specops/memory/screens-overview.md; then
  ok "T19.a (I2) screens-table fence → 사용자 입력 1건만 + 예시 행 제거"
else
  nope "T19.a fence" "예시 행 잔존 또는 신규 행 누락"
fi
teardown_fixture

# ── T20.a --help 에 --resume 설명 포함 ──
out=$(bash "$SCRIPT" --help 2>&1)
if echo "$out" | grep -q "\-\-resume"; then
  ok "T20.a --help 에 --resume 설명 포함"
else
  nope "T20.a --help resume" "--resume 설명 없음"
fi

# ── T21.a resume 모드: .specops/memory/ 존재 + RESUME_MODE=1 → 재확인 프롬프트 없이 통과 ──
setup_fixture
mkdir -p .specops/memory
echo "[sentinel]" > .specops/memory/constitution.md
# RESUME_MODE=1 + 프로젝트명 없음 → _check_memory 에서 prompt 없이 통과하고 Phase 2로 진행
# Phase 2 진입 전에 Ctrl-C 격인 early-exit stdin 을 보내도 Phase 1 (memory 검사) 은 통과 확인
out_r=$(echo "" | RESUME_MODE=1 bash "$SCRIPT" 2>&1 || true)
# "재부트스트랩 진행?" 가 출력되지 않으면 PASS
if ! echo "$out_r" | grep -q "재부트스트랩"; then
  ok "T21.a resume + memory 존재 → 재확인 프롬프트 없이 통과"
else
  nope "T21.a resume memory" "재부트스트랩 프롬프트 출력됨"
fi
teardown_fixture

# ── T21.b resume 모드: 충돌 파일 존재 + RESUME_MODE=1 → CONFLICT_POLICY=skip 자동 설정 ──
setup_fixture
echo "existing" > PRD.md
out_b=$(echo "" | RESUME_MODE=1 bash "$SCRIPT" 2>&1 || true)
# 충돌 정책 프롬프트가 출력되지 않으면 PASS
if ! echo "$out_b" | grep -q "충돌 파일.*개 감지\|기존 파일 처리 정책"; then
  ok "T21.b resume + 충돌 파일 존재 → 충돌 정책 프롬프트 없이 skip 자동 설정"
else
  nope "T21.b resume conflict" "충돌 정책 프롬프트 출력됨"
fi
teardown_fixture

# ── T21.c --resume 인자(플래그 직접) → RESUME_MODE 활성 + 재확인 프롬프트 없음 ──
setup_fixture
mkdir -p .specops/memory
echo "[sentinel]" > .specops/memory/constitution.md
out_c=$(echo "" | bash "$SCRIPT" --resume 2>&1 || true)
# [resume 모드] 안내 출력 + 재부트스트랩 프롬프트 없음
if echo "$out_c" | grep -q "\[resume 모드\]" && ! echo "$out_c" | grep -q "재부트스트랩"; then
  ok "T21.c --resume 인자(플래그) → resume 모드 진입 + 재확인 프롬프트 없음"
else
  nope "T21.c --resume flag" "[resume 모드] 미출력 또는 재부트스트랩 프롬프트 출력됨"
fi
teardown_fixture

# ── T22.a commands/init-project.md 에 --resume 문서화 ──
if grep -q "\-\-resume" "$PLUGIN/commands/init-project.md"; then
  ok "T22.a commands/init-project.md 에 --resume 문서화"
else
  nope "T22.a resume docs" "--resume 언급 없음"
fi

# ── T23.a --resume MyProject → PROJECT_NAME=MyProject (CLAUDE.md 등에 치환됨) ──
setup_fixture
{
  printf "3\np1\np2\np3\np4\np5\n"
  printf "1. cli tool\n2. dev\n3. bash\n4. m1\n5. m2\n6. m3\n\n"
  printf "n\n"
} | bash "$SCRIPT" --resume MyProject >/dev/null 2>&1 || true
if [ -f README.md ] && grep -q "MyProject" README.md; then
  ok "T23.a --resume <project-name> → PROJECT_NAME=MyProject README.md 치환됨"
else
  nope "T23.a resume+name" "README.md 미생성 또는 MyProject 치환 안됨"
fi
teardown_fixture

# ── T24.a merge 정책 선택 → stderr ⚠️ 경고 + skip fallback ──
setup_fixture
echo "existing" > PRD.md
out_24=$(printf 'merge\n' | bash "$SCRIPT" 2>&1 || true)
if echo "$out_24" | grep -q "merge 정책 미구현\|merge.*fallback\|fallback.*merge"; then
  ok "T24.a merge 정책 → ⚠️ 경고 + skip fallback"
else
  nope "T24.a merge warning" "merge fallback 경고 미출력 (out='$(echo "$out_24" | head -5)')"
fi
teardown_fixture

# ── T25.a _replace_line_prefix 백슬래시 escape 회귀 ──
T25=$(mktemp)
printf '**한 줄 설명**: <placeholder>\n' > "$T25"
( source "$SCRIPT" 2>/dev/null
  _replace_line_prefix "$T25" '**한 줄 설명**:' '**한 줄 설명**: 경로\test\new' )
if grep -qF '경로\test\new' "$T25"; then
  ok "T25.a _replace_line_prefix 백슬래시 원문 보존"
else
  nope "T25.a 백슬래시" "escape 확장됨 (awk -v 미전환)"
fi
rm -f "$T25"

# ── T15.a UI(KIND=1) consumer=y → api-spec-consumer.md 생성 ──────────────────
setup_fixture
{
  printf "1\np1\np2\np3\np4\np5\n"
  printf "1. UI consumer\n2. user\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "1\nhome\nn\ny\n"  # 방향=1, screens=home, DB=n, consumer=y
} | bash "$SCRIPT" >/dev/null 2>&1
if [ -f .specops/memory/api-spec-consumer.md ] \
   && ! grep -q '<PROJECT_NAME>' .specops/memory/api-spec-consumer.md; then
  ok "T15.a UI(KIND=1) consumer=y → api-spec-consumer.md 생성 + PROJECT_NAME 치환"
else
  nope "T15.a consumer=y" "파일 미생성 또는 PROJECT_NAME 미치환"
fi
teardown_fixture

# ── 결과 ──────────────────────────────────────
echo ""

# ── T26: Phase 7 은 screens 껍데기 미생성 (본설계는 start-all 2.5) ──
setup_fixture
{
  printf "1\np1\np2\np3\np4\np5\n"
  printf "1. UI app\n2. user\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "1\nhome\nn\nn\n"
} | bash "$SCRIPT" >/dev/null 2>&1
if [ ! -f screens/home.html ] && [ ! -f screens/home.md ] \
   && grep -qE '^\| home \|.*예정' .specops/memory/screens-overview.md; then
  ok "T26.a Phase 7 screens/* 미생성 + overview 목록만"
else
  nope "T26.a Phase 7 껍데기 금지" "screens/home 생성됨 또는 overview 누락"
fi
teardown_fixture

# ── T27: Phase 0 .init-prd-fields → Phase 4 재입력 생략 ──
setup_fixture
mkdir -p .specops
printf '한 줄 from phase0\n페르소나P0\na, b, c\nm1p0\nm2p0\nm3p0\n' > .specops/.init-prd-fields
{
  printf "3\nskip\nN\n"
} | bash "$SCRIPT" >/dev/null 2>&1
if grep -q '한 줄 from phase0' PRD.md \
   && [ ! -f .specops/.init-prd-fields ] \
   && [ -f .specops/memory/project-context.md ] \
   && [ -f .specops/memory/decisions.md ]; then
  ok "T27.a Phase 0 .init-prd-fields → PRD 반영 + 원장 골격"
else
  nope "T27.a phase0 fields" "PRD/원장/필드파일 소비 실패"
fi
teardown_fixture

# ── T23: Phase 0 기존 기획 문서 3단 탐색 배선 (20260716 — prd.md auto-discovery) ──
#   실무는 PRD 가 이미 파일로 존재 — brainstorming-*.md 만 감지하면 온보딩 마찰.
CMD_DOC="$PLUGIN/commands/init-project.md"
n=$(grep -c '0-c. 기존 기획 문서 auto-discovery' "$CMD_DOC")
if [ "$n" -eq 1 ] && grep -q '0-a. 명시 경로' "$CMD_DOC" \
   && grep -q 'PRD 초안 근거로 사용할까요' "$CMD_DOC" \
   && grep -q '사전 문서(브레인스토밍 메모 · Phase 0 에서 사용자가 확인한 기존 기획 문서)' "$CMD_DOC"; then
  ok "T23.a Phase 0 3단 탐색 (명시경로·메모·discovery) + 사용자 확인 + 근거4원 동기"
else
  nope "T23.a Phase 0 discovery 배선" "n=$n 또는 구성요소 누락"
fi

# ── T24: PRD 6필드 **값** 정합 (20260806) ────────────────────────────────────
# 기존 E2E 는 파일 존재·개수만 봐서, 무라벨 numbered list 가 값에 "1. " 를 남긴 채로도
# 전부 PASS 했다. 값이 PRD §1 → CLAUDE.md → README.md → requirements FR 시드까지
# 전파되므로 **한 곳이라도 오염되면 프로젝트 문서 전체가 오염**된다.
setup_fixture
{
  printf "4\nskip\n"
  printf "1. 사내 일정 관리\n2. 팀장\n3. 빠름, 간편, 정확\n4. 로그인\n5. 대시보드\n6. 알림\n\n"
  printf "1\nhome, login\ny\n2\n"
} | bash "$SCRIPT" mychat >/dev/null 2>&1
_one=$(grep -m1 '^\*\*한 줄 설명\*\*:' PRD.md 2>/dev/null | sed 's/^\*\*한 줄 설명\*\*: *//')
_per=$(grep -m1 '^\*\*주요 페르소나\*\*:' PRD.md 2>/dev/null | sed 's/^\*\*주요 페르소나\*\*: *//')
if [ "$_one" = "사내 일정 관리" ] && [ "$_per" = "팀장" ]; then
  ok "T24.a 무라벨 numbered list → PRD 값에 번호 미누출"
else
  nope "T24.a PRD 값 오염" "한줄='$_one' 페르소나='$_per'"
fi
if ! grep -qE '^\| FR-1 \| [0-9]+\. ' .specops/memory/requirements.md 2>/dev/null \
   && grep -q '^| FR-1 | 로그인 |' .specops/memory/requirements.md 2>/dev/null; then
  ok "T24.b requirements FR 시드행에 번호 미누출"
else
  nope "T24.b FR 시드 오염" "$(grep -m1 '^| FR-1 |' .specops/memory/requirements.md 2>/dev/null)"
fi
if ! grep -qE '^[0-9]+\. 사내 일정 관리' CLAUDE.md README.md 2>/dev/null \
   && grep -q '사내 일정 관리' README.md 2>/dev/null; then
  ok "T24.c PRD_ONELINE 전파처(CLAUDE·README) 미오염"
else
  nope "T24.c 전파 오염" "$(grep -m1 '사내 일정 관리' README.md 2>/dev/null)"
fi
teardown_fixture

# T24.d 라벨형도 동일 결과 (회귀 보호 — 두 형식 동치)
setup_fixture
{
  printf "4\nskip\n"
  printf "1. 한 줄 설명: 사내 일정 관리\n2. 페르소나: 팀장\n3. 가치: a, b, c\n4. M1: 로그인\n5. M2: 대시보드\n6. M3: 알림\n\n"
  printf "1\nhome\ny\n2\n"
} | bash "$SCRIPT" mychat >/dev/null 2>&1
_one=$(grep -m1 '^\*\*한 줄 설명\*\*:' PRD.md 2>/dev/null | sed 's/^\*\*한 줄 설명\*\*: *//')
[ "$_one" = "사내 일정 관리" ] \
  && ok "T24.d 라벨형 — 무라벨형과 동일 결과" || nope "T24.d" "한줄='$_one'"
teardown_fixture

# ── T28 repo 루트 가드 (FID 20260811-init-cwd-root-guard) ─────────
# harness.sh 에 SKIP 개념이 없어(ok/fail/nope/run/finish 5종만) 로컬 헬퍼로 구현한다.
#   사유 없는 skip 은 검증 공백을 통과로 위장하므로 FAIL 처리한다 (AC-5).
skipped() {
  if [ -z "${2:-}" ]; then
    nope "$1" "SKIP 사유 누락 — 검증 공백을 은폐함"
    return 1
  fi
  echo "SKIP $1 — $2"
}
LIB="$PLUGIN/scripts/_internal/init-project/lib.sh"

# T28.a subdir → repo 루트로 이동 + stderr 2줄 고지 (AC-2 · 구속사항 C-1)
setup_fixture
mkdir -p sub
_root=$(pwd -P)
_err_f=$(mktemp)
_out=$(cd sub && bash -c ". \"$LIB\"; _cd_repo_root; pwd -P" 2>"$_err_f")
_lines=$(grep -c . "$_err_f"); _err=$(cat "$_err_f"); rm -f "$_err_f"
if [ "$_out" = "$_root" ] && [ "$_lines" -ge 2 ]; then
  ok "T28.a subdir → repo 루트 이동 + 고지 2줄"
else
  nope "T28.a" "pwd=$_out root=$_root err줄=$_lines err=[$_err]"
fi
teardown_fixture

# T28.b repo 루트 실행 → cwd 무변경 + stderr 무출력 (AC-R-2 · 구속사항 C-2)
setup_fixture
_root=$(pwd -P)
_err_f=$(mktemp)
_out=$(bash -c ". \"$LIB\"; _cd_repo_root; pwd -P" 2>"$_err_f")
_err=$(cat "$_err_f"); rm -f "$_err_f"
if [ "$_out" = "$_root" ] && [ -z "$_err" ]; then
  ok "T28.b repo 루트 → 무변경·무출력"
else
  nope "T28.b" "pwd=$_out root=$_root err=[$_err]"
fi
teardown_fixture

# T28.c 비-git → cd 미실행 + rc=0 + 고지 무출력 (AC-4 조용한 실패 방지)
#   ★ `[init]` 부재 단언이 핵심이다 — rc=0/pwd 만 보면 `-z` 가드 제거 변이가 생존한다(실측).
_t=$(mktemp -d); _tp=$(cd "$_t" && pwd -P)
_out=$(cd "$_t" && bash -c ". \"$LIB\"; _cd_repo_root; echo \"rc=\$?\"; pwd -P" 2>&1)
rm -rf "$_t"
if printf '%s' "$_out" | grep -q "rc=0" \
   && printf '%s' "$_out" | grep -qF "$_tp" \
   && ! printf '%s' "$_out" | grep -q '\[init\]'; then
  ok "T28.c 비-git → cd 미실행·rc=0·무출력"
else
  nope "T28.c" "out=$_out"
fi

# T28.g skipped() 가 사유 없는 skip 을 통과로 위장하지 않는다 (AC-5)
#   서브셸이라 PASS/FAIL 카운터가 바깥으로 새지 않는다.
_p1=$(PASS=0; FAIL=0; skipped "probe" >/dev/null 2>&1; echo "FAIL=$FAIL")
_p2=$(PASS=0; FAIL=0; skipped "probe" "사유있음" >/dev/null 2>&1; echo "FAIL=$FAIL")
if [ "$_p1" = "FAIL=1" ] && [ "$_p2" = "FAIL=0" ]; then
  ok "T28.g skip 사유 누락 → FAIL · 사유 있으면 무증가"
else
  nope "T28.g" "무사유=$_p1 유사유=$_p2"
fi

# T28.d git worktree 루트 → _check_git 통과 + stderr 무출력 (AC-1)
setup_fixture
git commit -q --allow-empty -m init
# worktree 는 TMPDIR **내부**에 만든다 — 형제 경로(../)는 teardown 의 rm -rf 가 회수하지 못한다
_wt="$TMPDIR/wt-t28"
if git worktree add -q "$_wt" -b t28branch 2>/dev/null; then
  _err_f=$(mktemp)
  _out=$(cd "$_wt" && bash -c ". \"$LIB\"; _check_git; echo \"rc=\$?\"" 2>"$_err_f")
  _err=$(cat "$_err_f"); rm -f "$_err_f"
  if printf '%s' "$_out" | grep -q "rc=0" && [ -z "$_err" ]; then
    ok "T28.d worktree 루트 → _check_git 통과·무출력"
  else
    nope "T28.d" "out=$_out err=[$_err]"
  fi
  git worktree remove --force "$_wt" 2>/dev/null
else
  skipped "T28.d worktree" "git worktree 미지원 환경 (git $(git --version | awk '{print $3}')) — AC-1 미검증"
fi
teardown_fixture

# T28.e 비-git → exit 1 + 원문 메시지 (AC-R-1 승계 · T6.a 와 동일 계약)
_t=$(mktemp -d)
_out=$(cd "$_t" && bash -c ". \"$LIB\"; _check_git" 2>&1); _ec=$?
rm -rf "$_t"
if [ "$_ec" = "1" ] && printf '%s' "$_out" | grep -q "git 저장소가 아닙니다"; then
  ok "T28.e 비-git → exit 1 + 원문 메시지 보존"
else
  nope "T28.e" "ec=$_ec out=$_out"
fi

# T28.f source 시 호출자 cwd 무변경 (AC-3 — 회귀 방어)
#   ★ 양성 단언이다 — `!= 루트` 부정형으로 쓰면 source 자체가 사망해 _out 이 빈값일 때도
#     "루트가 아니다" 가 성립해 오탐 PASS 한다. sub 물리경로와 **일치**를 요구한다.
setup_fixture
mkdir -p sub
_sub=$(cd sub && pwd -P)
_out=$(cd sub && bash -c ". \"$SCRIPT\" >/dev/null 2>&1; pwd -P")
if [ "$_out" = "$_sub" ]; then
  ok "T28.f source → 호출자 cwd 무변경"
else
  nope "T28.f" "cwd=$_out 기대=$_sub (source 가 cwd 를 옮겼거나 스크립트 사망)"
fi
teardown_fixture

# T28.h 작업트리 밖(`.git` 내부 · bare repo) → exit 1 + 원문 메시지 (AC-R-1 회귀 방어)
#   ★ rc 만 보는 판정(`git rev-parse --git-dir`)은 이 두 위치에서 **rc=0** 이라 통과한다 —
#     구 `[ -d .git ]` 이 차단하던 곳이 뚫린다. `--is-inside-work-tree` 의 **출력**(`false`)
#     비교만이 격추한다(실측: 두 위치 모두 out=false, rc=0).
#   두 입력 클래스를 한 케이스로 묶는다 — 같은 계약(작업트리 밖 차단)의 두 표본이다.
_t=$(mktemp -d)
git -C "$_t" init -q r 2>/dev/null
git init -q --bare "$_t/b.git" 2>/dev/null
_out1=$(cd "$_t/r/.git" && bash -c ". \"$LIB\"; _check_git" 2>&1); _ec1=$?
_out2=$(cd "$_t/b.git" && bash -c ". \"$LIB\"; _check_git" 2>&1); _ec2=$?
rm -rf "$_t"
if [ "$_ec1" = "1" ] && printf '%s' "$_out1" | grep -q "git 저장소가 아닙니다" \
   && [ "$_ec2" = "1" ] && printf '%s' "$_out2" | grep -q "git 저장소가 아닙니다"; then
  ok "T28.h .git 내부·bare repo → exit 1 + 원문 메시지"
else
  nope "T28.h" ".git내부: ec=$_ec1 out=[$_out1] / bare: ec=$_ec2 out=[$_out2]"
fi

# T28.i cd 실패 분기 → rc≠0 + 사유 stderr (AC-4 ② — 유일하게 자동화 안 되던 분기)
#   기법: fake `git` 을 PATH 앞에 주입해 `--show-toplevel` 이 **존재하지 않는 경로**를 뱉게 한다.
#   PATH 오염은 아래 한 줄의 명령 앞 할당으로 한정된다(다른 케이스 무영향).
#   ★ 사유 문자열 단언이 핵심이다 — `cd` 는 `|| { …; return 1; }` 없이도 실패 시 rc=1 이라
#     rc 만 보면 에러 처리 블록 삭제 변이가 생존한다(실측). 경로 문자열 단언은 fake 가 실제로
#     발화했음을 보증한다(heredoc 오확장으로 빈값이면 `-n` 가드에 걸려 오탐 PASS 하므로).
_t=$(mktemp -d); _fake=$(mktemp -d)
cat > "$_fake/git" <<'FAKEGIT'
#!/usr/bin/env bash
# _cd_repo_root 가 부르는 서브커맨드만 가로챈다
case "$*" in
  "rev-parse --show-toplevel") echo "/nonexistent-t28-probe" ;;
  *) exit 1 ;;
esac
FAKEGIT
chmod +x "$_fake/git"
_out=$(cd "$_t" && PATH="$_fake:$PATH" bash -c ". \"$LIB\"; _cd_repo_root; echo \"rc=\$?\"" 2>&1)
rm -rf "$_t" "$_fake"
_rc=$(printf '%s\n' "$_out" | grep -o 'rc=[0-9]*' | tail -1)
if [ -n "$_rc" ] && [ "$_rc" != "rc=0" ] \
   && printf '%s' "$_out" | grep -qF '[init] repo 루트 이동 실패' \
   && printf '%s' "$_out" | grep -qF '/nonexistent-t28-probe'; then
  ok "T28.i cd 실패 → rc≠0 + 사유 stderr"
else
  nope "T28.i" "rc=[$_rc] out=[$_out]"
fi

# ── T29: `.specops/.gitignore` — FID 의 intent.md 만 추적, 그 밖의 FID 산출물은 무시 (20261008) ──
# 왜: 종전 규칙(`…-*/`)은 FID 디렉토리를 통째로 무시해 intent.md 가 저장소에 올라가지 않았다 — PR 리뷰어가
#   의도 문서를 볼 수 없고 git 이력도 남지 않는다. git 은 무시된 디렉토리 안의 파일을 `!` 로 되살릴 수 없으므로
#   규칙은 디렉토리가 아니라 **내용**(`…-*/*`)을 무시해야 한다 — 이 잠금은 생성기의 규칙을 실제 git 으로 판정한다.
# 규칙 본문은 생성기 함수에서 직접 받는다(종전엔 heredoc 을 awk 로 긁었다 — 병합 방식으로 바뀌며 함수가 됐다).
_gi=$(bash -c 'source "$1" && _specops_gitignore_template' _ "$SCRIPT" 2>/dev/null)
[ -n "$_gi" ] && ok "T29.0 생성기가 규칙 본문을 낸다" || nope "T29.0" "_specops_gitignore_template 출력 없음"
_t29=$(mktemp -d)
( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  cd "$_t29" && git init -q && mkdir -p .specops/20261008-x/reviews .specops/memory \
  && printf '%s\n' "$_gi" > .specops/.gitignore \
  && : > .specops/20261008-x/intent.md && : > .specops/20261008-x/plan.md && : > .specops/20261008-x/evidence.md \
  && : > .specops/20261008-x/reviews/T1-B-report.md && : > .specops/memory/requirements.md && : > .specops/session-progress.md ) >/dev/null 2>&1
_st=$(cd "$_t29" && git status --porcelain -uall 2>/dev/null)
if printf '%s\n' "$_st" | grep -q '20261008-x/intent.md'; then ok "T29.a intent.md 는 추적 대상(무시되지 않음)"; else nope "T29.a" "status=[$_st]"; fi
if ! printf '%s\n' "$_st" | grep -qE '20261008-x/(plan|evidence)\.md|reviews/'; then ok "T29.b plan·evidence·reviews 는 계속 무시"; else nope "T29.b" "status=[$_st]"; fi
if printf '%s\n' "$_st" | grep -q 'memory/requirements.md' && printf '%s\n' "$_st" | grep -q 'session-progress.md'; then ok "T29.c memory/·session-progress 는 추적 유지"; else nope "T29.c" "status=[$_st]"; fi
rm -rf "$_t29"

# ── T30: 재실행·기존 프로젝트에서 사용자 내용을 지우지 않는다 (20261009 init 점검) ──
# 왜: `--resume`·재실행이 화면 목록 표와 `.specops/.gitignore` 를 통째로 다시 썼다(설치본 재현) —
#   보강 표기·손으로 쓴 줄·하류가 직접 넣은 무시 규칙이 사라지고, 그 상태가 그대로 stage 됐다.

# T30.a 화면 목록: 기존 행·표 밖 내용 보존, 새 이름만 추가
setup_fixture
fullstack_stdin | bash "$SCRIPT" demo >/dev/null 2>&1
_ov=.specops/memory/screens-overview.md
sed -i.bak 's#^| home | home | 예정 — /start-all Phase 2.5 |#| home | 홈 대시보드 | init 보강 (미확정 3) |#' "$_ov"; rm -f "$_ov.bak"
printf '\n손으로 쓴 메모 줄\n' >> "$_ov"
printf '4\nhome, billing\n' | bash "$SCRIPT" --resume demo >/dev/null 2>&1
if grep -qF '| home | 홈 대시보드 | init 보강 (미확정 3) |' "$_ov" && grep -qx '손으로 쓴 메모 줄' "$_ov" \
   && grep -qE '^\| login \|' "$_ov" && [ "$(grep -cE '^\| billing \|' "$_ov")" = "1" ] \
   && [ "$(grep -cE '^\| home \|' "$_ov")" = "1" ]; then
  ok "T30.a 재실행 → 화면 목록의 기존 행·손으로 쓴 줄 보존 · 새 화면 1행만 추가"
else
  nope "T30.a" "home=[$(grep -E '^\| home \|' "$_ov" | head -2 | tr '\n' ' ')] billing=$(grep -cE '^\| billing \|' "$_ov") 메모=$(grep -cx '손으로 쓴 메모 줄' "$_ov")"
fi
# T30.b 화면 이름을 비워 재실행해도 표는 그대로다
_before=$(cat "$_ov")
printf '4\n\n' | bash "$SCRIPT" --resume demo >/dev/null 2>&1
[ "$_before" = "$(cat "$_ov")" ] && ok "T30.b 화면 이름 없이 재실행 → 화면 목록 무변경" || nope "T30.b" "화면 목록이 바뀜"

# T30.c .gitignore: 사용자 줄 보존 · 중복 없음 · 두 번째 실행은 무변경
printf '# 팀 규칙\nmy-local-notes/\n' >> .specops/.gitignore
printf '4\n\n' | bash "$SCRIPT" --resume demo >/dev/null 2>&1
_g1=$(cat .specops/.gitignore)
printf '4\n\n' | bash "$SCRIPT" --resume demo >/dev/null 2>&1
_dup=$(grep -vE '^(#|$)' .specops/.gitignore | sort | uniq -d | tr '\n' ' ')
if grep -qx 'my-local-notes/' .specops/.gitignore && grep -qx '# 팀 규칙' .specops/.gitignore \
   && [ -z "$_dup" ] && [ "$_g1" = "$(cat .specops/.gitignore)" ]; then
  ok "T30.c 재실행 → .gitignore 의 사용자 줄 보존 · 중복 0 · 재실행 멱등"
else
  nope "T30.c" "user=$(grep -cx 'my-local-notes/' .specops/.gitignore) dup=[$_dup] idem=$([ "$_g1" = "$(cat .specops/.gitignore)" ] && echo y || echo n)"
fi

# T30.d 새 프로젝트: 훅·스크립트가 쓰는 로컬 파일은 무시되고, 기록물은 추적 대상으로 남는다
_ign=""; for f in pending-capture.jsonl redact-failures.log friction-log.jsonl session-progress.md.bak .init-prd-fields .init-hold; do
  git check-ignore -q ".specops/$f" || _ign="$_ign $f"
done
_trk=""; for f in freelog.md session-progress.md memory/requirements.md 20261009-x/intent.md; do
  git check-ignore -q ".specops/$f" && _trk="$_trk $f"
done
git check-ignore -q .specops/20261009-x/plan.md || _ign="$_ign 20261009-x/plan.md"
[ -z "$_ign" ] && [ -z "$_trk" ] \
  && ok "T30.d 로컬 상태 파일 6종·FID 산출물 무시 · freelog·session-progress·memory·intent 는 추적 대상" \
  || nope "T30.d" "무시 안 됨:[$_ign] 잘못 무시됨:[$_trk]"
teardown_fixture

# T30.e 구판 .gitignore(하류 실물 형태) 이관: FID 디렉토리 통째 무시 → 내용 무시 + intent.md 예외
setup_fixture
mkdir -p .specops
cat > .specops/.gitignore <<'LEGACY'
# specops-ko 정책: memory/ 와 session-progress.md 는 commit, FID 디렉토리는 ignore
# FID 컨벤션: YYYYMMDD-slug (8자리 날짜 + dash). 일반 디렉토리 false positive 차단.
[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*/

# batch 디렉토리 (queue.md·plan-review.md·ACTIVE) — FID 컨벤션에 안 걸린다.
batch-*/

# 세션 훅 산출물 — 커밋 대상 아님
friction-log.jsonl

# 스크립트 백업 산출물
*.bak
LEGACY
{
  printf "3\nskip\n"
  printf "1. cli\n2. dev\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "n\n"
} | bash "$SCRIPT" --resume legacy >/dev/null 2>&1
mkdir -p .specops/20261008-x .specops/batch-20261008-1200
: > .specops/20261008-x/intent.md; : > .specops/20261008-x/plan.md; : > .specops/batch-20261008-1200/queue.md
_miss=""
git check-ignore -q .specops/20261008-x/intent.md && _miss="$_miss intent무시됨"
git check-ignore -q .specops/20261008-x/plan.md   || _miss="$_miss plan추적됨"
git check-ignore -q .specops/batch-20261008-1200/queue.md || _miss="$_miss 사용자규칙(batch)소실"
for l in 'batch-*/' 'friction-log.jsonl' '*.bak' '# 세션 훅 산출물 — 커밋 대상 아님'; do
  grep -qxF -- "$l" .specops/.gitignore || _miss="$_miss 줄소실($l)"
done
grep -qxF '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*/' .specops/.gitignore && _miss="$_miss 구규칙잔존"
[ "$(grep -cxF 'friction-log.jsonl' .specops/.gitignore)" = "1" ] || _miss="$_miss 중복(friction-log)"
[ -z "$_miss" ] && ok "T30.e 구판 .gitignore 이관 → intent.md 추적 · 나머지 FID 산출물 무시 · 사용자 줄 보존 · 중복 0" \
  || nope "T30.e" "$_miss"
teardown_fixture

# ── T31: bash 단계가 stage 하는 범위 (20261009 init 점검) ──
# T31.a 기존 앱의 screens/ 폴더는 stage 하지 않는다 — init 시점엔 specops 화면 파일이 아직 없다
setup_fixture
mkdir -p screens; printf 'export default function Draft() {}\n' > screens/Draft.tsx
fullstack_stdin | bash "$SCRIPT" demo >/dev/null 2>&1
if ! git diff --cached --name-only | grep -q 'Draft\.tsx' && git diff --cached --name-only | grep -qx 'PRD.md'; then
  ok "T31.a 기존 앱의 screens/ 파일은 stage 하지 않음 (산출물은 stage)"
else
  nope "T31.a" "staged=$(git diff --cached --name-only | tr '\n' ' ')"
fi
teardown_fixture

# T31.b 보존한 파일에 미커밋 수정분이 있으면 stage 하지 않고 기록한다(.init-hold) — 종결 커밋이 건너뛴다
setup_fixture
printf '# 팀 README\n' > README.md; printf '# 팀 가이드\n' > CLAUDE.md
git add README.md CLAUDE.md; git commit -q -m base
printf '# 팀 README\n\n작성 중인 문단\n' > README.md        # 미커밋 수정 (CLAUDE.md 는 깨끗)
{ printf "skip\n"; fullstack_stdin; } | bash "$SCRIPT" demo >/dev/null 2>&1
_hold=$(cat .specops/.init-hold 2>/dev/null | tr '\n' ' ')
if [ "$_hold" = "README.md " ] && ! git diff --cached --name-only | grep -qx 'README.md' \
   && grep -q '작성 중인 문단' README.md && git diff --cached --name-only | grep -qx 'PRD.md' \
   && git diff --cached --name-only | grep -qx '.specops/memory/requirements.md'; then
  ok "T31.b 보존 파일의 미커밋 수정분 → stage 안 함 · .init-hold 기록(깨끗한 보존 파일은 제외)"
else
  nope "T31.b" "hold=[$_hold] staged=$(git diff --cached --name-only | tr '\n' ' ')"
fi
teardown_fixture

# T31.c overwrite 를 고르면 기록하지 않는다 — 덮어쓴 파일은 init 의 산출물이다
setup_fixture
printf '# 팀 README\n' > README.md; git add README.md; git commit -q -m base
printf '# 팀 README\n\n작성 중\n' > README.md
{ printf "overwrite\n"; fullstack_stdin; } | bash "$SCRIPT" demo >/dev/null 2>&1
if [ ! -e .specops/.init-hold ] && git diff --cached --name-only | grep -qx 'README.md'; then
  ok "T31.c overwrite → 기록 없음 · 덮어쓴 README 는 stage"
else
  nope "T31.c" "hold=$([ -e .specops/.init-hold ] && cat .specops/.init-hold | tr '\n' ' ' || echo 없음) staged=$(git diff --cached --name-only | tr '\n' ' ')"
fi
teardown_fixture

# T31.d 즉시 커밋 경로도 init 의 파일만 담는다
setup_fixture
printf 'API_KEY=sk-test-000\n' > notes.env; git add notes.env
fullstack_stdin | SPECOPS_INIT_COMMIT_NOW=1 bash "$SCRIPT" demo >/dev/null 2>&1
if [ "$(git rev-list --count HEAD 2>/dev/null)" = "1" ] \
   && ! git show --name-only --format= HEAD | grep -q 'notes\.env' \
   && git diff --cached --name-only | grep -qx 'notes.env'; then
  ok "T31.d SPECOPS_INIT_COMMIT_NOW=1 → 무관 staged 파일은 커밋 제외 · staged 유지"
else
  nope "T31.d" "commits=$(git rev-list --count HEAD 2>/dev/null) files=$(git show --name-only --format= HEAD 2>/dev/null | tr '\n' ' ')"
fi
teardown_fixture

# T31.e 사용자가 만든 미커밋 파일(미추적 · 직접 stage 한 새 파일)도 보존하면 커밋에 넣지 않는다
#   독립 리뷰 재현: HEAD 대비 수정분만 보류하던 초판은 이 둘을 `chore(init)` 커밋에 쓸어 담았다 —
#   "README.md 보존" 이라고 출력해 놓고서다. git 상태만으로는 init 의 골격과 구분되지 않아, init 이 쓴 파일을
#   따로 기록한다(.init-written).
setup_fixture
printf 'x\n' > seed.txt; git add seed.txt; git commit -q -m base
printf '# 내 README (커밋 전)\n' > README.md                       # 미추적
printf '# 내 가이드\n' > CLAUDE.md; git add CLAUDE.md               # 사용자가 stage 한 새 파일
{ printf "skip\n"; fullstack_stdin; } | bash "$SCRIPT" demo >/dev/null 2>&1
_hold=$(sort .specops/.init-hold 2>/dev/null | tr '\n' ' ')
bash "$PLUGIN/scripts/_internal/init-finalize.sh" >/dev/null 2>&1
_cf=$(git show --name-only --format= HEAD 2>/dev/null)
if [ "$_hold" = "CLAUDE.md README.md " ] && ! printf '%s\n' "$_cf" | grep -qxE 'README\.md|CLAUDE\.md' \
   && printf '%s\n' "$_cf" | grep -qx 'PRD.md' \
   && git status --porcelain | grep -q '^?? README.md' && git status --porcelain | grep -q '^A  CLAUDE.md' \
   && grep -q '내 README' README.md; then
  ok "T31.e 사용자의 미추적·staged 새 파일 → 보류 · 커밋 제외 · 상태 그대로"
else
  nope "T31.e" "hold=[$_hold] commit=[$(printf '%s' "$_cf" | tr '\n' ' ' | cut -c1-120)] st=[$(git status --porcelain | tr '\n' '|')]"
fi
teardown_fixture

# T31.f 종결 전 재실행(재개든 아니든)은 이전 실행의 골격을 보류하지 않는다 — 종결 커밋이 전부 담는다
for _mode in rerun resume; do
  setup_fixture
  fullstack_stdin | bash "$SCRIPT" demo >/dev/null 2>&1                 # 1차: stage 만, 종결 안 함
  if [ "$_mode" = "rerun" ]; then
    printf 'y\nskip\n4\nhome, login\n' | bash "$SCRIPT" demo >/dev/null 2>&1
  else
    printf '4\nhome, login\n' | bash "$SCRIPT" --resume demo >/dev/null 2>&1
  fi
  _h=$([ -e .specops/.init-hold ] && tr '\n' ' ' < .specops/.init-hold || echo "")
  bash "$PLUGIN/scripts/_internal/init-finalize.sh" >/dev/null 2>&1
  _n=$(git show --name-only --format= HEAD 2>/dev/null | grep -c . || true)
  if [ -z "$_h" ] && [ "${_n:-0}" -ge 15 ] && [ -z "$(git status --porcelain)" ] \
     && [ ! -e .specops/.init-written ]; then
    ok "T31.f($_mode) 종결 전 재실행 → 이전 골격 보류 0 · 종결 커밋 ${_n}파일 · clean · 기록 파일 회수"
  else
    nope "T31.f($_mode)" "hold=[$_h] files=$_n st=[$(git status --porcelain | tr '\n' '|' | cut -c1-160)]"
  fi
  teardown_fixture
done

# T31.g 손으로 커밋한 뒤에는 쓴 파일 기록을 믿지 않는다 — 그 뒤의 수정분은 사용자의 것이다
#   종결 스크립트 대신 `git add -A && git commit` 으로 닫으면 .init-written 이 남는다. 그 상태에서 README 를
#   고치고 `--resume`(예: .gitignore 이관)하면, 기록만 믿는 판정은 README 를 init 의 파일로 보고 쓸어 담는다.
setup_fixture
fullstack_stdin | bash "$SCRIPT" demo >/dev/null 2>&1
git add -A; git commit -q -m "수동 커밋"
printf '\n작성 중인 문단\n' >> README.md
_o=$(printf '4\n\n' | bash "$SCRIPT" --resume demo 2>&1)
printf '\n- 보강 흉내\n' >> .specops/memory/requirements.md
bash "$PLUGIN/scripts/_internal/init-finalize.sh" >/dev/null 2>&1
_cf=$(git show --name-only --format= HEAD 2>/dev/null)
if printf '%s' "$_o" | grep -q 'init 커밋에 넣지 않습니다.*README\.md' \
   && printf '%s\n' "$_cf" | grep -qx '.specops/memory/requirements.md' \
   && ! printf '%s\n' "$_cf" | grep -qx 'README.md' \
   && [ "$(git status --short README.md | cut -c1-2)" = " M" ]; then
  ok "T31.g 수동 커밋 뒤의 README 수정분 → 보류(고지) · 종결 커밋 제외 · 보강분은 커밋"
else
  nope "T31.g" "commit=[$(printf '%s' "$_cf" | tr '\n' ' ')] st=[$(git status --short | tr '\n' '|')] out=$(printf '%s' "$_o" | grep '넣지' | cut -c1-80)"
fi
# T31.h 커밋할 것이 없는 종결 호출은 쓴 파일 기록을 닫는다 (수동 커밋 뒤 doctor 안내대로 종결을 부른 경우)
git checkout -q -- README.md; git add -A; git commit -q -m "보강분 수동 커밋" 2>/dev/null
printf 'README.md\n' > .specops/.init-written
bash "$PLUGIN/scripts/_internal/init-finalize.sh" >/dev/null 2>&1
[ ! -e .specops/.init-written ] && ok "T31.h 커밋 대상 없는 종결 → 쓴 파일 기록 회수" || nope "T31.h" ".init-written 잔존"
teardown_fixture

# T30.f .gitignore 보충은 사용자 규칙을 뒤집지 않는다 — 보충 규칙은 위에, 사용자 규칙은 아래(뒤가 이긴다)
setup_fixture
mkdir -p .specops
printf '# 팀 규칙\n!keep.bak\n' > .specops/.gitignore
{ printf "3\nskip\n"; printf "1. cli\n2. dev\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"; printf "n\n"; } \
  | bash "$SCRIPT" --resume neg >/dev/null 2>&1
: > .specops/keep.bak; : > .specops/other.bak
mkdir -p .specops/20261009-x; : > .specops/20261009-x/intent.md; : > .specops/20261009-x/plan.md
_m=""
git check-ignore -q .specops/keep.bak && _m="$_m keep.bak무시됨"
git check-ignore -q .specops/other.bak || _m="$_m other.bak추적됨"
git check-ignore -q .specops/20261009-x/intent.md && _m="$_m intent무시됨"
git check-ignore -q .specops/20261009-x/plan.md || _m="$_m plan추적됨"
[ -z "$_m" ] && ok "T30.f 사용자의 부정 규칙(!keep.bak)이 보충 뒤에도 듣는다 · 보충 규칙도 동작" || nope "T30.f" "$_m"
# T30.g 내용 무시 규칙만 있고 intent 예외가 없는 파일 → 예외를 그 규칙 바로 뒤에 끼운다
printf '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*/*\nmy-rule/\n' > .specops/.gitignore
printf '3\nn\n' | bash "$SCRIPT" --resume neg >/dev/null 2>&1
_m=""
git check-ignore -q .specops/20261009-x/intent.md && _m="$_m intent무시됨"
git check-ignore -q .specops/20261009-x/plan.md || _m="$_m plan추적됨"
grep -qx 'my-rule/' .specops/.gitignore || _m="$_m 사용자줄소실"
[ -z "$_m" ] && ok "T30.g intent 예외 누락 파일 → 내용 무시 규칙 뒤에 끼움 (예외가 실제로 듣는다)" || nope "T30.g" "$_m"
teardown_fixture

# ── T32: 답이 빠지거나 밀리면 기본값으로 덮지 않고 멈춘다 (20261009 init 점검 — 입력 계약) ──
# 왜: 이 스크립트는 질문을 stdin 에서 **순서대로** 읽는데 실제 호출자(Claude Code 의 Bash 도구)는 터미널이
#   아니다. 답이 모자라거나 한 줄 밀려도 전부 기본값으로 흡수하고 rc=0 으로 끝났다(설치본 재현 — 헌법 원칙
#   자리에 PRD 문구 · `<TODO>` 8건짜리 PRD · CLI 저장소에 풀스택 파일).
cli_stdin() {
  printf "3\nskip\n"
  printf "1. 한 줄: CLI 데모\n2. 페르소나: dev\n3. 가치: a, b, c\n4. M1: m1\n5. M2: m2\n6. M3: m3\n\n"
  printf "n\n"
}
_no_artifacts() { [ ! -e PRD.md ] && [ ! -e CLAUDE.md ] && [ ! -d .specops/memory ]; }

# T32.a 모르는 옵션은 프로젝트 이름으로 삼지 않는다 (`--enrich` 를 bash 에 넘기면 README 제목이 `# --enrich` 였다)
setup_fixture
out=$(cli_stdin | bash "$SCRIPT" --enrich 2>&1); rc=$?
if [ "$rc" -eq 2 ] && _no_artifacts && printf '%s' "$out" | grep -q -- '--enrich 는 이 스크립트의 옵션이 아닙니다'; then
  ok "T32.a --enrich 를 bash 에 넘김 → rc=2 · 산출물 0 · 사유 출력"
else
  nope "T32.a" "rc=$rc PRD=$([ -e PRD.md ] && echo 있음 || echo 없음) out=$(printf '%s' "$out" | head -2 | tr '\n' ' ')"
fi
out=$(cli_stdin | bash "$SCRIPT" --nonsense 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && _no_artifacts && printf '%s' "$out" | grep -q '모르는 옵션'; } \
  && ok "T32.b 모르는 옵션 → rc=2 · 산출물 0 (프로젝트 이름으로 삼지 않음)" || nope "T32.b" "rc=$rc"
out=$(cli_stdin | bash "$SCRIPT" one two 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && _no_artifacts; } && ok "T32.b2 이름 인자 2개 → rc=2 · 산출물 0" || nope "T32.b2" "rc=$rc"
teardown_fixture

# T32.c 종류 질문에 선택지가 아닌 값(답이 밀렸다는 가장 이른 신호) → 멈춘다
setup_fixture
out=$({ printf "Y\n"; cli_stdin; } | bash "$SCRIPT" demo 2>&1); rc=$?
if [ "$rc" -eq 2 ] && _no_artifacts && printf '%s' "$out" | grep -q '종류'; then
  ok "T32.c 종류에 'Y' → rc=2 · 산출물 0 (풀스택으로 넘어가지 않음)"
else
  nope "T32.c" "rc=$rc out=$(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi
teardown_fixture

# T32.d 답이 중간에 끊기면(입력 소진) 기본값으로 이어 가지 않는다
setup_fixture
out=$(printf '4\nskip\n1. 한 줄: x\n2. 페르소나: y\n3. 가치: a, b, c\n4. M1: m1\n5. M2: m2\n6. M3: m3\n\n' | bash "$SCRIPT" demo 2>&1); rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '입력이' && [ -z "$(git diff --cached --name-only)" ]; then
  ok "T32.d 디자인 방향 질문에서 입력 소진 → rc=2 · 멈춘 질문을 알림 · stage 없음"
else
  nope "T32.d" "rc=$rc staged=$(git diff --cached --name-only | grep -c .) out=$(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi
teardown_fixture

# T32.e PRD 필드가 모자라고 터미널도 없으면 `<TODO>` PRD 를 만들지 않는다
#   종전 가드는 `/dev/tty` 의 **존재**만 봤다 — 존재하지만 열 수 없는 환경(Claude Code 의 Bash 도구)에서 듣지 않았다.
#   SPECOPS_INIT_NO_TTY=1 은 "터미널 없음"을 고정하는 스위치다 — 개발자 터미널에서 돌려도 결과가 같게 한다.
setup_fixture
out=$(printf '4\nskip\n1. 한 줄: x\n\n1\nhome\nn\n1\n' | SPECOPS_INIT_NO_TTY=1 bash "$SCRIPT" demo 2>&1); rc=$?
if [ "$rc" -eq 2 ] && [ ! -e PRD.md ]; then
  ok "T32.e PRD 1/6 + 터미널 없음 → rc=2 · PRD.md 미생성"
else
  nope "T32.e" "rc=$rc PRD=$([ -e PRD.md ] && grep -c TODO PRD.md || echo 없음)"
fi
teardown_fixture

# T32.f 답이 한 줄 밀려 DB 질문에 문장이 들어오면 멈춘다 (문서가 허용하던 "필드 파일 + stdin 둘 다" 재현)
setup_fixture
mkdir -p .specops
printf '주문 관리\n영업\n가, 나, 다\n등록\n승인\n통계\n' > .specops/.init-prd-fields
out=$(printf '4\nskip\n1. 한 줄: 주문 관리\n2. 페르소나: 영업\n3. 가치: 가, 나, 다\n4. M1: 등록\n5. M2: 승인\n6. M3: 통계\n\n1\nhome\ny\n1\n' | bash "$SCRIPT" demo 2>&1); rc=$?
if [ "$rc" -eq 2 ] && [ ! -e .specops/memory/data-model.md ] && [ -z "$(git diff --cached --name-only)" ]; then
  ok "T32.f 밀린 답(DB 질문에 문장) → rc=2 · stage 없음"
else
  nope "T32.f" "rc=$rc out=$(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi
teardown_fixture

# T32.g 브레인스토밍 메모만 있는 저장소는 "이미 부트스트랩됨" 이 아니다 (/brainstorming → /init-project 권장 흐름)
#   종전엔 메모가 .specops/memory/ 를 만들어 재부트스트랩 질문이 떴고, 첫 답이 거기 소비돼 "취소됨" rc=0 · 산출물 0.
setup_fixture
mkdir -p .specops/memory
printf '# 브레인스토밍 메모\n## 문제\n사용자 인사 자동화\n' > .specops/memory/brainstorming-20261009-greet.md
out=$(cli_stdin | bash "$SCRIPT" demo 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -f PRD.md ] && grep -q '## 브레인스토밍 컨텍스트' PRD.md \
   && ! printf '%s' "$out" | grep -q '재부트스트랩' && [ -f .specops/memory/requirements.md ]; then
  ok "T32.g 메모만 있는 저장소 → 재부트스트랩 질문 없이 진행 · PRD 에 메모 참조"
else
  nope "T32.g" "rc=$rc PRD=$([ -f PRD.md ] && echo 있음 || echo 없음) out=$(printf '%s' "$out" | head -3 | tr '\n' ' ')"
fi
teardown_fixture

# ── T34: 프로젝트 종류를 기록하고 다시 쓴다 ──
# 왜: 종류를 어디에도 적지 않아 뒤 단계가 파일 존재와 자유 서술로 추정했다. CLI 로 init 한 직후
#   foundation 필수 판정이 FAIL 이었고(/start-all 진입 막힘), 답 없이 `--resume` 하면 풀스택으로 잡혀
#   CLI 저장소에 풀스택 파일 6개가 생겼다(설치본 재현).
setup_fixture
cli_stdin | bash "$SCRIPT" demo >/dev/null 2>&1
_k=$(sed -n 's/^<!-- specops:project-kind: \([1-6]\).*/\1/p' .specops/memory/project-context.md 2>/dev/null | head -1)
[ "$_k" = "3" ] && ok "T34.a 종류를 project-context.md 에 기록 (kind=3)" || nope "T34.a" "기록=[$_k]"
out=$(bash "$PLUGIN/scripts/_internal/check-foundation-present.sh" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'FAIL'; } \
  && ok "T34.b CLI 로 init 한 직후 foundation 필수 판정에 걸리지 않는다" || nope "T34.b" "rc=$rc out=$(printf '%s' "$out" | head -1)"
git add -A; git commit -q -m base
# 빈 답으로 재개 → 기록된 종류(3)를 쓴다 · 질문 수는 그대로(종류 → DB)
out=$(printf '\nn\n' | bash "$SCRIPT" --resume demo 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'PROJECT_KIND=3' \
   && [ ! -e DESIGN.md ] && [ ! -e .specops/memory/frontend-architecture.md ] && [ -z "$(git status --porcelain)" ]; then
  ok "T34.c 빈 답으로 --resume → 기록된 종류 사용 · 풀스택 파일 미생성 · 무변경"
else
  nope "T34.c" "rc=$rc kind=$(printf '%s' "$out" | grep -o 'PROJECT_KIND=.' | head -1) st=[$(git status --porcelain | tr '\n' '|' | cut -c1-120)]"
fi
# 답이 아예 없으면(입력 소진) 멈춘다 — 풀스택으로 넘어가지 않는다
out=$(bash "$SCRIPT" --resume demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 2 ] && [ ! -e DESIGN.md ] && [ -z "$(git status --porcelain)" ]; } \
  && ok "T34.d 답 없이 --resume → rc=2 · 무변경" || nope "T34.d" "rc=$rc st=[$(git status --porcelain | tr '\n' '|' | cut -c1-120)]"
teardown_fixture

# ── T33: 답변 파일 모드 (`--answers <파일>`) — 순서가 아니라 이름으로 답한다 ──
# 답변 파일의 키를 채우는 도우미: 빠졌다고 알려 준 키에 유효한 값을 넣는다.
_fill_key() {
  case "$1" in
    rebootstrap) echo "rebootstrap=y" ;; conflict) echo "conflict=skip" ;;
    principles) echo "principles=skip" ;;
    prd.oneline) echo "prd.oneline=주문 관리 | 영업 & 승인 = 한 화면" ;;
    prd.persona) echo "prd.persona=영업 담당" ;; prd.values) echo "prd.values=가, 나, 다" ;;
    prd.m1) echo "prd.m1=등록" ;; prd.m2) echo "prd.m2=승인" ;; prd.m3) echo "prd.m3=통계" ;;
    design) echo "design=1" ;; screens) echo "screens=home, orders" ;;
    db) echo "db=n" ;; api) echo "api=1" ;; api.consumer) echo "api.consumer=n" ;;
    *) echo "$1=?" ;;
  esac
}

# T33.a 종류별 자기 정합: `kind` 만 주면 빠진 키를 **전부** 알려 주고 아무것도 쓰지 않는다 →
#   알려 준 키만 채우면 완주한다. (사전 점검이 실제 질문과 어긋나면 여기서 드러난다)
for _kind in 1 2 3 4 5 6; do
  setup_fixture
  printf 'kind=%s\n' "$_kind" > ans.txt
  out=$(bash "$SCRIPT" --answers ans.txt demo 2>&1 </dev/null); rc1=$?
  _clean=0; _no_artifacts && [ -z "$(git status --porcelain | grep -v 'ans.txt')" ] && _clean=1
  _missing=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*- 빠짐: \([a-z0-9.]*\).*/\1/p')
  for _key in $_missing; do _fill_key "$_key" >> ans.txt; done
  out2=$(bash "$SCRIPT" --answers ans.txt demo 2>&1 </dev/null); rc2=$?
  if [ "$rc1" -eq 2 ] && [ "$_clean" = "1" ] && [ -n "$_missing" ] && [ "$rc2" -eq 0 ] \
     && [ -f PRD.md ] && grep -qF '**한 줄 설명**: 주문 관리 | 영업 & 승인 = 한 화면' PRD.md \
     && grep -qF -- '- **M3**: 통계' PRD.md && [ -n "$(git diff --cached --name-only)" ]; then
    ok "T33.a(kind=$_kind) 빠진 키 $(printf '%s\n' "$_missing" | grep -c .)개 고지·무기록 → 채우면 완주"
  else
    nope "T33.a(kind=$_kind)" "rc1=$rc1 clean=$_clean missing=[$(printf '%s' "$_missing" | tr '\n' ' ')] rc2=$rc2 out2=$(printf '%s' "$out2" | tail -2 | tr '\n' ' ' | cut -c1-160)"
  fi
  teardown_fixture
done

# T33.b 모르는 키·잘못된 값 → 전부 한 번에 알리고 아무것도 쓰지 않는다
setup_fixture
printf 'kind=3\nprinciples=skip\nprd.oneline=a\nprd.persona=b\nprd.values=c\nprd.m1=d\nprd.m2=e\nprd.m3=f\ndb=maybe\nscreen=home\n' > ans.txt
out=$(bash "$SCRIPT" --answers ans.txt demo 2>&1 </dev/null); rc=$?
if [ "$rc" -eq 2 ] && _no_artifacts && printf '%s' "$out" | grep -q 'db' && printf '%s' "$out" | grep -q 'screen'; then
  ok "T33.b 잘못된 값(db=maybe)·모르는 키(screen) → rc=2 · 둘 다 고지 · 산출물 0"
else
  nope "T33.b" "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
fi
# T33.c 답변 파일이 없으면 멈춘다
out=$(bash "$SCRIPT" --answers nope.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 2 ] && _no_artifacts; } && ok "T33.c 답변 파일 부재 → rc=2" || nope "T33.c" "rc=$rc"
teardown_fixture

# T33.d 답변 파일 모드는 stdin 을 읽지 않는다 — stdin 에 엉뚱한 줄이 있어도 결과가 같다
setup_fixture
printf 'db=n\nprd.m3=통계\nkind=3\nprd.m1=등록\nprinciples=skip\nprd.oneline=CLI 데모\nprd.persona=dev\nprd.values=a, b, c\nprd.m2=승인\n' > ans.txt
out=$(printf '4\noverwrite\ny\ny\ny\n' | bash "$SCRIPT" --answers ans.txt demo 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'PROJECT_KIND=3' && [ ! -e DESIGN.md ] \
   && grep -q 'CLI 데모' PRD.md && [ ! -e .specops/memory/data-model.md ]; then
  ok "T33.d 키 순서 무관 · stdin 무시 (kind=3 · db=n 그대로)"
else
  nope "T33.d" "rc=$rc kind=$(printf '%s' "$out" | grep -o 'PROJECT_KIND=.' | head -1)"
fi
# T33.e 이미 부트스트랩된 저장소: rebootstrap·conflict 를 요구하고, rebootstrap=n 이면 아무것도 바꾸지 않는다
git add -A >/dev/null 2>&1; git commit -q -m base
out=$(bash "$SCRIPT" --answers ans.txt demo 2>&1 </dev/null); rc=$?
_need=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*- 빠짐: \([a-z0-9.]*\).*/\1/p' | tr '\n' ' ')
printf 'rebootstrap=n\nconflict=skip\n' >> ans.txt
out2=$(bash "$SCRIPT" --answers ans.txt demo 2>&1 </dev/null); rc2=$?
if [ "$rc" -eq 2 ] && [ "$_need" = "rebootstrap conflict " ] && [ "$rc2" -eq 0 ] \
   && printf '%s' "$out2" | grep -q '취소' && [ -z "$(git status --porcelain | grep -v ans.txt)" ]; then
  ok "T33.e 부트스트랩된 저장소 → rebootstrap·conflict 요구 · rebootstrap=n 이면 무변경"
else
  nope "T33.e" "rc=$rc need=[$_need] rc2=$rc2 st=[$(git status --porcelain | tr '\n' '|' | cut -c1-100)]"
fi
# T33.f --resume + 기록된 종류 → kind 없이도 된다
printf 'db=n\n' > ans2.txt
out=$(bash "$SCRIPT" --resume --answers ans2.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'PROJECT_KIND=3'; } \
  && ok "T33.f --resume + 답변 파일 → kind 생략 가능(기록된 종류 사용)" || nope "T33.f" "rc=$rc out=$(printf '%s' "$out" | tail -3 | tr '\n' ' ' | cut -c1-200)"
teardown_fixture

# T33.g 키 목록은 스크립트가 알려 준다 — 호출자가 스크립트 원문을 읽어 순서를 알아낼 필요가 없다
setup_fixture
out=$(bash "$SCRIPT" --answers-template 2>&1 </dev/null); rc=$?
_miss=""; for k in kind principles prd.oneline prd.persona prd.values prd.m1 prd.m2 prd.m3 design screens db api api.consumer rebootstrap conflict; do
  printf '%s\n' "$out" | grep -qE "^#? ?${k}=" || _miss="$_miss $k"
done
{ [ "$rc" -eq 0 ] && [ -z "$_miss" ] && _no_artifacts; } \
  && ok "T33.g --answers-template → 키 15종 출력 · 아무것도 쓰지 않음" || nope "T33.g" "rc=$rc 누락:[$_miss]"
teardown_fixture

# ── T33.h~: 독립 리뷰가 찾은 사전 점검↔실행 불일치와 가장자리 (20261009) ──
setup_fixture
printf 'kind=3\nprinciple.1=skip\nprd.oneline=a\nprd.persona=b\nprd.values=c, d, e\nprd.m1=f\nprd.m2=g\nprd.m3=h\ndb=skip\n' > ans.txt
out=$(bash "$SCRIPT" --answers ans.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 0 ] && [ -f PRD.md ] && [ ! -e .specops/memory/data-model.md ]; } \
  && ok "T33.h principle.1=skip · db=skip → stdin 모드와 같은 뜻으로 완주(2~5 를 요구하지 않음)" \
  || nope "T33.h" "rc=$rc out=$(printf '%s' "$out" | head -4 | tr '\n' ' ' | cut -c1-200)"
git add -A >/dev/null 2>&1; git commit -q -m base
# 취소로 끝나는 답은 다른 키를 요구하지 않는다
printf 'rebootstrap=n\n' > only-n.txt
out=$(bash "$SCRIPT" --answers only-n.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '취소' && ! printf '%s' "$out" | grep -q '빠짐'; } \
  && ok "T33.i rebootstrap=n 한 줄 → 취소 rc=0 (종류 등 다른 키를 요구하지 않음)" || nope "T33.i" "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)"
# 템플릿의 빈 `kind=` 를 둔 채 재개해도 된다(기록된 종류)
printf 'kind=\ndb=n\n' > resume.txt
out=$(bash "$SCRIPT" --resume --answers resume.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'PROJECT_KIND=3'; } \
  && ok "T33.j --resume + 빈 kind= → 기록된 종류 사용" || nope "T33.j" "rc=$rc out=$(printf '%s' "$out" | head -3 | tr '\n' ' ' | cut -c1-160)"
teardown_fixture

setup_fixture
out=$(cli_stdin | bash "$SCRIPT" --answers "" demo 2>&1); rc=$?
out2=$(cli_stdin | bash "$SCRIPT" --answers= demo 2>&1); rc2=$?
{ [ "$rc" -eq 2 ] && [ "$rc2" -eq 2 ] && _no_artifacts; } \
  && ok "T33.k 빈 답변 파일 경로 → rc=2 (stdin 모드로 조용히 넘어가지 않음)" || nope "T33.k" "rc=$rc rc2=$rc2"
printf '\357\273\277kind=3\n' > bom.txt
out=$(bash "$SCRIPT" --answers bom.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'BOM' && _no_artifacts; } \
  && ok "T33.l BOM 이 붙은 답변 파일 → rc=2 · 원인을 말한다" || nope "T33.l" "rc=$rc out=$(printf '%s' "$out" | head -2 | tr '\n' ' ')"
# T33.m2 화면이 없는 종류(3 CLI)의 요구사항 문서에는 화면 전용 NFR 예시(접근성·브라우저 호환성)가 없다 · 다른 NFR 은 남는다
printf 'kind=3\nprinciples=skip\nprd.oneline=CLI 데모\nprd.persona=dev\nprd.values=a, b, c\nprd.m1=등록\nprd.m2=승인\nprd.m3=통계\ndb=n\n' > cli.txt
out=$(bash "$SCRIPT" --answers cli.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 0 ] && ! grep -qE 'WCAG|Chrome 120' .specops/memory/requirements.md && grep -q '^| NFR-1 | 성능 |' .specops/memory/requirements.md && grep -q '^| NFR-3 | 보안 |' .specops/memory/requirements.md; } \
  && ! grep -q '접근성' PRD.md && grep -q '^- 호환성:' PRD.md \
  && ok "T33.m2 CLI(kind=3) 요구사항·PRD — 접근성·브라우저 호환성 예시 없음 · 성능·보안·PRD 호환성 줄은 유지" || nope "T33.m2" "rc=$rc nfr=$(grep '^| NFR-' .specops/memory/requirements.md 2>/dev/null | cut -c1-24 | tr '\n' ' ')"
teardown_fixture
setup_fixture
# T33.m3 대조 — 화면이 있는 종류(1 Web/UI)에는 그 예시가 남는다
printf 'kind=1\nprinciples=skip\nprd.oneline=웹 데모\nprd.persona=dev\nprd.values=a, b, c\nprd.m1=등록\nprd.m2=승인\nprd.m3=통계\ndesign=1\nscreens=home\ndb=n\napi.consumer=n\n' > web.txt
out=$(bash "$SCRIPT" --answers web.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 0 ] && grep -q '^| NFR-4 | 접근성 |' .specops/memory/requirements.md && grep -q '^| NFR-5 | 호환성 |' .specops/memory/requirements.md; } \
  && grep -q '^- 접근성:' PRD.md \
  && ok "T33.m3 대조 — Web/UI(kind=1) 요구사항·PRD 에는 접근성·호환성 예시 유지" || nope "T33.m3" "rc=$rc out=$(printf '%s' "$out" | head -5 | tr '\n' ' ' | cut -c1-240)"
teardown_fixture
setup_fixture
# T33.n `키 = 값` 처럼 `=` 앞뒤에 공백을 둔 줄도 읽는다 — 종전엔 "모르는 키: kind " 와 "빠짐: kind" 가 함께 나와 원인을 알 수 없었다
printf 'kind = 3\nprinciples = skip\nprd.oneline = CLI 데모\nprd.persona = dev\nprd.values = a, b, c\nprd.m1 = 등록\nprd.m2 = 승인\nprd.m3 = 통계\ndb = n\n' > spaced.txt
out=$(bash "$SCRIPT" --answers spaced.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'PROJECT_KIND=3' && grep -q 'CLI 데모' PRD.md; } \
  && ok "T33.n 키 앞뒤 공백 → 그대로 읽어 완주" || nope "T33.n" "rc=$rc out=$(printf '%s' "$out" | head -4 | tr '\n' ' ' | cut -c1-220)"
teardown_fixture
setup_fixture
# T33.o 모르는 키는 여전히 알린다 — 공백을 허용한다고 오타까지 삼키지 않는다 (키 이름을 따옴표로 보여 공백이 보이게)
printf 'kind = 3\nscreen = home\n' > spaced2.txt
out=$(bash "$SCRIPT" --answers spaced2.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "모르는 키: 'screen'" && ! printf '%s' "$out" | grep -q '빠짐: kind' && _no_artifacts; } \
  && ok "T33.o 공백 낀 모르는 키 → 이름을 따옴표로 고지 · kind 는 읽힘" || nope "T33.o" "rc=$rc out=$(printf '%s' "$out" | head -4 | tr '\n' ' ' | cut -c1-220)"
# T33.p 가치제안은 3개다 — 2개면 쓰기 전에 알린다 (종전엔 통과해 PRD 에 자리표시자가 남았다)
printf 'kind=3\nprinciples=skip\nprd.oneline=x\nprd.persona=p\nprd.values=a,b\nprd.m1=1\nprd.m2=2\nprd.m3=3\ndb=n\n' > two.txt
out=$(bash "$SCRIPT" --answers two.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '잘못된 값: prd.values' && printf '%s' "$out" | grep -q '2개' && _no_artifacts; } \
  && ok "T33.p 가치제안 2개 → rc=2 · 개수를 말한다 · 산출물 0" || nope "T33.p" "rc=$rc out=$(printf '%s' "$out" | head -4 | tr '\n' ' ' | cut -c1-220)"
# T33.q 빈 항목이 섞인 3칸(`a,,c`)도 3개가 아니다 · 4개 이상은 앞 3개만 쓰이므로 알린다
printf 'kind=3\nprinciples=skip\nprd.oneline=x\nprd.persona=p\nprd.values=a,,c\nprd.m1=1\nprd.m2=2\nprd.m3=3\ndb=n\n' > hole.txt
out=$(bash "$SCRIPT" --answers hole.txt demo 2>&1 </dev/null); rc=$?
printf 'kind=3\nprinciples=skip\nprd.oneline=x\nprd.persona=p\nprd.values=a,b,c,d\nprd.m1=1\nprd.m2=2\nprd.m3=3\ndb=n\n' > four.txt
out2=$(bash "$SCRIPT" --answers four.txt demo 2>&1 </dev/null); rc2=$?
{ [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '잘못된 값: prd.values' && [ "$rc2" -eq 2 ] && printf '%s' "$out2" | grep -q '4개' && _no_artifacts; } \
  && ok "T33.q 빈 항목·4개 → rc=2" || nope "T33.q" "rc=$rc rc2=$rc2 out2=$(printf '%s' "$out2" | head -3 | tr '\n' ' ' | cut -c1-200)"
# T33.q2 끝에 콤마가 붙은 3개(`a,b,c,`)는 "빈 항목" 으로 말한다 — "3개가 필요합니다(지금 3개)" 라는 자기모순 문안을 내지 않는다
printf 'kind=3\nprinciples=skip\nprd.oneline=x\nprd.persona=p\nprd.values=a,b,c,\nprd.m1=1\nprd.m2=2\nprd.m3=3\ndb=n\n' > tail.txt
out=$(bash "$SCRIPT" --answers tail.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'prd.values — 빈 항목이 있습니다' && ! printf '%s' "$out" | grep -q '지금 3개' && _no_artifacts; } \
  && ok "T33.q2 끝 콤마 → '빈 항목' 으로 고지" || nope "T33.q2" "rc=$rc out=$(printf '%s' "$out" | head -4 | tr '\n' ' ' | cut -c1-220)"
# T33.r 같은 키가 두 번이면 알린다 — 첫 줄만 쓰이고 뒤 줄(고친 값)은 조용히 버려졌다
printf 'kind=3\nkind=1\nprinciples=skip\nprd.oneline=x\nprd.persona=p\nprd.values=a,b,c\nprd.m1=1\nprd.m2=2\nprd.m3=3\ndb=n\n' > dup.txt
out=$(bash "$SCRIPT" --answers dup.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "중복된 키: 'kind'" && _no_artifacts; } \
  && ok "T33.r 같은 키 중복 → rc=2 · 산출물 0" || nope "T33.r" "rc=$rc out=$(printf '%s' "$out" | head -4 | tr '\n' ' ' | cut -c1-220)"
# T33.s 들여쓴 주석·공백만 있는 줄은 건너뛴다 — 값 읽기와 사전 점검이 같은 규칙이어야 한다(= 가 든 주석이 "모르는 키" 가 됐다)
printf 'kind=3\n   # note: x=1\n\t\n   \nprinciples=skip\nprd.oneline=x\nprd.persona=p\nprd.values=a,b,c\nprd.m1=1\nprd.m2=2\nprd.m3=3\ndb=n\n' > cmt.txt
out=$(bash "$SCRIPT" --answers cmt.txt demo 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'PROJECT_KIND=3'; } \
  && ok "T33.s 들여쓴 주석·공백 줄 → 건너뛰고 완주" || nope "T33.s" "rc=$rc out=$(printf '%s' "$out" | head -4 | tr '\n' ' ' | cut -c1-220)"
teardown_fixture
setup_fixture
# 템플릿은 결정을 미리 채워 두지 않는다 — 빈칸만 채우는 호출자가 기본값을 사용자 선택으로 확정하지 않게
out=$(bash "$SCRIPT" --answers-template 2>&1 </dev/null)
_pre=$(printf '%s\n' "$out" | grep -E '^(kind|principles|design|db|api|api\.consumer|screens|prd\.[a-z0-9]+)=.' | tr '\n' ' ')
[ -z "$_pre" ] && ok "T33.m --answers-template 은 값을 미리 채우지 않는다" || nope "T33.m" "채워진 키: $_pre"
teardown_fixture

# T32.h 메모만 있는 memory 에 숨김 파일(.DS_Store)이 있어도 재부트스트랩을 묻지 않는다
setup_fixture
mkdir -p .specops/memory
printf '# 메모\n' > .specops/memory/brainstorming-20261009-x.md; : > .specops/memory/.DS_Store; : > .specops/memory/learnings.jsonl
out=$(cli_stdin | bash "$SCRIPT" demo 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [ -f PRD.md ] && ! printf '%s' "$out" | grep -q '재부트스트랩'; } \
  && ok "T32.h 메모 + 학습 기록 + 숨김 파일 → 재부트스트랩 질문 없음" || nope "T32.h" "rc=$rc"
teardown_fixture

# T34.e 종류 기록은 머리 구조를 깨지 않는다 — 여러 줄 주석·frontmatter 로 시작하면 끼워 넣지 않고 끝에 붙인다
for _head in multi front; do
  setup_fixture
  mkdir -p .specops/memory
  if [ "$_head" = "multi" ]; then
    printf '<!--\n 손으로 쓴\n 여러 줄 주석\n-->\n# ctx\n' > .specops/memory/project-context.md
  else
    printf -- '---\ntitle: ctx\n---\n# ctx\n' > .specops/memory/project-context.md
  fi
  _orig=$(cat .specops/memory/project-context.md)
  { printf "y\n"; cli_stdin; } | bash "$SCRIPT" demo >/dev/null 2>&1     # y = 재부트스트랩(원장 파일이 이미 있다)
  _now=$(cat .specops/memory/project-context.md)
  _k=$(sed -n 's/^<!-- specops:project-kind: \([1-6]\)[^0-9].*/\1/p' .specops/memory/project-context.md | head -1)
  if [ "$_k" = "3" ] && [ "$(printf '%s\n' "$_now" | sed '$d')" = "$_orig" ]; then
    ok "T34.e($_head) 종류 기록 → 기존 내용 그대로 · 마커는 파일 끝"
  else
    nope "T34.e($_head)" "kind=[$_k] 내용=$(printf '%s' "$_now" | tr '\n' '|' | cut -c1-120)"
  fi
  teardown_fixture
done

# ── T35: 실패를 성공처럼 보고하지 않는다 (20261009 init 점검 — 거짓 성공) ──
# T35.a API 정의 방식 절 정리는 python3 에 기대지 않는다
#   종전엔 python3 가 없으면 방식 절 4개가 전부 남는데 "→ api-spec.md (8f 방식=2 …)" 라고 출력했다.
setup_fixture
mkdir -p "$TMPDIR/nopy"; printf '#!/bin/sh\nexit 127\n' > "$TMPDIR/nopy/python3"; chmod +x "$TMPDIR/nopy/python3"
{
  printf "2\np1\np2\np3\np4\np5\n"
  printf "1. api\n2. dev\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\n"
  printf "n\n2\n"
} | PATH="$TMPDIR/nopy:$PATH" bash "$SCRIPT" demo >/dev/null 2>&1
_secs=$(grep -cE '^## §[1-4]\.' .specops/memory/api-spec.md 2>/dev/null || true)
if [ "${_secs:-0}" = "1" ] && grep -q '^## §2\. OpenAPI' .specops/memory/api-spec.md \
   && grep -q '^## §5\.' .specops/memory/api-spec.md && grep -q '^## §0\.' .specops/memory/api-spec.md; then
  ok "T35.a python3 없이도 고른 방식 절만 남는다 (§2 · 공통 절 §0·§5 유지)"
else
  nope "T35.a" "방식 절 ${_secs}개 (기대 1)"
fi
teardown_fixture

# T35.b 대소문자만 다른 파일(prd.md)을 산출물(PRD.md)의 "기존 파일"로 착각하지 않는다
#   대소문자를 구분하지 않는 파일시스템(macOS 기본)에서 prd.md 가 있으면 `[ -e PRD.md ]` 가 참이라 "PRD.md 보존"
#   으로 빠졌고, 확정한 PRD 6필드가 버려져 CLAUDE.md 는 `<TODO>` · FR 시드는 자리표시자였다(문서의 사용 예 그대로).
#   그 파일시스템에서는 둘을 함께 둘 수 없으므로 쓰기 전에 멈추고 이유를 말한다. 구분하는 파일시스템에서는 공존한다.
setup_fixture
printf '# 기획 원문\n\n하루 글 초안을 만든다.\n' > prd.md
_ci=0; [ -e PRD.md ] && _ci=1
out=$(cli_stdin | bash "$SCRIPT" demo 2>&1); rc=$?
if [ "$_ci" = "1" ]; then
  if [ "$rc" -eq 2 ] && [ ! -e CLAUDE.md ] && [ ! -d .specops/memory ] && grep -q '기획 원문' prd.md \
     && printf '%s' "$out" | grep -q 'prd.md'; then
    ok "T35.b (대소문자 무시 FS) prd.md 가 있으면 쓰기 전에 멈춤 · 원문 보존 · 이유 출력"
  else
    nope "T35.b" "rc=$rc out=$(printf '%s' "$out" | tail -3 | tr '\n' ' ' | cut -c1-200)"
  fi
  printf 'kind=3\nprinciples=skip\nprd.oneline=a\nprd.persona=b\nprd.values=c, d, e\nprd.m1=f\nprd.m2=g\nprd.m3=h\ndb=n\n' > "$TMPDIR/../ans-$$.txt"
  out=$(bash "$SCRIPT" --answers "$TMPDIR/../ans-$$.txt" demo 2>&1 </dev/null); rc=$?; rm -f "$TMPDIR/../ans-$$.txt"
  { [ "$rc" -eq 2 ] && [ ! -e CLAUDE.md ] && printf '%s' "$out" | grep -q 'prd.md'; } \
    && ok "T35.c (대소문자 무시 FS) 답변 파일 모드도 같은 이유로 멈춤" || nope "T35.c" "rc=$rc"
else
  if [ "$rc" -eq 0 ] && grep -q '기획 원문' prd.md && grep -q 'CLI 데모' PRD.md; then
    ok "T35.b (대소문자 구분 FS) prd.md 와 PRD.md 공존 · 6필드 반영"
  else
    nope "T35.b" "rc=$rc"
  fi
  ok "T35.c (대소문자 구분 FS) 해당 없음"
fi
teardown_fixture

# T35.e 대소문자 검사는 PRD 만 본다 — readme.md 같은 흔한 이름으로 정상 저장소를 막지 않는다 (독립 리뷰)
#   README·CLAUDE·DESIGN 은 대소문자가 달라도 보존 정책으로 그대로 두면 되고 잃는 것이 없다.
setup_fixture
printf '# 내 프로젝트\n' > readme.md
_ci=0; [ -e README.md ] && _ci=1
if [ "$_ci" = "1" ]; then
  out=$({ printf "skip\n"; cli_stdin; } | bash "$SCRIPT" demo 2>&1); rc=$?     # skip = 충돌 정책(README 가 이미 있다)
else
  out=$(cli_stdin | bash "$SCRIPT" demo 2>&1); rc=$?
fi
{ [ "$rc" -eq 0 ] && [ -f PRD.md ] && grep -q '내 프로젝트' readme.md; } \
  && ok "T35.e readme.md 가 있는 저장소 → 멈추지 않고 진행 · 내용 보존" || nope "T35.e" "rc=$rc out=$(printf '%s' "$out" | tail -2 | tr '\n' ' ' | cut -c1-160)"
teardown_fixture

# T35.f PRD.md 를 보존해도 확정한 6필드는 다른 산출물에 쓴다 (PRD.md 자체는 고치지 않는다)
#   "prd.md 를 PRD.md 로 맞춘다" 는 안내를 따르면 PRD 가 보존되는데, 종전엔 그때 6필드가 통째로 버려져
#   CLAUDE.md 는 `<TODO>` · FR 시드는 자리표시자였다 — 고쳤다던 증상이 그 경로로 그대로 났다(독립 리뷰 재현).
for _how in answers fields; do
  setup_fixture
  printf '# 기획 원문\n\n자유 형식의 PRD.\n' > PRD.md; _prd=$(cat PRD.md)
  if [ "$_how" = "answers" ]; then
    printf 'kind=3\nconflict=skip\nprinciples=skip\nprd.oneline=하루 글 초안 자동화\nprd.persona=운영자\nprd.values=a, b, c\nprd.m1=초안 생성\nprd.m2=검토\nprd.m3=통계\ndb=n\n' > "$TMPDIR/../a-$$.txt"
    bash "$SCRIPT" --answers "$TMPDIR/../a-$$.txt" demo >/dev/null 2>&1 </dev/null; rc=$?; rm -f "$TMPDIR/../a-$$.txt"
  else
    mkdir -p .specops; printf '하루 글 초안 자동화\n운영자\na, b, c\n초안 생성\n검토\n통계\n' > .specops/.init-prd-fields
    printf 'skip\n3\nskip\nn\n' | bash "$SCRIPT" demo >/dev/null 2>&1; rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ "$(cat PRD.md)" = "$_prd" ] && grep -q '하루 글 초안 자동화' CLAUDE.md \
     && ! grep -q '^<TODO>$' CLAUDE.md && grep -qE '^\| FR-1 \| 초안 생성 \| M1 \|' .specops/memory/requirements.md \
     && [ ! -e .specops/.init-prd-fields ]; then
    ok "T35.f($_how) PRD.md 보존 + 6필드 → CLAUDE.md 한 줄 설명·FR 시드 반영 · PRD.md 무변경 · 필드 파일 회수"
  else
    nope "T35.f($_how)" "rc=$rc claude=[$(sed -n '5,8p' CLAUDE.md 2>/dev/null | tr '\n' '|' | cut -c1-80)] fr=[$(grep -E '^\| FR-1 ' .specops/memory/requirements.md 2>/dev/null | cut -c1-50)]"
  fi
  teardown_fixture
done

# T35.d 활성 산출물 표기의 분모는 정본 개수(14)다 — 풀스택이 "14/13" 으로 찍혔다
setup_fixture
out=$(fullstack_stdin | bash "$SCRIPT" demo 2>&1)
{ printf '%s' "$out" | grep -q '14/14' && ! printf '%s' "$out" | grep -q '/13'; } \
  && ok "T35.d 활성 산출물 표기 14/14" || nope "T35.d" "$(printf '%s' "$out" | grep '스테이징 완료' | cut -c1-80)"
teardown_fixture

# ── T36: 뒤 단계가 읽는 값의 정직성 (20261009 init 점검) ──
# T36.a 헌법을 skip 해도 결정이 아닌 토큰(프로젝트명·날짜)은 채우고, CLAUDE.md 에 가짜 원칙 이름을 쓰지 않는다
#   종전엔 skip 이면 템플릿을 토큰째 복사했고(`# <PROJECT_NAME> 헌법`), CLAUDE.md 에는 "원칙 1: 원칙1" 이 들어갔다 —
#   채워진 것처럼 보이는 값이라 미채움 스캔에도 안 걸렸다(실기록: 그 상태로 FID 60개 진행).
setup_fixture
cli_stdin | bash "$SCRIPT" demo >/dev/null 2>&1
_c=.specops/memory/constitution.md
if grep -q '^# demo 헌법' "$_c" && ! grep -q '<PROJECT_NAME>\|<YYYY-MM-DD>' "$_c" \
   && grep -q '<PRINCIPLE_1_NAME>' "$_c" \
   && grep -qF -- '- 원칙 1: <미확정 — 근거 필요>' CLAUDE.md && ! grep -qE '^- 원칙 [1-5]: 원칙[1-5]$' CLAUDE.md; then
  ok "T36.a 헌법 skip → 프로젝트명·날짜는 채움 · 원칙 이름은 자리표시자 유지 · CLAUDE.md 는 미확정 마커"
else
  nope "T36.a" "head=[$(sed -n '5p' "$_c")] claude=[$(grep -E '^- 원칙 1:' CLAUDE.md)]"
fi
teardown_fixture

# T36.b 마일스톤 문구의 `|` 가 FR 표의 칸을 깨지 않는다
#   종전엔 "주문 등록 | 조회" 가 그대로 들어가 칸이 하나 밀렸고, FR 판독기가 마일스톤을 "조회" 로 읽었다.
setup_fixture
{
  printf "3\nskip\n"
  printf "1. 한 줄: x\n2. 페르소나: y\n3. 가치: a, b, c\n4. M1: 주문 등록 | 조회\n5. M2: m2\n6. M3: m3\n\n"
  printf "n\n"
} | bash "$SCRIPT" demo >/dev/null 2>&1
_row=$(grep -E '^\| FR-1 \|' .specops/memory/requirements.md | head -1)
_bars=$(printf '%s' "$_row" | tr -cd '|' | wc -c | tr -d ' ')
if [ "$_bars" = "6" ] && printf '%s' "$_row" | grep -q '| M1 | must |' && printf '%s' "$_row" | grep -q '주문 등록' \
   && grep -qF -- '- **M1**: 주문 등록 | 조회' PRD.md; then
  ok "T36.b 마일스톤의 | → FR 시드 행은 칸 5개 유지(구분자 치환) · PRD 원문은 그대로"
else
  nope "T36.b" "bars=$_bars row=[$_row]"
fi
teardown_fixture

# T36.c 문서가 실제 동작을 말한다 (낡은 문구 잠금)
_d=0
grep -q '후속 릴리즈' "$PLUGIN/skills/using-specops-ko/SKILL.md" && { _d=1; echo "  using-specops-ko: --resume 을 '후속 릴리즈'라 적음"; }
grep -q 'sync` 로 상태 셀' "$PLUGIN/commands/start-all.md" && { _d=1; echo "  start-all: sync 가 칸을 고친다고 적음(sync 는 행만 추가한다)"; }
grep -q '상태 셀' "$PLUGIN/commands/init-project.md" && { _d=1; echo "  init-project: 표에 없는 '상태 셀'을 가리킴(실제는 목적 칸)"; }
grep -q '다시 게이트' "$PLUGIN/commands/init-project.md" || { _d=1; echo "  init-project: 수정 뒤 재승인 지시 없음"; }
grep -q '미확정 — 근거 필요.*채운다\|채운다.*미확정 — 근거 필요' "$PLUGIN/skills/specifying-ko/SKILL.md" || { _d=1; echo "  specifying-ko: 재사용 화면의 미확정 항목을 메우라는 지시 없음"; }
[ "$_d" = "0" ] && ok "T36.c 문서의 낡은 문구 0 · 재승인·미확정 메움 지시 존재" || nope "T36.c" "위 항목 참고"

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
