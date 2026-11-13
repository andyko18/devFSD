<!-- OWNER_COMMAND: /init-project -->
<!-- layer: Project-Memory -->

# <PROJECT_NAME> 요구사항 설계서

> 한국 SI 표준 "요구사항 설계서". 전사 FR/NFR/제약 마스터. `/init-project` Phase 8a 가 1회 생성.
> 기능별 상세는 `.specops/<FID>/spec.md` 가 위임받음.

## 1. 개요

**프로젝트**: <PRD §1 한 줄 설명 자동 인용>

**문서 목적**: 전사 기능 요구사항 (FR) + 비기능 요구사항 (NFR) + 제약사항 마스터. PRD §4 마일스톤이 본 문서를 통해 기능별 spec 으로 분해됨.

**갱신 정책**: 마일스톤 단위 변경 시 본 문서 갱신. 의존 spec 영향 검토 필수.

## 2. 기능 요구사항 (FR)

각 FR 은 고유 ID + 마일스톤 매핑 + 우선순위 (must / should / nice-to-have).

> **FR-1~3 은 `/init-project` 가 PRD §4 마일스톤(M1~M3)을 1:1 로 시드**한 값이다(각 마일스톤 = 1 FR). 세부 기능은 이 시드를 **여러 FR 로 분해**하며(FR-4, FR-5 …), 각 FR 은 `/start` 진입 시 `.specops/<FID>/spec.md` 로 위임된다.
>
> **공통부**: 스캐폴딩·인증·공통 레이아웃 등은 설명 선두 `[공통]`(예: `| FR-4 | [공통] 프로젝트 스캐폴딩 … |`). `/start-all` 은 `foundation-scope` 로 SKIP — 구현은 `/start-foundation`.

<!-- seed-fr: FR-1,FR-2,FR-3 -->
<!-- foundation-fr: -->
<!-- 예: foundation-fr: FR-4,FR-27,FR-28 — Phase 11 에서 공통 FR ID 를 채운다(선택, [공통] 선두와 이중 인정) -->

| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | <한 줄> | M1 | must | (TBD) |
| FR-2 | <한 줄> | M2 | should | (TBD) |
| FR-3 | <한 줄> | M3 | nice | (TBD) |

## 3. 비기능 요구사항 (NFR)

| ID | 항목 | 기준 | 검증 방법 |
|---|---|---|---|
| NFR-1 | 성능 | <예: API 응답 ≤ 200ms p95> | 부하 테스트 |
| NFR-2 | 가용성 | <예: 월 99.9%> | 모니터링 대시보드 |
| NFR-3 | 보안 | <예: OWASP Top 10 대응> | 보안 리뷰 |
| NFR-4 | 접근성 | <예: WCAG 2.1 AA> | axe-core 자동 검증 |
| NFR-5 | 호환성 | <예: Chrome 120+, Safari 17+, Firefox 120+> | E2E 매트릭스 |

## 4. 제약사항

- 기술 스택: <PRD §7 인용 또는 보강>
- 라이선스: <오픈소스 라이선스 호환성>
- 호환성: <기존 시스템 인터페이스>
- 데이터 보호: <개인정보 보호법 / GDPR 준수>
- 외부 의존성: <3rd party API SLA, 비용>

## 5. 마일스톤별 분기

### M1 — <마일스톤 1 이름>

- 포함 FR: FR-1 (분해 시 FR-4+ 추가)
- 종속 NFR: <NFR ID>
- 예상 기간: <기간>
- 종속 .specops/<FID> 디렉토리: <목록>

### M2 — <마일스톤 2 이름>

- 포함 FR: FR-2
- 종속 NFR: <NFR ID>
- 예상 기간: <기간>

### M3 — <마일스톤 3 이름>

- 포함 FR: FR-3
- 예상 기간: <기간>

## 6. 참조

- 상위: `PRD.md` §4 마일스톤
- 하위: `.specops/<FID>/spec.md` (기능별 상세)
- 헌법: `.specops/memory/constitution.md` — FR/NFR 작성 시 헌법 원칙 준수

---

*작성: <작성자> · <YYYY-MM-DD> · 생성: /init-project (Phase 8a)*
