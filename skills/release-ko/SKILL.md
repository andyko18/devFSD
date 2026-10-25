---
name: release-ko
description: bash scripts/release.sh <semver> 1회로 CHANGELOG·README·footer·manifest 동기화, git 태그, 원격 push·GitHub Release 발행까지 완료되는 릴리즈 자동화
layer: 2
reference_upstream: specops-ko 독자 추가 (alirezarezvani/claude-skills release-manager + OMC skills/release/ 패턴 bash 번안)
specops_version: 1.78.2
used_by: /release
---

# release-ko — 릴리즈 자동화

## 개요

`bash scripts/release.sh <X.Y.Z>` 1회로 다음을 자동화한다:

1. **사전 검증** — semver + 워킹트리 클린 + 태그 중복 + 버전 단조성(현재 이하 거부)
2. **pre-flight** — `run-all.sh`(validate-structure + governance + DAG) 테스트 PASS 확인
3. **CHANGELOG** — `## [Unreleased]` → `## [X.Y.Z] — YYYY-MM-DD` 변환 + compare 링크 갱신 (멱등)
4. **README** — `(vOLD)` → `(vNEW)` 배지 + footer 최신 스탬프 갱신
5. **footer 스탬프** — `commands/*.md` footer/frontmatter 버전 불일치 수정
6. **manifest** — `plugin.json` + `marketplace.json` 버전 bump + description 토큰 갱신
7. **post-flight** — `validate-structure.sh` 재실행 (FAIL 시 trap 롤백)
8. **git** — `chore: release vX.Y.Z` 커밋 + annotated tag
9. **원격 발행 (자동)** — origin 존재 시 `git push` + 태그 push, gh CLI 설치 시 `gh release create` 까지 **자동 수행**
   - **재귀 가드**: push 는 `SPECOPS_RUN_ALL=1` prefix 로 실행돼 `pre-push` 훅의 `run-all.sh` 재실행을 막는다 (pre-flight 가 동일 스위트를 이미 통과 — 릴리즈당 3회 → 1회). 가드로 도달 불가해지는 origin CI-red 경고는 `release.sh` 가 push 직전 `check-ci-status.sh` 를 직접 호출해 보존한다.

## 사용법

```bash
# 릴리즈 실행 — origin·gh 있으면 원격 push + GitHub Release 발행까지 자동
bash scripts/release.sh <X.Y.Z>

# 예행 연습 (변경 없음)
bash scripts/release.sh <X.Y.Z> --dry-run
```

> **주의**: 로컬 커밋에서 멈추지 않는다 — origin·gh 감지 시 **원격 push + GitHub Release 발행까지 자동 진행**. origin 부재 시에만 push/release graceful skip + 수동 명령(`git push && git push --tags`) 안내.

## 환경변수 (테스트용)

| 변수 | 값 | 효과 |
|---|---|---|
| `RELEASE_PREFLIGHT_CMD` | `true` | pre/post-flight 전체 PASS (스킵) |
| `RELEASE_PREFLIGHT_CMD` | `false` | pre/post-flight 전체 FAIL (abort 트리거) |
| `RELEASE_PLUGIN_ROOT` | `/tmp/fixture` | 파일 루트 오버라이드 |

## 가정

- `CHANGELOG.md`에 `## [Unreleased]` 헤딩 존재 (없으면 경고 + CHANGELOG 갱신 skip)
- `README.md`에 `(vX.Y.Z)` 패턴 1곳 존재
- `commands/*.md` frontmatter에 `specops_version:` 필드 존재
- main 브랜치에서 실행 — 아니면 worktree 모드(FR-13): origin/main 위 CHANGELOG 만 바뀐 상태여야 하고, dry-run 은 이 검사를 하지 않는다

## 파일 구조

| 파일 | 역할 |
|---|---|
| `scripts/release.sh` | 핵심 구현 (bash 3.2+) |
| `scripts/tests/test-release.sh` | TDD 테스트 (T1~T10) |
| `commands/release.md` | `/release` 슬래시 커맨드 진입점 |

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 각 단계(CHANGELOG·README·footer·git) 실행 결과를 콘솔에 출력 — 무엇이 변경됐는지 명시 |
| 2 **문지기** | pre-flight FAIL = 릴리즈 abort. "이 정도면 괜찮다" 자의적 판단 금지 |
| 3 **깊이** | pre-flight 미실행 상태에서 "릴리즈 완료" 주장 금지 |
| 4 **주권 존중** | `--dry-run` 플래그로 변경 없이 예행 연습 가능 — 사용자가 릴리즈 내용 직접 확인 후 실행 결정 |
| 5 **한계 고백** | git 자격증명 미비·브랜치 불일치 등 환경 문제 시 즉시 abort + 원인 명시 |

## 참조

- `scripts/release.sh` — 핵심 구현
- `scripts/tests/test-release.sh` — TDD 테스트
- `commands/release.md` — `/release` 슬래시 커맨드

---

*specops-ko v1.10.0 · 2026-06-08 · release-ko skill*
