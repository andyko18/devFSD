# scripts/ — 구조 검증·릴리즈·DAG·eval 유틸리티

> 구성 (v1.72.0 기준): `_internal/` (validate-structure·init-project·run-verification 등 내부 유틸) ·
> `dag/` (parse-dag·emit-context·validate-context) · `tests/` (run-all aggregator ≈ **142** suites + llm-eval) ·
> 루트 (release.sh·gbrain-append.sh·session-progress-append.sh·git-branch-create.sh·show-fid-status.sh·slug.sh 등).
> baseline: commands=28 · skills=30 · templates=36 · agents=8 — 수치는 자주 바뀐다. 정본은 `scripts/_internal/.structure-baseline` 이다.
> 아래 절들은 초기 (v0.1~v0.2) 스크립트의 상세 설명 — 경로는 현행 (`_internal/`) 기준으로 갱신됨.

## v0.1 — 기존

### `count-artifacts.sh`

지정 디렉토리 최상위의 `.md` 아티팩트 파일 수를 stdout에 출력. FID 디렉토리 아티팩트 카운트·smoke test에 사용.

```bash
scripts/_internal/count-artifacts.sh .specops/20260420-rss-cache
# → 7
```

## v0.2 — 세션 4

### `validate-task-dependencies.sh`

`.specops/<FID>/tasks.md`에서 `scripts/·hooks/·tests/` 하위 `.sh` 파일 참조를 추출하여 **실제 파일 존재**와 **실행권한(exec-bit)** 을 검증. `/analyze` Process 스텝 9에서 자동 호출되며 실패 시 BLOCK 사유로 편입.

```bash
scripts/_internal/validate-task-dependencies.sh 20260420-rss-cache
# 정상:
#   OK: scripts/_internal/count-artifacts.sh
#   all ok: 1 refs validated
# 실패:
#   MISSING: scripts/ghost.sh   (exit 1)
#   NOT_EXEC: scripts/new-util.sh (fix: chmod +x scripts/new-util.sh)  (exit 1)
```

## v0.2 — 세션 5 🆕

### `validate-structure.sh`

플러그인 구조 무결성 정적 검증 Gate. 리팩토링·실수로 구조가 깨졌을 때 빨리 감지.

```bash
scripts/_internal/validate-structure.sh         # 사람이 읽는 출력
scripts/_internal/validate-structure.sh --json   # CI 통합용 JSON
```

**검증 항목 12개** (`.structure-baseline` jsonl 카운트 기준):
| 항목 | 실패 조건 |
|---|---|
| `directories` | 필수 디렉토리 부재 |
| `file_counts` | `.structure-baseline` glob 카운트 불일치 (현재 commands=28·skills=30·templates=36·agents=8 — 정본은 `.structure-baseline`) |
| `meta_injection` | `session-start.sh` 메타 skill 주입 누락 |
| `frontmatter` | YAML 파싱 실패 (pyyaml 부재 시 SKIP — 한계 고백) |
| `no_superpowers` | `commands/`·`agents/` 에 superpowers 런타임 참조 발견 |
| `manifest` | `plugin.json` ≠ `marketplace.json` 버전 |
| `ref_upstream_fmt` | 구조화 비율 정보성 보고 (FAIL 아님) |
| `skill_conventions` | SKILL.md 필수 필드·섹션 누락 |
| `version_sync` | 버전 문자열 불일치 |
| `readme_counts` | README 자산 카운트 불일치 |
| `changelog_body` | CHANGELOG 최신 버전 섹션 부재 |
| `xref_resolve` | 문서 상호참조 깨짐 |

**의존성**:
- Python 3 (필수) — JSON 파싱
- `pyyaml` (선택) — frontmatter 파싱. 없으면 항목 3은 SKIP 처리(원칙 5 한계 고백)

**출력 예**:
```
✅ directories: OK
✅ file_counts: OK
⚠️  frontmatter: SKIP — python3+pyyaml 미설치 — 한계 고백
✅ no_superpowers: OK
✅ manifest: OK (both=0.1.0)
ℹ️  ref_upstream_fmt: struct=8/23
```

exit code: `0` 전체 통과, `1` 하나 이상 FAIL.

## v0.2 — 세션 5.5 🆕

### `diff-upstream.sh`

상류 OSS 원본과 내재화본 간 drift 감지 프로토타입. 엄격 정규식
(`<owner>/<repo>@<tag> <path.ext>` + 라인 끝 앵커)으로 struct 분류
후 `##`·`###` 섹션 헤더 집합만 비교(한국어 재창작이라 본문 diff
무의미). 차이 결과를 `docs/upstream-drift-log.md`에 run 블록으로
prepend.

```bash
scripts/_internal/diff-upstream.sh               # 캐시 우선, miss 시 fetch
scripts/_internal/diff-upstream.sh --cached      # 네트워크 금지, 캐시만
scripts/_internal/diff-upstream.sh --no-fetch    # 캐시 miss 시 skip (offline 테스트)
scripts/_internal/diff-upstream.sh --file skills/tdd-ko/SKILL.md   # 단일 파일
```

**분류**:
- `struct` (auto): 엄격 매칭 (현재 — `skills/*/SKILL.md` 플랫 경로)
- `manual`: 다중·서술형·확장자 없음 (현재 17건) — v0.3 primary/secondary 필드 split 예정

**캐시**: `.specops-cache/upstream/${owner}__${repo}__${tag}__<path>` (gitignored)

**카운트 차이 (정상)**:
- `validate-structure.sh`의 `ref_upstream_fmt: struct=8/23` — 덜 엄격 (확장자 없어도 매칭)
- `diff-upstream.sh` 의 `struct=4` — 엄격 매칭
- 상세 배경: `docs/OSS-ATTRIBUTION.md §3.5`

## v0.2 — 세션 6 🆕

### `is-hook-enabled.sh`

훅 guard 유틸리티 — 각 훅 첫 줄에서 `bash scripts/_internal/is-hook-enabled.sh <hook-name> || exit 0` 형태로 호출. `.specops/config.yaml`을 읽어 활성/비활성을 결정합니다. config 부재 시 default enabled (v0.1 동작 보존). pyyaml 부재 시 stderr 1회 경고 + default enabled.

```bash
bash scripts/_internal/is-hook-enabled.sh ensure-session-progress; echo $?  # 0 = ON, 1 = OFF
SPECOPS_CONFIG=/path/to/alt.yaml bash scripts/_internal/is-hook-enabled.sh session-start
```

**스키마·profile 우선순위**: `hooks/README.md` "config" 섹션 참조.

## v0.2+ 도입 예정 (v0.3)

### `lint-five-principles.sh` (v0.3)

정규식 기반 5원칙 위반 정적 스캔:
- `except: pass` → 원칙 5
- 매직 넘버 3회 이상 → 원칙 3
- 주석 없는 복잡 조건문 → 원칙 1

## 테스트

```bash
bash scripts/tests/test-count-artifacts.sh              # 7건 (v0.1)
bash scripts/tests/test-validate-task-dependencies.sh   # 7건 (v0.2 세션 4)
bash scripts/tests/test-validate-structure.sh           # 7건 (v0.2 세션 5) — T1~T13
bash scripts/tests/test-validate-structure-chain.sh     # T14~T-cc4 (chain·agent_tools·hardgate) — 20261008 분할
bash scripts/tests/test-diff-upstream.sh                # 8건 (v0.2 세션 5.5)
bash scripts/tests/test-is-hook-enabled.sh              # 7건 (v0.2 세션 6)
```

## 수동 검증 (v0.1 잔존 — validate-structure.sh 등장 후 사용 줄어듦)

```bash
[ $(ls commands/*.md | wc -l | tr -d ' ') -eq 24 ] && echo commands:OK
[ $(ls agents/*.md | wc -l | tr -d ' ') -eq 8 ] && echo agents:OK
! grep -rE "^[^#<-]*superpowers:" commands/ agents/
# ↑ validate-structure.sh 가 이 모두를 자동화 — 직접 실행 불필요
```

## skill-routing-eval — 결정론 skill 라우팅 eval (토큰 0)

skill description 간 tf-idf 코사인(한글 조사 제거 → 글자 bigram → df 상한)으로 충돌 후보·드리프트를 보고하고, `scripts/tests/llm-eval/skills/*/trigger-queries.json` 의 owner 라우팅을 참고 지표로 냅니다. 모델·네트워크 호출 0, **warn-first**(경고만 rc 0).

```bash
bash scripts/skill-routing-eval.sh                       # 요약 · PAIR-WARN(≥0.20) · PAIR-DRIFT(기준선 대비) · QUERY-ROUTING/QUERY-WARN
bash scripts/skill-routing-eval.sh --strict              # PAIR-DRIFT ≥1 이면 rc 1 (향후 CI 전환용)
bash scripts/skill-routing-eval.sh --emit-baseline > /tmp/b.json && mv /tmp/b.json scripts/tests/llm-eval/skill-routing-baseline.json   # description 을 의도적으로 바꾼 뒤 기준선 갱신(사람이 확인·커밋). 직접 리다이렉트하면 오류 시 파일이 비므로 임시 파일 경유
bash scripts/tests/test-skill-routing-eval.sh            # fixture·계약 스위트 (run-all 포함)
```

구현이 jq 인 이유: macOS awk·Ubuntu mawk 는 바이트 단위(`length("가나다")`=9)라 한글 글자 bigram 이 불가합니다. 한계: 조사 제거는 말미 1개 휴리스틱·임계값 미보정이라 절대값이 아니라 **기준선 대비 변화**를 봅니다(질의 지표는 모델 라우팅과 다른 참고용).

## llm-eval — LLM 동작 smoke eval (수동 전용)

메타 skill 의 신호 감지 + 체인 진입을 headless `claude -p` 로 검증합니다.

⚠️ 실 claude 호출은 토큰 비용 발생 (~$0.5/fixture, 총 10 fixture) — run-all/CI **비포함**. 릴리즈 전 수동 실행 권장.

```bash
bash scripts/tests/llm-eval/run-evals.sh            # 실 eval (claude CLI 필요, 비용 발생)
bash scripts/tests/llm-eval/test-llm-eval.sh        # runner 단위 테스트 (stub, 토큰 0 — run-all 포함)
```

- `LLM_EVAL_RUNS=N` (N>1): 각 fixture N회 반복 → 성공률/FLAKY 신뢰성 리포트 (비차단). 기본 1=단발.

