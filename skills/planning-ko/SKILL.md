---
name: planning-ko
description: 스펙·요구사항이 확보된 다단계 작업에서 코드 건드리기 전에 사용 — 구현 플랜을 bite-sized task 단위로 작성
layer: 2
reference_upstream: obra/superpowers@v5.0.7 skills/writing-plans/SKILL.md
  - obra/superpowers@v5.0.7 skills/writing-plans/SKILL.md
specops_version: 2.18.0
used_by: clarifying-ko (chain 진입), decomposing-ko (chain 출구), /start-all (Phase 2 batch plan-review)
---

# Engine 스킬 — 구현 플랜 작성 (planning)

## 개요

엔지니어가 **코드베이스 컨텍스트 0이고 안목도 의심스럽다**고 가정하고, 포괄적 구현 플랜을 작성한다. 각 태스크에서 건드릴 파일, 코드, 테스트, 참조할 문서, 테스트 방법까지 모두 문서화. 전체 플랜을 **bite-sized 태스크**로 제공. DRY·YAGNI·TDD·잦은 커밋.

숙련 개발자이지만 **우리 도구 세트나 문제 도메인은 거의 모른다**고 가정. 좋은 테스트 설계도 잘 모른다고 가정.

**시작 시 선언**: "planning-ko 스킬로 구현 플랜을 작성합니다."

**컨텍스트**: 전용 worktree에서 실행 (specifying → clarifying 단계에서 생성됨).

**플랜 저장 경로**: `.specops/<FID>/plan.md`
- 사용자 선호가 있으면 그 경로 우선

- 입력: `.specops/<FID>/intent.md`(있으면) + `spec.md` + `acceptance-criteria.md` — intent 는 "왜", spec 은 "무엇", plan 은 "어떻게"
- 프로세스 입력: spec §1 에 `**프로세스**: P-NNN` 이 있으면 `.specops/memory/process-design.md` 의 그 블록을 읽는다 — **트리거→결과** 흐름이 태스크로 끊김 없이 덮이는지, **예외** 항목마다 실패 테스트가 있는지 확인하고 빠진 것은 태스크로 추가한다. 블록의 화면·API·테이블이 plan 의 파일 구조와 어긋나면 plan 을 맞추거나 불일치를 `## 8` 에 기록한다(process-design.md 자체는 여기서 고치지 않는다)

## 범위 점검

스펙이 여러 독립 서브시스템을 담으면 specifying 단계에서 서브프로젝트 스펙으로 쪼개졌어야 함. 그러지 않았다면 **지금이라도 분해 제안** — 서브시스템별 별도 플랜으로. 각 플랜은 단독으로 **동작하는·테스트 가능한 소프트웨어**를 산출해야 함.

## 파일 구조

태스크 정의 전에, 어떤 파일을 만들고 수정할지 + 각 파일의 책임을 **먼저 매핑**. 여기서 분해 결정이 확정된다.

- 명확한 경계·잘 정의된 인터페이스로 단위 설계. 각 파일은 **하나의 명확한 책임**
- 한 번에 컨텍스트에 담을 수 있는 코드일수록 추론과 편집이 정확. 작고 집중된 파일 선호
- **함께 변하는 파일은 함께 있다**. 기술 계층이 아니라 책임으로 분할
- 기존 코드베이스는 **기존 패턴 따름**. 코드베이스가 대형 파일을 쓰면 일방적 재구조화 금지. 다만 수정 중인 파일이 통제불능이면 분할을 플랜에 포함하는 것도 합당
- 매핑을 마치면 `templates/plan.md` 의 `### 경계 약속` 칸 4개(소유·범위 밖·허용 의존·다시 검토할 조건)를 채운다 — 소유에는 테스트 경로도 백틱으로 적는다

이 구조가 태스크 분해의 근거. 각 태스크는 **독립적으로 의미가 통하는** 자족적 변경을 산출해야 함.

## Bite-Sized 태스크 단위

**각 스텝 = 단일 행동 (2~5분)**:
- "실패 테스트 작성" — 스텝
- "실패 확인 위해 실행" — 스텝
- "최소 구현 작성" — 스텝
- "테스트 통과 확인 실행" — 스텝
- "커밋" — 스텝

