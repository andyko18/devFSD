---
name: start-all-auto
disable-model-invocation: true
description: "[전체·무인] specops-ko 한국어 자율 Lifecycle — requirements.md FR 표 전체 기능 무인(가역 게이트 자동통과) 일괄 구현. /start-all 무인 변형, batch PR 직전 1회만 확인"
triggers:
  - "/start-all-auto"
mode: ask
specops_version: 2.18.0
specops_layer: Lifecycle
reference_upstream: specops-ko 독자 추가 (start-all 무인 변형)
---

# /start-all-auto [<기능 설명>]

## 목적

`/start-all` 의 **무인 변형**. 한 번 진입하면 `requirements.md` FR 표 전체를 spec→clarify→plan→decompose→implement→verify→review→security→integration→performance 까지 **가역 게이트 자동 통과**, batch PR 직전 가정 다이제스트와 함께 1회만 확인.

**가역 게이트는 자동 통과, 비가역 행동(batch PR 생성, 파괴적/덮어쓰기 task, security Critical/High)에서만 정지.**

## Process

Phase 0~3 오케스트레이션(batch-id 결정·`requirements.md` 탐색·FR 파싱·`check-fr-table` / `check-fr-table.sh --classify` 시드·`foundation-scope` SKIP·`check-foundation-present.sh`·`check-foundation-merged.sh`·`init-batch-queue.sh`·`feat/<BATCH_ID>`·`queue.md`)은 **`commands/start-all.md` 와 동일**(시드/`foundation-scope` SKIP·eligible=0·foundation-present HARD·foundation-merged HARD·queue 기계 초기화 포함). Phase 2.5-A `check-foundation-shell-baseline` snapshot→verify(§auto HARD)·`foundation-shell` 불변 · Phase 2.5-B `check-foundation-if-baseline` snapshot→verify(§auto HARD)·`foundation-baseline` 불변도 **동일**. 아래는 §auto 무인 차이점만 명시한다.

1. **메타 skill 활성 확인** — `skills/using-specops-ko/SKILL.md` 가 세션 시작 시 이미 활성돼 있어야 함.
2. **인자 선택적** — 인자 없이 `requirements.md` FR 표 전체를 무인 순회한다(`/start-all` 미러). 인자를 주면 추가 맥락으로만 사용. (빈 인자 되물음 없음.)
3. **Phase 1 각 FR specifying 호출 args 3줄 prepend** — 각 FR 의 specifying-ko 호출 시 args 앞에 자동 주입:
   ```
   <!-- entry: batch -->
   <!-- batch-id: <BATCH_ID> -->
   <!-- auto: true -->
   <FR 원문>
   ```
   - `entry: batch` → specifying-ko batch 분기 (git-branch-create skip, Step 5.5·5.6 SKIP, `**§batch**` 라벨). 화면·인터페이스는 Phase 2.5 통합(화면→IF).
   - `auto: true` (셋째 줄) → specifying-ko batch 분기가 **추가 감지** → spec.md §1 에 `**§auto**: true` 동시 기재
   - 결과: 각 spec.md §1 = `**§유형**` + `**§batch**: <id>` + `**§auto**: true` → 다운스트림 6개 skill 무변경으로 §auto 자동통과 전파
