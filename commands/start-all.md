---
name: start-all
disable-model-invocation: true
description: "[전체·대화형] specops-ko 한국어 자율 Lifecycle — requirements.md FR 표 전체 기능 일괄 구현. 3-Phase 오케스트레이터"
triggers:
  - "/start-all"
mode: ask
specops_version: 2.18.0
specops_layer: Lifecycle
reference_upstream: specops-ko 독자 추가
---

# /start-all

## 목적

`requirements.md` FR 표의 **전체 기능**을 단일 세션에서 일괄 구현하는 오케스트레이터.

`/init-project`(doc-only) → `/start-foundation`(공통 코드) → **`/start-all`(전체 기능 일괄 구현)** 순서로 진행. `/start`의 단일 기능 루프를 FR 단위로 자동 반복한다.

## Process

0. **기본 동작과 `--step`** — 인자가 `--step` 으로 시작하면 그 낱말을 떼고 `--step` 모드(아래 각 Phase 의 기존 동작 — FR 마다 묻고 Phase 2·2.5-E 에서 승인)로 돈다. 없으면 `§일괄` 모드: 질문은 Phase 1a·1c 의 묶음 2회(회당 많아야 4개), 승인은 Phase 2.5-E 의 승인 묶음 1회이고 그 사이는 묻지 않는다(규칙 원본 `skills/specifying-ko/once-approval.md`). 모드는 Phase 0 의 queue.md 생성 직후 헤더에 `mode: 일괄` 또는 `mode: step` 1줄로 남기고, 재진입하면 그 줄을 읽어 같은 모드로 돈다 — 줄이 없는 기존 ACTIVE queue(이 변경 전 batch)는 `step` 으로 보고, 재진입 인자에 `--step` 이 있으면 줄을 `mode: step` 으로 바꾼다(인자가 이긴다 · 반대로는 바꾸지 않는다). 그래도 멈추는 곳: plan-review·design-review Critical cap · 2.5-C Critical 충돌 · 비가역(HELD) · 보안 Critical/High · Phase 3 미완 · batch PR. `/start-all-auto` 는 이 절과 무관하다(auto 변형 문단이 따로 있다). auto 변형 문단은 `/start-all-auto` 로 들어왔을 때만 적용한다(그 queue 에는 `mode:` 줄이 없다) — `mode: 일괄` batch 에서는 FR spec 라벨로 판정하지 않는다.

### Phase 0 — 준비

1. **batch-id 결정 — 재개 키는 날짜가 아니라 `ACTIVE` 마커다**

   구 규약은 `batch-<YYYYMMDD>` 여서 **날짜가 곧 재개 키**였다. 같은 날 두 번째 `/start-all` 을
   다른 `requirements.md` 로 돌리면 이전 batch 의 `queue.md` 를 재사용해 서로 다른 FR 집합이
   한 큐에 뭉갰다. 재개 판정을 이미 존재하는 진행 표시(`ACTIVE`)로 옮기고, 신규 id 에는 시각을 붙인다.

   ```bash
   # ① 진행 중 batch 탐색 — 훅(_batch_pr_gate)과 동일 관용구: .specops/batch-*/ACTIVE
   for m in .specops/batch-*/ACTIVE; do [ -f "$m" ] && basename "$(dirname "$m")"; done
   ```

   - **정확히 1개** → 그 batch **재개**. `BATCH_ID = basename`. (구 포맷 `batch-<YYYYMMDD>` 도
     ACTIVE 가 있으면 그대로 재개된다 — **하위호환**. 디렉토리명을 바꾸지 않는다.)
   - **2개 이상** → **모호**. 목록을 제시하고 사용자에게 선택받는다(자동 선택 금지 — 주권).
     `"진행 중 batch 가 여러 개입니다. 어느 것을 이어서 진행할까요? [번호 / new=새 batch]"`
   - **0개** → 신규 생성:
     ```
     BATCH_ID = "batch-<YYYYMMDD>-<HHMM>"   예: batch-20260806-1430
     ```
     `.specops/$BATCH_ID` 가 이미 있으면(같은 분 재실행) `-2`, `-3` … 접미로 회피한다.

   > 훅(`hooks/pretool-governance.sh`)·`batch-state.sh` 는 `batch-*` 글롭과 디렉토리 인자만 쓰므로
   > id 포맷에 의존하지 않는다 — 본 변경으로 게이트 동작은 바뀌지 않는다.
2. **requirements.md 탐색** (`.specops/memory/requirements.md` 우선, 없으면 루트):
   - 탐색 순서: `.specops/memory/requirements.md` → `requirements.md`
   - 두 곳 모두 없으면: "`requirements.md`가 없습니다. `/init-project`를 먼저 실행하세요." 출력 후 **중단**
3. **FR 목록 파싱** — 손으로 `grep` 하지 않는다. 아래 판정기가 FR 행을 읽는다(ID 를 굵게 쓴 `| **FR-10** |`·접미 ID `| FR-11b |` 도 FR 이다 — 공백까지 맞춘 `grep` 은 그런 행을 조용히 놓친다).
   FR 행이 하나도 없으면 판정기가 `rc=1` 로 알린다: "FR 표가 비어 있습니다. `requirements.md`에 FR 표를 작성 후 재실행하세요." 출력 후 **중단**

   **★ placeholder FR 가드 (필수 — 20260806)**: 행이 있다는 것만으로는 부족하다. 골격 `| FR-1 | <한 줄> | M1 | must |` 도 FR 행이라, 사용자가 FR 을 하나도 안 썼는데 batch 가 진입한다(Phase 1 이 넘기는 "FR 원문" 이 `<한 줄>`). 실 FR 판정은 스크립트로:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-fr-table.sh
   ```
   - `rc=0` → 실 FR 개수 확인 후 진행. placeholder 경고가 나오면 **그 FR 은 batch 대상에서 제외**한다.
   - **`해석하지 못한 FR 행 N건` 경고가 나오면 사용자에게 그대로 알린다** — FR 처럼 보이는데 ID 형식이 다르거나(`FR 6`·`FR-x7`) 행이 들여쓰여 읽지 못한 행이다. batch 대상에서 빠지므로, 진행 전에 requirements 의 ID 를 고칠지 묻는다(`/start-all-auto` 는 고치지 않고 진행하되 queue 머리말과 PR 다이제스트에 남긴다).
   - `rc=1` → 실 FR 0건. 중단하고 requirements.md 작성 안내.
   - `rc=2` → 파일 부재. 위 `/init-project` 안내와 동일 처리.

   **★ 시드 FR ≠ placeholder (필수 — 20260812)**: init 가 FR-1~3 을 M1~M3 **마일스톤 시드**로 넣고 세부 FR-4+ 를 붙인 뒤에도, 시드 행이 실 FR 로 남아 queue `PENDING` 에 들어가면 **이중 구현**된다(attendance·Argus 실측 — Argus 는 수동 `FR-1·2·3 = SKIP`). `rc=0` 이면 **반드시** 분류기를 돌린다:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-fr-table.sh --classify
   ```
   - `ELIGIBLE|<id>|<desc>|<M>` → queue Status=`PENDING`
   - `SKIP|<id>|placeholder|` → queue에 넣지 않거나 Status=`SKIP` + 설명 `(placeholder)`
   - `SKIP|<id>|seed-decomposed|<M>` → Status=`SKIP`, 설명에 `(마일스톤 시드 — 세부 FR로 분해됨)`
   - `SKIP|<id>|foundation-scope|<M>` → Status=`SKIP`, 설명에 `(공통부 — /start-foundation 담당)` — 설명 선두 `[공통]`/`**[공통]**` 또는 `<!-- foundation-fr: FR-N,… -->`
   - `SUMMARY|…|eligible=0|…` 이고 실 FR≥1 이면 → "batch 대상 FR 0건"(시드·공통부만 남음) 안내 후 **중단**. 공통만이면 `/start-foundation` 완주(또는 기능 FR 추가) 후 재실행.
   - 시드·공통부 SKIP ≥1 이면 queue 상단에 사유 2–3줄 기재(Argus queue 헤더 패턴)
   - **기존 `queue.md` 재사용 시 재분류 금지** (재개 규약 — PENDING/PLAN_DONE 보존)

   **★ 공통부 FR ≠ 기능 FR (필수 — 20260812)**: 시드 가드·foundation-manifest 선행과 **별개**. `[공통]` 표기 FR 은 **항상** queue SKIP — `/start-all` 이 공통을 `§유형=신규`+`§batch` 로 구현하면 manifest·Step 5.6 경로와 어긋난다. hybrid(`§유형=foundation`+`§batch`)도 금지(`check-spec-label-compat.sh`).

   **★ foundation-manifest 선행 게이트 (필수 — 20260812)**: 시드 FR 가드와 **별개**. UI/BE/풀스택/모바일이면 `.specops/memory/foundation-manifest.md` 가 채워져 있어야 한다 — 부재 시 `check-foundation-reuse` 가 SKIP 되어 공통 재구현이 침묵 통과한다. FR 표 통과 ≠ foundation 완료.
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-foundation-present.sh
   ```
   - `rc=1` (`FOUNDATION-PRESENT: FAIL`) → Phase 0 **중단**. `/start-foundation "<공통부>"` 완주(manifest 채움) 후 `/start-all` 재실행.
   - `rc=0` + `PASS` → 진행.
   - `rc=0` + `WARN`/`SKIP` (CLI 등 비필수) → 진행. WARN이면 queue 헤더에 1줄 기록.
   - §auto·대화형 **동일 HARD** (가정 다이제스트로 우회 금지). ACTIVE 재진입 시에도 **매 Phase 0** 재검사.

   **★ foundation 브랜치 머지 게이트 (필수 — 20260812)**: present(문서)와 **별개**. `§유형=foundation` FID 의 `feat/<FID>` 가 `main` 에 미머지(git 조상 아님 ∧ gh도 MERGED 아님)이면 UI/BE/풀스택/모바일은 **중단** — manifest 만 있고 공통 코드가 base 에 없는 이중 트랙을 막는다.
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-foundation-merged.sh
   ```
   - `rc=1` (`FOUNDATION-MERGED: FAIL`) → Phase 0 **중단**. foundation PR 머지(또는 로컬 main 반영) 후 `/start-all` 재실행.
   - `rc=0` + `PASS`/`SKIP` → 진행. `WARN`(비필수·미머지)이면 queue 헤더에 1줄.
   - FID 없거나 브랜치가 이미 삭제된 경우 SKIP/PASS. §auto·대화형 동일 HARD.
