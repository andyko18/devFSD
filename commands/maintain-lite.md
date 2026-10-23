---
name: maintain-lite
disable-model-invocation: true
description: "[유지보수·경량] analyzing-mini + clarify·plan 생략 — 화면/IF·Phase B/C·verify·AC-R-1 유지"
triggers:
  - "/maintain-lite"
mode: ask
specops_version: 2.12.0
specops_layer: Lifecycle
reference_upstream: specops-ko 독자 추가 (commands/maintain.md § lite variant)
---

# /maintain-lite [<대상 또는 변경 설명>]

## 목적

`/maintain` 대비 **토큰 절감 유지보수 진입**. analyzing은 **mini**(대상 파일·호출자·회귀 요약), clarify·plan은 생략. **화면/IF(해당 시)·Phase B/C·verify·AC-R-1**은 유지.

## Process

0. **기본 동작과 `--step`** — 인자가 `--step` 으로 시작하면 그 낱말(과 뒤 공백)을 떼고 `<!-- step: true -->` 줄을 args 의 약속어 줄(`<!-- entry: … -->`) 바로 다음 줄에(아래 2 에서 약속어를 붙인 뒤) 넣는다(지금까지의 단계별 확인). 없으면 넣지 않는다 — 기본은 `§일괄`: 질문은 최대 2회 묶음, intent·설계·스펙·AC·화면·IF·답변을 한 번에 승인받고 PR 게이트까지 멈추지 않는다(비가역·보안 Critical/High·plan 리뷰 Critical·NEEDS_DISCUSSION 등은 그대로 멈춘다 — `skills/specifying-ko/once-approval.md`).

1. **메타 skill 활성 확인**
2. **analyzing-ko 호출** — args 첫 줄에 `<!-- entry: maintain-lite -->` prepend 후 원본 인자. analyzing-ko **[lite-mini 분기]**가 짧은 current-state + impact 요약 산출 + ★ HARD GATE
3. **사용자 검토 통과 후 specifying-ko** — 동일 args(약속어 유지). `[maintain-lite 분기]`: `§유형=유지보수` + `§lite=true` + AC-R-1 · 화면/IF 해당 시 동일
4. **이후 chain (lite)**: decomposing(1 task) → implementing(A + end-loaded B/C) → verifying → request/receive(end-loaded skip) → security → integration → performance → PR. clarifying·planning **호출 금지**.

## `/maintain` 대비

| 단계 | `/maintain` | `/maintain-lite` |
|---|---|---|
| analyzing | full ★ | **mini** ★ |
| clarifying / planning | ✅ | **skip** |
| 화면 5.5 / IF 5.6 | 조건부 ✅ | **동일 유지** |
| decompose | N | **1 task** |
| Phase B/C | ✅ | **필수 유지** |
| AC-R-1 (회귀) | ✅ | ✅ |

**strict 승격** (두 지점): ① 진입 직후 요청에 auth·migration·결제/PII·파괴적 스키마 등 strict 신호가 보이면 거부 후 `/maintain` 안내. ② 놓쳤어도 분해 단계의 `LITE-STRICT-GUARD`(`risk-profile.sh` rc=3)가 기계로 잡는다 — 그때는 제자리에서 clarify → plan 을 수행해 승격한다(분석은 mini 로 남는다 — 풀 영향 분석이 필요하면 `/maintain` 재진입). 설계 문서를 **인용만** 한 것(spec §참조)과 테스트가 자기 임시 디렉터리를 치우는 코드는 strict 신호가 아니다.

## 사용 예

```
/maintain-lite 주문 목록 정렬이 최신순이 아닌 버그

→ <!-- entry: maintain-lite -->
→ analyzing-ko mini ★ HARD GATE
→ specifying-ko (유지보수 + §lite, AC-R-1)
→ clarify/plan SKIP → 1 task → implement B/C → verify → …
```

## 안티패턴

- **자연어로 lite 추론 금지** — "가볍게 고쳐줘"로 maintain-lite 추론 금지. 슬래시만.
- **신규 기능을 `/maintain-lite`로 진입** — 재분류 요청 (`/start-lite` 또는 `/start`)
- **analyzing 완전 skip** — mini라도 baseline·회귀 요약은 필수 (AC-R-1 근거)
- **화면·IF·Phase B/C·verify 생략** — lite 불변식 위반
- **인자 없이 진입** — modally 되묻기
- **인자 내용 2차 판단** — analyzing 호출 보류 금지

## 참조

- `commands/maintain.md` — 풀 유지보수 진입
- `commands/start-lite.md` — 경량 신규 자매
- `skills/analyzing-ko/SKILL.md` — `[lite-mini 분기]`
- `skills/specifying-ko/SKILL.md` — `[maintain-lite 분기]`

---

*specops-ko v2.12.0 · 2026-08-04 · 경량 유지보수 Lifecycle 진입 (analyze-mini, clarify·plan skip)*
