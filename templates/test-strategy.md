<!-- OWNER_COMMAND: /init-project -->
<!-- layer: Project-Memory -->

# <PROJECT_NAME> 테스트 전략

> 한국 SI 표준 "테스트 CASE" 의 전사 정책. `/init-project` Phase 8h 가 1회 생성.
> 기능별 테스트 CASE 는 `.specops/<FID>/acceptance-criteria.md` 가 흡수 (「스프린트 계약」(docs/harness-principles.md) 계약).

## 1. 테스트 피라미드 정책

목표 비율 (line coverage 기준):

- **단위 테스트** (Unit): <70%>
- **통합 테스트** (Integration): <20%>
- **E2E 테스트** (End-to-End): <10%>

각 레벨의 책임:

- 단위: 함수·클래스·모듈 격리 검증. mock 활용
- 통합: 모듈 간 인터페이스, DB·외부 서비스 연동
- E2E: 사용자 플로우 (UI 클릭 → API → DB)

## 2. 테스트 도구

| 레벨 | 도구 | 비고 |
|---|---|---|
| 단위 | <Jest / Vitest / pytest / JUnit> | <부가 옵션> |
| 통합 | <Supertest / pytest+TestContainers> | DB 격리 정책 |
| E2E | <Playwright / Cypress / Selenium> | <헤드리스 / 헤드풀> |
| 마이그레이션 | <마이그레이션 도구 자체 + TestContainers/일회용 DB> | data-model §6 도구와 동일 — 아래 §4.5 정책 |
| 부하 | <k6 / Locust / JMeter> | NFR-1 검증 |
| 보안 | <Snyk / OWASP ZAP / Trivy> | NFR-3 검증 |

## 3. 커버리지 목표

- **line coverage**: <목표 %>
- **branch coverage**: <목표 %>
- **critical path coverage** (<핵심 경로>): <목표 %>

CI 가 PR 마다 커버리지 측정. 신규 코드 커버리지 기준: <신규 코드 기준>

> 위 임계값은 프로젝트가 정한다 — 정하지 않은 값을 기본값으로 굳히지 않는다(§6.5 가 이 값의 하향을 막는다).

## 4. 회귀 테스트 정책

specops-ko 「스프린트 계약」(docs/harness-principles.md) 와 연동:

- **유지보수 FID** (`/maintain` 진입): `acceptance-criteria.md` 의 `## 회귀 방지 AC (유지보수 FID 필수)` 섹션에 `AC-R-N` ≥ 1 강제
- 회귀 AC 미작성 시 sprint-contracts evaluator 가 `verdict = BLOCK`
- 회귀 테스트는 기존 동작 보존 검증 + 변경 후 동일 입력에 동일 출력 보장

## 4.5. 마이그레이션 테스트 정책 (DB 스키마 변경 시)

decomposing-ko "마이그레이션 태스크 분해"(forward+reverse 쌍)와 연동 — 스키마 변경 FID 는 다음을 테스트로 고정:

- **멱등·역가역성**: up → down → up 이 에러 없이 수렴 (일회용 DB/TestContainers 에서)
- **제약 위반 경로**: NOT NULL / CHECK / UNIQUE / FK 각 제약의 위반 입력이 실제로 거부되는지
- **인덱스 존재**: forward 후 계획된 인덱스가 실제 생성됐는지 (`data-model.md §4` 대조)
- **데이터 보존** (파괴적 변경 시): expand-contract 각 단계에서 기존 행 손실 0 — 회귀 AC-R 과 연계
- down 으로 복구 불가한 변경(DROP 류)은 테스트가 아니라 **격리·승인**(decomposing 비가역 격리)으로 다룬다

## 5. CI 통합

```yaml
# 예: GitHub Actions (.github/workflows/test.yml)
name: tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: <SETUP_RUNTIME>
        run: <SETUP_COMMAND>
      - name: 단위 테스트
        run: <UNIT_TEST_COMMAND>
      - name: 통합 테스트
        run: <INTEGRATION_TEST_COMMAND>
      - name: E2E 테스트
        run: <E2E_TEST_COMMAND>
      - name: 커버리지 보고
        run: <COVERAGE_COMMAND>
```

## 6. 결정 기록

- **mock vs real**: <외부 의존 처리>
- **테스트 데이터**: <데이터 준비 방식>

## 6.5. 완료 정의(DoD)

Phase C(`code-reviewer-ko`)가 "기준 약화"를 판정하는 **바닥선**이다 — 이 아래로 내려가는 변경은 사유 없이 통과하지 않는다.

- **테스트가 통과한다** — 실패를 가리거나 미루지 않는다(러너 종료 코드가 기준).
- **assertion 이 줄지 않는다** — 테스트 파일의 단언 줄(`expect(`·`assert`·프로젝트의 단언 관용구)이 순감소하지 않는다.
- **린트·타입 억제를 새로 달지 않는다** — `eslint-disable`·`@ts-ignore`·`# noqa`·`# type: ignore` 같은 억제 주석 신규 0.
- **테스트를 삭제하거나 skip 하지 않는다** — 테스트 파일·함수 삭제, `.skip`·`xit`·`@pytest.mark.skip`·`t.Skip(` 신규 0.
- **커버리지 등 임계를 낮추지 않는다** — §3 의 임계값·`--cov-fail-under` 하향, 타임아웃 상향 금지.
- **검증 명령을 무력화하지 않는다** — 테스트·린트·빌드 명령 뒤 `|| true`·`continue-on-error: true`·`set +e`·`exit 0` 강제 금지.

**예외 절차**: 바닥선을 의도적으로 낮출 때는 같은 diff 에 사유(주석·AC·커밋 메시지)를 남긴다. 사유가 있으면 Phase C 는 Suggestion 으로 강등하되 항목을 지우지 않는다(AC 소멸은 AC·spec 정정을 가리키는 사유만 인정). 사유 없는 약화는 Important, 삭제·skip 된 테스트가 지키던 AC 가 비면 Critical 이다.

## 7. 참조

- 헌법: `.specops/memory/constitution.md` (TDD 원칙 강제 시)
- 요구사항: `.specops/memory/requirements.md` §3 NFR (성능·가용성 테스트 기준)
- 기능별 AC: `.specops/<FID>/acceptance-criteria.md`

---

*작성: <작성자> · <YYYY-MM-DD> · 생성: /init-project (Phase 8h)*