## 플랜 문서 헤더

**모든 플랜은 이 헤더로 시작**:

```markdown
# [기능명] 구현 플랜

> **에이전트 워커용**: 필수 하위 스킬 — `specops-ko:implementing-ko` (권장) 또는 `specops-ko:decomposing-ko` 사용. 스텝은 체크박스 `- [ ]` 문법으로 추적.

**목표**: [한 문장 — 무엇을 만드는가]

**아키텍처**: [2~3 문장 — 접근]

**기술 스택**: [주요 기술·라이브러리]

---
```

## 태스크 구조

````markdown
### Task N: [컴포넌트명]

**파일**:
- 생성: `exact/path/to/file.py`
- 수정: `exact/path/to/existing.py:123-145`
- 테스트: `tests/exact/path/to/test.py`

- [ ] **Step 1: 실패 테스트 작성**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: 실패 확인 실행**

실행: `pytest tests/path/test.py::test_name -v`
예상: FAIL with "function not defined"

- [ ] **Step 3: 최소 구현 작성**

```python
def function(input):
    return expected
```

- [ ] **Step 4: 통과 확인 실행**

실행: `pytest tests/path/test.py::test_name -v`
예상: PASS

- [ ] **Step 5: 커밋**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: 특정 기능 추가"
```
````

## 플레이스홀더 금지

각 스텝은 엔지니어가 필요한 **실제 내용**을 담아야 함. 다음은 **플랜 실패** — 절대 쓰지 말 것:

- "TBD", "TODO", "implement later", "fill in details"
- "적절한 에러 처리 추가" / "유효성 검증 추가" / "엣지 케이스 처리"
- "위에 대한 테스트 작성" (실제 테스트 코드 없이)
- "Task N과 유사" (코드 반복 — 엔지니어가 순서와 무관하게 읽을 수 있음)
- 무엇을 할지만 설명하고 **어떻게**를 보여주지 않는 스텝 (코드 스텝은 코드 블록 필수)
- 어떤 태스크에도 정의 없는 타입·함수·메서드 참조

## 기억할 것

- **정확한 파일 경로** 항상
- **모든 스텝에 완전한 코드** — 스텝이 코드를 바꾸면 코드를 보여라
- **정확한 명령과 기대 출력**
- DRY·YAGNI·TDD·잦은 커밋

## 자체 검토

완전한 플랜 작성 후, 새 눈으로 스펙과 대조.

**1. 스펙 커버리지**: 스펙의 각 섹션/요구를 훑어보고, 그 요구를 구현하는 태스크를 짚을 수 있는가? 누락 나열.

**2. 플레이스홀더 스캔**: "플레이스홀더 금지" 섹션의 레드 플래그 검색. 수정.

**3. 타입 일관성**: 후반 태스크에서 쓴 타입·메서드 시그니처·속성명이 전반 태스크에서 정의한 것과 일치하는가? Task 3에서 `clearLayers()`였는데 Task 7에서 `clearFullLayers()`라면 버그.

**4. 기존 테스트 승계 스캔**: 이 변경이 **판정 의미**를 바꾸는가? 그렇다면 그 의미를 단언하는 **기존 어서션을 전수 나열**하고 각각 승계/무손상을 명시했는가? 특히 **양성 대조군을 요구하는 어서션**(정상값 존재를 `grep -q` 로 확인하는 형태)은 새 의미에서 표준 픽스처에 양성이 없어 **조용히 깨진다**. 픽스처를 고칠지 단언을 뒤집을지는 **양쪽을 실제로 돌려보고** 정한다 — 추론으로 정하면 틀린다.

**5. 어서션 실행 가능성**: 각 검증 절이 **구조적으로 항상 통과**하지는 않는가? `.gitignore` 로 제외된 경로를 `git diff` 로 검사하거나, 변이 앵커가 실행되지 않는 분기에 있거나, `PATH` 를 통째로 교체해 `bash` 자체를 못 찾는 경우가 실제로 있었다.

**6. 복구 절차 안전성**: 변이 실험의 복구가 **미커밋 구현을 파괴**하지 않는가? `git checkout` 은 커밋 전 작업을 지운다 — `cp` 백업을 쓰고 실험은 커밋 뒤에 한다.

**7. RED 예상 실측**: Step 2 의 예상 출력을 **추론으로 쓰지 않았는가?** 예상이 실제와 다르면 구현자가 절차에서 막힌다.

**8. 최소 태스크**: 각 태스크에 rung 순서로 질문: 존재 필요(YAGNI)? · 기존 헬퍼·유틸 재사용? · stdlib? · 네이티브 기능? · 설치된 의존성? 과잉 태스크 제거. 검증·에러·보안 절차는 제거 대상 아님.

> **4~7은 판정 질문이다 — plan 본문에 답을 길게 쓰지 말 것.** 해당 없으면 "해당 없음" 한 줄이면 된다. 이 검토의 목적은 **리뷰 재dispatch 비용 절감**인데 답이 길어지면 리뷰 대상이 늘어 **역효과**다.
>
> 근거(20260808 실측): plan-reviewer 1회차 판정이 **FAIL 3/3**, 토큰 **525k**(서브에이전트의 52%). 그중 두 건의 Critical 이 **항목 4와 동일 클래스**였다.

이슈 발견 시 인라인 수정. 자체 체크리스트는 재실행 불필요 — 수정 후 아래 독립 검증으로 진행. 스펙 요구에 태스크가 없으면 **태스크 추가**.

## 독립 리뷰 (plan-reviewer 서브에이전트)

### [§batch 분기] plan-reviewer DEFER (Phase 2 batch 1회)

```bash
grep -qE '^\*\*§batch\*\*:' .specops/<FID>/spec.md && echo BATCH || echo SINGLE
```

**`**§batch**` 감지 시** (`/start-all` Phase 1):

1. 자체 검토(위 절)까지 완료 후 **`plan-reviewer-ko` dispatch 하지 않음**
2. 외부 critic(`critic-ask.sh`) **per-FR 미호출**
3. decomposing-ko 진입 **허용** — 아래 「FAIL 시 decomposing 차단」HARD GATE는 **본 경로에 적용하지 않음**(검사는 `/start-all` Phase 2)
4. `.specops/<FID>/dispatch-log.md`에 기록:
   `| <N> | <ISO-8601> | plan-reviewer | DEFERRED | — | Phase 2 batch |`
5. session-progress: `/plan 완료 "plan.md (plan-reviewer DEFERRED → Phase 2 batch)"`
6. handoff Remaining에 `plan-reviewer DEFERRED → Phase 2 batch` 명시
7. 즉시 `## 실행 전환` / `## 다음 skill`(decomposing-ko)

