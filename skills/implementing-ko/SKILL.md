---
name: implementing-ko
description: "본 세션에서 구현 플랜을 태스크별로 실행할 때 사용 — 태스크별 fresh 구현(A) 후 FID 단위 스펙·코드 리뷰(B·C) 각 1회(end-loaded 기본). 레거시 per-task 리뷰는 review_mode: per-task"
layer: 2
reference_upstream: obra/superpowers@v5.0.7 skills/subagent-driven-development/SKILL.md
specops_version: 2.18.0
used_by: decomposing-ko (chain 진입), verifying-evidence-ko (chain 출구 · end-loaded/per-task), /start-all (FR별 implementing)
---

# Engine 스킬 — 서브에이전트 주도 구현 (implementing)

플랜을 태스크별 **fresh 서브에이전트**로 구현(A)한 뒤, FID 전체 기준으로 **스펙 준수 리뷰(B) 1회 → 코드 품질 리뷰(C) 1회**를 수행한다 (**end-loaded**, 기본).

**왜 서브에이전트**: 전문 에이전트에게 **격리된 컨텍스트**로 태스크를 위임. 지시와 컨텍스트를 **정확히** 조립해 집중·성공을 보장. 서브에이전트는 **당신 세션의 컨텍스트·히스토리를 절대 상속하지 않는다** — 필요한 것만 당신이 구성해 넘긴다. 이로써 당신의 컨텍스트도 코디네이션 용도로 보존된다.

**핵심 원칙**: 태스크별 fresh 구현(A) + FID 단위 2단계 리뷰(B→C) = **고품질 + 리뷰 비용 O(1)**. Generator↔Evaluator 분리는 유지한다(리뷰 생략 아님 — **시점만** 태스크 루프 뒤로 모음).

### 리뷰 모드 선택 (tasks.md YAML)

```bash
# tasks.md ## 의존 그래프 YAML 루트
grep -E '^review_mode:' .specops/<FID>/tasks.md
```

| `review_mode` | 동작 |
|---|---|
| **`end-loaded`** (기본, 필드 부재 시 동일) | wave = **A만** → 전부 완료 후 **B 1회 + C 1회** → verify |
| **`per-task`** (레거시) | 태스크마다 A→B→C (구 기본). 고위험 FID에서만 명시 opt-in |

`risk-profile`의 「Phase B/C 축소 금지」는 **리뷰 생략**을 금지한 것이다. end-loaded는 B·C를 **수행**하므로 allowlist 위반이 아니다.

**§lite 불변** (`spec.md`에 `**§lite**: true` — `/start-lite`·`/maintain-lite`): clarify·plan만 축약된 FID다. **Phase B(`spec-reviewer-ko`)·Phase C(`code-reviewer-ko`) 생략 금지**. end-loaded B/C 각 1회 필수. 화면·IF 설계 계약을 §6으로 소비(해당 시).

## 개발 구간 무질문

구현 시작부터 PR 게이트 직전까지 사용자에게 **묻지 않고** 진행한다 — "계속할까요?" 류 재확인 금지, 순서·리뷰 지적 처리는 기본값으로 정하고 `dev-decision.sh` 로 기록해 끝에 한 번 보고한다. wave loop **직전에** 같은 디렉터리 `dev-autonomy.md` 를 Read 한다 (알려진 외부 작업의 일괄 사전 승인 · 계약 안이면 고치고 밖이면 넘기는 기준 · 그래도 멈추는 예외).

## 설계 계약 준수 (design-first 후진 teeth)

사전 설계 산출물이 존재하면 구현은 이를 **계약**으로 준수한다 (specifying-ko 의 정방향 design-first 가 구현까지 이어지도록 — 화면·인터페이스 대칭):

- `screens/{name}.md`·`.html` — 화면 기능의 **UI 계약** (Step 5.5 산출)
- `.specops/memory/api-spec.md`·`api-spec-consumer.md`·`data-model.md` — **인터페이스(제공·소비)/스키마 계약** (Step 5.6 design-first · Phase 8g 산출)

`emit-context.sh`(decomposing Step 10b)가 설계 산출물(`api-spec.md`·`api-spec-consumer.md`·`data-model.md`·`screens/`) 존재 시 dispatch 컨텍스트의 **§6 설계 계약** 섹션에 경로를 **자동 포함**한다(Wave 2 배선 — 부재 시 §6 생략 graceful). 구현자는 §6 계약을 준수하고 임의로 벗어나지 않으며(계약을 바꿔야만 구현되면 BLOCKED 로 올린다 — `dev-autonomy.md` §2), `verifying-evidence-ko` 의 "memory 설계 동기화 점검"(역방향 안전망)이 사후 검증한다. (정방향 계약(§6 자동 emit) + 역방향 net 으로 design-first 의 전·후진 teeth 를 모두 확보)

**최소 구현**: leaf 구현 전 rung 순서 질문 — 존재 필요(YAGNI)? · 기존 헬퍼·유틸 재사용? · stdlib? · 네이티브 기능? · 설치된 의존성? · 한 줄 가능? · 아니면 최소 코드. 검증·에러 처리·보안·접근성·AC 테스트는 절감 제외. scope 이관 시 재사용 우선.

## 사용 시점

```
구현 플랜 있음?
    ↓ yes
태스크 대체로 독립적?
    ↓ yes
본 세션에서 진행?
    ↓ yes
→ implementing-ko (본 스킬)
   단일 세션 내 독립 leaf 2+ → DAG-AWARE PARALLEL 분기 (v0.4a부터 지원)
   단일 leaf 또는 chain → SEQUENTIAL 분기

↓ no (다른 세션 병렬) → 별도 실행 흐름 (현재 미지원 — 본 세션 내 직렬 처리)
```

태스크가 밀접하게 결합돼 있으면 → decomposing-ko 복귀해 재분해.

## 프로세스 (다단계 wave — dag::find_ready 기반 · end-loaded 기본)

