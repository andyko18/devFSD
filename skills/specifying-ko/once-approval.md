# 질문 묶음과 승인 묶음 (`§일괄` — specifying-ko 보조 문서)

> `skills/specifying-ko/SKILL.md` Step 1 의 §일괄 판정, `skills/analyzing-ko/SKILL.md` Step 7, `skills/clarifying-ko/SKILL.md` `## §일괄 모드` 가 이 문서를 가리킨다.
> 적용: `/start`·`/maintain`·`/start-lite`·`/maintain-lite` 와 자연어 진입의 기본. `--step`(`<!-- step: true -->`)이면 적용하지 않고 각 skill 의 기존 동작대로 단계마다 확인한다. `§auto`·`§batch`·foundation 은 해당 없음.
> `/start-all` 은 `commands/start-all.md` 「기본 동작과 `--step`」(0번) — 질문 묶음 = Phase 1a·1c · 승인 묶음 = Phase 2.5-E.
> 원칙: 사람에게는 **질문 묶음 최대 2회와 승인 묶음 1회**만 받고, 승인 뒤에는 PR 게이트까지 묻지 않는다. 승인 생략은 확인 생략이지 검증 생략이 아니다 — TDD·B/C·verify·보안·R-1/R-2 는 그대로다.

## 1. 질문 묶음

- **최대 2회**: 1회째는 specifying Step 3(설계 전 명확화), 2회째는 clarifying(spec 작성 뒤 BLOCKING·DESIRABLE). lite·trivial 은 clarifying 이 없으므로 1회째뿐이다.
- 회마다 **많아야 4개**를 한 메시지로 묻는다(AskUserQuestion 이 있으면 그것으로). 질문마다 선택지와 영향 한 줄, **추천 선택지와 근거 한 줄을 맨 앞에** 둔다.
- 1회째에 넣을 것: 목적·제약·성공 기준 · 유지보수 오분류 확인(기존 코드를 실제로 고칠 때만) · 신규 trivial 축약 제안(해당 시).
- 묶음에 넣지 못한 질문은 묻지 않고 best-guess 로 정해 `(ASSUMED)`(intent·spec) 또는 `status: ASSUMED`(clarifications)로 적는다. 승인 묶음과 PR 게이트에 보인다.
- 질문할 것이 없으면 그 회는 건너뛴다.

## 2. 승인 묶음

위치: 정상 경로는 clarifying-ko 끝 · `§lite`·`§유형: trivial` 단축 경로는 specifying-ko 의 사용자 검토 게이트 자리. 한 메시지에 아래를 **빠짐없이** 싣는다(해당 없으면 "해당 없음" 1줄):

1. **intent** — 문제 · 기대 결과 (경로 `.specops/<FID>/intent.md`)
2. **분석 요약** (유지보수 계열) — 변경 대상 · 보존할 동작 · 회귀 위험 (`current-state.md`·`impact-analysis.md`)
3. **설계 요지** — 고른 접근과 **버린 대안**(짧은 이유)
4. **spec·AC** — 경로와 AC 마다 한 줄(clarify 가 더할 AC 포함)
5. **화면 경로** — 만든 `screens/{name}.md`·`.html` 목록(모두 만든 뒤)
6. **IF 변경** — `api-spec.md`·`data-model.md` 에서 바꾼 행 · 계약 칸 점검 `WARN` · memory 문서 생성 여부
7. **질문 답** — 질문 묶음의 답과 `ASSUMED` 로 정한 것
8. **승인 뒤 자동 진행** — clarify(남았으면) → plan(전문가 패스·plan-reviewer) → decompose → implement(B/C) → verify → security → integration → performance 를 묻지 않고 진행한다 · 실행 방식은 서브에이전트 주도 · **병렬 worktree** 를 쓸 수 있다
9. **그래도 멈추는 곳** — 비가역 작업(`irreversible`·NEEDS_APPROVAL) · 보안 Critical/High · plan-reviewer Critical · B/C 한도 초과 뒤 남은 Critical · NEEDS_DISCUSSION · 실행 환경 없는 게이트 · FID 10태스크 이상 분할 · verify 재시도 뒤 남은 실패 · PR

끝 문장: "이대로 구현까지 진행할까요? [y/수정]"

## 3. 수정 요청과 기록

- 수정 요청이 오면 고친 뒤 승인 묶음을 **다시 제시**한다(질문 묶음 횟수에 넣지 않는다).
- 승인되면: `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dev-decision.sh add <FID> approval "승인 묶음 승인" "<요지 1줄>"` · intent `Status: accepted` · `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /approve 완료 "승인 묶음"`.
- 승인 뒤 범위가 바뀌는 일(lite·trivial 규모 초과 승격 등)이 생기면 clarifying 의 승인 묶음을 한 번 더 받는다.

## 4. 승인 뒤 각 skill 의 동작

| skill | `§일괄` 동작 |
|---|---|
| planning-ko `## 실행 전환` | 묻지 않고 서브에이전트 주도 |
| using-git-worktrees-ko 생성 동의 | 승인 묶음이 동의 |
| decomposing-ko lite·trivial 규모 초과 | 묻지 않고 정상 경로 승격(dev-decision `order`) |
| verifying-evidence-ko fix_loop 상한 | §auto 와 같은 재시도 1회 뒤 남으면 사용자에게 |
| performance-test-ko PR 게이트 | 단일 모드 게이트 + `ASSUMED` 항목 표시 |