**금지**: §batch인데 Phase 1에서 plan-reviewer를 돌리는 것(비용·시점 계약 위반).

**비-batch** (`/start`·foundation 등 §batch 부재): 아래 기존 독립 리뷰 절차 **그대로**.

### dispatch 직전 사전검사 (필수 — 20260809)

`plan-reviewer` 를 부르기 **전에** 실행한다:

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-plan-predispatch.sh <FID>
```

- **rc=0** (`PREDISPATCH: OK` 또는 `SKIP`) → 아래 dispatch 진행
- **rc=1** → 지적대로 `plan.md` 를 수정하고 **재실행**해 통과시킨 뒤 dispatch

**근거**: plan-reviewer **1회차 FAIL 이 5/5** 이고 재dispatch 1회가 **+62~91k 토큰**이다. 검사기는 그 FAIL 을 만든 결함 중 **기계 판별 가능한 3클래스**만 본다 — ① 잠글 문자열이 repo 에도 plan 구현부에도 없어 어서션이 영구 FAIL ② propagation 레코드가 파서 스키마(`.edges[].path`)와 달라 잠금이 무음 사망 ③ Step 2 가 "이미 통과한다"고 단정하면서 실측 근거가 없음.

> **리뷰어를 대체하지 않는다** — 왕복만 줄인다. 판별이 애매하면 **통과**시키므로(미탐 선택) 놓친 것은 plan-reviewer 가 여전히 잡는다. 실 코퍼스 28건 오탐 **0**.

### 경계 대조 입력 (경고 전용 — 20261015)

사전검사 통과 뒤, plan-reviewer 를 부르기 **전에** 실행한다:

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-plan-boundary.sh <FID> > .specops/<FID>/plan-boundary.txt 2>&1
```

