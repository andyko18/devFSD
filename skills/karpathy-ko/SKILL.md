---
name: karpathy-ko
description: 코드 작성·검토·리팩터링 시 항상 적용 — Think·Simplicity·Surgical·Goal 4원칙으로 LLM 코딩 실수 방지 (Karpathy 관찰 한국어 재창작)
layer: 2
reference_upstream: forrestchang/andrej-karpathy-skills@main skills/karpathy-guidelines/SKILL.md
specops_version: 1.0.0
used_by: using-specops-ko (cross-cutting), implementing-ko, tdd-ko
---

# Karpathy 행동 원칙

Andrej Karpathy의 LLM 코딩 함정 관찰에서 파생된 4가지 행동 지침.  
specops-ko의 5원칙(투명성·문지기·주권·한계 고백)과 직교하여 상호 강화한다.

**트레이드오프:** 이 원칙들은 속도보다 신중함에 치우친다. 자명한 작업은 판단하여 적용할 것.

---

## 원칙 1 — 코드 작성 전 사고 (Think Before Coding)

**가정하지 말 것. 혼란을 숨기지 말 것. 트레이드오프를 드러낼 것.**

구현 전:
- 가정을 명시적으로 서술한다. 불확실하면 묻는다.
- 여러 해석이 가능하다면 모두 제시한다 — 조용히 하나를 고르지 않는다.
- 더 단순한 접근이 있다면 말한다. 타당하다면 반론을 제기한다.
- 무언가 불명확하면 멈춘다. 무엇이 혼란스러운지 이름 붙이고 묻는다.

**specops-ko 연결:** 원칙 1 투명성 + 원칙 5 한계 고백

---

## 원칙 2 — 단순성 우선 (Simplicity First)

**문제를 해결하는 최소한의 코드. 추측성 코드 금지.**

- 요청받은 것 이상의 기능 추가 금지.
- 단일 사용 코드에 추상화 금지.
- 요청하지 않은 "유연성" 또는 "설정 가능성" 금지.
- 발생 불가능한 시나리오에 대한 에러 핸들링 금지.
- 200줄로 작성했는데 50줄로 가능하다면 다시 작성한다.

자문: "고급 엔지니어가 이것을 과도하게 복잡하다고 말할까?" → 그렇다면 단순화한다.

**specops-ko 연결:** spec.md YAGNI 제약, 원칙 4 주권 (요청 범위 준수)

---

## 원칙 3 — 외과적 변경 (Surgical Changes)

**반드시 건드려야 하는 것만 수정한다. 자신의 흔적만 정리한다.**

기존 코드 편집 시:
- 인접한 코드·주석·포맷을 "개선"하지 않는다.
- 망가지지 않은 것을 리팩터링하지 않는다.
- 자신의 방식과 달라도 기존 스타일을 따른다.
- 관련 없는 데드 코드를 발견하면 언급한다 — 삭제하지 않는다.

자신의 변경이 고아를 만든 경우:
- **자신의 변경**으로 불필요해진 import·변수·함수만 제거한다.
- 기존에 있던 데드 코드는 요청받지 않는 한 건드리지 않는다.

**판정 기준:** 변경된 모든 줄이 사용자의 요청과 직접 연결되어야 한다.

**specops-ko 연결:** verifying-evidence-ko 범위 제어, 「스프린트 계약」 (AC 범위 외 변경 금지)

---

## 원칙 4 — 목표 기반 실행 (Goal-Driven Execution)

**성공 기준을 정의한다. 검증될 때까지 반복한다.**

작업을 검증 가능한 목표로 변환:
- "유효성 검사 추가" → "잘못된 입력에 대한 테스트 작성 후 통과시키기"
- "버그 수정" → "버그를 재현하는 테스트 작성 후 통과시키기"
- "X 리팩터링" → "전후 테스트 통과 보장"

다단계 작업 시 간략한 계획을 명시:
```
1. [단계] → 검증: [확인 방법]
2. [단계] → 검증: [확인 방법]
3. [단계] → 검증: [확인 방법]
```

강한 성공 기준은 독립적인 반복을 가능하게 한다.  
약한 기준("작동하게 만들기")은 지속적인 명확화를 요구한다.

**specops-ko 연결:** acceptance-criteria.md 스프린트 계약, tdd-ko Red-Green-Refactor 사이클

---

## 5원칙 매핑 요약

| Karpathy 원칙 | specops-ko 연결 |
|---|---|
| 1 코드 작성 전 사고 | 원칙 1 투명성 + 원칙 5 한계 고백 |
| 2 단순성 우선 | YAGNI + 원칙 4 주권 |
| 3 외과적 변경 | 「스프린트 계약」 AC 범위 |
| 4 목표 기반 실행 | acceptance-criteria.md + tdd-ko |

---

## 참조

- `forrestchang/andrej-karpathy-skills skills/karpathy-guidelines/SKILL.md` — 원본 (MIT)
- `skills/tdd-ko/SKILL.md` — 원칙 4와 TDD 연결
- `skills/verifying-evidence-ko/SKILL.md` — 원칙 3·4 검증 단계
- `docs/harness-principles.md` 「스프린트 계약」 — 원칙 3 범위 계약

---

*v1.0.0 · 2026-05-03 · Karpathy Guidelines 한국어 재창작 + specops-ko 5원칙 매핑*
