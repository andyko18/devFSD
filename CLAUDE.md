# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

specops-ko는 **Claude Code 전용 한국어 자율 Lifecycle 플러그인**이다. 슬래시 1회(`/start`, `/start-lite`, `/maintain`, `/maintain-lite` 와 각각의 무인 변형 `-auto`) 또는 자연어 진입 후 메타 스킬이 spec → (clarify → plan) → TDD implement → verify → review → security → integration-test → performance-test → PR 전 단계를 자동 chain한다. `/start-lite`·`/maintain-lite`는 clarify·plan ceremony만 생략하고 화면/IF·Phase B/C·verify는 유지한다(NL로 lite 추론 금지). 몇 줄짜리 수정은 `/quick-fix` 가 chain 밖에서 받는다 — 문서 없이 테스트 실행 + 코드 리뷰 1회이고, 범위 상한은 커밋 때 훅이 판정한다(아래 거버넌스 엔진의 quick 경로). Conductor 에이전트 없이 각 SKILL.md 본문의 `## 다음 skill` 섹션이 다음 단계를 강제한다.

## 테스트 명령

> **clone 마다 1회**: `bash scripts/_internal/install-git-hooks.sh` — 2단 git hook 게이트를 설치한다 (`core.hooksPath` 는 `.git/config` 로컬 설정이라 버전관리되지 않는다). `pre-commit` = validate-structure + check-propagation(~5s) · `pre-push` = origin main **CI 상태 경고**(`gh` 있을 때만, ~1s, 비차단) + `run-all.sh` 전체(**192 스위트** <!-- doc-lock: suite-count --> · 작업자 풀 병렬 — 2026-09-11 실측 median 병렬 382s(5회) / 직렬 813s(3회). `SPECOPS_RUN_ALL_JOBS` 로 병렬 수 지정(기본 코어 수·상한 8, `1`=직렬). 스위트별 600s 상한). **Claude Code PreToolUse 훅(R-1)은 Cursor 등 다른 도구의 커밋에 발화하지 않으므로**, 로컬의 도구 무관 게이트는 이 층뿐이다 (계기: run-all 없이 나간 커밋이 main 을 하루 red 로 만들었다). 원격에는 main 브랜치 보호가 있다(20261010 — PR 머지는 CI 4종 `run-all`·`run-all-macos`·`shellcheck`·`security-scan` 통과가 필요하다. 관리자의 직접 push 는 막지 않는다: `release.sh` 가 main 에 직접 push 한다). 탈출구는 `--no-verify`.

> **릴리즈 주기** (20261011 결정): 릴리즈 대상은 **행동 변경**(skill·command·agent·hook·template·비테스트 script 의 동작 변화)뿐이고, **주 1회 상한**으로 묶어 발행한다. 테스트·문서·주석만의 PR 은 `[Unreleased]` 에 둔다. 예외는 훅이 정상 커밋을 막거나 설치본이 깨지는 오류(즉시 패치). PR 마다 발행하지 않는다 — 10월 1~11일 22회 발행으로 하류가 제각각 버전에 고정됐다. 상세는 README `### 릴리즈 주기`.

```bash
# 전체 테스트 (run-all.sh — 릴리즈 pre-flight 게이트와 동일)
bash scripts/tests/run-all.sh
# 병렬 수 지정·직렬 강제: SPECOPS_RUN_ALL_JOBS=1 bash scripts/tests/run-all.sh
#   CPU 경합에 약한 시간 임계 스위트는 파일 선두 20줄에 `# run-all: serial — <사유>` 를 달면 병렬 풀 종료 뒤 하나씩 돈다.

# 숨은 실 트리 쓰기 탐지 (수동 — 스위트 격리를 바꿀 때. 확정=실 트리 쓰기 · 검토=상대경로라 사람이 판정)
bash scripts/tests/find-tree-writes.sh -j 6

