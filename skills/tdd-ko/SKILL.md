---
name: tdd-ko
description: 기능·버그픽스·리팩터링 구현 시 구현 코드 작성 전 반드시 사용 — Red-Green-Refactor 사이클 강제, 프로덕션 코드는 실패 테스트 없이 작성 금지
layer: 2
discipline: true
reference_upstream: obra/superpowers@v5.0.7 skills/test-driven-development/SKILL.md
  - obra/superpowers@v5.0.7 skills/test-driven-development/SKILL.md
  - affaan-m/everything-claude-code@1.2.0 skills/tdd-workflow
  - skills/tdd-ko/SKILL.md
specops_version: 1.73.0
used_by: implementing-ko (서브에이전트가 각 태스크마다 본 스킬 따름)
---

# Engine 스킬 — 테스트 주도 개발 (TDD)

## 개요

**먼저 테스트를 쓴다. 실패하는 것을 본다. 통과시킬 최소 코드를 쓴다.**

**핵심 원칙**: **테스트가 실패하는 것을 보지 않았다면 올바른 것을 테스트하는지 모른다.**

**규칙의 문구를 어기는 것은 규칙의 정신을 어기는 것이다.**

## 사용 시점

**항상**:
- 신규 기능
- 버그 픽스
- 리팩터링
- 동작 변경

**예외 (사용자 파트너에게 질문)**:
- 일회용 프로토타입
- 생성된 코드
- 설정 파일

"이번만 TDD 생략"이라는 생각? 중단. 그건 합리화.

## 철칙 (Iron Law)

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
실패 테스트 없이 프로덕션 코드 금지
```

테스트 전 코드 작성했나? **삭제**. 처음부터 다시.

**예외 없음**:
- "참조용"으로 남기지 말 것
- 테스트 쓰는 동안 "적응"시키지 말 것
- 보지 말 것
- **삭제는 삭제**

테스트에서 신선하게 구현. 끝.

## Red-Green-Refactor

```
RED (실패 테스트 작성)
    ↓
실패 올바르게? ─── no (잘못된 실패) ───┐
    ↓ yes                            ↑
GREEN (최소 코드)                     │
    ↓                                │
전부 green? ─── no ──────────────────┘
    ↓ yes
REFACTOR (정리)
    ↓ (green 유지)
