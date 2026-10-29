---
name: decomposing-ko
description: planning-ko 완료 후 호출 — plan.md를 2~5분 단위 TDD 5스텝 태스크로 분해. 모든 must AC가 최소 1 태스크에 매핑되도록 보장. bash 테스트 컨벤션 (templates/test-conventions-bash.md) 준수 점검 포함
layer: 2
reference_upstream: obra/superpowers@v5.0.7 skills/writing-plans/SKILL.md
  - github/spec-kit commands/tasks.md (specops-ko 경유)
  - specops-ko commands/tasks.md
  - specops-ko templates/tasks.md
  - obra/superpowers@v5.0.7 skills/writing-plans/SKILL.md (bite-sized task 단위)
specops_version: 2.18.0
used_by: planning-ko (chain 진입), implementing-ko (chain 출구), /start-all (BATCH-PHASE1-DONE halt 분기)
---

# Engine 스킬 — 태스크 분해 (decomposing)

`plan.md`의 카테고리·순서를 **2~5분 단위 TDD 바이트사이즈 태스크**로 분해한다. 모든 `must` AC가 **최소 1 태스크**에 매핑되도록 보장.

<HARD-GATE>
**플레이스홀더("TBD", "TODO", "similar to N", 코드 없는 스텝)**가 남은 채로 `devfsd:implementing-ko` 호출 금지. 커버리지 누락 AC가 있는 채로도 호출 금지.

**bash 테스트 파일 규약**: 생성되는 `test-*.sh` 에 shebang (`#!/usr/bin/env bash`) 또는 실행권한 (exec-bit, `chmod +x`) 이 누락된 채로 `devfsd:implementing-ko` 호출 금지. 단, 파일 첫 두 줄 내에 `# library-only` 주석 마커가 존재하면 library-only 전용 (sourced only) 으로 간주하여 exec-bit 검증 skip. shebang 은 library-only 포함 모든 bash 테스트 파일에 필수. 상세: `templates/test-conventions-bash.md`.

**Python 테스트 파일 규약**: 생성되는 `test_*.py` 에 exec-bit 및 shebang 불필요. pytest가 직접 실행. 파일명은 `test_<subject>.py` (underscore, hyphen 아님). 상세: `templates/test-conventions-python.md`.

**v0.4a 신규 — DAG 섹션 의무**: `tasks.md` 끝에 `## 의존 그래프` 섹션이 **YAML fenced block** 으로 작성되지 않은 채로 `devfsd:implementing-ko` 호출 금지. YAML 파싱 실패 (`bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dag/parse-dag.sh` 의 `dag::find_independent_batch` 가 stderr WARN 발화) 시도 차단. fallback 운영은 implementing-ko 의 sequential 분기 책임 (advisor 협의 13:00 — v0.4a 는 decomposing-ko 자동 생성은 100% YAML 정합 보장).

**foundation 재사용 게이트**: spec.md §유형이 `foundation` 이 **아니고** `.specops/memory/foundation-manifest.md` 가 존재하면, 각 task 에 다음 중 하나가 **반드시** 기재되어야 한다 — 누락 시 `devfsd:implementing-ko` 호출 금지:
- `**재사용 foundation**: <foundation-manifest.md 의 모듈명>` — foundation 모듈을 재사용하는 경우
- `**미재사용 근거**: <이유>` — 재사용하지 않는 경우 (예: 해당 task 가 foundation 범위 외)

> **판정 SoT = `scripts/_internal/check-foundation-reuse.sh`** (20260806 기계화). Step 10b 의 `emit-context.sh` 가 **구현 전에** 자동 호출하므로 누락 시 dispatch 자체가 열리지 않는다(디스크 작성 0 — 다른 검증과 동일 원자성). 종전엔 산문뿐이라 모델이 선언을 빠뜨리면 그대로 통과했다 — 공통부를 만들어 놓고 아무도 안 쓰는 상태가 조용히 지나간다. 빈 값·`<모듈명>` 류 placeholder 는 **미기재로 판정**한다(형식만 갖춘 통과 차단).

