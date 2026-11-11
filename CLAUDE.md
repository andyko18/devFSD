# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

devFSD(개발 자율주행)는 **Claude Code 전용 한국어 자율 Lifecycle 플러그인**이다. 슬래시 1회(`/start`, `/start-lite`, `/maintain`, `/maintain-lite` · 무인 일괄 `/start-all-auto`) 또는 자연어 진입 후 메타 스킬이 spec → (clarify → plan) → TDD implement → verify → review → security → integration-test → performance-test → PR 전 단계를 자동 chain한다. `/start-lite`·`/maintain-lite`는 clarify·plan ceremony만 생략하고 화면/IF·Phase B/C·verify는 유지한다(NL로 lite 추론 금지). 몇 줄짜리 수정은 `/quick-fix` 가 chain 밖에서 받는다 — 문서 없이 테스트 실행 + 코드 리뷰 1회이고, 범위 상한은 커밋 때 훅이 판정한다(아래 거버넌스 엔진의 quick 경로). Conductor 에이전트 없이 각 SKILL.md 본문의 `## 다음 skill` 섹션이 다음 단계를 강제한다.

## 테스트 명령

> **clone 마다 1회**: `bash scripts/_internal/install-git-hooks.sh` — 2단 git hook 게이트(`pre-commit` 정합 ~5s · `pre-push` 전체 스위트)를 설치한다. 탈출구는 `--no-verify`.

```bash
bash scripts/tests/run-all.sh                    # 전체 스위트 (릴리즈 pre-flight 게이트와 동일 · 병렬 수 SPECOPS_RUN_ALL_JOBS)
bash scripts/_internal/validate-structure.sh     # 플러그인 구조 무결성
bash scripts/_internal/check-doc-numbers.sh      # 문서 수치 doc-lock
bash scripts/skill-routing-eval.sh               # 결정론 skill 라우팅 eval (토큰 0)
```

상세 — 훅 게이트 동작·릴리즈 대상·수동 러너(LLM eval·E2E·dogfood, 토큰 비용)·스위트 격리 규약(새 `test-*.sh` 의 `unset GIT_DIR …` 줄) — 는 `scripts/tests/CLAUDE.md`. 릴리즈는 사용자가 말할 때만 한다.

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

훅 이벤트 4종(`SessionStart`·`PreToolUse`·`PostToolUse`·`Stop`)이 `hooks/rules.jsonl` 의 R-1~R-5 를 검사한다. R-1(commit 전 verify)·R-2(PR 전 verify)는 **pretool=사전 차단 / posttool=감사 기록**이고, verify 면제는 자기보고가 아니라 transcript 의 실행 증거(`VERIFY: PASS`)로만 열린다. `.specops/` 가 없는 repo 는 관할 밖이다(판정·기록·생성 안 함). 커밋이 면제되는지는 `bash scripts/_internal/scope-explain.sh '<커밋 명령>'` 으로 미리 묻는다.

**상세는 `hooks/CLAUDE.md`** — 훅별 동작·SessionStart 조립 순서 계약과 인라인 예산·면제 4종·플러그인 런타임 예외·실행-근거 gate·트리거 인식 범위·quick 경로·`governance-lib.sh` 800줄 규칙 예외. `hooks/` 를 고치거나 커밋이 deny 되면 먼저 그 파일을 읽는다.

### 서브에이전트 리뷰 패턴 · SKILL.md 규약

Generator ↔ Evaluator 를 분리한다(구현 Phase B `spec-reviewer-ko` → Phase C `code-reviewer-ko` · 설계 `plan-reviewer-ko` · batch `design-reviewer-ko`). Evaluator 는 frontmatter `role: evaluator` 로 Write/Edit 가 박탈되고, 모델·effort 는 각 `agents/*.md` frontmatter 가 단일 소스다. **상세와 SKILL.md frontmatter 필수 필드는 `skills/CLAUDE.md`** — skill·agent 본문을 만들거나 고치기 전에 읽는다.

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

### tasks.md DAG 포맷

`decomposing-ko`가 생성하는 `tasks.md`에는 YAML DAG가 포함된다. `scripts/dag/parse-dag.sh`가 파싱하여 독립 batch를 추출하고, `implementing-ko`가 병렬 dispatch에 활용한다.

### maintenance flag

진입 분기 약속어 — args 첫 줄에 HTML 주석을 prepend하여 분기를 구분한다.
매칭 순서(specifying-ko): maintain-lite → maintain → lite → foundation → batch → (신규 기본).

- `<!-- entry: maintain-lite -->` — 경량 유지보수. `analyzing-ko` `[lite-mini 분기]` → `specifying-ko` `[maintain-lite 분기]`. `maintain`보다 **먼저** 매칭.
- `<!-- entry: maintain -->` — 유지보수 진입. `specifying-ko`의 `[유지보수 분기]`가 감지.
- `<!-- entry: lite -->` — 경량 신규. `specifying-ko` `[lite 분기]` — clarify/plan skip, §lite+trivial, 화면/IF·B/C 유지.
- `<!-- entry: foundation -->` — 공통부 먼저 개발 진입. `specifying-ko`의 `[foundation 분기]`가 감지. Step 5.5 **셸 전용**(allowlist `app-shell`·`layout`·`login` + `<!-- foundation-shell -->`, 기능 화면 금지), Step 5.6 적용, §유형=`foundation` 자동 라벨.
- `<!-- entry: batch -->` — `/start-all` FR 루프. Step 0 git-branch skip, Step 5.5·5.6 skip(Phase 2.5로 이관). 셋째 줄 `<!-- auto: true -->`면 `§auto` 동시 기재.

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