# LLM 동작 smoke eval (수동 전용 — 토큰 비용 발생, run-all 비포함)
bash scripts/tests/llm-eval/run-evals.sh
# LLM eval N-run 신뢰성 (수동 — flakiness 측정): LLM_EVAL_RUNS=10 bash scripts/tests/llm-eval/run-evals.sh
#   fixture별 성공률·FLAKY(<80%) 리포트. 기본 N=1 은 기존 단발 동작.
# 주간 자동 smoke: .github/workflows/llm-smoke.yml (ANTHROPIC_API_KEY secret 등록 시 활성 — 미등록 시 graceful skip)
# skill 별 활성화·행동 eval (수동 전용 — 토큰 비용, run-all 비포함 · 데이터 계약은 test-skill-evals.sh 가 run-all 에서 잠금)
#   ANTHROPIC_API_KEY 있으면 isolated(--bare, 실측 미확인 — unverified 표기) · 없으면 routed(메타 라우팅 혼합)
bash scripts/tests/llm-eval/run-skill-evals.sh --trigger   # 또는 --evals · 뒤에 skill 이름으로 대상 한정
#   agent 본문 주입(with/without 비교, 토큰 비용 — 수동·별도 승인): SKILL_EVAL_INJECT=1 bash scripts/tests/llm-eval/run-skill-evals.sh --evals implementing-ko (케이스 `agent` 필드 · 갈래당 N≥3 · 프로토콜은 scripts/README.md)
#   agent effort·model arm 비교(토큰 비용 — 수동·별도 승인): SKILL_EVAL_EFFORT=<level> SKILL_EVAL_MODEL=<m> (candidate 질의에만 적용 · 프로토콜은 scripts/README.md 의 파일럿 절 · 판별 4케이스만: SKILL_EVAL_CASES=e-6,e-8,e-10,e-12)
#   행동 eval 의 llm_rubric 채점기 보정 (수동 — 채점 호출 ≈ $5~8, 오답 오통과 0 이고 일치 ≥ 90% 일 때만 ADOPT):
bash scripts/tests/llm-eval/run-judge-calibration.sh

# 결정론 skill 라우팅 eval (토큰 0 — description 충돌·드리프트, warn-first. 기준선 갱신은 scripts/README.md 의 skill-routing-eval 절 참조)
bash scripts/skill-routing-eval.sh

# lifecycle E2E 자동 검증 (수동 전용 — 토큰 비용 발생, run-all 비포함)
# e2e-test-ko skill 이 greet-cli fixture 로 9단계 chain 완주 + 산출물 구조 검증
/e2e-test

# Phase 2.5 dogfood (수동 전용 — 토큰 비용, run-all 비포함)
# scripts/tests/dogfood/phase25-checklist.md

# 거버넌스 규칙 테스트 (R-1~R-6, 전 항목 PASS 목표)
bash scripts/tests/governance/test-rules.sh

# DAG 파서 테스트 (전 항목 PASS 목표)
bash scripts/tests/dag/test-parse-dag.sh

# 플러그인 구조 무결성 검증 (전 항목 ✅ 목표)
bash scripts/_internal/validate-structure.sh

