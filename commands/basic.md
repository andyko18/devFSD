---
name: basic
disable-model-invocation: true
description: "[단일·기본] 기본 경로 직접 지정 — spec 1장 승인 → 주 세션 직접 구현 → 스펙·코드 리뷰 + 보안 스캔 동시 1회 → 검증 1회 → PR (`/start`·`/maintain` 이 위험 신호가 없으면 자동으로 고르는 경로)"
triggers:
  - "/basic"
mode: ask
specops_version: 4.0.10
specops_layer: Lifecycle
reference_upstream: specops-ko 독자 추가 (commands/start.md 와 commands/quick-fix.md 사이의 기본 경로)
---

# /basic <만들거나 고칠 것 한 줄>

## 목적

`/quick-fix` 로는 크고 풀 경로로는 무거운 **보통 작업**을 빠르게 끝낸다. **`/start`·`/maintain`·자연어 진입은 위험 신호가 없으면 이 경로를 자동으로 고른다**(`basic-path.sh route`) — `/basic` 은 이 경로를 직접 지정하는 명령이다. 신규·유지보수를 가리지 않는다(유지보수는 아래 1번의 `maintain`).

문서는 **spec 1장**(목표·범위·수용 기준)이 기본이고, 작업에 따라 **켜지는 단계**가 있다(20261114 통합 절차 — 아래 「켜지는 단계」): 위험 신호가 걸린 유지보수는 분석 문서, 태스크 2개 이상이거나 위험 신호가 있으면 결정만 적은 계획, 걸린 신호마다 전문가 1종. 태스크 분해 문서·구현자 dispatch·인계 문서는 만들지 않고 **주 세션이 직접 구현**한다. 남기는 검증은 넷이다 — 테스트 먼저(TDD) · 스펙 리뷰와 코드 리뷰 각 1회 · 보안 스캔 1회 · 검증 러너 1회(커밋·PR 훅은 `/start` 와 같은 조건으로 연다).

근거(20261112 실측): 풀 경로 기계 시간 149~157분 · lite 53분 · 이 경로 42분(원인 조사 15분 포함)과 12분 — 두 건 모두 리뷰 Critical 0 · CI 통과. **표본 2건**이고 자동 분기·승격의 실제 주행은 아직 재지 않았다.

## 세 갈래

| 갈래 | 기준 | 명령 |
|---|---|---|
| quick | 구현 파일 2개·20줄 이하 · 화면 구조 변경 없음 (`scripts/_internal/quick-scope.sh` 상한) | `/quick-fix` |
| **기본** | 아래 풀 조건이 아닌 나머지 — 가벼운 위험 신호(인증·권한 · DB 스키마 · API 계약 등)는 이 경로 안에서 단계를 켠다 | `/start` · `/maintain` 이 자동으로 (직접 지정 `/basic`) |
| 풀 | 데이터 삭제·이관 · 되돌릴 수 없는 외부 작업 · 결제·개인정보 · 태스크 4개 이상 · 파일 삭제(`rm -rf`)·배포·인프라 변경 · `--full` · `--step` | `/start` · `/maintain` 이 자동으로 (무조건 풀 `--full`) |

갈래와 켤 단계는 선언이 아니라 스크립트가 판정한다(`scripts/basic-path.sh` — 시작·승인·계획·봉인). **애매하면 무거운 쪽**이고, 작업 중에 풀 조건이 나오면(종료 코드 3) 멈추고 안내만 하지 않고 **풀 경로로 올린다** — 만든 spec·코드를 버리지 않고 이어 간다(아래 「풀 경로로 올리기」).

### 켜지는 단계

| 단계 | 켜지는 조건 | 알려 주는 줄 |
|---|---|---|
| 분석 문서(`analysis.md`) | 유지보수이고 위험 신호가 있다 | 1번 `ANALYSIS: doc <경로>` |
| 계획(`plan.md` — 결정만) | 태스크 2개 이상 또는 위험 신호가 있다 | 4-1번 `PLAN: yes <경로>` |
| 전문가 1종 | 걸린 신호마다 — DB 스키마 → DB · 인증·권한 → 보안 · API 계약 → API · 서비스 간 연동 → 구조 | 4-1번 `EXPERTS: <에이전트…>` |
| 풀 경로로 올림 | 무거운 신호 · 태스크 4개 이상 · 계획 때 없던 신호가 구현에서 나옴 | 종료 코드 3 |