```
플랜 + tasks.md 1회 읽기 → review_mode 판정 (부재=end-loaded) → TodoWrite 생성
    ↓
DAG 초기화 (bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dag/parse-dag.sh)
    yaml=$(dag::extract_yaml .specops/<FID>/tasks.md)
    done=""   ← 완료 task id 집합 (공백 구분 문자열, 초기 빈)
    ↓
[WAVE LOOP — Phase A only when end-loaded] ──────────────────
ready=$(dag::find_ready "$yaml" $done)
    ↓
ready 비어 있음? → 전부 구현 완료 → END-LOADED REVIEW (또는 per-task면 이미 B/C 끝)
    ↓
ready 내 disjoint batch 선별 (dag::find_independent_batch 로직):
    batch ≥ 2 leaf + outputs disjoint?
    ├─ yes (병렬 분기) → DAG-AWARE PARALLEL ─────────────┐
    └─ no (단일 ready 또는 chain) → SEQUENTIAL          │
                                                          │
SEQUENTIAL 분기 (1 태스크씩):                            │
  ready 중 1개 선택:                                      │
  작업 디렉터리: 별도 worktree 를 만들지 않는다 — §5 라인을      │
  repo root 절대경로로 sed 갱신(validate-context 가 절대경로 허용) │
    ┌─ 구현자 dispatch (implementer-ko)  ← Phase A        │
    │     ↓                                                │
    │  [end-loaded] B/C 여기서 하지 않음                   │
    │  [per-task] Phase B → Phase C (레거시)               │
    │     ↓                                                │
    │  receipt + 커밋 (아래 공통 규칙)                     │
    └─ TodoWrite 완료 → done에 task-id 추가              │
    ↓                                                      │
→ WAVE LOOP 재진입                                        │
                                                          │
DAG-AWARE PARALLEL 분기: ←────────────────────────────────┘
  각 batch leaf: context 확인 · validate-context · worktree (`.worktrees/<FID>-<task-id>/`)
  dispatching-parallel-agents-ko → 각 leaf implementer-ko (A only)
  결과 수집 (NEEDS_CONTEXT 재dispatch / DONE)
  **Wave 2**: emit-context.sh 산출물 사용. 부재 시 decomposing-ko 재진입 HARD GATE.
    ↓
  [per-task만] Phase B(병렬) → Phase C(병렬)
  [end-loaded] B/C 스킵 — 머지·receipt·커밋만
    ↓
  부모 머지 (R11): output count 적은 leaf 먼저 · git apply --index · 부모 commit
    - **커밋 직전 receipt (필수)**: `record-task-receipt.sh <FID> <task-id>`
      end-loaded: **Phase A DONE + 태스크 테스트 통과 후** (B/C 전). per-task: Phase C PASS 후.
      한 번에 남기기: `record-task-done.sh <FID> <task-id> [요약]` — receipt · dispatch-log 구현 행(`IMPL_DONE`) · session-progress 줄을 함께 쓴다(receipt 실패면 아무것도 쓰지 않는다). 이것을 쓰면 그 태스크의 receipt·Phase A 행·진행 줄을 따로 쓰지 않는다.
    - **커밋 분리**: `git add`와 `git commit` 별도 Bash (compound 금지)
    - **위험 프로파일**: effective를 dispatch-log 1줄. B/C **생략**·TDD/verify/receipt 면제 금지.
      end-loaded의 B/C 지연은 생략이 아님.
    ↓
  done에 batch task-id 추가 → WAVE LOOP 재진입
    ─────────────────────────────────────────────────────────
    ↓ ready 비어 있음 (전부 A 완료)
[END-LOADED REVIEW] (review_mode≠per-task 일 때 필수)
  최초 B·C 쌍: **한 메시지에서 동시 dispatch** → 「최초 B/C 쌍 병렬」(재라운드는 직렬 B→C)
  Phase B 1회: spec-reviewer-ko — FID 전체(전 task context·AC·diff)
    → SubagentStop 훅(hooks/save-review-report.sh)이 **task마다** reviews/<tid>-B-report.md 저장
      (판정 SoT = reviews 파일 · report 부재 시 부모 fallback 저장 — 반환 전문에서 tid 별로)
      (반환에 훅 요약이 없으면 파일 존재와 무관하게 덮어쓰기 저장 — `저장:` 경로 목록이 아니면 옛 report 를 반환 전문으로 교체) · 단 `review-saved.sh check` rc 0 이면 다시 쓰지 않는다(「end-loaded B/C 산출물 규약」)
    → dispatch-log 행은 부모가 기록: 각 tid 행(경로 `reviews/<tid>-B-report.md` 또는 ## task-<tid> + B 셀)
    → FAIL 시 feedback → 관련 implementer 재dispatch(cap=2 FID 단위) → B 재실행
  Phase C 1회: code-reviewer-ko — FID 전체 + B-report 경로들(최초 병렬은 `병렬 dispatch: yes (B 판정 대기)`)
    → reviews/<tid>-C-report.md (또는 -C-feedback) 동일 규약
  최종 통합 code-reviewer: **SKIP** (end-loaded C가 전체 구현을 이미 봄 — E2와 동형)
    ↓
[per-task만] 최종 코드 리뷰어 — 태스크 수==1 이면 SKIP (E2)
    ↓
specops-ko:verifying-evidence-ko 호출
```

**DAG 파싱 실패 fallback (advisor 협의 13:00)**: `dag::find_independent_batch` 가 빈 출력 + stderr WARN 반환 → SEQUENTIAL 분기로 자동 fallback. 강제 차단 안 함 (v0.4a; v0.4b strict mode 옵션 검토).

### end-loaded B/C 산출물 규약 (review-audit 정합)

한 번의 Evaluator dispatch여도 **감사 teeth는 per-task 파일**을 요구한다 (`check-review-audit.sh`):

1. 리뷰어는 FID 전체를 보고 tid 마다 `<<<REVIEW …>>>` 블록으로 전문을 낸다. SubagentStop 훅(`hooks/save-review-report.sh`)이 `reviews/<tid>-B-report.md` / `reviews/<tid>-C-report.md` 로 분할 저장하고(통과 판정이 아니면 `-feedback.md` 병기) 리뷰어에게 요약 재종료를 요구한다. 판정 SoT = reviews 파일 — 부모는 반환 요약이 아니라 파일을 읽어 판정한다. report 부재 시 부모 fallback 저장: 훅이 돌지 않았거나 블록 형식이 틀리면 리뷰어 전문이 그대로 반환되므로 부모가 태스크별로 분할 저장한다. 단 B/C dispatch 직전 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/review-saved.sh mark <FID> <B|C>` 를 남기고, 반환 뒤 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/review-saved.sh check <FID> <B|C> <tid>...` 가 rc 0 이면 반환 도구 경로의 훅(PreToolUse — 요약을 내지 않는다)이 이번 dispatch 뒤에 모든 tid 를 저장한 것이라 다시 쓰지 않는다 · rc 1 이면 출력된 tid 만 아래 규칙으로 저장한다 · rc 2(인자 오류·FID 디렉터리 없음)면 rc 1 처럼 전 tid 를 저장한다. 반환에 훅 요약이 없으면 파일 존재와 무관하게 덮어쓰기 저장한다 — 반환이 훅 요약(`저장:` 경로 목록)이 아니면 이전 라운드 report 가 남아 있어도 반환 전문으로 tid 별로 덮어써, 형식 오류·이동 실패로 옛 판정을 읽는 경로를 막는다