4. **batch 브랜치 생성** (1회, 재진입 시 skip):
   ```bash
   # 이미 존재하면 switch, 없으면 create
   git show-ref --verify --quiet "refs/heads/feat/$BATCH_ID" \
     && git checkout "feat/$BATCH_ID" \
     || git checkout -b "feat/$BATCH_ID"
   ```
5. **queue.md 초기화 + ACTIVE 마커** — `.specops/$BATCH_ID/queue.md` 생성 (재진입 시 기존 파일 재사용).
   queue.md 를 만들거나 재사용할 때 **반드시 함께** 진행 표시를 남긴다:
   ```bash
   : > ".specops/$BATCH_ID/ACTIVE"
   ```
   이 마커가 batch PR 게이트(`hooks/pretool-governance.sh`)의 판정 범위다 — **마커가 있는 batch 만** 검사한다.
   `.specops/*` 는 gitignore 라 끝난 batch 디렉토리가 디스크에 계속 남는데, 마커 없이 아무 batch 나 집으면
   그것과 무관한 후속 작업의 PR 이 과거 상태로 차단된다(false-block). 마커를 안 남기면 게이트도 발화하지 않는다.

   **★ queue 기계 초기화 (필수 — 20260812)**: 모델이 표를 손으로 쓰지 않는다. `--classify` 결과를 스크립트가 반영한다.
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/init-batch-queue.sh \
     ".specops/$BATCH_ID"
   ```
   - `QUEUE-INIT: CREATED` → 신규 표(ELIGIBLE→PENDING · seed-decomposed/foundation-scope→SKIP · placeholder 행 생략).
   - `QUEUE-INIT: REUSE` → 기존 `queue.md` **불변**(재개 — PENDING/PLAN_DONE 보존). 재분류·덮어쓰기 금지.
   - `QUEUE-INIT: FAIL` → Phase 0 **중단**(eligible=0 · requirements 부재 · classify 실패).
   - ACTIVE 마커는 위와 **병치**(스크립트는 queue만 담당).

   재사용은 **스텝 1이 ACTIVE 로 재개를 판정한 batch 에서만** 일어난다 — 신규 batch 는 id 에 시각이 붙어
   디렉토리가 겹치지 않으므로 남의 queue 를 물려받지 않는다(구 날짜-키 규약의 뭉갬 경로 제거).
   FID 칸은 Phase 1에서 `BATCH-PHASE1-DONE: <FID>` 수신 후 `queue-set-status.sh` 가 채운다(스텝 3). Phase 1 은 **PENDING 만** 처리하므로 SKIP 은 자연 제외.

### Phase 1a — 질문 묶음 1회 (`§일괄`)

`mode: 일괄` 이 아니면(`--step`·`/start-all-auto`) 건너뛴다. `questions.md` 에 `## 1a` 절이 이미 있으면(재진입) 건너뛴다.

1. PENDING FR 전체 행과 `.specops/memory/*` 를 읽고(결정 원장 확정 주제는 `check-decisions-ledger.sh` 로 확인해 뺀다), 답에 따라 FR 의 설계·AC 가 달라지는 질문만 고른다.
2. 많아야 4개를 한 메시지로 묻는다 — 질문마다 관련 FR · 선택지와 영향 1줄 · 추천과 근거 1줄을 맨 앞에(AskUserQuestion 이 있으면 그것으로). 넘는 것은 묻지 않고 Phase 1 체인이 ASSUMED 로 정한다. 물을 것이 없으면 건너뛴다.
3. `.specops/<BATCH_ID>/questions.md` 의 `## 1a` 절에 질문 · 추천 · 답 · 관련 FR 을 적는다. 답은 Phase 1 args 의 `결정:` 줄로 그 FR 에 전한다.

### Phase 1 — 전 FR spec→decompose (대화형)

각 FR에 대해 **순서대로** 반복 (queue.md PENDING 항목):

1. `specops-ko:specifying-ko` 호출 — args 정확히 아래 형식:
   ```
   <!-- entry: batch -->
   <!-- batch-id: <BATCH_ID> -->
   <FR 원문 — FR-N 행의 설명 부분>
   ```
   - **`§일괄`**: 둘째 줄 다음에 `<!-- auto: true -->` 셋째 줄을 넣고(`/start-all-auto` 와 같은 형식) FR 원문 아래에 Phase 1a 의 그 FR 답을 `결정: <질문> → <답>` 줄로 붙인다 — 체인은 묻지 않고 BLOCKING 을 `status: ASSUMED` 로 적는다.
2. specifying-ko → clarifying-ko → planning-ko → decomposing-ko 체인 자동 진행 (FID는 specifying-ko Step 0이 결정)
   - **HARD**: batch 분기에서 specifying **Step 5.5·5.6 SKIP** — 화면·인터페이스 상세는 Phase 2.5 전담(통상 순서: 화면 → 인터페이스). Phase 1은 예정 화면/엔드포인트·테이블 **이름만** §참조에 남긴다.
   - clarifying은 `.specops/memory/decisions.md` 확정 주제를 재묻지 않음 (init 원장 우선).
   - **planning**: `**§batch**`이면 plan-reviewer·per-FR critic **DEFER** (Phase 2에서 1회). 스펙→플랜→쪼개기만 수행.