끄는 스위치: `.specops/config.yaml` 의 `unified_path: false`(또는 환경 변수 `SPECOPS_UNIFIED_PATH=0`) — 끄면 종전대로 위험 신호가 하나라도 있으면 풀 경로다.

## Process

FID 는 `YYYYMMDD-<kebab-slug>` (인자에서 슬러그를 뽑는다 — 정식 경로와 같은 규칙).

1. **시작** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh start <FID> "<요청 한 줄>" [maintain]`
   요청 문장으로 갈래를 판정하고, FID 폴더·진행 기록·spec 골격(`.specops/<FID>/spec.md`)을 만든다. 기본 브랜치 위면 브랜치를 만든다.
   - **유지보수**(`/maintain` 에서 왔거나 이미 있는 코드·동작을 고치는 요청)면 끝에 `maintain` 을 붙인다 — 골격에 `**§유형**: 유지보수` · `### 현재 동작과 영향` 절 · `### AC-R-1`(기존 동작 유지)이 더해지고 4번 승인이 셋을 검사한다. 분석 단계(`analyzing-ko`)는 돌리지 않는다 — 2번에서 코드를 읽으며 그 절을 채운다.
   - **`ANALYSIS: doc <경로>`** 가 나오면(위험 신호가 걸린 유지보수) spec 보다 **먼저** 그 분석 문서를 채운다 — 코드를 읽고 현재 동작(파일:줄) · 영향 범위(부르는 곳·같은 데이터와 계약을 쓰는 곳·관련 테스트) · 깨질 수 있는 기존 동작과 지키는 방법을 사실만 적는다. spec 의 `### 현재 동작과 영향` 절에는 요지와 `analysis.md` 참조를 적는다. 사용자 확인은 4번 승인에서 spec 과 함께 받는다(따로 멈추지 않는다). `ANALYSIS: section` 은 종전대로 spec 의 절로 쓴다.
   - 종료 코드 **3** = 풀 신호 → 만든 것이 없다. "위험 신호 <무엇> — 풀 경로로 진행" 1줄을 알리고 풀 경로로 들어간다(신규 `devfsd:specifying-ko` · 유지보수 `devfsd:analyzing-ko` 에 `<!-- entry: maintain -->` 첫 줄 — `commands/start.md`·`commands/maintain.md` 의 풀 경로 절차).