> **부모 dispatch 프롬프트 규약 (형식을 그대로 옮길 것)**: Phase B/C dispatch 시 리뷰어에게 아래 형식을 지시한다. 속성을 생략하면 훅이 저장하지 않는다 — 형식이 어긋나면 훅이 `exit 1` 로 사유를 남기고 부모 fallback 경로로 떨어진다.
>
> ```
> <<<REVIEW fid=<FID> tid=<T#> phase=<B 또는 C> verdict=<PASS|READY_TO_MERGE|NEEDS_FIX|NEEDS_DISCUSSION>>>
> (보고서 전문)
> <<<END>>>
> ```
>
> `fid` 는 `YYYYMMDD-slug`, `tid` 는 `T` + 숫자, `phase` 는 `B` 또는 `C` 다. tid 마다 블록을 하나씩 낸다.

> **판정 어휘 → 부모 처리** (본문의 "B/C FAIL" = `NEEDS_FIX`; dispatch-log 판정 열은 `PASS`/`FAIL` 로 정규화):
> - `PASS`·`READY_TO_MERGE` → 진행 · `NEEDS_FIX` → `FAIL` 기록 + implementer-ko 재dispatch(feedback 경로, 재시도 cap·상향 규칙)
> - `NEEDS_CONTEXT`(훅 정규식 밖 → 부모 fallback 저장)·`SKIP` → 컨텍스트/B-report 경로 보정 후 재dispatch (재시도 불산입)
> - C `NEEDS_DISCUSSION` → `HOLD` 기록 + **사용자 판단 대기**(trade-off 선택지 그대로 제시, `§auto` 도 자동 선택 금지, `§batch` 는 `BATCH-FR-HELD: <FID>` 출력 후 halt)
>
> **채운 예시** — 위 골격의 꺾쇠 자리표시자는 닫는 `>` 가 마커의 `>>>` 와 이어져 개수를 오독하기 쉽다. 프롬프트에는 아래처럼 **값을 채운 형태**로 적는다:
>
> ```
> <<<REVIEW fid=20260917-example-fid tid=T2 phase=B verdict=PASS>>>
> (보고서 전문)
> <<<END>>>
> ```

2. dispatch-log 행은 부모가 기록 — `dispatch-log.md`에 **tid마다** 1행 append — `reviews/<tid>-B-report.md` 경로 포함 (또는 `## task-<tid>` 섹션 + Phase 셀 `B`/`C`)
3. 금지: `all-B-report.md`만 남기고 tid 파일 0건 (audit가 `all`을 tid로 오인하거나 SKIP/FAIL)
4. dispatch-log 투명성: `| <ts> | End-loaded-B | spec-reviewer-ko | PASS|FAIL | reviews/<tid>-B-report.md |` 형태를 tid 루프에 기록

## F-12 ESCAPE HATCH 재정의 (v0.4a — 동일 파일 쌍 집약 vs DAG 병렬)

v0.4a DAG 자동 라우팅 도입 후 F-12 ESCAPE HATCH 의미가 정정됐다 (advisor 협의 13:00):

| 시나리오 | 처리 방식 | 근거 |
|---|---|---|
| **동일 파일 쌍 TDD 체인** (예: T1·T2 모두 `src/X.sh` + `tests/test-X.sh` 수정) | 구현자 1 dispatch 집약 (Phase A) + **end-loaded면 FID B/C 1회**, per-task면 별도 B/C — **순차** | 동일 파일 = outputs overlap → DAG 가 자동으로 batch 형성 안 함 |
| **독립 leaf 2+** (출력 disjoint) | DAG-AWARE PARALLEL 분기 (v0.4a 신규) — **병렬** | dag::find_independent_batch 가 자동 식별 |
| **1 leaf + chain** | 기본 SEQUENTIAL 분기 — **순차** | 일반 케이스 |

**F-12 집약 조건** (동일 파일 쌍 시):

태스크 2 개 이상이 **동일 파일 쌍** (예: `src/X.sh` + `tests/test-X.sh`) 을 **순차 수정하는 TDD 체인** 이면 구현자 dispatch 를 **1 회로 집약**할 수 있다. 조건:

1. 각 태스크의 TDD 5 스텝 (RED → FAIL → GREEN → PASS → COMMIT) 을 **태스크 내부 embedded cycle** 로 구현자가 준수
2. 2 단계 리뷰 (Phase B 스펙 · Phase C 코드 품질) 는 **생략 금지** — end-loaded면 FID 말미 1회, per-task면 태스크별. **구현자 집약 대상이 아님**
3. `dispatch-log.md` 에 집약 근거 (동일 파일 쌍 판정 · 태스크 LOC · TDD 사이클 구조) 명시 의무 (원칙 1 투명성)

**근거**: dogfood FID `20260422-csv-lines` 실측 — 5 태스크 전부 `csv-lines` + `tests/test-csv-lines.sh` 만 수정 · 총 40 LOC. 규약대로 15 dispatch 대신 3 dispatch (구현자 1 + 리뷰어 2) 로 집약해 27.1k 토큰 절감, Phase B/C 리뷰는 유지. `dispatch-log.md` Phase A/B/C 기록이 5 원칙 4 (주권) · 1 (투명성) 충족 증거 (FRICTION-LOG F-12). end-loaded 기본은 이 패턴을 **모든 FID**에 일반화한다(A=N, B=1, C=1).

**위 조건 불충족 시** 기본값 ("태스크별 fresh 구현자 dispatch") 그대로 유지 — B/C는 여전히 end-loaded(기본) 또는 per-task.

## 최종 리뷰 right-size — 중복 제거 (E2 + end-loaded)

Wave loop 완료 후의 **최종 코드 리뷰어(전체 구현)** 는 **태스크 간 통합**(경계·교차 영향)을 검토하는 단계다.