**최소 태스크 게이트**: 각 task 에 rung 순서 질문 — 존재 필요(YAGNI)? · 기존 헬퍼·유틸 재사용? · stdlib? · 네이티브 기능? · 설치된 의존성? 과잉 task 제거 후 매핑 유지. 검증·에러·보안 절차 task 는 제거 대상 아님.
</HARD-GATE>

## trivial / §lite 단축 분기 (plan.md 부재)

다음 중 하나이고 `plan.md` 가 **부재**하면 (clarify·plan SKIP — specifying trivial 또는 `/start-lite`·`/maintain-lite`) — 아래 경량 절차로 대체하고 정상 체크리스트를 건너뛴다:

- `**§유형**: trivial`
- 또는 `**§lite**: true` (§유형이 `유지보수`여도 §lite면 본 분기)

1. **입력 확인** — `.specops/<FID>/spec.md` + `acceptance-criteria.md` 존재 (plan.md·clarifications.md 부재는 **정상** — SKIP 됨). 위 조건 재확인 (아니면 정상 체크리스트로 복귀).
2. **단일 태스크 합성** — spec.md 설계 섹션 + AC(`must`, 유지보수면 AC-R-*) 를 근거로 **TDD 5스텝 단일 태스크** 를 `templates/tasks.md` 구조로 작성. 모든 `must` AC 가 이 1 태스크에 매핑. `review_mode: end-loaded` **필수**. 파일 구조는 spec.md §참조·설계 섹션에서 확정 (plan.md §파일구조 대체).
3. **teeth 불변 준수** — TDD 5스텝·플레이스홀더 스캔·테스트 컨벤션·DAG 섹션(단일 노드 YAML)은 **정상과 동일하게 필수**. 축약되는 것은 clarify·plan 뿐.
4. **DAG** — leaf 1개 YAML (`depends_on: []`). Step 10 자체 검증·Step 10b `emit-context.sh` 정상 수행.
5. 이후 `## 다음 skill` (implementing-ko) 로 정상 진행.

