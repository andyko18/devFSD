---
name: design-interfaces
disable-model-invocation: true
description: "[lifecycle 밖] 복수 인터페이스 일괄 설계 — 목록 자동판단·승인 게이트·순차 루프. lifecycle 안은 Step 5.6·Phase 2.5-B 가 자동 처리"
triggers:
  - "/design-interfaces"
mode: ask
specops_version: 2.6.0
specops_layer: Lifecycle-Tool
reference_upstream: specops-ko 독자 추가
---

# /design-interfaces [기능 설명]

여러 인터페이스를 한 번에 설계하는 오케스트레이터. ① 필요 인터페이스 목록을 자동 판단하고 ② 승인 게이트를 거쳐 ③ 각 인터페이스를 `/design-interface` 대화 루프로 순차 설계한다. 분업 기준은 `§인터페이스 설계 경로 분업`(단수 `commands/design-interface.md`) 참조.

> **분업**: lifecycle 안에서는 **Step 5.6**(단일 `/start`·`/maintain`)·**Phase 2.5-B**(`/start-all` batch)가 자동 처리한다 — 본 슬래시는 **lifecycle 밖 전용**이다. 분업 기준 SoT: `commands/design-interface.md` §인터페이스 설계 경로 분업

## Step 1: 인터페이스 목록 자동 판단 + 승인 게이트

**목록 근거**:
1. **화면 Interactions** (1차): `screens/*.md` 의 `## Interactions` 스캔 → 필요 엔드포인트/테이블 도출
2. **requirements.md FR 표** (보완): 화면에 안 드러난 백엔드 FR(배치·웹훅 등)도 포함
3. **클라이언트 스토리지 앱**: 화면 영속화 Interaction(예: "저장 → localStorage") 이면 data-model 엔티티도 목록에 포함 (서버 없는 프론트)

목록 제시 → `[y/수정]` 승인 게이트. `y` 시 Step 2 진행.

## Step 2: 인터페이스별 순차 대화 루프

각 인터페이스에 대해 `/design-interface {name}` 의 Step 2~4(대화 → 마스터 append → 커밋)를 순차 수행한다 (커밋은 인터페이스별 또는 루프 종료 후 1회 일괄 — 재량). 채택 섹션 덮어쓰기 금지·별도 산출물 금지 규약 동일.

## Step 3: 설계 통합 뷰 갱신 (루프 끝 1회)

모든 인터페이스가 끝나면 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/design-overview.sh` 를 1회 실행해 출력된 경로를 사용자에게 알린다(단수의 Step 5 는 루프 안에서 건너뛴다). rc≠0(python3 없음·설계 문서 없음)이면 `통합 뷰 생성 못 함 — <사유>` 1줄만 알리고 진행한다(막지 않는다).

## 참조
- `commands/design-interface.md` — 단수(분업표 단일출처)
- `templates/api-spec.md`·`api-spec-consumer.md`·`data-model.md`

---

*specops-ko v2.6.0 · 2026-07-10 · 복수 인터페이스 일괄 설계 오케스트레이터*