- **`review_mode: end-loaded`(기본)**: end-loaded Phase C가 이미 FID 전체를 보므로 **최종 리뷰 항상 SKIP**. `dispatch-log.md`에 `최종 리뷰 SKIP (end-loaded C — 전체 구현 이미 리뷰, E2)` 기록.
- **`review_mode: per-task` + 태스크 수 == 1**: 동일하게 SKIP (`최종 리뷰 SKIP (단일 태스크 — Phase C 중복 제거, E2)`).
- **`review_mode: per-task` + 태스크 2개 이상**: 최종 리뷰 **유지** — per-task C가 못 보는 교차 표면.
- **금지**: Phase B/C **생략**(리뷰 0회). end-loaded는 **시점 통합**이지 생략이 아니다. risk-profile allowlist의 「B/C 축소 금지」= 생략 금지.

## Phase B/C 자동 재dispatch 정책 (Wave 2 U5)

| Phase | FAIL 시 동작 | 재dispatch subagent_type | cap | cap 초과 시 |
|---|---|---|---|---|
| B (spec-reviewer-ko FAIL) | reviewer feedback (`reviews/<task-id>-B-feedback.md`) 을 추가 컨텍스트로 1회 자동 재dispatch | `specops-ko:implementer-ko` | **per-task**: task 당 1회 (B=1/2). **end-loaded**: FID 당 1회 재시도(관련 task만 재구현) | 아래 「cap 초과 처리」 — 전역 재시도 뒤에도 남으면 `HARD-GATE: <task-id> Phase B cap 초과` |
| C (code-reviewer-ko FAIL) | reviewer feedback (`reviews/<task-id>-C-feedback.md`) 을 추가 컨텍스트로 1회 자동 재dispatch | `specops-ko:implementer-ko` | **per-task**: task 당 1회 (C=1/2). **end-loaded**: FID 당 1회 | 아래 「cap 초과 처리」 — 전역 재시도 뒤에도 남으면 `HARD-GATE: <task-id> Phase C cap 초과` |

**cap=2 (Phase별 독립)** — Phase B 최대 2회 시도 (`B=0/2` → `B=1/2` → `B=2/2 EXCEEDED`), Phase C 최대 2회 시도 (`C=0/2` → `C=1/2` → `C=2/2 EXCEEDED`). Phase B/C 는 각자 독립된 cap 을 가지며 공유하지 않는다. cap 초과 시 곧바로 멈추지 않는다 — 아래 「cap 초과 처리」의 전역 재시도 1회 뒤에도 Critical 이 남을 때만 HARD GATE 다. end-loaded FAIL 시에도 feedback 파일은 **영향받은 tid마다** 저장하고 dispatch-log에 tid 행을 남긴다(감사 정합).

## Evaluator 모델 불가 fallback (P1 — 20260718 test2 정주행 회고)

Phase B/C Evaluator 는 frontmatter 별칭 모델(spec sonnet·code opus)로 고정이다. 지정 모델이 **불가**(한도 소진·overload·접근 불가)해 Evaluator dispatch 가 실패하면 Generator↔Evaluator 분리가 위협받는다. **아래 순서를 강제**한다:

1. **같은 Evaluator 를 독립 서브에이전트로 재dispatch** 하되 **가용 모델을 override**(Agent 도구 `model` 인자로 세션 모델 등 지정, 실패한 모델 아님 — `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` 설정 시 불가). fresh 서브에이전트 = **부모와 분리된 컨텍스트**라 Generator↔Evaluator 불변식이 보존된다 — 독립성은 **모델 차이가 아니라 컨텍스트 분리**에서 온다.
2. **절대 부모 self-review 로 후퇴 금지** — 부모(생성자)가 자기 산출을 리뷰하면 Evaluator=Generator 편향(자기평가)이다. **test2 실측 근거**: 부모(opus) self-review 가 놓친 Critical(I-1 self-gate exit 마스킹)을 **독립 서브에이전트 리뷰어가 잡았다**. 즉 **독립-약한 모델 ≫ 편향-강한 모델**.
3. `dispatch-log.md` 에 degradation 명시: `Phase C: code-reviewer-ko (모델 fallback: <지정 모델> 불가 → <모델>) PASS/FAIL` (원칙 1·5 — 투명성·한계 고백).
4. **메트릭 (Wave C, 필수)**: fallback 직후 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/record-metric.sh --fid <FID> --task <task-id> --phase evaluator-degradation --fallback true --model <override-model>` 실행. 프롬프트·사유 원문은 넣지 않는다(스키마 식별자만).
5. 이건 **graceful floor** 지 지정 모델 등가가 아니다 — 리뷰 깊이가 낮아질 수 있으니, 한도 복구 후 **보안·인증·DB·migration 등 고위험 FID 는 지정 모델로 재리뷰 필요**(dispatch-log 플래그 + 위 메트릭 한 줄이 근거).

> **[기계 검사 — 미기록은 VERIFY 를 막는다]** (20260721 test1 dogfood): 위 3·4·5 항(degradation 기록·메트릭)과 아래 감사 추적은 **프로즈가 아니다**. `scripts/_internal/check-review-audit.sh` 가 `reviews/<task-id>-[BC]-{report,feedback}.md` ↔ `dispatch-log.md` **구조화 행/경로**를 대조하고, `run-verification.sh` 가 이를 호출해 **미기록 리뷰가 있으면 `VERIFY: PASS` 를 거부**한다 (실행-근거 게이트 → 커밋도 안 열림). 인정 형태: (1) `reviews/<basename>` 경로 (2) Phase 셀 `B:<task-id>`/`C:<task-id>` (3) `## task-<task-id>` 섹션 내 B/C 행. **tid 문자열만 산문에 있으면 부족**하다. 실측 근거: test1 `20260717-approval-rbac` 이 `reviews/T10-B-report.md` 만 남기고 dispatch-log 행을 누락 · downstream-dogfood 산문위장 false-pass. **한계**: 행은 썼는데 내용이 거짓인 falsification은 자기보고라 파일 대조로 못 잡는다.

> **[B/C 판정 file-based 감사 추적]** (20260716 dogfood 관찰 B — Phase C 리뷰어가 "B PASS 근거가 부모 선언뿐" 지적): Phase B·C 판정은 **PASS 여도** `reviews/<task-id>-B-report.md`(·`-C-report.md`) 로 저장한다 — 판정·AC별 근거 요약(리뷰어 반환 그대로). FAIL 피드백(`-B-feedback.md`)만 파일화하고 PASS 는 대화 선언으로 흘리면, Phase C 는 B 통과 자격을 검증 불가능한 부모 말로 수용하게 되고(file-based-communication 위반) 사후 감사 추적이 비어버린다. Phase C dispatch 프롬프트에는 `-B-report.md` **경로**를 포함한다(최초 병렬 쌍은 사후 대조 행으로 대체 — 「최초 B/C 쌍 병렬」).

