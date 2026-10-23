# 개발 구간 무질문 정책 (implementing-ko 보조 문서)

> `skills/implementing-ko/SKILL.md` `## 개발 구간 무질문` 에서 참조. wave loop 에 들어가기 **직전에** 한 번 읽는다.
> 적용 구간: **구현 시작 ~ PR 게이트 직전** (implementing · verify · 리뷰 · security · integration · performance). 설계 구간(analyze · specify · clarify · plan)의 질의응답은 그대로다.

## 원칙

질문은 설계 구간에서 끝낸다. 개발 구간에서는 **묻지 않고 기본값으로 진행**하고, 정한 것을 기록해 **끝에 한 번** 보고한다.

- 기록: `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dev-decision.sh add <FID> <종류> "<결정>" "<근거>"` — 묻지 않고 정할 때마다 1줄. 기록하지 않은 결정은 사용자에게 보이지 않는다.
- 끝 보고: PR 게이트가 `dev-decision.sh show <FID>` 를 그대로 보여 준다(`performance-test-ko`). batch 는 `collect-assumptions.sh` 가 FR 별로 모은다.

근거(실측 20261008, 하류 3개 프로젝트의 개발 중 질문 40건): 플러그인이 강제로 멈춘 것은 7건이고 나머지는 세션이 스스로 물었다 — 범위 밖 발견 15 · "계속할까/어느 순서" 8 · 외부 작업 승인 4 · 리뷰 지적 처리 3. 대부분 추천안이 있었고 그 추천안이 선택됐다.

## 1. 시작 전 — 알려진 외부 작업은 한 번에 승인받는다

wave loop 전에 아래 태스크를 모은다:

- DAG YAML 의 표지 — `grep -nE 'irreversible:[[:space:]]*true|^[[:space:]]*external:' .specops/<FID>/tasks.md` (`external: "<무엇을 어디에>"` 는 `decomposing-ko` 가 붙인다)
- 표지가 없어도 스텝 본문에 repo 밖 흔적이 보이는 태스크 — 실 DB 쓰기·적재, 외부 API 호출(과금·호출 한도), 배포, 원격 리소스 생성·삭제

표지와 훑기는 **앞단**이다. 여기서 빠진 것은 구현자가 실행 직전에 `NEEDS_APPROVAL` 로 잡는다(`agents/implementer-ko.md` — repo 밖 흔적은 승인 기록 없이는 실행하지 않는다). 두 층 중 하나만 믿지 않는다.

1건 이상이면 **질문 1회**로 묶어 묻는다: 태스크별로 무엇을·어디에·되돌리는 방법을 적는다. 승인된 태스크마다 `.specops/<FID>/dispatch/<task-id>-approval.md` 에 1줄(`<ts> 사용자 사전 승인: <작업 요약>`)을 남기고 dispatch 프롬프트에 그 **경로**를 준다 — 구현자는 승인 범위 안에서 `NEEDS_APPROVAL` 없이 진행한다. `dev-decision.sh add <FID> approval …` 로도 남긴다.

- 승인받지 못한 태스크와 **그 태스크에 의존하는 태스크**(`depends_on`)는 dispatch 하지 않고 끝 보고에 `skip` 으로 남긴다. 그 때문에 AC 가 비면 verify 가 FAIL 한다 — 숨기지 않는다. 이 FAIL 은 fix_loop 로 다시 시도하지 않는다(사용자가 거부한 일을 되묻게 된다): "사용자 거부로 미구현: <task-id> · 빈 AC" 를 보고하고 멈춘다.
- 사전 승인된 태스크는 그 태스크의 Step 0(승인 요청)을 다시 묻지 않는다 — 승인 기록이 그 답이다.
- `§auto` 는 종전대로 태스크 위치에서 `AUTO-HARD-GATE` 다. `§batch` 는 사용자 채널이 없다 — `BATCH-FR-HELD: <FID>` 를 내고 그 FR 을 halt 한다(`needs-approval.md` 4항).
- 외부 적재 태스크에 `irreversible: true` 를 **붙이지 않는다** — 그 필드는 위험도 판정이 strict 신호로 읽는다. 되돌릴 수 없는 작업에만 쓴다.

## 2. 진행 중 — 묻지 않고 정하는 것

