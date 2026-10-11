# specops-ko

**Claude Code 전용 한국어 자율 Lifecycle 플러그인** (v2.20.1)

슬래시 1회 또는 자연어 1회로 **spec → clarify → plan → decompose → TDD implement → verify → review → security → integration-test → performance-test → PR** 전 단계를 자동으로 이어서 진행한다.
한글로는 **명세 → 명확화 → 계획 → 분해 → TDD 구현 → 검증 → 리뷰 → 보안 → 통합 테스트 → 성능 테스트 → PR** 이다.

- **자율 chain** — 각 스킬 본문의 `## 다음 skill` 이 다음 단계를 강제한다. 단계마다 지시할 필요가 없다.
- **파일이 기억한다** — 모든 산출물은 `.specops/<FID>/` 에 남는다. 세션이 끊겨도 파일만 읽고 이어간다.
- **주장은 증거로만** — verify 없이 `git commit`·`gh pr create` 하면 훅이 실행 전에 차단한다.

> **도입을 검토 중이라면** → [docs/architecture.md](docs/architecture.md) — 무엇을 보장하고, **어떤 장치로** 보장하며, 무엇을 보장하지 **않는지**를 실측 수치와 함께 정리했다.
> 이 도구가 **자기 결함을 어떻게 다루는가**가 궁금하다면 → [docs/audit/](docs/audit/) — 저자가 동일 루브릭으로 반복 측정한 평가서(최신 9회차 6.6/10 — 8회차 6.3 은 독립 감사 5건으로 방법이 달라지며 새로 드러난 결함이 점수를 깎은 것이고, 9회차는 그 수정 직후의 정적 확인 델타다)와 개선 제안·이후 경과.

---

## 설치

```bash
# 1) 설치
claude plugin marketplace add andyko18/specops-ko
claude plugin install specops-ko@specops-ko

# 2) 확인
/doctor
```

로컬 개발은 `claude plugin marketplace add /절대경로/specops-ko`.

---

## 빠른 시작

```bash
/init-project 재고관리          # 새 프로젝트 — 표준 문서 14종(풀스택 기준 · 종류·선택별 7~14종) 부트스트랩 (1회)
/start-foundation "라우팅·인증"  # 공통 인프라 먼저 (선택, 1회)
/start "CSV 줄 수 세기 CLI"      # 기능 1건 구현
/maintain "auth.js 토큰 만료"    # 기존 코드 수정
/status                         # 지금 어디까지 왔나
```

자연어로 해도 된다 — "CSV 줄 수 세기 CLI 만들어줘" 처럼 쓰면 메타 스킬이 신호를 감지해 라우팅한다.

---

## 알아둘 것

도입 전에 한 번 읽어 두면 시행착오가 줄어드는 사실들이다. 수치는 저자가 쓰는 6개 repo 의 `.specops/` 실측이다(대조군 없음 — 효과가 아니라 **비용**을 보여 주는 숫자다).

### 필요한 도구

| 도구 | 필요성 | 없으면 |
|---|---|---|
| `git` | 필수 | lifecycle 자체가 성립하지 않는다 |
| `jq` | 거버넌스 훅의 필수 의존 | **훅이 전면 fail-open** — 에러 없이 R-1~R-5 차단·감사가 꺼진다. `brew install jq` 후 `/doctor` 의 `deps` 항목으로 확인 |
| `python3` + `pyyaml` | DAG 파서·태스크 id/크기 게이트·훅 킬스위치 | 해당 게이트가 SKIP 되고, 킬스위치(`config.yaml`)를 훅이 읽지 못한다 |
| `gh` | 선택 | `gh pr create` 단계만 수동 |
| `bash` 3.2+ | 필수 | macOS 기본 bash(3.2)에서 동작하도록 작성돼 있다 |
| `semgrep` · `gitleaks` | 선택 | 보안 단계가 내장 self-check(정규식 기반 비밀·위험 함수)만 돌고 결과에 `self-check only` 라고 표기한다 |

검증한 환경은 macOS 와 Linux(ubuntu)다 — CI 가 두 곳에서 전체 스위트를 돌린다. Windows 는 네이티브 셸에서 검증하지 않았다(WSL 을 쓴다).

설치 직후 `/doctor` 를 한 번 돌려 `deps` 항목이 ✅ 인지 본다 — `.specops/` 가 아직 없는 저장소에서는 환경 항목(`deps`·`effort_env`)만 나온다. `/init-project` 뒤에 다시 돌리면 `governance` 를 포함한 전체 항목이 나온다.

### 한 건에 걸리는 시간

