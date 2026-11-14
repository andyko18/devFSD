---
name: start
disable-model-invocation: true
description: "[단일·대화형] devFSD 한국어 자율 Lifecycle 단일 기능 진입 슬래시 — 위험 신호가 없거나 가벼우면 기본 경로(가벼운 신호는 그 안에서 계획·전문가 단계를 켠다), 무거우면 풀 경로(devfsd:specifying-ko)를 자동으로 고른다 (`--full` = 무조건 풀)"
triggers:
  - "/start"
mode: ask
specops_version: 2.6.0
specops_layer: Lifecycle
reference_upstream: obra/superpowers@v5.0.7 commands/brainstorm.md
---

# /start [--full] [--step] [--no-split] [<기능 설명>]

## 목적

specops-ko 한국어 자율 Lifecycle의 **단일 진입 슬래시**. 자연어 진입(`"X 기능을 만들고 싶어"`)과 **동등한 진입점**이며, 사용자가 명시적으로 Lifecycle을 시작하고 싶을 때 사용.

## Process

0-0. **갈래 고르기 (자동 분기)** — 인자 원문을 옵션째로 넘겨 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh route start "<인자 원문>"` 을 1회 실행하고(따옴표·백틱·`$` 는 빼고 넘긴다), `NOTICE:` 줄을 사용자에게 그대로 보인다(1줄).
   - `ROUTE: basic` (위험 신호 없음, 또는 가벼운 위험 신호 — 그때는 기본 경로 안에서 분석·계획·전문가 단계가 켜진다) → **기본 경로**. `PROCEDURE:` 줄의 파일(`commands/basic.md`)을 Read 해 그 Process 를 `REQUEST:` 줄의 요청으로 1번부터 따른다. 아래 단계는 하지 않는다.
   - `ROUTE: full` (무거운 위험 신호 — 데이터 삭제·이관 · 되돌릴 수 없는 외부 작업 · 결제·개인정보 · 파일 삭제·배포 · `--full` · `--step` · `.specops/` 없음 · 판정 불가) → **풀 경로**. `--full` 낱말을 인자에서 떼고 아래 0 부터 종전대로 한다.
   - 갈래는 스크립트의 답이다 — 요청이 가벼워/무거워 보인다는 이유로 모델이 바꾸지 않는다. 사용자가 뒤집는 방법은 `--full`(무조건 풀)과 `/basic`(기본 경로 직접 지정)이다. 기본 경로 진행 중 위험 신호가 나오면 풀 경로로 올라온다(`commands/basic.md` 「풀 경로로 올리기」).

0. **기본 동작과 `--step`** — 인자가 `--step` 으로 시작하면 그 낱말(과 뒤 공백)을 떼고 `<!-- step: true -->` 줄을 args 맨 앞에 넣는다(지금까지의 단계별 확인). 없으면 넣지 않는다 — 기본은 `§일괄`: 질문은 최대 2회 묶음, intent·설계·스펙·AC·화면·IF·답변을 한 번에 승인받고 PR 게이트까지 멈추지 않는다(비가역·보안 Critical/High·plan 리뷰 Critical·NEEDS_DISCUSSION 등은 그대로 멈춘다 — `skills/specifying-ko/once-approval.md`).

0-1. **`--no-split`** — 인자에 `--no-split` 이 있으면 그 낱말을 떼고 `<!-- split: false -->` 줄을 args 의 주석 줄들(`<!-- entry: … -->`·`<!-- step: true -->`) 뒤에 넣는다. 풀 경로는 기본으로 구현 구간(구현~성능 게이트)을 대화 맥락이 빈 자식 세션에서 돌리고 결과만 받아 PR 게이트로 간다(사용자 동작 없음 — `skills/decomposing-ko/session-split.md`). `--no-split` 은 그 분리를 끄고 종전처럼 이 세션에서 구현한다.

0-2. **대화 크기 고지 (차단 아님)** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/split-session.sh warn-size` 를 1회 실행한다. `CONTEXT-LARGE:` 줄이 나오면 그 줄을 사용자에게 그대로 보이고 **멈추지 않고** 진행한다(출력이 없으면 아무 말도 하지 않는다). 기준은 `.specops/config.yaml` 의 `session_split.warn_context_tokens`(기본 150000 · 0 이면 끔).