2. **spec 1장** — 코드를 읽고 골격을 채운다: 목표 · 범위(범위 밖 · 화면 변경) · 수용 기준(`### AC-n:` 블록 — Given·When·Then·우선순위) · 비기능 요구. **인증·권한 · DB 스키마 · 데이터 삭제·이관 · API 응답 형태 · 되돌릴 수 없는 외부 작업을 바꾸면 범위 절에 그 말로 적는다** — 4번 승인의 갈래 판정은 목표·범위 절만 본다(수용 기준의 전제나 현재 동작 설명에 나온 낱말로는 풀 경로로 올리지 않는다). 적지 않은 변경은 7번 봉인이 바뀐 파일 **경로**(스키마·모델·인증·세션 이름)로 잡지만 파일 내용은 보지 않고, 그때 올라가면 구현을 마친 뒤다. 질문이 있으면 **많아야 4개를 한 번에** 묻고(추천 선택지 먼저), 나머지는 추천안으로 정해 spec 에 `(ASSUMED)` 로 적는다. 화면을 건드리는데 `.specops/memory/ui-probe.json`(화면 기록)이 없으면 **서버 시작 명령·포트·화면 경로**를 이 질문 묶음에 넣는다 — 7번 화면 점검이 쓰고, 승인 뒤에는 묻지 않는다.
3. **화면 설계 확인 범위** — 화면을 건드리면 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh design-scope <고치는 화면 수> [new|flow]` 의 답을 따른다. 화면 변경량은 갈래를 바꾸지 않고 **설계 확인 범위만** 정한다.
   - `DESIGN: none` (문구·스타일만) → 설계 확인 없음.
   - `DESIGN: update` (기존 화면 1~2개 일부 수정) → 구현과 함께 `screens/<name>.md` 의 해당 부분을 갱신한다.
   - `DESIGN: approve` (화면 3개 이상 · 새 화면(`new`) · 흐름 변경(`flow`)) → 구현 전에 화면 스펙·목업을 만들고(`/design-screen`·`/design-screens` 의 절차) 4번 승인에 그 경로를 함께 싣는다.
   - 같은 출력의 `UI:` 줄은 설계 확인 범위와 무관하게 항상 따른다(`DESIGN: none` 이어도) — 5번의 **목업 CSS 이식**과 7번의 **화면 점검**.
   - API·테이블 계약을 바꾸는 작업은 위험 신호로 걸려 4-1번에서 그 전문가가 켜진다. 계약 문서 `api-spec.md`·`data-model.md` 자체를 고쳐야 하면(2~5번 어디서든) 그 파일을 고치지 말고 풀 경로로 올린다(「풀 경로로 올리기」).
4. **승인 1회** — spec 경로와 요지(목표 · 범위 · AC 마다 한 줄 · `ASSUMED` 로 정한 것 · 화면 설계 경로 · 분석 문서가 있으면 그 경로와 "깨질 수 있는 기존 동작" 요지)를 한 메시지로 보이고 "이대로 구현까지 진행할까요? [y/수정]" 을 묻는다. 승인되면:
   `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh approve <FID>`
   spec 절을 확인하고, spec 본문으로 갈래를 다시 판정하고, 수용 기준 절을 `acceptance-criteria.md` 로 옮긴다(검증 러너·스펙 리뷰어가 읽는 계약 파일). 종료 코드 3 = 풀 신호 → 「풀 경로로 올리기」(spec 을 쓰다가 풀 신호를 알아챘으면 승인을 묻기 전에 올린다 — 승인 묶음은 풀 경로 형식으로 한 번만 받는다). 승인 뒤에는 PR 까지 묻지 않는다(비가역 작업·리뷰어 `NEEDS_DISCUSSION`·고치지 못한 Critical 은 멈춘다).
4-1. **켤 단계 판정 · 계획 · 전문가** — 승인 뒤 구현 전에 한 번:
   - 태스크 수를 센다 — **함께 변하는 파일 묶음(구현 + 그 테스트)이 1태스크**다. 그 수로 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh plan <FID> <태스크 수>` 를 실행한다.
   - 종료 코드 **3**(태스크 4개 이상) → 「풀 경로로 올리기」.
   - `PLAN: skip` → 계획 없이 5번으로.
   - `PLAN: yes <경로>` → 그 골격을 채운다. **결정만 적는다**: 파일 구조 · 태스크마다 파일·인터페이스(시그니처, 앞뒤 태스크와 주고받는 것)·테스트 이름과 단언(spec 의 값 그대로)·수용 기준 · 위험 신호 대응(무엇을 바꾸는가 · 기존 데이터와 호출자에 주는 영향 · 되돌리는 방법). 함수 본문은 적지 않는다. 다 쓰면 스스로 본다 — 수용 기준마다 태스크가 있는가 · 뒤 태스크가 쓰는 이름·타입이 앞 태스크와 같은가 · 결정이 없는 줄("적절히 처리")이 없는가.
   - `EXPERTS: <에이전트…>` 가 `none` 이 아니면 그 에이전트들을 **한 메시지에서 동시에** 호출한다(`Agent` 도구 `subagent_type` 에 그 이름 그대로). 입력은 경로만 — `.specops/<FID>/spec.md` · `plan.md` · 분석 문서(있으면) · `.specops/memory/` 의 계약 문서(있으면). 산출은 `.specops/<FID>/experts/<db|security|api|arch>.md`. 지적은 계획에 반영하거나 근거를 적어 기각하고 그 파일 끝 `## 반영` 에 1줄씩 남긴다. `## 확인 필요` 질문은 추천안으로 정해 spec 에 `(ASSUMED)` 로 적는다(되돌릴 수 없는 결정이면 멈추고 묻는다). 전문가가 `api-spec.md`·`data-model.md` 를 고쳐야 한다고 하면 그 파일을 고치지 말고 풀 경로로 올린다. 봉인은 이 보고서가 없으면 받지 않는다.