- FID 1건(spec → verify)의 **중앙값 약 2시간, p90 약 7.6시간** (`metrics.jsonl` 기록이 있는 48건). 스테이지 단위 시각은 일괄 기록이라 부정확하다.
- 변경이 **약 150줄 미만**이면 산출물(spec·plan·tasks·evidence·dispatch·리뷰)이 변경량보다 훨씬 크다 — 무게가 변경 크기에 비례하지 않는다. 작은 수정은 `/start-lite`·`/maintain-lite` 로 clarify·plan 을 건너뛰되, 화면/IF·Phase B/C·verify 는 유지된다.
- 대화형 `/start` 는 승인 관문(spec 검토·clarify·plan·실행 전환)마다 응답을 기다린다. 첫 코드가 나오기 전에 여러 번의 왕복이 있다.
- **`/init-project`** 는 종류에 따라 답 9~12개를 받는다(프로젝트 종류 · 헌법 원칙 · PRD 6칸 · 디자인 · 화면 이름 · DB · API — 원칙을 직접 적으면 4개 더). 비대화로 돌릴 때는 `--answers-template` 이 키 목록을 내준다. 대화형에서는 문서 보강 단계 앞에 사전 인터뷰가 최대 5문항 있다.
- **경량 경로도 가볍지는 않다.** 3줄짜리 수정을 `/maintain-lite` 로 하면 승인 3~4회(분석 검토 · 설계·의도 통합 승인 · PR) · 스킬 10개 안팎 · 서브에이전트 3종(구현자 · 스펙 리뷰 · 코드 리뷰) · 산출물 9개 안팎(current-state · impact-analysis · intent · spec · AC · tasks · dispatch · reviews · evidence)을 거친다. 줄어드는 것은 clarify·plan 뿐이다. 실측으로 50줄 미만 변경은 산출물이 변경량의 약 50배였고(14건), 소요는 변경 크기와 거의 무관했다 — 이 도구의 비용은 고정비에 가깝다([10회차 평가](docs/audit/2026-10-09-plugin-evaluation-10th.md) 의 실사용 감사).
- **코드를 바꾸는 커밋은 항상 verify 증거를 요구한다.** 정말 필요 없는 변경이면 `SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='<사유>'` 로 우회하되, 사유는 `friction-log` 에 원문째 남는다.

### 적용 범위

- 훅의 **차단·감사·기록**은 cwd 에 `.specops/` 가 있는 repo 에서만 동작한다(없으면 면제). 훅은 `.specops/` 를 스스로 만들지 않는다 — 만드는 것은 훅이 아닌 명시적 호출(`/init-project`·`/start`·`/maintain` 계열 진입, `/gbrain`·`/design-*` 같은 기록 명령)뿐이다. `.specops/` 를 `.gitignore` 한 저장소에서 새 git worktree 를 만들면 그 worktree 는 `.specops/` 없이 시작하므로, lifecycle 에 진입하기 전까지는 면제 상태다. (v2.17.0 이하에서는 Stop 훅이 `.specops/` 없는 repo 에도 `session-progress.md` 를 만들어 그 repo 를 관할로 편입시켰다. 플러그인을 쓰지 않는 repo 에 `session-progress.md` 만 든 `.specops/` 가 남아 있으면 지우면 된다 — `/doctor` 의 `bootstrap` 항목이 알려 준다.)
- 그러나 기본 설치(`user` 범위)는 **모든 repo 의 세션 시작에 메타 스킬을 주입**한다. 일부 repo 에서만 쓰려면 범위를 좁혀 설치한다: `claude plugin install specops-ko@specops-ko --scope project` (또는 `local`). 이미 설치했다면 `claude plugin disable specops-ko` 후 필요한 repo 에서만 켠다.
- 기존 프로젝트에 도입할 때는 `/init-project` 를 먼저 돌리고(표준 문서 부트스트랩), 이후 수정은 `/maintain` 으로 시작한다.
- **주입된 메타 스킬이 하는 일**: 대화에서 기능 요청("X 를 만들어 줘"·"Y 버그 고쳐 줘")을 감지하면 lifecycle 로 진입한다 — `.specops/` 가 없는 repo 에서도 그렇다. 그때 `/init-project` 를 권하는 1줄 안내가 먼저 나오고, 거절해도 명세 단계(`specifying-ko`)로 들어간다. repo 안의 파일을 바꾸지 않는 작업(PPT·Excel·외부 기획서·분석 보고)이나 단순 질문은 진입하지 않는다 — README 같은 repo 안 문서를 고치는 요청은 진입한다. 이 동작을 원하지 않는 repo 에서는 위처럼 설치 범위를 좁힌다.

### 저장소에 생기는 변화

lifecycle 에 진입하면 저장소에 다음이 생긴다 — 진입 전에 알아 둔다.

- **브랜치**: `/start`·`/maintain` 은 `feat/<FID>` 브랜치를 만들어 옮겨 간다(`git checkout -b`). `/start-all` 은 `feat/<BATCH_ID>` 하나를 쓴다.
- **커밋**: 설계 단계가 승인된 `intent.md` 를 커밋하고(추적 대상일 때) 구현 단계가 태스크마다 커밋한다. 커밋은 그 브랜치에만 쌓이고, 마지막에 **PR 을 만들지** 묻는다(push 는 PR 생성에 딸려 간다 · 무인 모드도 PR 직전에는 묻는다).
- **파일**: `.specops/<FID>/` 산출물 · 화면 기능이면 저장소 루트의 `screens/` · API·스키마 기능이면 `.specops/memory/` 의 설계 문서 갱신.
- **PR 뒤**: lifecycle 은 PR 에서 끝난다 — 브랜치는 그대로 남는다. 정리는 머지를 확인한 뒤 `finishing-a-development-branch-ko` 스킬을 직접 불러서 한다(머지 판정을 통과한 로컬 브랜치를 지우고, 원격 브랜치 삭제는 묻는다).

