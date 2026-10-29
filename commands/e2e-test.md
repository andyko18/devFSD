---
name: e2e-test
disable-model-invocation: true
description: specops-ko E2E 자동 테스트 — (init-project 부트스트랩)→specify→…→verify→(integration/performance SKIP)→(finishing 정리) 9단계를 greet-cli fixture로 완주하고 산출물 구조를 검증
triggers:
  - "/e2e-test"
mode: auto
specops_version: 2.6.0
specops_layer: E2E-Test
reference_upstream: specops-ko 독자 추가 (upstream 미존재)
---

# /e2e-test

## 목적

specops-ko lifecycle chain의 **완전 자동 E2E 검증**. HARD GATE 없이 내장 `greet-cli` fixture를 사용해
`(init-project 부트스트랩) → specifying → clarifying → planning → decomposing → implementing → verifying-evidence → (integration/performance SKIP) → (finishing 정리)`
9단계를 완주하고 25개 검증 항목(V1~V25)을 점검한다.

## Process

1. `devfsd:e2e-test-ko` 스킬 즉시 호출
2. 스킬이 전체 lifecycle 자동 실행 + 산출물 구조 검증 수행
3. PASS/FAIL 결과 보고

## 사용 예

```
/e2e-test

→ greet-cli fixture 기반 lifecycle 자동 실행 (9단계)
→ 25개 검증 항목 점검 (V1~V25)
→ PASS=25 FAIL=0 또는 실패 항목 리포트 (python3+pyyaml 미설치 시 V8 SKIP — PASS≥24 허용)
```

## 주의

- 이 커맨드는 실제 파일을 생성한다 (`.specops/<FID>/`, `greet-cli.sh`, `test-greet-cli.sh`)
- 완료 후 산출물은 증거로 보존됨 (명시 요청 시 `rm -rf .specops/<FID>`)
- **S0(부트스트랩)·S7(정리)는 repo ROOT 를 변경하므로 격리 throwaway repo(`mktemp -d`+`git init`)에서 실행하고 `rm -rf` 로 제거**한다 — 플러그인 repo 본체는 건드리지 않음
- S7 의 `gh pr view` 실제 PR `MERGED` 경로는 fixture 로 검증 불가 (HARD GATE 로직만 단위검증 — 한계)
- 모든 bash 블록은 **단일 연속 셸**로 실행해야 `e2e_check`·카운터가 누적됨 (블록 분리 시 카운터 리셋)
- V9 는 `validate-structure.sh` 가 `scripts/_internal/.structure-baseline` 기대값(동적)과 대조해 판정 — 파일 추가/삭제 시 baseline 갱신 필요

## 참조

- `skills/e2e-test-ko/SKILL.md` — 실행 로직 + fixture 정의
- `scripts/_internal/validate-structure.sh` — V9 구조 검증
- `scripts/dag/parse-dag.sh` — V8 DAG 파싱 검증

---

*specops-ko v2.6.0 · 2026-05-03 · E2E 자동 테스트 진입점*