- `bash scripts/tests/llm-eval/run-pressure-evals.sh` — **압박 테스트** (HARD GATE 우회 거부 검증, 실 claude 비용·수동 전용). `test-pressure-evals.sh` 는 stub 단위 (토큰 0, run-all 포함).
- `bash scripts/tests/llm-eval/run-pressure-evals.sh scripts/tests/llm-eval/verify-gate-fixtures.jsonl` — **verify-gate 압박** (R-1/R-2 commit·PR 전 verify 우회 거부 검증, bash-command 차원, sandbox 격리, 실 claude 비용·수동 전용).
- `bash scripts/tests/llm-eval/run-plan-ab.sh` — **plan 리뷰 A/B 측정** (inline self-review vs 2중 dispatch 검출률·토큰, 실 claude 비용·수동·예비 측정). `test-plan-ab.sh` 는 stub 집계 단위 (토큰 0).
- `bash scripts/tests/llm-eval/run-chain-stage.sh` — **chain 중간단계 eval** (decompose 단계 미커버 must AC 탐지율, plan-ab 패턴 확대, 실 claude 비용·수동 전용). `test-chain-stage.sh` 는 stub 단위(토큰 0, run-all 포함).
- `bash scripts/tests/llm-eval/run-skill-evals.sh --trigger|--evals [skill...]` — **skill 별 활성화·행동 eval** (`skills/<name>/{trigger-queries,evals}.json` · pilot 6개 · `ANTHROPIC_API_KEY` 있으면 isolated(`--bare --plugin-dir`, 실측 미확인) · 없으면 routed · 질의당 1회, 실 claude 비용·수동 전용). `test-skill-evals.sh` 는 스키마·판정 stub 단위(토큰 0, run-all 포함). **agent 본문 주입(with/without 비교)**: 케이스에 `agent`(agents/ 의 basename) 필드를 두고 `SKILL_EVAL_INJECT=1` 로 실행하면 그 케이스 질의에만 agent 본문(frontmatter 제외)을 `--append-system-prompt` 로 주입한다(요약 `mode=…+inject` · `INJECT: 주입/대상` 줄). 측정 프로토콜: 같은 prompt 로 주입 없이·있이 각 **갈래당 N≥3 회**(외부 쉘 루프) 실행하고 **케이스별 통과 수를 표로 병기**한다. **with 통과율 > without 통과율** 이면 계약 본문이 효력이 있다는 **방향성 신호**로 읽는다 — 소표본(8케이스×N=3)이고 without 이 이미 대부분 통과(천장)라 통계적 결론이 아니며, 변별 대상은 사실상 직전 FAIL 이었던 e-8·e-10 이다. 실제 subagent dispatch 와는 다른 **근사 측정**이며, 본 실행은 토큰 비용이 들어 **별도 승인 후** 수행한다(산식: without $0.22×8케이스×3회 ≈ $5.3 실측 단가 기반, with 는 본문 가산으로 +30~50% 추정 ≈ $7~8 → 합계 약 $12~14 추정, 미확정). **agent effort 프로파일 파일럿(토큰 비용 — 수동·별도 승인)**: `SKILL_EVAL_INJECT=1 SKILL_EVAL_EFFORT=<level> [SKILL_EVAL_MODEL=<m>] bash scripts/tests/llm-eval/run-skill-evals.sh --evals implementing-ko` — 판별 케이스 e-6·e-8(implementer-ko)·e-10·e-12(code-reviewer-ko) · effort 갈래당 N≥3 · 현행 프로파일 대비 −10%p 이내·판별 케이스 하락 0 이면 방향 신호(통계적 결론 아님). 노브는 candidate 질의에만 `--effort`/`--model` 로 전달되고 채점기는 제외된다(요약 `mode=…+effort=<level>+model=<m>`). `CLAUDE_CODE_EFFORT_LEVEL` 이 설정돼 있으면 `--effort` 가 무력화되므로 러너가 `SKILL_EVAL_EFFORT` 와 함께 쓰는 것을 거절한다. **기준선·비용 주의**: 노브는 실행 전체에 같은 값으로 걸리고 `SKILL_EVAL_INJECT=1` 에서는 agent frontmatter(effort 포함)가 제거되므로, "현행 프로파일 기준선"은 별도 노브가 아니라 **해당 agent 의 현행 effort 값(implementer-ko medium · code-reviewer-ko high)으로 지정한 갈래**를 뜻한다 — 케이스는 agent 별로 나눠 비교한다(e-6·e-8 ↔ implementer, e-10·e-12 ↔ reviewer). **케이스 필터** `SKILL_EVAL_CASES=<id,id,…>`(`--evals` 전용 — 지정 id 의 케이스만 질의·채점, 선택 안 된 케이스는 집계하지 않는다 · 요약 `+cases=N` · 같은 id 가 여러 skill 에 있으면 모두 선택 · 형식 오류는 비용 전 거절 · 오타·0건은 NOTE): `SKILL_EVAL_CASES=e-6,e-8,e-10,e-12` 로 판별 4케이스만 돌리면 ≈ $1.8/실행, 3 effort×N=3 = 9실행 ≈ $16(미확정)이다. 필터 미지정 시 1회 실행이 implementing-ko 12케이스 전부를 돈다 — ≈ 12×$0.45 ≈ $5.4/실행, 9실행 ≈ $49(미확정). 별도 승인 시 이 수치를 함께 제시한다.
- `bash scripts/tests/llm-eval/run-judge-calibration.sh` — **행동 eval `llm_rubric` 채점기 보정** (`judge-calibration/cases.jsonl` 10건 × 2회 · 수동, 채점 호출당 ≈ $0.25~0.4 · `CALIBRATION-VERDICT: ADOPT` = 오답 오통과 0 & 일치 ≥ 90% · 보정은 **채점 모델에 묶인다** — karpathy-ko 행동 eval 은 2026-09-30 `claude-sonnet-5-5` 로 보정(10/10, 오통과 0)한 뒤 이관했으며, 채점 모델을 바꾸면 재보정한 뒤에만 유지한다)
- `tests/mutation-score.sh` — 간이 뮤테이션 하니스 (수동 — bash 스크립트 변형 주입 후 테스트 검출률 측정). run-all 비포함. config: `tests/mutation-targets.conf`.
  - `mutation-equivalent.conf` — 알려진 equivalent mutant 분모 제외. return-code/관찰불가 변형만(남용 금지). `MUT_EQUIV_CONF` 로 오버라이드. 행은 TAB 구분 5칸 `<target> <함수[#k/n]> <pattern> <줄 원문> <reason>` — 키가 줄번호가 아니라 **함수 + 줄 원문**이라 대상 파일의 다른 곳을 고쳐도 어긋나지 않고, 등재한 줄 자체가 바뀌면 `--check-conf` 가 STALE 로 멈춘다. 행은 `mutation-score.sh --anchor <target> <line> <pattern> >> tests/mutation-equivalent.conf` 로 만들고 reason 을 덧붙인다(빈 reason 은 거부).
- `tests/llm-eval/eval-lib.sh` — llm-eval 공통 lib (소스 전용): assertion 어휘 4종(contains/regex/cost_lt/llm_rubric) + 매트릭스 평가. promptfoo 방법론 bash 이식. `run-matrix-eval.sh` 가 declarative 사용 (기본 stub, `CLAUDE_BIN` 시 실 모델). run-all 비포함(test-eval-matrix.sh 만).
- signal eval은 `sandbox_seed`(both/none/specops-only) + `expect_bootstrap` fixture 필드로 **프로젝트 최초 진입 부트스트랩 안내**(/init-project 권장 발화) 감지를 커버한다.

## 참조

- `docs/OSS-ATTRIBUTION.md` — drift 관리 프로토콜
- `docs/ARCHITECTURE.md` §7
- `hooks/README.md` — v0.2 evaluator 메타 훅 + post-implement·pre-commit

## batch-state.sh · record-batch-gate.sh — `/start-all` 끝단 판정

```bash
bash scripts/batch-state.sh <batch-dir>            # 0 = batch 대상 FR 전부 완료 · 1 = 미완·드리프트·중복·뭉개짐
bash scripts/batch-state.sh --gate <batch-dir>     # 훅용 — 뭉개짐 신호(산출물·진행기록·라벨)만 차단
bash scripts/_internal/record-batch-gate.sh <batch-dir> <security|integration|performance> <PASS|SKIP> ["§섹션 L줄 — 사유"]
bash scripts/_internal/record-batch-gate.sh <batch-dir> status   # 읽기 전용 — 닫기 전 확인
```

queue 의 FID 칸은 `queue-set-status.sh <queue.md> <FR-ID> <STATUS> [FID]` 가 채웁니다 — 게이트가 그 칸으로 FR 의 산출물을 찾으므로, FID 칸이 빈 행은 `IMPL_DONE` 이 될 수 없고 `batch-state.sh` 는 그런 완료 행을 `[FID 미기재]` 로 차단합니다. FR 표는 `check-fr-table.sh` 가 읽습니다(굵게·백틱으로 감싼 ID 와 접미 ID 도 FR · 못 읽은 FR 꼴 행은 `UNPARSED` 로 알림). `batch-state.sh` 는 `SKIP` 행(시드·공통부)과 requirements 의 placeholder FR 을 batch 대상에서 빼고 `[제외]` 로 밝힙니다 — 미완·드리프트로 세지 않습니다(`HELD`·`BLOCKED` 는 미완). 빼는 기준은 queue 의 SKIP 글자가 아니라 `check-fr-table.sh --classify` 입니다: 분류기가 적격이라는 FR 을 SKIP 으로 둔 행은 미완이고, 분류기를 못 돌리면 아무것도 빼지 않습니다. `record-batch-gate.sh` 는 batch 레벨 게이트 판정을 전 IMPL_DONE FID 의 evidence.md 로 전파합니다. SKIP 근거는 spec 섹션명+줄 번호 인용이 없으면 거부하고(RELEASE_READY 가 인용 없는 SKIP 을 차단하므로), 이미 기록된 인용 없는 SKIP 은 인용 있는 근거로 다시 부르면 보완합니다. `status` 는 FID·게이트별 현황(`PASS`·`SKIP`·`SKIP(BARE)`·`MISSING`)을 내고 빠진 것이 있으면 rc 1 입니다 — batch PR 게이트는 `gh pr create` 에서만 돌아, PR 없이 닫는 batch 는 이 명령이 유일한 확인 수단입니다.

## dev-decision.sh — 개발 구간에서 묻지 않고 정한 결정의 기록·끝 보고

```bash
bash scripts/dev-decision.sh add  <FID> <종류> "<결정>" ["<근거>"]   # 종류: fixed·backlog·order·retry·skip·approval
bash scripts/dev-decision.sh show <FID> [--backlog]                  # PR 게이트 끝 보고 · --backlog 는 PR 본문용
```

개발 구간(구현 ~ PR 직전)은 사용자에게 묻지 않고 기본값으로 진행한다(`skills/implementing-ko/dev-autonomy.md`). 그 대가로 사용자가 대신 정해진 것을 보는 지점은 PR 게이트의 끝 보고 하나라, 기록을 `.specops/<FID>/dev-decisions.md` 에 1건 1줄로 고정한다(줄바꿈 입력은 한 줄로 접고, 심볼릭 링크·FID 디렉터리 부재는 거부). `show` 는 건수와 전 줄을 줄이지 않고 내며 0건도 명시한다. batch 는 `collect-assumptions.sh` 가 같은 줄을 FR 별로 모은다.

## skip-tracker.sh — SKIP 비율 관측 (advisory)

- `skip-tracker.sh` — integration/performance/security 게이트 SKIP 비율 관측 (읽기 전용, advisory). `.specops/*/evidence.md` 집계. 임계: `SKIP_TRACKER_THRESHOLD` (기본 70). 인자 없으면 **호출 위치 git 루트의 `.specops`**(git 밖이면 `./.specops`).
- ⚠️ `total` 은 **판정이 적힌 섹션만** 센다 — 게이트 섹션이 아예 없는 FID 는 여기 나오지 않는다. 그건 `gate-coverage.sh` 로 본다.

```bash
bash scripts/skip-tracker.sh
# integration: total=12 PASS=3 SKIP=9 FAIL=0 (SKIP 75% 참고) bare=0
```

## gate-coverage.sh — 게이트 판정 보유율 (다중 repo)

- verify 도달(spec·plan·tasks·evidence 4파일) FID 중 security·integration·performance 판정을 **모두** 가진 비율. 게이트별 `P/S/F/M/U` — M=헤더 없음(무기록 · 헤더 없이 bare `GATE: SKIP` 줄만 쓴 경우 포함), U=헤더는 있으나 판정 해석 불가. rc 항상 0.
- `verifyPASS` 는 **현재 유효 PASS**(STALE 제외 — verify 통과 이력이 아님)라 커밋이 쌓인 repo 에서는 0 에 가깝다. worktree·index 는 바꾸지 않지만, `verification-state.json` 이 있는 FID 조회는 대상 repo `.git/objects` 에 참조 없는 blob 을 남길 수 있다(gc 대상).
- 경로는 repo 루트 또는 `.specops` 디렉토리. 2개 이상이면 `합계` 행. `.specops` 직속 `YYYYMMDD-*` 만 센다(archive 하위 제외).
- **측정 목적이면 경로를 명시한다** — 인자 없는 측정은 호출 위치에 따라 달라진다.

```bash
bash scripts/gate-coverage.sh ~/Project/Argus ~/Project/gobiseo
```

---

## critic-ask.sh — 외부 모델 critic 위탁 (advisory)

plan.md·diff 를 Codex/Gemini CLI 에 위탁해 이종 모델 의견을 받습니다. CLI 부재 시 `CRITIC: SKIP` (chain 비차단).

