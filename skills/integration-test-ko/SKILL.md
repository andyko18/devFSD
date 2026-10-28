---
name: integration-test-ko
description: lifecycle chain에서 통합 표면(API 엔드포인트·DB·다중 모듈 경계) 검출 시 통합 테스트를 작성·실행·증거화. 표면 부재 시 graceful skip
layer: 2
reference_upstream: specops-ko 독자 추가 (test-master 패턴 번안)
specops_version: 2.18.0
used_by: security-review-ko (단일 모드 chain 진입), /start-all (batch 모드 직접 호출), performance-test-ko (chain 출구)
---

# Engine 스킬 — 통합 테스트 (integration-test)

## 개요

**PR 직전, 리뷰 완료된 결과물에 통합 검증을 실시한다.**

코드 리뷰는 각 구성요소를 검사했지만, **통합 표면**—API 엔드포인트·DB 왕복·서비스 간 호출·외부 인터페이스—이 실제로 연결되어 동작하는지는 별도 검증이 필요하다.

**핵심 원칙**: "주장 전에 증거." verifying-evidence-ko의 철칙을 계승. 테스트를 실행하지 않고 통과를 주장하는 것은 부정직이다.

**선결 조건**: 본 skill은 `security-review-ko` 완료 후 호출된다. 코드 리뷰 이슈·보안 스캔 결함이 미해결이면 본 skill 진입 전에 해결한다.

---

## 적용성 판정 게이트

진입 즉시 `spec.md`의 §범위·§NFR·§2 포함 항목을 읽어 **통합 표면 신호**를 검출한다.

**통합 표면 신호 (하나라도 존재 시 → 통합 테스트 단계 진행)**:
- REST / GraphQL / gRPC 엔드포인트 노출
- DB CRUD 왕복 (INSERT·SELECT·UPDATE·DELETE)
- 2개 이상 서비스/모듈 간 호출 경계
- 외부 API·메시지 큐·파일시스템 연동
- 인증/인가 흐름 (JWT·세션·OAuth 토큰 검증)
- **화면 렌더·사용자 흐름** (SPA·컴포넌트 렌더, 클릭·폼 제출·라우팅·브라우저 상호작용 — 순수 프론트 기능 포함)

**UI 표면 검출 시 (화면 렌더·사용자 흐름 신호) — E2E 위임**:
- 브라우저 E2E 는 **downstream 프로젝트 스택(Playwright/Cypress 등)으로 작성·실행**한다(플러그인은 브라우저 인프라 미보유 — execution 은 downstream). `e2e-runner` 에이전트가 있으면 선택적으로 활용(없어도 downstream 스택 직접 지시로 graceful — 하드 의존 금지).
- 실행 환경은 **아래 Step 2 env-check 를 재사용**(별도 fallback 신설 금지) — 불가 시 `[환경 설정 후 재실행 / skip]` 질문.
- **풀스택(UI+백엔드 동시 검출)**: API 통합(supertest/httpx 등)과 UI E2E 를 **각각 수행**(Q5 — 신호 OR, 둘 다 커버).

**신호 없는 경우 (graceful skip)**:
```
INTEGRATION: SKIP — <근거: spec.md §섹션명 Lxx-yy, 표현 예: "§범위 L12-15 — CLI 단일 프로세스, DB·API·외부 IF 없음">
```
위 문자열을 `.specops/<FID>/evidence.md`에 append 후 **즉시 `## 다음 skill`로 chain** (나머지 절차 스킵).

> **SKIP 근거 의무** (V3): SKIP 근거에 spec.md **섹션명 + 라인 번호**를 반드시 인용한다 (예: `§NFR-1 L52`) — `§유형` 과 무관하다(`release-ready.sh` 가 인용 없는 SKIP 을 NOT_READY 로 본다). 근거 없는 SKIP 은 형식화 — 거부.
> **관측**: `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/skip-tracker.sh` 로 게이트별 누적 SKIP 비율(참고)과 **근거 없는(라인인용 없는) SKIP 건수**를 확인할 수 있다 (advisory — bare SKIP 이 형식화 신호). 판정 무기록 FID 는 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gate-coverage.sh ~/repoA ~/repoB` (scripts/README).

> 한계 고백: spec.md가 없거나 §범위 섹션이 없는 경우 → 사용자에게 "spec.md §범위 미발견 — 통합 표면을 수동으로 알려주세요 [혹은 skip?]" 1줄 질문. 사용자 응답에 따라 진행 또는 SKIP 처리.

---

## 통합 테스트 단계 (표면 신호 존재 시)

### Step 1: 테스트 파일 생성·확인

기존 통합 테스트 파일이 있으면 내용 확인. 없으면 신규 작성. downstream 프로젝트의 테스트 러너·구조에 맞춘다.

**API 엔드포인트 패턴** (Supertest/Jest 예시 — downstream 스택으로 등가 구현):

```typescript
// tests/integration/auth.test.ts
import request from 'supertest'
import { app } from '../../src/app'

describe('POST /api/auth/login', () => {
  it('유효 자격증명 → 200 + JWT 반환', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'test@example.com', password: 'valid-password' })
    expect(res.status).toBe(200)
    expect(res.body).toHaveProperty('token')
  })

  it('잘못된 비밀번호 → 401', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'test@example.com', password: 'wrong' })
    expect(res.status).toBe(401)
  })
})
```

**DB 왕복 패턴** (Jest + Prisma/pg 예시 — downstream 스택으로 등가 구현):

```typescript
// tests/integration/user-repository.test.ts
import { db } from '../../src/db'
import { userRepository } from '../../src/repositories/user'

beforeEach(async () => {
  await db.user.deleteMany() // 격리 초기화
})