5. **직접 구현** — 주 세션이 구현한다(서브에이전트에게 구현을 맡기지 않는다). 계획이 있으면 그 태스크 순서대로 한다. 수용 기준마다 **실패하는 테스트를 먼저** 쓰고 실패를 확인한 뒤 고친다(`devfsd:tdd-ko`). 구현 중에는 **관련 테스트만** 돌린다. 통과를 확인한 명령은 그 뒤로 파일을 바꾸지 않았으면 다시 돌리지 않는다(앞선 출력을 쓴다). 커밋은 7번 뒤에 한다.
   - **화면을 건드리면 — 목업 CSS 이식이 첫 일이다**: 고치는 화면에 `screens/<name>.html` 목업이 있으면 화면 코드를 쓰기 전에 **목업 CSS 이식**부터 한다 — 목업 `<style>` 의 토큰(`:root` 변수)과 공통 컴포넌트 클래스(카드·버튼·입력·표·배지·내비 등)를 앱 전역 CSS(또는 공통 컴포넌트)로 옮기고, 화면 코드는 그 클래스·토큰을 쓴다. 이미 옮겨져 있으면 빠진 것만 더한다. Tailwind 앱이면 클래스 대신 토큰을 tailwind 설정으로 옮긴다. 화면 CSS 는 목업이 기준이다 — 최소 구현(YAGNI)으로 줄이지 않는다(풀 경로 `planning-ko` 「화면 FID — 목업 CSS 이식」과 같은 규칙. 근거: 하류 4개 앱 20261114 재실측 생존율 8%·33%·90%).
6. **리뷰 1회 (동시)** — 먼저 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh review <FID>` 로 진행 기록(구현 완료 · 리뷰 진행)을 남긴다(관제판 단계 표시용 — 판정은 없다). 그다음 한 메시지에서 함께 보낸다:
   - `devfsd:spec-reviewer-ko` — FID · tid `T1` · `spec.md`·`acceptance-criteria.md` 경로 · 리뷰 대상 `git diff <base>...HEAD` + 작업 트리 변경.
   - `devfsd:code-reviewer-ko` — 같은 대상 · `병렬 dispatch: yes (B 판정 대기)`.
   - 보안 스캔 — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/security-scan.sh <변경 파일…>` 을 백그라운드(Bash `run_in_background`)로.
   - 두 리뷰어 프롬프트에 `<<<REVIEW fid=<FID> tid=T1 phase=<B|C> verdict=…>>>` 보고 형식(`skills/implementing-ko/SKILL.md` 「부모 dispatch 프롬프트 규약」)과 실행 상한(대상 테스트 실행 B 2회·C 3회 이내 · 전체 스위트 실행 금지 · 되돌려-관찰은 임시 복사본에서)을 적는다. 저장 훅이 `.specops/<FID>/reviews/T1-B-report.md`·`T1-C-report.md` 로 옮긴다.
   - 리뷰어가 도는 동안 주 세션은 **PR 본문을 준비**한다(기다리기만 하지 않는다).
   - **지적 처리**: 스펙 미충족·Critical(`[기존]` 라벨이 붙어도 같다)·보안 Critical/High 는 주 세션이 고치고 **관련 테스트를 다시 돌린다 — 재리뷰는 없다**. Important 는 이번 변경이 만든 결함이면 고치고 아니면(리뷰어의 `[기존]` 라벨) PR 본문 "넘긴 것" 에 적는다. 고칠 수 없는 Critical 이나 `NEEDS_DISCUSSION` 은 멈추고 사용자에게 묻는다.