3. decomposing-ko 출력에서 `BATCH-PHASE1-DONE: <FID>` 감지 → 그 FR 의 **FID 칸과 Status 를 한 번에** 갱신한다(넷째 인자가 FID):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/queue-set-status.sh .specops/$BATCH_ID/queue.md <FR-ID> PLAN_DONE <FID>
   ```
   > **★ FID 칸도 스크립트로 채운다** (20261009). batch PR 게이트(`batch-state.sh --gate`)·RELEASE_READY·게이트 전파(`record-batch-gate.sh`)는 **이 칸으로** 그 FR 의 evidence·리뷰 산출물을 찾는다. 칸이 `TBD` 로 남으면 그 FR 은 검사할 수 없다 — `batch-state.sh` 가 `[FID 미기재]` 로 차단하고, `queue-set-status.sh` 는 FID 칸이 빈 행을 `IMPL_DONE` 으로 바꾸지 않는다.
   > **★ Status 는 스크립트로만 갱신한다 — 손으로 표를 고치지 마라** (20260828). 모델이 강조 표기를 붙여 `**PLAN_DONE**` 로 쓰면 소비자 3곳(`batch-state.sh`·`collect-assumptions.sh`·`record-batch-gate.sh`)이 전건 불일치하고, **검사가 대상 0건으로 조용히 통과**한다. argus batch-20260729 실측: FR 31건이 그 상태로 무검증 방치됐다. 읽는 쪽 정규화가 사후 방어로 들어갔지만 유입을 끊는 것은 이 호출이다.
4. 다음 PENDING FR 반복

> **HARD GATE**: clarifying-ko의 BLOCKING 질문은 사용자 응답 필수. Phase 1은 대화형이다. (원장에 이미 확정된 주제는 BLOCKING에서 제외)
> (`§일괄` 이면 체인은 묻지 않는다 — 질문은 Phase 1a·1c 묶음으로 받는다 · 위 HARD GATE 는 `--step` 모드 몫이다)

### Phase 1c — 확인 묶음 1회 (`§일괄`)

`mode: 일괄` 이 아니면(`--step`·`/start-all-auto`) 건너뛴다. 전 FR 이 PLAN_DONE 일 때:

1. 이 batch 의 전 FID `clarifications.md` 에서 머리줄에 `BLOCKING · ASSUMED` 가 있는 블록을 모은다(queue.md 의 FID 칸 기준 · clarifying-ko Q-block 형식과 같은 문자열).
2. 영향이 큰 것(아키텍처·저장소·핵심 입출력 먼저)부터 많아야 4개를 한 메시지로 묻는다 — 추측값을 추천으로 맨 앞에. 0건이면 건너뛴다.
3. 답이 추측과 같으면 그 블록의 `status` 를 `RESOLVED` 로 바꾼다. 머리줄의 ` · ASSUMED` 도 뗀다(재진입한 1c 가 다시 모으지 않게).
4. 다르면 **그 FR 만** 다시 돈다: clarifications 블록을 답·`RESOLVED` 로 고침(머리줄의 ` · ASSUMED` 도 뗀다) → 답이 AC 를 바꾸면 acceptance-criteria.md 에 append → `specops-ko:planning-ko` 를 그 FID 로 호출(§batch 라 plan-reviewer DEFER) → decomposing → `BATCH-PHASE1-DONE` → `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dev-decision.sh add <FID> order "1c 답 변경 → clarify·plan·decompose 재실행" "<질문>: <추측> → <답>"`. 재실행이 plan 에서 실패하면 그 FR 을 HELD 로 바꾸지 않고 queue 상태와 FID 칸을 그대로 두며(PENDING 으로 되돌리면 재진입이 FID 를 새로 만든다), Phase 2 에 들어가지 않고 사용자에게 1줄 보고한다 — 재진입하면 1c 4번부터 그 FR 을 다시 돈다.
5. 묻지 못한 나머지는 ASSUMED 그대로 두고 `questions.md` 의 `## 1c` 절에 질문 · 추천(추측) · 답(또는 `미질문 — ASSUMED`)을 적는다.

### Phase 2 — batch plan-review + 일괄 게이트

> **순서**: (1) batch plan-reviewer 1회 → (2) 짧은 digest → (3) [y/n] / §auto → Phase 2.5.  
> Phase 1에서 §batch plan-reviewer는 **DEFERRED** — 여기서 해소한다(생략 아님).

0. **전제**: queue.md의 추적 FR이 모두 `PLAN_DONE`(또는 이후 상태). 미완이면 Phase 1 복귀.

1. **Batch plan-review (필수)** — `Agent` `subagent_type: "specops-ko:plan-reviewer-ko"` **1회**
   - 컨텍스트: 전 PLAN_DONE FID의 `.specops/<FID>/spec.md` + `plan.md` **경로 목록**(본문 전문 붙여넣기 금지)
   - 부모는 stdout을 `.specops/<BATCH_ID>/plan-review.md`에 저장
   - 각 FID `dispatch-log.md`에 deferred 해소 행: `| … | plan-reviewer | plan-reviewer-ko | PASS|FAIL | batch Phase 2 |`
   - **PASS** → 선택: 외부 critic 최대 1회(대표 plan 또는 전 경로) 또는 `CRITIC: SKIP (batch defer)` 기록 → 스텝 2
   - **FAIL** (1회차): 이슈 목록으로 관련 FID `plan.md` 수정 → 필요 시 해당 FID만 `decomposing-ko` 재실행 → plan-reviewer **재dispatch 1회**
   - **FAIL** (재시도 후): 부모가 `.specops/<BATCH_ID>/plan-review.md` 에서 **`^Critical:[[:space:]]*[1-9]`** 를 본다(Phase 2.5-D 와 **동일 기계 판정** — plan-reviewer 도 `Critical: <N>건` 을 출력한다). **Critical≥1**: 대화형·**§auto 모두** `HARD-GATE: batch plan-reviewer cap — 사용자 개입` 후 **정지**(§auto 자동통과 금지). **Critical=0 이고 Important≥1**: 대화형은 HARD GATE(§일괄 은 아래 2.6), **§auto**만 가역 자동통과 + queue/다이제스트 기록 — 단 `^Critical:[[:space:]]*0` 줄이 **있을 때만** Critical=0 이다. `Critical:` 줄이 아예 없으면(리뷰어 출력 형식 이탈) 정지한다: 줄이 없다고 통과시키면 무인에서 Critical plan 이 지나간다(`planning-ko` 의 단일 모드 판정과 같은 방향).
     > 산문 판단 금지(20260806): 무인에서 Critical 을 눈으로 세면 오판 시 **Critical plan 이 자동통과**한다 — 사람이 없다. 두 리뷰 축이 같은 패턴을 쓰게 고정한다.
   - **금지**: Phase 2 plan-review 생략 · 부모 self-review 대체 · FR마다 plan-reviewer 재실행

2. **짧은 digest** — 전 plan 본문 덤프 금지. 스크립트:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/batch-plan-digest.sh ".specops/$BATCH_ID"
   ```
   출력(FR당 1줄): `FID | §유형 | 태스크수 | AC수 | plan/tasks 경로`. architecture 드리프트가 보이면 한 줄 경고만.  
   이 시점의 `api-spec`·`data-model` cross-FR 검수는 **하지 않는다**(Phase 2.5-B).

2.5. **[§auto 모드]**: digest 수행 후 일괄 리뷰 게이트 **자동 통과** → Phase 2.5 직행 (가역 — 가정은 batch PR 다이제스트 집계). plan-review FAIL Critical cap이면 자동통과 금지.

2.6. **[§일괄 모드]**: 아래 3 을 묻지 않고 Phase 2.5 로 간다(digest 는 2.5-E 승인 묶음에 싣는다). plan-review Critical cap 정지는 그대로다. Critical 0 · Important 만 남은 cap 은 §auto 와 같이 지나가고 그 Important 를 2.5-E 승인 묶음에 싣는다.

3. 단일 게이트: **"화면·인터페이스 설계 후 구현 진행? [y/n]"**
   - `n` → **중단**. 아티팩트·`feat/<BATCH_ID>` 보존. 재진입 시 Phase 2.5부터 가능(plan-review.md PASS 있으면 digest/[y/n]만 재개 가능)
   - `y` → Phase 2.5 진입

### Phase 2.5 — batch 통합 design-first (화면 → 인터페이스)
> **왜 여기 통합 단계인가**: specifying Step 5.5·5.6은 batch에서 **SKIP**한다. FR마다 화면·IF를 돌리면 batch 이점을 깨뜨리므로, 구현 직전 **1회 통합**한다. 통상 순서: **A 화면 → A2 화면 전문가 → B 인터페이스 → C cross-FR → D 무거운 설계 리뷰 → E 승인 → F 커밋**.

#### A. 통합 화면 설계 (UI 기능 시)

1. **UI 표면 검출** — 전 FID `.specops/<FID>/spec.md` §참조·§범위에서 화면 신호(`screens/<name>` 목록·화면 렌더·사용자 흐름)를 취합한다.
   - **★ 화면 목록 마스터 합류 (20260906)**: FR 취합에 더해 `/init-project` 가 정의한 마스터를 **읽는다** — 마스터에만 있는 화면은 어느 FR 도 언급하지 않으면 **조용히 누락**된다(PR #32 가 한계로 기록한 것을 본 배선이 해소).
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-screens-overview.sh list
     ```
     - 출력 이름을 FR 취합 결과와 **합집합**으로 화면셋을 정한다.
     - 마스터에만 있는 이름은 queue 상단에 `화면 마스터 전용: <name>… (FR 미언급 — 이번 batch 설계 대상 여부 판단)` **헤더 산문 줄**로 기록한다(**`|` 로 시작 금지** — `batch-state.sh` 가 표 행으로 오인한다).
     - 마스터 부재(미부트스트랩)면 빈 출력 — **그대로 진행**(비차단).
   - **신호 없음(순수 API·CLI·데이터 batch)** — **합집합 기준**이다(FR 신호가 0 이어도 마스터 전용 이름이 있으면 **신호 있음**) → `SCREEN-DESIGN: SKIP — <근거>` 를 `queue.md`에 기록 후 **B(인터페이스)로 진행** (Phase 3 직행 금지 — API batch도 B가 본설계).
