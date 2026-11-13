# scripts/tests/ — 테스트 명령 상세

> 루트 `CLAUDE.md` 에서 원문 그대로 분리했다(20261112). 하위 디렉터리의 CLAUDE.md 는 그 폴더의 파일을 읽거나 고칠 때만 로드된다 — 루트에는 요약과 포인터만 있다.

## 테스트 명령

> **clone 마다 1회**: `bash scripts/_internal/install-git-hooks.sh` — 2단 git hook 게이트를 설치한다 (`core.hooksPath` 는 `.git/config` 로컬 설정이라 버전관리되지 않는다). `pre-commit` = validate-structure + check-propagation(~5s) · `pre-push` = origin main **CI 상태 경고**(`gh` 있을 때만, ~1s, 비차단) + `run-all.sh` 전체(**223 스위트** <!-- doc-lock: suite-count --> · 작업자 풀 병렬 — 2026-09-11 실측 median 병렬 382s(5회) / 직렬 813s(3회). `SPECOPS_RUN_ALL_JOBS` 로 병렬 수 지정(기본 코어 수·상한 8, `1`=직렬). 스위트별 600s 상한). **Claude Code PreToolUse 훅(R-1)은 Cursor 등 다른 도구의 커밋에 발화하지 않으므로**, 로컬의 도구 무관 게이트는 이 층뿐이다 (계기: run-all 없이 나간 커밋이 main 을 하루 red 로 만들었다). 원격에는 main 브랜치 보호가 있다(20261010 — PR 머지는 CI 3종 `run-all`·`shellcheck`·`security-scan` 통과가 필요하다(20261112 — 맥 전체 스위트 `run-all-macos` 는 PR 에서 돌지 않고 main 에 들어간 뒤에만 도는 사후 검사다. 맥 전용 결함은 머지 뒤에 발견될 수 있다). 관리자의 직접 push 는 막지 않는다: `release.sh` 가 main 에 직접 push 한다). 탈출구는 `--no-verify`.

> **작업 브랜치 push 는 관련 스위트로 판정한다** (20261113): `pre-push` 는 기본 브랜치·태그 push 에서만 전체 스위트를 돈다. 그 밖의 브랜치는 `scripts/_internal/prepush-related.sh` 가 기본 브랜치와의 차이에서 관련 스위트를 골라(`run-related.sh --list` · 상한 80개) 그것만 돌리고, 같은 트리에서 이미 통과한 기록(`.specops/.related-suite-pass`)이 있으면 건너뛴다. 전체 스위트는 PR 의 CI 가 본다(머지 필수). 고를 수 없는 변경·커밋하지 않은 추적 변경·HEAD 가 아닌 커밋 push 는 전체다. **대가**: CI 는 리눅스라 관련 스위트 밖의 맥 전용 결함은 머지 뒤 `run-all-macos` 에서 발견된다 — 발행 전에는 `release.sh` pre-flight 의 로컬 전체 스위트가 잡는다. 전체로 강제: `SPECOPS_FORCE_FULL=1 git push`.

> **커밋·PR 게이트도 관련 스위트 통과를 실행 증거로 받는다** (20261113-commit-gate-related-evidence): `run-related.sh` 는 전부 통과하고 판정기(`scripts/_internal/related-suite-fresh.sh` rc 0 — 기록이 지금 트리의 것이고 변경이 닿는 스위트를 전부 덮음)가 인정할 때만 `VERIFY: PASS` 를 내고, R-1·R-2 는 그 줄을 `run-all.sh` 와 같은 술어로 읽는다. 검증 판정이 `STALE` 이어도 같은 판정기가 FRESH 면 커밋을 막지 않는다. 돌릴 명령: `bash scripts/tests/run-related.sh $(bash scripts/_internal/related-suite-fresh.sh --need)`. `.specops/` 없는 작업 트리에서는 통과 기록을 쓸 곳이 없어 이 경로는 꺼진다(종전대로 전체 스위트). **대가**: CI 는 리눅스라 관련 스위트 밖의 맥 전용 결함은 머지 뒤에 보이고, 기본 브랜치에 직접 커밋하면 CI 가 사후에만 본다.

> **릴리즈 대상** (20261011 결정 · 20261015 주기 상한 폐지): 릴리즈 대상은 **행동 변경**(skill·command·agent·hook·template·비테스트 script 의 동작 변화)뿐이고, 발행 시점은 사용자가 정한다(주기 상한 없음). 테스트·문서·주석만의 PR 은 `[Unreleased]` 에 둔다. 상세는 README `### 릴리즈 주기`.

```bash
# 전체 테스트 (run-all.sh — 릴리즈 pre-flight 게이트와 동일)
bash scripts/tests/run-all.sh
# 병렬 수 지정·직렬 강제: SPECOPS_RUN_ALL_JOBS=1 bash scripts/tests/run-all.sh
#   CPU 경합에 약한 시간 임계 스위트는 파일 선두 20줄에 `# run-all: serial — <사유>` 를 달면 병렬 풀 종료 뒤 하나씩 돈다.

# 스위트별 소요 — 전체 스위트가 끝나면 .specops/suite-times.tsv 에 `<초>\t<rc>\t<경로>` 가 느린 순으로 남는다(run-related 는 suite-times-related.tsv)
head -11 .specops/suite-times.tsv

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
