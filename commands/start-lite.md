---
name: start-lite
disable-model-invocation: true
description: "[단일·별칭] `/start` 의 별칭 — 다음 메이저에서 제거. `/start` 가 무거운 위험 신호가 없으면 기본 경로를 자동으로 고른다"
triggers:
  - "/start-lite"
mode: ask
specops_version: 3.1.36
specops_layer: Lifecycle
reference_upstream: specops-ko 독자 추가 (commands/start.md 의 별칭)
---

# /start-lite [<기능 설명>]

## 목적

**`/start` 의 별칭이다 — 다음 메이저에서 제거한다.** 가벼운 경로를 사용자가 고를 필요가 없어졌다: `/start` 가 위험 신호를 스크립트로 판정해 신호가 없으면 기본 경로(spec 1장 → 주 세션 직접 구현 → 리뷰 1회 → 검증 1회 → PR)를, 있으면 풀 경로를 고른다. 종전의 lite 절차(clarify·plan 만 생략하고 구현자 dispatch 는 유지 — 20261112 실측 53분)는 이 명령으로 더 이상 돌지 않는다.

## Process

1. **고지 1줄** — "`/start-lite` 는 다음 메이저에서 제거됩니다 — `/start` 가 자동으로 고릅니다." 를 먼저 보인다.
2. **갈래 고르기** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh route start "<인자 원문>"` 을 1회 실행하고(따옴표·백틱·`$` 는 빼고 넘긴다) `NOTICE:` 줄을 그대로 보인다.
   - `ROUTE: basic` → `PROCEDURE:` 줄의 파일(`commands/basic.md`)을 Read 해 그 Process 를 `REQUEST:` 줄의 요청으로 1번부터 따른다.
   - `ROUTE: full` → `ENTRY:` 줄의 파일(`commands/start.md`)을 Read 해 그 Process 를 0 부터 따른다(0-0 갈래 고르기는 방금 했다).

`/start <같은 인자>` 와 결과가 같다. 옵션(`--full`·`--step`·`--no-split`)도 `/start` 와 같게 받는다.

## 안티패턴

- **종전 lite 절차로 진행** — `<!-- entry: lite -->` 약속어를 붙여 `specifying-ko` 를 부르지 않는다. 이 명령은 그 분기로 들어가지 않는다.
- **자연어로 이 명령을 추론** — 자연어 진입은 메타 skill 이 `/start` 와 같은 갈래 판정을 거친다. 별칭을 고를 일이 없다.

## 참조

- `commands/start.md` — 본 명령 · `commands/maintain-lite.md` — 자매 별칭
- `commands/basic.md` · `scripts/basic-path.sh` — 기본 경로와 갈래 판정(`route`)

---

*specops-ko v3.1.36 · 2026-11-12 · `/start` 의 별칭 (다음 메이저에서 제거)*