2. **DESIGN.md 토큰 적용** — 취합된 **전체 화면셋**에 프로젝트 `DESIGN.md` 토큰을 공통 적용한다(부재 시 `templates/screen.html` 기본 토큰).
3. **★ foundation 셸 baseline 불변 (20260812)**: 화면 생성 **직전** snapshot → **직후** verify. allowlist(`app-shell`·`layout`·`login`) ∩ `<!-- foundation-shell -->` 파일 해시가 바뀌면 FAIL → Phase 2.5 중단.
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-foundation-shell-baseline.sh \
     snapshot ".specops/$BATCH_ID/foundation-shell-baseline.sha"
   # … 기능 화면 생성(셸 재작성·--force 금지) …
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-foundation-shell-baseline.sh \
     verify ".specops/$BATCH_ID/foundation-shell-baseline.sha"
   ```
   - `FOUNDATION-SHELL-BASELINE: FAIL` → 셸 되돌림. 셸 변경은 `/start-foundation` 또는 `/design-screen`(셸 슬러그)만.
   - `SKIP`(셸 0) → 진행(구 프로젝트). **§auto도 HARD**.
4. **화면 산출물 생성** — 각 **기능** 화면별 `screens/<name>.md` + `screens/<name>.html` 쌍을 DESIGN.md 토큰으로 생성한다.
   - **foundation-shell 마커 + allowlist 슬러그**가 이미 있으면 → **재사용만**(내용 재생성·`--force`·마커 삭제 금지).
   - **파일이 없으면 생성**한다(기능 화면).
   - **이미 있고**(비-셸) `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/design-screen.sh --check screens/<name>.md screens/<name>.html` → exit 1(정상) → **재사용**.
   - **이미 있고** exit 0(껍데기) → **재사용 금지**. DESIGN.md 토큰으로 덮어쓰고 **껍데기 마커 줄을 삭제**한다.
   - 해당 FID spec.md §참조에 경로가 없으면 추가한다.
   - **DESIGN.md 준수**: 화면 작성 시 `DESIGN.md` **§2 타이포·§3 간격** · §6 레이아웃 패턴 · §6.1 화면 원형 · §7 상태 표현 · §8 원칙/안티패턴 · §9 AI 지침을 읽고 따른다 (DESIGN.md 부재 시 skip). `/start`·`/maintain` 의 Step 5.5 `[공통]` 과 동일 요건 — batch 라고 축이 줄지 않는다.
   - **입력 접근성**: 입력(input·select·textarea)마다 label 의 for 속성과 입력 id 를 같은 값으로 짝지어 연결한다(label 이 입력을 감싸거나 aria-label 도 허용 — for 없이 형제로만 둔 label 은 연결이 아니다). 라디오·체크박스는 선택지마다 자기 label 을 두고 그룹 이름은 fieldset 과 legend 로 둔다. 템플릿 html 의 주석 속 입력 예시를 복사해 쓴다.
   - **템플릿 기반**: 각 `.html` 은 `templates/screen.html` 을 기반으로 생성한다 — `--text-*`·`--space-*` 토큰 자리가 DESIGN.md §2·§3 과 1:1 대응한다.
   - **★ 마스터 갱신 + 잔여 고지 (20260906)**: 생성 완료 후 **기계로** 마스터를 갱신한다(모델이 손으로 행을 쓰지 않는다 — 빼먹으면 마스터가 다시 낡는다).
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-screens-overview.sh sync
     bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-screens-overview.sh diff
     ```
     - `sync` 는 fence **안에만** 추가하고 멱등이다(2회 실행해도 중복 없음).
     - `diff` 잔여 차집합은 queue 헤더 산문 줄로 기록 + 사용자 고지. **차단하지 않는다** — 정당한 불일치가 많다(다음 마일스톤 선등재·`/design-screen` 개별 생성분).
   - **init 미확정 해소**: 재사용하는 화면에 `<미확정 — 근거 필요>` 가 남아 있고 이번 batch FR 이 그 값을 확정했으면 **그 마커만** 채운다(나머지 본문 유지). 채운 뒤 그 화면의 `screens-overview.md` 행 **목적 칸**에 적힌 `init 보강 (미확정 N)` 의 N 을 남은 마커 수로 고친다(0 이면 한 줄 목적으로 바꾼다) — `sync` 는 행을 추가할 뿐 칸을 고치지 않는다
5. **[§auto 모드]**: 화면별 대화형 승인 **없이** 자동 반영. 생성 화면 목록은 batch PR 다이제스트에 집계. **셸 불변은 §auto도 HARD**.
6. **[§일괄 모드]**: §auto 와 같이 대화 승인 없이 반영하고 생성 화면 목록을 E 승인 묶음에 싣는다. 셸 불변은 HARD 그대로다.

#### A2. 화면 전문가 패스 (A 가 기능 화면을 만들거나 고쳤을 때 · batch 당 1회)

> 단일 경로의 specifying Step 6.6 과 같은 에이전트다. batch 는 Step 6.6 을 건너뛰므로(§batch 제외) 여기서 한 번에 본다. D(`design-reviewer-ko`)의 독립 판정은 그대로다 — 전문가는 리뷰 앞에서 빈칸을 채우고 리뷰어는 따로 판정한다.

1. **발동** — A 에서 기능 화면 `screens/<name>.md` 를 만들거나 고쳤으면 부른다. foundation 셸(`<!-- foundation-shell -->`)만 재사용했거나 A 가 SKIP 이면 `UI-EXPERT: SKIP — 화면 산출 없음` 을 `queue.md` 헤더 산문 줄로 기록하고 B 로 간다(`|` 로 시작 금지).
2. **dispatch** — `Agent` 도구, `subagent_type: "specops-ko:ui-designer-ko"`, batch 당 1회. 입력은 경로만 — 이번 batch 가 만든·고친 `screens/<name>.md`·`.html` · PLAN_DONE FID 의 `spec.md`·`acceptance-criteria.md` · `DESIGN.md`(있으면) · `BATCH_ID` 와 산출 경로 `.specops/<BATCH_ID>/experts/ui.md`(산출 경로의 `<FID>` 자리에만 `<BATCH_ID>` 를 쓴다고 프롬프트에 적는다). 산출은 그 파일 하나다.
3. **반영** — 지적은 화면 파일에 반영하거나 기각하고 `experts/ui.md` 끝 `## 반영` 에 1줄씩 적는다. `## 확인 필요` 질문은 E 설계 승인 게이트에서 함께 묻는다 — `§auto` 면 best-guess 로 정해 `(ASSUMED)` 로 queue 다이제스트에 남긴다.
4. **모델 불가·산출 없음** — opus 를 쓸 수 없으면 같은 에이전트를 가용 모델 override 로 다시 dispatch 한다(부모가 대신 검토하지 않는다). 산출이 없으면 1회 다시 부르고, 그래도 없으면 `queue.md` 에 `UI-EXPERT: 산출 없음` 을 산문 줄로 남기고 B 로 간다.
5. 반영 뒤 B 로 진행한다(인터페이스 도출은 반영된 화면의 Interactions 를 쓴다).