- **종료 코드와 무관하게 진행한다** — 0(판정 완료·경고 포함·SKIP)도 2(판정 불가 항목 있음)도 막지 않는다. 출력은 plan-reviewer 가 `## 경계 대조` 에서 읽는다(Minor 로만).
- 출력 줄: `[경고]`(경계 약속 절·칸) · `[소유 밖] <경로>`(파일 구조 목록이 소유 경로 밖) · `RULE <ID> …`(파일이 닿는 헌법 구조 규칙) · `[판정 불가] …`(없는 것이 아니라 확인하지 못한 것).

### DB 전문가 패스 (DB 를 건드릴 때만 — 20261020)

경계 대조 뒤, plan-reviewer 를 부르기 **전에** 판단한다. plan §2 파일 구조나 태스크가 **DB 산출물**(마이그레이션·SQL·스키마·ORM 모델·`data-model.md`·upsert·대량 적재 코드·테스트 DB fixture)을 만들거나 바꾸면 발동한다. 단어가 언급되기만 하고 그런 파일·태스크가 없으면 발동하지 않는다. 파일 구조·태스크로 판단이 서지 않으면 부른다(긴 plan 에서 DB 결함은 plan-reviewer 를 통과했다: Argus 실제 계획서 2개 0/2). `§batch` 는 이 패스 미적용(후속 FID — 기록 행도 남기지 않는다) · `§auto` 는 그대로 부른다.

- **dispatch**: `Agent` 도구, `subagent_type: "specops-ko:db-designer-ko"` · 입력은 경로만 — `.specops/<FID>/spec.md` · `plan.md` · `.specops/memory/data-model.md`(있으면) · `${CLAUDE_PLUGIN_ROOT}/skills/planning-ko/db-expert/engines/`.
- **반영**: 에이전트가 쓴 `.specops/<FID>/experts/db.md` 의 지적과 `## 확인 필요` 질문마다(질문은 코드베이스·사용자에게 전제를 확인한 뒤) plan.md 에 반영하거나 기각하고, 같은 파일 끝 `## 반영` 절에 `반영(plan §/Task N)` 또는 `기각(근거)` 1줄씩 적는다. plan.md 가 바뀌었으면 위 '사전검사'(check-plan-predispatch.sh)와 '경계 대조 입력'(check-plan-boundary.sh) 의 두 스크립트를 다시 실행한 뒤 plan-reviewer 를 부른다(입력은 그대로 — 전문가 파일을 넘기지 않는다 · 아래 구조 전문가 패스도 돌면 재실행은 그 패스 뒤에 한 번만).
- **모델 불가·산출 없음**: opus 를 쓸 수 없으면 같은 에이전트를 가용 모델 override 로 다시 dispatch 한다(plan-reviewer 의 모델 불가 fallback 과 같은 원칙 — 부모가 대신 검토하지 않는다). `experts/db.md` 가 만들어지지 않았으면 1회 다시 부르고, 그래도 없으면 dispatch-log 에 `| <N> | <ISO-8601> | db-expert | db-designer-ko | 산출 없음 | - |` 를 남기고 plan-reviewer 로 진행한다.
- **기록** (결과 칸에 `DONE`·`IMPL` 을 쓰지 않는다 — 재개 판독기 `reconcile-check.sh` 가 구현 증거로 읽는다): dispatch-log 에 `| <N> | <ISO-8601> | db-expert | db-designer-ko | 반영 | experts/db.md (지적 N · 반영 N · 기각 N) |`. 발동하지 않으면 `| <N> | <ISO-8601> | db-expert | - | SKIP | DB 표면 없음 |` 1행.

### 구조 전문가 패스 (새 모듈·계층·도메인 개념을 만들 때만 — 20261021)

