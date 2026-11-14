---
name: maintain
disable-model-invocation: true
description: "[유지보수·대화형] devFSD 한국어 자율 Lifecycle 유지보수 진입 슬래시 — 위험 신호가 없거나 가벼우면 기본 경로(가벼운 신호는 그 안에서 계획·전문가 단계를 켠다), 무거우면 풀 경로(analyzing-ko 선행 → specifying-ko 유지보수 분기)를 자동으로 고른다 (`--full` = 무조건 풀)"
triggers:
  - "/maintain"
mode: ask
specops_version: 4.0.15
specops_layer: Lifecycle
reference_upstream: specops-ko 독자 추가 (본가 obra/superpowers@v5.0.7 미존재)
---

# /maintain [--full] [--step] [--no-split] [<대상 또는 변경 설명>]

## 목적

`/start` 와 동등한 진입 슬래시지만 maintenance flag 자동 세팅. 위험 신호가 없으면 기본 경로(유지보수 골격), 있으면 풀 경로 — analyzing-ko 선행 후 specifying-ko 유지보수 분기로 직행.

## Process

0-0. **갈래 고르기 (자동 분기)** — 인자 원문을 옵션째로 넘겨 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh route maintain "<인자 원문>"` 을 1회 실행하고(따옴표·백틱·`$` 는 빼고 넘긴다), `NOTICE:` 줄을 사용자에게 그대로 보인다(1줄).
   - `ROUTE: basic` (위험 신호 없음, 또는 가벼운 위험 신호 — 그때는 기본 경로 안에서 분석·계획·전문가 단계가 켜진다) → **기본 경로**. `PROCEDURE:` 줄의 파일(`commands/basic.md`)을 Read 해 그 Process 를 `REQUEST:` 줄의 요청으로 1번부터 따른다(1번 start 끝에 `maintain` 을 붙인다 — 분석 단계 대신 spec 1장의 「현재 동작과 영향」 절과 `AC-R-1` 이 회귀 위험을 받는다). 아래 단계는 하지 않는다.
   - `ROUTE: full` (무거운 위험 신호 — 데이터 삭제·이관 · 되돌릴 수 없는 외부 작업 · 결제·개인정보 · 파일 삭제·배포 · `--full` · `--step` · `.specops/` 없음 · 판정 불가) → **풀 경로**. `--full` 낱말을 인자에서 떼고 아래 0 부터 종전대로 한다.
   - 갈래는 스크립트의 답이다 — 요청이 가벼워/무거워 보인다는 이유로 모델이 바꾸지 않는다. 사용자가 뒤집는 방법은 `--full`(무조건 풀)과 `/basic`(기본 경로 직접 지정)이다. 기본 경로 진행 중 위험 신호가 나오면 풀 경로로 올라온다(`commands/basic.md` 「풀 경로로 올리기」).

0. **기본 동작과 `--step`** — 인자가 `--step` 으로 시작하면 그 낱말(과 뒤 공백)을 떼고 `<!-- step: true -->` 줄을 args 의 약속어 줄(`<!-- entry: … -->`) 바로 다음 줄에(아래 2 에서 약속어를 붙인 뒤) 넣는다(지금까지의 단계별 확인). 없으면 넣지 않는다 — 기본은 `§일괄`: 질문은 최대 2회 묶음, intent·설계·스펙·AC·화면·IF·답변을 한 번에 승인받고 PR 게이트까지 멈추지 않는다(비가역·보안 Critical/High·plan 리뷰 Critical·NEEDS_DISCUSSION 등은 그대로 멈춘다 — `skills/specifying-ko/once-approval.md`).

0-1. **`--no-split`** — 인자에 `--no-split` 이 있으면 그 낱말을 떼고 `<!-- split: false -->` 줄을 args 의 주석 줄들(`<!-- entry: … -->`·`<!-- step: true -->`) 뒤에 넣는다. 풀 경로는 기본으로 구현 구간(구현~성능 게이트)을 대화 맥락이 빈 자식 세션에서 돌리고 결과만 받아 PR 게이트로 간다(사용자 동작 없음 — `skills/decomposing-ko/session-split.md`). `--no-split` 은 그 분리를 끄고 종전처럼 이 세션에서 구현한다.

0-2. **대화 크기 고지 (차단 아님)** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/split-session.sh warn-size` 를 1회 실행한다. `CONTEXT-LARGE:` 줄이 나오면 그 줄을 사용자에게 그대로 보이고 **멈추지 않고** 진행한다(출력이 없으면 아무 말도 하지 않는다). 기준은 `.specops/config.yaml` 의 `session_split.warn_context_tokens`(기본 150000 · 0 이면 끔).

1. **메타 skill 활성 확인** — `skills/using-specops-ko/SKILL.md` 가 세션 시작 시 활성
2. **(풀 경로) analyzing-ko 호출** — args 첫 줄에 `<!-- entry: maintain -->` HTML 주석 prepend 후 원본 인자. analyzing-ko 가 current-state.md + impact-analysis.md 산출 + ★ HARD GATE
3. **사용자 검토 통과 후 specifying-ko 호출** — analyzing-ko 가 동일 args 로 chain (args 첫 줄 약속어 유지). specifying-ko Step 1 [유지보수 분기] 가 두 산출물 참조
4. **이후 chain** — 각 engine skill 본문의 `## 다음 skill` 섹션이 자동 강제: clarifying-ko → planning-ko → decomposing-ko → implementing-ko → verifying-evidence-ko → security-review-ko → integration-test-ko → performance-test-ko → PR. 본 command는 **진입만** 책임

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
| `/maintain X` | 명시적 유지보수 진입 — 갈래 고르기 → 기본 경로 또는 args 합성 직접 |
| `"X 고쳐줘"` (자연어) | 메타 skill 신호 매칭 → maintenance flag → 같은 갈래 고르기 → 기본 경로 또는 analyzing-ko 호출 시 args 합성 |

## 안티패턴

- **인자 내용 2 차 판단** — `/maintain <아무 인자>` 는 인자가 "유지보수 신호처럼 보이지 않는다"는 이유로 진입(갈래 고르기 → 기본 경로 또는 `devfsd:analyzing-ko` 호출)을 **보류하지 않는다**. 슬래시 진입 자체가 사용자 의도 확정 신호 (명시적 유지보수 진입). 인자 적합성은 specifying-ko Step 1 [유지보수 분기] 검증 문항이 처리. 메타 skill 의 자연어 신호 감지 로직을 command 레이어에 복제 금지 (`/start` 안티패턴 sister 항목과 의미적 동치)
- **신규 기능을 `/maintain` 으로 진입** — specifying-ko Step 1 분기 검증 문항이 사용자에게 재분류 요청
- **인자 없이 진입** — modally 되묻기 (`/start` 안티패턴 동일)

## 참조

- `commands/start.md` — 자매 진입로 (신규)
- `commands/basic.md` · `scripts/basic-path.sh` — 기본 경로와 갈래 판정(`route`)·승격(`promote`)
- `skills/specifying-ko/SKILL.md` Step 1 — maintenance 분기
- `skills/using-specops-ko/SKILL.md` — 메타 skill 신호 매칭

---

*specops-ko v2.6.0 · 2026-04-27 · 유지보수 진입 슬래시 (자연어 진입과 동등)*