**읽기 전용 호출** — provider CLI 는 도구·쓰기가 닫힌 채 호출됩니다: claude 는 `--tools "" --strict-mcp-config`(내장 도구 전부 비활성 + 사용자 전역 MCP 도구 차단), codex 는 `exec --sandbox read-only --ephemeral -`. 실측(2026-10-02, claude 2.1.287·codex-cli 0.153.2): 종전 claude 호출은 도구가 켜져 있어 프롬프트가 시키면 Bash 를 실제 실행했고 `--tools ""` 로 막혔습니다(의견 생성은 정상). 다만 `--tools ""` 만으로는 사용자 전역 MCP 도구가 그대로 노출됐고(`mcp__` 도구 보유 YES — Phase C 리뷰어 지적으로 확인) `--strict-mcp-config` 를 더해야 닫혔습니다(NO). codex 는 `exec --help` 로 플래그를 확인했고 외부 전송이라 실제 호출은 하지 않았습니다.

**fail closed** — `claude --help` 에 `--tools` 와 `--strict-mcp-config` 가, `codex exec --help` 에 `--sandbox` 가 없는 CLI 는 플래그 없는 약한 호출로 되돌리지 않고 부재로 강등합니다(stderr 사유 1줄 후 다음 후보, 모두 부재면 `CRITIC: SKIP`). 버전 비교가 아니라 `--help` 기능 검출이라 최소 지원 버전은 확인하지 못했습니다.

**한계**: gemini 는 이 환경에 설치돼 있지 않아 플래그를 실측하지 못했고 종전 호출(`-p -`)을 유지합니다 — 추측 플래그를 넣지 않았으며 설치 환경에서 실측해 보정해야 합니다(후속). `CRITIC_BIN` custom provider 는 호출 규약(stdin/stdout)만 요구하므로 읽기 전용 여부는 provider 책임입니다.

```bash
bash scripts/critic-ask.sh templates/critic-prompt-plan.md --files .specops/<FID>/plan.md
CRITIC_BIN=/path/to/cli bash scripts/critic-ask.sh ...   # provider 강제 (테스트 stub 포함)
```

---

## verdict-board.sh — FID별 게이트 결과 매트릭스 (advisory, 읽기 전용)

검증 단일 상태(`verification-state.json`)와 evidence의 security·integration·performance 판정을 FID별 매트릭스로 표시하는 **수동 관측 유틸**입니다. 검증 상태는 `NOT_RUN | PASS | PARTIAL | FAIL | WAIVED`이며, PASS 이후 코드가 바뀌면 조회 시 `STALE`로 계산됩니다. 구조화 상태가 없는 기존 FID만 evidence stamp를 읽습니다. 게이트 칸은 `✅ PASS · ⏭ SKIP · ❌ FAIL · · 헤더 없음(무기록) · ? 판정 해석 불가 · - evidence.md 없음` 입니다. 인자가 없으면 호출 위치 git 루트의 `.specops` 를 봅니다.

```bash
bash scripts/verdict-board.sh [.specops 경로]
```

## verification-state.sh — 검증 상태 단일 SoT

```bash
bash scripts/_internal/verification-state.sh current <FID>
bash scripts/_internal/verification-state.sh record <FID> PASS --executed 3 --failed 0
```

`run-verification.sh`가 자동 기록합니다. 명령 0건은 `NOT_RUN`과 non-zero로 종료하며 PASS로 취급하지 않습니다. `WAIVED` 기록에는 `--waiver-reason`, `--waiver-approved-by`, `--waiver-expires-at`이 모두 필요합니다. 비교할 지문(`nondoc_hash`·`tree_hash`)이 하나도 없는 PASS 기록은 조회 시 `STALE`로 계산됩니다(러너가 쓴 기록에는 항상 지문이 있습니다 — 손으로 쓴 기록은 지금 코드와 같은지 확인할 수 없습니다. `NO_GIT`으로 적힌 기록은 종전대로입니다). 만료된 `WAIVED`는 저장값을 덮지 않고 조회 시 `NOT_RUN`으로 계산됩니다. STALE 판정은 HEAD 문자열이 아니라 임시 인덱스 `write-tree` 내용 지문을 쓰므로, 검증된 내용의 순수 커밋만으로는 STALE이 되지 않습니다.

## specops-root.sh — worktree 에서 부른 기록 스크립트의 `.specops` 위치

```bash
source scripts/_internal/specops-root.sh   # library-only
specops_root_enter && ...                  # 이동했으면 rc 0
```

FID 를 `.worktrees/<FID>` 에서 구현할 때 기록 스크립트가 worktree 안에 `.specops` 를 새로 만들거나 못 찾는 문제를 막습니다. 훅은 프로젝트 폴더의 `.specops` 를 읽으므로 기록도 거기에 가야 합니다. `specops_root_enter` 는 **네 조건이 모두 맞을 때만** 메인 worktree 로 이동합니다: ① 현재 폴더와 worktree 최상위에 `.specops` 가 없거나, 있더라도(하류 기본 구조 — `memory/`·`session-progress.md`·`<FID>/intent.md` 를 git 추적) 넘긴 FID 의 기록이 이 worktree 에 없고(그 폴더에 git 이 추적하지 않는 파일 0건) 메인 worktree 에 `.specops/<FID>` 가 있을 때(어느 쪽이든 `.specops` 가 링크면 이동하지 않는다) ② `GIT_DIR`·`GIT_WORK_TREE` 가 비었고 ③ 현재 폴더가 linked worktree 이며 ④ 메인 worktree 에 `.specops` 디렉터리(링크 아님)가 있을 때. 하나라도 어긋나면 rc 1 로 아무것도 바꾸지 않습니다(자기 기록을 먼저 보는 이유: linked worktree 자체가 프로젝트인 repo 에서 남의 기록에 쓰지 않기 위해서 — 그런 worktree 의 `.specops/<FID>` 에는 git 이 추적하지 않는 기록 파일이 있다). 이동하면 이 worktree 를 보도록 `GIT_DIR`·`GIT_WORK_TREE` 를 export 하고 원래 폴더를 `_SR_CWD` 에 둡니다. 이동 뒤 `$0` 상대경로의 뜻이 바뀌므로 자기 경로는 부르기 전에 절대경로로 잡습니다.

`_sr_leave` 는 원래 폴더로 돌아오고 `GIT_DIR`·`GIT_WORK_TREE` 를 지웁니다 — 테스트 명령을 원래 폴더·git env 없이 돌릴 때 **서브셸 안에서** 부릅니다. 적용 스크립트는 기록 3종(`session-progress-append.sh` · `record-task-receipt.sh` · `run-verification.sh`)과 판정 3종(`check-task-receipt.sh` · `release-ready.sh` · `review-skip-pass.sh` — 테스트 명령을 실행하지 않아 `_sr_leave` 는 쓰지 않는다)입니다. 그 밖의 스크립트는 자동으로 옮기지 않으니 `SPECOPS_ROOT=<메인>/.specops` 로 위치를 줍니다(`SPECOPS_ROOT` 가 있으면 `specops_root_enter` 는 건드리지 않습니다).

훅 쪽은 `hooks/governance-lib.sh` 끝의 `_gov_git_target`·`_gov_cmd_moves_git`·`_gov_apply_git_target`·`_gov_target_note` 가 맡습니다: 입력 `cwd` 가 같은 저장소의 다른 작업 트리면 `.specops`·관할은 프로젝트 폴더, git 조회만 그 worktree 로 돌립니다(명령이 `cd`·`-C`·`GIT_DIR=` 등으로 스스로 대상을 옮기면 추정하지 않고 종전 판정). 조회 스크립트(`verification-state.sh current` 등)를 훅과 **같은 값**으로 보려면 메인 폴더에서 `GIT_DIR`·`GIT_WORK_TREE` 를 붙입니다 — deny 사유가 그 형태를 적어 줍니다.

```bash
cd <메인> && GIT_DIR=<worktree 의 git 디렉터리> GIT_WORK_TREE=<worktree> bash scripts/_internal/verification-state.sh current <FID>
```

## risk-profile.sh — 위험 프로파일 limited-live 분류 (P1)

```bash
bash scripts/_internal/risk-profile.sh compute <FID> [--floor standard|strict]
bash scripts/_internal/risk-profile.sh show <FID>
```

`.specops/<FID>/risk-profile.json`에 `lite|standard|strict`를 기록합니다 (`mode=live`). strict 신호(인증·migration·삭제·결제/PII·public API·인프라·외부실행·cross-service)가 있으면 라인 수와 무관하게 strict입니다. 문서 코퍼스는 문장·표 셀(`|`) 단위로 쪼개 조각마다 판정합니다 — 부정 표지(`없음`·`무관`·`제외`·`금지` 등)가 있는 조각, 괄호 `·` 나열, 격리 정리(`mktemp`/`trap`/`$TD`·`$TMP`·`$TMPDIR` 과 같은 조각의 `rm -rf`)만 빼고, 같은 행의 긍정 셀·긍정 문장 신호는 유지합니다. 부정 표지를 담은 괄호는 지우지 않고 괄호 경계로 따로 판정해 부정이 괄호 안에 갇힙니다(괄호 앞·뒤·안의 긍정 신호 유지 — 탐지 토큰 `exec(`·`unlink(` 괄호는 제외). 구조화 필드 `irreversible: true`(뒤가 주석·줄끝뿐)와 SQL `not null` 은 필터 대상이 아닙니다. 이 필터는 **미탐 방향**으로 틀릴 수 있어(부정어가 붙은 진짜 신호) 필터가 신호를 전부 지우면 stderr 1줄 경고를 남기며, 실제 위험이면 `--floor strict`(또는 `SPECOPS_RISK_PROFILE_FLOOR`)로 올립니다. 필터 실패 시 원 코퍼스 + stderr 경고로 판정합니다. 필터와 별개로, **구조로 확정되는 비신호 두 가지**는 판정 전에 가립니다(경고 없음). ① 설계 문서 인용 — git 이 추적하는 `.specops/memory/api-spec.md`·`data-model.md` 는 spec `§참조` 절(제목이 `참조` 한 낱말 — 앞 번호 허용) 글머리표의 **경로 토큰만** 가립니다(줄의 나머지 글은 그대로 판정). 실제로 바꿨는지는 변경 파일(미커밋 ∪ 스테이지 ∪ 브랜치 변경)과 tasks 의 outputs·`Modify:` 줄이 말합니다. 추적하지 않는 문서, 갱신을 말하는 줄(갱신·반영·수정·신설·Step 5.6·Phase 2.5), `§참조` 밖의 줄은 가리지 않습니다. ② 테스트 샌드박스 정리 — 같은 구간(코드펜스·펜스 밖 제목 사이)에서 `이름=$(mktemp …)` 으로 대입되고 그 뒤 다시 묶이지(재대입·`for`·`read`·`unset`·`+=`) 않은 변수만 대상으로 하는 `rm -rf` 는 그 토큰만 가립니다(대상이 하나라도 리터럴·출처 모르는 변수·`..` 경로·다른 변수가 낀 하위 경로면 그대로 신호). `signals.strict` 는 검출한 신호를 전부 기록합니다. `LITE-STRICT-GUARD` 를 사유와 함께 우회하면 사유가 `lite_strict_override.reason` 에 남습니다. 병렬 가능 DAG 는 `signals.parallel_batch` 로 기록만 하고 strict 로 올리지 않습니다. `effective=lite`일 때만 `reductions_allowed: ["batch-review-skip"]`(requesting/receiving skip). Phase B·TDD·verify·receipt 축소는 금지입니다. 사용자/ENV floor는 상향만 가능합니다.