1. **메타 skill 활성 확인** — `skills/using-specops-ko/SKILL.md`가 세션 시작 시 이미 활성돼 있어야 함. 아니면 수동으로 `Skill` 도구 호출
2. **(풀 경로) 즉시 `devfsd:specifying-ko` 스킬 호출** — 전달된 `<기능 설명>`을 초기 맥락으로 제공
3. **이후 chain** — 각 engine skill 본문의 `## 다음 skill` 섹션이 자동 강제 (specifying-ko → clarifying-ko → planning-ko → decomposing-ko → implementing-ko → verifying-evidence-ko → security-review-ko → integration-test-ko → performance-test-ko → PR). 본 command는 **specifying-ko 진입만** 책임.
   - **implementing 기본**: `review_mode: end-loaded` — 태스크별 구현(A) 후 FID 단위 스펙·코드 리뷰(B·C) 각 1회. requesting은 end-loaded B/C 산출이 있으면 `review-skip.md`로 중복 리뷰 skip.
   - **specifying 내부 design-first**: UI 기능이면 **Step 5.5**(화면 — `screens/{name}.md`+`.html`), API 엔드포인트·DB 스키마·**클라이언트 영속** 데이터를 신설·변경하면 **Step 5.6**(인터페이스 — `.specops/memory/api-spec.md`·`data-model.md`)이 설계 승인 직후 자동 실행된다. **해당 없으면 skip** — `/design-screen(s)`·`/design-interface(s)` 를 따로 부를 필요 없다.

## 사용 예

```
/start CSV 줄 수 세기 CLI 만들어줘

→ 메타 skill 활성 확인
→ devfsd:specifying-ko 호출
→ specifying-ko가 프로젝트 맥락 탐색 + 명확화 질문 시작
→ HARD GATE (설계 승인)
→ 사용자 y → devfsd:clarifying-ko 자동 호출
→ ... (Lifecycle 자동 진행)
```

## 자연어 진입 vs 슬래시 진입

| 진입 방식 | 동작 | 비고 |
|---|---|---|
| `/start CSV 줄 수 세기 CLI` | 본 command 실행 — 갈래 고르기 → 기본 경로 또는 `devfsd:specifying-ko` | 명시적 진입 |
| `"CSV 줄 수 세기 CLI 만들어줘"` (자연어) | 메타 skill이 신호 감지 → 같은 갈래 고르기 → 기본 경로 또는 `devfsd:specifying-ko` | 암묵적 진입 (SessionStart 메타 skill) |

두 방식은 **기능적으로 동등**. `/start` 슬래시는 명시적 진입점이고, 자연어는 메타 skill이 같은 갈래 판정(`basic-path.sh route`)을 거쳐 연결한다. `--full`·`--step`·`--no-split` 은 슬래시로만 준다.

## 안티패턴

- **인자 없이 진입** — `/start`만 치면 어떤 기능을 만들지 사용자에게 되물음 (modally). `/start <기능 설명>` 권장
- **인자 내용 2차 판단** — `/start <아무 인자>` 는 인자가 "기능 설명 신호처럼 보이지 않는다"는 이유로 진입(갈래 고르기 → 기본 경로 또는 `devfsd:specifying-ko` 호출)을 **보류하지 않는다**. 슬래시 진입 자체가 사용자 의도 확정 신호 (명시적 진입). 인자 적합성은 specifying-ko 가 HARD GATE 로 처리. 메타 skill 의 자연어 신호 감지 로직을 command 레이어에 복제 금지
- **구현 직진 요구** — `/start "그냥 바로 만들어"` 같은 명시 우회도 specifying-ko가 HARD GATE로 **거절**. 5원칙 4 주권 + 안티패턴 "너무 간단해서 설계 불필요" 적용
- **specifying-ko 생략** — 풀 경로에서 /start 이후 planning-ko·implementing-ko를 직접 호출해도 chain 무결성 **깨짐**. 반드시 specifying-ko부터

## 참조

- `skills/using-specops-ko/SKILL.md` — 메타 skill (자동 활성)
- `commands/basic.md` · `scripts/basic-path.sh` — 기본 경로와 갈래 판정(`route`)·승격(`promote`)
- `skills/specifying-ko/SKILL.md` — 풀 경로의 첫 Lifecycle 단계
- `skills/structured-artifacts-ko/SKILL.md` — `.specops/<FID>/` 경로 규약
- 설계 근거: specops-ko 설계 케이스 스터디 `2026-04-21-specops-auto-ko-design.md §15.5` (진입 흐름)
- 참조: affaan-m/everything-claude-code@1.2.0 commands/orchestrate.md

---

*specops-ko v2.6.0 · 2026-04-21 · 단일 진입 슬래시 (자연어 진입과 동등)*