DB 전문가 패스 뒤, plan-reviewer 를 부르기 **전에** 판단한다. plan §2 파일 구조가 **새 폴더·새 모듈·새 계층**을 만들거나, 경계 약속의 허용 의존에 **새 의존 방향**이 생기거나, spec 에 **새 도메인 개념**(엔티티·상태)이 생기면 발동한다. 기존 파일 수정뿐이거나 문서·테스트만 바꾸면 발동하지 않는다. 파일 구조·태스크로 판단이 서지 않으면 부른다. `§batch` 는 이 패스 미적용(기록 행도 남기지 않는다) · `§auto` 는 그대로 부른다. 효과는 합성 평가 케이스로만 봤다(Argus 실제 계획서 측정은 후속).

- **dispatch**: `Agent` 도구, `subagent_type: "specops-ko:arch-designer-ko"` · 입력은 경로만 — `.specops/<FID>/spec.md` · `plan.md` · `.specops/memory/backend-architecture.md`·`frontend-architecture.md`(있으면) · `${CLAUDE_PLUGIN_ROOT}/skills/planning-ko/arch-expert/patterns/`.
- **반영**: 에이전트가 쓴 `.specops/<FID>/experts/arch.md` 의 지적과 `## 확인 필요` 질문마다(질문은 코드베이스·사용자에게 전제를 확인한 뒤) plan.md 에 반영하거나 기각하고, 같은 파일 끝 `## 반영` 절에 `반영(plan §/Task N)` 또는 `기각(근거)` 1줄씩 적는다. 두 전문가 패스 중 하나라도 plan.md 를 바꿨으면 위 두 스크립트(check-plan-predispatch.sh · check-plan-boundary.sh)를 **이 패스 뒤에 한 번만** 다시 실행한 뒤 plan-reviewer 를 부른다(입력은 그대로 — 전문가 파일을 넘기지 않는다).
- **모델 불가·산출 없음**: opus 를 쓸 수 없으면 같은 에이전트를 가용 모델 override 로 다시 dispatch 한다(부모가 대신 검토하지 않는다). `experts/arch.md` 가 만들어지지 않았으면 1회 다시 부르고, 그래도 없으면 dispatch-log 에 `| <N> | <ISO-8601> | arch-expert | arch-designer-ko | 산출 없음 | - |` 를 남기고 plan-reviewer 로 진행한다.
- **기록** (결과 칸에 `DONE`·`IMPL` 을 쓰지 않는다 — 재개 판독기 `reconcile-check.sh` 가 구현 증거로 읽는다): dispatch-log 에 `| <N> | <ISO-8601> | arch-expert | arch-designer-ko | 반영 | experts/arch.md (지적 N · 반영 N · 기각 N) |`. 발동하지 않으면 `| <N> | <ISO-8601> | arch-expert | - | SKIP | 구조 표면 없음 |` 1행.

### 비-batch — plan-reviewer dispatch

자체 검토 통과 후 `specops-ko:plan-reviewer-ko` 서브에이전트를 dispatch해 plan.md를 독립 검증한다. 이 리뷰어는 **spec 대조 2관점(스펙 커버리지·스펙 정합) + 엔지니어링 4관점(TDD·플레이스홀더·파일경계·타입일관성)** 6관점을 fresh 시각으로 수행한다 (구 general-purpose Plan Document Reviewer 의 spec 대조 역할을 전용 Evaluator 로 흡수 — 20260723, dispatch 1회로 단일화).

**dispatch:** `Agent` 도구, `subagent_type: "specops-ko:plan-reviewer-ko"`
입력: `.specops/<FID>/spec.md`(요구 원본) + `.specops/<FID>/plan.md`(검토 대상) + `.specops/<FID>/plan-boundary.txt`(경계 대조 입력) 경로

**판정 처리 (cap=2):**

`PLAN-REVIEW-RESULT: FAIL` — Critical/Important 이슈 발견 시 **HARD GATE 발동**: decomposing-ko 진입 차단 + plan.md 수정 요청.