7. **봉인과 검증 1회**
   - **화면 점검 (화면을 건드렸을 때 — 봉인 전 1회)**: 통합 게이트는 돌리지 않지만 화면은 실제 브라우저로 한 번 연다.
     ```bash
     node "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/ui-probe.cjs --out .specops/<FID>/ui \
       --memory .specops/memory/ui-probe.json --a11y-baseline .specops/memory/ui-a11y-baseline.json \
       [--start-cmd "<서버 시작 명령>"] [--mock screens/<이름>.html ...] [http://localhost:<port>/<경로> ...]
     bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-mock-css.sh .
     ```
     - 화면 기록이 있으면 URL 없이 돈다. 없으면 2번에서 받은 서버 시작 명령·포트·경로로 첫 실행한다(서버는 주 세션이 띄우고 끝나면 끈다 — 하네스는 서버를 띄우지 않는다). 고친 화면의 목업은 `--mock` 으로 넘긴다.
     - `UI-PROBE: FAIL`(가로 넘침·콘솔 오류·기준선에 없던 접근성 위반) → 고치고 다시 돌린다. 여기서 고친 것은 리뷰어가 보지 않는다(재리뷰 없음) — 관련 테스트와 검증 러너가 본다.
     - **접근성 기준선 첫 실행**: 기준선 파일이 없던 저장소는 지금 위반을 기록만 하고 막지 않는다(`기준선 기록:` 줄 — 아래에 요소가 붙는다). 그 줄에 **이번에 만들거나 고친 화면**이 있으면 고치고 기준선 파일을 지운 뒤 다시 돌린다 — 방금 만든 위반을 기준선에 넣지 않는다. 남긴 `기준선 기록:` 줄은 `evidence.md` 에 그대로 옮긴다. `배치 경고`(`L-CLIP-X`·`L-OVERLAP`)는 판정을 바꾸지 않지만 이번 변경이 만든 것이면 고친다.
     - 찍힌 `<화면>@<폭>.png` 를 Read 로 열어 본다 — 목업(`.mock.png`)이 있으면 폭마다 나란히 보고, 눈에 띄는 차이(브라우저 기본 모양의 입력·버튼, 빠진 상태 표시)는 고친다.
     - `MOCK-CSS: WARN` → 빠진 클래스를 5번의 이식으로 돌아가 채운다. `SKIP`·`OK` 는 그대로 적는다.
     - `UI-PROBE: SKIP (…)` 이거나 서버를 띄울 수 없으면 멈추지 않는다 — **PASS 로 적지 않는다**. 미실행으로 적고 PR 본문 "미실행 게이트" 에 싣는다.
     - 검증이 끝난 뒤 `evidence.md` 에 한 줄을 남긴다(풀 경로 통합 테스트의 브라우저 줄에 `MOCK-CSS:` 를 더한 형식 — 이 경로는 사용자에게 묻지 않으므로 `USER_SKIP` 은 없다):
       ```
       **브라우저**: 실행(<N>화면·<M>폭 · UI-PROBE: PASS|FAIL · 배치 경고 <N> · 계측 못 함 <M> · MOCK-CSS: <OK|WARN|SKIP …> · .specops/<FID>/ui/)
       **브라우저**: 미실행(NO_TOOL|NO_ENV|NO_SERVER — <한 줄 사유>)
       ```
   - **검증 명령 고르기** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh related` 의 답을 `test_command` 로 쓴다.
     - `RELATED: <명령>` → 그 명령 그대로(변경 파일이 닿는 스위트만 돈다). 스위트 매핑(`scripts/tests/run-related.sh`)이 있는 저장소에서만 나온다.
     - `RELATED: none — <사유>` → 종전대로 **프로젝트의 테스트 명령 전체**(테스트 스크립트 · `pytest` · `npm test` 등 검증 러너가 받는 형태). 매핑이 없는 저장소, 관련 스위트를 특정할 수 없는 변경, 너무 넓게 닿는 변경이 여기다. `none — …` 줄 자체는 명령이 아니다 — seal 은 검증 러너가 받지 않는 형식의 문자열을 거부한다(rc 1).
   - `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh seal <FID> "<test_command>"` — 변경 파일로 갈래를 다시 판정하고(4-1번의 판정 기록과 대조한다 — 계획 때 없던 위험 신호가 바뀐 파일에서 나오면 종료 코드 3, 켜기로 한 전문가의 보고서가 없으면 거부), 1-태스크 문서(`tasks.md`)와 리뷰 감사 행(`dispatch-log.md`)을 만든다. 관련 스위트 명령에 지금 변경이 닿는 스위트가 빠져 있으면 받지 않는다(`related` 를 다시 실행). 종료 코드 **3** = 풀 신호 → 「풀 경로로 올리기」 · **4** = 리뷰 보고서 없음(6번으로).
   - `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/run-verification.sh <FID>` 를 **포그라운드**로 실행한다(Bash `timeout` 명시). `VERIFY: PASS` 가 나와야 한다.
   - **전체 스위트는 여기서 돌리지 않는다** — 관련 스위트로 검증했으면 전체는 PR 의 CI 가 맡는다(작업 브랜치의 push 전 게이트 `pre-push` 는 같은 관련 스위트로 판정하고, 같은 트리의 통과 기록이 있으면 건너뛴다 — 기본 브랜치·태그 push 는 전체다). push 전 게이트도 CI 도 없는 저장소는 `related` 가 `none` 을 내므로 위에서 이미 전체를 돌렸다.
   - 통과하면 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /verify PASS "evidence.md, AC N/N (/basic)"`. 보안 스캔 결과를 `evidence.md` 에 `## /security-review — <시각>` 절(결과·근거)로 남긴다.
   - 실패하면 고치고 다시 seal → 검증이다. 세 번 실패하면 `devfsd:systematic-debugging-ko`.