다음 → RED
```

> **명칭 관계** (P2-② drift 정리 — TDD 감사 20260711): decomposing-ko 의 태스크 **"5스텝"**(RED 작성→FAIL 검증→GREEN 구현→PASS 검증→**COMMIT**)은 본 Red-Green-**Refactor** 사이클의 **태스크 실행형**이다 — RED/GREEN 을 각각 "작성+검증" 2스텝으로 쪼개고 커밋을 스텝으로 명시한 것. REFACTOR 는 5스텝 안에 없는 게 **의도**다: 2~5분 태스크 안에서는 GREEN 후 즉시 커밋하고, 정리가 필요하면 **별도 리팩터링 태스크**(green 유지 확인 포함)로 분해한다. "5스텝에 REFACTOR 가 빠졌다"는 결함이 아니라 단위 차이다.

### RED — 실패 테스트 작성

무엇이 일어나야 하는지 보여주는 **최소 테스트 하나** 작성.

**좋은 예**:
```typescript
test('retries failed operations 3 times', async () => {
  let attempts = 0;
  const operation = () => {
    attempts++;
    if (attempts < 3) throw new Error('fail');
    return 'success';
  };

  const result = await retryOperation(operation);

  expect(result).toBe('success');
  expect(attempts).toBe(3);
});
```
명확한 이름, 실제 동작 테스트, 하나만.

**나쁜 예**:
```typescript
test('retry works', async () => {
  const mock = jest.fn()
    .mockRejectedValueOnce(new Error())
    .mockRejectedValueOnce(new Error())
    .mockResolvedValueOnce('success');
  await retryOperation(mock);
  expect(mock).toHaveBeenCalledTimes(3);
});
```
모호한 이름, 코드가 아닌 mock 테스트.

**요구**:
- 하나의 동작
- 명확한 이름
- 실제 코드 (불가피한 경우 아니면 mock 금지)

### Verify RED — 실패 확인

**필수. 절대 생략 금지.**

```bash
npm test path/to/test.test.ts
```

확인:
- 테스트가 **실패**함 (error가 아니라)
- 실패 메시지가 **예상대로**
- 기능 부재로 실패 (오타 때문 아님)

**테스트가 통과?** 기존 동작을 테스트 중. 테스트 수정.

**테스트가 error?** 에러 고치고 **올바르게 실패할 때까지** 재실행.

### RED 대체 — detection-proof (테스트 전용·이미 동작하는 로직)

일부 태스크는 **새 동작 구현이 아니라 이미 정상 동작하는 로직에 테스트를 추가**한다 — 커버리지 보강·스캐너 탐지 테스트·회귀 락인. 이때 코드가 이미 통과하므로 **자연스러운 RED 가 없다.** 위 "테스트가 통과? → 테스트 수정"은 이 경우엔 **틀린 처방**이다(테스트가 옳고, 기존 동작을 검증하려는 게 목적).

대신 **detection-proof 로 RED 를 대체**한다 — 테스트가 실제 탐지력이 있음(tautology 아님)을 **변이(mutation)로 증명**:

1. **규칙 뒤집기 (rule inversion)** — 대상 로직/규칙을 일시 반전(우선순위 역전·조건 부정·랭크 역전)하고 테스트가 **FAIL** 하는지 확인 → 복원.
2. **유령 주입 (ghost injection)** — 잡혀야 할 가짜 케이스(존재하면 안 되는 경로·항목)를 주입하고 테스트가 **FAIL(탐지)** 하는지 확인 → 제거.

변이본에서 테스트가 FAIL 하면 = RED 가 증명하려던 것("이 테스트는 실패할 수 있다")과 **동치**다. **변이해도 통과하는 테스트는 tautology** — RED 미충족과 같으니 테스트를 강화한다.

> **원칙**: RED 의 본질은 "실패 테스트를 먼저 쓰는 것"이 아니라 **"테스트가 fail 할 수 있음을 관찰하는 것"**이다. 새 동작은 코드 부재로 fail 하고(자연 RED), 기존 동작은 변이로 fail 시켜 증명한다(detection-proof). **둘 다 실측 출력 원문 인용 필수**(변이본 FAIL 출력 = RED 원문 인용 규약과 대칭). 근거: 20260718 test2 정주행 — 테스트 전용 태스크에서 이 패턴을 run 이 스스로 발명(규칙 뒤집기·유령 주입)해 TDD 깊이를 대체했다.

### GREEN — 최소 코드

테스트 통과에 필요한 **가장 단순한 코드** 작성.

**좋은 예**:
```typescript
async function retryOperation<T>(fn: () => Promise<T>): Promise<T> {
  for (let i = 0; i < 3; i++) {
    try {
      return await fn();
    } catch (e) {
      if (i === 2) throw e;
    }
  }
  throw new Error('unreachable');
}
```
통과만 시킴.

**나쁜 예**:
```typescript
async function retryOperation<T>(
  fn: () => Promise<T>,
  options?: {
    maxRetries?: number;
    backoff?: 'linear' | 'exponential';
    onRetry?: (attempt: number) => void;
  }
): Promise<T> {
  // YAGNI
}
```
과잉 설계.

**기능 추가·다른 코드 리팩터링·"개선" 금지**. 테스트 너머로 가지 말 것.

### Verify GREEN — 통과 확인

**필수.**

```bash
npm test path/to/test.test.ts
```

확인:
- 테스트 통과
- 다른 테스트도 여전히 통과
- 출력 **청정** (에러·경고 없음)

**테스트 실패?** 테스트가 아니라 **코드** 수정.

**다른 테스트 실패?** **지금** 수정.

### REFACTOR — 정리

green 이후에만:
- 중복 제거
- 이름 개선
- 헬퍼 추출

**테스트 green 유지**. 동작 추가 금지.

### 반복

다음 기능의 다음 실패 테스트로.

## 좋은 테스트

| 품질 | 좋음 | 나쁨 |
|---|---|---|
| **최소** | 하나의 일. 이름에 "and" 있음? 분할 | `test('validates email and domain and whitespace')` |
| **명확** | 이름이 동작을 설명 | `test('test1')` |
| **의도 표현** | 원하는 API 시연 | 코드가 해야 할 일을 가림 |

## 순서가 중요한 이유

**"코드 후에 테스트 쓰면 되지"**

코드 후에 쓴 테스트는 **즉시 통과**. 즉시 통과는 아무것도 증명 못 함:
- 엉뚱한 것 테스트했을 수도
- 동작이 아니라 구현을 테스트했을 수도
- 잊어버린 엣지 케이스를 놓쳤을 수도
- 테스트가 버그를 잡는 것을 **본 적이 없음**

테스트 먼저는 **실패를 강제로 보게** 해서 실제로 테스트함을 증명.

**"이미 수동으로 엣지 케이스 다 테스트했다"**

수동 테스트는 **ad-hoc**. 다 테스트한 것 같지만:
- 무엇을 테스트했는지 **기록 없음**
- 코드 바뀌면 재실행 불가
- 압박 상황에서 케이스 잊기 쉬움
- "해봤을 때 되더라" ≠ 포괄적

자동 테스트는 **체계적**. 매번 같은 방식으로 실행.

**"X시간 작업 삭제는 낭비"**

**매몰비용 오류**. 시간은 이미 지나갔다. 지금 선택:
- 삭제 + TDD로 재작성 (X시간 더, 높은 신뢰)
- 유지 + 나중에 테스트 (30분, 낮은 신뢰, 버그 가능성 높음)

"낭비"는 **신뢰할 수 없는 코드 유지**. 진짜 테스트 없는 동작 코드는 기술 부채.

## 합리화 차단표

| 변명 | 실제 |
|---|---|
| "테스트하기엔 너무 단순" | 단순 코드도 깨진다. 테스트는 30초. |
| "나중에 테스트" | 즉시 통과는 아무것도 증명 못 함 |
| "나중에 테스트로 같은 목표" | 나중 = "뭐 하는지", 먼저 = "뭐 해야 하는지" |
| "이미 수동 테스트" | Ad-hoc ≠ 체계적. 기록 없음. 재실행 불가 |
| "X시간 삭제는 낭비" | 매몰비용. 미검증 코드 유지가 부채 |
| "참조로 남기고 테스트 먼저" | 적응할 것. 그게 나중 테스트. 삭제는 삭제 |
| "먼저 탐색 필요" | OK. 탐색 버리고 TDD 시작 |
| "테스트 어려움 = 설계 불명확" | 테스트에게 들으라. 테스트 어려움 = 쓰기 어려움 |
| "TDD는 느려" | TDD가 디버깅보다 빠름. 실용 = 테스트 먼저 |
| "수동 테스트 빠름" | 수동은 엣지 케이스 증명 못 함. 매 변경 재테스트 |
| "기존 코드에 테스트 없음" | 개선 중. 기존 코드에도 테스트 추가 |
| "RED 는 카운트 요약이면 충분" | RED 실측 출력 원문(요약행+FAIL 라인 ≤10줄) 인용 없이는 관찰 증거 아님. GREEN 원문 인용과 대칭 |

## 레드 플래그 — 중단하고 처음부터

- 테스트 전 코드
- 구현 후 테스트
- 테스트가 즉시 통과
- 테스트 실패 이유 설명 불가
- 테스트 "나중에"
- "이번만" 합리화
- "이미 수동 테스트했다"
- "나중 테스트도 같은 목적"
- "문구가 아니라 정신"
- "참조로 유지"·"기존 코드 적응"
- "X시간 썼는데 삭제는 낭비"
- "TDD 교조적, 실용적으로"
- "이건 다르다, 왜냐하면..."

**모두 의미**: 코드 삭제. TDD로 처음부터.

## 예시 — 버그 픽스

**버그**: 빈 이메일 수락됨

**RED**:
```typescript
test('rejects empty email', async () => {
  const result = await submitForm({ email: '' });
  expect(result.error).toBe('Email required');
});
```

**Verify RED**:
```
$ npm test
FAIL: expected 'Email required', got undefined
```

**GREEN**:
```typescript
function submitForm(data: FormData) {
  if (!data.email?.trim()) {
    return { error: 'Email required' };
  }
  // ...
}
```

**Verify GREEN**:
```
$ npm test
PASS
```

**REFACTOR**: 여러 필드 대상이면 검증 추출.

## 검증 체크리스트

작업 완료 표시 전:

- [ ] 모든 신규 함수/메서드에 테스트 있음
- [ ] 각 테스트가 구현 전 **실패하는 것을 보았다**
- [ ] 각 테스트가 **예상된 이유**로 실패 (기능 부재, 오타 아님)
- [ ] 각 테스트를 통과시키는 **최소 코드** 작성
- [ ] 모든 테스트 통과
- [ ] 출력 청정 (에러·경고 없음)
- [ ] 테스트가 실제 코드 사용 (불가피한 경우만 mock)
- [ ] 엣지 케이스와 에러 커버

다 체크 못 하면? TDD 생략한 것. **처음부터**.

## 막혔을 때

| 문제 | 해법 |
|---|---|
| 어떻게 테스트할지 모름 | 원하는 API 작성. 단언(assertion) 먼저 작성. 사용자 파트너에게 질문 |
| 테스트가 너무 복잡 | 설계가 너무 복잡. 인터페이스 단순화 |
| 전부 mock해야 함 | 코드가 너무 결합. DI(의존성 주입) 사용 |
| 테스트 셋업 거대 | 헬퍼 추출. 여전히 복잡? 설계 단순화 |

## 디버깅 통합

버그 발견? 재현하는 **실패 테스트 먼저 작성**. TDD 사이클 따름. 테스트가 픽스를 증명하고 회귀 방지.

**테스트 없이 버그 수정 금지**.

## 마이그레이션(DDL)도 TDD (gap3)

스키마 변경도 예외 아님 — **up→down→up 멱등 테스트를 먼저** 작성(RED: 마이그레이션 파일 부재로 실패)하고 forward/reverse 를 구현한다. 제약(NOT NULL/CHECK/UNIQUE/FK) 위반 경로·인덱스 존재도 테스트 대상. 상세 정책: `templates/test-strategy.md §4.5` · 태스크 분해: `decomposing-ko` "마이그레이션 태스크 분해".

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 테스트 실패·통과 로그 **캡처** (`.specops/<FID>/test-log.md`) |
| 2 **문지기** | "이번만 생략" 제안은 즉시 거절. 사용자 파트너만 예외 허가 |
| 3 **깊이** | 즉시 통과하는 테스트는 의심. 실패 먼저 보기 |
| 4 **주권 존중** | TDD 예외 결정은 사용자. 에이전트 단독 예외 금지 |
| 5 **한계 고백** | 테스트 이유 설명 불가면 "이 테스트의 의도를 확신 못 함" 선언 |

## 최종 법칙

```
프로덕션 코드 → 테스트 존재하고 먼저 실패함
그 외 → TDD 아님
```

사용자 파트너 허가 없이 예외 없음.

## 참조

- ECC 보완: `affaan-m/everything-claude-code@1.2.0 skills/tdd-workflow/`
- specops-ko 한국어 선례: `skills/tdd-ko/SKILL.md`
- `skills/karpathy-ko/SKILL.md` — 원칙 4 목표 기반 실행 (Goal-Driven Execution)

## 다음 skill

본 스킬은 **서브루틴 스킬**. `devfsd:implementing-ko`가 각 태스크마다 서브에이전트에게 본 스킬을 따르도록 지시한다.

단독 호출 후에는 상위 호출자(`implementing-ko` 또는 사용자)가 다음 단계 결정. TDD 사이클 완료 후 명시적 다음 스킬은 없음.