### 끄는 법

- **쓰지 않는 repo 에서 훅을 끌 필요는 없다.** `.specops/` 가 없는 repo 에서 훅은 차단·감사·기록·캡처를 하지 않는다. 끄려고 `.specops/config.yaml` 을 만들지 않는다 — `.specops/` 가 생기는 순간 그 repo 가 관할이 된다. 다만 메타 스킬은 그 repo 에서도 기능 요청을 받으면 lifecycle 로 들어가 `.specops/<FID>/` 와 브랜치를 만든다(위 "적용 범위") — 그것까지 막으려면 설치 범위를 좁히거나 `claude plugin disable` 한다.
- **도입한 repo 에서 일부를 끈다**: 그 repo 의 `.specops/config.yaml` 에 끌 훅만 적는다.
  ```yaml
  hooks:
    pretool-governance:      { enabled: false }   # 커밋·PR 차단
    posttool-governance:     { enabled: false }   # 사후 감사 기록
    stop-governance:         { enabled: false }   # 성공 주장·계획 수정 점검
    freecomment-capture:     { enabled: false }   # 자유작업 캡처(사용자 입력 저장)
    ensure-session-progress: { enabled: false }   # 진행 기록 파일의 자동 생성(Stop 훅) — lifecycle 이 직접 쓰는 기록은 그대로다
  ```
  차단 훅을 끈 채 커밋·PR 이 나가면 `.specops/friction-log.jsonl` 에 `GOVERNANCE-DISABLED` 가 남는다. 이 파일을 읽으려면 `python3` + `pyyaml` 이 있어야 한다(없으면 설정이 무시되고 훅은 켜진 채다 — `/doctor` 의 `deps` 가 알린다).
- **세션 하나에서 줄인다**: `claude` 를 띄우기 **전에** 셸에서 `export SPECOPS_GOVERNANCE_PROFILE=<값>` (세션 안에서 export 하면 훅에 닿지 않는다) — `strict`(기본, 전부) · `standard`(차단·감사·Stop 점검·세션 시작 주입) · `minimal`(차단과 세션 시작 주입만). 괄호 안에 없는 훅은 그 프로파일에서 전부 꺼진다 — `standard` 면 자유작업 캡처·알림·진행 기록 자동 생성·리뷰 보고서 자동 저장이 꺼진다(진행 기록은 lifecycle 이 직접 쓰므로 계속 남는다).
- **커밋 한 건만 넘긴다**: 명령 앞에 붙인다 — `SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='<사유>' git commit …` (사유가 기록된다).
- **아예 쓰지 않는다**: `claude plugin disable specops-ko`.

### 산출물은 기본적으로 로컬이다

`/init-project` 가 만드는 `.specops/.gitignore` 는 **`memory/`·`session-progress.md`·각 FID 의 `intent.md`(의도 문서)만 커밋하고 그 밖의 FID 산출물(`.specops/YYYYMMDD-*/` 의 spec·plan·evidence·리뷰 리포트)은 무시**한다. 의도 문서는 PR 에서 보이지만 나머지는 저장소에 올라가지 않으므로 **PR 리뷰어는 볼 수 없다**. (v2.9.0 이전에 init 한 프로젝트는 FID 디렉토리 전체가 무시된다 — `.specops/.gitignore` 의 규칙을 `…-*/*` + `!…-*/intent.md` 두 줄로 바꾸면 같아진다.) 팀과 공유해야 하면 PR 본문에 핵심(요구·AC·검증 결과)을 옮겨 적거나, `.specops/.gitignore` 의 패턴을 프로젝트 정책에 맞게 바꾼다.

### 설계를 한 화면에서 보기

`/init-project` 가 끝나면 `.specops/design-overview.html` 이 함께 만들어진다 — 설계 문서 전체를 묶은 **읽기 전용 생성물**이다. 그림은 통상 표기를 따른다 — **계층형 시스템 구성도**(사용자 → 채널 → 애플리케이션 → 데이터, 외부 연계 분리, 기술·프로토콜 표기) · **스윔레인 업무 흐름도** · **까마귀발 ERD** · 화면 흐름도. 순서는 설계서 관례대로 **전체 그림 먼저, 상세는 뒤**다 — 개요(PRD) → 시스템 구성 → 요구사항 → 업무 프로세스(프로세스마다 흐름도 아래 정의 표) → 화면(목록 + 설계 전/미리보기 상태) → 인터페이스 → 데이터 → 추적·미결. 요구사항 현황, 추적표, API 목록, 전 문서의 미확정·가정 목록을 함께 모은다. 원본은 계속 마크다운이라 고칠 때는 `.md` 를 고치고 `/design-overview` 로 다시 만든다. 외부 리소스를 참조하지 않아 폐쇄망에서도 열리고, 기본은 git 에 올리지 않는다(공유 전 내부 URL·계정 정보가 실려 있지 않은지 확인).

### 데이터와 프라이버시