**cap 초과 처리** (모드 무관 — 종전엔 `§auto` 전용이었고 단일 모드는 곧바로 사용자에게 물었다):

cap 초과 시 곧바로 멈추지 않고 **systematic-debugging-ko → 전역 재시도** 흐름을 먼저 탄다 (Phase C 의 Important 만 남은 경우는 재시도 없이 `backlog` 로 넘긴다 — `dev-autonomy.md` §2):

```
auto-state.md 읽기 (.specops/<FID>/auto-state.md — 없으면 auto_retry_count=0 으로 간주)
auto_retry_count < 1?
  ├─ YES → auto_retry_count += 1 저장 + escalations 기록
  │        → specops-ko:systematic-debugging-ko 호출
  │        → 복귀 후 task 재dispatch (loop 재진입)
  └─ NO  → HARD GATE (`§auto` 는 무인 종료 · 그 밖은 사용자에게 한 번에 묻는다):
           "AUTO-HARD-GATE: <task-id> Phase B/C 전역 재시도 초과 (1/1)
            FAIL: <이슈 목록>
            systematic-debugging 또는 사용자 개입 필요"
```

**auto-state.md 경로**: `.specops/<FID>/auto-state.md` (structured-artifacts-ko 규약).
**카운터 공유**: implementing-ko와 verifying-evidence-ko가 동일 `auto_retry_count`를 공유 — per-FID 전역.

## pre-dispatch irreversible 게이트 (§auto 전용)

각 task dispatch **직전**, tasks.md YAML에서 `irreversible: true` 필드를 확인:

```bash
# 해당 task-id 의 irreversible 필드 확인
grep -A5 "id: <task-id>" .specops/<FID>/tasks.md | grep "irreversible: true"
```

**3-way 분기**:
- `§batch` 감지 → 진행 (오케스트레이터 책임)
- `§auto` 감지 + `irreversible: true` → **mini HARD GATE (발생 위치에서 정지)**:
  ```
  AUTO-HARD-GATE: <task-id> 비가역 작업 — 최종 게이트로 큐잉 불가
  내용: <task 헤더 요약>
  진행하시겠습니까? [y/n]
  ```
  `n` 시 → Lifecycle 종료. `y` 시 → 진행.
- 단일 모드 + `irreversible: true` → 사전 승인 기록(`dispatch/<task-id>-approval.md` — `dev-autonomy.md` §1)이 있으면 다시 묻지 않고 진행, 없으면 task 내부 Step 0

**reviewer 출력 파일 경로 규약** (file-based-communication-ko 준수 — reviewer 는 read-only, SubagentStop 훅이 저장 · report 부재 시 부모 fallback 저장):
- `.specops/<FID>/reviews/<task-id>-B-report.md` — spec-reviewer-ko 판정 보고서(PASS/FAIL 무관). **SubagentStop 훅이 저장** — 부모는 fallback 조건(report 부재 · 반환에 훅 요약 없음)일 때만 저장 · `review-saved.sh check` rc 0 이면 저장하지 않는다
- `.specops/<FID>/reviews/<task-id>-B-feedback.md` — FAIL 시 implementer-ko 재dispatch 용 (B-report 와 동일 내용이거나 이슈 발췌)
- `.specops/<FID>/reviews/<task-id>-C-feedback.md` — code-reviewer-ko 출력. **SubagentStop 훅이 저장** — 부모는 같은 fallback 조건일 때만 저장

전달 규약 (본문 페이로드 금지 — 항상 **경로만**):
- **PASS 경로 (Phase B→C, 직렬 재라운드)**: Phase B PASS 시 부모는 `reviews/<task-id>-B-report.md` 경로를 Phase C(code-reviewer-ko) dispatch context.md 의 "Phase B PASS 보고서" 항목에 **경로로** 명시. code-reviewer-ko 는 이 경로를 read 해 PASS 진입 자격을 확인 (경로 누락 시에만 SKIP).
- **FAIL 경로**: Phase B/C FAIL 직후 훅이 저장한 위 feedback 경로를 확인한 뒤(fallback 조건이면 부모가 저장) implementer-ko 재dispatch, 경로만 추가 컨텍스트로 전달.

### 최초 B/C 쌍 병렬 (20261006-review-bc-parallel)

B 는 거의 항상 통과(1회차 FAIL 6/101)하는데 직렬이라 FID 당 약 8~9분이 더해졌다. end-loaded **최초** B·C 는 **한 메시지에서 동시 dispatch** 한다(재라운드·per-task 는 직렬 B→C). 두 프롬프트에 실 트리 변조 금지·임시 복사본 규칙을 반복하고, C 에는 B-report 경로 대신 `병렬 dispatch: yes (B 판정 대기)` 를 준다. 한쪽 dispatch 가 실패하면 실패한 쪽만 위 Evaluator 모델 불가 fallback 을 적용하고 다른 쪽을 기다리며 사후 대조 규칙은 동일하다. 병렬은 리뷰 축소가 아니므로 strict 위험 프로파일의 B/C 축소 금지와 충돌하지 않는다.

**사후 대조(필수)** — 둘 다 끝나면 `reviews/<tid>-B-report.md` 판정을 읽어 tid 마다 dispatch-log 에 Phase 셀 `BC-PAR-CHECK:<tid>` 행(결과·B/C 리포트 경로)을 남긴다. 이 행이 없으면 `check-review-audit.sh` 가 `PENDING(병렬` C 리포트를 FAIL 한다.
- B PASS → 결과 `B PASS`. C 판정을 채택한다.
- B FAIL → 결과 `C 폐기(B FAIL)`. C 결과는 채택하지 않고 implementer 재dispatch 컨텍스트에 B feedback·C 보고서 경로를 함께 준다. 재라운드 C 가 같은 파일명으로 덮어쓴다.
사후 대조는 tid 단위다 — C 는 FID 전체 1회지만 B PASS tid 의 C 판정만 채택하고 B FAIL tid 의 C 만 폐기한다. 폐기는 C cap 을 소모하지 않으며 재라운드는 영향 tid 만 직렬 B→C 로 다시 돈다. 훅이 지우지 않는 옛 `-B-feedback.md` 가 남아도 행은 그 tid 의 실제 B 판정(`B PASS`·`C 폐기`)대로 쓴다.