> **오판 안전망**: trivial/§lite 는 사용자가 명시(슬래시·승인)한 것이나, decompose 가 spec+AC 를 단일 태스크로 못 담을 만큼 복잡하면 (must AC ≥ 4 또는 **구현 파일 ≥ 2 — 테스트 파일 제외**) — "규모가 lite/trivial 을 넘습니다. 정식 plan 을 거칠까요?" 확인 후 정상 경로 복귀 가능. teeth 유지가 우선.
> **`§일괄`** 도 묻지 않고 정상 경로(clarify → plan)에 올리고(유지보수면 `current-state.md`·`impact-analysis.md` 를 analyzing 풀 체크리스트(Step 1~6) 기준으로 이 자리에서 보강 — `analyzing-ko` 를 다시 호출하지 않는다) `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dev-decision.sh add <FID> order "lite/trivial → 정상 경로 승격(규모 초과)" "<must AC 수·구현 파일 수>"` 를 남긴다 — clarifying 이 승인 묶음을 한 번 더 받는다(`../specifying-ko/once-approval.md` §3).
> (기준 보정 근거 — 20260716 trivial dogfood 발견 #1: 구 기준 "AC ≥ 3 또는 파일 ≥ 2" 는 TDD 최소 구성에 **항상 걸리는 false-trigger** 였다. 실질 복잡도 신호는 비테스트 구현 파일 2개↑ 또는 AC 4건↑.)

## 체크리스트

1. **입력 아티팩트 확인** — `.specops/<FID>/plan.md` + `.specops/<FID>/acceptance-criteria.md`. 없으면 planning-ko 선행 요청 후 **중단**. **예외**: 위 `## trivial / §lite 단축 분기` 조건이면 그 경량 절차를 따르고 본 체크리스트는 건너뛴다
1a. **DAG 힌트 추출 (v0.4b 신규)** — spec.md §2 포함 섹션에서 의존 구조 사전 파악:
   - `(독립 — 병렬 구현 가능)` 표기 항목 2개 이상 → DAG leaf 후보 목록 초기화
   - `(의존: X)` 표기 항목 → 해당 태스크의 `depends_on` 초기값으로 설정
   - 표기 없으면 → 기능 설명에서 독립성 추론 (공유 파일·상태 없으면 독립으로 간주)
   - 결과를 step 10 DAG 의존 그래프에 반영
2. **AC 커버리지 매핑** — 각 `must` AC → 최소 1 태스크 할당. 커버리지 표 작성
3. **파일 구조 확정** — plan.md §파일 구조의 Create/Modify/Delete 목록 고정
4. **TDD 5스텝 작성** — `devfsd:tdd-ko` 준수:
   - Step 1 RED: 실패 테스트 (실제 코드)
   - Step 2 검증: FAIL 확인
   - Step 3 GREEN: 최소 구현 (실제 코드)
   - Step 4 검증: PASS 확인
   - Step 5 COMMIT: `git add` + 한국어 커밋 메시지
5. **문지기 체크 (원칙 2)** — 파괴적 작업 태스크는 **별도 분리** + `⚠️ 사용자 승인 필요` 표기 + 확인 스텝 삽입
6. **플레이스홀더 스캔** — TBD·TODO·"similar to N" 발견 시 **구체 코드로 대체**
7. **테스트 컨벤션 점검** — 테스트 생성 태스크가 있으면 언어별 컨벤션 준수 확인:
   - bash (`test-*.sh`): `templates/test-conventions-bash.md` 준수. exec-bit·shebang 누락 시 `<HARD-GATE>` 발동
   - Python (`test_*.py`): `templates/test-conventions-python.md` 준수. exec-bit·shebang 불필요. `test_<subject>.py` 명명 위반 시 `<HARD-GATE>` 발동
8. **타입 일관성 점검** — 후속 태스크의 시그니처가 이전 태스크와 일치
9. **출력** — `templates/tasks.md` 구조로 `.specops/<FID>/tasks.md` 생성
10. **DAG 의존 그래프 작성 (v0.4a 신규, 의무)** — `tasks.md` 끝에 `## 의존 그래프` 섹션 추가:
    - **Mermaid block** (사람용 시각화): `graph TD` + 노드·edge
    - **YAML fenced block** (기계용 단일 소스 진실): 루트에 `review_mode: end-loaded`(기본) + `tasks:` 배열 — 각 task에 `id`·`depends_on`·`inputs`·`outputs`·`ac` 필드
      - **`id` 는 숫자 전용**(`T1`~`Tn`) — T1a·task-3 같은 접미사·비숫자 id 는 `emit-context`(`check-task-ids.sh`)가 구현 전에 거부한다(FID 날짜 20261001 이후). 커밋 메시지의 `Task: T숫자` 와 정확히 일치해야 R-1 receipt 탈출구가 열린다
    - **`review_mode`**: 기본 `end-loaded`(implementing이 A만 wave → FID 말미 B·C 각 1회). 고위험 FID만 `per-task` opt-in(태스크마다 A→B→C). §batch(`/start-all`)도 **FID end-loaded** — FR마다 implementing이 B/C까지 수행. 필드 부재 시 implementing은 end-loaded로 취급.
    - 형식 표준: `templates/tasks.md` 끝 placeholder + `scripts/tests/dag/fixtures/tasks-md/05-diamond.md` 예시 참조
    - **자체 검증**: 작성 직후 다음 명령으로 YAML 정합 + leaf 식별 확인
      ```bash
      source "${CLAUDE_PLUGIN_ROOT}"/scripts/dag/parse-dag.sh
      yaml=$(dag::extract_yaml .specops/<FID>/tasks.md)
      dag::list_leaves "$yaml"            # 빈 출력 시 YAML 결함 → 재작성
      dag::find_independent_batch "$yaml" # 병렬 후보 출력 (참고용)
      ```
    - YAML 파싱 실패 또는 빈 leaf 시 → 본 스킬 재작성 의무 (HARD-GATE 차단)
    - **Step 10b. emit-context.sh 자동 산출 (Wave 2 U2 — 의무)** — Step 10 의 DAG 자체 검증 통과 후:
      ```bash
      bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dag/emit-context.sh <FID>
      ```
      - tasks.md YAML 의 모든 task 에 대해 `.specops/<FID>/dispatch/<task-id>-context.md` 5섹션 자동 산출
      - fail-fast atomic — 1건이라도 검증 실패 (test_command 미기재 / ac 배열 빈 값 / AC.md 매칭 AC-id 부재 / inputs·outputs 키 부재) 시 exit 1 + stderr 출력 + 부분 잔류 0
      - 성공 시 stdout `EMIT: N files`
      - 실패 시 본 스킬 재진입 의무 (HARD GATE — stderr 사유 해소 후 재호출. tasks.md 외에 intent·AC 형식·스택·기준선·회귀 AC·FID 크기·task id 도 막는다)
      - implementing-ko 는 본 산출물의 `.specops/<FID>/dispatch/<task-id>-context.md` 를 leaf dispatch 직전에 §5 worktree 라인만 sed 갱신 (컨텍스트 수동 작성 단계 단순화)
10c. **위험 프로파일 limited-live 기록 (P1)** — tasks.md 확정 후:
    ```bash
    bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/risk-profile.sh compute <FID>
    ```
    - `.specops/<FID>/risk-profile.json`에 `lite|standard|strict` 기록 (`mode=live`)
    - `effective=lite` → `reductions_allowed: ["batch-review-skip"]` (그 외는 `[]`)
    - **allowlist 외 축소 금지** — TDD·verify·Phase B/C·receipt는 프로파일과 무관하게 유지. `batch-review-skip`만 batch 오케스트레이터가 requesting/receiving에 적용 가능. **`review_mode: end-loaded`는 Phase B/C 생략이 아님**(시점만 FID 말미로 통합) — allowlist와 무관하게 기본 동작
    - 사용자 상향만 허용: `--floor standard|strict` 또는 `SPECOPS_RISK_PROFILE_FLOOR`
    - **★ rc=3 = `LITE-STRICT-GUARD` (HARD GATE — 20260806)**: `§lite` FID 인데 프로파일이 `strict` 면 compute 가 rc=3 을 낸다. lite 는 clarify·plan 을 **이미 건너뛴** 상태라 그대로 진행하면 고위험 변경이 설계 검토 없이 구현된다. **implementing-ko 로 진행 금지** — `devfsd:clarifying-ko` → `devfsd:planning-ko` 를 수행해 승격한 뒤 본 스킬 재진입(정상 체크리스트 경로). `plan.md` 가 생기면 가드는 자동 해제된다. 사용자 주권 우회는 env + 사유 병기(`SPECOPS_LITE_STRICT_OVERRIDE=1 SPECOPS_LITE_STRICT_REASON='<사유>'`)뿐 — 모델이 파일을 써서 열 수 없다.
11. **session-progress append** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /tasks 완료 "tasks.md (N 태스크)"` 호출. `devfsd:implementing-ko` 다음 단계 안내
12. **전환** — `devfsd:implementing-ko` 호출

## 골격 기계 생성 (선택 — 있으면 쓴다)

Step 9(출력) 에서 `tasks.md` 를 처음부터 타이핑하기 전에, `plan.md` 가 있으면 골격 생성을 **먼저 시도**한다:

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dag/plan-to-tasks.sh <FID> > "${TMPDIR:-/tmp}/tasks-skeleton-<FID>.md"
```

- **rc=0** — `${TMPDIR:-/tmp}/tasks-skeleton-<FID>.md` 가 `## Task N` 블록(`**파일**` 블록·Step 본문·코드펜스 포함)을 담고 있다. 그 위에 **생성기가 만들지 않는 4섹션만** 직접 작성한다 — `## AC → Task 매핑` · `## 파괴적 작업` · `## 진행 상태` · `## 의존 그래프`(YAML). **Task 본문을 다시 타이핑하지 않는다.**
- **rc≠0** — 생성기가 파싱을 거부했다(산문형 plan · Step 0개 Task · plan 부재). stderr 사유를 1줄 고지하고 **기존 전량 작성 경로로 진행**한다. chain 을 막지 않는다(graceful **fallback**).

> 근거(실측 20260809): `tasks.md` 의 substantive 줄 중 `plan.md` 와 **완전 동일한 줄**이 44~63% 다(3 FID). 생성기는 그 도출 가능한 구간만 옮긴다.

> 생성기는 `## 의존 그래프` YAML 을 **의도적으로 만들지 않는다**. `depends_on` 은 plan.md 에서 도출할 수 없고, `[]` 로 채우면 `dag::find_independent_batch` 가 전 태스크를 절대 leaf 로 보아 **거짓 병렬**이 열린다(실측: 3-task all-leaf → `T1 T2 T3` 무경고 반환). 이 섹션은 항상 사람·모델이 쓴다.

> per-task `ac` 배열도 생성기가 채우지 않는다 — 이것은 **안전하다**. 비운 채로 두면 `emit-context.sh` 가 `must AC 미커버` 로 dispatch 를 차단하므로 **관문이 강제**한다. 반대로 `depends_on` 은 그런 관문이 없어서(무경고 통과) 생성기가 손대지 않는 쪽을 택했다. 두 필드의 처리가 다른 이유가 이것이다.

## 태스크 크기 규약

**각 태스크 = 2~5분 작업 단위**

- 5 스텝 (RED 작성·FAIL 검증·GREEN 구현·PASS 검증·COMMIT)
- 각 스텝에 **실제 코드·명령·예상 출력** 포함
- 단일 파일 또는 밀접한 2~3 파일로 한정
- 스텝 간 의존 없음 (스텝 N+1이 스텝 N 산출 없이도 읽고 이해 가능)

**태스크가 5분을 초과한다면**: 더 작은 태스크로 분할

## FID 크기 규약 (완성율 레버)

per-태스크 크기(2~5분)와 **별개로**, **FID 전체 태스크 수**가 완성율을 좌우한다 — dogfood 실측: test2 3-태스크 FID 는 **6/6 완주**, test1 10-태스크 FID 는 **24h+ 정체**(태스크 각각은 정상이었으나 FID 전체가 7.5시간 마라톤 → 세션 경계에서 중간 이탈). **큰 FID = 긴 세션 = 이탈 노출 ↑.**

**권장 FID 스코프 = 태스크 ≤6.**

**분해 결과 태스크가 7개 이상이면** — 분해 출력 끝에 소프트 신호 1줄을 남긴다:

```
⚠️ FID-SIZE: <N> 태스크 (권장 ≤6) — 다중 세션에 걸칠 수 있음. 중간 이탈 시 재개는 /status (reconcile) 로.
```

그리고 아래 중 하나를 택한다:

- **선호 (예방)** — 다음 기능부터 `specifying-ko` 단계에서 **수직 슬라이스**(각자 독립 shippable 단위)로 FID 를 작게 스코프한다. 큰 기능 1 FID 보다 작은 기능 여러 FID 가 완주율이 높다.
- **현 FID (완화)** — (6개 초과 9개 이하, 또는 아래 무인·batch 예외) `implementing-ko` 는 태스크별로 `dispatch-log` 를 갱신하므로(session-progress 는 끝에 1줄), 중간 이탈해도 `/status` reconcile 이 그 dispatch-log·커밋을 읽어 정확한 재개점을 잡는다. 즉 큰 FID 의 세션 경계 생존은 reconcile(#220)에 의존한다.

**7개 이상 분할 계획행 의무** — tasks.md 끝에 줄 선두 `**분할 계획**: <이번 FID 범위·후속 FID 후보>` 1행. 미기재 시 `emit-context.sh`(`check-fid-size.sh`)가 거부한다.

**10개 이상 차단 (대화형)** — FID 분할 없이 구현 진입 불가(계획행이 있어도 `check-fid-size.sh` 가 거부). 수직 슬라이스로 FID 를 나눈 뒤 본 스킬 재진입. **예외** — 사용자 채널이 없는 `§auto`·`/start-all` batch(FR 단위 FID)는 계획행 + `FID-SIZE` 경고만으로 진행한다(`foundation` 은 층별 FID 로 나눈다).

## 테스트 컨벤션 (bash)

plan.md 가 bash 테스트 파일 생성 태스크를 포함하는 경우, 다음 4 항목 규약을 준수하도록 태스크를 설계한다. 상세는 `templates/test-conventions-bash.md` 참조.

| 항목 | 규칙 요약 | 강도 |
|---|---|---|
| 위치 | `scripts/tests/[feature]/test-*.sh` · 전역은 `scripts/tests/test-*.sh` | 내부 예시 |
| 명명 | `test-<subject>.sh` — subject 는 대응 프로덕션 파일 basename (확장자 제거) | 내부 예시 |
| 실행권한 | `chmod +x` (755) | Universal 강제 |
| 헤더 L1 | `#!/usr/bin/env bash` shebang | Universal 강제 |
| 헤더 L2~ | `set -u`, `PASS=0; FAIL=0`, `PLUGIN=$(cd ... && pwd)`, `T<N>.<letter>` TEST ID | 내부 예시 |

**강도 해석**:
- **Universal 강제** — 위반 시 `<HARD-GATE>` 발동. `devfsd:implementing-ko` 호출 차단
- **내부 예시** — specops-ko 패턴. downstream 프로젝트 기존 패턴이 있으면 그것 우선
- **단일 예외** — 실행권한 강제는 파일 L2 에 `# library-only` 마커 선언 시 skip (library-only 파일). shebang 은 예외 없음

상세 규약·예시 코드블록·회귀 금지 체크리스트: `templates/test-conventions-bash.md`.

### Python 테스트 파일 (`test_*.py`)

plan.md 가 Python 테스트 파일 생성 태스크를 포함하는 경우, 다음 규약을 준수하도록 태스크를 설계한다. 상세는 `templates/test-conventions-python.md` 참조.

| 항목 | 규칙 | 강도 |
|---|---|---|
| 위치 | downstream 프로젝트 기존 test 디렉토리 우선, 없으면 `tests/` | 권장 |
| 명명 | `test_<subject>.py` — underscore | Universal 강제 |
| exec-bit | 불필요 | Universal 규약 |
| 헤더 | shebang 불필요 | Universal 규약 |

**강도 해석**:
- **Universal 강제** — `test_*.py` 명명 위반 시 `<HARD-GATE>` 발동
- **Universal 규약** — exec-bit·shebang은 불필요 (bash와 다름)
- **내부 예시** — downstream 프로젝트 기존 패턴이 있으면 그것 우선

상세: `templates/test-conventions-python.md`.

## AC 커버리지 표

```markdown
## AC → Task 매핑

| AC | must/should | Task(s) |
|---|---|---|
| AC-1 | must | Task 1, Task 3 |
| AC-2 | must | Task 2 |
| AC-3 | must | Task 4 |
| AC-4 | should | Task 5 |
| AC-5 | must | Task 6 |

**must AC 커버리지**: 5/5 (100%)
```

**미매핑 must AC가 1건이라도 있으면 → chain 중단, planning-ko 재호출**

## 태스크 포맷

`templates/tasks.md` 그대로 사용. 각 태스크는:

````markdown
### Task N: <컴포넌트명>

**AC 매핑**: AC-1, AC-3
**파일**:
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

- [ ] **Step 1: RED — 실패 테스트 작성**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: FAIL 검증**

실행: `pytest tests/path/test.py::test_name -v`
예상: `FAIL — function not defined`

- [ ] **Step 3: GREEN — 최소 구현**

```python
def function(input):
    return expected
```

- [ ] **Step 4: PASS 검증**

실행: `pytest tests/path/test.py::test_name -v`
예상: `PASS`

- [ ] **Step 5: COMMIT**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: <기능명> 추가"
```
````

## 마이그레이션 태스크 분해 (DB 스키마 변경 시)

**트리거**: `data-model.md` 스키마 변경(테이블·컬럼·인덱스 신설/변경) **또는** `plan.md` 에 DDL 표면(`CREATE/ALTER TABLE`·ORM 스키마·마이그레이션 파일 생성)이 있으면 — **둘 중 하나라도** 마이그레이션을 분해한다. (★ `data-model.md` 가 미부트스트랩인 무인 batch(`/start-all-auto`) DB 기능에서도 plan DDL 만으로 발동 — 파괴적 마이그레이션이 reverse/test 없이 진행되는 구멍 차단.)

마이그레이션을 **forward+reverse 쌍**으로 분해한다 (단순 "비가역 격리"로 끝내지 말 것):

1. **forward(up) 태스크** — DDL 적용 (`CREATE/ALTER`). `data-model.md` §6 도구(Prisma Migrate/Alembic/Flyway 등)·명명 규약(`<timestamp>_<desc>`) 준수
2. **reverse(down) 태스크** — 롤백 DDL. 가역 가능하면 작성, **데이터 손실 동반(DROP 류)이면** down 으로도 복구 불가임을 명시 + 아래 "파괴적 작업 격리" + `analyzing-ko §2 expand-contract` 적용
3. **마이그레이션 테스트 태스크** — up→down→up **멱등·역가역성** + 제약(NOT NULL/CHECK/UNIQUE) 위반 경로 + 인덱스 존재 검증
4. data-model.md 의 ERD·엔티티표가 forward 와 일치하도록 갱신 (Step 5.6 design-first 산출과 정합)

DAG: down·테스트는 up 에 `depends_on`. 파괴적 forward 는 아래 격리 규칙으로 `irreversible: true`.

## repo 밖 흔적 표지 (`external:`)

되돌릴 수는 있어도 **repo 밖에 흔적을 남기는** 태스크(실 DB 쓰기·적재, 과금·호출 한도가 있는 외부 API 호출, 배포, 원격 리소스 생성)는 DAG YAML 노드에 `external: "<무엇을 어디에 — 되돌리는 방법>"` 을 붙인다. `implementing-ko` 가 구현 시작 전에 이 표지를 모아 **한 번에** 승인받는다(`dev-autonomy.md` §1) — 표지가 없으면 태스크마다 실행 직전에 멈춘다. `irreversible: true` 와 섞지 않는다: 그 필드는 되돌릴 수 없는 작업 전용이고 위험도 판정이 strict 신호로 읽는다.

## 파괴적 작업 격리

데이터 삭제·프로덕션 설정 변경·마이그레이션 등 **되돌릴 수 없는 작업**은:

1. **별도 태스크**로 분리 (다른 태스크와 합치지 말 것)
2. 태스크 헤더에 `⚠️ 사용자 승인 필요` 표기
3. **Step 0 삽입**: "사용자에게 파괴적 변경 승인 요청. 승인 없으면 태스크 중단"
4. **DAG YAML 노드에 `irreversible: true` 필드 추가** — implementing-ko(부모)가 pre-dispatch에서 이 필드를 읽어 분기 처리:
   - `§batch` → 진행 (오케스트레이터 책임)
   - `§auto` → mini HARD GATE (발생 위치에서 정지): `"AUTO-HARD-GATE: <task-id> 비가역 작업 — 확인 필요 [y/n]"`
   - 단일 모드 → 기존 Step 0 확인

```markdown
### Task 7 ⚠️ 사용자 승인 필요: `.cache/` 디렉토리 정리

- [ ] **Step 0: 승인 요청**

사용자에게 다음 메시지 전달:
> "Task 7은 `.cache/` 디렉토리 전체를 삭제합니다. 진행하시겠습니까? [y/n]"

`y`가 아니면 **중단**.

> **참고 (§auto 모드)**: 서브에이전트는 사용자 채널이 없으므로 Step 0을 직접 실행할 수 없다. `irreversible: true` 필드가 있는 task는 implementing-ko 부모가 pre-dispatch 단계에서 mini HARD GATE를 발동한다. 이 Step 0은 단일 모드 전용이자 PR 게이트 가정 다이제스트의 참조 소스다.

- [ ] **Step 1: RED** ...
```

**DAG YAML `irreversible` 필드 예시**:
```yaml
tasks:
  - id: T7
    irreversible: true   # ← 파괴적/덮어쓰기 작업 표기
    depends_on: [T6]
    outputs: [.cache/]
    ac: [AC-8]
```

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 각 태스크에 AC 매핑 명시. "이 태스크가 어느 요구사항을 충족하는가" |
| 2 **문지기** | 파괴적 태스크는 별도 격리 + 승인 스텝. 합치지 말 것 |
| 3 **깊이** | 플레이스홀더 남기지 말 것. "similar to N"도 구체화 |
| 4 **주권 존중** | 파괴적 작업 승인은 사용자에게 직접 질문. 대신 결정 금지 |
| 5 **한계 고백** | 불확실한 태스크에 "추정 — 구현 중 확인 필요" 태그 |

## 안티패턴

- **태스크 크기 초과** — 1 태스크 = 2~5분. 더 크면 분할
- **TDD 5스텝 생략** — 특히 RED 검증 스텝 누락
- **플레이스홀더 포함** — TBD·TODO·구현 생략 금지
- **미매핑 must AC 방치** — 커버리지 100% 전 chain 진행 금지
- **파괴적 작업을 일반 태스크에 섞음** — 반드시 격리
- **Task N 참조만으로 코드 생략** — 엔지니어가 순서와 무관하게 읽을 수 있으니 코드 반복

## 참조

- `skills/planning-ko/SKILL.md` — 선행 스킬
- `skills/tdd-ko/SKILL.md` — TDD 5스텝 규약
- `templates/tasks.md` — 출력 포맷
- upstream 근거: Spec-Kit `commands/tasks.md` (specops-ko 경유) + bite-sized 태스크 단위 규약
- specops-ko 선례: `commands/tasks.md`, `templates/tasks.md`
- `skills/structured-artifacts-ko/SKILL.md` — .specops/<FID>/ 아티팩트 경로 규약
- `skills/karpathy-ko/SKILL.md` — Think·Simplicity·Surgical·Goal 4원칙 (cross-cutting)

## Handoff 기록 (다음 skill 진입 직전 필수)

`implementing-ko` 호출 직전 `.specops/<FID>/handoffs/decomposing.md` 작성 (structured-artifacts-ko 규약 4필드: Decided/Rejected/Risks/Remaining).

## 다음 skill

tasks.md 저장 + AC 커버리지 100% + 플레이스홀더 0 확인 + handoff.md 기록 후:

**3-way 분기 확인**:

```bash
if grep -qE '^\*\*§batch\*\*:' .specops/<FID>/spec.md; then
  echo "BATCH"
elif grep -qE '^\*\*§auto\*\*:[[:space:]]*true' .specops/<FID>/spec.md; then
  echo "AUTO"
else
  echo "SINGLE"
fi
```

- **§batch (batch 분기)** → `BATCH-PHASE1-DONE: <FID>` 출력 후 **halt** (implementing-ko 미호출). `/start-all` 오케스트레이터가 queue.md를 PLAN_DONE으로 갱신하고 다음 FR을 처리한다.
- **§auto (auto 분기)** → implementing-ko 직행. §auto 라벨이 propagate되어 각 단계에서 가역 게이트 자동 통과가 계속됨.
- **단일 분기** → 기존 동작. **호출 직전 한 줄 선언**(R-3 투명성 — 20260718 test2 회고: implementing-ko 만 선언 없이 자동 호출돼 R-3 warn 12건 누적. 자동 체인이라도 전환을 1줄 명시):

```
구현 단계로 진행 — devfsd:implementing-ko 를 호출합니다.
Skill: devfsd:implementing-ko
```

implementing-ko가 각 태스크마다 fresh 서브에이전트를 dispatch한다. 본 decomposing-ko는 **batch halt 또는 implementing-ko 이외의 다음 스킬을 호출하지 않는다**.