4. **Phase 1 무인** — 각 FR clarify BLOCKING 모호점은 spec.md `**§auto**: true` 라벨 기반으로 best-guess 자동응답 + `status: ASSUMED` 기록(clarifying-ko §auto 분기). **단** `.specops/memory/decisions.md` 확정 주제는 ASSUMED 재질문도 금지(원장 우선). 사용자 정지 없음.
5. **Phase 2** — 전 PLAN_DONE 후 **batch plan-reviewer 1회** → `batch-plan-digest.sh` → 일괄 리뷰 게이트 자동 통과 → Phase 2.5 (Critical plan-review cap은 정지).
5b. **Phase 3 의 FR 보류** — implementing-ko 가 `BATCH-FR-HELD: <FID>` 를 내면(비가역 작업의 승인 요청·리뷰어의 판단 요청) 그 FR 만 `HELD` 로 두고 나머지를 계속한다. 무인이라도 대신 승인하지 않는다 — Phase 3 완료의 batch-state 스캔이 미완으로 세어 그 자리에서 정지하고 사용자 답을 기다린다(`commands/start-all.md` Phase 3 스텝 1b). 위 표의 "파괴적/덮어쓰기 task" 정지와 같은 종류의 멈춤이다: batch 에서는 그 자리에서 물을 수 없어 FR 단위로 미뤄 두었다가 여기서 한꺼번에 묻는다.
6. **batch PR 게이트 = 가정 다이제스트** — batch PR 직전 **집계기로** 수집·제시한다:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/collect-assumptions.sh ".specops/$BATCH_ID"
   ```
   > **수기 집계 금지 (20260806)**: 이 다이제스트는 무인 진행에서 **사용자가 자동 확정 항목을 보는 유일한 지점**이다(나머지 확인은 전부 자동 통과). 집계가 모델 재량이면 누락 시 사용자는 무엇이 자기 대신 결정됐는지 모른 채 PR 을 승인한다 — 무인 모드를 수용 가능하게 만드는 단 하나의 게이트가 내용을 잃는다(5원칙 4 주권). 집계기는 IMPL_DONE FID 전체를 훑어 과소보고를 구조적으로 차단하고, **0건도 명시 보고**한다("0건"과 "집계 안 함"은 다르다).
   집계기 출력에 더해 아래 항목을 확인한다:
   - 전 FID `clarifications.md` 의 `status: ASSUMED` 항목 (FID별 그룹)
   - 전 FID `handoffs/*.md` Decided 필드 집계
   - 전 FID spec.md "자동 결정 화면" 목록
   - 전 FID spec.md "자동 결정 인터페이스" 목록 (Phase 2.5-B — 엔드포인트/테이블)
   - `.specops/<BATCH_ID>/design-review.md` 판정 요약 (`DESIGN-REVIEW-RESULT` · Critical 정지 / Important-only cap 자동통과 여부)
   - 제시 후: **"위 가정 위에 N개 FR 구현됨. batch PR 생성? [y/n]"** — 단일 [y/n] 확인.

## §auto 모드 동작 (batch)

| 단계 | start-all-auto 동작 | 정지? |
|---|---|---|
| intent | Step 1.5 가 FR 행에서 도출 · 추정 항목 `(ASSUMED)` · PR 게이트 다이제스트로 집계 | ❌ |
| Phase 1 각 FR clarify BLOCKING | best-guess 자동응답 + `status: ASSUMED` (clarify §auto 분기, spec 라벨 기반) | ❌ |
| Phase 2 batch plan-review | 전 PLAN_DONE 후 **1회** (Phase 1 DEFER 해소). FAIL Critical → 정지 | 🛑 Critical |
| Phase 2 일괄 리뷰 게이트 | digest 후 **자동 통과** → Phase 2.5 직행 | ❌ |
| Phase 2.5-A 화면 마스터 대조 | `list` 합류 · `sync` 갱신 · `diff` 잔여는 **PR 다이제스트로 집계**. 전 모드 rc=0 이라 **정지 없음** | ❌ |
| Phase 2.5-A→B→C | 화면·IF 대화형 승인 **없이** 자동 반영. 표면 없으면 해당 축만 SKIP. **A는 foundation-shell 불변** · **B는 foundation-baseline 마커 불변**(snapshot→verify HARD, §auto 동일) | ❌ / 🛑 baseline |
| Phase 2.5-D `design-reviewer-ko` | 화면 또는 IF 산출 시 **항상** dispatch. FAIL 1회 수정 재시도. **Critical≥1 cap → 정지**(§auto 자동통과 금지). Important-only cap → 자동통과+기록(가역) | 🛑 Critical / ⚠️ Important |
| Phase 2.5-E 설계 승인 | D PASS/Important-only cap 후 **자동 통과** · Critical cap이면 미도달 · 다이제스트 집계 | ❌ |
| Phase 3 implement/verify cap 초과 | systematic-debugging → 1회 재시도 → 재실패 시 정지 | ⚠️ |
| Phase 3 파괴적/덮어쓰기 task | mini HARD GATE 정지 (§auto 우회 불가) | 🛑 |
| security-review-ko Critical/High | **차단 보존** — §auto여도 자동통과 금지 (systematic-debugging 후 재실행) | 🛑 |
| batch PR 게이트 | 가정 다이제스트(전 FR ASSUMED 집계) 제시 + [y/n] 1회 | 🛑 |

## 안티패턴

| 합리화 | 거절 사유 |
|---|---|
| "자연어로 무인 추론 진행" | 진입은 슬래시(`/start-all-auto`)로만 — 메타 skill 신호 감지와 구분 |
| "FR마다 개별 PR 생성" | batch PR 1회 원칙 위반 — 전 FR 일괄 PR |
| "security Critical/High 도 §auto니 자동통과" | 비가역 불변식 위반 — 무인이어도 차단 보존 |
| "빈 인자니 기능 설명 되물음" | `/start-all` 미러 — requirements.md FR 표 전체 순회 (AC-9) |
| "리프 구현자가 중간에 사용자에게 되물어도 된다" | 각 태스크 dispatch-context `## 7. 실행 모드`(`batch`)가 "사용자와 직접 대화 불가·질문은 시작 시 한 번에·의존 없는 나머지는 끝까지·비가역은 먼저 NEEDS_APPROVAL"을 싣는다(`emit-context.sh`) |

## 참조

- `commands/start-all.md` — Phase 0~3 batch 오케스트레이션 본문 (동일 참조)
- `skills/specifying-ko/SKILL.md` — batch+auto 라벨 동시기재 분기
- `skills/clarifying-ko/SKILL.md` L20 — §auto best-guess 분기(spec 라벨 grep)

---

*specops-ko v2.18.0 · 2026-10-09 · 무인 배치 오케스트레이터 (requirements.md FR 전체 가역 게이트 자동통과, 비가역 정지 · FR 보류는 대신 승인하지 않는다)*
