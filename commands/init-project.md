---
name: init-project
description: specops-ko 한국어 자율 Lifecycle 진입 — 한국 SI 표준 14종(풀스택 기준 · 종류·선택별 7~14종) 산출물 자동 부트스트랩
triggers:
  - "/init-project"
mode: ask
specops_version: 2.17.0
specops_layer: Lifecycle-Bootstrap
reference_upstream: specops-ko 독자 추가 (github/spec-kit 패턴 번안)
---

# /init-project [<프로젝트명>] [<기존 기획 문서 경로>]

## 목적

프로젝트 **최초 1회** 실행. PRD/CLAUDE/DESIGN/architecture 등 **한국 SI 표준 14종 산출물**(풀스택 기준 — 종류·선택별 7~14종)을 자동 부트스트랩한다. `/start-design`은 본 슬래시로 통합됐다. (구 `/start-project` 에서 rename.)

**축소 계약 (v1.50)**: Intake 1 → Skeleton → Light enrich(게이트 1) → **Commit 1**. bash 단계는 화면 파일을 만들지 않는다(이름 목록만) — 화면 본문은 Phase 11 보강(UI 종류 · 미확정 마커 허용)이 초안을 만들고 `/start-all` Phase 2.5 가 FR 확정 뒤 메운다.

## Process

0. **PRD 6필드 초안 합성** (bash 호출 전 — LLM 레이어). 근거 문서 탐색은 4단 우선순위:
   - **0-a. 명시 경로** — args 에 파일 경로가 포함되면(`/init-project 쇼핑몰 docs/기획서.md`) 그 문서가 최우선 근거.
   - **0-b. 브레인스토밍 메모** — `ls -t .specops/memory/brainstorming-*.md 2>/dev/null | head -1` 존재 시 사용.
   - **0-b2. plan 모드 산출물** (20260820 신설 — plan 은 파일로 안 남지만 transcript 에는 남는다):
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/extract-plan-from-transcript.sh
     ```
     - **rc=0** — stdout 이 plan 전문, stderr 에 `PLAN-SOURCE:`(출처·경과시간)가 오고, plan 에 `# ` 제목줄이 있으면 `PLAN-TITLE:`(제목)도 온다(**제목 없으면 생략** — 실패 아님). **사용자 확인 필수**(주권 — 자동 소비 금지): "직전 plan(`<PLAN-TITLE>` — 없으면 파일명, <N>시간 전)을 PRD 초안 근거로 사용할까요? [y/n]". `n` 이면 무시하고 0-c 로 내려간다.
     - **rc≠0** — 조용히 0-c 로 하강한다(디렉토리 부재·plan 0건·빈 plan·창 초과=1, `jq` 부재=2). 어떤 경우에도 `/init-project` 를 막지 않는다.
     - 기본 시간 창은 24시간 — `SPECOPS_PLAN_MAX_AGE_HOURS` 로 조정한다. 오래된 plan 을 근거로 끌어오는 stale 을 막는다.
   - **0-c. 기존 기획 문서 auto-discovery** (20260716 신설 — 온보딩 마찰 해소: 실무는 PRD 가 이미 파일로 존재하는 게 보통):
     ```bash
     ls PRD*.md prd*.md docs/PRD*.md docs/prd*.md 기획*.md 요구사항*.md REQUIREMENTS*.md requirements*.md docs/기획*.md docs/요구사항*.md docs/requirements*.md 2>/dev/null
     ```
     - 발견 시 **사용자 확인 필수**(주권 — 자동 소비 금지): "기존 문서 `<경로>` 를 PRD 초안 근거로 사용할까요? [y/n]". `n` 이면 무시.
     - 복수 발견 시 목록 제시 → 사용자 선택 (전체·일부·없음).
     - **루트의 `prd.md` 주의** — 대소문자를 구분하지 않는 파일시스템(macOS 기본)에서는 산출물 `PRD.md` 와 **같은 파일**이다. bash 가 쓰기 전에 rc=2 로 멈추고 두 선택지를 알려 준다 — 사용자에게 물어 고른다(임의로 옮기지 않는다): ① 기획 원문으로 남긴다 → 다른 이름으로 옮긴다(`git mv prd.md docs/prd-source.md`) → init 이 `PRD.md` 를 새로 쓴다 ② 그 파일을 그대로 PRD 로 쓴다 → `git mv prd.md PRD.md` → `PRD.md` 는 보존되고 확정한 6필드는 `CLAUDE.md`·`README.md` 의 한 줄 설명과 FR 시드에만 쓰인다.
     - **`PRD.md` 가 이미 있어 보존될 때도 `prd.*` 6키를 적는다** — 필수는 아니지만, 적어야 `CLAUDE.md`·`README.md` 의 한 줄 설명과 FR 시드가 채워진다(`PRD.md` 자체는 고치지 않는다).
     - `requirements*.md` 가 이미 **FR 표를 포함**하면 Phase 8a 에서 해당 파일 보존(`_should_skip` 정책)되도록 안내 — 초안 근거와 산출물 보존은 별개.
   - 위 어느 경로든 문서 확보 시: 읽고 **6필드 초안**(한 줄/페르소나/가치제안 3개/M1/M2/M3)을 합성해 사용자에게 제시 → 확인/수정 → **확정값을 답변 파일의 `prd.*` 키로 적는다**(아래 1번).
   - 문서에 없는 필드는 창작하지 말고 사용자에게 질문 (사실성 계약 — 근거 4원의 ① 이 "사전 문서"로 확장됨).
   - **넷 다 부재 시 현행 수동 입력** 그대로 (fallback — 초안 단계 skip).