afterAll(async () => {
  await db.$disconnect()
})

it('사용자 생성 → 조회 왕복', async () => {
  const created = await userRepository.create({
    email: 'test@example.com',
    name: 'Test User',
  })
  const found = await userRepository.findById(created.id)
  expect(found?.email).toBe('test@example.com')
})
```

> **주의**: 위 예시는 TypeScript/Jest 기준. downstream 프로젝트가 Python(pytest+httpx), Go(net/http/httptest), bash 등을 사용하면 **동등한 검증**을 해당 도구로 구현한다.

### Step 2: 실행 환경 전제 확인

테스트 실행 전 다음을 확인한다:
- DB·외부 서비스 연결 가능 여부 (환경변수·Docker Compose 등)
- 테스트 전용 환경 분리 (`.env.test`, 격리 DB 등)
- 불가 시 → 사용자에게 "통합 테스트 실행 환경이 준비되지 않았습니다. [환경 설정 후 재실행 / skip]" 질문

### Step 3: 테스트 실행 및 결과 판정

```bash
# downstream 프로젝트의 통합 테스트 명령 (예시)
npm run test:integration
# 또는
pytest tests/integration/ -v
# 또는
go test ./tests/integration/... -v
```

**결과 분기**:

| 결과 | 처리 |
|---|---|
| exit 0, 전 항목 PASS | `INTEGRATION: PASS — <테스트 수> tests, 0 failures` → evidence.md append → `## 다음 skill` |
| exit 0, skip 있음 | PASS로 간주. skip 이유를 evidence.md에 부기 |
| exit 1, FAIL 존재 | → **FAIL 분기** (아래) |
| 실행 자체 실패 (명령 없음 등) | → 사용자에게 "통합 테스트 명령을 찾을 수 없습니다" 보고 + 해결 후 재시도 |

---

## FAIL 분기 (chain 차단)

테스트를 실행했으나 1건이라도 FAIL이면:

```
INTEGRATION: FAIL — <N> failures:
  - <test name>: <failure message>
  ...
```

위 내용을 `.specops/<FID>/evidence.md`에 append 후 **chain 차단** → `devfsd:systematic-debugging-ko` 호출.

systematic-debugging-ko가 원인 분석·수정을 완료하면 다음 경로로 복귀:
```
수정 완료 → verifying-evidence-ko 재호출 → requesting-code-review-ko → receiving-code-review-ko → (chain 대로 security-review-ko →) integration-test-ko (재진입)
```

> 5원칙 2 문지기: FAIL을 숨기거나 "warning"으로 격하해 통과시키는 것은 금지. 1건이라도 FAIL = chain 차단.

---

## 증거화 (evidence.md append)

PASS·SKIP·FAIL 모든 경우에 `.specops/<FID>/evidence.md`에 결과를 append한다:

```markdown
## /integration-test — <ISO-8601>

**결과**: PASS | SKIP | FAIL
**근거**: <spec.md 섹션 인용 또는 테스트 출력 요약>

<테스트 명령 전문 출력 — PASS/FAIL 시>
```

미실행 상태에서 "PASS"를 주장하는 것은 **verifying-evidence-ko 절칙 위반**이다.

---

## session-progress append

evidence.md append 직후:
```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /integration-test DONE|SKIP|FAIL "<요약>"
# 예: bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh 20260605-login /integration-test SKIP "§범위 L12-15 — CLI 단일 프로세스"
# 예: bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh 20260605-login /integration-test DONE "12 tests passed"
# 예: bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh 20260605-login /integration-test FAIL "2 failures — systematic-debugging-ko 호출"
```

---

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 판정 근거를 spec.md 특정 섹션 인용으로 명시 — "아마 통합 표면 없을 것" 추측 금지 |
| 2 **문지기** | FAIL 1건 = chain 차단. "minor failure"로 격하 금지 |
| 3 **깊이** | 테스트 실행 없이 PASS 주장 금지. 출력 전문을 evidence.md에 기록 |
| 4 **주권 존중** | SKIP 처리 시 근거를 spec.md 라인 번호로 명시 — 사용자가 판단 가능하게 |
| 5 **한계 고백** | 실행 환경 미비·spec.md 미발견 시 추측 진행 금지. 사용자에게 명시 질문 |

---

## 참조

- 번안 원본 패턴: Jeffallan/claude-skills `skills/test-master/references/integration-testing.md` (HEAD SHA e8be415)
- 선행 skill: `skills/receiving-code-review-ko/SKILL.md`
- 증거 원칙: `skills/verifying-evidence-ko/SKILL.md`
- 실패 우회: `skills/systematic-debugging-ko/SKILL.md`

---

## 다음 skill

PASS 또는 SKIP + session-progress append 직후 즉시 호출:

**[batch 모드 분기]** 먼저 spec.md `**§batch**` 라벨 감지 확인:

```bash
grep -qE '^\*\*§batch\*\*:' .specops/<FID>/spec.md && echo "BATCH" || echo "SINGLE"
```

- **batch 모드** (`**§batch**` 라벨 감지) → `BATCH-INTEGRATION-DONE: <FID>` 출력 + **halt**. performance-test-ko 미호출. `/start-all` 오케스트레이터가 다음 단계(성능)를 제어한다

**[단일 모드]** (`**§batch**` 라벨 없는 경우) → 즉시 호출:

```
Skill: devfsd:performance-test-ko
```

performance-test-ko가 성능 NFR 임계값 존재 여부를 판정하고 PR 게이트까지 진행한다. 본 integration-test-ko는 단일 모드에서 **performance-test-ko 이외의 다음 스킬을 호출하지 않는다** (batch halt·FAIL 시 systematic-debugging-ko 경유 후 chain 복귀 제외).