#### B. 통합 인터페이스 설계 (API/스키마 기능 시 · 화면 직후)

> design-first: **A에서 만든 `screens/*.md`의 Interactions를 우선**해 엔드포인트·테이블을 도출한다 (`/design-interface` Step 1과 동일). 화면이 없으면(B만 해당) 각 FID spec §범위·예정 IF 이름에서 도출한다.

1. **IF 표면 검출** — 전 FID spec §범위·§참조 + (존재 시) `screens/*.md` Interactions에서 API/DB/클라이언트 스토리지 신호를 취합한다.
   - **신호 없음(순수 UI·문서 batch)** → `INTERFACE-DESIGN: SKIP — <근거>` 를 `queue.md`에 기록 후 **C로 진행**.
2. **마스터 갱신** — `.specops/memory/api-spec.md`·`data-model.md`에 전 FR 변경분을 **append**(섹션 덮어쓰기 금지 · 동일 메서드+경로/테이블은 **해당 행 갱신** — 단 **`<!-- foundation-baseline -->` 마커 안은 갱신·삭제 금지**, 마커 밖만).
   - **★ foundation IF baseline 불변 (20260812)**: 갱신 **직전** snapshot → **직후** verify. 마커 본문이 바뀌면 FAIL → Phase 2.5 중단.
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-foundation-if-baseline.sh \
     snapshot ".specops/$BATCH_ID/foundation-if-baseline.sha"
   # … 마스터 append (마커 밖만) …
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-foundation-if-baseline.sh \
     verify ".specops/$BATCH_ID/foundation-if-baseline.sha"
   ```
   - `FOUNDATION-IF-BASELINE: FAIL` → baseline 되돌리고 FR 전용만 다시 append. `/start-foundation` 또는 `/design-interface`로만 baseline 변경.
   - `SKIP`(마커 0) → 진행(구 프로젝트).
   - memory 부재 시: 대화형은 생성 확인, §auto는 신규 생성 금지·각 FID spec에 "인터페이스 미반영: memory 부재" 기록.
   - **init 미확정 해소**: 갱신하는 행에 `<미확정 — 근거 필요>` 가 남아 있고 이번 batch FR 이 그 값을 확정했으면 **그 마커만** 채운다(나머지 본문 유지 · `<!-- foundation-baseline -->` 마커 안은 제외).
3. 각 FID spec.md §1에 반영 요약 1줄(`**자동 결정 인터페이스**` 또는 대화형 동등 요약) + §참조에 api-spec/data-model 경로.
4. **[§auto 모드]**: 인터페이스 대화형 승인 없이 자동 append(가역 — PR 다이제스트 집계). **마커 안 불변은 §auto도 HARD**.
5. **[§일괄 모드]**: 대화 승인 없이 반영한다. memory 문서가 없으면 템플릿(제공 `templates/api-spec.md` · 외부 소비 `templates/api-spec-consumer.md` · `templates/data-model.md`)으로 만들고 E 승인 묶음에 싣는다(§auto 의 생성 금지와 다르다 — 사람이 E 에서 본다). 마커 안 불변은 HARD 그대로다.

#### C. cross-FR 계약 리뷰 (오케스트레이터 quick)

1. 갱신된 `api-spec.md`·`data-model.md`에서 **충돌·중복 엔드포인트/테이블**을 한 표로 요약 (서브에이전트 추가 금지 — 산문 1회).
2. 충돌이 있으면 해소 후 D로 — §auto여도 Critical 충돌은 자동 무시 금지(목록 기록 + 최소 수정 또는 사용자 확인).

#### D. 무거운 설계 리뷰 (`design-reviewer-ko`)

> A(화면) 또는 B(IF) 중 **하나라도 산출**되면 **항상** Evaluator를 돌린다. 둘 다 SKIP이면 D·E 생략 → F(커밋 없이 Phase 3) 또는 빈 design 커밋 생략 후 Phase 3.

1. **dispatch** — `Agent` 도구, `subagent_type: "specops-ko:design-reviewer-ko"`. 컨텍스트: `BATCH_ID` · PLAN_DONE FID 목록 · `screens/` · `api-spec.md` · `data-model.md` · 각 FID `spec.md` 경로.
2. 부모는 리뷰어 stdout을 `.specops/<BATCH_ID>/design-review.md`에 저장한다 (리뷰어는 Write 없음).
3. 시그널 처리:
   | 결과 | 동작 |
   |---|---|
   | `DESIGN-REVIEW-RESULT: PASS` | E로 진행 |
   | `DESIGN-REVIEW-RESULT: FAIL` (1회차) | 이슈 목록으로 A/B 수정 → **재dispatch 1회** |
   | `DESIGN-REVIEW-RESULT: FAIL` (재시도 후) | 부모가 `design-review.md`에서 `^Critical:[[:space:]]*[1-9]` 를 본다. **Critical≥1**: 대화형·**§auto 모두** `HARD-GATE: design-reviewer Critical cap — 사용자 결정` 후 **정지**(§auto 자동통과 금지, queue에 사유 기록). **Critical=0 이고 Important≥1**: 대화형은 HARD GATE. **§auto**만 `Important-only cap → §auto 자동통과` 를 queue/다이제스트에 기록 후 E(가역) — `^Critical:[[:space:]]*0` 줄이 있을 때만이다(줄이 없으면 정지) |
   | `DESIGN-REVIEW-RESULT: SKIP` | D 대상 아님 — E 생략 후 F/Phase 3 |
4. **Evaluator 모델 불가 fallback**: `design-reviewer-ko` 의 지정 모델(별칭 sonnet) 불가(한도 소진·접근 불가) 시 부모 self-review 금지 — 같은 `design-reviewer-ko`를 가용 모델 override로 재dispatch. queue 또는 design-review.md 헤더에 `모델 fallback: <지정 모델> 불가 → <모델>` 기록 (`implementing-ko` 동일 원칙). 직후 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/record-metric.sh --fid <대표-FID-또는-BATCH_ID가-FID형식이면그값> --phase evaluator-degradation --fallback true --model <override-model>` 실행(식별자만; BATCH_ID가 FID 형식이 아니면 PLAN_DONE 중 대표 FID 1개 사용).
5. **[§일괄 모드]**: Critical=0 · Important 만 남은 cap 은 §auto 와 같이 지나가고 그 Important 를 E 승인 묶음에 싣는다. Critical cap 정지는 그대로다.

#### E. 설계 승인 게이트

1. `design-review.md` 요약(Critical/Important/Minor 건수 + 상위 이슈) + 화면 목록 + IF 변경 요약을 제시.
   - FR 별 intent 1줄 요약(문제 → 기대 결과) — `.specops/<FID>/intent.md` 에서 발췌
   - A2 의 `experts/ui.md` `## 확인 필요` 질문(있으면) — 사용자가 답한 내용은 화면 파일에 반영한 뒤 F 로 간다
2. 대화형: **"이 설계로 구현 진행? [y/n]"**
   - `n` → A/B 수정 후 D부터 재개 (리뷰 재실행)
   - `y` → F
