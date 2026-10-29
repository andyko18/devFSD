---
name: finishing-a-development-branch-ko
description: feature branch 작업 완료 후 worktree 정리·branch 삭제·main 동기화를 체계적으로 수행하는 Lifecycle 최종 정리 스킬
layer: 2
reference_upstream: obra/superpowers@v5.1.0 skills/finishing-a-development-branch/SKILL.md
specops_version: 1.61.0
used_by: using-git-worktrees-ko (짝 스킬 — 작업 완료 후 호출), performance-test-ko, e2e-test-ko
---

# Engine 스킬 — 개발 브랜치 정리 (finishing-a-development-branch)

## 개요

feature branch 작업·PR 머지가 완료된 후 **worktree 제거 → local/remote branch 삭제 → main 동기화** 순서로 저장소를 클린 상태로 복원한다.

**핵심 원칙**: 미머지 브랜치 강제 삭제 금지. remote 삭제는 반드시 사용자 확인 후.

**시작 시 선언**: "devfsd:finishing-a-development-branch-ko 스킬로 브랜치 정리를 시작합니다."

## 체크리스트

**0. detached HEAD 감지 (PRI-974)**:

```bash
git symbolic-ref -q HEAD >/dev/null || echo "detached HEAD — 브랜치 없음"
```

detached (분리) 상태면 **merge/PR 관련 스텝 (Step 2 PR 상태 확인·Step 4~6 merge/push) 을 skip** 하고, 사용자에게 **(1) worktree 그대로 유지 (2) worktree 폐기** 만 질문한다.

### Step 1: 현재 상태 확인

```bash
# 현재 브랜치 확인
git branch --show-current

# 미커밋 변경 확인
git status --short

# 미push 커밋 확인 (비어있어야 정상)
git log origin/$(git branch --show-current)..HEAD --oneline 2>/dev/null \
  | head -5
```

**HARD GATE 1**: 미커밋 변경이 있으면 중단 — "미커밋 변경이 있습니다. 커밋·stash 후 재실행하세요."

**HARD GATE 2**: 미push 커밋이 있으면 중단 — "push되지 않은 커밋이 있습니다. 브랜치 삭제 전 push하세요."

### Step 2: PR 상태 확인

**gh CLI 가용 시**:
```bash
MERGE_CONFIRMED_BY_GH=false
PR_STATE=$(gh pr view --json state --jq '.state' 2>/dev/null)
echo "PR state: $PR_STATE"
```
- `MERGED` → `MERGE_CONFIRMED_BY_GH=true` 세팅 후 계속 진행
- `OPEN` 또는 `CLOSED` → HARD GATE: "PR이 아직 머지되지 않았습니다. 머지 후 재실행하세요."
- 명령 실패 (gh 미설치 등) → fallback으로 전환

**gh CLI 미가용 시 (fallback)**:
```bash
# squash-merge 에서는 git log 가 커밋 남아있음을 정상 보고 — 완전한 확인 불가
MERGE_CONFIRMED_BY_GH=false
FEAT_BRANCH=$(git branch --show-current)
UNMERGED=$(git log origin/main.."$FEAT_BRANCH" --oneline 2>/dev/null | wc -l | tr -d ' ')
if [ "$UNMERGED" -gt 0 ]; then
  echo "경고: origin/main 에 없는 커밋 ${UNMERGED}건. PR이 머지됐나요? [y/n]"
  # squash-merge 시 이 경고는 오탐 가능 — 사용자 응답 대기
fi
```

> **한계**: squash-merge(GitHub 기본값) 환경에서 fallback `git log` 는 오탐 경고를 출력한다. gh CLI 사용 권장.

### Step 3: Worktree 정리

> **Provenance (PRI-974)**: 아래 정리는 `.worktrees/` 내부 (플러그인 생성분) 만 대상. 그 외 위치 worktree 는 **사용자 소유 — 불가침** (목록에 보여도 제거 금지):

