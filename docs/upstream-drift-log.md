# Upstream Drift Log

> 내재화된 OSS 원본과의 drift 감지 히스토리. scripts/diff-upstream.sh가 최신 run을 상단에 prepend.
> 한국어 재창작 특성상 **섹션 헤더 구조 비교**만 자동화. 본문 diff는 수동 리뷰.

**포맷**: `## <YYYY-MM-DD> drift 스캔` 블록 단위
**분류**:
- `struct` (auto): `<owner>/<repo>@<tag> <path.ext>` 엄격 매칭 — 섹션 수·제목 비교
- `manual`: 다중·서술형·확장자 없음 — 수동 리뷰 대상 (v0.3 구조화 마이그레이션 예정)

**카운트 해석**: `scripts/_internal/validate-structure.sh`의 `ref_upstream_fmt` struct는 덜 엄격한 정규식 산출. diff-upstream의 struct는 확장자 + 라인 끝 앵커 엄격 매칭. 두 숫자가 다른 것이 정상.

---

## 2026-06-30 drift 스캔

**요약**: struct=21 · manual=26 · cache_hit=2 · fetched=14 · cache_miss=0 · errors=5

### struct (자동 처리)

- `commands/start.md` vs `obra/superpowers@v5.0.7 commands/brainstorm.md`
  - 상류 헤더: 0, 로컬 헤더: 6, 공통: 0
  - 상류에만: 0, 로컬에만: 6
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/clarifying-ko/SKILL.md` vs `obra/superpowers@v5.0.7 skills/brainstorming/SKILL.md`
  - 상류 헤더: 7, 로컬 헤더: 14, 공통: 0
  - 상류에만: 7, 로컬에만: 14
  - 상류 신규 섹션 (최대 5건):
    - ## After the Design
    - ## Anti-Pattern: "This Is Too Simple To Need A Design"
    - ## Checklist
    - ## Key Principles
    - ## Process Flow
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/context-resets-ko/SKILL.md` vs `revfactory/harness@v1.0 skills/context-resets/SKILL.md` — fetch 실패(https://raw.githubusercontent.com/revfactory/harness/v1.0/skills/context-resets/SKILL.md)
- `skills/decomposing-ko/SKILL.md` vs `obra/superpowers@v5.0.7 skills/writing-plans/SKILL.md`
  - 상류 헤더: 11, 로컬 헤더: 16, 공통: 0
  - 상류에만: 11, 로컬에만: 16
  - 상류 신규 섹션 (최대 5건):
    - ## Bite-Sized Task Granularity
    - ## Execution Handoff
    - ## File Structure
    - ## No Placeholders
    - ## Overview
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/dispatching-parallel-agents-ko/SKILL.md` vs `obra/superpowers@v5.0.7 skills/dispatching-parallel-agents/SKILL.md`
  - 상류 헤더: 14, 로컬 헤더: 20, 공통: 0
  - 상류에만: 14, 로컬에만: 20
  - 상류 신규 섹션 (최대 5건):
    - ## Agent Prompt Structure
    - ## Common Mistakes
    - ## Key Benefits
    - ## Overview
    - ## Real Example from Session
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/file-based-communication-ko/SKILL.md` vs `revfactory/harness@v1.0 skills/file-based-communication/SKILL.md` — fetch 실패(https://raw.githubusercontent.com/revfactory/harness/v1.0/skills/file-based-communication/SKILL.md)
- `skills/finishing-a-development-branch-ko/SKILL.md` vs `obra/superpowers@v5.1.0 skills/finishing-a-development-branch/SKILL.md`
  - 상류 헤더: 13, 로컬 헤더: 12, 공통: 0
  - 상류에만: 13, 로컬에만: 12
  - 상류 신규 섹션 (최대 5건):
    - ## Common Mistakes
    - ## Overview
    - ## Quick Reference
    - ## Red Flags
    - ## Summary
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/generator-evaluator-ko/SKILL.md` vs `obra/omc@v1.0 skills/generator-evaluator/SKILL.md` — fetch 실패(https://raw.githubusercontent.com/obra/omc/v1.0/skills/generator-evaluator/SKILL.md)
- `skills/implementing-ko/SKILL.md` vs `obra/superpowers@v5.0.7 skills/subagent-driven-development/SKILL.md`
  - 상류 헤더: 9, 로컬 헤더: 18, 공통: 0
  - 상류에만: 9, 로컬에만: 18
  - 상류 신규 섹션 (최대 5건):
    - ## Advantages
    - ## Example Workflow
    - ## Handling Implementer Status
    - ## Integration
    - ## Model Selection
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/karpathy-ko/SKILL.md` vs `forrestchang/andrej-karpathy-skills@main skills/karpathy-guidelines/SKILL.md`
  - 상류 헤더: 4, 로컬 헤더: 6, 공통: 0
  - 상류에만: 4, 로컬에만: 6
  - 상류 신규 섹션 (최대 5건):
    - ## 1. Think Before Coding
    - ## 2. Simplicity First
    - ## 3. Surgical Changes
    - ## 4. Goal-Driven Execution
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/planning-ko/SKILL.md` vs `obra/superpowers@v5.0.7 skills/writing-plans/SKILL.md`
  - 상류 헤더: 11, 로컬 헤더: 21, 공통: 0
  - 상류에만: 11, 로컬에만: 21
  - 상류 신규 섹션 (최대 5건):
    - ## Bite-Sized Task Granularity
    - ## Execution Handoff
    - ## File Structure
    - ## No Placeholders
    - ## Overview
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/receiving-code-review-ko/SKILL.md` vs `obra/superpowers@v5.0.7 skills/receiving-code-review/SKILL.md`
  - 상류 헤더: 16, 로컬 헤더: 19, 공통: 0
  - 상류에만: 16, 로컬에만: 19
  - 상류 신규 섹션 (최대 5건):
    - ## Acknowledging Correct Feedback
    - ## Common Mistakes
    - ## Forbidden Responses
    - ## GitHub Thread Replies
    - ## Gracefully Correcting Your Pushback
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/requesting-code-review-ko/SKILL.md` vs `obra/superpowers@v5.0.7 skills/requesting-code-review/SKILL.md`
  - 상류 헤더: 5, 로컬 헤더: 13, 공통: 0
  - 상류에만: 5, 로컬에만: 13
  - 상류 신규 섹션 (최대 5건):
    - ## Example
    - ## How to Request
    - ## Integration with Workflows
    - ## Red Flags
    - ## When to Request Review
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/specifying-ko/SKILL.md` vs `obra/superpowers@v5.0.7 skills/brainstorming/SKILL.md`
  - 상류 헤더: 7, 로컬 헤더: 23, 공통: 1
  - 상류에만: 6, 로컬에만: 22
  - 상류 신규 섹션 (최대 5건):
    - ## After the Design
    - ## Anti-Pattern: "This Is Too Simple To Need A Design"
    - ## Checklist
    - ## Key Principles
    - ## Process Flow
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/sprint-contracts-ko/SKILL.md` vs `revfactory/harness@v1.0 skills/sprint-contracts/SKILL.md` — fetch 실패(https://raw.githubusercontent.com/revfactory/harness/v1.0/skills/sprint-contracts/SKILL.md)
- `skills/structured-artifacts-ko/SKILL.md` vs `revfactory/harness@v1.0 skills/structured-artifacts/SKILL.md` — fetch 실패(https://raw.githubusercontent.com/revfactory/harness/v1.0/skills/structured-artifacts/SKILL.md)
- `skills/systematic-debugging-ko/SKILL.md` vs `obra/superpowers@v5.0.7 skills/systematic-debugging/SKILL.md`
  - 상류 헤더: 15, 로컬 헤더: 18, 공통: 0
  - 상류에만: 15, 로컬에만: 18
  - 상류 신규 섹션 (최대 5건):
    - ## Common Rationalizations
    - ## Overview
    - ## Quick Reference
    - ## Real-World Impact
    - ## Red Flags - STOP and Follow Process
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/tdd-ko/SKILL.md` vs `obra/superpowers@v5.0.7 skills/test-driven-development/SKILL.md`
  - 상류 헤더: 20, 로컬 헤더: 22, 공통: 1
  - 상류에만: 19, 로컬에만: 21
  - 상류 신규 섹션 (최대 5건):
    - ## Common Rationalizations
    - ## Debugging Integration
    - ## Example: Bug Fix
    - ## Final Rule
    - ## Good Tests
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/using-git-worktrees-ko/SKILL.md` vs `obra/superpowers@v5.1.0 skills/using-git-worktrees/SKILL.md`
  - 상류 헤더: 16, 로컬 헤더: 28, 공통: 0
  - 상류에만: 16, 로컬에만: 28
  - 상류 신규 섹션 (최대 5건):
    - ## Common Mistakes
    - ## Overview
    - ## Quick Reference
    - ## Red Flags
    - ## Step 0: Detect Existing Isolation
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/using-specops-ko/SKILL.md` vs `obra/superpowers@v5.0.7 skills/using-superpowers/SKILL.md`
  - 상류 헤더: 8, 로컬 헤더: 12, 공통: 0
  - 상류에만: 8, 로컬에만: 12
  - 상류 신규 섹션 (최대 5건):
    - ## How to Access Skills
    - ## Instruction Priority
    - ## Platform Adaptation
    - ## Red Flags
    - ## Skill Priority
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)
- `skills/verifying-evidence-ko/SKILL.md` vs `obra/superpowers@v5.0.7 skills/verification-before-completion/SKILL.md`
  - 상류 헤더: 10, 로컬 헤더: 20, 공통: 0
  - 상류에만: 10, 로컬에만: 20
  - 상류 신규 섹션 (최대 5건):
    - ## Common Failures
    - ## Key Patterns
    - ## Overview
    - ## Rationalization Prevention
    - ## Red Flags - STOP
  - 권고: 수동 검토 (한국어 재창작 업데이트 여부)

### manual (수동 리뷰 대상)

- `commands/brainstorming.md` — specops-ko 독자 추가 (garrytan/gstack office-hours 한국어 재창작)
- `commands/design-screen.md` — specops-ko 독자 추가
- `commands/design-screens.md` — specops-ko 독자 추가
- `commands/e2e-test.md` — specops-ko 독자 추가 (upstream 미존재)
- `commands/gbrain.md` — specops-ko 독자 추가 (garrytan/gstack office-hours gbrain 패턴 한국어 재창작)
- `commands/improve-arch.md` — specops-ko 독자 추가 (mattpocock improve-codebase-architecture 한국어 재창작)
- `commands/init-project.md` — specops-ko 독자 추가 (github/spec-kit 패턴 번안)
- `commands/maintain.md` — specops-ko 독자 추가 (본가 obra/superpowers@v5.0.7 미존재)
- `commands/promote.md` — specops-ko 독자 추가 (본가 obra/superpowers@v5.0.7 미존재)
- `commands/security-scan.md` — specops-ko 독자 추가
- `commands/start-all-auto.md` — specops-ko 독자 추가 (start-all + start-auto 결합)
- `commands/start-all.md` — specops-ko 독자 추가
- `commands/start-auto.md` — specops-ko 독자 추가 (commands/start.md § auto variant)
- `commands/start-foundation.md` — specops-ko 독자 추가
- `commands/status.md` — specops-ko 독자 추가
- `commands/statusline-install.md` — specops-ko 독자 추가
- `skills/advisor-ko/SKILL.md` — specops-ko 독자 추가 (Anthropic Claude Code advisor 도구 활용 패턴)
- `skills/analyzing-ko/SKILL.md` — specops-ko 독자 추가 (본가 obra/superpowers@v5.0.7 미존재 — brainstorming SKILL 흡수 패
- `skills/brainstorming-ko/SKILL.md` — specops-ko 독자 추가 (garrytan/gstack office-hours 한국어 재창작)
- `skills/e2e-test-ko/SKILL.md` — specops-ko 독자 추가 (upstream 미존재)
- `skills/gbrain-ko/SKILL.md` — specops-ko 독자 추가 (garrytan/gstack office-hours gbrain 패턴 한국어 재창작)
- `skills/improve-codebase-architecture-ko/SKILL.md` — "specops-ko 독자 추가 (mattpocock improve-codebase-architecture 한국어 재창작)"
- `skills/integration-test-ko/SKILL.md` — specops-ko 독자 추가 (test-master 패턴 번안)
- `skills/performance-test-ko/SKILL.md` — specops-ko 독자 추가 (test-master 패턴 번안)
- `skills/release-ko/SKILL.md` — specops-ko 독자 추가 (alirezarezvani/claude-skills release-manager + OMC skills
- `skills/security-review-ko/SKILL.md` — specops-ko 독자 추가 (integration-test-ko 게이트 패턴 번안)
- hooks/console.tsx·core.ts·rail.tsx·elapsed.tsx·console.test.ts — Claude Flightdeck v0.6.0 (MIT, Copyright 2026 Stephen Casella) 이식, devFSD 변경은 // devFSD: 주석 (hooks/register.tsx 는 devFSD 작성 진입점)
- 20261106: console.tsx 렌더 본체 재구성(패널 순서·간격·헤더·오로라) — 원본 대비 구조 이탈 큼, 원본 영어 문구는 유지

---