3. **[§auto 모드]**: D가 PASS(또는 Important-only cap 자동통과)면 본 게이트 **자동 통과**. Critical cap 정지 시 E에 도달하지 않는다. 화면·IF·design-review 결과는 batch PR 다이제스트에 집계.
4. **[§일괄 모드] — 유일한 승인 묶음**: 1 의 항목에 더해 ① `.specops/<BATCH_ID>/questions.md` 의 1a·1c 답 ② 이 batch 의 PLAN_DONE FID 마다 `clarifications.md` 의 머리줄 `· ASSUMED` 또는 `status: ASSUMED` 인 블록과 spec `**자동 결정 …**` 줄을 직접 모은 목록(`collect-assumptions.sh` 는 IMPL_DONE FID 만 집계해 이 시점에는 0건이다 — batch PR 게이트에서 쓴다) ③ 승인 뒤 자동 진행(Phase 3 → 통합·E2E·성능 → batch PR) ④ 그래도 멈추는 곳(plan·design Critical cap · 보안 Critical/High · Phase 3 HELD·미완 · batch PR) ⑤ plan·design 리뷰가 Important 만 남긴 cap(§auto 와 같이 지나간 것)을 한 메시지에 싣고 2 의 질문으로 묻는다. 승인되면 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dev-decision.sh add <대표 FID> approval "batch 승인 묶음 승인" "<요지>"` 1줄. `n` 은 2 와 같다. 이 batch 의 FR spec 에 `**§auto**: true` 가 있어도(§일괄 이 셋째 줄로 넣은 것) 3 을 적용하지 않는다 — 판정은 queue.md 의 `mode:` 줄이다.

#### F. design 산출물 커밋 → Phase 3

1. `screens/*.md`·`screens/*.html`·`DESIGN.md`·`.specops/memory/api-spec.md`·`.specops/memory/data-model.md`·`.specops/<BATCH_ID>/design-review.md`·`.specops/` **만** 담아 커밋(코드 혼입 금지). R-1 docs/design-only 면제 — **BYPASS 불요**.
2. 완료 → Phase 3. `implementing-ko`는 `screens/`·api-spec·data-model을 **§6 설계 계약**으로 소비하고, `verifying-evidence-ko` memory 동기화 점검이 역방향 안전망이다.

### Phase 3 — per FR 순차 구현 (무중단)

> **[per-FR ≠ batch-level — 뭉개짐 방지 경계]** 아래 스텝 1~6 은 **FR 마다 개별** 실행이다 — verify·code-review 는 FID 당 **각각 1개**의 산출물(`evidence.md` · `review-request.md`)을 남긴다. **한 번에 뭉쳐 돌리지 않는다.** (대조: 아래 "Phase 3 완료" 의 Step A/B/C security·integration·performance 는 batch 전체를 대표 FID 로 **1회** 통합 실행 — 성격이 반대다. 이 문서 후반부의 batch-level 패턴을 verify·review 에 일반화하지 말 것.) verify 는 `run-verification.sh <FID>` 로 그 FR 의 tasks.md 명령만 뽑아 자연히 격리되지만, review.diff 는 공유 batch 브랜치에서 **base 를 명시 기록**하지 않으면 직전 FR 변경까지 끌어들여 내용이 뭉개진다(스텝 1a).

queue.md의 PLAN_DONE 항목을 **순서대로** 처리 (IMPL_DONE은 skip). 각 FR(=FID)에 대해:

1a. **per-FR review base 기록** — implementing-ko 호출 **직전** 현재 HEAD 를 그 FID 의 review base 로 고정 (이 파일이 없으면 requesting-code-review-ko 가 `HEAD~1` 로 falling back → batch 에서 FR 격리 실패):
   ```bash
   git rev-parse HEAD > ".specops/<FID>/review-base.sha"   # 이 FR 구현 시작점 — review.diff 격리 base
   ```
   (재진입 시 해당 FID 가 이미 IMPL_DONE 이면 이 FR 전체를 skip — 파일 재기록 금지. **파일이 이미 있으면 다시 쓰지 않는다** — 보류(`HELD`)에서 돌아온 FR 이 그 경우다: 다시 쓰면 보류 전에 끝낸 태스크 커밋이 리뷰 diff 밖으로 밀린다. 그 사이 다른 FR 의 커밋이 diff 에 섞이는 것은 감수한다 — 빠지는 것보다 낫다)
1. `specops-ko:implementing-ko` 호출 (**FID 기준**)
1b. **FR 보류 신호** — implementing-ko 가 `BATCH-FR-HELD: <FID>` 를 내고 멈추면 그 FR 은 여기서 끝낸다. 구현자의 `NEEDS_APPROVAL`(비가역·repo 밖 흔적) 또는 Phase C 의 `NEEDS_DISCUSSION` 이다 — batch 는 사용자와 직접 대화할 수 없어 그 자리에서 묻지 못한다.
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/queue-set-status.sh .specops/$BATCH_ID/queue.md <FR-ID> HELD <FID>
   ```
   - 스텝 2~5 는 하지 않는다 — verify·리뷰·`IMPL_DONE` 금지. 사유는 그 FID 의 `dispatch-log.md` 에 있다(`NEEDS_APPROVAL <task-id> …` 또는 `HOLD` 행).
   - 다음 `PLAN_DONE` FR 로 넘어간다(무중단).
   - 보류된 FR 은 "Phase 3 완료" 의 batch-state 스캔에서 미완으로 잡혀 사용자 확인 게이트에 오른다. 그때 FR 별 사유와 선택지를 `dispatch-log.md` 원문 그대로 보인다. 승인·결정을 받으면 그 FR 을 `PLAN_DONE` 으로 되돌려(같은 스크립트) 스텝 1a 부터 다시 돈다(`NEEDS_APPROVAL` 은 승인 기록 `dispatch/<task-id>-approval.md` 를 남긴다 — `skills/implementing-ko/needs-approval.md`).
2. 완료 → `specops-ko:verifying-evidence-ko` 호출 (**FID 기준** — `run-verification.sh <FID>` → `.specops/<FID>/evidence.md` 개별 생성 + session-progress 에 `/verify PASS` 줄 append 까지가 이 스텝이다. 이 줄이 R-1/R-2 면제 신호이자 batch-state 하드 재검 대상 — `pnpm test` 류 직접 실행으로 대체하면 실행 증거·진행 줄이 없어 커밋/PR 게이트가 닫힌 채 남는다)
3. **request/receive 리뷰** — 기본: `specops-ko:requesting-code-review-ko` → `receiving-code-review-ko` (**FID 기준**, review.diff base = `.specops/<FID>/review-base.sha`).
   - **축소(오케스트레이터 산문 + batch-state 메타 검증)**: 아래 중 하나면 requesting/receiving **skip 가능**. skip 시 `BATCH-REVIEW-DONE: <FID>` 를 오케스트레이터가 기록하고, IMPL_DONE 전에 `review-request.md` 대신 `review-skip.md`(사유 1줄)를 둔다.
     1. **end-loaded**: `review-skip.md`에 `end-loaded:` 포함 + 전 tid `reviews/<tid>-[BC]-report.md` 존재 (멀티태스크·standard/strict 허용 — implementing이 이미 FID B·C 수행) — report 는 SubagentStop 훅이 저장한다(판정 SoT = reviews 파일 · report 부재 시 부모 fallback 저장 · 반환에 훅 요약이 없으면 파일 존재와 무관하게 덮어쓰기 저장 · dispatch-log 행은 부모가 기록)
     2. **lite+단일**: `.specops/<FID>/risk-profile.json`의 `effective=lite` · `reductions_allowed`에 `batch-review-skip` · 태스크 1개 · Phase C PASS (기존). 파일 부재·멀티태스크·standard/strict·auth/DB/migration·allowlist 부재는 이 경로 **금지**
   - `batch-state.sh`가 skip-only 경로에서 위 메타를 재검한다.
4. receiving(또는 skip) 후 per-FR security/integration/performance/PR 차단. chain 자동 진행
5. `.specops/<FID>/review-base.sha` · `evidence.md` · (`review-request.md` **또는** `review-skip.md`) **3종 존재** + session-progress FID 섹션의 **`/verify PASS` 줄 존재** 확인 후 queue.md 해당 FR → `IMPL_DONE` 갱신 (**스크립트로만** — 위 Phase 1 스텝 3 주의 참조):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/queue-set-status.sh .specops/$BATCH_ID/queue.md <FR-ID> IMPL_DONE <FID>
   ```
    (FID 를 함께 준다 — Phase 1 에서 FID 칸이 채워지지 않은 batch(이전 버전에서 시작한 batch 포함)도 여기서 채워진다. FID 없이 부르면 FID 칸이 빈 행은 거부된다.)
    (하나라도 없으면 뭉개짐 — IMPL_DONE 금지, 해당 스텝 재실행. batch PR 직전 `batch-state.sh` 가 IMPL_DONE FID 마다 재검 — skip 경로는 메타 조건까지 통과해야 인정)
6. 다음 PLAN_DONE FR 반복

> **HARD GATE**: implementing-ko HARD GATE cap 초과 시에만 사용자 개입 요청. 그 외 실패는 `specops-ko:systematic-debugging-ko`로 처리 후 재개.

### Phase 3 완료 — batch 레벨 통합·E2E·성능 테스트 + batch PR 생성
전 FID IMPL_DONE 확인 후 — **batch-state 하드 스캔** (prose 확인이 아닌 스크립트 판정):

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/batch-state.sh ".specops/$BATCH_ID"
```
- exit 0 → Step A 진행
- `SKIP` 행(시드·공통부)과 requirements 의 placeholder FR 은 batch 대상이 아니다 — 미완·드리프트로 세지 않고 `[제외]` 로 출력된다. 적격 FR 이 전부 `IMPL_DONE` 이면 SKIP 이 있어도 exit 0 이다(`HELD`·`BLOCKED` 는 멈춘 것이라 여전히 미완). **적격 FR 을 SKIP 으로 바꿔 넘기지 않는다** — 분류기(`check-fr-table.sh --classify`)가 batch 대상이라는 FR 의 SKIP 은 미완으로 판정된다. 이번 batch 에서 못 끝내는 FR 은 `HELD` 로 두고 queue 헤더에 사유를 적는다.
- exit 1 (미완·드리프트·중복 목록 출력) → 사용자 확인 게이트: **"미완/드리프트 N건 — 그래도 batch PR 진행? [y/n]"**. `y`=의도적 부분 진행 허용(주권 — queue 헤더에 사유 기록 권장), `n`=중단. `HELD` FR 이 있으면 FR 별 사유·선택지(`dispatch-log.md` 원문)를 함께 보이고 **세 번째 답**을 받는다 — 승인·결정을 주면 그 FR 을 `PLAN_DONE` 으로 되돌려 스텝 1a 부터 다시 돈 뒤 이 스캔으로 돌아온다(스텝 1b). **§auto 무인은 여기서 정지**(목록 출력 + 사용자 입력 대기 — silent 부분 PR 금지)

> **이 스캔은 산문 지시일 뿐 아니라 훅으로도 강제된다** (20260721-batch-pr-teeth). `gh pr create` 시
> `hooks/pretool-governance.sh` 가 최신 `.specops/batch-*/queue.md` 에 `batch-state.sh --gate` 를 자동 실행한다.
> `--gate` 는 기본 모드와 판정 기준이 다르다 — **뭉개짐 신호만** 차단한다(per-FR 산출물 부재·진행기록 부재·라벨 오염).
> 드리프트·미완·중복은 부분 batch 에서 정당하므로 훅은 차단하지 않는다(위 [y/n] 게이트 소관).
> 훅 차단은 **인라인 `SPECOPS_GOVERNANCE_BYPASS` 로 열리지 않는다** — batch PR 은 비가역이라
> security Critical/High 와 동급으로 다룬다. 사용자 주권 탈출구는 세션 env(`export SPECOPS_GOVERNANCE_BYPASS=1`)다.
> 계기: dogfood 20260721 test1 — 이 스캔이 산문에만 있어 호출되지 않았고, 7 FR 이 BATCH_ID 하나로 뭉개진 채 PR 이 나갔다.

> **batch-level 호출 규약**: Step A/B/C 의 skill 은 §batch 감지를 `grep .specops/<FID>/spec.md` 로 **FID-scoped** 수행한다. 오케스트레이터는 batch 의 **대표 FID**(queue.md 의 임의 IMPL_DONE FID — 전 FR spec 이 `**§batch**` 라벨 보유)의 spec.md 를 참조해 호출해야 batch 모드가 발동한다(§batch 부재 스코프로 호출 시 SINGLE 모드 falling back → 단일-batch-PR 불변식 위협). 따라서 아래 `-DONE` signal 의 suffix 는 그 대표 `<FID>` 다(스캔 범위는 batch 전체지만 라벨 판정 기준은 대표 FID).

> **게이트 FAIL 뒤의 복귀 (Step A·B·C 공통)**: 수정은 새 코드다 — 실패한 게이트를 곧장 다시 돌리지 않는다(수정 커밋이 verify·리뷰를 건너뛴다). `specops-ko:systematic-debugging-ko` 로 고친 뒤 ① 수정이 속한 FR(FID)마다 Phase 3 스텝 2(verify)·스텝 3(리뷰)을 다시 돌려 `BATCH-REVIEW-DONE: <FID>` 를 받고 — `review-base.sha` 는 다시 쓰지 않는다(리뷰 diff 가 수정분을 포함해야 한다) ② **Step A(보안)부터** 다시 실행한다 — 어느 Step 이 실패했든 그렇다. 앞서 통과한 Step 의 결과는 수정 전 코드의 것이라, 실패한 Step 부터 이으면 수정분이 보안 스캔을 건너뛴다. 단일 모드의 복귀 경로(각 게이트 SKILL 의 FAIL 분기 — verify → 리뷰 → security → integration → performance)와 같은 순서이고, batch 에서는 리뷰가 끝나면 skill 이 halt 하므로 오케스트레이터가 재진입시킨다.

**Step A: batch 레벨 보안 리뷰 (SAST)**

1. `specops-ko:security-review-ko` 호출 — batch 전체 코드 변경 표면 대상
   - 각 FR의 `.specops/<FID>/spec.md` `§범위` 스캔 → 코드 변경 표면 신호 부재 시 graceful skip
   - 또는 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/security-scan.sh .`로 batch 전체 직접 스캔 (semgrep·gitleaks 미설치 시 graceful skip)
   - `BATCH-SECURITY-DONE: <FID>` 출력 후 오케스트레이터로 제어 반환 (`**§batch**` halt)
   - Critical/High 검출 시 → 위 **게이트 FAIL 뒤의 복귀** (§auto여도 자동 통과 금지)
   - **PASS/SKIP 후 전 FID 전파 (필수)** — skill 은 대표 FID 1곳의 evidence.md 에만 기록하는데, `gh pr create` 의 RELEASE_READY 는 **전 IMPL_DONE FID** 각각에 이 게이트를 요구한다(MISSING → hard deny). **SKIP 근거는 spec.md 섹션명+줄 번호를 인용한다**(예: `"§범위 L12-15 — 통합 표면 없음"`) — 인용이 없으면 스크립트가 기록을 거부한다(RELEASE_READY 가 인용 없는 SKIP 을 차단하므로 여기서 먼저 막는다):
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/record-batch-gate.sh ".specops/$BATCH_ID" security <PASS|SKIP> ["§섹션 L줄 — 사유"]
     ```

**Step B: batch 레벨 통합·E2E 테스트**

2. `specops-ko:integration-test-ko` 호출 — batch 전체 통합 표면 대상
   - 각 FR의 `.specops/<FID>/spec.md` `§범위` 스캔 → **두 표면을 함께** 검출(integration-test-ko Q5 풀스택 — 신호 OR, 둘 다 커버):
     - **통합 표면**(API·DB·서비스 간 호출) → downstream 스택 통합 테스트(supertest/httpx/pg 등)
     - **UI 표면**(화면 렌더·사용자 흐름·클릭/폼/라우팅) → **E2E 위임**: 브라우저 E2E 를 downstream 프로젝트 스택(**Playwright/Cypress 등**)으로 작성·실행(플러그인은 브라우저 인프라 미보유 — execution 은 downstream). `e2e-runner` 에이전트 있으면 선택 활용(없어도 downstream 스택 직접 지시로 graceful — 하드 의존 금지).
   - **두 표면 모두 부재**(순수 데이터 batch·CLI) 시에만 graceful skip. **UI batch 인데 E2E 를 건너뛰면 안 된다** — 화면 있는 batch 는 E2E 가 통합 검증의 본체다(dogfood 20260716: batch 가 API 통합만 보고 UI E2E 를 흐름 밖으로 흘려 사후 수동 보충됨).
   - `BATCH-INTEGRATION-DONE: <FID>` 출력 후 오케스트레이터로 제어 반환 (`**§batch**` halt — performance 자동 chain 차단)
   - FAIL 시 → 위 **게이트 FAIL 뒤의 복귀**
   - **PASS/SKIP 후 전 FID 전파 (필수 — Step A 와 동일 이유)**:
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/record-batch-gate.sh ".specops/$BATCH_ID" integration <PASS|SKIP> ["§섹션 L줄 — 사유"]
     ```

