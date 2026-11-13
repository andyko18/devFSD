---
name: basic
disable-model-invocation: true
description: "[단일·기본] 기본 경로 직접 지정 — spec 1장 승인 → 주 세션 직접 구현 → 스펙·코드 리뷰 + 보안 스캔 동시 1회 → 검증 1회 → PR (`/start`·`/maintain` 이 위험 신호가 없으면 자동으로 고르는 경로)"
triggers:
  - "/basic"
mode: ask
specops_version: 4.0.7
specops_layer: Lifecycle
reference_upstream: specops-ko 독자 추가 (commands/start.md 와 commands/quick-fix.md 사이의 기본 경로)
---

# /basic <만들거나 고칠 것 한 줄>

## 목적

`/quick-fix` 로는 크고 풀 경로로는 무거운 **보통 작업**을 빠르게 끝낸다. **`/start`·`/maintain`·자연어 진입은 위험 신호가 없으면 이 경로를 자동으로 고른다**(`basic-path.sh route`) — `/basic` 은 이 경로를 직접 지정하는 명령이다. 신규·유지보수를 가리지 않는다(유지보수는 아래 1번의 `maintain`).

문서는 **spec 1장**(목표·범위·수용 기준)뿐이다. plan 문서·태스크 분해·구현자 dispatch·인계 문서를 만들지 않고 **주 세션이 직접 구현**한다. 남기는 검증은 넷이다 — 테스트 먼저(TDD) · 스펙 리뷰와 코드 리뷰 각 1회 · 보안 스캔 1회 · 검증 러너 1회(커밋·PR 훅은 `/start` 와 같은 조건으로 연다).

근거(20261112 실측): 풀 경로 기계 시간 149~157분 · lite 53분 · 이 경로 42분(원인 조사 15분 포함)과 12분 — 두 건 모두 리뷰 Critical 0 · CI 통과. **표본 2건**이고 자동 분기·승격의 실제 주행은 아직 재지 않았다.

## 세 갈래

| 갈래 | 기준 | 명령 |
|---|---|---|
| quick | 구현 파일 2개·20줄 이하 · 화면 구조 변경 없음 (`scripts/_internal/quick-scope.sh` 상한) | `/quick-fix` |
| **기본** | 아래 풀 신호가 없는 나머지 | `/start` · `/maintain` 이 자동으로 (직접 지정 `/basic`) |
| 풀 | 인증·권한 변경 · DB 스키마 변경 · 데이터 삭제·이관 · 기존 API 응답 형태 변경 · 되돌릴 수 없는 외부 작업 | `/start` · `/maintain` 이 자동으로 (무조건 풀 `--full`) |

갈래는 선언이 아니라 스크립트가 판정한다(`scripts/basic-path.sh` — 시작·승인·봉인 세 번). **애매하면 무거운 쪽**이고, 작업 중에 풀 신호가 나오면(종료 코드 3) 멈추고 안내만 하지 않고 **풀 경로로 올린다** — 만든 spec·코드를 버리지 않고 이어 간다(아래 「풀 경로로 올리기」).

## Process

FID 는 `YYYYMMDD-<kebab-slug>` (인자에서 슬러그를 뽑는다 — 정식 경로와 같은 규칙).

1. **시작** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh start <FID> "<요청 한 줄>" [maintain]`
   요청 문장으로 갈래를 판정하고, FID 폴더·진행 기록·spec 골격(`.specops/<FID>/spec.md`)을 만든다. 기본 브랜치 위면 브랜치를 만든다.
   - **유지보수**(`/maintain` 에서 왔거나 이미 있는 코드·동작을 고치는 요청)면 끝에 `maintain` 을 붙인다 — 골격에 `**§유형**: 유지보수` · `### 현재 동작과 영향` 절 · `### AC-R-1`(기존 동작 유지)이 더해지고 4번 승인이 셋을 검사한다. 분석 단계(`analyzing-ko`)는 돌리지 않는다 — 2번에서 코드를 읽으며 그 절을 채운다.
   - 종료 코드 **3** = 풀 신호 → 만든 것이 없다. "위험 신호 <무엇> — 풀 경로로 진행" 1줄을 알리고 풀 경로로 들어간다(신규 `devfsd:specifying-ko` · 유지보수 `devfsd:analyzing-ko` 에 `<!-- entry: maintain -->` 첫 줄 — `commands/start.md`·`commands/maintain.md` 의 풀 경로 절차).