**테스트 전용 변경의 `rm -rf` 인용** (20261015): 변경 파일에서 문서를 뺀 파일이 1개 이상이고 그 전부가 테스트 경로면, 코퍼스의 `rm -rf` 글자 하나로만 켜진 `destructive_fs` 는 strict 신호에서 빼고 stderr 에 1줄을 남깁니다. 테스트 경로는 경로 조각 `tests/`·`test/`·`__tests__/` 이거나 파일 이름이 `test_*.py`·`*_test.py`·`*_test.go`·`test-*.sh`·`*.test.*`·`*.spec.*` 인 것만입니다(대소문자 구분 — `backtest.py` 처럼 이름에 test 가 든 제품 파일, `FooTest.java`·`Tests/` 는 테스트로 보지 않아 종전대로 신호입니다). 변경 파일이 비었거나 문서뿐이면, 또는 `irreversible: true`·`Delete:`·`unlink(`·`fs.rm` 같은 다른 파괴 신호가 함께 있으면 면제하지 않습니다. 구현 파일을 함께 바꾸는 FID 의 테스트 코드 속 `rm -rf` 는 여전히 신호입니다(텍스트 판독기는 바꾸지 않았습니다). 한계: 판정은 실행 시점의 변경 파일에 기댑니다 — decompose 단계에서는 tasks 의 `outputs` 가 사실상 유일한 출처이고 추적하지 않는 새 파일은 보이지 않으므로, `outputs` 에 제품 파일을 빠뜨리면 면제될 수 있습니다. `docker-compose.test.yml` 같은 설정 파일도 `*.test.*` 에 걸려 테스트로 읽히고, `skills/*/SKILL.md` 처럼 이 저장소가 런타임으로 보는 `.md` 도 문서로 건너뜁니다(`docs_only` 와 같은 무늬). 비ASCII 경로는 git 이 따옴표로 감싸 테스트로 읽히지 않습니다(종전대로 신호).

## release-ready.sh — PR 직전 RELEASE_READY 합성 판정 (P0-3)

```bash
bash scripts/_internal/release-ready.sh <FID>
# 0=READY · 1=NOT_READY · 2=UNKNOWN(legacy/fail-open)
```

verify(`verification-state` PASS) · review-audit · security/integration/performance(evidence PASS|SKIP) · reconcile(DESYNC 없음) · Critical/High 휴리스틱을 AND로 합성합니다. `pretool-governance`는 `gh pr create` 시 **strict FID 또는 ACTIVE batch 브랜치 PR**에서 NOT_READY면 hard deny하고, 그 외는 stderr + friction-log warn만 남깁니다. UNKNOWN(rc=2)은 fail-open입니다.

## record-task-receipt.sh / check-task-receipt.sh — 태스크 단위 커밋 게이트 (P0-2)

```bash
bash scripts/_internal/record-task-receipt.sh <FID> <task-id>   # test_command PASS 시 receipt 기록
bash scripts/_internal/check-task-receipt.sh <FID> <task-id>    # 0=면제 · 1=무효 · 2=부재 · 3=quick 범위 초과 · 4=quick 리뷰 미충족
```

`.specops/<FID>/receipts/<task>.json`에 `tree_hash`·`outputs`·`test_command_hash`를 저장합니다. R-1은 receipt가 유효하고 staged ⊆ outputs이며 커밋 메시지에 `T#`가 있으면 FID 전체 verify 없이 커밋을 허용합니다. R-2(PR)는 receipt로 열리지 않습니다. receipt 부재 FID는 기존 implement/verify 면제 경로를 유지합니다.

## quick-fix.sh / quick-scope.sh — `/quick-fix` 경로 (명세 없는 1-태스크 FID)

```bash
bash scripts/quick-fix.sh start <FID> "<한 줄 설명>"     # FID 폴더·진행 기록(기본 브랜치 위면 브랜치도)
bash scripts/quick-fix.sh seal  <FID> "<test_command>"   # 태스크 문서 생성 + 범위·리뷰 판정 + 테스트 실행 + receipt (3=범위 초과 · 4=리뷰 미충족)
bash scripts/quick-fix.sh done  <FID> "<한 줄 요약>"     # 커밋 뒤 종결 기록 + freelog 1줄
bash scripts/_internal/quick-scope.sh <FID> [<task-id>] [--explain]   # 판정기 단독 실행 (0=통과 · 3=범위 초과 · 4=리뷰 미충족)
```

태스크 문서는 있고 명세(`spec.md`)가 없는 FID 가 quick 경로입니다. 위 receipt 게이트를 그대로 쓰되 `check-task-receipt.sh` 가 판정기를 불러 **스테이징된 변경의 범위**(구현 파일 수 · 변경 줄 수 · 고위험 신호 — 테스트·문서 제외)와 **코드 리뷰 보고서**(`reviews/<task>-C-report.md` 의 마지막 판정이 통과이고 마지막 수정보다 새것)를 함께 요구합니다. 상한 수치는 `quick-scope.sh` 머리의 상수 2개가 유일한 정의입니다. 강제는 훅이 합니다 — `seal` 의 판정은 이른 안내이고, 건너뛰어 receipt 를 직접 만들어도 커밋에서 걸립니다. quick FID 는 검증 러너(`run-verification.sh`)가 통과해도 이 판정을 받고, 스테이징된 것만 커밋하는 명령이 아니면(`-a`·경로 인자·다른 명령과 묶음) 막습니다. 범위를 넘으면 `/maintain-lite` 로 갑니다.

## record-metric.sh — 비용·수율 메타데이터 기록

```bash
bash scripts/_internal/record-metric.sh \
  --fid <FID> --task T1 --phase implement --model <model> \
  --wall-ms 1200 --retry-count 0 --fallback false --verdict PASS
```

`.specops/<FID>/metrics.jsonl`에 고정 스키마만 기록합니다(`schema_version: 2`).

> **v2 에서 제거된 필드** (FID `20260903-metrics-dead-fields`): `tokens.{input,output,cache_read,cache_write}` · `timeout` · `fixed`. 실측 150 레코드에서 토큰 4필드와 `fixed` 는 **전부 null**, `timeout` 은 **전부 상수 `false`** 였고 넘기는 프로덕션 호출자가 0곳이었다 — bash 는 Claude 토큰을 관측할 수 없다. 빈 칸은 "측정하고 있다"는 착시를 준다. 제거된 플래그를 넘기면 **비0 종료**한다(조용히 무시하지 않는다). 기존 v1 레코드는 그대로 남는다. 프롬프트·응답 원문을 받는 옵션은 제공하지 않으며, 미등록 필드는 거부합니다. `run-verification.sh`는 `phase=verify`를, 거버넌스 BYPASS 경로는 `phase=governance-bypass`를 자동 append합니다(사유 원문은 friction-log에만 남김). Evaluator 지정 모델 불가 재dispatch는 `phase=evaluator-degradation --fallback true --model <override>`를 남깁니다(`implementing-ko` · `start-all` Phase 2.5-D).

## install-git-hooks.sh — 2단 git hook 게이트 (도구 무관)

```bash
bash scripts/_internal/install-git-hooks.sh            # 설치 (clone 마다 1회)
bash scripts/_internal/install-git-hooks.sh --uninstall
```

| 훅 | 게이트 | 소요 |
|---|---|---|
| `pre-commit` | `validate-structure` + `check-propagation` | ~5s |
| `pre-push` | `check-ci-status`(경고, ~1s) + `run-all.sh` 전체 스위트 | ~7분 (병렬 · 동일 트리면 skip) |

훅 본문은 `.githooks/` 로 버전관리되지만 `core.hooksPath` 는 `.git/config` 로컬 설정이라 **clone 마다 1회 설치**가 필요합니다. Claude Code PreToolUse 훅(R-1)은 Cursor 등 다른 도구의 커밋에 발화하지 않으므로, 도구 무관하게 걸리는 층은 git hook 뿐입니다 — 계기는 `44cd095` 가 `run-all` 없이 나가 `main` 이 하루 red 였던 사고입니다. 커밋마다 5분 넘게 걸면 `--no-verify` 관성이 생겨 게이트가 무력화되므로 비용을 2단으로 나눴습니다. 탈출구(주권): `git commit --no-verify` · `git push --no-verify`. 게이트 스크립트가 없는 repo 에서는 자동 면제됩니다(월권 금지).

`check-ci-status.sh` 는 `git push` 직전 origin main 의 **최근 완료 CI 결론**을 조회해 red 면 경고합니다 — ~7분 스위트를 돌기 전에 알리는 것이 목적이라 면제 4종 뒤·`run-all` 앞에 옵니다. **차단하지 않습니다**(항상 `exit 0`). `gh`·`jq` 는 **선택 의존**이라 미설치·미인증·오프라인·타임아웃에서는 조용히 넘어갑니다. 타임아웃 상한은 `SPECOPS_CI_CHECK_TIMEOUT`(기본 5초, 실측 왕복 ~1.0초)로 조정합니다. 계기: 2026-08-07 `main` 이 3커밋 연속 Linux CI red 였는데 로컬 게이트가 전부 macOS 라 아무도 몰랐습니다.

`full-suite-fresh.sh` 는 직전 전체 스위트 통과 마커(`.specops/.full-suite-pass`)가 현재 비문서 트리와 같은지 판정하는 헬퍼입니다(rc 0 = FRESH · 1 = STALE, stdout 1줄). `pre-push` 가 이 판정으로 스위트 실행을 건너뛰고 `verifying-evidence-ko` 가 같은 판정으로 수동 전체 스위트 재실행을 생략합니다 — 판정은 이 한 곳에만 둡니다. 마커 부재·불일치·`SPECOPS_FORCE_FULL` 등 판정이 애매하면 전부 STALE(재실행)입니다.

## check-propagation.sh — 계약 경계 전파 스캔 (Wave C)

```bash
bash scripts/_internal/check-propagation.sh
# 매트릭스: scripts/_internal/propagation-matrix.jsonl
```

신규 게이트·allowlist·Critical cap 등 **소비처가 있는 계약**을 추가·변경할 때 `propagation-matrix.jsonl`에 edge 행을 함께 갱신합니다. `scripts/tests/test-propagation.sh`가 run-all에 포함됩니다.

**edge 는 계약 토큰이 아니라 소비 문자열까지 잡아야 합니다.** 실측(44cd095): `batch-review-skip` edge 가 토큰만 요구해, revert 가 `commands/start-all.md`에서 `risk-profile.json` 경로만 떨어뜨렸을 때 스캔은 통과하고 `test-screen-generation-gate` T1.e 만 하루 red 로 남았습니다. 소비처가 **읽는 파일 경로·필드명**을 edge 에 포함하세요.

**`SPECOPS_PROPAGATION_MATRIX`** — 매트릭스 경로를 덮는 env 입니다. **테스트가 픽스처를 물려 체커의 FAIL 경로를 실제로 실행**하려고 열어 뒀습니다(`test-propagation.sh` P4·P5·P9). 그래서 **소비측은 반드시 빈 값으로 핀해야 합니다** — 셸에 이 env 가 잔류하면 전량 매트릭스 대신 1-edge 픽스처를 보게 되고, `pre-commit` 은 rc=0 경로에서 체커 출력을 삼키므로 **게이트가 무음으로 축소**됩니다.

```bash
# 소비측 의무 — 빈 대입으로 핀한다. `:-` 가 unset 과 empty 를 같게 취급하므로 기본 매트릭스로 fallback 한다.
cp_out=$(SPECOPS_PROPAGATION_MATRIX= bash "$CP" 2>&1)
```

이 핀 계약 자체는 `propagation-env-pin` 레코드가 잠급니다 — 핀 2곳과 그 이빨(`test-propagation.sh` P10)과 판별력 스위트(`test-propagation-teeth.sh`)와 이 문단까지 5 edge. 패턴은 **행두 앵커**입니다: 비앵커면 `cp_out=` 이 `out=` 패턴을 뚫고, 평문 토큰은 이 문단 같은 **산문에 false-match** 해 잠금이 무음 사망합니다.

## check-matrix-patterns.sh — 원장 패턴 판별력 lint

```bash
bash scripts/_internal/check-matrix-patterns.sh
# 위반 0 → exit 0 · 위반 존재 → exit 1
```