8. **커밋 · PR** — `git add <파일…>` 과 `git commit` 을 따로 실행한다. 커밋·PR 은 `/start` 와 같은 훅(R-1·R-2)이 본다 — 7번의 검증 실행 출력과 진행 기록이 있어야 열린다. 막히면 우회하지 않고 사유를 고친다. PR 을 만들지 묻고(y/n), 만들면 본문에 요약 · 테스트 계획 · 리뷰어가 찾았지만 넘긴 것 · **돌리지 않은 게이트**(아래)를 싣는다. 화면을 건드렸으면 7번의 `**브라우저**:` 줄을 그대로 옮긴다.
9. **마무리** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh done <FID> "<한 줄 요약>"`

## 풀 경로로 올리기 (승격)

1번 뒤 어느 지점에서든 풀 조건이 나오면(approve·plan·seal 의 종료 코드 3 — 무거운 신호 · 태스크 4개 이상 · 계획 때 없던 신호 · `api-spec.md`·`data-model.md` 를 고쳐야 함) 멈추고 안내만 하지 않는다:

1. `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/basic-path.sh promote <FID> "<사유 한 줄>"` — spec 1장·리뷰 보고서·1-태스크 문서를 `.specops/<FID>/basic-draft/` 로 보존하고 진행 기록(`/full 승격`)을 남긴다. 코드 변경은 작업 트리에 그대로 둔다(커밋·되돌리기 금지).
2. `NOTICE:` 줄을 사용자에게 그대로 보인다(1줄 — "<사유> — 풀 경로로 올림.").
3. `PROCEDURE:` 줄의 파일(`skills/specifying-ko/basic-promote.md`)을 Read 하고, `NEXT:` 의 skill 을 `ARGS:` 줄들(순서 그대로) + 원래 요청 한 줄로 호출한다. 같은 FID·같은 브랜치로 풀 경로가 이어진다 — spec 은 풀 형식으로 다시 쓰이고 clarify → plan → 분해 → 구현(이미 쓴 코드에서 시작) → 리뷰·게이트가 돈다.

| 걸린 지점 | 그때 있는 것 | 풀 경로에서 이어지는 곳 |
|---|---|---|
| 1번 start | 없음 | 처음부터(승격 아님 — 풀 경로 진입) |
| 2~4번 (spec · approve) | spec 1장 | spec 을 풀 형식으로 → 승인 묶음(풀 형식) → clarify → plan |
| 5번 (구현 중 계약 문서 필요) · 7번 seal | spec 1장 + 코드 (+ 리뷰 보고서) | 위와 같고, plan 이 "이미 작성된 코드" 를 싣고 plan 리뷰·구현 뒤 스펙·코드 리뷰가 그 코드를 본다. 세션 분리는 끈다 |

## 이 경로가 하지 않는 것

- **통합·성능 게이트** — 돌리지 않는다(화면을 건드린 작업의 브라우저 점검만 7번에서 1회 돈다 — 하류 E2E·API 통합 테스트는 여전히 없다). `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/gate-preflight.sh <FID>` 가 `GATE integration APPLY` 나 `GATE performance APPLY` 를 내면 PR 본문에 "미실행 게이트" 로 적는다(성능 임계값이 수용 기준이면 풀 경로가 맞다).
- **plan 리뷰 · 이해 검사 · 테스트 설계 전문가** — 없다. 걸린 신호의 전문가 1종만 돈다(4-1번). 그 이상의 검토가 필요한 작업(태스크 4개 이상 · 무거운 신호)이 풀 경로의 대상이다.
- **재리뷰** — 리뷰는 한 번이다. 고친 것은 관련 테스트와 검증 러너가 본다.
- **검증 단계의 전체 스위트** — 관련 스위트 명령(`RELATED: <명령>`)으로 검증한 작업은 커밋 시점에 전체 스위트가 돌지 않은 상태다. 전체는 PR 의 CI 가 돌린다(작업 브랜치의 push 전 게이트는 관련 스위트만 본다) — 거기서 떨어지면 고치고 다시 seal → 검증이다.

## 갈래별 차이

| | `/quick-fix` | 기본 경로 | 풀 경로 |
|---|---|---|---|
| 문서 | 없음(자동 태스크 문서) | spec 1장 (+ 조건부: 분석 문서 · 결정만 적은 계획) | intent · spec · AC · clarify · plan · tasks · 인계 |
| 승인 대기 | 없음 | 1회 | 질문 묶음 최대 2회 + 승인 1회 |
| 구현 | 주 세션 | 주 세션 | 구현자 서브에이전트 |
| 리뷰 | 코드 리뷰 | (조건부: 걸린 신호의 전문가 1종) · 스펙 + 코드 + 보안 스캔 (동시 1회) | plan 리뷰 · 전문가 · 스펙 + 코드 · 게이트 3종 |
| 화면 | 구조 변경 없음 | 목업 CSS 이식 · 브라우저 점검 1회 | 화면 전문가 · 목업 CSS 이식 · 통합 테스트의 브라우저 점검 · 데모 |
| 크기·위험 상한 | 파일 2·20줄 (훅) | 무거운 신호 없음 · 태스크 3개 이하 (스크립트 4회) | 없음 |
| 끝나는 지점 | 커밋 | PR | PR |

## 안티패턴

- **모델이 갈래를 고르기** — "가벼워 보인다"·"적당히 해줘" 로 고르지 않는다. `/start`·`/maintain`·자연어 진입의 갈래는 `basic-path.sh route` 의 답이고, 사용자가 뒤집는 방법은 `--full`(풀)과 `/basic`(기본) 둘뿐이다.
- **풀 신호를 피하려고 spec 문구를 바꾸기** — 신호 낱말을 지우는 것이 아니라 풀 경로로 간다.
- **태스크 수를 줄여 세기** — 4개 이상이면 풀 경로다. 상한을 피하려고 묶어 세지 않는다(함께 변하는 파일 묶음이 1태스크다).
- **구현을 서브에이전트에 맡기기** — 그러면 인계 문서가 필요해지고 이 경로의 이점이 사라진다.
- **리뷰 생략 · 검증 생략** — 봉인이 리뷰 보고서를, 훅이 검증 실행 출력을 요구한다. 우회하지 않는다.
- **무인 변형** — 없다.

## 참조

- `scripts/basic-path.sh` — route · lane · start · approve · review · related · seal · promote · design-scope · done
- `skills/specifying-ko/basic-promote.md` — 풀 경로로 올린 뒤의 절차
- `scripts/tests/run-related.sh` — 변경 파일이 닿는 스위트 고르기(`--list`)·실행 (스위트 매핑이 있는 저장소)
- `templates/spec-basic.md` — spec 1장 골격
- `scripts/_internal/ui-probe.cjs` · `scripts/_internal/check-mock-css.sh` — 7번 화면 점검(브라우저 판정 · 목업 클래스 생존율)
- `scripts/_internal/risk-profile.sh` — 영문 위험 신호 판정(`rp::detect_strict_signals`)
- `commands/quick-fix.md` · `commands/start.md` · `commands/maintain.md` — 이웃 갈래

---

*specops-ko v4.0.10 · 2026-11-12 · 기본 경로 (spec 1장 · 주 세션 구현 · 리뷰 1회 · 검증 1회)*