| 결과 | 처리 |
|---|---|
| `PLAN-REVIEW-RESULT: PASS` | `## 실행 전환` 진행 (decomposing-ko 허용) |
| `PLAN-REVIEW-RESULT: FAIL` (초기 시도) | **decomposing-ko 진입 차단** — 이슈 목록 기반 plan.md 수정 → 재dispatch (1회 허용) |
| `PLAN-REVIEW-RESULT: FAIL` (재dispatch 후 재검토) | 아래 「cap 초과 — 단일 대화형」(`§auto` 면 [§auto 모드]) |

**cap 초과 — 단일 대화형** (`§auto`·`§batch` 아님): 반환 전문을 `.specops/<FID>/plan-review.md` 에 저장하고 [§auto 모드] 와 같은 grep 으로 Critical=0 을 판정한다(눈으로 세지 않는다).
- Critical=0 이고 남은 Important 를 **모두** plan.md 에 반영할 수 있으면 반영 후 3회차 리뷰 없이 진행 — 기록: `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dev-decision.sh add <FID> skip "plan-reviewer 3회차 생략 — Important <N>건 반영" "<요지>"`(PR 직전 보고에 보인다) · dispatch-log 판정 칸 `FAIL→진행(Critical 0 · Important <N> 반영)` · 비고 칸 `Critical: 0건 · Important: <N>건 반영`. 외부 critic 은 반영 **후** 1회.
- 아니면 `HARD-GATE: plan-reviewer cap 초과 — 사용자 결정 필요` 로 중단 — Critical≥1 · `Critical:` 줄 없음 · spec·AC 변경이나 사용자가 골라야 하는 Important · 애매함.

**Evaluator 모델 불가 fallback (P1 — 20260718)**: `plan-reviewer-ko`(opus 고정)도 모델 불가(한도·접근) 시 dispatch 가 실패한다. 이때 **부모 self-review 로 후퇴 금지** — 같은 `plan-reviewer-ko` 를 **독립 서브에이전트로 가용 모델 override 재dispatch**(Agent `model` 인자)해 Generator↔Evaluator 분리를 보존한다. dispatch-log 에 `plan-reviewer-ko (모델 fallback: <지정 모델> 불가 → <모델>)` 기록. 상세 규약은 `skills/implementing-ko/SKILL.md` "Evaluator 모델 불가 fallback" 참조(동일 원칙).

**[§auto 모드]** (`grep -qE '^\*\*§auto\*\*:[[:space:]]*true' .specops/<FID>/spec.md`):
cap 초과 시 리뷰어 반환 전문을 `.specops/<FID>/plan-review.md` 에 저장하고 **그 파일을 기계 판정**한다 — `grep -qE '^Critical:[[:space:]]*0([^0-9]|$)' .specops/<FID>/plan-review.md` 가 맞을 때만 Critical=0 이다(plan-reviewer 는 `Critical: <N>건` 줄을 낸다. 줄이 없거나 형식이 다르면 Critical 이 있는 것으로 본다). 눈으로 세지 않는다 — 무인에서 오판하면 Critical plan 이 자동 통과하고 사람이 없다. **Critical≥1 이면 무인이라도 `HARD-GATE: plan-reviewer Critical cap — 사용자 결정` 으로 정지**한다(`/start-all` Phase 2·2.5-D 와 같은 판정 — 진입 경로에 따라 답이 달라지지 않는다). **Critical=0(Important 만 남음)** 일 때만 HARD GATE 대신 **자동 통과** (가역 — plan은 verify/review 단계가 검증). dispatch-log.md에 "plan-reviewer cap 초과(Important <N>건) → §auto 자동통과" 기록. cap 초과 자동통과 **직전** `advisor()` 1회 자문 시도 → 권고 요지를 dispatch-log.md에 기록(보조 입력 — plan 판정 권한 없음, 가역 게이트라 자동 진행). `advisor()` 미연결 시 자문 없이 자동통과 진행(graceful fallback — 하드 의존 금지).

**dispatch-log.md 기록** (`.specops/<FID>/dispatch-log.md` — 부재 시 `templates/dispatch-log.md` 복사):

| <N> | <ISO-8601> | plan-reviewer | plan-reviewer-ko | PASS\|FAIL | - |

### 외부 critic 병행 (advisory — multimodel-critic)