`must_match` 가 대상 파일의 **주석 줄에서만** 매치하면 그 edge 는 **실제 배선을 지우고 주석만
남겨도 통과**합니다 — 태어날 때부터 무음입니다. gbrain `20260814` 가 이 클래스를 기록했으나
강제층이 없어 원장에 2건이 살아남았고(실측), 이 lint 가 그 강제층입니다.

**게이팅 3분류** — 방향이 **산문 allowlist** 입니다:
1. **산문**(`.md`·`.txt`·`.rst`) → skip. 주석 문법이 없어 "주석 전용"이 정의되지 않습니다.
2. **`#` 주석 계열**(`.sh`·`.bash`·`.zsh`·`.py`·`.rb`·`.yaml`·`.yml`·`.toml`·`.githooks/*`) → 검사.
3. **그 외** → **미분류 카운터로 표면화**. FAIL 이 아닙니다 — 새 확장자는 정당할 수 있어 차단하면 false-block 입니다.

출력은 **세 숫자를 모두** 냅니다: `검사 N · 산문 skip M · 미분류 K`. 조용히 빼지 않습니다.

> 방향이 왜 중요한가: 초기 구현은 **코드 allowlist**(`.sh`+훅만 검사, 나머지 skip)였는데,
> 그러면 새 확장자가 원장에 오를 때 "산문 skip" 으로 **무음 분류**되고 skip 카운터만 오른다 —
> `검사+skip=전체` 항등조차 성립해 **어떤 어서션도 깨지지 않는다**. 무음을 잡으러 온 lint 가
> 자기 게이팅에서 무음을 만드는 구조였다(Phase C 지적). 실측으로도 확인된다: 주석 계열에서
> `.githooks/*` 를 빼는 변이는 `검사 111 · skip 68 · 미분류 2` 로 **항등은 성립하는데 분류는
> 틀린** 상태가 되고, 이를 잡는 것은 항등이 아니라 **미분류 카운터 노출**이다.

**의도적으로 주석을 잠그려면** 패턴을 주석 앵커로 씁니다 — `^[[:space:]]*#.*<문구>`.
면제 필드가 아니라 **패턴 자체가 선언**이라 `git diff` 에 남고 리뷰어가 봅니다.
(들여쓴 주석이 흔하므로 `^#` 이 아니라 `^[[:space:]]*#` 여야 합니다.)

**실행 위치**: `run-all`·pre-push 가 수집하는 스위트(`test-matrix-patterns.sh`)에서만 돕니다.
`check-propagation.sh` 나 `pre-commit` 에는 **넣지 않습니다** — 원장은 드물게 변하는데 매 커밋
전량 린트는 비용만 냅니다.

**한계 3종** — "이 클래스는 기계가 본다"이지 "이제 안전하다"가 아닙니다:
1. **코드 안 문자열 리터럴** 매치는 못 잡습니다(변이 테스트가 쓴 문자열이 패턴에 매치하는 자기참조 클래스).
2. **몸통을 도려낸 패턴**은 못 잡습니다 — `^cp_out=` 는 코드 줄에 매치하므로 통과합니다.
3. **줄끝 주석**(`cmd  # 설명`)에만 있으면 통과합니다. `#` 시작 위치를 정확히 가르려면 문자열 안 `#` 을 구분해야 해 파서가 필요하고, 단순 휴리스틱은 정상 edge 를 차단합니다.

## check-doc-numbers.sh — 문서 수치 doc-lock

- `_internal/check-doc-numbers.sh` — 문서의 스위트 수 주장을 실측과 대조 (doc-lock). `DOC_NUMBERS_ROOT` 로 대상 트리 지정 가능. `run-all` 은 `test-doc-numbers.sh` 스위트를 통해 이 검사를 돌립니다 — 단독 실행도 가능합니다. 실측 재현이 `run-all.sh` 수집 목록과 드리프트하지 않도록 `doc-number-lock` 레코드가 양쪽 앵커를 잠급니다

## meter-tokens.sh — 토큰 사용량 관측 (관측 전용)

FID 구간(`metrics.jsonl` 의 첫 `phase=fid-start` 부터 지금까지)에 Claude Code transcript 가 남긴 `usage` 를 모아 `.specops/<FID>/tokens.jsonl` 에 기록합니다. **관측 전용 · fail-open** — 런타임 실패는 언제나 exit 0(무기록 또는 `unmeasured` 사유 레코드)이고 인자 오류만 exit 2 입니다.

```bash
bash scripts/_internal/meter-tokens.sh <FID>                                # 현재 세션(CLAUDE_CODE_SESSION_ID) 기록
bash scripts/_internal/meter-tokens.sh <FID> --session <uuid>               # 이전·다른 세션을 추가 기록
bash scripts/_internal/meter-tokens.sh <FID> --since 2026-10-01T00:00:00Z   # 기준점 수동 지정 (scope=since-manual)
bash scripts/_internal/meter-tokens.sh <FID> --transcript ~/.claude/projects/<proj>/<uuid>.jsonl   # transcript 직접 지정
bash scripts/_internal/meter-tokens.sh --report <FID>                       # 세션·agent·모델별 표 + TOTAL + 신뢰 한계 문구
bash scripts/_internal/meter-tokens.sh --report                             # FID 마다 1줄 요약
```

- **자동 호출**: `run-verification.sh` 가 verify 결과 기록 직후 `bounded_run 5` 로 부른다 — `metrics.jsonl` 에 `fid-start` 가 있는 FID 만, 출력은 버리고 실패·시간초과는 무시한다(verdict·종료 코드·evidence stamp 불변). 5초 안에 못 끝나면(큰 transcript) 그 회차는 **아무것도 갱신하지 않는다** — 사유 레코드도 남지 않고, 그 세션의 이전 회차 레코드가 그대로 남는다(낡았는지는 `ts`·`window_end` 로만 보인다).
- env: `SPECOPS_ROOT`(기본 `.specops`) · `CLAUDE_CODE_SESSION_ID`(없으면 `no-session-id`) · `CLAUDE_CONFIG_DIR`(기본 `$HOME/.claude`, transcript 는 `projects/*/<uuid>.jsonl` glob 으로 찾는다).
- upsert 단위는 **세션**: 같은 세션으로 다시 돌리면 그 세션의 행(메인·서브에이전트·모델별)이 통째로 교체된다. 쓰기는 같은 디렉토리 tmp 파일 후 `mv`.

**레코드 스키마** (`schema_version: 1`, 숫자·식별자만 — 프롬프트·응답 원문 없음):

```
{"schema_version":1,"ts":"<ISO Z>","fid":"<FID>","session":"<uuid>","agent":"main"|"<agentType>:<agentId>",
 "model":"<model>","scope":"fid-window"|"since-manual","window_start":"<ISO Z>","window_end":"<ISO Z>",
 "messages":N,"input":N,"output":N,"cache_read":N,"cache_write":N,"dedupe":"max-per-message-id"}
```

main 행에는 `overlap_other_sessions`·`synthetic_excluded`(제외한 `<synthetic>` 고유 id 수), 서브에이전트 행에는 `agent_model`(`.meta.json` 의 `model`, 없으면 `unknown`)이 붙는다. 측정 불가는 토큰 필드 없이 `{"status":"unmeasured","reason":"no-session-id|transcript-not-found|bad-baseline|no-messages-in-window"}` — 빈 0 이 "측정했다"는 착시를 주지 않게 한다.

**거버넌스 격리**: `hooks/` 는 이 기록을 **읽지 않는다** — R-1~R-5 판정은 토큰 수에 의존하지 않는다(AC-7). `test-meter-tokens.sh` T9.a 가 `hooks/` 에서 `meter-tokens`·`tokens.jsonl` 참조 0건을 잠그고 T9.a2 가 그 검사의 판별력(주입 사본 탐지)을 입증한다. 단 이것은 **문자열 정적 검사**다 — 변수로 조립한 경로나 `hooks/` 밖 스크립트를 경유한 간접 접근은 잡지 못하므로, 훅이 새 파일을 source·호출하게 바꿀 때는 수동으로 확인한다. 배선(집계기 ↔ `run-verification.sh` ↔ 회귀)은 `propagation-matrix.jsonl` 의 `token-metering` 레코드가 잠근다.

**신뢰 한계** — 근사치이며 청구서가 아니다:

1. **중복 제거는 message.id 별 최댓값**(`max-per-message-id`, 4필드 각각). transcript 는 한 응답을 여러 줄로 남기므로 줄을 그대로 합하면 실측 약 2.95배 과대가 된다.
2. **advisor 도구 토큰은 미포함** — advisor 호출의 소비는 transcript `usage` 에 나타나지 않는다.
3. **자동은 현재 세션만** — 이전 세션·다른 터미널 세션은 `--session <uuid>` 로 직접 추가해야 한다. report 가 `구간과 겹치는 다른 세션 N개 미포함` 으로 알린다.
4. **겹침 세션 수는 근사치** — `find -mmin` 으로 구간 동안 수정된 같은 프로젝트 디렉토리의 다른 `*.jsonl` 수를 센다. (a) 분 단위 올림이라 **최대 1분 오차**, (b) **macOS(BSD find)에서만 실측 검증**(GNU find 의 `-mmin` 경계는 미검증), (c) 같은 프로젝트의 **무관한 작업 세션도 센다**, (d) 레코드에 세션 id 목록이 없어 이미 `--session` 으로 포함한 세션도 다시 셀 수 있다 — 다중 세션이면 report 의 "미포함 N개" 는 과대일 수 있다.
5. **transcript 는 비공개 내부 형식** — 필드명·경로가 바뀌면 대개 `unmeasured`(`no-messages-in-window`·`transcript-not-found`)로 떨어진다. 그러나 **탐지하지 못하는 변경**도 있다: 같은 필드명에 의미만 바뀌면(예: `usage` 가 누적값이 되거나 id 재사용 규칙이 바뀜) max-per-id 가 조용히 틀린 숫자를 내고, `subagents/` 배치만 바뀌면 main 은 측정된 채 서브에이전트 행만 조용히 빠진다.
6. **측정·미측정 세션이 섞이면 report 는 측정된 행만 보인다** — 한 FID 에 `unmeasured` 세션이 함께 있어도 표·TOTAL 에 표시되지 않는다. 전부 미측정일 때만 `측정 안 됨 (<사유>)` 이 나온다. 의심되면 `tokens.jsonl` 원본의 `status` 를 직접 본다.
7. **symlink 는 건너뛴다(NFR-3)** — FID 생략 report 는 symlink 인 `tokens.jsonl` 을 **표시 없이** 건너뛰고, FID 지정 report 는 `측정 안 됨 (기록 없음)` 으로 표시한다(실제로는 파일이 있다). 기록 모드도 경로상 symlink 를 만나면 무기록 종료한다.
8. **구간은 fid-start 기준** — FID 마다 독립 구간이라, 같은 세션에서 두 FID 가 동시에 진행되면 겹친 구간의 토큰이 **양쪽 FID 에 이중 계상**된다. FID 간 합산은 하지 않는다.
9. **`--transcript` 단독 사용은 현재 env 세션으로 귀속된다** — `--session` 을 함께 주지 않으면 레코드 `session` 은 `CLAUDE_CODE_SESSION_ID` 가 되고(env 가 비었을 때만 transcript 파일명), upsert 가 **현재 세션의 기존 행을 그 transcript 의 숫자로 덮어쓸 수 있다**. 다른 세션의 transcript 를 지정할 때는 `--session <uuid>` 를 같이 쓴다.
10. **손상된 `tokens.jsonl` 은 갱신이 건너뛰어진다** — 파일에 JSON 객체로 읽히지 않는 줄(깨진 줄·객체 아닌 값)이 하나라도 있으면 이후 기록은 사유 레코드 없이 **무음으로 갱신되지 않고**, report 는 그 FID 를 `읽을 수 없음 (tokens.jsonl 손상 — 파일 삭제 후 재측정)` 으로 표시한다. 복구는 그 파일을 지우고 다시 측정하는 것이다(관측 기록일 뿐이라 다른 판정에 영향은 없다).

## stage-timing.sh — FID 간 단계별 소요 집계 (관측 전용)

