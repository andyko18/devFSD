---
name: using-git-worktrees-ko
description: 현재 워크스페이스에서 격리가 필요한 기능 작업을 시작하거나 구현 플랜 실행 전에 사용 — git worktree로 격리 워크스페이스를 생성하고 안전 검증
layer: 2
reference_upstream: obra/superpowers@v5.1.0 skills/using-git-worktrees/SKILL.md
specops_version: 1.0.0
used_by: specifying-ko (Phase 4 — 설계 승인 후 구현 직전), implementing-ko (모든 태스크 실행 전), planning-ko (참조)
integrates_with: specops-ko:finishing-a-development-branch-ko
---

# Engine 스킬 — Git Worktree 격리 작업

## 개요

git worktree는 동일 저장소를 공유하는 격리 워크스페이스를 만들어 **여러 브랜치를 동시 작업**할 수 있게 한다. 브랜치 전환 없이.

**핵심 원칙**: 체계적 디렉터리 선택 + 안전 검증 = 신뢰 가능한 격리.

**시작 시 선언**: "specops-ko:using-git-worktrees-ko 스킬을 사용해 격리 워크스페이스를 설정합니다."

**Provenance 규약 (v5.1.0 PRI-974)**: `.worktrees/` 내부 경로 = 플러그인 생성분 — finishing 의 정리 대상. 그 외 위치의 worktree = 사용자 소유 — **불가침** (정리·삭제 금지).

## 디렉터리 선택 프로세스

다음 우선순위 순서로:

### 1. 기존 디렉터리 확인

```bash
# 우선순위 순서로 확인
ls -d .worktrees 2>/dev/null     # 우선 (숨김)
ls -d worktrees 2>/dev/null      # 대안
```

**발견 시**: 그 디렉터리 사용. 둘 다 있으면 `.worktrees` 우선.

### 2. CLAUDE.md 확인

```bash
grep -i "worktree.*director" CLAUDE.md 2>/dev/null
```

**선호 명시 시**: 묻지 말고 사용.

### 3. 사용자에게 질문 (5원칙 4 — 주권)

디렉터리도 없고 CLAUDE.md 선호도 없으면:

```
worktree 디렉터리 없음. 어디에 worktree를 만들까요?

1. .worktrees/ (프로젝트 로컬, 숨김)
2. ~/.config/specops-ko/worktrees/<project-name>/ (전역 위치)

어느 쪽?
```

## 안전 검증

**0. 중첩 worktree 감지 (PRI-974)** — 생성 전 필수:

```bash
gd=$(git rev-parse --git-dir 2>/dev/null); gcd=$(git rev-parse --git-common-dir 2>/dev/null)
if [ -n "$gd" ] && [ -n "$gcd" ] && [ "$gd" != "$gcd" ]; then
  echo "이미 linked worktree 내부 ($(pwd)) — 신규 생성 skip, 현 worktree 재사용"
fi
```

감지 시 생성 절차를 중단하고 현 worktree 를 그대로 사용한다 (common dir 이동 금지 — 사용자 작업 위치 보존). submodule 은 `git-dir == git-common-dir` 이므로 오탐 없음.

### 프로젝트 로컬 디렉터리 (`.worktrees` 또는 `worktrees`)

**worktree 생성 전에 디렉터리가 ignore되었는지 검증 의무**:

```bash
# ignore 확인 (local·global·system gitignore 모두 존중)
git check-ignore -q .worktrees 2>/dev/null || git check-ignore -q worktrees 2>/dev/null
```

**ignore 안 된 경우** ("깨진 것은 즉시 수정" 원칙):
1. .gitignore에 적절한 라인 추가
2. 변경 commit
3. worktree 생성으로 진행

**왜 critical**: worktree 내용을 저장소에 실수로 commit하는 것 방지.

### 전역 디렉터리 (`~/.config/specops-ko/worktrees`)

.gitignore 검증 불필요 — 프로젝트 외부.

> **`.specops` 를 worktree 로 복사하지 않는다** (20261016) — 훅과 기록 스크립트가 메인 쪽 `.specops` 를 쓴다. 사본은 판정과 갈라지고 worktree 와 함께 사라진다. 그 밖의 스크립트는 `SPECOPS_ROOT` 로 위치를 준다.

## 생성 동의 게이트 (PRI-974 — 모드별 분기)