```bash
# 전체 worktree 순회 — provenance 필터는 루프 내 case 1곳 (이중화 금지)
git worktree list | awk '{print $1}' | while read wt_path; do
  case "$wt_path" in
    */.worktrees/*) ;;  # 플러그인 생성분 — 정리 진행
    *) echo "사용자 소유 worktree ($wt_path) — 정리 대상 제외 (provenance)"; continue ;;
  esac
  if [ -n "$(git -C "$wt_path" status --short 2>/dev/null)" ]; then
    echo "HARD GATE: $wt_path 에 미커밋 변경 있음 — 수동 처리 후 재실행"
    exit 1
  fi
  echo "Removing worktree: $wt_path"
  git worktree remove "$wt_path"
done
```

worktree가 없으면 "worktree 없음 — 스킵" 출력 후 다음 단계.

### Step 4: 로컬 feature branch 삭제

```bash
FEAT_BRANCH=$(git branch --show-current)

# main으로 먼저 이동 (판정기는 현재 체크아웃 브랜치를 거부한다)
git checkout main

# ★ 삭제 안전 판정 — 판정기가 SoT (20260806 기계화)
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-branch-deletable.sh "$FEAT_BRANCH" main || {
  echo "HARD GATE: 삭제 금지 — 위 사유 확인 후 재실행"
  exit 1
}
# rc=0 일 때만 삭제 (조상 확인분은 -d 로도 지워지고, squash/rebase merge 분만 -D 필요)
git branch -d "$FEAT_BRANCH" 2>/dev/null || git branch -D "$FEAT_BRANCH"
```

**HARD GATE 판정 SoT = `scripts/_internal/check-branch-deletable.sh`**.
- 종전엔 `MERGE_CONFIRMED_BY_GH` 라는 **모델이 스스로 세팅하는 변수**가 게이트였다 — gh 가 실제로 `MERGED` 를 반환했는지 검증하는 층이 0곳이었고, `git branch -D` 는 pretool 훅 관할 밖(R-1/R-2 는 commit·PR 만 본다)이라 미머지 브랜치 삭제 시 **커밋이 소실**될 수 있었다.
- 판정 근거 2종: **① git 조상**(`merge-base --is-ancestor` — 일반 merge) **② gh PR `state=MERGED`**(squash/rebase merge 는 조상이 아니므로 이것만이 근거).
- **fail-CLOSED**: gh 미설치·PR 없음·조회 실패 등 판정 불가는 **금지**로 처리한다. 다른 게이트의 fail-open 과 반대인 이유는 결과가 **비가역 데이터 손실**이기 때문이다 — 안전한 쪽이 "안 지움" 이다. 의도적 폐기는 사용자가 수동 `git branch -D`.

### Step 5: Remote branch 삭제 (사용자 확인)

```bash
echo "remote branch '$FEAT_BRANCH'를 삭제하시겠습니까? [y/n]"
# 사용자 응답 대기
# y 시:
git push origin --delete "$FEAT_BRANCH"
# n 시: "remote branch 유지. 나중에 수동 삭제: git push origin --delete $FEAT_BRANCH"
```

### Step 6: main 동기화

```bash
git checkout main
git pull origin main
echo "main 동기화 완료"
```

### Step 7: 정리 확인

```bash
echo "=== 잔류 worktree 확인 ==="
git worktree list

echo "=== 잔류 로컬 브랜치 확인 ==="
git branch

echo "=== 정리 완료 ==="
```

feat/<FID> 브랜치와 관련 worktree가 목록에 없으면 정리 성공.

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 각 단계 실행 전 "무엇을 하려 하는지" 1줄 출력 |
| 2 **문지기** | 미머지 상태에서 `-D` 강제 삭제 절대 금지. remote 삭제 전 반드시 확인 |
| 3 **깊이** | PR 상태를 실제 확인 — "아마 머지됐겠지" 추측 금지 |
| 4 **주권 존중** | remote branch 삭제는 사용자가 결정. 자동 삭제 금지 |
| 5 **한계 고백** | gh CLI 미가용 시 git log fallback 사용 — "머지 여부를 완전히 확인할 수 없음" 명시 |

## 참조

- 짝 스킬: `skills/using-git-worktrees-ko/SKILL.md` — worktree 생성 측

## 다음 skill

본 스킬은 Lifecycle의 **최종 정리 단계**다. 정리 완료 후 chain을 시작하지 않는다.

다음 기능 작업은 `/start "<기능>"` 또는 `/maintain "<대상>"` 으로 새 Lifecycle을 시작한다.