# 문서 수치 doc-lock (run-all 은 test-doc-numbers.sh 스위트를 통해 이 검사를 돌린다 — 단독 실행도 가능)
bash scripts/_internal/check-doc-numbers.sh
```

> **스위트는 스스로 격리한다** (20261011): `scripts/tests` 아래 모든 `test-*.sh` 는 첫 코드 줄(`set -u`) 바로 뒤에서 git 저장소 변수 7개를 지운다(`unset GIT_DIR …` — `.githooks/pre-push` 와 같은 목록). 훅이 내보낸 `GIT_DIR` 이 남은 환경에서 스위트를 `run-all` 없이 직접 돌리면(영수증·검증 러너·변이 측정·수동 실행) 픽스처의 git 명령이 임시 저장소가 아니라 실저장소에 실행되기 때문이다 — 2026-10-06 에 픽스처 커밋 50개가 그렇게 실 origin 의 브랜치로 push 됐고, 희생용 복제본 실측에서 스위트 191개 가운데 32개가 저장소를 바꿨다(그중 11개는 통과로 끝났다). **새 스위트에도 같은 줄을 넣는다** — 빠지면 `test-git-hooks.sh` GH-env.4 가 그 파일을 대며 실패한다(GH-env.6 은 사고의 두 스위트를 훅 환경에서 직접 돌려 저장소·원격이 그대로인지 본다). 재현 실험은 희생용 복제본과 로컬 원격에서만 한다.

## 아키텍처

### Skill 계층 구조

```
skills/<name>/SKILL.md   ← 플랫 구조, layer 필드로 계층 구분
```

- **layer: 1** — 메타 스킬 (`using-specops-ko`): SessionStart 훅으로 자동 주입, 신호 감지 후 chain 진입
- **layer: 2** — Engine Skills: Lifecycle 체인의 각 단계 (specifying → clarifying → planning → decomposing → implementing → verifying → reviewing → security-review → integration-test → performance-test → PR)
- **layer: 2** — `karpathy-ko`: cross-cutting 행동 원칙 (Think·Simplicity·Surgical·Goal), 구현 단계 자동 활성
- **layer: 3** — Harness Skills: 아키텍처 원칙 강제 (sprint-contracts, structured-artifacts, generator-evaluator, context-resets, file-based-communication) + e2e-test-ko (lifecycle E2E 자동 검증)

chain 의 primary edge 는 `hooks/chain.yaml` 이 단일 Source of Truth 다 — 각 SKILL.md `## 다음 skill` 코드블록·메타 skill chain 목록과의 drift 는 `validate-structure.sh` `chain_consistency` 검사가 적발한다 (edge 변경 시 세 곳 동기 수정).

### 거버넌스 엔진

거버넌스 훅 이벤트 4종(+ `Notification` → `notify.sh` 보조 1종)이 자동 실행되며, `hooks/rules.jsonl`에 정의된 6개 규칙 중 R-1~R-5 를 검사한다 (R-6 은 `enabled: false` — gbrain-ko manual-only 설계):

- `SessionStart` → `session-start.sh`: 메타 스킬 주입 + session-progress rehydrate. **조립 순서 계약**: `specops-ko-anchor` → `freecomment-pending` → `session-progress-reconcile` → `batch-resume`(조건부 — ACTIVE 마커 있는 미완 batch 존재 시) → 메타 본문 → `session-progress-rehydrate` — harness 는 훅 출력 1건이 **문자 10,000**(UTF-16 단위 — JS length, 바이트·코드포인트 아님)을 넘으면 파일로 빼고 선두 2KB 프리뷰만 인라인하므로 행동 지시 블록을 앞에 두고, 총량은 **예산 9,500자 가드**(넘치면 rehydrate 만 절단 + 생략 포인터)로 한도 아래에 둔다 (`scripts/tests/test-session-start-order.sh` 가 잠금)
- `PreToolUse` → `pretool-governance.sh` (v1.14.0 신설): R-1(commit 전 verify)·R-2(PR 전 verify) **사전 차단(Hard block)** — verify 누락 시 `git commit`·`gh pr create` 실행 전 deny. **관할 한정**: cwd 에 `.specops/` 부재 시(specops 미사용 repo) 면제 — 플러그인은 자기 관할 repo 만 통제(5원칙 4 주권). 면제 **4종**: `SPECOPS_GOVERNANCE_BYPASS=1`(인라인 사용 시 `SPECOPS_BYPASS_REASON='<사유>'` 병기 필수 — 무사유는 deny) · docs/design-only 변경(`*.md`·`*.txt`·`*.rst` + `screens/*.html`·`.specops/*`) · `.specops/` 부재 · fail-open(transcript 부재·tool_use 이벤트 0건(rc=2)·rules·jq 판정 불가)