- 플러그인 자체의 **텔레메트리·외부 전송은 없다.** 훅은 네트워크를 쓰지 않는다. 기록(`.specops/` 의 friction-log·metrics·session-progress)은 전부 로컬 파일이다.
- 외부 송신이 가능한 유일한 경로는 **외부 모델 의견 병행**(`scripts/critic-ask.sh`, 코드 리뷰 요청 시 diff 를 의견용으로 위탁)이다. provider 는 `claude` → `codex` → `gemini` → `ollama(로컬)` 순으로 **먼저 쓸 수 있는 하나**를 고르고, 한 번에 최대 200KB 만 보낸다. 비밀(자격증명·`.env`·키)이 diff 에 있을 것 같으면 위탁하지 않는 규약이다. 쓰고 싶지 않으면 해당 CLI 를 PATH 에서 빼거나 `CRITIC_BIN` 으로 로컬 도구를 지정한다.
- **자유작업 캡처**(Stop 훅): lifecycle 밖에서 파일을 고친 턴이면 그때의 사용자 입력을 **정규식으로 마스킹하고 2,000자로 자른 뒤** `.specops/pending-capture.jsonl` 에 로컬 저장한다. 정규식 마스킹은 비밀 노출을 완전히 막지 못하며(마스킹 실패 시 입력을 버린다), `.specops/` 가 있는 repo 에서만 캡처한다(v2.17.0 이하는 모든 repo). 끄려면 그 repo 의 `.specops/config.yaml` 에 `hooks.freecomment-capture.enabled: false` 를 적거나 프로파일을 `standard`·`minimal` 로 둔다(위 "끄는 법" — v2.17.0 이하는 끌 수 없었다). 알림 훅(Notification)은 데스크톱 알림을 띄우며 `SPECOPS_GOVERNANCE_PROFILE=standard`(또는 `minimal`)이면 꺼진다.

### 업그레이드 · 삭제

```bash
claude plugin update specops-ko@specops-ko   # 적용하려면 Claude Code 재시작
claude plugin uninstall specops-ko           # 제거
```

- 업그레이드 후 `/doctor` 로 `deps`·`governance`·`statusline` 을 다시 확인한다. 상태바는 `statusline-install.sh` 가 `.claude/settings.json` 의 `statusLine` 키에 **절대경로를 박아 둔** 것이라, 플러그인 버전이 바뀌면 경로가 낡을 수 있다(`scripts/statusline-install.sh --check` 로 미리보기).
- 삭제해도 각 repo 의 `.specops/`·`CLAUDE.md`·`screens/` 는 **남는다**(사용자 데이터). 필요 없으면 직접 지운다. `statusLine` 키도 수동으로 제거한다.

---

## 진입로

| 슬래시 | 용도 |
|---|---|
| `/init-project` | 프로젝트 초기화 — 표준 산출물 14종(풀스택 기준 · 종류·선택별 7~14종) 부트스트랩 (1회) |
| `/start-foundation` | 공통부(라우팅·인증·레이아웃·공통 스키마) 먼저 개발 (1회) |
| `/start` | 신규 기능 1건 — 표준 경로 (대화형) |
| `/start-lite` | 신규 기능 경량 — clarify·plan 생략, 화면/IF·리뷰·verify 유지 |
| `/start-auto` · `/start-lite-auto` | 신규 기능 무인 — 가역 게이트 자동 통과, PR만 확인 (`-lite-auto` 는 clarify·plan 도 생략, 고위험이면 풀 무인 경로로 자동 승격) |
| `/start-all` · `/start-all-auto` | `requirements.md` FR 표 전체 일괄 구현 |
| `/maintain` · `/maintain-lite` | 기존 코드 수정 — 영향 분석 선행 + 회귀 AC 강제 |
| `/maintain-auto` · `/maintain-lite-auto` | 기존 코드 수정 무인 — 분석 검토·설계 승인 자동 통과(분석·회귀 AC·리뷰는 그대로), PR만 확인 |
| `/quick-fix` | 몇 줄짜리 수정 — 명세·분해 문서 없이 테스트 실행 + 코드 리뷰 1회. 크기 상한과 고위험 신호를 커밋 때 훅이 판정하고, 넘으면 `/maintain-lite` 로 간다 |
| `/brainstorming` | (선택) 구현 전 아이디어 탐색 |
| `/design-screen(s)` · `/design-interface(s)` | lifecycle 밖 화면·인터페이스 단발 설계 |

**어느 걸 고를까**

```
새 프로젝트?  → /init-project → (필요 시) /start-foundation → /start-all 또는 기능마다 /start
기존 코드를 고치나?
  ├─ 아니오 (새 산출물) → /start        (무인: /start-auto · 경량: /start-lite · 경량 무인: /start-lite-auto)
  └─ 예   (수정·제거)   → /maintain     (무인: /maintain-auto · 경량: /maintain-lite · 경량 무인: /maintain-lite-auto · 몇 줄짜리: /quick-fix)
```

> `-lite`·`-auto` 는 슬래시로만 진입한다. 자연어 "가볍게 해줘"·"알아서 다 해줘"를 lite·무인으로 추론하지 않는다.
> 무인(`-auto`)은 사람의 확인만 줄인다 — 분석 산출물·회귀 AC·리뷰·verify 는 그대로고, 되돌릴 수 없는 작업·치명 결함·보안 Critical/High 에서는 멈춘다. 자동으로 지나간 것은 PR 직전의 가정 다이제스트에 전부 나온다. `-lite-auto` 는 사람의 검토가 가장 적은 경로라 작은 변경에만 쓴다.