worktree 생성은 **동의 없이는 금지** (upstream #991). 모드별 동의 주체:

모드 감지: `grep -qE '^\*\*§auto\*\*:[[:space:]]*true' .specops/<FID>/spec.md` (§batch 동일 패턴 · `§일괄` 은 `^\*\*§일괄\*\*:[[:space:]]*true`) — 라벨 없으면 단일 모드.

| 모드 | 동의 주체 | 동작 |
|---|---|---|
| 단일 | 사용자 | "worktree 생성 (<목록>) — 진행? [y/n]". **n → worktree 없이 SEQUENTIAL 분기로 전환** (거부 ≠ 작업 중단) |
| §auto | 자동통과 (가역) | dispatch-log 기록 + PR 게이트 **가정 다이제스트** 집계 |
| §batch | 오케스트레이터 대행 | dispatch-log 기록 |
| §일괄 | 승인 묶음이 동의(묶음에 병렬 worktree 사용을 예고했다) | 다시 묻지 않는다 · dispatch-log 기록 |
| 병렬 wave (implementing-ko) | 부모가 wave 시작 시 **1회 일괄** 동의 요청 (leaf 수·경로 명시) | 단일 모드 규칙. §auto/batch/§일괄 면 해당 행 적용 |

## 생성 단계

### 1. 프로젝트 이름 감지

```bash
project=$(basename "$(git rev-parse --show-toplevel)")
```

### 2. Worktree 생성

```bash
# 전체 경로 결정
case $LOCATION in
  .worktrees|worktrees)
    path="$LOCATION/$BRANCH_NAME"
    ;;
  ~/.config/specops-ko/worktrees/*)
    path="$HOME/.config/specops-ko/worktrees/$project/$BRANCH_NAME"
    ;;
esac

# 새 브랜치로 worktree 생성
git worktree add "$path" -b "$BRANCH_NAME"
cd "$path"
```

### 3. 프로젝트 셋업 실행

자동 감지하여 적절한 셋업:

```bash
# Node.js
if [ -f package.json ]; then npm install; fi

# Rust
if [ -f Cargo.toml ]; then cargo build; fi

# Python
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
if [ -f pyproject.toml ]; then poetry install; fi

# Go
if [ -f go.mod ]; then go mod download; fi

# bash 프로젝트 (specops 컨벤션)
if [ -d tests ] && ls tests/test-*.sh >/dev/null 2>&1; then
  chmod +x tests/test-*.sh
fi
```

### 4. Clean Baseline 검증

worktree가 깨끗하게 시작하는지 테스트로 확인:

```bash
# 프로젝트 적합 명령 사용
npm test
cargo test
pytest
bash tests/test-*.sh
go test ./...
```

**테스트 실패 시** (5원칙 5 — 한계 고백):
실패 보고하고 진행할지 조사할지 사용자에 확인.

**테스트 통과 시**: 준비 완료 보고.

### 5. 위치 보고

```
Worktree 준비됨: <full-path>
테스트 통과 (<N>개 테스트, 0 실패)
<feature-name> 구현 준비 완료
```

## 빠른 참조

| 상황 | 동작 |
|---|---|
| `.worktrees/` 존재 | 사용 (ignore 검증) |
| `worktrees/` 존재 | 사용 (ignore 검증) |
| 둘 다 존재 | `.worktrees/` 우선 |
| 둘 다 없음 | CLAUDE.md → 사용자 질문 |
| 디렉터리 ignore 안 됨 | .gitignore 추가 + commit |
| baseline 테스트 실패 | 실패 보고 + 사용자 확인 |
| package.json/Cargo.toml 없음 | 의존성 설치 생략 |
| 중첩 감지 | git-dir ≠ git-common-dir 이면 생성 skip |
| 동의 | 생성 전 모드별 게이트 (위 표) |

## 5원칙 주입

| 원칙 | 본 skill 연결 |
|---|---|
| 1 투명성 | worktree 경로·base 브랜치를 명시 보고 |
| 2 문지기 | ignore 검증 의무 — 회색지대 만들지 말 것 |
| 3 깊이 | "테스트가 통과할 거야" 추측 금지, baseline 실제 실행 |
| 4 주권 | 디렉터리 위치 모호 시 사용자 질문 (3 옵션) |
| 5 한계 고백 | baseline 실패 시 사용자에게 보고 후 진행 결정 |

## 흔한 실수

### Ignore 검증 생략
- 문제: worktree 내용이 추적되어 git status 오염
- 수정: 프로젝트 로컬 worktree 생성 전 항상 `git check-ignore`

### 디렉터리 위치 가정
- 문제: 일관성 깨짐, 프로젝트 컨벤션 위반
- 수정: 우선순위 따름 — 기존 > CLAUDE.md > 질문

### 실패 테스트로 진행
- 문제: 새 버그와 기존 이슈 구분 불가
- 수정: 실패 보고, 명시 진행 허락 받기

### 셋업 명령 하드코딩
- 문제: 다른 도구 사용 프로젝트에서 깨짐
- 수정: 프로젝트 파일에서 자동 감지

## 예시 워크플로

```
You: specops-ko:using-git-worktrees-ko 스킬을 사용해 격리 워크스페이스를 설정합니다.

[.worktrees/ 확인 — 존재]
[ignore 검증 — git check-ignore 가 .worktrees/ 가 ignore됨 확인]
[worktree 생성: git worktree add .worktrees/auth -b feature/auth]
[npm install 실행]
[npm test 실행 — 47개 통과]

Worktree 준비됨: /Users/mac/myproject/.worktrees/auth
테스트 통과 (47개 테스트, 0 실패)
auth 기능 구현 준비 완료
```

## 적색 플래그

**금지**:
- **`git worktree add` 직접 사용** — `EnterWorktree` 같은 native tool 이 있으면 반드시 사용. 이것이 #1 실수 (upstream v5.1.0)
- Step 0 감지에서 기존 격리 환경 탐지 시 worktree 추가 생성
- Step 1a 생략하고 곧바로 Step 1b git 명령 실행
- 프로젝트 로컬 디렉터리에서 ignore 검증 없이 worktree 생성
- baseline 테스트 검증 생략
- 사용자 확인 없이 실패 테스트로 진행
- 모호 시 디렉터리 위치 가정
- CLAUDE.md 확인 생략
- **동의 없이 worktree 생성** — 모드별 동의 게이트 우회 금지 (#991)
- **중첩 생성** — linked worktree 내부에서 또 생성 (감지 스텝 생략 금지)
- **외부 worktree 정리** — `.worktrees/` 밖은 사용자 소유 (provenance)

**의무**:
- 디렉터리 우선순위 따름: 기존 > CLAUDE.md > 질문
- 프로젝트 로컬은 ignore 검증
- 프로젝트 셋업 자동 감지·실행
- clean baseline 검증

## 통합

**호출자**:
- `specops-ko:specifying-ko` (Phase 4) — 설계 승인 후 구현 단계 진입 시 의무
- `specops-ko:implementing-ko` — 어떤 태스크 실행 전에도 의무
- `specops-ko:planning-ko` — 플랜 §2 "파일 구조" 작성 시 worktree 위치 가정
- `specops-ko:dispatching-parallel-agents-ko` (v0.4a) — DAG-aware 모드에서 leaf 별 worktree 생성 (`.worktrees/<FID>-<task-id>/`)

**짝**:
- `specops-ko:finishing-a-development-branch-ko` — 작업 완료 후 정리 의무

## v0.4a — leaf-per-worktree 모드 (R11 git race 차단)

`dispatching-parallel-agents-ko` DAG-aware 모드에서 호출 시:
- 각 leaf id 마다 별도 worktree 생성 — `.worktrees/<FID>-<task-id>/`
- leaf subagent 는 본인 worktree 안에서만 작업 (commit 권한 박탈, R8 보강)
- 부모 implementing-ko 가 leaf 결과 수집 후 머지 순서 (output count 적은 leaf 먼저) → main worktree 로 fast-forward
- 머지 실패 시 sequential fallback (leaf commit 재사용, rebase)

**branch 명명 규약**: `feature/<FID>-<task-id>` (예: `feature/20260426-test-feature-T1`).

## 다음 skill

worktree 준비 완료 후:
- `specops-ko:implementing-ko` — 격리 환경에서 태스크 실행

## 참조

- 짝: `specops-ko:finishing-a-development-branch-ko`
- 호출 위치: `specops-ko:specifying-ko`, `specops-ko:implementing-ko`

---

*2026-04-25 · 한국어 이식 + 5원칙 주입 + specops bash 프로젝트 셋업 추가*