**Step C: batch 레벨 성능 테스트**

3. `specops-ko:performance-test-ko` 호출 — batch 전체 성능 임계값 대상
   - `.specops/memory/requirements.md` `## 3. 비기능 요구사항 (NFR)` + 각 FR spec.md `§NFR` 스캔
   - 성능 임계값 신호 부재 시 graceful skip
   - FAIL 시 → 위 **게이트 FAIL 뒤의 복귀**
   - **본 skill의 PR 게이트 skip** (`**§batch**` 라벨 감지 → `BATCH-PERF-DONE: <FID>` 출력 후 오케스트레이터로 제어 반환)
   - **PASS/SKIP 후 전 FID 전파 (필수 — Step A 와 동일 이유)**:
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/record-batch-gate.sh ".specops/$BATCH_ID" performance <PASS|SKIP> ["§섹션 L줄 — 사유"]
     ```

**Step D: batch PR 생성**

**닫기 전 게이트 현황 확인 (필수)** — Step A/B/C 판정이 전 IMPL_DONE FID 에 전파됐는지 스크립트로 확인한다:

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/record-batch-gate.sh ".specops/$BATCH_ID" status
```
- rc 0 (`BATCH-GATE-STATUS: OK`) → 아래로 진행.
- rc 1 (`INCOMPLETE`) → **닫지 않는다.** `MISSING` 은 그 Step 을 실행하고 전파한다. `SKIP(BARE)` 는 같은 전파 명령을 줄 번호를 인용한 근거로 다시 부르면 보완된다.
- PR 을 만들지 않고 닫는 경우(원격 없는 저장소 · 로컬 병합)에도 **반드시** 돌린다 — batch PR 게이트와 RELEASE_READY 는 `gh pr create` 에서만 발화하므로, 그 경로에서는 이 확인이 유일한 관문이다(실기록 20261008: batch 6건 중 PR 로 닫힌 것은 0건이었고 2건은 전파 없이 닫히거나 멈췄다).