**공통부 · 일괄 진입 주의**

- `/start-all` 전 UI/BE/풀스택은 `.specops/memory/foundation-manifest.md` 필수 (Phase 0 HARD — 없으면 재사용 게이트가 침묵 SKIP)
- foundation 브랜치는 main 머지 후에 `/start-all` (`check-foundation-merged`)
- foundation IF 는 `foundation-baseline`, UI 셸은 `foundation-shell` 마커 — Phase 2.5 는 마커 밖만 건드린다
- `/start-all` 의 `queue.md` 는 `init-batch-queue.sh --classify` 가 기계 작성한다 (재개 시 재사용)
- `[공통]` FR 은 `/start-all` 에서 SKIP — 구현은 `/start-foundation` 담당

---

## Lifecycle

```
/start <기능>  ·  /maintain <대상>  ·  자연어
    ↓
using-specops-ko (메타)            신호 감지 → 신규 / 유지보수 분류
    ↓
analyzing-ko (분석)                current-state.md · impact-analysis.md      [유지보수만] ★ HARD GATE
    ↓
specifying-ko (명세)               spec.md · acceptance-criteria.md
    │                              └ 화면 설계(screens/*.md+html) · 인터페이스 설계(api-spec·data-model)
    ↓ ★ HARD GATE (승인)
clarifying-ko (명확화)             clarifications.md
    ↓ ★ HARD GATE
planning-ko (계획)                 plan.md   ← plan-reviewer-ko (플랜 리뷰)
    ↓
decomposing-ko (분해)              tasks.md + YAML DAG
    ↓
implementing-ko (구현)             태스크별 fresh dispatch · DAG 병렬
    │                              Phase B — spec-reviewer-ko (스펙 준수 리뷰)
    │                              Phase C — code-reviewer-ko (코드 품질·보안 리뷰)
    ↓
verifying-evidence-ko (검증)       evidence.md
    ↓
requesting-code-review-ko (리뷰 요청) → receiving-code-review-ko (리뷰 수용)
    ↓
security-review-ko (보안) → integration-test-ko (통합 테스트) → performance-test-ko (성능 테스트)
    │                       (해당 표면 없으면 graceful skip)
    ↓
"PR 생성? [y/n]" → finishing-a-development-branch-ko (브랜치 정리)
```

**HARD GATE** 는 되돌리기 비싼 지점(analyzing 분석 · specifying 명세 승인 · clarifying 명확화 · planning 계획 · PR)에서만 멈춘다. 나머지는 자동 통과한다.

**질문은 설계에서, 개발은 묻지 않고** — 구현부터 PR 직전까지는 사용자에게 묻지 않는다. 실 DB 적재·외부 API 호출처럼 미리 알 수 있는 작업은 구현 시작 전에 **한 번에** 승인받고, 리뷰 지적은 승인받은 계약(AC·spec) 안이면 고치고 밖이면 다음 작업으로 넘긴다. 묻지 않고 정한 것은 전부 `.specops/<FID>/dev-decisions.md` 에 남아 PR 질문 직전에 한 번에 보고된다(넘긴 것은 PR 본문에도 실린다). 그래도 멈추는 것은 예상 못 한 비가역 작업 · 재시도 뒤에도 남은 치명 결함 · 리뷰어가 절충 선택을 요구한 경우뿐이다 — `skills/implementing-ko/dev-autonomy.md`.

**Generator ↔ Evaluator 분리** — 구현체(`implementer-ko`)와 평가자(`spec-reviewer-ko` · `code-reviewer-ko`)를 다른 서브에이전트로 나눠 자기평가 편향을 막는다. Evaluator 는 `role: evaluator` 로 Write/Edit 가 박탈된다. 기본 `review_mode: end-loaded` (FID 단위 B×1 + C×1), 레거시는 `per-task`.

---

## 산출물

FID 포맷은 `YYYYMMDD-kebab-slug`.

```
.specops/
├── memory/                  api-spec.md · data-model.md · foundation-manifest.md · learnings.jsonl
├── freelog.md               lifecycle 밖 자유작업 기록
└── <FID>/
    ├── spec.md · acceptance-criteria.md · clarifications.md · plan.md · tasks.md
    ├── current-state.md · impact-analysis.md      (유지보수 진입 시)
    ├── dispatch/ · reviews/ · evidence.md
    ├── session-progress.md                        (재개용)
    └── friction-log.jsonl                         (거버넌스 위반 기록)
```

---

## 거버넌스 엔진

훅이 규칙을 강제한다. **PreToolUse** 는 위반 도구 실행을 차단하고, **PostToolUse·Stop** 은 `friction-log.jsonl` 에 기록한다. **SessionStart** 는 메타 스킬 주입 + session-progress rehydrate 를 담당하며, 조립 순서 계약은 `anchor → freecomment-pending → reconcile → batch-resume → 메타 본문 → rehydrate` 다 (행동 지시 블록이 앞). `batch-resume` 는 조건부 — `ACTIVE` 마커가 남은 미완 batch 가 있을 때만 주입된다.

