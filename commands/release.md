---
name: release
disable-model-invocation: true
description: devFSD 플러그인 릴리즈 자동화 — bash scripts/release.sh <semver> 실행
triggers:
  - "/release"
mode: ask
specops_version: 2.6.0
specops_layer: Lifecycle-Tool
reference_upstream: specops-ko 독자 추가
---

# /release — 릴리즈 자동화

## 사용법

```
/release <X.Y.Z>
```

## 동작

`bash scripts/release.sh <X.Y.Z>` 를 실행해 다음을 수행한다:

1. **사전 검증**: semver 형식 + 워킹트리 클린 + 태그 중복 + **버전 단조성**(현재 plugin.json 버전 이하 거부)
2. **pre-flight**: `run-all.sh`(validate-structure + governance + DAG) 테스트 PASS 확인
3. **CHANGELOG**: `[Unreleased]` 섹션을 버전·날짜 헤딩으로 변환 + compare 링크 갱신 (멱등 — 이미 존재 시 skip)
4. **README**: 버전 배지 `(vOLD)` → `(vNEW)` + footer 최신 스탬프 갱신
5. **footer**: `commands/*.md` footer/frontmatter 버전 불일치 수정
6. **manifest**: `.claude-plugin/plugin.json` + `marketplace.json` 버전 bump + marketplace description 토큰 갱신
7. **post-flight**: `validate-structure.sh` 재실행 (FAIL 시 trap 롤백)
8. **git**: `chore: release vX.Y.Z` 커밋 + annotated tag 생성
9. **원격 발행 (자동)**: origin 존재 시 `git push` + 태그 push, gh CLI 설치 시 `gh release create`(CHANGELOG 본문을 노트로) 까지 **자동 수행**

> **주의**: 로컬 커밋에서 멈추지 않는다 — origin·gh 가 있으면 **자동으로 원격 push + GitHub Release 발행**까지 진행된다. origin 부재(테스트 임시 repo 등) 시에만 push/release 를 graceful skip 하고 수동 명령(`git push && git push --tags`)을 안내한다.

## 예행 연습

```
/release <X.Y.Z> --dry-run
```

변경 없이 예정 작업 목록만 출력.

## 환경변수 (테스트용)

| 변수 | 효과 |
|---|---|
| `RELEASE_PREFLIGHT_CMD=true` | pre/post-flight skip (PASS) |
| `RELEASE_PREFLIGHT_CMD=false` | pre/post-flight FAIL (abort 트리거) |
| `RELEASE_PLUGIN_ROOT=/tmp/fixture` | 파일 루트 오버라이드 |

## 참조

- `skills/release-ko/SKILL.md` — 스킬 문서
- `scripts/release.sh` — 핵심 구현

---

*specops-ko v2.6.0 · 2026-06-08 · /release command*