> **플러그인 런타임 예외** (`_files_all_docs`): `.claude-plugin/plugin.json` 이 있는 repo 에서는 `skills/*/SKILL.md`·`commands/*.md`·`agents/*.md`·`templates/*.md`·`hooks/*`·`.claude-plugin/*` 이 **확장자와 무관하게 코드**다. 같은 트리라도 `skills/*/README.md`·루트 `README`·`CHANGELOG`·`CLAUDE.md` 는 면제 유지(배포 런타임 아님). (근거·이력: docs/governance-history.md §1)
- `PostToolUse` → `posttool-governance.sh`: R-1(commit 전 verify), R-2(PR 전 verify) **감사 기록(Soft Warn)**, R-3(스킬 선언 투명성). 기록 시 `_audit_scope_class` 로 **방금 액션의 커밋 범위**(R-1 `HEAD~1..HEAD` · R-2 `base...HEAD`)를 분류해 `scope_class` 필드를 남긴다 — 면제 시엔 기록 자체가 없으므로 posttool 기여분에 `docs-only` 는 구조적으로 나타나지 않고 `code`·`empty`·판정불가(필드 부재)만 쌓인다. matcher 는 `Bash|Skill` 이다(모든 posttool 규칙의 `trigger_tool` 집합 — `test-manifest.sh` T12.h·T12.i 가 잠금). Bash 는 R-1/R-2 `trigger_pattern` 사전 필터(pretool 동형)로 커밋·PR 이 아닌 명령을 git 호출 전에 끝낸다 — **판정 불가(정규식 로드 실패·정규식 오류)면 조기 종료하지 않고 종전 경로**로 간다(감사층은 기록 보존이 안전 · `test-hooks.sh` T8.h~T8.k).
- `Stop` → 3 훅 발화: `ensure-session-progress.sh`(session-progress.md 보장 — `.specops/` 가 없으면 아무것도 만들지 않는다) + `stop-governance.sh`(거버넌스: R-4 성공 주장 + 테스트 미실행, R-5 plan 수정 + Advisor 협의 누락(협의를 **주장**하면 transcript 실호출 증거 요구 — `server_tool_use`(advisor)↔`advisor_tool_result` 또는 `critic-ask.sh`. `해당 없음` 정직 선언은 증거 불요), R-6 `/verify` + evidence.md 후 gbrain-append 호출 부재 — 비활성) + `freecomment-capture.sh`(자유 코멘트 자동 캡처 — pending 적재, SessionStart 에서 LLM 요약→freelog.md · `.specops/config.yaml` 의 `hooks.freecomment-capture.enabled: false` 나 프로파일 `standard`·`minimal` 로 끈다)

**관할 한정은 pretool 만의 것이 아니다** — 기록을 남기는 나머지 훅(`posttool-governance`·`stop-governance`·`freecomment-capture`·`ensure-session-progress`)도 `.specops/` 가 없는 repo 에서는 판정·기록·생성을 하지 않는다. 훅이 `.specops/` 를 만들면 그 repo 가 관할로 편입돼 다음 커밋부터 R-1 이 막는다(실측 20261009: 플러그인을 쓰지 않는 repo 4곳에 흔적). 디렉토리는 관할을 여는 쪽(`/init-project` · specifying-ko 의 FID 생성 · `session-progress-append.sh`)만 만든다.

R-1/R-2 는 **pretool=강제 차단 / posttool=감사** 로 역할이 분리된다(면제·fail-open 시 posttool audit trail 보존). 그 외 위반은 `.specops/<FID>/friction-log.jsonl`에 Soft Warn으로 기록된다.

> **면제 조회 — "이 커밋은 면제됩니까"를 미리 묻는다**: `bash scripts/_internal/scope-explain.sh '<커밋 명령>'`(인자, 또는 stdin 파이프)이 훅과 **같은 판정 함수**를 불러 `SCOPE=staged|conservative EXEMPT=yes|no REASON=<class>(<N> files)` 1줄로 답한다. rc 계약: **0=판정 성공 · 2=입력 없음/읽기 불가 · 3=판정기 로드 불가** — 판정 불가를 그럴듯한 1줄로 위장하지 않는다. 훅 경로에서 묻고 싶으면 `SPECOPS_DRYRUN=1`(env 또는 **명령 선두 인라인**)을 붙인다: 같은 1줄을 stderr 로 내고 **deny 한다** — 조회이므로 커밋을 실행하지 않는다(allow 를 한 건도 늘리지 않는 deny 전용 경로). ⚠️ **DRYRUN 의 관할 경계**: `.specops/` 부재 repo 와 **사유를 병기한** `SPECOPS_GOVERNANCE_BYPASS=1`(무사유는 deny 라 실행되지 않는다) 사용 시에는 훅이 **그 앞 분기에서 이미 빠져나가** DRYRUN 이 무시되고 커밋이 **실제로 실행된다**(실측: 두 경우 모두 `{"continue":true}`) — 조회 의도였다면 커밋이 나간 뒤에야 알게 되므로, 그 두 상황에서는 `scope-explain.sh` 를 쓴다. (근거·이력: docs/governance-history.md §2)