## 전체 스위트 병행 (20261005-dedupe-test-runs)

`scripts/tests/run-all.sh` 가 있는 repo 에서, 마지막 태스크의 Phase A·receipt·커밋이 끝나면 B/C 에 들어가기 **전에** 전체 스위트를 백그라운드(Bash `run_in_background`)로 띄운다. Phase B/C 와 **겹쳐** 돈다 — 리뷰 대기 동안 스위트가 끝나 있게 하는 것이 목적이다.

```bash
bash "$(git rev-parse --show-toplevel)"/scripts/tests/run-all.sh --quiet > ".specops/$FID/run-all.log" 2>&1
```

- **증거가 아니다**: R-1/R-2 게이트 증거는 verify 단계 `run-verification.sh` 의 `VERIFY: PASS` 실행 출력이다. 이 실행은 verify 가 전체 스위트를 생략할 근거(통과 마커)를 만들 뿐이다.
- **수정 라운드**: Phase B/C FAIL 로 코드가 바뀌면 마커 지문이 달라져 STALE 이 되고 verify 가 포그라운드로 다시 돈다. 라운드마다 다시 띄우지 않는다.
- **FAIL 이면**: 종료 후 `run-all.log` 의 `FAILED` 줄을 사용자에게 알리되 B/C 는 막지 않는다. 최종 판정은 verify 의 포그라운드 재실행이다(flaky 를 숨기지 않는다).
- **실 트리 변조 금지**: 병행 스위트가 실 트리를 읽는 동안 리뷰어가 되돌려-관찰·변이를 실 트리에서 하면 스위트가 오염된다. 그 관찰은 **임시 복사본**에서만 한다(dispatch 프롬프트에 명시).
- `§batch` FID 에는 적용하지 않는다 — FR 마다 스위트를 띄우면 곱으로 번진다.

### 리뷰어 실행 예산

부모 dispatch 프롬프트는 에이전트 계약(`agents/spec-reviewer-ko.md`·`agents/code-reviewer-ko.md`) 밖의 실행을 **추가하지 않는다**. `risk-profile.json` 의 effective 가 `lite`·`standard` 면 Phase B 는 diff·AC 대조 + 핵심 실행 2회 이내, Phase C 는 되돌려-관찰 3회 이내이고 전체 소비자 스위트 재실행은 하지 않는다(병행 스위트·verify 의 몫). `strict` 는 종전 그대로 제한 없음. 근거: 20261005 실측 — 리뷰 구간이 FID 당 30~40분을 차지하고 그 상당수가 리뷰어의 재실행이다.

**대상 스위트가 느린 경우**(단독 실행 60초 이상 — 예: `test-skill-evals` 2분 29초): B·C 가 같은 스위트를 겹쳐 돌리면 부하에서 서로 거짓 FAIL(T5.o 계열)을 만들고 리뷰가 20분을 넘긴다(20261008 실측: 2줄 수정에 B 20분·C 29분). 그래서 `lite`·`standard` 한정 — `strict` 는 위대로 제한 없음: ① dispatch 프롬프트에 **대상 스위트 실행 상한을 숫자로** 적는다(되돌려-관찰 포함 B ≤2회·C ≤3회 — 위 예산과 같은 수), ② 동시 실행으로 생긴 실패는 단독 재실행으로 구분한다, ③ 부모는 계약 밖 점검(호스트 변수 전수 등)을 프롬프트에 **추가하지 않는다**. 구현자 dispatch 에도 같은 이유로 `RED 1회·GREEN 1회·되돌려-관찰 1회` 상한을 적는다 (GREEN 이 FAIL 이면 수정 후 재실행은 상한에 넣지 않는다 — 상한은 첫 PASS 이후의 반복 실행만 센다). B·C 각 1회 필수와 독립 되돌려-관찰 증거는 줄이지 않는다(품질 우선).

## 리뷰어 dispatch 입력 계약 (20260809)

Phase B/C dispatch 시 `agents/spec-reviewer-ko.md`·`agents/code-reviewer-ko.md` 의 **받는 컨텍스트** 목록 밖 경로를 임의로 첨부하지 않는다. 두 계약은 이미 최소다 — `tasks.md`·`plan.md`·`clarifications.md` 는 **거기 없다**.

리뷰어가 더 필요하면 **`NEEDS_CONTEXT` 로 당겨간다**(push → pull). 그 반환 경로가 이미 규약에 있으므로 부모가 미리 얹을 이유가 없다.

**근거(실측 20260809)**: 계약 밖 첨부가 dispatch 당 **5~11k 토큰(8~14%)** 을 더한다. `/start-all` 에서는 **2N배**로 곱해진다.

## dispatch-log.md 자동 append (Wave 2 U5)

task 시작 시 `.specops/<FID>/dispatch-log.md` 부재면 `templates/dispatch-log.md` 복사로 생성. 매 시도(Phase A/B/C)마다 해당 task-id 블록에 1행 append:

```
| # | <ISO-8601> | <Phase> | <agent> | PASS|FAIL | <feedback path 또는 -> |
```

footer 의 `재시도 누적: B=N/2 C=N/2 (cap=2)` 카운트도 시도마다 갱신. cap 초과 시 처리는 위 「cap 초과 처리」를 따른다.

## 모델 라우팅 (역할별 고정)

서브에이전트 모델·effort 는 **각 `agents/<name>.md` frontmatter 의 `model:`·`effort:` 로 역할별 고정**된다. 별칭 sonnet·opus 만 쓴다(fable 금지 — 과금·접근 불가 가능). 세션·주간 한도는 공유되고 서브에이전트는 별도 소모되므로 호출이 가장 많은 구현자는 Sonnet, 계획·코드 리뷰어는 Opus 다(덮어쓰기: README `모델 · effort 운용`). 상향 규칙 외에는 부모가 dispatch 마다 티어를 판단하지 않는다.

| 역할 | 에이전트 | model · effort |
|---|---|---|
| Generator | `implementer-ko` | sonnet · medium |
| Evaluator (Phase B·설계) | `spec-reviewer-ko`·`design-reviewer-ko` | sonnet · high |
| Evaluator (계획·Phase C) | `plan-reviewer-ko`·`code-reviewer-ko` | opus · high |
| self-config 감사 | `red-team-ko`·`blue-team-ko`·`auditor-ko` | inherit |