2. **spec 1장** — 코드를 읽고 골격을 채운다: 목표 · 범위(범위 밖 · 화면 변경) · 수용 기준(`### AC-n:` 블록 — Given·When·Then·우선순위) · 비기능 요구. 질문이 있으면 **많아야 4개를 한 번에** 묻고(추천 선택지 먼저), 나머지는 추천안으로 정해 spec 에 `(ASSUMED)` 로 적는다.
3. **화면 설계 확인 범위** — 화면을 건드리면 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh design-scope <고치는 화면 수> [new|flow]` 의 답을 따른다. 화면 변경량은 갈래를 바꾸지 않고 **설계 확인 범위만** 정한다.
   - `DESIGN: none` (문구·스타일만) → 설계 확인 없음.
   - `DESIGN: update` (기존 화면 1~2개 일부 수정) → 구현과 함께 `screens/<name>.md` 의 해당 부분을 갱신한다.
   - `DESIGN: approve` (화면 3개 이상 · 새 화면(`new`) · 흐름 변경(`flow`)) → 구현 전에 화면 스펙·목업을 만들고(`/design-screen`·`/design-screens` 의 절차) 4번 승인에 그 경로를 함께 싣는다.
   - API·테이블 계약을 바꾸는 작업은 풀 신호다(1번에서 걸린다). 걸리지 않았는데 `api-spec.md`·`data-model.md` 를 고쳐야 하면(2~5번 어디서든) 그 파일을 고치지 말고 풀 경로로 올린다(「풀 경로로 올리기」).
4. **승인 1회** — spec 경로와 요지(목표 · 범위 · AC 마다 한 줄 · `ASSUMED` 로 정한 것 · 화면 설계 경로)를 한 메시지로 보이고 "이대로 구현까지 진행할까요? [y/수정]" 을 묻는다. 승인되면:
   `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh approve <FID>`
   spec 절을 확인하고, spec 본문으로 갈래를 다시 판정하고, 수용 기준 절을 `acceptance-criteria.md` 로 옮긴다(검증 러너·스펙 리뷰어가 읽는 계약 파일). 종료 코드 3 = 풀 신호 → 「풀 경로로 올리기」(spec 을 쓰다가 풀 신호를 알아챘으면 승인을 묻기 전에 올린다 — 승인 묶음은 풀 경로 형식으로 한 번만 받는다). 승인 뒤에는 PR 까지 묻지 않는다(비가역 작업·리뷰어 `NEEDS_DISCUSSION`·고치지 못한 Critical 은 멈춘다).
5. **직접 구현** — 주 세션이 구현한다(서브에이전트에게 구현을 맡기지 않는다). 수용 기준마다 **실패하는 테스트를 먼저** 쓰고 실패를 확인한 뒤 고친다(`devfsd:tdd-ko`). 구현 중에는 **관련 테스트만** 돌린다. 통과를 확인한 명령은 그 뒤로 파일을 바꾸지 않았으면 다시 돌리지 않는다(앞선 출력을 쓴다). 커밋은 7번 뒤에 한다.
6. **리뷰 1회 (동시)** — 먼저 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh review <FID>` 로 진행 기록(구현 완료 · 리뷰 진행)을 남긴다(관제판 단계 표시용 — 판정은 없다). 그다음 한 메시지에서 함께 보낸다:
   - `devfsd:spec-reviewer-ko` — FID · tid `T1` · `spec.md`·`acceptance-criteria.md` 경로 · 리뷰 대상 `git diff <base>...HEAD` + 작업 트리 변경.
   - `devfsd:code-reviewer-ko` — 같은 대상 · `병렬 dispatch: yes (B 판정 대기)`.
   - 보안 스캔 — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/security-scan.sh <변경 파일…>` 을 백그라운드(Bash `run_in_background`)로.
   - 두 리뷰어 프롬프트에 `<<<REVIEW fid=<FID> tid=T1 phase=<B|C> verdict=…>>>` 보고 형식(`skills/implementing-ko/SKILL.md` 「부모 dispatch 프롬프트 규약」)과 실행 상한(대상 테스트 실행 B 2회·C 3회 이내 · 전체 스위트 실행 금지 · 되돌려-관찰은 임시 복사본에서)을 적는다. 저장 훅이 `.specops/<FID>/reviews/T1-B-report.md`·`T1-C-report.md` 로 옮긴다.
   - 리뷰어가 도는 동안 주 세션은 **PR 본문을 준비**한다(기다리기만 하지 않는다).
   - **지적 처리**: 스펙 미충족·Critical·보안 Critical/High 는 주 세션이 고치고 **관련 테스트를 다시 돌린다 — 재리뷰는 없다**. Important 는 이번 변경이 만든 결함이면 고치고 아니면 PR 본문 "넘긴 것" 에 적는다. 고칠 수 없는 Critical 이나 `NEEDS_DISCUSSION` 은 멈추고 사용자에게 묻는다.
7. **봉인과 검증 1회**
   - **검증 명령 고르기** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh related` 의 답을 `test_command` 로 쓴다.
     - `RELATED: <명령>` → 그 명령 그대로(변경 파일이 닿는 스위트만 돈다). 스위트 매핑(`scripts/tests/run-related.sh`)이 있는 저장소에서만 나온다.
     - `RELATED: none — <사유>` → 종전대로 **프로젝트의 테스트 명령 전체**(테스트 스크립트 · `pytest` · `npm test` 등 검증 러너가 받는 형태). 매핑이 없는 저장소, 관련 스위트를 특정할 수 없는 변경, 너무 넓게 닿는 변경이 여기다. `none — …` 줄 자체는 명령이 아니다 — seal 은 검증 러너가 받지 않는 형식의 문자열을 거부한다(rc 1).
   - `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh seal <FID> "<test_command>"` — 변경 파일로 갈래를 다시 판정하고, 1-태스크 문서(`tasks.md`)와 리뷰 감사 행(`dispatch-log.md`)을 만든다. 관련 스위트 명령에 지금 변경이 닿는 스위트가 빠져 있으면 받지 않는다(`related` 를 다시 실행). 종료 코드 **3** = 풀 신호 → 「풀 경로로 올리기」 · **4** = 리뷰 보고서 없음(6번으로).
   - `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/run-verification.sh <FID>` 를 **포그라운드**로 실행한다(Bash `timeout` 명시). `VERIFY: PASS` 가 나와야 한다.
   - **전체 스위트는 여기서 돌리지 않는다** — 관련 스위트로 검증했으면 전체는 PR 의 CI 가 맡는다(작업 브랜치의 push 전 게이트 `pre-push` 는 같은 관련 스위트로 판정하고, 같은 트리의 통과 기록이 있으면 건너뛴다 — 기본 브랜치·태그 push 는 전체다). push 전 게이트도 CI 도 없는 저장소는 `related` 가 `none` 을 내므로 위에서 이미 전체를 돌렸다.
   - 통과하면 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /verify PASS "evidence.md, AC N/N (/basic)"`. 보안 스캔 결과를 `evidence.md` 에 `## /security-review — <시각>` 절(결과·근거)로 남긴다.
   - 실패하면 고치고 다시 seal → 검증이다. 세 번 실패하면 `devfsd:systematic-debugging-ko`.