- `stage-timing.sh` — `.specops/session-progress.md` 의 인접 행 차이를 **FID 간 단계별**로 집계한다(읽기 전용). 합계 내림차순 표: 합계·비중·n·중앙값·p90·max(분). FID 단위 소요는 `show-fid-status.sh`(`/status`)가 이미 낸다 — 이 스크립트는 "시간이 어느 단계에 가는가"를 본다.
- 옵션: `--since YYYYMMDD`(도착 행 날짜 기준 — 마지막 행이 그 이전인 FID 는 대상에서 빼고 수를 표시) · `--gap-cap-min N`(기본 720 — 넘는 구간은 통계에서 빼되 건수·합계를 별도 줄로 표시) · `--min-n N`(n 이 N 미만인 단계를 표에서 가리고 가린 단계 수를 표시) · `--split`(아래) · `--by-agent`(아래 — `--split` 내포) · `--transcript-dir DIR`(`--split`·`--by-agent` 전용 — transcript 디렉토리 직접 지정). `SPECOPS_ROOT` 로 원장 위치를 바꾼다.
- rc: 0 = 집계 성공(구간 0건이어도 그 사실을 표시) · 2 = 원장 부재·읽기 불가·잘못된 인자(`--transcript-dir` 를 `--split` 없이 주거나 디렉토리가 아닌 경우 포함).
- ⚠️ **옵션 없이는 경과 시간이지 작업량이 아니다** — 사람 응답 대기·서브에이전트 대기가 포함된다. 분 해상도(0 = 1분 미만), 도착 행의 단계에 귀속, FID 첫 행은 기준이 없어 집계에서 빠지며(건수 표시), DST·타임존 변경 경계는 ±60분 오차가 날 수 있다. FID 섹션 안의 형식 불일치 행(커맨드가 `/` 로 시작하지 않는 등)과 시각 범위 밖 행(`24:00` 등)은 집계에서 빼고 건수만 표시한다. 같은 FID 가 여러 섹션에 흩어져 있으면 한 시간선으로 합친다.
- **`--split`** — Claude Code transcript 의 **구조 필드**(`system/turn_duration`·사용자 레코드의 `origin.kind`)로 각 구간을 쪼갠다: `작업`(에이전트 턴 진행 시간 — 모델 추론 + 도구 실행 포함, 권한 승인·질문 응답 대기가 섞일 수 있다) · `사람`(턴 종료 뒤 사람 프롬프트까지) · `백그라운드`(턴 종료 뒤 알림·서브에이전트가 재개할 때까지) · `기타`(나머지 — 미분류 포함). 겹침이 없는 행은 열 합 = 합계이고, 겹침 구간이 있는 행은 끝에 `[겹침 N]` 이 붙는다. transcript 는 `CLAUDE_CONFIG_DIR`(기본 `~/.claude`) 아래 `projects/` 에서 원장 루트 실경로의 비영숫자를 `-` 로 바꾼 이름의 디렉토리(직속 `*.jsonl`, 원장 최초 날짜 이후 수정된 것만)를 읽는다 — 비ASCII 경로는 바이트 단위·문자 단위 치환을 차례로 시도하고, 어긋나면 `--transcript-dir` 로 지정한다. 링크 worktree 의 세션은 `git worktree list` 경로 전부를 같은 규칙으로 인코딩한 디렉토리의 합집합으로 읽는다(머리의 `transcript 디렉토리 N개 읽음` 으로 확인 · `--transcript-dir` 는 반복 지정 가능). 그 밖의 cwd 에서 연 세션은 읽히지 않는다. **프롬프트·응답 본문은 읽지도 저장하지도 않는다** — `scripts/_internal/transcript-turns.sh` 가 허용 필드만 추출하고 카나리 테스트로 잠근다. transcript 가 없거나 jq 가 없으면 오류가 아니라 표 끝에 `측정 불가(--split): 사유` 한 줄이다.
- `--split` 해석 주의: transcript 는 개발자 로컬 자산이라 원장보다 기간이 짧다 — 푸터의 `transcript 시간 범위`·`범위 밖 구간`을 확인하고 `--since` 로 범위 안만 보라(범위 밖 구간은 전부 `기타`). 게이트(질문) 대기와 일반 대화 지연은 구분하지 않는다(본문 비열람 계약). 같은 세션의 누적 turn_duration(알림으로 재개된 턴이 앞 턴 시작부터 누적된 값)은 직전 턴 끝·직전 트리거(턴은 그 턴을 연 트리거보다 앞서 시작할 수 없다)로 잘라내며, 남는 겹침은 동시 세션 가능성이다(`겹침 N구간`, 해당 구간의 기타는 0). 세션 사이는 짝짓지 않는다. `origin.kind`·`turn_duration` 은 Claude Code 내부 포맷이라 미인식 값은 `미분류`로 보인다. 첨부(이미지 등)가 있는 프롬프트는 트리거로 잡히지 않아 그 대기는 `기타` 로 간다. 푸터의 `직전 turn_duration 없이 시작한 트리거` 는 세션 시작 외에 대기열에 쌓인 프롬프트·명령 전개 등을 포함할 수 있다(본문 비열람이라 구분하지 않는다). jq 1.6 이상(`localtime`)이 필요하고, `--transcript-dir` 는 절대 경로를 권장한다. 읽을 수 없는 세션 파일이 하나라도 있으면 `측정 불가` 가 되고, 기록 중인 세션 파일(끝 개행 없음)은 마지막 줄이 유실될 수 있으며, 비정상적으로 큰 `durationMs`(7일 초과)는 0 으로 본다.

- **`--by-agent`** — `--split` 을 내포하고 그 표 뒤에 **서브에이전트 역할별 소요 표**를 더한다(합계·비중·n·중앙값·p90·max, 분). 서브에이전트 transcript(`세션폴더/subagents/agent-ID.jsonl` + `agent-ID.meta.json`)의 **구조 필드만** 읽는다 — jsonl 의 `timestamp`, meta 의 `agentType`·`toolUseId`(`scripts/_internal/agent-spans.sh` 가 읽고 카나리 테스트로 잠근다 — `description`·본문·도구 입출력은 읽지 않는다). 역할은 meta 의 `agentType` 이다(단 `toolUseId` 가 있고 이름 형식이 맞을 때만). 이름 지정 에이전트(깊이 0, `toolUseId` 없음 — meta 가 없거나 형식이 맞지 않는 경우도 같은 줄에 든다)는 `미분류(이름 지정)` 줄에 건수·합계만 보이고 이름은 출력하지 않는다. 이 줄이 전체의 큰 몫일 수 있으니(실측 약 32%) 역할 표만 보고 결론내지 말라. 기준일(`--since`, 없으면 원장 최초 날짜) 이후에 시작한 서브에이전트만 센다. 서브에이전트나 transcript 가 없거나 jq 가 없으면 오류가 아니라 표 끝에 `측정 불가(--by-agent): 사유` 한 줄이다.
- `--by-agent` 해석 주의: 이 표는 서브에이전트가 **살아 있던 시간**이지 부모가 기다린 시간이 아니다 — 병렬·부모 작업 중 실행 때문에 역할 wall 합은 `백그라운드` 열 합과 같지 않다(푸터에 두 합을 나란히 보인다). 권한 승인 대기·긴 도구 실행이 섞이며, 내부 간격이 10분을 넘는 건수·합은 제외하지 않고 푸터에 보인다(방치 상한 초과 간격만 뺀다). `--min-n` 은 역할 표에 적용하지 않는다. 표시는 초 단위로 계산한 뒤 분으로 반올림한다. 서브에이전트 transcript 위치·meta 키는 Claude Code 내부 포맷이고, 서브에이전트가 부른 서브에이전트(깊이 2 이상)는 읽지 않고, meta 는 한 줄 JSON 이라는 전제라 여러 줄로 풀어 쓴 meta 는 역할을 잃어 미분류가 된다. 시각은 로컬 벽시계 초로 바꿔 계산하므로 DST 전환을 걸친 에이전트의 wall·간격은 ±60분 오차가 날 수 있다. 실측 약 5초(483개·273MB — 본 표 계산과 병렬로 읽는다).

```bash
bash scripts/stage-timing.sh --since 20260901
bash scripts/stage-timing.sh --split --since 20260902      # transcript 범위 안만 — 어느 단계에서 사람·백그라운드 대기가 큰가
bash scripts/stage-timing.sh --by-agent --since 20260902   # 어느 역할(구현자·리뷰어·플랜 리뷰어)의 서브에이전트 시간이 큰가
bash scripts/stage-timing.sh --split --transcript-dir A --transcript-dir B   # 지정은 반복 가능 · 지정 없으면 git worktree 전부의 projects 디렉토리 합집합
```

## review-cost.sh — plan-reviewer 비용·재dispatch 집계 (관측 전용)

- `review-cost.sh` — `.specops/*/dispatch-log.md` 의 plan-reviewer 구조화 행으로 **FID 별 라운드 수·첫/끝 판정·Critical/Important 건수**를 집계한다(읽기 전용). 요약은 라운드 분포·평균·**첫 라운드 FAIL 비율**·마지막 판정 PASS·Critical/Important 합·첫 라운드 FAIL 의 심각도 분해·predispatch 도입 전후·월별 줄이고, 원장(`session-progress.md`)의 FID 별 plan 창과 서브에이전트 transcript(`scripts/_internal/agent-spans.sh` 재사용)를 조인해 plan-reviewer **wall(분)** 을 FID 에 귀속한 뒤 비용 상위 FID 표를 낸다. "plan 리뷰 비용의 어디를 줄이면 되는가"를 숫자로 보는 도구다 — 개선안을 제안하지는 않는다.
- 옵션: `--since YYYYMMDD`(FID 이름의 날짜 접두가 그 이상인 FID 만 — 요약·표·전후 비교·월별 모두) · `--predispatch-date YYYYMMDD`(전/후 비교 기준일, 기본 `20260809` = `check-plan-predispatch.sh` 도입일) · `--top N`(표 행 수, 기본 10) · `--transcript-dir DIR`(서브에이전트 transcript 위치 직접 지정 — 기본은 `stage-timing.sh` 와 같은 규칙으로 `CLAUDE_CONFIG_DIR/projects/` 아래 원장 루트 실경로의 비영숫자를 `-` 로 바꾼 디렉토리). 잘못된 값·알 수 없는 옵션·`$SPECOPS` 부재는 rc 2. 라운드 집계는 `jq`·transcript 없이도 나오고, wall 만 `wall 측정 불가(사유)` 한 줄이 된다.
- 라운드 정의: dispatch-log 의 `|` 로 시작하고 **단계 필드가 `plan-reviewer`** 인 행 중 판정의 첫 단어(`*` 제거 후)가 `PASS`·`FAIL` 인 것(`FAIL→PASS` 는 FAIL). `ABORT`·`PROCEED`·`DEFERRED`·`—` 등은 `기타 행` 으로 세고 분모에서 뺀다. FID 안 순서는 `#` 오름차순이고 숫자가 아닌 번호는 숫자 행 뒤에 파일 순서로 둔다. `Critical N`·`Important N` 은 FAIL 행 비고(7번째 칸부터 마지막 칸까지를 `|` 로 이은 문자열 — 비고 안의 `|` 를 넘어 읽는다)에서 키워드 뒤 6자 안의 첫 숫자만 읽는다. 시각 있는 서브에이전트가 하나도 없으면 wall 자리는 `wall 측정 불가(시각 있는 서브에이전트 0개)` 한 줄이다.
- ⚠️ **해석 주의**: 첫 라운드 FAIL 비율은 표본 n 과 함께 읽어야 한다(월별 표본이 작다). predispatch 도입 전후·월별 비교는 **FID 이름 날짜 접두 기준의 관찰이지 인과가 아니다** — 표본이 작고 플랜 복잡도·검토 방식이 함께 변했다. wall 은 원장 plan 창(`/clarify`(없으면 `/specify`)의 가장 이른 시각 ~ `/plan` 의 가장 늦은 시각, 앞 60초·뒤 120초 여유)과 서브에이전트 시작 시각의 **조인**이다 — 후보 FID 가 정확히 1개일 때만 귀속하고(여럿이면 `모호`, 없으면 `미귀속` 으로 건수를 보인다) 동시에 진행된 FID 가 겹치거나 창 밖에서 돈 재dispatch 는 귀속되지 않는다. wall 은 에이전트가 살아 있던 시간이라 권한 승인 대기가 섞일 수 있다. 표의 `라운드 0` 행은 서브에이전트는 돌았지만 dispatch-log 에 구조화 행이 없는 FID 다(행 기록 누락).
- 한계: 사유 **클래스**(예: predispatch 3클래스)는 비고가 자유 서술이라 구조로 얻지 못한다 — 숫자 `Critical`·`Important` 만 읽고 둘 다 못 읽은 FAIL 행은 건수로 보인다(키워드 뒤 6자 안의 첫 숫자를 건수로 읽으므로 `Important: AC-2 누락` 처럼 숫자가 건수가 아닌 비고는 오독한다 — 읽힌 행 수는 맞아도 값은 검증되지 않는다). 라운드는 구현자가 쓴 dispatch-log 행 수라 누락·산문 행은 세지 못한다. 서브에이전트 transcript 는 개발자 로컬 자산이라 기간이 dispatch-log 보다 짧다(그 앞 FID 는 wall 이 없다). 서브에이전트 파일은 원장 최초 행 날짜 이후에 수정된 것만 모집단이 된다(`stage-timing.sh` 와 같은 규약 — 그 이전에 끝난 파일은 보지 않는다). Phase B/C 리뷰어·외부 critic·토큰은 범위 밖이다. 서브에이전트 transcript 위치·meta 키는 Claude Code 내부 포맷이다.
- 프라이버시: 리뷰어 보고서 파일·프롬프트·서브에이전트·transcript 본문·dispatch-log 비고의 비숫자 텍스트는 출력도 저장도 하지 않는다 — 읽는 것은 dispatch-log 구조화 행(번호·단계·판정·비고에서 숫자)·원장의 FID 섹션 행·`agent-spans.sh` 출력(숫자·역할)이고, 서브에이전트 meta 는 plan-reviewer 후보를 고르려고 `agentType` 일치 여부만 본다(`grep -l` — 내용 출력 없음). 임시 파일에는 FID 이름·정수·역할 이름만 쓰고 종료 시 지우며 카나리 테스트가 이를 잠근다.

