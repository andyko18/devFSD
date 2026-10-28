# 도입 전 알아둘 것

> README 의 `## 알아둘 것` 요약에서 넘어온 전체 문서다. 요약만 보려면 [README](../README.md#알아둘-것) 로 돌아간다.

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

- FID 1건(spec → verify)의 **중앙값 약 2시간, p90 약 7.6시간** (`metrics.jsonl` 기록이 있는 48건). 스테이지 단위 시각은 일괄 기록이라 부정확하다. 속도 개선(v2.32~2.36: 승인 1회·리뷰 병렬·전문가 동시 실행) 전 측정이다. 개선 뒤 수치는 아직 재지 않았다.
- 변경이 **약 150줄 미만**이면 산출물(spec·plan·tasks·evidence·dispatch·리뷰)이 변경량보다 훨씬 크다 — 무게가 변경 크기에 비례하지 않는다. 작은 수정은 `/start-lite`·`/maintain-lite` 로 clarify·plan 을 건너뛰되, 화면/IF·Phase B/C·verify 는 유지된다.
- 기본 동작은 질문 묶음 최대 2회와 승인 묶음 1회 뒤 PR 직전까지 묻지 않는다. `--step` 을 붙이면 단계마다(spec 검토·clarify·plan·실행 전환) 응답을 기다린다.
- **`/init-project`** 는 종류에 따라 답 9~12개를 받는다(프로젝트 종류 · 헌법 원칙 · PRD 6칸 · 디자인 · 화면 이름 · DB · API — 원칙을 직접 적으면 4개 더). 비대화로 돌릴 때는 `--answers-template` 이 키 목록을 내준다. 대화형에서는 문서 보강 단계 앞에 사전 인터뷰가 최대 5문항 있다.
- **경량 경로도 가볍지는 않다.** 3줄짜리 수정을 `/maintain-lite` 로 하면 승인 묶음 1회와 PR · 스킬 10개 안팎 · 서브에이전트 3종(구현자 · 스펙 리뷰 · 코드 리뷰) · 산출물 9개 안팎(current-state · impact-analysis · intent · spec · AC · tasks · dispatch · reviews · evidence)을 거친다. 줄어드는 것은 clarify·plan 뿐이다. 실측으로 50줄 미만 변경은 산출물이 변경량의 약 50배였고(14건), 소요는 변경 크기와 거의 무관했다 — 이 도구의 비용은 고정비에 가깝다([10회차 평가](audit/2026-10-09-plugin-evaluation-10th.md) 의 실사용 감사).
- **코드를 바꾸는 커밋은 항상 verify 증거를 요구한다.** 정말 필요 없는 변경이면 `SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='<사유>'` 로 우회하되, 사유는 `friction-log` 에 원문째 남는다.

### 적용 범위

- 훅의 **차단·감사·기록**은 cwd 에 `.specops/` 가 있는 repo 에서만 동작한다(없으면 면제). 훅은 `.specops/` 를 스스로 만들지 않는다 — 만드는 것은 훅이 아닌 명시적 호출(`/init-project`·`/start`·`/maintain` 계열 진입, `/gbrain`·`/design-*` 같은 기록 명령)뿐이다. `.specops/` 를 `.gitignore` 한 저장소에서 새 git worktree 를 만들면 그 worktree 는 `.specops/` 없이 시작하므로, lifecycle 에 진입하기 전까지는 면제 상태다. (v2.17.0 이하에서는 Stop 훅이 `.specops/` 없는 repo 에도 `session-progress.md` 를 만들어 그 repo 를 관할로 편입시켰다. 플러그인을 쓰지 않는 repo 에 `session-progress.md` 만 든 `.specops/` 가 남아 있으면 지우면 된다 — `/doctor` 의 `bootstrap` 항목이 알려 준다.)
- 그러나 기본 설치(`user` 범위)는 **모든 repo 의 세션 시작에 메타 스킬을 주입**한다. 일부 repo 에서만 쓰려면 범위를 좁혀 설치한다: `claude plugin install devfsd@devfsd --scope project` (또는 `local`). 이미 설치했다면 `claude plugin disable specops-ko` 후 필요한 repo 에서만 켠다.
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
claude plugin update devfsd@devfsd   # 적용하려면 Claude Code 재시작
claude plugin uninstall specops-ko           # 제거
```

- 업그레이드 후 `/doctor` 로 `deps`·`governance`·`statusline` 을 다시 확인한다. 상태바는 `statusline-install.sh` 가 `.claude/settings.json` 의 `statusLine` 키에 **절대경로를 박아 둔** 것이라, 플러그인 버전이 바뀌면 경로가 낡을 수 있다(`scripts/statusline-install.sh --check` 로 미리보기).
- 삭제해도 각 repo 의 `.specops/`·`CLAUDE.md`·`screens/` 는 **남는다**(사용자 데이터). 필요 없으면 직접 지운다. `statusLine` 키도 수동으로 제거한다.