| Rule | 감지 조건 | 동작 |
|---|---|---|
| R-1 | `git commit` 전 verify 미호출 | 사전 차단 + 감사 |
| R-2 | `gh pr create` 전 verify 미호출 | 사전 차단 + 감사 |
| R-3 | 스킬 호출 전 "Using …" 선언 부재 | 감사 |
| R-4 | 성공 주장 + 테스트 러너 미실행 | 감사 (Stop) |
| R-5 | spec/plan 수정 + Advisor 협의 기록 누락 | 감사 (Stop) |
| R-6 | verify 후 gbrain-append 부재 | **비활성** (manual-only 설계) |

**실행-근거 gate** — verify 면제는 자기보고만으로 열리지 않는다. transcript 의 `tool_use ↔ tool_result` 를 join 해 러너가 실제로 `VERIFY: PASS` 를 출력했는지 확인한다.

**면제 4종** — `SPECOPS_GOVERNANCE_BYPASS=1`(+`SPECOPS_BYPASS_REASON` 필수) · docs/design-only 변경 · `.specops/` 부재(미사용 repo) · 판정 불가(fail-open).

---

## 모델 · effort 운용

specops 는 Claude Code 에서 **Sonnet 과 Opus 만** 쓰도록 서브에이전트의 모델과 effort 를 frontmatter 로 고정한다. 별칭만 쓰고 fable 은 쓰지 않는다(플랜에 따라 usage credits 로 과금될 수 있다).

| 서브에이전트 | 모델 · effort | 이유 |
|---|---|---|
| implementer-ko (구현) | sonnet · medium | plan 이 코드를 담아 전사에 가깝고 호출이 가장 많다. 재시도·BLOCKED 때만 부모가 opus 로 1회 상향 |
| spec-reviewer-ko · design-reviewer-ko | sonnet · high | 명세·설계 대조와 명령 실행 |
| plan-reviewer-ko · code-reviewer-ko | opus · high | 계획 결함은 하류에 곱해지고 코드 리뷰는 최종 관문 |
| red-team-ko · blue-team-ko · auditor-ko | 세션 모델 계승 | 드문 self-config 감사 |

외부 critic(`scripts/critic-ask.sh`)도 기본 opus, fallback sonnet 이다(`CRITIC_CLAUDE_MODEL`·`CRITIC_CLAUDE_FALLBACK` 로 변경).

**세션 설정 권장** — 메인 대화의 모델과 effort 는 사용자가 정한다. 기본은 Sonnet 이 한도에 유리하고, 설계가 어려운 명세·계획 단계에서만 `/model` 로 Opus 를 쓴다. 단계별 effort 는 `/effort` 로 조절한다(skill frontmatter 의 effort 동작은 아래 실측을 참고 — specops 는 skill 단위로 고정하지 않는다).

| 단계 | effort 권장 |
|---|---|
| 분석·명세·계획 (analyze·specify·plan) | high — 어려운 설계는 프롬프트에 `ultrathink` |
| 명확화·분해 (clarify·decompose) | medium |
| 구현 조율·검증·리뷰 수신 (implement·verify·review) | low ~ medium |

**effort 우선순위** — 환경변수 `CLAUDE_CODE_EFFORT_LEVEL` 이 가장 높고, 그다음이 서브에이전트 frontmatter, 세션 설정(`/effort`·settings.json 의 `effortLevel`), 모델 기본값 순이다(공식 문서 기준 — 버전에 따라 다를 수 있다). 환경변수를 설정하면 위 프로파일의 effort 가 무시된다. `/doctor` 의 `effort_env` 행이 이 상태를 알린다.

**skill frontmatter effort — 실측 (20261007, Claude Code 2.1.292, 헤드리스 `-p`, sonnet-5-5 1회)** — 훅으로 도구 호출 시점의 effort 를 기록해 확인했다. ① skill 이 **활성화된 이후**의 도구 호출부터 적용된다(Skill 호출 자체는 직전 레벨). ② skill 이 끝나도 **복원되지 않는다** — 같은 턴이 끝날 때까지 마지막으로 활성화된 skill 의 값이 유지된다(중첩·연쇄 모두 마지막 값). ③ 다음 사용자 턴에서 세션 값으로 돌아온다(이 증거는 약하다 — 해당 실행도 `--effort` 를 다시 줬다. 공식 문서 서술과는 일치). ④ 환경변수 `CLAUDE_CODE_EFFORT_LEVEL` 이 있으면 frontmatter effort 가 **전부 무력화**된다(skill 은 위 실험에서 전 구간 env 값으로 고정됨을 확인, agent 는 공식 문서 기준). 함의(마지막 값 유지 실측에서 나온 **추론** — effort 를 지정하지 않은 skill 이 뒤따르는 경우는 직접 측정하지 않았다): specops 는 한 턴 안에서 skill 을 연쇄 호출하므로 **일부 skill 에만 effort 를 지정하면 지정하지 않은 후속 skill 이 직전 값을 물려받을 것으로 추정된다** — 지정하려면 연쇄 전체를 명시하는 전부-또는-전무여야 한다. 그래서 specops 는 여전히 skill 단위로 고정하지 않는다(프로파일 선택은 별도 결정이고 낮춘 effort 의 품질 영향은 측정 전이다). 이 실측은 단일 환경이며, skill 종료 후 비복원·연쇄 호출 시 전파 규칙은 공식 문서에 명시되어 있지 않다.