```bash
bash scripts/review-cost.sh
bash scripts/review-cost.sh --since 20260901 --top 5
bash scripts/review-cost.sh --predispatch-date 20260901      # 전/후 비교 기준일 바꾸기
```

## guard-map.sh — 가드 생존 맵 (관측 전용)

- `guard-map.sh` — 이 플러그인의 가드를 repo 파일에서 **기계 추출**(하드코딩 목록 없음)하고 가드마다 어떤 **생존 증거**가 있고 없는지 한 표로 보인다(읽기 전용). 인벤토리 3종: `hooks/rules.jsonl` 의 규칙(id·`enabled`) · `scripts/_internal/check-*.sh`(가드명 = `check-` 와 `.sh` 를 뗀 이름) · `validate-structure.sh` 의 `emit <label>` 라벨(실행하지 않고 정적 추출). 출력은 머리 `인벤토리: rules N · check M · structure L` → 가드별 표 → 요약 → `증거 약함` 목록 → 한계 푸터 순이다.
- 증거 칸(해당 없으면 `-`): **T**(테스트) — check 는 `scripts/tests/**/test-<가드명>.sh` 명명 일치 `있음(명명)`, 아니면 어떤 테스트든 스크립트 이름을 언급하면 `있음(참조)`, rule·structure 는 id·라벨 언급 · **M**(변이 대상, check 만) — `scripts/tests/mutation-targets.conf` 의 대상 열에 스크립트 경로가 있음 `있음(conf)` · **P**(호출 배선, check 만) — propagation 원장에 **호출처 파일**을 가리키는 edge 의 `must_match` 가 가드명(`check-X`) 또는 그 스크립트 경로를 할당받은 `*_SH` 변수명을 담음 `있음(이름)`·`있음(변수 X_SH)`. 호출처가 `.md`(skill·command)면 근거에 `산문` 이 붙는다 `있음(이름·산문)`(증거 약함 판정에서 P 있음으로 센다). 가드 스크립트 자기 자신만 잠그는 edge 는 `자기잠금` 으로 따로 표기하고 있음으로 세지 않는다. 테스트·README 를 가리키는 edge 와 `*_SH` 가 아닌 일반 변수(`CHK` 등)는 호출처 배선으로 세지 않는다.
- 칸 값은 `있음(근거)` · `없음` · `미측정(사유)` · `-`(해당 없음) 이고 비활성 규칙은 `비활성` 이다. 입력 파일 부재·파싱 불가·`jq` 부재는 해당 소스에 의존하는 칸을 `미측정(사유)` 로 표시한다 — 측정 못 한 것을 `없음` 으로 위장하지 않는다(P 는 호출처가 코드·산문 어디에도 없으면 `미측정(호출처 코드 없음)`). 요약은 종류별 가드 수와 증거 종류별 `있음`·`없음`·`미측정`·`-` 수(칸마다 합 = 가드 수)이고, `증거 약함` 은 **적용 증거가 2종 이상인 가드(check)** 중 **판정 가능한 칸**(미측정 제외)에서 `있음` 이 1종 이하인 가드다(판정 가능한 칸이 하나도 없으면 제외). 적용 증거가 T 1종뿐인 rule·structure 라벨은 표·요약에 T 개수(있음/없음)만 보이고 약함 판정에서 **제외**한다 — 요약에 `판정 제외(적용 증거 1종)` 로 표기한다(1종뿐이면 `있음` ≤ 1 이 늘 참이라 진짜 구멍인 check 를 묻기 때문). `--weak-only` 의 항목 수 = 요약의 증거 약함 수다.
- 옵션: `--weak-only`(약함 목록만) · `--repo <root>`(대상 repo root — 기본은 스크립트 위치 기준 repo). 종료 코드 0 정상(약함이 있어도 0 — 관측 도구) · 2 사용 오류(알 수 없는 옵션·`--repo` 값 부재 또는 빈 값·root 가 디렉터리 아님). 출력은 사람용 정렬 텍스트 표뿐이다 — `--json`·`--tsv` 는 지원하지 않는다(기계 소비는 후속 게이트 FID 에서). 임시 파일은 `mktemp -d` 아래에만 만들고 종료 시 지우며 시각·세션 변수·실 `~/.claude` 에 의존하지 않는다. `source` 하면 `gm::` 함수만 정의한다.
- ⚠️ **해석 주의**: **증거 있음 ≠ 가드 작동**이다. 테스트 `참조` 는 가드를 단언한다는 뜻이 아니고(이름이 한 줄 나오기만 해도 참조다 — 라벨처럼 흔한 단어는 더 느슨하다), propagation edge 는 **문자열 존재**만 보고 `must_match` 를 단어 단위로만 읽는다 — 교대(`|`)·glob·부정 정규식은 오탐·미탐이 날 수 있다. 이 도구의 가치는 증거가 **없는** 가드(변이 대상 0개 · 호출 배선 부재 · 테스트 없음)를 드러내는 쪽에 있다.
- 한계: 명명 규약 밖 게이트(`release-ready.sh`·`reconcile-check.sh`·`batch-state.sh --gate` 등)와 훅 deny 분기는 인벤토리에 없다(출력 푸터에도 고지). 변이 점수는 직접 재계산하지 않는다 — M 은 conf **등록 여부**만 본다(점수는 `mutation-score.sh`). 호출처 판정은 호출처 후보 파일(`hooks/`·`scripts/`(테스트·README 제외)·`.githooks/`·`skills/`·`commands/`·`agents/`·`templates/` 의 `.sh`·`.md`·`.json`)에 가드 이름이 나오는지로 하므로 주석 속 언급도 호출처로 읽는다. 가드 강도(차단/경고)는 판정하지 않는다.

```bash
bash scripts/guard-map.sh                       # 표 + 요약 + 증거 약함 + 한계
bash scripts/guard-map.sh --weak-only           # 증거 약함 목록만
bash scripts/guard-map.sh --repo /path/to/repo  # 다른 repo 에 겨눈다
```

## reuse-metrics.sh — 재사용·복제 관측 (읽기 전용 · 비차단)

FID 하나의 변경 규모·복제·재사용 선언 이행을 재서 `.specops/<FID>/reuse-metrics.json` 에 남긴다. 차단하거나 경고하지 않는다 — 재사용을 강화하는 작업이 효과가 있었는지 볼 기준선이다.

```bash
bash scripts/reuse-metrics.sh measure <FID>   # 한 FID 측정(재측정 시 덮어씀)
bash scripts/reuse-metrics.sh measure <FID> --range <base>..<head>   # 머지된 FID 를 기록된 분기점·머리로 다시 잰다(작업 트리 무관 · jscpd 제외)
bash scripts/reuse-metrics.sh report          # .specops/*/reuse-metrics.json 을 FID 별 표로
```

`run-verification.sh` 가 `VERIFY: PASS` 를 낸 뒤 `measure` 를 한 번 부른다. 측정이 실패하거나 스크립트가 없어도 verify 의 판정 줄과 종료 코드는 그대로다.

| 항목 | 무엇을 재나 |
|---|---|
| `size` | 분기점부터 작업 트리까지 추가·삭제 줄 수 — 구현·테스트·문서로 나눈다(문서 분류는 `file-class.sh`). 삭제된 파일의 줄도 센다. lockfile·`*.min.js` 같은 생성물은 빼고 건수만 남긴다 |
| `dup` | 추가된 코드에서 연속 6줄(앞뒤 공백 제거 후 완전 일치)이 ① 추가분 안에서 반복된 줄 수 ② 분기점 시점의 저장소에 이미 있던 줄 수. ② 는 같은 변경에서 지운 줄과 같은 창을 뺀다 — 파일 이름 변경·블록 이동·들여쓰기 변경은 복제로 세지 않는다 |
| `jscpd` | `jscpd` 가 PATH 에 있을 때만 그 수치를 **추가로** 기록한다(파일 전체·토큰 기반이라 `dup` 과 서로 비교하지 않는다) |
| `reuse` | `재사용 foundation` 선언에 적힌 경로·심볼이 추가된 코드에 나오는 건수 / 선언 건수. 식별자 경계에서만 맞춘다(`index` 는 `indexOf` 에 맞지 않는다) |

- 복제는 import 줄(한 줄·괄호/중괄호 여러 줄)을 빼고, 구현·테스트를 나눠 센다 — `dup.impl`·`dup.test`·`dup.import_lines_excluded`(schema 2).
- 재사용 이행은 구현(비테스트) 추가 줄만 본다. 백틱 없는 선언은 본문의 슬래시 경로로, 파이썬 점 표기와 `from 부모 import 잎` 도 이행으로 센다. 분기점에 이미 있던 선언 모듈 파일 자체를 이번 변경이 고쳤으면 이행이다(테스트 파일·이번에 새로 만든 파일 제외).
- schema 1 기록은 `report` 에 `(v1)` 로 나온다 — 수치 정의가 달라 새 기록과 비교하지 않는다(필요하면 재측정).

각 항목은 `status` 를 갖는다: `measured` · `not_measured`(사유) · `not_applicable`(사유). 값은 `measured` 일 때만 숫자이고 나머지는 `null` 이다 — 재지 못한 것을 0 으로 쓰지 않는다. `report` 는 이를 `미측정(사유)`·`해당없음` 으로 보인다.

- 인자 없이 머지된 FID 를 재면 범위가 비어 `not_measured` 로 덮는다 — 그때는 `--range`. 잘못된 범위·인자는 rc 2 이고 기록은 그대로다.

분기점은 `.specops/<FID>/review-base.sha` 가 있으면 그 커밋(`/start-all` batch 는 한 브랜치에 FR 을 여럿 쌓는다), 없으면 기본 브랜치와의 merge-base 다.

