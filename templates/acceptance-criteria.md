<!-- FID: <YYYYMMDD-kebab-slug> -->
<!-- OWNER_COMMAND: /specify -->
<!-- MUTABLE_BY: /clarify (append only) -->
<!-- reference_upstream: github/spec-kit + sprint-contracts Given/When/Then -->
<!-- layer: Lifecycle-Artifact -->

# 수락 기준 (Acceptance Criteria) — <FID>

> 이 파일은 **스프린트 계약서**입니다. 명세 단계(`specifying-ko`)가 생성하고 명확화 단계(`clarifying-ko`)가 append 수정하며, 이후 단계는 **읽기 전용**입니다. Evaluator(`spec-reviewer-ko`·`code-reviewer-ko`·`plan-reviewer-ko`)는 이 계약만을 판정 기준으로 삼습니다.

## 계약 항목

각 AC는 Given/When/Then 형식으로 **관찰 가능한 결과**를 기술합니다. 구현 세부사항은 포함하지 않습니다.

> **판정 SoT = `scripts/_internal/check-ac-format.sh`** (20260807 기계화 — `emit-context.sh` 가 구현 직전 자동 호출).
> AC 블록마다 **Given·When·Then·우선순위** 는 **필수**다. 특히 `**우선순위**` 를 빠뜨리면
> `emit-context.sh` 의 **must AC 역방향 커버리지** 검사가 그 AC 를 보지 못한다 —
> 필수 AC 가 어느 태스크에도 매핑되지 않은 채 구현이 진행되고, 그 기능은 영영 구현되지 않는다.
> `**검증 방법**`·`**관련 FR**` 은 현재 WARN (전환 예정 — 관련 FR 은 대조 SoT 확정 후 hard).

### AC-1: <기능 이름>

**Given** <전제 조건·초기 상태>

**When** <사용자/시스템 동작>

**Then** <관찰 가능한 결과>

**검증 방법**: <수동 재현 단계 또는 자동 테스트 경로>
**관련 FR**: FR-1
**우선순위**: must

---

### AC-2: <기능 이름>

**Given** ...

**When** ...

**Then** ...

**검증 방법**: ...
**관련 FR**: FR-2
**우선순위**: must

---

### AC-3: <기능 이름>

**Given** ...

**When** ...

**Then** ...

**검증 방법**: ...
**관련 FR**: FR-3
**우선순위**: should

---

## 회귀 방지 AC (유지보수 FID 필수)

`spec.md §개요` 의 `**§유형**` 라벨이 `유지보수` 인 경우, 본 섹션에 `AC-R-N` 회귀 must AC 를 **최소 1 개 이상** 작성한다. 「스프린트 계약」(docs/harness-principles.md) `scripts/_internal/check-regression-ac.sh` 가 회귀 AC 누락을 막는다(구현 직전 `emit-context.sh` 가 호출).

> **판정 SoT = `scripts/_internal/check-regression-ac.sh`** (20260806 기계화 — `emit-context.sh` 가 구현 직전 자동 호출). 유지보수인데 AC-R-1 이 없거나 아래 대괄호 placeholder 를 그대로 두면 dispatch 가 열리지 않는다. 스키마 override(current-state.md §1 마커) 시 AC-R-2 는 §유형 무관 강제.

### AC-R-1: 기존 동작 보존

**Given** [구체적 입력 또는 기존 호출 패턴]
**When** [현재와 동일한 트리거]
**Then** 기존 출력 [구체적 결과] 와 동일하게 동작한다 — 변경되지 않음

**검증 방법**: [기존 회귀 테스트 경로 또는 신규 회귀 테스트 추가]
**관련 FR**: 회귀 방지
**우선순위**: must

### AC-R-2: 데이터 보존·역가역성 (DB 스키마 변경 시 필수)

> **활성 조건**: `impact-analysis.md §1` 의 `DB 스키마` 가 변경 있음(특히 파괴적 `ALTER`/`DROP`)이거나 analyzing-ko trivial **스키마 override** 발동 시 — 본 AC 를 작성한다. 스키마 무변경이면 생략.

**Given** [마이그레이션 적용 전 데이터 상태 / 대상 테이블·컬럼]
**When** 마이그레이션 forward(up) 적용 후 reverse(down) 적용
**Then** ① up→down→up **멱등**(스키마 동일 복원) ② 기존 데이터가 손실 없이 보존(또는 파괴적이면 backup/expand-contract 로 복구 경로 확보) ③ 제약(NOT NULL/CHECK/UNIQUE) 위반 0

**검증 방법**: [마이그레이션 테스트 — up/down 왕복 + 데이터 보존 단언]
**관련 FR**: 데이터 안전
**우선순위**: must

> **§유형 = 신규 / trivial 인 경우 본 섹션(AC-R-1) 면제** — `**§유형**: 신규` 또는 `**§유형**: trivial` (변경 라인 ≤ 5 자동) 이면 회귀 AC 강제 발동 안 함. 단 신규 chain 무손상은 별도 AC 로 보장 권장. **예외**: trivial 이어도 analyzing-ko **스키마 override**(파괴적 DB 변경)가 발동하면 AC-R-2 는 강제(데이터 안전은 라인수에 면제되지 않음).

---

## 우선순위 규약

- **must**: 이 항목이 충족되지 않으면 `/verify` PASS 불가
- **should**: 가능하면 충족. 미충족 시 스펙 리뷰어가 보고서에 적고 부모가 `dev-decision.sh … backlog` 로 남긴다(PR 본문 "넘긴 것"). 판정(PASS)은 막지 않는다
- **nice-to-have**: 여유가 있으면 반영. 미충족 시 BLOCK 없음

## 참조

- `docs/harness-principles.md` 「스프린트 계약」 — 계약서 운용 규약
- `templates/session-progress.md` — 진행 기록 포맷

---

*작성: <작성자> · <날짜> · FID: <FID> · 생성 커맨드: /specify*