**비-batch만**: plan-reviewer **최종 PASS 직후** 1회 (cap 초과 자동통과 경로 포함 — §auto·단일 대화형 모두. 자동통과도 진행 확정이므로 동일 호출. FAIL 루프 중에는 미호출):

1. `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/critic-ask.sh "${CLAUDE_PLUGIN_ROOT}"/templates/critic-prompt-plan.md --files .specops/<FID>/plan.md`
2. 의견 출력 시 (`CRITIC[<provider>]:`): 요지 1~2문장을 plan.md §8 에 행 추가 —
   `| <ts> | 외부 critic (<provider>) | <요지> | 참고 | §N |`
3. `CRITIC: SKIP/FAIL` → dispatch-log 1줄만 기록 (plan.md §8 미기재 — 잡음 방지)
4. **advisory**: 외부 의견은 참고 입력 — PASS/FAIL **판정 권한 없음** (판정은 plan-reviewer 소관)

**§batch**: per-FR critic **미호출**. `/start-all` Phase 2 batch plan-review **PASS 후** 오케스트레이터가 대표 plan 1개 또는 전 plan 경로로 critic **최대 1회**(또는 dispatch-log에 `CRITIC: SKIP (batch defer)`). 판정 권한 없음은 동일.

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 태스크 설명은 **근거 명시**. "왜 이 파일을 먼저?" |
| 2 **문지기** | 파괴적 작업(DB 마이그레이션·프로덕션 설정 변경)은 **별도 태스크 + 명시 확인** |
| 3 **깊이** | 스펙이 모호하면 planning 중단 → specifying 복귀 |
| 4 **주권 존중** | 핵심 결정점은 사용자 리뷰 요청 |
| 5 **한계 고백** | "이 태스크는 가정 기반" 태그 |

## 실행 전환

플랜 저장 후 실행 방식 선택 제시:

> "플랜을 `.specops/<FID>/plan.md`에 저장했습니다. 두 가지 실행 옵션:
>
> **1. 서브에이전트 주도 (권장)** — 태스크별 fresh 서브에이전트 dispatch, 태스크 간 리뷰, 빠른 반복
>
> **2. 인라인 실행** — 본 세션에서 배치 실행, 체크포인트마다 리뷰
>
> 어느 쪽으로 할까요?"

**서브에이전트 주도 선택 시**:
- 필수 하위 스킬: `specops-ko:implementing-ko`
- 태스크별 fresh 서브에이전트 + 2단계 리뷰

**인라인 실행 선택 시**:
- 하위 스킬: `specops-ko:decomposing-ko`로 태스크 분할 후 인라인 순차 실행
- 체크포인트마다 리뷰

## plan.md 필수 섹션

plan.md 작성 시 `templates/plan.md` 구조를 **정확히** 따른다. 특히 아래 두 섹션은 **반드시** 포함:

1. **`## 7. 자체 검토 (5원칙 체크리스트)`** — 체크리스트 4항목 모두 기재
2. **`## 8. Advisor 협의 기록`** — advisor() 호출 내역 또는 "해당 없음 — 본 plan 작성 중 불확실 지점 없음"

`## 8. Advisor 협의 기록` 부재 시 R-5 거버넌스 규칙이 트리거된다. 반드시 작성할 것.

## 참조

- `templates/plan.md` — 작성 포맷 (**정확히 따를 것**, 특히 §8 Advisor 협의 기록 섹션)
- `templates/tasks.md` — 태스크 분해 포맷
- `skills/structured-artifacts-ko/SKILL.md` — .specops/<FID>/ 아티팩트 경로 규약
- `skills/karpathy-ko/SKILL.md` — Think·Simplicity·Surgical·Goal 4원칙 (cross-cutting)

## 공유 유틸 창발 중복 경고 (P2 — 20260718 test2 회고)

foundation-manifest 는 **사전 선언된** 공통부 재사용만 게이트한다 — 그런데 **여러 형제 FID 가 각자 만드는 유틸이 창발적으로 중복**되는 건 못 잡는다(전방 계약 ≠ 후방 탐지). test2 실측: `mask_block_comments`·`PRUNE`/`ANALYZE_EXT` 리터럴이 **4~5 FID 에 복제**돼 "sysprobe-lib 승격" backlog 가 반복 발생했다.

