---
name: maintain
disable-model-invocation: true
description: "[유지보수·대화형] specops-ko 한국어 자율 Lifecycle 유지보수 진입 슬래시 — specifying-ko 유지보수 분기 호출 (Phase C 적용 후 analyzing-ko 선행)"
triggers:
  - "/maintain"
mode: ask
specops_version: 2.6.0
specops_layer: Lifecycle
reference_upstream: specops-ko 독자 추가 (본가 obra/superpowers@v5.0.7 미존재)
---

# /maintain [<대상 또는 변경 설명>]

## 목적

`/start` 와 동등한 진입 슬래시지만 maintenance flag 자동 세팅. analyzing-ko 선행 후 specifying-ko 유지보수 분기로 직행.

## Process

0. **기본 동작과 `--step`** — 인자가 `--step` 으로 시작하면 그 낱말(과 뒤 공백)을 떼고 `<!-- step: true -->` 줄을 args 의 약속어 줄(`<!-- entry: … -->`) 바로 다음 줄에(아래 2 에서 약속어를 붙인 뒤) 넣는다(지금까지의 단계별 확인). 없으면 넣지 않는다 — 기본은 `§일괄`: 질문은 최대 2회 묶음, intent·설계·스펙·AC·화면·IF·답변을 한 번에 승인받고 PR 게이트까지 멈추지 않는다(비가역·보안 Critical/High·plan 리뷰 Critical·NEEDS_DISCUSSION 등은 그대로 멈춘다 — `skills/specifying-ko/once-approval.md`).

1. **메타 skill 활성 확인** — `skills/using-specops-ko/SKILL.md` 가 세션 시작 시 활성
2. **analyzing-ko 호출** — args 첫 줄에 `<!-- entry: maintain -->` HTML 주석 prepend 후 원본 인자. analyzing-ko 가 current-state.md + impact-analysis.md 산출 + ★ HARD GATE
3. **사용자 검토 통과 후 specifying-ko 호출** — analyzing-ko 가 동일 args 로 chain (args 첫 줄 약속어 유지). specifying-ko Step 1 [유지보수 분기] 가 두 산출물 참조
4. **이후 chain** — 각 engine skill 본문의 `## 다음 skill` 섹션이 자동 강제: clarifying-ko → planning-ko → decomposing-ko → implementing-ko → verifying-evidence-ko → requesting-code-review-ko → receiving-code-review-ko → security-review-ko → integration-test-ko → performance-test-ko → PR. 본 command는 **진입만** 책임

## 사용 예

```
/maintain auth.js 토큰 만료 버그

→ args 합성: "<!-- entry: maintain -->\nauth.js 토큰 만료 버그"
→ analyzing-ko (current-state.md + impact-analysis.md) ★ HARD GATE
→ 사용자 검토 통과 → specifying-ko Step 1 [유지보수 분기] (두 산출물 참조)
→ spec.md §유형 = 유지보수 + acceptance-criteria.md AC-R-1 강제
   (DB 스키마 변경이면 analyzing trivial override + AC-R-2 데이터 보존 강제)
→ ... (Lifecycle 자동)
```

## 자연어 진입 vs 슬래시 진입

| 진입 방식 | 동작 |
|---|---|
| `/maintain X` | 명시적 유지보수 진입 — args 합성 직접 |
| `"X 고쳐줘"` (자연어) | 메타 skill 신호 매칭 → maintenance flag → specifying-ko 호출 시 args 합성 |

## 안티패턴

- **인자 내용 2 차 판단** — `/maintain <아무 인자>` 는 인자가 "유지보수 신호처럼 보이지 않는다"는 이유로 `specops-ko:analyzing-ko` 호출을 **보류하지 않는다**. 슬래시 진입 자체가 사용자 의도 확정 신호 (명시적 유지보수 진입). 인자 적합성은 specifying-ko Step 1 [유지보수 분기] 검증 문항이 처리. 메타 skill 의 자연어 신호 감지 로직을 command 레이어에 복제 금지 (`/start` 안티패턴 sister 항목과 의미적 동치)
- **신규 기능을 `/maintain` 으로 진입** — specifying-ko Step 1 분기 검증 문항이 사용자에게 재분류 요청
- **인자 없이 진입** — modally 되묻기 (`/start` 안티패턴 동일)

## 참조

- `commands/start.md` — 자매 진입로 (신규)
- `skills/specifying-ko/SKILL.md` Step 1 — maintenance 분기
- `skills/using-specops-ko/SKILL.md` — 메타 skill 신호 매칭

---

*specops-ko v2.6.0 · 2026-04-27 · 유지보수 진입 슬래시 (자연어 진입과 동등)*