**재dispatch 시 (상향 규칙)**: BLOCKED·Phase B/C FAIL 로 `implementer-ko` 를 재dispatch 할 때는 컨텍스트 보강과 함께 부모가 Agent 도구 `model` 인자로 `opus` 를 지정해 **1회 상향**한다(재dispatch 마다, 횟수·cap 불변). 상향 후에도 실패하면 B/C 는 「cap 초과 처리」, BLOCKED 는 에스컬레이션이다. 상향한 때만 dispatch-log 에 `(모델 상향: sonnet → opus)` 를 기록한다(FORCE 설정 시 상향 불가).

## 구현자 상태 처리

구현자 서브에이전트는 다섯 가지 상태 중 하나 보고(`agents/implementer-ko.md` 반환 상태와 1:1). 각각 적절히 처리:

**DONE**: 스펙 준수 리뷰로 진행.

**DONE_WITH_CONCERNS**: 구현자가 작업은 완료했으나 의문을 표시. 리뷰 전 우려사항 읽기. 정확성·범위 관련이면 **리뷰 전 처리**. 관찰(예: "이 파일이 커지고 있음")이면 메모 후 리뷰 진행.

**NEEDS_CONTEXT**: 구현자가 제공받지 못한 정보 필요. 누락된 컨텍스트 제공 후 재dispatch.

v0.4a W2 — leaf subagent 가 다음 6 트리거 중 하나라도 발견 시 즉시 NEEDS_CONTEXT 반환 (추측 금지):
1. 5 컨텍스트(담당 AC / spec.md 섹션 / test 명령 / 수정 허용 파일 whitelist / worktree 경로) 중 1개 이상 누락
2. 담당 AC ID 가 acceptance-criteria.md 에서 발견 안 됨
3. spec.md 섹션 경로가 존재하지 않거나 빈 라인 범위
4. 테스트 명령 실행 자체가 실패 (test 파일 없음)
5. whitelist 외 파일을 수정해야 task 완수 가능 — 부모에 컨텍스트 보강 요청
6. worktree 경로 존재 안 함 또는 git worktree 가 아님