**실행-근거 gate** (v1.45.0, `governance-lib.sh:_verify_exec_evidence`): R-1/R-2 의 verify 면제는 **자기보고만으로 열리지 않는다**. transcript 가용 시, 자기보고 면제 3경로 — session-progress 의 `/verify PASS` 줄 · evidence.md 의 `RUN-VERIFICATION-RESULT` 스탬프 · `verifying-evidence-ko` Skill 호출 — 는 **무엇이 있든** transcript 의 `tool_use` ↔ `tool_result` 를 `tool_use_id` 로 join 해 검증 러너가 **실제로 실행되어 `VERIFY: PASS` 를 출력했는지** 확인한 뒤에만 면제된다 (`VERIFY: PARTIAL`·`FAIL`·`is_error` 는 불인정). 모델이 spec.md 에 스스로 쓰는 `§auto: true` 라벨의 **무조건 면제는 제거됐다** — 자기발급 면제표였기 때문이다. 무인 모드(`/start-auto`)도 chain 에 verify 가 있어 실제 실행하므로 정직한 흐름은 그대로 통과한다. 판정 불가(transcript 부재·tool_use 이벤트 0건(rc=2)·jq 실패)는 fail-open.

> 러너 명령에 FID 가 글자로 적혀 있는데(`run-verification.sh <FID>`) 그것이 활성 FID 가 아니면 실행 증거로 치지 않는다 그리고 판정 SoT(`verification-state.sh current`)가 `STALE` 이면 진행 기록·스탬프가 있어도 R-1 은 열리지 않는다 `STALE` 이어도 막지 않는 경우는 둘이다(`_vs_stale_blocks`) — 전체 스위트가 **지금 이 트리**에서 통과했거나(`full-suite-fresh.sh` rc 0 — `run-all.sh` 는 판정 상태를 갱신하지 않는다), 달라진 것이 추적하지 않는 파일뿐일 때(`verification-state.sh stale-scope` = `untracked-only` — 기록의 `tracked_nondoc_hash` 와 대조 · 커밋만 실행하는 명령(`git commit [-a] -m …` 한 줄 — `_commit_scope_is_staged`)일 때만 · compound·파이프·경로 인자는 조회용 명령과 함께여도 제외). (근거·이력: docs/governance-history.md §3)

> 트리거(`hooks/rules.jsonl` R-1·R-2 `trigger_pattern`)는 명령 위치의 `git commit`·`gh pr create` 를 env 접두·래퍼(`rtk`·`time`·`nice`·`sudo`·`env` 와 그 옵션 · `exec`·`nohup`·`timeout N`)·제어 키워드(`then`·`do`·`else`·`if`·`while`·`!`)·`case` 가지 뒤, 경로로 부른 형태(`/usr/bin/git`), 줄 연속, `gh pr -R … create` 까지 인식한다. `sh -c`·`eval`·`xargs`·alias·변수에 든 명령은 여전히 범위 밖이다 pretool 을 설정으로 끈 채 커밋·PR 이 나가면 repo 레벨 friction-log 에 `GOVERNANCE-DISABLED` 가 남는다(끄는 것 자체는 막지 않는다). (근거·이력: docs/governance-history.md §4)