8. **커밋 · PR** — `git add <파일…>` 과 `git commit` 을 따로 실행한다. 커밋·PR 은 `/start` 와 같은 훅(R-1·R-2)이 본다 — 7번의 검증 실행 출력과 진행 기록이 있어야 열린다. 막히면 우회하지 않고 사유를 고친다. PR 을 만들지 묻고(y/n), 만들면 본문에 요약 · 테스트 계획 · 리뷰어가 찾았지만 넘긴 것 · **돌리지 않은 게이트**(아래)를 싣는다.
9. **마무리** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh done <FID> "<한 줄 요약>"`

## 풀 경로로 올리기 (승격)

1번 뒤 어느 지점에서든 풀 신호가 나오면(approve·seal 의 종료 코드 3 · `api-spec.md`·`data-model.md` 를 고쳐야 함) 멈추고 안내만 하지 않는다:

1. `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh promote <FID> "<사유 한 줄>"` — spec 1장·리뷰 보고서·1-태스크 문서를 `.specops/<FID>/basic-draft/` 로 보존하고 진행 기록(`/full 승격`)을 남긴다. 코드 변경은 작업 트리에 그대로 둔다(커밋·되돌리기 금지).
2. `NOTICE:` 줄을 사용자에게 그대로 보인다(1줄 — "<사유> — 풀 경로로 올림.").
3. `PROCEDURE:` 줄의 파일(`skills/specifying-ko/basic-promote.md`)을 Read 하고, `NEXT:` 의 skill 을 `ARGS:` 줄들(순서 그대로) + 원래 요청 한 줄로 호출한다. 같은 FID·같은 브랜치로 풀 경로가 이어진다 — spec 은 풀 형식으로 다시 쓰이고 clarify → plan → 분해 → 구현(이미 쓴 코드에서 시작) → 리뷰·게이트가 돈다.

| 걸린 지점 | 그때 있는 것 | 풀 경로에서 이어지는 곳 |
|---|---|---|
| 1번 start | 없음 | 처음부터(승격 아님 — 풀 경로 진입) |
| 2~4번 (spec · approve) | spec 1장 | spec 을 풀 형식으로 → 승인 묶음(풀 형식) → clarify → plan |
| 5번 (구현 중 계약 문서 필요) · 7번 seal | spec 1장 + 코드 (+ 리뷰 보고서) | 위와 같고, plan 이 "이미 작성된 코드" 를 싣고 plan 리뷰·구현 뒤 스펙·코드 리뷰가 그 코드를 본다. 세션 분리는 끈다 |

## 이 경로가 하지 않는 것

- **통합·성능 게이트** — 돌리지 않는다. `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/gate-preflight.sh <FID>` 가 `GATE integration APPLY` 나 `GATE performance APPLY` 를 내면 PR 본문에 "미실행 게이트" 로 적는다(성능 임계값이 수용 기준이면 풀 경로가 맞다).
- **plan 리뷰 · 전문가 패스(DB·구조·API·보안·테스트 설계)** — 없다. 그 검토가 필요한 작업이 풀 신호의 대상이다.
- **재리뷰** — 리뷰는 한 번이다. 고친 것은 관련 테스트와 검증 러너가 본다.
- **검증 단계의 전체 스위트** — 관련 스위트 명령(`RELATED: <명령>`)으로 검증한 작업은 커밋 시점에 전체 스위트가 돌지 않은 상태다. 전체는 PR 의 CI 가 돌린다(작업 브랜치의 push 전 게이트는 관련 스위트만 본다) — 거기서 떨어지면 고치고 다시 seal → 검증이다.

## 갈래별 차이

| | `/quick-fix` | 기본 경로 | 풀 경로 |
|---|---|---|---|
| 문서 | 없음(자동 태스크 문서) | spec 1장 | intent · spec · AC · clarify · plan · tasks · 인계 |
| 승인 대기 | 없음 | 1회 | 질문 묶음 최대 2회 + 승인 1회 |
| 구현 | 주 세션 | 주 세션 | 구현자 서브에이전트 |
| 리뷰 | 코드 리뷰 | 스펙 + 코드 + 보안 스캔 (동시 1회) | plan 리뷰 · 전문가 · 스펙 + 코드 · 게이트 3종 |
| 크기·위험 상한 | 파일 2·20줄 (훅) | 풀 신호 없음 (스크립트 3회) | 없음 |
| 끝나는 지점 | 커밋 | PR | PR |

## 안티패턴

- **모델이 갈래를 고르기** — "가벼워 보인다"·"적당히 해줘" 로 고르지 않는다. `/start`·`/maintain`·자연어 진입의 갈래는 `basic-path.sh route` 의 답이고, 사용자가 뒤집는 방법은 `--full`(풀)과 `/basic`(기본) 둘뿐이다.
- **풀 신호를 피하려고 spec 문구를 바꾸기** — 신호 낱말을 지우는 것이 아니라 풀 경로로 간다.
- **구현을 서브에이전트에 맡기기** — 그러면 인계 문서가 필요해지고 이 경로의 이점이 사라진다.
- **리뷰 생략 · 검증 생략** — 봉인이 리뷰 보고서를, 훅이 검증 실행 출력을 요구한다. 우회하지 않는다.
- **무인 변형** — 없다.

## 참조

- `scripts/basic-path.sh` — route · lane · start · approve · review · related · seal · promote · design-scope · done
- `skills/specifying-ko/basic-promote.md` — 풀 경로로 올린 뒤의 절차
- `scripts/tests/run-related.sh` — 변경 파일이 닿는 스위트 고르기(`--list`)·실행 (스위트 매핑이 있는 저장소)
- `templates/spec-basic.md` — spec 1장 골격
- `scripts/_internal/risk-profile.sh` — 영문 위험 신호 판정(`rp::detect_strict_signals`)
- `commands/quick-fix.md` · `commands/start.md` · `commands/maintain.md` — 이웃 갈래

---

*specops-ko v3.1.33 · 2026-11-12 · 기본 경로 (spec 1장 · 주 세션 구현 · 리뷰 1회 · 검증 1회)*