PR 직전 **자동 확정 항목을 집계기로 수집**해 PR 본문·사용자 확인에 포함한다 — `/start-all` 도 Phase 2.5 에서 화면·인터페이스를 **대화 승인 없이** 반영하는 경로가 있고(§auto 여부와 무관하게 `**자동 결정 화면**`·`**자동 결정 인터페이스**` 가 남는다), 수기 집계는 과소보고를 막지 못한다:

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/collect-assumptions.sh ".specops/$BATCH_ID"
```

```bash
git push -u origin "feat/$BATCH_ID"
```
```bash
BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||'); BASE=${BASE:-main}   # 기본 브랜치가 main 이 아닌 repo 대응
gh pr create \
  --base "$BASE" \
  --head "feat/$BATCH_ID" \
  --title "feat: $BATCH_ID 전체 기능 일괄 구현" \
  --body "$(cat <<'EOF'
## Summary
- /start-all로 requirements.md FR 전체 기능 일괄 구현
- batch 레벨 통합·성능 테스트 완료 (또는 graceful skip)

## FR 목록
queue.md 상태 전이 요약 (PENDING→PLAN_DONE→IMPL_DONE) 직접 기재

## Test plan
- [ ] 전 FR verifying-evidence-ko PASS 확인
- [ ] batch 레벨 security-review PASS 또는 SKIP 확인
- [ ] batch 레벨 integration-test (통합 + UI 표면 시 E2E) PASS 또는 SKIP 확인
- [ ] batch 레벨 performance-test PASS 또는 SKIP 확인
- [ ] validate-structure.sh 전 항목 ✅

🤖 Generated with specops-ko /start-all
EOF
)"
```

PR 생성이 **성공하면** 진행 표시를 지운다 — 이 batch 는 끝났고, 남겨두면 이후의 무관한 작업이
끝난 batch 상태로 차단된다(false-block):
```bash
rm -f ".specops/$BATCH_ID/ACTIVE"
```

## 안티패턴

- **requirements.md FR 표 없이 실행** — `/init-project` 먼저 실행해 `requirements.md`에 FR 표 작성 후 `/start-all` 진입
- **foundation 없이 start-all (UI/BE/풀스택/모바일)** — `/start-foundation`으로 `foundation-manifest.md` 채운 뒤 진입. Phase 0 `check-foundation-present` 가 HARD 차단
- **foundation 브랜치 미머지 상태로 start-all** — `feat/<foundation-FID>` 를 main 에 머지한 뒤 진입. Phase 0 `check-foundation-merged` 가 HARD 차단
- **공통 FR을 batch PENDING에 넣기** — `[공통]`/`foundation-fr` 표기 FR 은 SKIP. 구현은 `/start-foundation`만
- **§유형=foundation + §batch hybrid** — 금지. `check-spec-label-compat` FAIL
- **spec 생략 요구** — 각 FR에 대해 specifying-ko → clarifying-ko → planning-ko → decomposing-ko 체인 필수. Phase 1 생략 금지
- **per-FR PR 생성** — Phase 3에서 per-FR PR 생성 금지. `receiving-code-review-ko`가 `BATCH-REVIEW-DONE: <FID>` 를 출력하고 halt함으로써 자동 차단된다. 최종 batch PR 1개 (Phase 3 완료 Step D)만 생성
- **Phase 2·2.5 건너뜀** — batch plan-review·일괄 게이트·화면→IF design-first 필수. 사용자 확인 없이 Phase 3 진입 금지
- **Phase 1에서 §batch plan-reviewer 실행** — DEFER 계약 위반. Phase 2에서 1회만
- **Phase 2 batch plan-review 생략** — Generator↔Evaluator 폐기. digest/[y/n]만으로 Phase 2.5 진입 금지
- **Phase 2에서 전 FID plan 전문 덤프** — `batch-plan-digest.sh` 짧은 표만
- **Phase 1에서 batch Step 5.6 실행** — FR별 api-spec 선갱신 금지. 인터페이스는 Phase 2.5-B(화면 직후)
- **foundation-baseline 마커 안을 Phase 2.5-B에서 갱신** — 금지. `check-foundation-if-baseline` FAIL. baseline은 `/start-foundation`·`/design-interface`만
- **foundation-shell screens를 Phase 2.5-A에서 재작성** — 금지. `check-foundation-shell-baseline` FAIL. 셸은 `/start-foundation`·`/design-screen`(allowlist)만
- **Phase 2.5-D 생략** — 화면 또는 IF 산출이 있으면 `design-reviewer-ko` 필수. 부모 self-review로 대체 금지
- **design-review FAIL을 무시하고 구현** — PASS(또는 §auto Important-only cap 기록) 없이 Phase 3 진입 금지. **Critical cap은 §auto여도 정지**
- **skill 미호출 인라인 뭉개기** — 오케스트레이터가 spec~verify 산출물을 heredoc 으로 직접 쓰는 것 금지 (R-3 스킬 선언 투명성 위반 + session-progress 줄 0 → `batch-state.sh` `[진행기록 누락]` 이 batch PR 직전 차단). 각 단계는 Skill 도구로 **실호출**한다 — dogfood 20260716: 4 FID spec→tasks 가 3분 만에 인라인 생성되어 진행 흔적이 전무했다
- **deny 를 무사유 BYPASS 로 정면 돌파** — pretool deny 를 만나면 우선 `run-verification.sh <FID>` 를 실행해 정직하게 연다. 우회가 정당한 경우(verify 선행 단계의 중간 커밋 등)에도 인라인 BYPASS 는 `SPECOPS_BYPASS_REASON='<사유>'` 병기 필수 — 무사유는 pretool 이 deny 한다

## 참조

- `skills/specifying-ko/SKILL.md` — batch 분기 (Step 0 git-branch-create skip, §batch 라벨)
- `skills/decomposing-ko/SKILL.md` — Phase 1 정지점 (BATCH-PHASE1-DONE)
- `commands/start-foundation.md` — 미러링 패턴
- `commands/start.md` — 단일 기능 진입 슬래시
- `templates/requirements.md` — FR 표 포맷 참조

---

*specops-ko v2.18.0 · 2026-10-09 · FR 보류 신호 수신(`BATCH-FR-HELD`) · 게이트 FAIL 뒤의 복귀 경로*