**plan 작성 시 판별**: 이 플랜의 태스크가 **재사용 가능한 유틸리티**(파싱 헬퍼·공유 상수·전처리 함수 등 — 이 기능 고유 로직이 아니라 형제 기능도 쓸 만한 것)를 만드는가?

- **그렇다** → 그 로직을 **공통 lib**(예: `<project>/lib` · foundation 모듈)에 배치하도록 플랜에 명시하고, `.specops/memory/foundation-manifest.md` 에 등재 후보로 기재한다. per-FID 인라인 복제 금지.
- **판단 애매** → plan.md 에 `공유후보: <유틸명> (창발 중복 리스크)` 1줄 기록 → 리뷰·후속 FID 가 인지. **advisor 자문 권장**(조기 분리 가치 — test2 learning: advisor 가 '조합 vs 재구현' 조기 포착).

**하드 게이트 아님** — 판단 도구다. 목적은 "3번째 복제가 생기기 전에 승격"이지 차단이 아니다.

## foundation 분기 — manifest 산출 지시

spec.md §유형=`foundation` 인 플랜은 **반드시** 태스크 목록 마지막에 다음 태스크를 포함한다:

> **[foundation 전용 마지막 태스크]** 공통부 구현 완료 후 `templates/foundation-manifest.md` 를 기반으로 실제 모듈 경로·역할을 채워 `.specops/memory/foundation-manifest.md` 에 저장한다.
>
> 템플릿의 모듈 5행(라우팅·인증·레이아웃·공통 컴포넌트·DB 스키마)과 기술 스택 3항목은 **웹/풀스택 기준 예시**다. **프로젝트 유형에 맞게 교체하고 해당 없는 행·항목은 삭제**한다 — CLI/라이브러리 foundation 이면 인자 파싱·로깅·설정 로더 등 실제 제공 모듈로 바꾼다. placeholder(`<경로>`·`<확정된 프레임워크>`)를 그대로 남기면 `check-foundation-manifest.sh` 가 미채움으로 판정해 `VERIFY: FAIL` 이 난다(실측 20260806: 무관 행 방치가 모델의 자연스러운 선택이라 이 안내가 없으면 CLI foundation 이 반복 실패한다).

> **manifest 가 이미 있으면 덮어쓰지 않는다** — 기존 표에 행을 더하거나 고친다(verify 가 사라진 모듈명을 경고한다). 표의 경로는 저장소에 **실재**해야 한다 — 하나도 없으면 `VERIFY: FAIL`.

이 태스크가 없으면 후속 `/start <기능>` 시 decomposing-ko HARD GATE 가 `foundation-manifest.md` 를 발견하지 못해 재사용 게이트가 동작하지 않는다.

**강제**: 이는 산문 권고가 아니다 — `verifying-evidence-ko` 의 **foundation manifest 산출 게이트**가 §유형=foundation 인 FID 완료 시 `.specops/memory/foundation-manifest.md` 존재+채움을 검사하여 누락 시 `VERIFY: FAIL` 로 완료를 차단한다(태스크 누락·파일 미작성 모두). 즉 manifest 없이는 foundation lifecycle 이 완료 선언될 수 없다.

## session-progress append (v0.4-pre P1 신설)

플랜 저장 직후, decomposing-ko 호출 직전에:
```
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /plan 완료 "plan.md"
```

## Handoff 기록 (다음 skill 진입 직전 필수)

`decomposing-ko` 호출 직전 `.specops/<FID>/handoffs/planning.md` 작성 (structured-artifacts-ko 규약 4필드: Decided/Rejected/Risks/Remaining).

## 다음 skill

플랜 저장 + session-progress append + 실행 방식 결정 + handoff.md 기록 후 즉시 호출:

```
Skill: specops-ko:decomposing-ko
```

decomposing-ko가 플랜을 실행 가능한 태스크 리스트로 분해. 그 후 `specops-ko:implementing-ko`로 전환.
