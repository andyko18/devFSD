---
name: design-interface
disable-model-invocation: true
description: "[lifecycle 밖] 인터페이스 1개 설계 — api-spec.md·data-model.md 마스터 반영. lifecycle 안은 Step 5.6(단일)·Phase 2.5-B(batch) 가 자동 처리"
triggers:
  - "/design-interface"
mode: ask
specops_version: 2.6.0
specops_layer: Lifecycle-Tool
reference_upstream: specops-ko 독자 추가
---

# /design-interface [name]

## 목적

`api-spec.md`(IF 설계서)의 채택 정의방식 섹션 + `data-model.md`(테이블 설계서)에 엔드포인트/테이블 1건을 설계 반영한다. 화면이 `screens/{name}.{md,html}` 파일을 만드는 것과 달리, 인터페이스는 **per-endpoint 파일 없이 마스터 문서 섹션을 대화로 갱신**한다 (무스크립트).

## 인터페이스 설계 경로 분업

| 경로 | 진입 | 언제 쓰나 |
|---|---|---|
| **specifying Step 5.6** (인라인) | lifecycle 자동 (API/스키마 기능 spec 승인 직후) | `/start`·`/start-foundation` — 별도 호출 불필요. **`/start-all` batch는 SKIP** |
| **`/start-all` Phase 2.5-B** | batch 오케스트레이터 | FR별 5.6 대신 **화면(2.5-A) 직후** 전 FR 인터페이스 1회 통합. 이어서 **2.5-D `design-reviewer-ko`** 가 정합 리뷰 |
| **`/design-interface [name]`** | 독립 슬래시 | lifecycle 밖에서 **인터페이스 1개** 신규/수정 |
| **`/design-interfaces`** | 독립 슬래시 | lifecycle 밖에서 **여러 인터페이스 일괄** (목록 자동판단+승인게이트+순차루프) |

> `/init-project` Phase 11 이 `api-spec.md`·`data-model.md` 를 PRD 기반 **실설계**로 채운다 — M1 범위는 설계 리뷰까지 끝내고 문서 머리에 `<!-- specops:init-designed: M1 -->` 표지를 단다(지우지 않는다). 위 경로는 그 위에 FR 확정분을 갱신하고 남은 미확정을 메운다.

## Process

### Step 1: 화면 Interactions 참조 (design-first 도출)

`screens/*.md` 존재 시 각 화면의 `## Interactions`("요소 → 결과/화면")를 스캔해 이 `{name}` 이 필요로 하는 엔드포인트·테이블 초안을 도출한다. 화면 부재(BE-only/CLI) 시 사용자에게 직접 명시 요청 (추측 금지).
예: 화면의 `저장 버튼 → 주문 생성` Interaction → `POST /orders` 엔드포인트 + `orders` 테이블 도출.

### Step 2: 인터페이스 대화

사용자에게:
> "인터페이스 설계를 시작합니다:
> 1. 엔드포인트 **경로·메서드**? (예: POST /orders) 또는 **테이블명·핵심 필드**?
> 2. 요청/응답 **스키마**?
> 3. **인증**? (세션/JWT/없음)
> 4. 저장 방식? **제공 API**(내가 만드는 서버) / **외부 소비 API**(3rd party 호출) / **클라이언트 스토리지**(localStorage·IndexedDB — 서버 없는 프론트 영속 데이터)"

### Step 3: 마스터 문서 갱신 (append — 덮어쓰기 금지)

- **제공 API**: `.specops/memory/api-spec.md §0` 에서 **채택된 정의방식 섹션**(§1 Markdown 표 / §2 OpenAPI / §3 GraphQL / §4 RPC 중 선택분)에 신규 행 **append**
- **외부 소비 API**: `.specops/memory/api-spec-consumer.md` 에 append (부재 시 `templates/api-spec-consumer.md` 로 생성 확인)
- **DB 스키마 동반 시**: `data-model.md` §3 엔티티 표·§2 ERD 에 append
- **클라이언트 스토리지**(localStorage·IndexedDB): `data-model.md` §1 유형=해당 스토리지 (기존 서버 DB 유형이 있으면 §1 에 `+` 복수 표기 — 덮어쓰기 금지) + §3 엔티티·저장 키 append (HTTP api-spec 아님 — 혼입 금지). IndexedDB 는 objectStore·keyPath·인덱스 수준까지만(트랜잭션·버전 상세는 구현 재량)
- `api-spec.md` **부재** 시(UI-only init): 제공/소비 구분 물어 `templates/api-spec.md`(제공)·`templates/api-spec-consumer.md`(소비) 로 생성 여부 확인

### Step 4: 커밋 (마스터 변경 확정)

갱신한 마스터 문서를 커밋한다 (화면 `/design-screen` Step 5 대칭 — 미커밋 방치·`/design-interfaces` 다건 루프 누적 방지):
```bash
git add .specops/memory/api-spec.md .specops/memory/api-spec-consumer.md .specops/memory/data-model.md 2>/dev/null
git commit -m "design(if): <name> 인터페이스 설계 반영"
```
> 복수 `/design-interfaces` 진행 중이면 각 인터페이스마다 커밋하거나 루프 종료 후 1회 일괄 커밋(오케스트레이터 재량).

### Step 5: 설계 통합 뷰 갱신

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/design-overview.sh
```

출력 1줄의 경로(`.specops/design-overview.html`)를 사용자에게 알린다 — 바뀐 엔드포인트·테이블이 API 목록·ERD 에 보인다. rc≠0(python3 없음·설계 문서 없음)이면 `통합 뷰 생성 못 함 — <사유>` 1줄만 알리고 진행한다(막지 않는다). `/design-interfaces` 루프 안에서는 인터페이스마다 실행하지 않는다(루프가 끝에 1회 한다).

## 안티패턴
- **채택 섹션 덮어쓰기** — §0 미선택 섹션 건드리기 금지 (batch 다수 기능 순차 기록 오염 방지)
- **별도 산출물 생성** — 반드시 api-spec.md·data-model.md 마스터만 갱신 (Step 5.6·verify net 정합)

## 참조
- `commands/design-interfaces.md` — 복수 일괄
- `skills/specifying-ko/SKILL.md` Step 5.6 — lifecycle 인라인 동일 로직
- `templates/api-spec.md`·`api-spec-consumer.md`·`data-model.md`

---

*specops-ko v2.6.0 · 2026-07-10 · 화면 대칭 인터페이스 설계 (무스크립트·마스터 append)*