환경변수: `SPECOPS_REUSE_DUP_WINDOW`(연속 줄 수) · `SPECOPS_REUSE_MAX_FILES`(변경된 비문서 파일 수 상한 — 넘으면 `dup`·`jscpd`·`reuse` 미측정) · `SPECOPS_REUSE_MAX_TREE_FILES`·`SPECOPS_REUSE_MAX_TREE_BYTES`(분기점 트리 파일 수·바이트 합 상한, 기본 1만 개·200MB — 넘으면 분기점 코드를 읽지 않고 ② 만 미측정) · `SPECOPS_REUSE_MAX_CORPUS_LINES`(대조 코퍼스 줄 수 상한 — 넘으면 ② 만 미측정).

한계: 자체 방식은 이름만 바꾼 복제를 못 잡는다. `reuse` 는 선언한 이름이 코드에 나오는지만 보는 근사치다(간접 사용은 못 본다). 추적하지 않는 새 파일은 대상이 아니다(`git add` 한 것부터 센다). 분기점과 HEAD 가 같고 작업 트리 변경도 없으면(기본 브랜치 위·합친 뒤) 0 이 아니라 `not_measured` 다 — 그때 다시 재면 앞선 기록을 덮어쓴다. 라이선스 머리말 같은 상투 블록은 6줄 이상 같으면 복제로 센다(import 줄은 뺀다 — 앞머리만 보는 근사치). verify 가 부를 때는 측정을 30초에서 끊는다 — 끊기면 기록을 남기지 않고 판정 줄·종료 코드에는 영향이 없다(직접 `measure` 를 부르면 시간 상한 없이 위 상한들이 일의 양을 묶는다). 따옴표가 든 경로처럼 추가된 줄을 다 읽지 못하면(읽은 줄 수가 변경 규모와 다르면) `dup`·`reuse` 를 `not_measured` 로 남긴다 — 깨진 심볼릭 링크는 영향이 없다(코드 경로로 세지 않는다). 문서에서 지운 줄과 같은 블록을 코드에 복사하면 이동으로 보아 기존 코드 복제에서 빠진다. 임계값 판정은 하지 않는다. `jscpd` 연동은 리포트 형식(`statistics.total.lines`·`duplicatedLines`)을 스텁으로만 검증했다 — 실 도구로는 미검증.

## check-constitution-rules.sh — 헌법 「구조 규칙」 표 읽기 (읽기 전용 · 비차단)

프로젝트 헌법(`.specops/memory/constitution.md`)의 「구조 규칙」 절에 적은 표를 읽어 형식을 판정하고, 규칙 행을 기계가 쓰기 좋은 줄로 내준다. 부르는 곳은 `scripts/dag/emit-context.sh`(`--list` 출력을 태스크별 dispatch 컨텍스트의 `## 8. 구조 규칙` 절로 실어 구현자와 코드 리뷰어에게 전달) · `check-rule-commands.sh` · `check-plan-boundary.sh`(아래) 다. 표가 없으면 절도 없고, 표가 틀려도 **아무것도 막지 않는다**: 컨텍스트의 그 절과 `emit-context: WARN` 줄에 "싣지 못했다"와 사유가 남는다. `명령` 판정 규칙의 명령은 검증 때 `check-rule-commands.sh` 가 실행한다(경고 전용).

```bash
bash scripts/_internal/check-constitution-rules.sh            # 형식 판정 (기본: .specops/memory/constitution.md)
bash scripts/_internal/check-constitution-rules.sh --list     # 규칙마다 `ID|규칙|적용 경로|판정|판정 명령` 한 줄
bash scripts/_internal/check-constitution-rules.sh <헌법 파일>
```

표는 두 표지 `<!-- structure-rules:start -->` · `<!-- structure-rules:end -->` 사이에 둔다(`templates/constitution.md` 에 골격이 있다).

| 칸 | 규칙 |
|---|---|
| ID | `S-숫자`, 중복 없음 |
| 규칙 · 적용 경로 | 비어 있으면 안 된다(꺾쇠 자리표시자도 빈 것으로 본다) |
| 판정 | `리뷰` 또는 `명령` |
| 판정 명령 | 판정이 `명령`이면 필수. 없으면 `-` |

표지는 줄 전체가 표지여야 하고, 표지 사이에는 빈 줄과 표 행만 둔다. 첫 행은 머리 행(`| ID | 규칙 | 적용 경로 | 판정 | 판정 명령 |` — 칸 이름·순서 그대로), 둘째 행은 구분 행이다. 그 뒤로 ID 칸이 `(예시)` 로 시작하는 행은 규칙으로 세지 않는다. 표지 없이 머리 행만 있으면 위반이다(표지 낱말을 틀리게 적은 경우). 어긋나는 줄은 조용히 버리지 않고 위반으로 알린다.

| 종료 코드 | 뜻 |
|---|---|
| 0 | 형식 통과(규칙 N건) 또는 해당 없음 — 헌법 없음 · 절 없음 · 규칙 0건 |
| 1 | 형식 위반 — 위반마다 `파일:줄: 사유` 를 표준 오류로. `--list` 는 아무 규칙도 내지 않는다 |
| 2 | 판정 불가 — 사용 오류 · 닿을 수 없거나 읽을 수 없는 파일(들어갈 수 없는 상위 디렉터리 · 끊어진 심볼릭 링크 · 샌드박스 같은 정책으로 접근이 거부된 파일 포함) · NUL 바이트가 든 파일 · 내부 도구 실패. "헌법 없음"·"규칙 0건"으로 답하지 않는다 |

한계: 칸 안에 세로줄 문자를 쓸 수 없다(칸 수 위반으로 잡힌다 — 명령에 파이프가 필요하면 스크립트 파일로 감싼다). 규칙 내용의 옳고 그름, 적용 경로가 실제로 있는지, 판정 명령이 실행되는지는 보지 않는다. `--list` 는 칸을 적힌 그대로(백틱 포함) 낸다. UTF-8 이 아닌 헌법은 지원하지 않는다.

## check-plan-boundary.sh — plan 의 「경계 약속」 대조 (읽기 전용 · 경고 전용)

plan.md 의 `### 경계 약속`(소유 · 범위 밖 · 허용 의존 · 다시 검토할 조건)을 파일 구조 목록과 헌법 구조 규칙에 대 본다. `planning-ko` 가 사전검사 뒤 실행해 `.specops/<FID>/plan-boundary.txt` 로 남기고 plan-reviewer 에 넘긴다 — 리뷰어는 `## 경계 대조` 에서 Minor 로만 적고, **아무것도 막지 않는다**.

```bash
bash scripts/_internal/check-plan-boundary.sh <FID>                         # .specops/<FID>/plan.md
bash scripts/_internal/check-plan-boundary.sh --plan <경로> [--constitution <경로>]
```

출력 첫 줄은 `PLAN-BOUNDARY: OK|WARN|SKIP`(plan.md 없음 = SKIP · 끊어진 링크나 들어갈 수 없는 디렉터리라 확인할 수 없으면 `[판정 불가]`), 그 아래 `[경고]`(절 없음·칸 비었음·자리표시자) · `[소유 밖] <경로>`(테스트·삭제 경로도 예외 없음) · `RULE <ID> (<적용 경로>) — <규칙> — 닿는 파일: …` · `[판정 불가] …`. 종료 코드: 0 = 판정 완료(경고 포함)·SKIP · 1 = 사용 오류 · 2 = 판정 불가 항목 있음(파일 목록을 찾지 못함 · 규칙 표를 읽지 못함 — "없음"으로 쓰지 않는다).

경로는 파일 구조 절(제목에 `파일` 이 든 `##` 절)의 목록 항목 줄(`-`·`*`·`1.` — 바로 백틱이거나 `생성:`·`T1:` 같은 짧은 이름표 뒤, 그 줄의 경로꼴 백틱 전부)과 표 첫 칸의 백틱에서만 뽑는다 — 산문·코드 블록·표 둘째 칸·코드 조각 백틱은 보지 않는다. 굵은 이름표(`**Create:**`) 뒤의 경로와, 셸·glob 글자(`< > | * ? $ "`)가 들거나 `-`·`=` 로 시작하는 토큰(`tests/*.sh` 등)은 뽑지 않는다(조용히 빠진다). 구조 규칙 표는 `check-constitution-rules.sh --list` 로만 읽는다.

한계: import 방향은 보지 않는다(검증 때 `check-import-direction.sh` 가 허용 의존 화살표와 대조한다 — 아래 절). 경로 비교는 폴더 경계 기준 접두 비교다(소유 `src` 는 `src/a.sh` 를 포함하고 `src2/` 는 포함하지 않는다). 실측(20261015): 하류 plan 57건 중 55건에서 경로를 뽑았고 2건(파일 구조 절 없음)은 판정 불가.

## check-import-direction.sh — 허용 의존 화살표 대조 · import 순환 (읽기 전용 · 경고 전용)

plan.md `### 경계 약속` 의 `허용 의존` 칸을 화살표 형식(`` `src/domain/` → 없음 · `src/app/` → `src/domain/` ``)으로 적으면, 이 FID 가 바꾼 파일(분기점…작업 트리 + 추적 안 한 새 파일 — 분기점은 `reuse-metrics.sh` 와 같다)의 실제 import 와 대조한다. `run-verification.sh` 가 30초 상한으로 불러 evidence.md `### import-direction` 에 남기고, 위반이면 경고만 낸다(VERIFY 판정·종료 코드 불변).

```bash
bash scripts/_internal/check-import-direction.sh <FID>
bash scripts/_internal/check-import-direction.sh --plan <경로> --files <목록 파일> [--root <디렉터리>]
```

출력 첫 줄은 `IMPORT-DIRECTION: OK|WARN|SKIP|판정 불가`, 그 아래 `[역방향] <파일>:<줄> → <대상>` · `[순환] a → b → a` · `[미해석] N건`(별칭·동적 import 를 풀지 못함 — 지킴으로 치지 않는다) · `[범위 상한]`. 종료 코드 0 = 판정함(위반이 있어도 0)·SKIP · 1 = 사용 오류 · 2 = 판정 불가(python3 없음 · 분기점 없음 · 읽기 실패).

판정은 **선언한 경로끼리만** 한다 — 왼쪽 경로 안의 파일이 다른 왼쪽 경로를 허용 없이 부르면 역방향이다. 어느 왼쪽 경로에도 속하지 않는 내부 파일이나 외부 패키지를 부르는 것은 보지 않는다(오탐을 만들지 않으려는 선택 — 누락은 생긴다). 화살표가 하나도 없으면(자유 문장·자리표시자) 방향은 SKIP 이고 순환만 본다. 순환은 바꾼 파일에서 최상위 import 를 따라가(노드 400개 상한) 바꾼 파일이 낀 것만 낸다 — 들여쓴 import·TS `import type`·동적 import 는 순환 간선에서 뺀다(방향 판정에는 넣는다).

언어: Python(`import` · `from … import` · 상대 import — 패키지 루트는 저장소 루트·`src/`·선언 경로에서 모듈 첫 마디가 나오는 위치 앞) · JS/TS(`import … from` · `export … from` · `import '…'` · `require('…')` · `import('…')` · 상대 경로 · 루트 `tsconfig.json`/`jsconfig.json` 의 `paths`·`baseUrl`). 정규식 추출이다 — 오탐을 막으려고 주석·문자열·템플릿 리터럴 안의 import 꼴은 읽지 않고, 여러 줄 괄호 import 를 이어 읽고, 표준 라이브러리 첫 마디는 외부로 읽고, `__init__.py` 없는 폴더는 모듈로 치지 않고, tsconfig 에 `baseUrl` 이 없으면 bare 이름을 저장소 파일로 풀지 않는다. 절 찾기는 `check-plan-boundary.sh` 와 같다(펜스 안 무시 · 제목 수준 2~4). 판정기 자체의 오류·시간 초과는 evidence 에 `판정 불가` 줄로 남는다. 차단으로 올리는 것은 실사용 오탐 0 을 확인한 뒤 별도 변경으로 한다(구조 규칙 판정 명령과 같은 절차).