부모 검증: dispatch 직전 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dag/validate-context.sh .specops/<FID>/dispatch/<task-id>-context.md` 실행 — exit 1 시 dispatch 보류. 표준 포맷: `templates/dispatch-context.md`.

> **[스코프 이관 규약]** (트리거 5 = whitelist 외 파일 수정 필요 — verify-exec-gate 잔여 backlog): 이관은 **tasks.md 가 SoT** 다. dispatch context 파일만 수기 보강하는 것을 **금지**한다 — ① tasks.md 와 drift ② emit-context 재실행 시 수기 보강 증발 ③ 후속 wave 의 outputs-disjoint 병렬 판정이 **낡은 outputs 로 계산**되어 두 leaf 가 같은 파일을 병렬 편집(R11 git race). 처리 순서:
> 1. `.specops/<FID>/tasks.md` YAML 의 해당 task `outputs`(필요시 `inputs`)를 먼저 갱신 — 이관 사유 1줄 주석
> 2. `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dag/emit-context.sh <FID>` 재실행 (dispatch context 재생성 — 수기 편집 금지) + §5 worktree 라인 sed 재갱신 (재생성으로 리셋됨)
> 3. **미완 wave 의 outputs-disjoint 재판정** — 이관으로 두 task 의 outputs 가 겹치게 되면 해당 쌍은 병렬 금지 → 순차 강등
> 4. dispatch-log 에 `SCOPE-MOVED: <task-id> +<file> (<사유>)` 1줄 기록 후 재dispatch

**NEEDS_APPROVAL**: 구현자가 비가역·범위 변경 작업에서 **멈추고** 승인을 요청한 것 — 무응답으로 두면 태스크가 조용히 멈춘다. 작업 요약을 사용자에게 그대로 제시하고 `NEEDS-APPROVAL: <task-id> … 진행하시겠습니까? [y/n]` 로 묻는다(`§auto` 도 예외 없음, `§batch` 는 `BATCH-FR-HELD: <FID>` 출력 후 halt). 절차 전문(승인 기록·`n` 처리·dispatch-log 행)은 같은 디렉터리 `needs-approval.md` 를 Read 한다.

**BLOCKED**: 구현자가 태스크 완료 불가. 블로커 평가 (구현자 기본은 sonnet — 컨텍스트 보강·분해와 함께 위 상향 규칙으로 opus 1회 상향, 이후 에스컬레이션):
1. 컨텍스트 문제 → 컨텍스트 더 주고 재dispatch
2. 더 강력한 추론 필요 → 위 상향 규칙으로 opus 1회 상향, 상향 후에도 막히면 태스크를 더 작게 분해하거나 사람에게 에스컬레이션
3. 태스크가 너무 큼 → 더 작게 쪼개기
4. 플랜 자체가 잘못 → **사람에게 에스컬레이션**

**절대 금지**: 에스컬레이션 무시, 변경 없이 재시도. 구현자가 막혔다고 말하면 **무언가 바뀌어야 한다** (컨텍스트·태스크 크기·플랜).

## 에이전트 정의 파일

3개 에이전트가 `agents/` 디렉토리에 정의돼 있다:

- `agents/implementer-ko.md` — 구현자 서브에이전트 (Phase A)
- `agents/spec-reviewer-ko.md` — 스펙 준수 리뷰어 (Phase B)
- `agents/code-reviewer-ko.md` — 코드 품질 리뷰어 (Phase C)

각 에이전트는 **자신의 namespace subagent_type** 으로 dispatch 한다 — Phase A 는 `subagent_type: "specops-ko:implementer-ko"`, Phase B 는 `"specops-ko:spec-reviewer-ko"`, Phase C 는 `"specops-ko:code-reviewer-ko"` (Generator/Evaluator 분리 — 리뷰어를 implementer 로 dispatch 금지). 모두 `templates/dispatch-context.md` 포맷의 컨텍스트 파일을 입력으로 받는다.

## 레드 플래그 — 금지

**절대 금지**:
- main/master 브랜치에서 **명시 동의 없이** 구현 시작
- 리뷰 생략 (스펙 준수 OR 코드 품질)
- **미해결 이슈를 두고 진행** (`backlog` 로 기록해 넘긴 계약 밖 항목은 미해결이 아니다 — `dev-autonomy.md` §2)
- 구현 서브에이전트를 **상태 공유 시 병렬로** dispatch (충돌, R11). v0.4a 정정: outputs disjoint 한 독립 leaf 2+ 는 `dispatching-parallel-agents-ko` DAG-aware 모드로 자동 병렬 권장 — `dag::find_independent_batch` 가 자동 식별. **상태 공유 (같은 파일 수정) 시에만 병렬 금지**
- 서브에이전트 프롬프트에 **파일 본문(payload)을 인라인 첨부** — `file-based-communication-ko` 위반. 경로만 전달하고 서브에이전트가 `.specops/<FID>/*.md`·`dispatch/<task-id>-context.md` 를 직접 read 해야 한다 (컨트롤러 컨텍스트 오염 방지)
- 장면 설정 컨텍스트 생략 (서브에이전트는 태스크가 어디에 맞는지 이해해야 함)
- 서브에이전트 질문 무시 (진행 전에 답하기)
- "근접함"으로 스펙 준수 인정 (스펙 리뷰어가 이슈 발견 = 미완료)
- 리뷰 루프 생략 (리뷰어 이슈 발견 → 구현자 수정 → 다시 리뷰)
- 구현자 자체검토를 실제 리뷰로 대체 (둘 다 필요)
- **스펙 준수 ✅ 전에 코드 품질 리뷰 시작** (순서 어김)
- 어느 리뷰라도 이슈 미해결인 채 다음 태스크로 이동

**서브에이전트가 질문하면**:
- 명확하고 완전히 답변
- 필요하면 추가 컨텍스트 제공
- 구현으로 몰아치지 말 것

**리뷰어가 이슈 발견하면**:
- 구현자(같은 서브에이전트)가 수정
- 리뷰어 재리뷰
- 승인까지 반복
- 재리뷰 생략 금지

**서브에이전트가 태스크 실패하면**:
- **수정 서브에이전트**를 구체 지시로 dispatch
- 수동 수정 금지 (컨텍스트 오염)

## 이점

**수동 실행 대비**:
- 서브에이전트가 자연스럽게 TDD 따름
- 태스크별 fresh 컨텍스트 (혼동 없음)
- 병렬 안전 (서브에이전트끼리 간섭 없음)
- 서브에이전트가 질문 가능 (시작 전과 진행 중 모두)

**병렬 세션 실행 대비**:
- 같은 세션 (전환 없음)
- 연속 진행 (대기 없음)
- 리뷰 체크포인트 자동

**효율**:
- 컨트롤러 컨텍스트 보존 (파일 본문 미적재 — 경로만 전달, 서브에이전트가 필요 시 직접 read)
- 컨트롤러가 `dispatch-context.md` 로 **정확히 필요한 컨텍스트 경로만** 조립
- 서브에이전트는 지정된 파일을 read 해 완전한 정보 도달
- 질문이 작업 **시작 전에** 노출 (작업 후가 아니라)

**품질 게이트**:
- 자체검토가 핸드오프 전 이슈 포착
- 2단계 리뷰: 스펙 준수 → 코드 품질
- 리뷰 루프로 수정이 실제 동작함 보장
- 스펙 준수로 과잉·부족 구축 방지
- 코드 품질로 구현이 잘 만들어졌음 보장

**비용** (`review_mode: end-loaded` 기본):
- 구현자 invoke ≈ 태스크 수(A), 리뷰어 ≈ **2**(B+C) — O(N)→O(1) 리뷰
- `per-task` opt-in 시 구현자+리뷰어 2명 / 태스크 (구 비용)
- 컨트롤러 사전 작업(컨텍스트 조립) + 리뷰 루프 이터레이션
- end-loaded는 태스크 중반 피드백이 늦어질 수 있음 — verify FAIL·fix_loop(≤3)가 안전망

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 서브에이전트 dispatch 시 지시·컨텍스트 **전체 기록** (`.specops/<FID>/dispatch-log.md`) |
| 2 **문지기** | 파괴적 명령은 서브에이전트에게도 **명시 확인 루틴** 삽입 |
| 3 **깊이** | BLOCKED 상태는 에스컬레이션. 우회 금지 |
| 4 **주권 존중** | 승인받은 계약(AC·spec) 밖의 것은 **묻지 않고 만들지 않는다** — 넘기고 `dev-decisions.md` 로 끝에 보고. 비가역 작업은 반드시 승인 |
| 5 **한계 고백** | 서브에이전트 자체검토 보고를 **독립 검증 없이** 수용 금지 |

## 통합

**필수 워크플로 스킬**:
- `specops-ko:planning-ko` — 본 스킬이 실행할 플랜 작성
- `specops-ko:verifying-evidence-ko` — 전체 구현 후 검증
- `specops-ko:requesting-code-review-ko` — 리뷰어 서브에이전트용 리뷰 템플릿

**서브에이전트가 사용해야 하는 스킬**:
- `specops-ko:tdd-ko` — 서브에이전트는 각 태스크를 TDD로

**실패 시**:
- `specops-ko:systematic-debugging-ko` — BLOCKED 블로커가 버그성이면 호출

## 참조

- `skills/generator-evaluator-ko/SKILL.md` — 2단계 리뷰(스펙·품질) 분리 원칙
- `skills/context-resets-ko/SKILL.md` — fresh 서브에이전트 세션 보장
- `skills/karpathy-ko/SKILL.md` — Think·Simplicity·Surgical·Goal 4원칙 (cross-cutting)

## Handoff 기록 (다음 skill 진입 직전 필수)

`verifying-evidence-ko` 호출 직전 `.specops/<FID>/handoffs/implementing.md` 작성 (structured-artifacts-ko 규약 4필드: Decided/Rejected/Risks/Remaining). 특히 Remaining 섹션에 "검증이 필요한 AC story 목록" 명시.

## session-progress append (v0.4-pre P1 신설)

모든 태스크 완료 직후, verifying-evidence-ko 호출 직전에:
```
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /implement DONE "Task 1~N 완료, PASS=N FAIL=0, 커밋 <SHA>..<SHA>"
```

## 다음 skill

모든 태스크 완료 + end-loaded(또는 per-task) B/C 통과 + 최종 리뷰 정책 충족 + session-progress append 후 즉시 호출:

```
Skill: specops-ko:verifying-evidence-ko
```

verifying-evidence-ko가 "증거 기반 완료 선언"을 강제한다. 본 implementing-ko는 **verifying-evidence-ko 이외의 다음 스킬을 호출하지 않는다**.