> 실행 증거(`_exec_rc ≠ 1` — `0`=러너 실행 확인 · `2`=판정 불가 fail-open)는 자기보고 3경로를 **여는 전제조건**이지 단독 면제가 아니다. 앵커가 하나도 없으면 러너를 몇 번 돌려도 통과하지 않는다. R-1 의 implement 창은 FID 에 `tasks.md` 가 있고 **verify 가 아직 유효 PASS 가 아닐 때**(`verification-state` 가 `NOT_RUN`·`PARTIAL`·`FAIL`) 열리며 receipt 로 면제된다 — 종전의 `evidence.md 부재` 조건은 구현 중 태스크가 그 파일을 쓰면 남은 태스크의 탈출구를 닫았다. `STALE`·`WAIVED` 는 창이 닫힌다. deny 메시지는 세 조건(①·②·receipt)의 **실제 상태**를 표시한다(`cause` 진단이 없거나 파싱 실패면 종전 무조건 3블록 문안으로 떨어지고 deny 는 유지된다). (근거·이력: docs/governance-history.md §5)

> **quick 경로** (20261010): 태스크 문서는 있고 명세(`spec.md`)가 없는 FID 는 `/quick-fix` 의 FID 다. R-1 의 receipt 경로가 그대로 쓰이되(테스트 실제 실행 · staged ⊆ outputs · 트리 신선도), `check-task-receipt.sh` 가 판정기(`scripts/_internal/quick-scope.sh`)를 불러 **범위**(구현 파일 수 · 변경 줄 수 상한 — 테스트·문서 제외 · 고위험 신호 없음. 수치는 판정기 머리의 상수가 유일한 정의다)와 **리뷰**(통과 판정의 `reviews/T1-C-report.md` 가 마지막 수정보다 새것)를 함께 요구한다. 넘으면 deny 하고 `/maintain-lite` 를 안내한다(`cause.receipt = quick-over | quick-noreview`). quick 구조의 FID 는 **verify 상태와 무관하게** 이 판정을 받는다 — 검증 러너가 PASS 를 내도 영수증 가지를 타고(`_quick_structure`), 스테이징된 것만 커밋하는 명령이 아니면(`-a`·경로 인자·다른 명령과 묶음) 막는다(`cause.receipt = quick-unstaged`). (근거·이력: docs/governance-history.md §6)

### 서브에이전트 리뷰 패턴 (Generator ↔ Evaluator 분리)

Generator와 Evaluator를 엄격히 분리해 자기평가 편향을 차단한다. `agents/` 의 서브에이전트는 용도가 나뉜다:

- **구현 2단계** (`implementing-ko` 가 태스크별 fresh dispatch): **Phase B** `spec-reviewer-ko`(스펙 준수만) → PASS 후 **Phase C** `code-reviewer-ko`(코드 품질·보안·커버리지·DB 관점).
- **설계 리뷰** (`planning-ko` 가 dispatch): `plan-reviewer-ko` — TDD 커버리지·플레이스홀더·파일 경계·타입 일관성 + 실측 의무.
- **batch 화면·IF 리뷰** (`/start-all` Phase 2.5-D): `design-reviewer-ko` — Interactions↔api-spec·data-model 정합·껍데기·cross-FR + 실측 의무.
- **self-config 적대감사** (`/security-scan --self-config`): `red-team-ko`(공격 표면 탐색) → `blue-team-ko`(기존 방어 유효성 평가) → `auditor-ko`(종합 risk 등급 A~F 리포트). 플러그인 자기 hooks·rules·settings 번들을 read-only 감사.

Evaluator 에이전트는 frontmatter `role: evaluator` 로 Write/Edit 를 하드 박탈한다 (validate-structure `agent_tools` 스캔 강제).

서브에이전트의 **모델·effort 는 각 `agents/*.md` frontmatter 가 단일 소스**다(별칭 sonnet·opus 만, fable 금지 — 프로파일 표와 사용자 덮어쓰기는 README `## 모델 · effort 운용`). 값은 `test-review-evidence-rules`(Evaluator 4종)·`test-gate-presence`(구현자·상향 규칙·README 문구)가 잠근다.

### 아티팩트 규약

모든 작업 산출물은 `.specops/<FID>/`에 보관된다. FID 포맷: `YYYYMMDD-kebab-slug`.

```
.specops/<FID>/
├── intent.md                          ← specifying 1.5 산출 (설계 전 승인)
├── spec.md + acceptance-criteria.md   ← /specify 산출
├── clarifications.md                  ← /clarify 산출
├── plan.md                            ← /plan 산출
├── tasks.md                           ← /decompose 산출 (YAML DAG 포함)
├── dispatch/<task-id>-context.md      ← 서브에이전트 입력
├── evidence.md                        ← /verify 산출
└── friction-log.jsonl                 ← 거버넌스 위반 기록
```