1. **답변 파일을 쓰고 bash 를 호출한다** — 질문의 답은 순서가 아니라 **키**로 준다:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/init-project.sh --answers-template   # 키 목록·설명 (아무것도 쓰지 않는다)
   # → 사용자와 정한 값을 .specops/.init-answers 에 키=값 으로 적는다 (순서 무관)
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/init-project.sh --answers .specops/.init-answers [--resume] "<프로젝트명>"
   ```
   - 인자를 비우면 프로젝트명은 `basename $PWD`.
   - **빠진 키·잘못된 값·모르는 키가 있으면 rc=2 로 전부 알려 주고 아무것도 쓰지 않는다** — 알려 준 항목을 채워 같은 명령을 다시 실행한다. 어떤 키가 필요한지는 저장소 상태와 종류에 따라 다르므로(이미 있는 파일의 질문은 생략된다) 스크립트 원문을 읽어 추측하지 말고 이 출력에 따른다.
   - **사용자가 정하지 않은 값을 지어 넣지 않는다** — 종류(`kind`)·헌법 원칙(`principles`)·DB 사용(`db`)·디자인 방향(`design`)·화면 이름(`screens`)·API 방식(`api`)은 사용자에게 묻거나 Phase 0 근거 문서에서 확인한 값만 적는다. (실기록: 묻지 않고 `skip`·`n` 을 넣어 헌법이 빈 채로 굳었다.)
   - **답을 stdin 으로 순서대로 넣지 않는다.** stdin 모드는 터미널에서 사람이 직접 답할 때 쓴다. 질문 수가 종류·기존 파일·메모 유무로 달라져 한 줄만 밀려도 전부 어긋난다 — 그래서 터미널이 아닌데 입력이 모자라거나 선택지가 아닌 값이 들어오면 스크립트가 rc=2 로 멈춘다.
   - `.specops/.init-answers` 는 `.specops/.gitignore` 의 `.init-*` 규칙으로 무시된다. 종결 뒤 지운다.
   - `--resume`: 기존 파일 보존·누락 파일만 생성 (부분 부트스트랩 재개 시 사용). 화면 목록 표와 `.specops/.gitignore` 도 보존 대상이다 — 표에는 새 이름만 덧붙고, `.gitignore` 는 빠진 규칙만 파일 위쪽에 보충한다(사용자 규칙이 뒤에 있어 우선한다 · 구 규칙 `…-*/` 은 `…-*/*` + `intent.md` 예외로 이관).
2. **10 Phase 진행**:
   - Phase 1: 사전검사 (git/.specops/memory 검사 + 14종 파일별 표(존재 여부 — 활성은 Phase 2 KIND 가 정한다) + 충돌 정책). 브레인스토밍 메모 있으면 **BM_REF=y 자동**(Phase 0 확인 후 재질문 없음).
   - Phase 2: 종류 분류 (Web/UI · BE/API · CLI/lib · 풀스택 · 모바일 · 기타). 고른 종류는 Phase 10 이 `project-context.md` 머리에 `<!-- specops:project-kind: N -->` 로 적는다 — foundation 필수 판정과 다음 `--resume` 이 추정 대신 이 값을 쓴다(`--resume` 이고 종류가 기록돼 있으면 `kind` 를 비워 두거나 생략할 수 있다 — 기록이 없는 기존 프로젝트는 답해야 한다).
   - Phase 3: 헌법 5원칙 입력 ('skip' 가능)
   - Phase 4: PRD — 답변 파일의 `prd.*` 6키 (stdin 모드는 numbered list · 구 `.init-prd-fields` 도 읽는다)
   - Phase 5: CLAUDE.md 자동 생성 (PRD §1 + constitution 원칙 5개 인용)
   - Phase 6: DESIGN.md (UI/풀스택/모바일만) — 디자인 방향 카탈로그(`templates/design-directions.md`, 9개)에서 1택 → 방향 선언·다이얼·§1 팔레트 9색·§8 방향 특성을 채운다
   - Phase 7: 화면 **이름 목록만** → `screens-overview.md` 표. **`screens/*.{md,html}` 껍데기 미생성**. 표가 이미 있으면 **보존**하고 표에 없는 이름만 끝에 덧붙인다(기존 행·손으로 쓴 줄 무변경)
     - **★ 이 목록의 소비자**: `/design-screen(s)`(fence 갱신) · **`/start-all` Phase 2.5-A**(Step 1 `list` 로 화면셋에 합류 · Step 4 `sync` 로 갱신 · `diff` 로 잔여 고지 — 20260906 배선). 마스터에만 있고 어느 FR 도 언급하지 않은 화면은 **queue 헤더에 고지**되며, 비차단이므로 batch 는 계속 진행된다.
   - Phase 8: 종류별 산출물 매트릭스 (8a~8i: requirements/architecture/frontend/backend/data-model/api-spec/api-spec-consumer/test-strategy/process-design)
     - `api-spec-consumer.md`(8g)는 **14종 밖**이다 — UI·모바일 + 소비 계약 `y` 일 때만 생성된다.
   - Phase 9: README.md 자동 생성 (PRD §1 인용)
   - Phase 10: `.specops/.gitignore`(없으면 생성 · 있으면 **병합** — 사용자 규칙 보존) + session-progress + **원장 골격**(`project-context.md`·`decisions.md`) + **스테이징만**(커밋은 Phase 11 단일 · 범위는 init 산출물뿐 — 미리 stage 돼 있던 다른 파일·기존 앱의 `screens/` 는 건드리지 않는다). `SPECOPS_INIT_COMMIT_NOW=1` 이면 bash에서 즉시 커밋. 종결 커밋은 Phase 11 의 `init-finalize.sh` 가 수행.
3. **Phase 11 — Light enrich** (bash 종료 후, 아래 §Phase 11 섹션 준수)
4. **설계 통합 뷰 생성** (커밋 뒤 — 생성물이라 커밋 대상이 아니다): `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/design-overview.sh` 를 실행하고 출력된 경로를 사용자에게 알린다("전체 설계를 한 화면에서 보려면 `<경로>` 를 브라우저로 여세요"). 실패(rc≠0 — python3 부재 등)는 1줄 고지만 하고 부트스트랩을 실패로 만들지 않는다. `--enrich` 뒤에도 같다.
5. 종료 후 안내: "이제 `/start \"<첫 기능>\"` 또는 `/start-foundation` → `/start-all` 으로 lifecycle 진입하세요"

## Phase 11 — Light enrich (bash 종료 후)

bash 10 Phase 가 생성한 산출물은 템플릿 골격이다. Phase 11 에서 LLM 이 **핵심 문서만** 프로젝트 특화 초안으로 보강한다.

**용도 선언**: 산출물은 **개발 기준 문서**다 — specifying·planning·implementing 이 재작성 없이 인용·소비한다. 보강은 정확·상세·정직해야 한다.

**문서별 보강 깊이 (Light enrich) — 최소 깊이 기준**:

**깊게** (원칙: bash 생성분 · 해당 KIND만 — 예외: `screens/<name>.md` 는 bash 비생성분이라 보강이 아니라 **새로 만든다**. `process-design.md` 는 bash 가 골격을 만들며 KIND 조건이 붙지 않는다):
- `PRD.md` — **§1~2 는 Phase 4 확정분이라 건드리지 않는다**(사용자 응답 덮어쓰기 금지). 보강 대상은 `<TODO>` 가 남는 **§목적·성공 판정 · NFR · 리스크 · 기술 스택**뿐. e2e V21 이 `PRD.md` 를 스캔 대상으로 **지정**하므로 담당이 비면 게이트가 검사만 하고 채우는 주체가 없다(20260806 실측: 부트스트랩 직후 원시 `<TODO>` 10곳 잔존).
- `requirements.md` — M1 FR 세부 분해(must) + M2/M3 시점 명시(should)
- `api-spec.md` · `data-model.md` — PRD에서 도출된 실 엔드포인트·엔티티. **`<!-- specops:example:start -->`…`:end -->` 예시 블록은 마커째 삭제**한다(전자상거래 샘플 — 남기면 유령 스키마가 설계 계약이 되고 `scan-enrich-placeholders.sh` 가 미채움 판정).
- `frontend-architecture.md` · `backend-architecture.md` — 스택 표 실값
- `screens/<name>.md` + `screens/<name>.html` — **UI KIND일 때만**. 입력은 `screens-overview.md` fence 안 화면 이름 목록. 상세는 아래 §화면 보강 규약
- `process-design.md` — 업무 프로세스 설계. `templates/process-design.md` 기반으로 `.specops/memory/process-design.md` 를 **채운다** — 골격은 bash Phase 8i 가 만든다(정본 14종 편입, 20261008). 골격이 없으면(`--enrich` 로 들어온 구 프로젝트) 같은 템플릿으로 새로 만든다. **KIND 무관 항상 산출**(CLI 도 `사용자 → 명령 → 처리 → 출력` 흐름을 갖는다). 프로세스마다 트리거·행위자·화면·API·테이블·결과·예외
  - **하류 이관** (`--enrich` · `--resume` 실행 시): 구 이름 `.specops/memory/intent.md` 가 프로세스 형식(본문에 `트리거`)으로 있고 `process-design.md` 가 없으면 `git mv .specops/memory/intent.md .specops/memory/process-design.md` 를 제안한다 [y/n]. 사용자가 거절하면 그대로 둔다 — **자동 개명·덮어쓰지 않는다**. `§auto` 는 제안만 기록하고 변경하지 않는다
- `DESIGN.md` — **UI KIND일 때만**. 머리의 `디자인 방향` 선택을 `decisions.md` 결정 표에 행으로 upsert 한다(주제 `디자인 방향` · 출처 `init Phase6`) — 그 행의 이유·검토한 대안 칸도 채운다(근거가 없으면 비운다)

**얕게/스킵** (골격·placeholder 유지 허용):
- `constitution.md` · `test-strategy.md` · `architecture.md` · `CLAUDE.md` · `README.md`
- `screens-overview.md` — 골격 유지. **예외: 화면을 보강한 행의 목적 칸만** 갱신(아래 §화면 보강 규약). 표의 나머지(이름·제목·링크)는 Phase 7 bash 소유라 건드리지 않는다
- **헌법이 skip 으로 남았으면**(`constitution.md` 의 원칙 이름이 자리표시자 · `CLAUDE.md` 의 원칙 줄이 미확정 마커) 승인 게이트 요약에 "헌법 원칙 미작성" 을 한 줄로 알린다 — 사용자가 원칙 5개를 주면 `constitution.md` 와 `CLAUDE.md` 원칙 줄을 함께 채운다. 원칙을 지어내지 않는다

**Phase 11.5 — 단일 라운드 사전 인터뷰** (보강 전 — 대화형 전용):
- 보강 **직전**, 근거 부족으로 `가정:`·미확정 마커가 될 **결정급**만 질문으로 변환한다.
- **상한**: **총 최대 5문항** (단일 라운드 — 그룹별 5×3 폐지). 후보 초과 시 **결정급 우선** 선정(스택·인증·배포·데이터 경계·UI 유무) — 6번째부터는 묻지 않고 미확정 마커로 남긴다(실기록: 7문항).
- 객관식 우선. **모든 질문에 "모름/나중에" 선택지 필수** — 해당 답변은 미확정 마커로 남긴다.
- 답변은 근거 ④(인터뷰 응답)로 편입 — 마커/가정 대신 실값 기재.
- **질문 스킵 주권**: 사용자가 "질문 스킵" 응답 시 인터뷰 없이 아래 현행 흐름(가정:/마커)으로 진행.

**§화면 보강 규약** (UI KIND 전용 — `/design-screen(s)`·`specifying-ko` Step 5.5 와 동일 계약):

- **입력**: `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-screens-overview.sh list` 로 마스터 화면 이름을 얻는다.
- **셸 3종 제외**: `app-shell`·`layout`·`login` 은 **생성하지 않는다** — `/start-foundation` Step 5.5 의 몫이고 그쪽만 `<!-- foundation-shell -->` 마커를 단다. init 이 먼저 만들면 foundation 이 덮어써 이름이 충돌한다. 표에는 이름만 남는다.
- **산출**: `templates/screen.md` 기반으로 `screens/<name>.md` 를, `templates/screen.html` 기반으로 `screens/<name>.html` 을 **함께** 생성한다. 양쪽의 `<!-- specops:screen-placeholder ... -->` 줄을 **삭제**한다 — `.html` 은 `design-screen.sh` 가 **마커만** 보므로 이 삭제가 곧 채움 선언이다.
- **채움**: 필수 8섹션(목적·Layout·Components·States·Interactions·필드 정의표·데이터 소스·에러 메시지)을 **모두** 둔다. PRD 로 도출되지 않는 항목은 `<미확정 — 근거 필요>` 로 채운다 — 이 마커는 `design-screen.sh` 의 "헤더+본문 존재" 판정을 통과하고 `scan-enrich-placeholders.sh` 제외 ①에도 걸리므로 **두 게이트가 함께 통과**한다. 조건부 4섹션(RBAC·반응형·접근성·진입/이탈)은 해당할 때만 넣는다.
- **DESIGN.md 준수**: `DESIGN.md` §6.1 화면 원형 · §7 상태 표현을 읽고 따른다(부재 시 skip). `/design-screen(s)` 와 동일 의무다.
- **표 목적 칸 갱신**: 보강한 화면의 `screens-overview.md` 행에서 목적 칸(셋째 칸)의 `예정 — /start-all Phase 2.5` 를 `init 보강 (미확정 <N>)` 으로 바꾼다(`<N>` = 그 화면에 남은 미확정 마커 수). **마커 수 상한은 두지 않는다** — 상한은 근거 없는 숫자이고, 남은 미확정은 `/start-all` Phase 2.5 가 FR 확정 후 메운다.
- **비UI KIND**: 화면 보강 전체를 graceful skip 한다(FAIL 아님).

**사실성 계약 (Karpathy 원칙 — karpathy-ko)**:
- 서술 근거는 **근거 4원**만: ① 사전 문서(브레인스토밍 메모 · Phase 0 에서 사용자가 확인한 기존 기획 문서) ② 사용자 응답(Phase 2~8 입력) ③ 검증 가능한 사실 ④ 인터뷰 응답(Phase 11.5). 이 외 창작 금지.
- **일반론 boilerplate 금지** — 어느 프로젝트에나 맞는 문장 대신 프로젝트 특화 구체값(이름·수치·결정)으로 작성.
- 불확실 항목은 `<미확정 — 근거 필요>` 마커로 남긴다. **깊게 대상 문서**에는 원시 placeholder `<...>` 를 남기지 않는다(미확정 마커만 허용) — 얕게/스킵 문서의 골격 placeholder 는 위 깊이 규칙대로 남을 수 있고, 종결 커밋이 남은 건수를 알린다.
- **규약 표기는 채움 대상 아님·잔존 허용** — `.specops/<FID>`·`screens/<name>` 류 문서 본문 서술은 placeholder 가 아니다 (allowlist SoT: `scripts/_internal/scan-enrich-placeholders.sh`). 스캔 통과 목적으로 규약 표기를 지우는 과보강 금지.
- 추론 항목은 `가정:` 접두 명시.
- 사용자가 이미 작성한 본문은 덮어쓰기 금지 (보강 대상 = placeholder·미확정 마커뿐).

must (구조 완결 — 위반 시 보강 미완):
- **빈 셀 금지** — 깊게 대상 문서의 표 셀·목록은 실값·`가정:`·`<미확정 — 근거 필요>` 셋 중 하나. `(미정)`·"며칠" 류 무정보 값 금지.
- 첫 마일스톤(M1) FR 분해 필수 — requirements.md 의 M1 시드를 세부 FR 로.
- **공통부 FR 표기** — 스캐폴딩·인증·공통 레이아웃·공통 API 클라이언트·공통 DB 베이스 등 `/start-foundation` 범위는 설명 선두 `[공통]`(또는 `**[공통]**`)로 쓰고, 가능하면 `<!-- foundation-fr: FR-N,… -->` 목록도 둔다. `/start-all` 은 이들을 `foundation-scope` 로 SKIP 한다 — 표기 없으면 batch PENDING 에 들어가 공통이 기능처럼 구현된다.

should (수치·상세 — 근거 없으면 마커 + 사유):
- NFR 정량화 (수치 임계값).
- M2/M3 사전 분해 — 불가 시 마커 + 분해 시점 명시.

**단일 승인 게이트 + 가정 다이제스트** (전문 재출력 금지 — 요약+변경 diff 1회):
1. 깊게 대상 전부 보강 → **1회** 요약 제시 → 게이트 `[y/번호 수정]`
   - `가정:` 전건 번호 목록 + 결정급 ★ 표시
   - `y` = 전체 승인, 번호 = 해당 가정만 수정 후 재제시 (루프 cap 없음 — 사용자 주권)
   - **수정 요청을 반영한 뒤에는 다시 게이트를 받는다** — 반영 직후 곧바로 종결 커밋하지 않는다(실기록: 수정 요청 뒤 재승인 없이 커밋). `y` 를 받은 내용과 커밋하는 내용이 같아야 한다
2. (구 그룹①②③ 3게이트 폐지)
3. DESIGN.md 보강 후 `screens/*.html` 이 **이미 존재**하면(구 부트스트랩·수동 생성): `bash` 로 각 html 에 `scripts/_internal/init-project/lib.sh` 의 `_inject_design_palette` 재실행 — DESIGN.md 확정 색을 화면 미리보기에 반영 (**스캐폴딩 원본·사용자 미편집 상태에서만** — 편집본 덮어쓰기 금지)

**가정 다이제스트 + 결정 원장** (대화형·무인 공통):
- 승인(또는 자동수락)된 `가정:` 전건을 **PRD.md 말미 `## §보강 가정 다이제스트`** 에 기록 (PRD 단일 출처 — requirements 등 중복 금지). 재실행(--enrich 포함) 시 기존 섹션 **전건 갱신**(replace) — 중복 섹션 append 금지.
- **동시**: `.specops/memory/project-context.md` §1~2 채움(머리의 `<!-- specops:project-kind: N -->` 줄은 **지우지 않는다** — 뒤 단계가 읽는 종류 기록이다) + `.specops/memory/decisions.md` 표에 행 upsert (출처=`init Phase0`/`init Phase11.5`) — 이유·검토한 대안 칸도 채운다(근거가 없으면 비운다 · 5칸 원장이면 머리·구분선 끝에 두 칸을 붙인다). specifying·clarifying이 이 원장을 소비한다.

**단일 커밋** (bash Phase 10 스테이징 + enrich 변경 통합) — **반드시 아래 1줄로 수행한다**:

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/init-finalize.sh
```

이 스크립트가 **정본 산출물 목록을 소유**한다(`ARTIFACTS_ROOT[@]`·`ARTIFACTS_MEMORY[@]`) — 파일 목록을 직접 나열하지 말 것. enrich 수정분 재-add·단일 커밋·진행기록 append 를 함께 수행한다.

**제목과 출력이 남은 미채움을 말한다** — 커밋한 문서에 자리표시자·예시 블록이 없으면 제목이 `부트스트랩+enrich (N종)`, 남아 있으면 `부트스트랩 (N종 · 미채움 M건 · 예시 블록 E건)`(해당하는 것만) 이고 출력에 문서별 건수가 나온다(막지는 않는다). 스캔하지 못했으면 제목은 `부트스트랩 (N종)` 이다. 이 출력을 사용자에게 그대로 전한다 — 예시 블록이 남았다는 고지는 보강이 빠졌다는 신호다.

**커밋 범위는 init 산출물뿐이다** — 루트 4종 · `.specops/memory/` · 화면 목록에 있는 `screens/<name>.{md,html}` · `.specops/.gitignore` · `session-progress.md`. 그 밖은 커밋하지 않고 **출력으로 알린다**(사용자에게 그대로 전달할 것):
- 미리 stage 돼 있던 무관한 파일 → 인덱스에 그대로 남는다.
- init 이 보존한 기존 파일 중 **미커밋 내용이 있는 것**(미추적·staged·수정 — init 이 쓴 파일이 아닌 것) → 건드리지 않는다. bash 가 Phase 1 에서 `.specops/.init-hold` 에 적고, init 이 쓴 파일은 `.specops/.init-written` 에 따로 적어 둘을 가른다(둘 다 종결 뒤 삭제). 사용자가 확인하고 직접 커밋한다. 종결 전에 다시 실행해도(`--resume` 이든 아니든) 이전 실행의 골격은 보류되지 않는다.
- 화면 목록(`screens-overview.md`)에 없는 `screens/*.md`·`*.html` → 목록에 먼저 등록한다(`/design-screen`).

 커밋 실패 시 rc=1 과 사유·재시도 안내가 출력되며 산출물은 staged 로 보존된다. bash 만 단독 실행할 때의 즉시커밋은 `SPECOPS_INIT_COMMIT_NOW=1` 이다.

**무인 계약**: e2e-test-ko·§auto 무인 진입 시 승인 게이트를 **자동수락** 하고 Phase 11.5 인터뷰·가정 **건별 승인을 생략**한다 (HARD GATE 없이 완주 설계 정합). 단 가정 다이제스트·원장 기록은 **무인에서도 수행** — 사후 감사 경로.

## --enrich (소급 보강 단독 실행)

`/init-project --enrich`: Phase 1~10 부트스트랩 **skip** (Process 항목 0 PRD 초안 합성도 skip), Phase 11 만 단독 실행. **bash 스크립트를 부르지 않는다** — `--enrich` 는 이 명령의 모드이지 `init-project.sh` 의 옵션이 아니다(넘기면 rc=2).

- 대상 = 원시 placeholder(`<...>`) 또는 `<미확정 — 근거 필요>` 가 **잔존 문서만** (문서 자체가 상태 — 재실행 멱등 수렴). Light enrich 깊이 규칙 동일.
- 사용자 기작성 본문 무변경 보존.
- 기존 프로젝트(과거 부트스트랩)에 소급 적용하는 경로.
- Phase 11.5 인터뷰·가정 다이제스트 게이트를 **대화형 규칙 그대로** 적용한다 (멱등 계약 유지 — 대상 판정은 위 잔존 기준(원시 placeholder·미확정 마커)과 동일하며, `## §보강 가정 다이제스트` 섹션 내 `가정:` 은 잔존 판정에서 제외).

## 사용 예

```
/init-project mychat
# 기존 기획서가 있으면: /init-project mychat docs/기획서.md (0-a)
# 또는 repo 에 기획 문서(docs/기획서.md · requirements.md 등)를 두면 0-c 가 자동 발견 → 사용 확인 [y/n]
#   (루트의 prd.md 는 macOS 에서 산출물 PRD.md 와 같은 파일이다 — 0-c 의 주의 참고)
→ Phase 0 6필드 확정
→ 종류·헌법 원칙·디자인 방향·화면 이름·DB·API 방식을 사용자와 정한다
→ .specops/.init-answers 작성:
     kind=4
     principles=skip
     prd.oneline=…  prd.persona=…  prd.values=…  prd.m1=…  prd.m2=…  prd.m3=…
     design=1
     screens=home, login, dashboard
     db=y
     api=2
→ bash … init-project.sh --answers .specops/.init-answers mychat
   (빠진 키가 있으면 rc=2 로 목록을 알려 준다 → 채워서 재실행)
→ 14종 골격(해당 KIND 활성분) + 원장 골격 스테이징
→ Phase 11.5 인터뷰 ≤5 → Light enrich → 게이트 1회 [y]
→ bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/init-finalize.sh → "init-finalize: 커밋 완료 <sha> (N파일)"
→ "이제 /start-foundation 또는 /start-all 로 lifecycle 진입하세요"
```

## 안티패턴

- **lifecycle chain 자동 진입 금지** — 본 슬래시는 부트스트랩 **단독**. spec/clarify/plan 등은 `/start` 가 진입.
- **자동 chain 강제 시도 금지** — 5원칙 4 (사용자 주권) 위반.
- **재실행으로 덮어쓰기 금지** — `.specops/memory/` 존재 시 명시 안내 후 [y/N] 확인 (Phase 1).
- **Phase 7(bash)에서 screens 파일 생성 금지** — 화면 초안은 Phase 11 보강, 본설계는 start-all 2.5.
- **stdin 으로 답을 순서대로 밀어 넣기 금지** — 답변 파일(`--answers`)을 쓴다. 스크립트가 rc=2 로 멈추면 출력이 알려 준 키를 채운다(기본값으로 넘어가도록 우회하지 않는다).

## 참조

- `scripts/_internal/init-project.sh` — 본 슬래시의 오케스트레이터
- `templates/{constitution,PRD,CLAUDE,README,DESIGN,project-context,decisions,...}.md` — 14종+원장 템플릿(전체 목록 — KIND 별 부분 활성)
- `skills/using-specops-ko/SKILL.md` — 프로젝트 최초 진입 감지 분기
- `skills/specifying-ko/SKILL.md` — `.specops/memory/*` 자동 감지 (Step 1)

---

*specops-ko v2.17.0 · 2026-10-09 · 답변 파일 · Light enrich · 원장 · Phase7 목록만 · 커밋1*