| 상황 | 기본 동작 | 기록 종류 |
|---|---|---|
| "계속할까요?"·다음 단계 확인 | **묻지 않는다.** chain 의 다음 단계로 간다 | (기록 불요) |
| 순서·진행 방식 선택 (무엇을 먼저) | 추천안으로 정한다 | `order` |
| 리뷰어의 Important — **이번 FID 가 만들거나 고친 코드의 결함**이고 AC·spec 을 바꾸지 않아도 된다 | 고친다 — 수정 라운드 1회에 모아 재dispatch 하고 **재리뷰를 거친다**(직렬 B→C · 리뷰 재시도 cap 을 소모한다) | `fixed` |
| 리뷰어의 Important — 이번 FID **이전부터 있던 결함**이거나, 고치려면 **AC·spec 문언을 바꿔야** 한다 | 고치지 않는다. 다음 작업으로 넘긴다 | `backlog` |
| 구현 중 발견한 범위 밖 요구·설계 결정 | 위 두 줄과 같은 기준 — 계약 안이면 처리, 계약 밖이면 넘긴다 | `fixed`/`backlog` |
| 리뷰 재시도 cap 소진 뒤 Important 만 남음 | 추가 라운드 없이 넘긴다 | `backlog` |
| 게이트 적용성 판정 — 해당 표면이 없다(통합·성능·보안 게이트의 graceful skip) | 근거를 evidence 에 적고 SKIP | (게이트가 evidence 에 남긴다) |
| Suggestion | 기록하지 않는다(리뷰 리포트에 남아 있다) | — |

**이번 FID 의 것인가**는 위치로 판정한다 — 지적된 줄이 이 브랜치가 추가·수정한 줄(`git diff <base>...HEAD`)이면 이번 FID 의 것이다. 판정이 애매하면 고치는 쪽이다.

**넘길 수 없는 것** — 출처가 기존 코드여도 `backlog` 대상이 아니다: Phase B FAIL(스펙 미충족) · 리뷰어의 Critical · 보안 스캔의 Critical/High(`security-review-ko` — 1건이라도 chain 차단) · verify FAIL. 이들은 각 skill 의 수정 루프를 타고, 끝내 안 풀리면 §3 으로 멈춘다.

**기준은 승인받은 계약이다.** 사용자가 승인한 AC·spec 안의 일은 묻지 않고 끝낸다. 그 밖의 것은 **묻지 않고 만들지 않는다** — 좋은 제안이어도 넘긴다. `backlog` 로 넘긴 것은 "미해결 방치"가 아니라 기록된 결정이다(레드 플래그 「미해결 이슈를 두고 진행」의 대상이 아니다). 넘길 때는 리뷰어의 증거(파일:줄·재현)를 근거에 옮겨 다음 작업이 바로 착수할 수 있게 한다. 설계 계약(§6 — 화면·API·테이블 설계)도 같다: 임의로 벗어나지 않고, 계약을 바꿔야만 구현할 수 있으면 BLOCKED 4(플랜이 틀렸다)로 올린다.

**기다리며 턴을 끝낼 때는 질문으로 끝내지 않는다.** 서브에이전트·백그라운드 명령이 도는 동안 턴을 끝내야 하면 무엇을 기다리는지 1줄만 쓴다 — 끝나면 알림이 다음 턴을 연다(사용자 입력이 필요 없다). "진행할까요?"·"결과가 나오면 알려 드릴까요?"로 끝내면 사람이 "진행해"를 쳐야 이어진다(20261023 측정: 구현 단계 사람 대기 1537분 · 무정보 프롬프트 26%).

## 3. 그래도 멈추는 것

| 상황 | 처리 |
|---|---|
| **예상 못 한 비가역 작업·repo 밖 흔적** — 구현자가 `NEEDS_APPROVAL` 반환(사전 승인 범위 밖) | 종전대로 즉시 묻는다 — `needs-approval.md`. 끝에 알리면 이미 실행된 뒤다 |
| **Critical 미해결** — Phase B FAIL 또는 Phase C `NEEDS_FIX` 가 cap 과 전역 재시도 1회 뒤에도 남음 | `HARD-GATE` 로 멈춘다 |
| 리뷰어 판정 `NEEDS_DISCUSSION` | 선택지를 그대로 제시하고 판단을 기다린다(`§auto` 도 자동 선택 금지) |
| 보안 스캔 Critical/High 가 수정 루프 뒤에도 남음 | `security-review-ko` 의 chain 차단 그대로 |
| 표면은 있는데 **실행 환경이 없어** 통합·성능·보안 게이트를 돌릴 수 없다 | 각 게이트 skill 의 질문 그대로(환경 설정 후 재실행 / skip) — 조용히 SKIP 하면 검증되지 않은 채 PR 로 간다 |
| 플랜 자체가 틀렸다(BLOCKED 4) · verify fix_loop 상한 초과 · `systematic-debugging-ko` 의 3회 이상 픽스 실패 | 종전 에스컬레이션 |

멈출 때는 한 번에 묻는다 — 같은 시점에 걸린 결정을 모아 질문 1회로 낸다.

## 4. 끝 — 한 번에 보고한다

PR 게이트 직전에 `dev-decision.sh show <FID>` 출력을 **줄이지 않고** 보여 준 뒤 PR 생성 여부를 묻는다. `backlog` 줄은 PR 본문에도 넣는다(`show <FID> --backlog`) — 리뷰어가 찾았지만 이번에 고치지 않은 것이 PR 을 보는 사람에게도 보여야 한다.