### design-first 대칭 (화면 Step 5.5 ↔ 인터페이스 Step 5.6)

`specifying-ko` 설계 승인 직후, 구현 전에 두 design-first 루프가 대칭으로 돈다:

- **Step 5.5 화면** — UI 기능이면 화면별로 `screens/<name>.md`(스펙) + `screens/<name>.html`(미리보기) 쌍 생성. lifecycle 밖 개별/일괄 수정은 `/design-screen(s)`.
- **Step 5.6 인터페이스** — API/스키마 기능이면 마스터 문서 `.specops/memory/api-spec.md`(IF 설계) · `.specops/memory/data-model.md`(테이블 설계) 의 해당 섹션을 **먼저** 갱신. lifecycle 밖은 `/design-interface(s)`.

`foundation` 분기는 Step 5.5 를 **전면 skip 하지 않는다** — **셸 전용**(allowlist `app-shell`·`layout`·`login` + `<!-- foundation-shell -->`, 기능 화면 금지). **Step 5.6 은 적용**(공통부 DB 스키마·공통 API 의 본진). `/start-all` **batch** 는 Step 5.5·5.6을 모두 skip 하고 Phase 2.5에서 **화면→인터페이스→`design-reviewer-ko` 무거운 리뷰** 순으로 1회 통합한다(화면 또는 IF 산출 시 리뷰 필수). 파괴적 스키마 변경은 `impact-analysis.md §2`(expand-contract) + 회귀 AC-R-2(데이터 보존)로 연계. verify 가 역방향 안전망으로 설계-구현 대칭을 검사한다.

### 학습 루프 (gbrain / freelog)

세션 인사이트는 `.specops/memory/learnings.jsonl` 에 축적된다 — `scripts/gbrain-append.sh` append, `/gbrain` 조회. 자유작업(lifecycle 밖 편집)은 Stop 훅 `freecomment-capture.sh` 가 pending 적재 → SessionStart 가 LLM 요약해 `.specops/freelog.md` 기록 + mini-FID 또는 진행 중 FID 귀속. `/log` 로 수동 즉석 기록.

## 주요 규약

### SKILL.md frontmatter 필수 필드

```yaml
---
name: <스킬명>
description: <한 줄 설명>
layer: <1|2|3>
reference_upstream: <owner/repo@version path>  # 포맷 필수 (독자 추가 시 "specops-ko 독자 추가" 허용)
specops_version: <semver>  # 본 skill 본문이 마지막으로 substantive 변경된 플러그인 버전 (자동 갱신 아님)
used_by: <호출자 목록>  # 표기 규약 — command 는 /<name>, skill 은 short name (<skill>-ko)
---
```

선택 marker 필드: skills `discipline: true` (합리화 차단표 의무 — test-skill-conventions T9 스캔), agents `role: evaluator` (Write/Edit 박탈 하드강제 — validate-structure agent_tools 스캔). 신규 discipline/evaluator 항목은 marker 만 달면 자동 검사 편입.

### tasks.md DAG 포맷

`decomposing-ko`가 생성하는 `tasks.md`에는 YAML DAG가 포함된다. `scripts/dag/parse-dag.sh`가 파싱하여 독립 batch를 추출하고, `implementing-ko`가 병렬 dispatch에 활용한다.

### maintenance flag

진입 분기 약속어 — args 첫 줄에 HTML 주석을 prepend하여 분기를 구분한다.
매칭 순서(specifying-ko): maintain-lite → maintain → lite → foundation → batch → auto → (신규 기본).

