# 기여 가이드 — specops-ko

Claude Code 한국어 자율 Lifecycle 플러그인에 기여 환영. 본 가이드는 PR/skill 추가 시 최소 요건을 정의한다.

## 사전 요건

- Claude Code 설치 (`claude` CLI)
- `bash 5+`, `jq`, `python3` (+ `pyyaml`)
- 플러그인을 marketplace로 등록 후 dogfood

```bash
claude plugin marketplace add andyko18/specops-ko                    # GitHub
claude plugin install devfsd@devfsd
# 로컬 dogfood: claude plugin marketplace add /절대경로/specops-ko
```

## 개발 워크플로

clone 후 1회: `bash scripts/_internal/install-git-hooks.sh` (pre-commit≈5s · pre-push≈run-all).

본 플러그인은 **자기 자신을 dogfood** 한다. 신규 skill·command·hook 추가는 다음 슬래시로 진입한다:

```bash
/start "<기능 설명>"                 # 신규 기능 (풀 chain)
/start-lite "<기능>"                 # 경량 신규 (clarify·plan skip)
/start-foundation "<공통부>"         # 공통부 1회
/start-all                           # FR batch (requirements 필요)
/start-all-auto                      # 무인 batch
/maintain "<수정 대상>"              # 유지보수 (analyzing 선행)
/maintain-lite "<대상>"              # 경량 유지보수
```

자율 chain: specify → clarify → plan → decompose → implement → verify → request-review → receive-review → security → integration-test → performance-test → PR.

## PR 전 필수 체크

```bash
# 1) 구조 무결성 (전 항목 ✅ 목표)
bash scripts/_internal/validate-structure.sh

# 2) 거버넌스 규칙 회귀 (전 항목 PASS, FAIL=0 목표)
bash scripts/tests/governance/test-rules.sh

# 3) DAG 파서 (PASS=26 목표)
bash scripts/tests/dag/test-parse-dag.sh

# 4) SKILL.md 규약
bash scripts/tests/test-skill-conventions.sh

# (권장) 전체 pre-flight 게이트 한 번에 — 릴리즈와 동일
bash scripts/tests/run-all.sh

# (권장·soft) 릴리즈 전 LLM smoke — stamp 7일 이내
# bash scripts/tests/llm-eval/run-evals.sh
```

1건이라도 FAIL 시 머지 금지.

## Skill 추가 규약

### frontmatter 필수 필드

```yaml
---
name: <kebab-case-ko>
description: <한 줄 — 언제 사용·무엇·결과>
layer: 1 | 2 | 3
reference_upstream: <owner/repo@version path> 또는 "specops-ko 독자 추가"
specops_version: <semver>
used_by: </command 또는 skill short name>  # command=/start, skill=specifying-ko (devfsd: prefix 금지)
---
```

### layer 분류

| layer | 용도 | 예시 |
|---|---|---|
| **1** | 메타 (SessionStart 자동 주입) | `using-specops-ko` |
| **2** | Engine — Lifecycle 단계·cross-cutting | `specifying-ko`, `karpathy-ko`, `advisor-ko` |
| **3** | Harness — 아키텍처 원칙 강제 | `sprint-contracts-ko`, `context-resets-ko` |

### 본문 필수 섹션

- `## 사용 시점` — 언제 호출되는가
- `## 절차 (Process)` — Step 1, 2, ...
- `## 다음 skill` — chain 끊김 방지 (layer 1 메타 skill 제외)
- `## 참조` — upstream 링크 + 관련 skill

### Skill 작성 방법론

skill 본문 작성 시 **failure-first + rationalization table** 2원칙을 따른다.

**ⓐ failure-first (실패 먼저 관찰)**

> "skill 없이 agent 가 실패하는 걸 안 봤으면, 그 skill 이 맞는지도 모른다."

1. **RED** — skill 없이 agent 에게 해당 작업 시킴. 어떻게 틀리는지 *직접 목격*.
2. **GREEN** — 목격한 실패만 겨냥하는 최소 skill 작성.
3. **REFACTOR** — agent 가 찾아낸 합리화 루프홀을 표로 닫음 (→ rationalization table).

머리로 상상한 문제가 아닌, **실제 목격한 실패만** skill 로 만든다. 과잉설계 방지.

**ⓑ rationalization table (합리화 차단표)**

discipline-class skill(거버넌스 강제·규율 위반 방지 목적)에는 `## 합리화 차단표` 섹션을 포함한다. 양식은 `templates/SKILL.md` 참조.

| AI 합리화 패턴 예시 | 차단 규칙 |
|---|---|
| "이건 사소해서 면제" | 사소함 자기판단 금지, 무조건 적용 |
| "이미 통과했음(증거 없음)" | transcript 증거 없으면 불인정 |
| "예외 케이스임" | 예외 판단 권한 없음, 규칙 준수 |

## Command 추가 규약

`commands/<slug>.md` frontmatter에 `specops_layer`, `specops_version` 필수. 단순 wrapper면 process 본문은 5줄 이내 — 실제 로직은 skill에 위임.

## Hook 추가 규약

- `hooks/hooks.json` 매니페스트 등록
- `scripts/_internal/is-hook-enabled.sh` config guard 호출
- `set -uo pipefail` 강제 (또는 `safe_exit` 패턴 일관성)
- 실패 시 `exit 0` 투과 — 도구 흐름 차단 금지
- `hooks/rules.jsonl` R-* 규칙 신설 시 `test-rules.sh`에 회귀 테스트 추가

## Commit 메시지 컨벤션

```
<type>(<scope>): <subject>

<body>
```

- type: `feat`, `fix`, `chore`, `docs`, `test`, `refactor`
- scope: skill/command/hook 이름 또는 영역
- subject: 50자 이내, 명령형 한국어 가능

## PR 생성

`receiving-code-review-ko` 가 자동 안내. 수동 생성 시:

```bash
gh pr create \
  --base main \
  --head feat/<FID> \
  --title "<scope>: <subject>"
```

PR 본문: `.specops/<FID>/spec.md` + `acceptance-criteria.md` + `evidence.md` 링크 권장.

## Semver 정책

| bump | 트리거 |
|---|---|
| MAJOR | skill chain 호환성 깨짐 (예: HARD GATE 추가, 산출물 포맷 변경) |
| MINOR | 신규 skill/command/hook 추가, 기존 skill 본문 확장 |
| PATCH | bug fix, frontmatter 정합성, 테스트 보강, doc 갱신 |

`.claude-plugin/plugin.json` + `marketplace.json` 동시 갱신. `CHANGELOG.md` Unreleased → 버전 섹션 이동.

## 5원칙

| 원칙 | 의미 |
|---|---|
| 1 투명성 | skill 호출·결정 명시. 침묵 진행 금지 |
| 2 문지기 | binary 분기. 회색지대 만들지 말 것 |
| 3 회귀 보호 | 모든 AC는 테스트로 검증 |
| 4 사용자 주권 | HARD GATE는 사용자 승인. 임의 진행 금지 |
| 5 한계 고백 | 불확실 시 advisor 호출 또는 사용자 질문 |

## 참조

- `CLAUDE.md` — 프로젝트 컨텍스트 (Claude Code 전용)
- `README.md` — 사용자 진입 가이드
- `docs/case-studies/` (specops-ko 본 저장소) — 설계 근거