**agent effort 프로파일 파일럿 (20261008, Claude Code 2.1.292, 헤드리스 `-p`, routed 모드, 갈래당 N=3, 총 약 $16)** — 위 표의 effort 가 근거 없이 정해졌는지 확인하려고 implementing-ko 판별 케이스를 agent 본문 주입(`SKILL_EVAL_INJECT=1`)으로 effort low·medium·high 에서 돌렸다(`SKILL_EVAL_EFFORT`·`SKILL_EVAL_MODEL`·`SKILL_EVAL_CASES`, 사용법은 `scripts/README.md`). 구현자(sonnet) e-6·e-8 은 세 effort 모두 6/6, 코드 리뷰어(opus) e-10·e-12 는 low 6/6 · medium 5/6(e-12 1회 FAIL — 채점 노이즈로 보임) · high 6/6 이다. **낮춘 effort 에서 통과율 하락은 관측되지 않았다**(현행 대비 −10%p 이내 · 판별 케이스 하락 0 — 사전 고정 규칙의 "낮춰도 무방" 방향 신호). 비용(2케이스 1실행 평균)은 구현자가 low 0.50 · medium 0.43 · high 0.47 USD 로 차이가 없고, 리뷰어는 low 1.23 · medium 1.21 · high 1.64 USD 로 high 가 약 35% 비싸다. **한계** — 케이스 2개 × N=3 의 소표본이고 거의 전 갈래가 통과하는 천장이라 effort 민감도를 변별하지 못했을 수 있으며, 짧은 단일 응답이라 실제 리뷰의 다중 파일 diff 읽기·도구 실행과 다르다. 그래서 **프로파일은 바꾸지 않았다.** 비용 절감 후보는 code-reviewer-ko 의 high → medium(약 25%↓)이며, 실제 Phase C 리뷰를 같은 diff 로 두 effort 에서 비교하는 A/B 로 확인한 뒤 판단한다.

**덮어쓰기** — Opus 를 쓸 수 없는 계정이거나 한도를 더 아끼려면 `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` 과 `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` 로 모든 서브에이전트 모델을 강제할 수 있다(Claude Code 공식 문서 기준 — 버전에 따라 다를 수 있으니 문서로 확인). 단 `_FORCE` 를 켜면 Claude 가 Agent 도구의 model 인자로 모델을 지정할 수 없어 implementing-ko 의 opus 상향·모델 fallback override 도 적용되지 않는다.

**한도와 확인** — 세션·주간 한도는 공유되고(Opus·Sonnet 계열별 한도 메시지도 있다) 서브에이전트·병렬 작업은 별도로 소모된다. 플랜별 사용 가능 모델과 Opus 가 Sonnet 보다 한도를 얼마나 더 쓰는지는 공식 문서에 수치가 없다(문서 미확인) — 내 계정에서 `/model` 피커로 쓸 수 있는 모델을 확인하고 Claude Code 의 사용량 표시로 소모를 관찰한다. Opus 를 쓸 수 없다고 나오면 위 덮어쓰기를 쓴다.

---

## 운영 슬래시

| 슬래시 | 용도 |
|---|---|
| `/status` | 진행 중 FID 의 단계·아티팩트 현황 |
| `/doctor` | 설치·환경 건강 진단 9항목 (read-only) |
| `/design-overview` | 설계 문서를 읽기 전용 HTML 한 장으로 — 구성도·프로세스 흐름·ERD 그림, 추적표, 미확정/가정 목록 (`--check` 로 낡음 확인) |
| `/gbrain` · `/log` | 세션 인사이트 조회 · 즉석 기록 |
| `/promote` | 자유작업 mini-FID 를 lifecycle 로 승격 |
| `/security-scan` | 온디맨드 SAST + DAST (`--self-config` 로 자기 번들 적대감사) |
| `/improve-arch` | deep module 기준 split/merge 권고 |
| `/statusline-install` | HUD 상태줄 등록 |
| `/e2e-test` · `/release` | **플러그인 개발자 전용** — lifecycle 9단계 fixture 완주 검증(수동 · 토큰 비용 · 임시 저장소에 파일 생성) · 릴리즈 자동화(플러그인 저장소에서만) |

---

## 자산 구조

```
specops-ko/
├── .claude-plugin/     plugin.json · marketplace.json
├── commands/           슬래시 진입로 29건
├── hooks/              SessionStart · PreToolUse · PostToolUse · Stop · Notification
│                       + rules.jsonl(규칙) · chain.yaml(chain edge 단일 SoT)
├── skills/             flat: skills/<name>/SKILL.md × 30
│                       layer 1 메타 · layer 2 Engine(lifecycle) · layer 3 Harness(원칙)
├── agents/             ← 8건  implementer · spec-reviewer · code-reviewer · plan-reviewer
│                              design-reviewer · red-team · blue-team · auditor
├── templates/          ← 37건 (lifecycle 20 + /init-project 산출 14 + 기타 3)
├── scripts/            doctor · release · gbrain · security-scan · dag/ · tests/ · _internal/
├── docs/               설계 노트 · 갭 분석 · upstream drift log · audit/(자기 평가·제안 스냅샷)
└── CLAUDE.md · DESIGN.md · CONTRIBUTING.md · CHANGELOG.md
```