- `<!-- entry: maintain-lite -->` — 경량 유지보수. `analyzing-ko` `[lite-mini 분기]` → `specifying-ko` `[maintain-lite 분기]`. `maintain`보다 **먼저** 매칭.
- `<!-- entry: maintain -->` — 유지보수 진입. `specifying-ko`의 `[유지보수 분기]`가 감지.
- `<!-- entry: lite -->` — 경량 신규. `specifying-ko` `[lite 분기]` — clarify/plan skip, §lite+trivial, 화면/IF·B/C 유지.
- `<!-- entry: foundation -->` — 공통부 먼저 개발 진입. `specifying-ko`의 `[foundation 분기]`가 감지. Step 5.5 **셸 전용**(allowlist `app-shell`·`layout`·`login` + `<!-- foundation-shell -->`, 기능 화면 금지), Step 5.6 적용, §유형=`foundation` 자동 라벨.
- `<!-- entry: batch -->` — `/start-all` FR 루프. Step 0 git-branch skip, Step 5.5·5.6 skip(Phase 2.5로 이관). 셋째 줄 `<!-- auto: true -->`면 `§auto` 동시 기재.
- `<!-- entry: auto -->` — 무인 단독(`§auto: true`). git-branch 유지, clarify/plan 수행.
- **무인 표지 (둘째 줄)** `<!-- auto: true -->` — `maintain`·`maintain-lite`·`lite` 약속어 **다음 줄**에 붙으면 그 분기에 무인을 겹친다(`/maintain-auto`·`/maintain-lite-auto`·`/start-lite-auto`). `analyzing-ko` 는 검토 게이트를 자동 통과하고(분석 산출물은 그대로), `specifying-ko` 는 `§auto: true` 를 함께 적는다 — 뒤 단계는 그 라벨만 본다. lite 계열의 strict 신호는 중단 대신 풀 무인 경로로 자동 승격한다. batch 의 셋째 줄 `<!-- auto: true -->` 와 같은 표지다.

### `hooks/governance-lib.sh` 는 800줄 규칙 예외다

이 repo 는 그 규칙을 **`hooks/governance-lib.sh`(1892줄 · 함수 51개) 한 파일에 한해 적용하지 않는다** 나눌 이유가 생기면 **되돌려-관찰(변이 주입)로 각 가드의 생존을 실증하며** 나눈다. 이 예외는 분할 검토를 영구 금지하지 않고 근거 없는 분할만 막는다. 예외는 이 **한 파일에만** 적용되며 다른 파일의 비대화를 정당화하지 않는다. (근거·이력: docs/governance-history.md §7)

## `/doctor` 의 memory·bootstrap ⚠️ 는 정상이다 (정책의 알려진 결과)

이 repo 에서 `doctor` 는 `memory: 문서 0건` 과 `bootstrap: 미종결` 을 **항상** 경고한다. 둘 다 **정확한 보고**이며 고칠 결함이 아니다 — `.specops/` 를 **전량 로컬 전용**으로 돌린 정책의 직접적 결과다:

- `.specops/` 가 `.gitignore` 되어 project memory(`constitution`·`requirements`·`test-strategy`)가 **커밋되지 않는다** → `memory ⚠️`
- `/init-project` 를 이 repo 에 돌린 적이 없다(이 repo 가 곧 플러그인이다) → `chore(init):` 커밋 부재 → `bootstrap ⚠️`
- `init-finalize.sh` 를 돌려도 **no-op** 이다 — 대상이 전부 ignore 되거나 이미 tracked-clean 이다.

**`doctor.sh` 를 고쳐 이 경고를 끄지 않는다.** 플러그인 저장소를 예외 처리하면, Claude Code 플러그인을 만들면서 specops 를 쓰는 하류 사용자의 **진짜 경고까지 죽는다**. 경고를 무시하는 것과 방향만 반대인 같은 병이다. 정책을 뒤집을 근거가 생기면(=memory 를 공유·버전관리할 이유) 그때 `.gitignore` 예외를 논의한다.

## 구조 검증이 FAIL나면

```bash
bash scripts/_internal/validate-structure.sh
```

- `file_counts FAIL` → 파일 추가/삭제 시 스크립트 내 기대값(commands, skills, templates 개수) 업데이트
- `frontmatter FAIL` → YAML `{{placeholder}}`는 따옴표로 감싸야 함
- `ref_upstream_fmt` → `owner/repo@version path` 포맷 또는 `specops-ko 독자 추가` 명시 필요