내부 규약 상세(chain SoT · 분기 마커 · frontmatter 필수 필드 · design-first 대칭)는 [CLAUDE.md](CLAUDE.md), 설계 근거·한계·규모 실측은 [docs/architecture.md](docs/architecture.md) 참조.

---

## 개발 · 테스트

> **clone 마다 1회**: `bash scripts/_internal/install-git-hooks.sh` — pre-commit(구조 검증 ~5s) + pre-push(전체 테스트 ~330s) 게이트 설치.

```bash
bash scripts/tests/run-all.sh                    # 전체 (릴리즈 pre-flight 게이트와 동일)
bash scripts/_internal/validate-structure.sh     # 구조 무결성
bash scripts/tests/governance/test-rules.sh      # 거버넌스 R-1~R-6
bash scripts/tests/dag/test-parse-dag.sh         # DAG 파서
bash scripts/tests/llm-eval/run-evals.sh         # LLM smoke (수동, 토큰 비용)
```

### 릴리즈 주기

- **대상은 행동 변경뿐이다** — `skills/`·`commands/`·`agents/`·`hooks/`·`templates/`·`scripts/`(테스트 제외)의 동작이 바뀐 것. 테스트·문서·주석·CHANGELOG 만 바뀐 PR 은 `[Unreleased]` 에 두고 릴리즈하지 않는다(판정 기준은 거버넌스 훅의 플러그인 런타임 예외와 같다 — `CLAUDE.md` `## 거버넌스 엔진`).
- **주 1회 상한** — 행동 변경이 쌓이면 주제가 닫히는 시점 또는 주 1회 묶어 발행한다. PR 마다 발행하지 않는다(2026-10-01~11 에 22회 발행 → 플러그인 캐시에 버전 18개, 하류 프로젝트가 제각각의 버전에 고정됐다).
- **예외** — 훅이 정상 커밋·PR 을 막거나 설치본이 깨지는 오류는 즉시 패치 릴리즈.
- 발행 절차는 그대로다(`scripts/release.sh` · 독립 clone 에서 · 사용자 승인).

**검증 현황** — lifecycle dogfood 5회 완주 · 전체 suite PASS · 거버넌스 p95 69ms (AC-8 < 200ms).
테스트 37,307줄 / 운영 스크립트 13,862줄 = **2.7 : 1** · mutation score 60% (기준 55%) · 구조 검사기 27종.

---

## 트러블슈팅

| 증상 | 조치 |
|---|---|
| commit 이 verify 누락으로 deny | 정상(R-1). verify 실행 후 재시도. 불가피하면 `SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='<사유>'` |
| `file_counts FAIL` | `validate-structure.sh --update-baseline` |
| `version_sync` · `readme_counts FAIL` | README 헤더/footer 버전, 자산 구조 카운트가 실측과 불일치 |
| `chain_consistency FAIL` | `chain.yaml` · SKILL.md `## 다음 skill` · 메타 스킬 목록 세 곳 동기 수정 |
| 어디까지 했는지 모름 | `/status` · 환경 이상은 `/doctor` |

---

## 라이선스 · 출처

**MIT** — [LICENSE](LICENSE). `Copyright (c) 2026 andyko18`.

### 상류 프로젝트

이 플러그인의 **skill 구조와 여러 패턴은 아래 프로젝트에서 왔다**. 각 파일의 `reference_upstream`
frontmatter 가 어디서 무엇을 가져왔는지 개별로 밝힌다(실측 54건).

| 프로젝트 | 라이선스 | 이 repo 에서 |
|---|---|---|
| [obra/superpowers](https://github.com/obra/superpowers) | MIT | skill 계층·harness 구조의 원형 |
| [obra/omc](https://github.com/obra/omc) | — | 릴리즈 패턴 일부 |
| [revfactory/harness](https://github.com/revfactory/harness) | — | harness 패턴 4건 |
| [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) | — | `karpathy-ko` 원형 |
| [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) v4.13.0 | MIT | 최소 범위(YAGNI) rung 사다리(4 skill, v2.3.0) · 과잉 설계 리뷰 태그·`shortcut:` 부채 장부(`code-reviewer-ko`·`scan-shortcuts.sh`) · `/improve-arch --lean` 감사 |
| [github/spec-kit](https://github.com/github/spec-kit) · garrytan/gstack · mattpocock · alirezarezvani/claude-skills | — | 패턴 번안·한국어 재창작 |

> **원본 코드를 복사(vendoring)하지 않았다.** 전부 패턴 참조 · 번안 · 한국어 재창작이고,
> `reference_upstream` 에 `specops-ko 독자 추가` 로 표시된 것(실측 30여 건)은 상류에 대응물이 없는
> 자체 설계다. 상류 라이선스 확인 결과 지배적 출처(superpowers)가 MIT 라 본 repo 의 MIT 와 호환된다.
> 표에서 라이선스를 `—` 로 둔 것은 **확인하지 않았다는 뜻**이다 — 해당 프로젝트 코드를 복사하지
> 않았으므로 라이선스 의무가 발생하지 않는다고 판단했으나, 그 판단 자체는 검증되지 않았다.

---

*초기화: 2026-04-21 · v1.0.0 릴리즈: 2026-04-26 · **최신: v2.20.1 (2026-10-11)** · Claude Code 전용*