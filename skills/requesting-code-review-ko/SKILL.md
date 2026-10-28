---
name: requesting-code-review-ko
description: 태스크 완료, 주요 기능 구현, 머지 전 사용 — 결과물이 요구를 충족하는지 외부 리뷰어에게 검증 요청
layer: 2
reference_upstream: obra/superpowers@v5.0.7 skills/requesting-code-review/SKILL.md
specops_version: 2.18.0
used_by: verifying-evidence-ko (chain 진입), receiving-code-review-ko (chain 출구)
---

# Engine 스킬 — 코드 리뷰 요청 (requesting-code-review)

코드 리뷰어 서브에이전트를 **이슈가 누적되기 전에** dispatch. 리뷰어는 당신의 세션 히스토리가 아니라 **정확히 조립된 평가용 컨텍스트**를 받는다. 리뷰어를 결과물에 집중시키고, 당신 자신의 컨텍스트도 계속된 작업용으로 보존한다.

**핵심 원칙**: **일찍 리뷰, 자주 리뷰.** (단, implementing이 이미 FID 전체 B·C를 끝낸 end-loaded면 **중복 리뷰 생략** — 아래 Step 0)

## Step 0 — end-loaded 중복 skip (필수 분기)

`verifying-evidence-ko` 직후 진입 시 **먼저** 판정:

```bash
FID=...   # 활성 FID
# tasks.md YAML 루트 review_mode (부재=end-loaded)
grep -E '^review_mode:' ".specops/$FID/tasks.md" || true
```

**SKIP 조건** (모두 충족):
1. `review_mode`가 `per-task`가 **아님** (부재·`end-loaded` 포함)
2. tasks.md의 **모든** task id에 대해 `.specops/<FID>/reviews/<tid>-B-report.md` **와** `<tid>-C-report.md` 존재
3. (권장) `dispatch-log.md`에 해당 tid의 B/C PASS 행이 있음
4. **신선도** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-review-fresh.sh <FID>` 가 rc 0(FRESH). 리뷰 **이후** 코드가 바뀌었으면(security/integration/performance FAIL 을 고친 재진입 등) rc 1(STALE)이고, 판정 불가는 rc 2 — 둘 다 SKIP **불가**다. 리포트가 *존재*한다는 사실만으로는 수정 커밋이 리뷰받았다는 증거가 아니다.

**SKIP 시 동작**:
1. `.specops/<FID>/review-skip.md` 작성 — 첫 줄에 `end-loaded: Phase B/C already covered full FID diff` (사유 필수·비공백)
2. session-progress: `/request-review 완료 "review-skip.md (end-loaded)"`
3. **외부 code-reviewer Agent dispatch 하지 않음**
4. 즉시 `receiving-code-review-ko` 호출 (receiving이 skip을 통과시켜 security로)

lite+단일태스크 `batch-review-skip` 경로와 **별개**다. end-loaded skip은 risk-profile allowlist와 무관하며, `batch-state.sh`가 B/C report 존재로 검증한다.

조건 미충족 → 아래 정상 리뷰 요청 절차. (STALE 재진입이면 `review-skip.md` 가 남아 있어도 **새로 리뷰**하고, 낡은 `review-skip.md` 는 `review-skip.md.stale-<날짜>` 로 옮겨 둔다 — 하류 `receiving-code-review-ko` 가 낡은 skip 을 통과시키지 않도록.)

## 리뷰 요청 시점

**필수**:
- 서브에이전트 주도 개발의 **각 태스크 후**
- 주요 기능 완료 후
- main 머지 전

**선택이지만 가치 있음**:
- 막혔을 때 (새 관점)
- 리팩터링 전 (기준선 체크)
- 복잡한 버그 픽스 후

## 요청 방법

### 1. git SHA 획득

```bash
BASE_SHA=$(git rev-parse HEAD~1)  # 또는 origin/main
HEAD_SHA=$(git rev-parse HEAD)
```

> **[batch 모드 — per-FR base 격리]** `.specops/<FID>/spec.md` 에 `**§batch**` 라벨이면, 위 `HEAD~1` 은 **쓰지 않는다**. batch 는 공유 `feat/<BATCH_ID>` 브랜치에 여러 FR 커밋이 누적되므로, `HEAD~1`·`git log|grep "Task 1"|head -1` 은 **직전 FR 의 변경까지 diff 에 끌어들여** review.diff 를 뭉갠다(이름만 per-FID, 내용은 blended). 오케스트레이터(`/start-all` Phase 3)가 각 FR 구현 **직전** 기록한 base 를 읽는다:
> ```bash
> if grep -qE '^\*\*§batch\*\*:' ".specops/$FID/spec.md" 2>/dev/null && [ -f ".specops/$FID/review-base.sha" ]; then
>   BASE_SHA=$(cat ".specops/$FID/review-base.sha")   # 이 FR 구현 시작 시점 HEAD — per-FR 격리
> fi
> ```
> `review-base.sha` 부재 시(단일 모드·파일 미기록)는 위 기본 `HEAD~1` 로 fallback.

### 외부 모델 의견 병행 (advisory — multimodel-critic)

리뷰어 dispatch **전** 1회:

1. `git diff <BASE_SHA>..<HEAD_SHA> > .specops/<FID>/reviews/review.diff`
   - diff 에 비밀 (자격증명·.env·키) 포함 의심 시 위탁 생략 — `외부 critic: SKIP (비밀 보호)` 기재 (외부 모델 전송 = 외부 송신)
2. `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/critic-ask.sh "${CLAUDE_PLUGIN_ROOT}"/templates/critic-prompt-diff.md --files .specops/<FID>/reviews/review.diff`
3. 의견 출력 시 `.specops/<FID>/reviews/external-critic.md` 저장 → 리뷰어 dispatch 프롬프트에 **경로만** 추가 (file-based-communication)
4. `CRITIC: SKIP/FAIL` → 미첨부 + review-request.md 에 `외부 critic: SKIP (<사유>)` 1줄 (한계 고백)
5. **advisory**: 외부 의견은 **판정 권한 없음** — Claude 리뷰어가 비판적으로 평가할 입력 (receiving-code-review 규약 적용)

### 2. 코드 리뷰어 서브에이전트 dispatch

`Agent` 도구로 `code-reviewer`(또는 `oh-my-claudecode:code-reviewer`) 서브에이전트 호출. 다음 정보를 **전체 텍스트**로 포함:

**필수 필드**:
- `WHAT_WAS_IMPLEMENTED` — 방금 구축한 것
- `PLAN_OR_REQUIREMENTS` — 무엇을 해야 했는지 (플랜·요구사항)
- `BASE_SHA` — 시작 커밋
- `HEAD_SHA` — 종료 커밋
- `DESCRIPTION` — 간략 요약

### 3. 피드백 대응

- **Critical 이슈**: **즉시** 수정
- **Important 이슈**: 다음 단계 진행 **전에** 수정
- **Minor 이슈**: 기록 후 나중에
- **리뷰어가 틀렸으면**: 근거와 함께 pushback (본 스킬 `## 리뷰어가 틀렸을 때` 참조)

## 예시

```
[Task 2 방금 완료: 검증 함수 추가]

당신: 진행 전 코드 리뷰를 요청합니다.

BASE_SHA=$(git log --oneline | grep "Task 1" | head -1 | awk '{print $1}')  # 단일 모드 예시 — batch 는 §1 [batch 모드] 분기(review-base.sha) 사용
HEAD_SHA=$(git rev-parse HEAD)

[code-reviewer 서브에이전트 dispatch]
  WHAT_WAS_IMPLEMENTED: 대화 인덱스 검증·수리 함수
  PLAN_OR_REQUIREMENTS: docs/plans/deployment-plan.md Task 2
  BASE_SHA: a7981ec
  HEAD_SHA: 3df7661
  DESCRIPTION: verifyIndex() + repairIndex() 추가, 4 이슈 타입

[서브에이전트 반환]:
  강점: 깔끔한 아키텍처, 실제 테스트
  이슈:
    Important: 진행 표시기 누락
    Minor: 보고 간격 100이 매직 넘버
  평가: 진행 가능

당신: [진행 표시기 수정]
[Task 3 진행]
```

## 워크플로 통합

**서브에이전트 주도 개발**:
- **각 태스크 후** 리뷰
- 복합되기 전 이슈 포착
- 다음 태스크 전 수정

**인라인 실행**:
- **각 배치(3 태스크) 후** 리뷰
- 피드백 받고 적용, 계속

**애드혹 개발**:
- 머지 전 리뷰
- 막혔을 때 리뷰

## 레드 플래그

**절대 금지**:
- "간단하니까" 리뷰 생략
- Critical 이슈 무시
- Important 이슈 미해결로 진행
- 타당한 기술 피드백에 논쟁

**리뷰어가 틀렸을 때**:
- 기술 근거와 함께 pushback
- 동작을 증명하는 코드·테스트 제시
- 명확화 요청

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 리뷰 요청 payload 전문을 `.specops/<FID>/review-request.md`에 보존(skip 시 `review-skip.md`) |
| 2 **문지기** | Critical 미해결 상태로 머지 불가. **무단** 리뷰 생략 불가 — end-loaded/lite skip만 산출물·메타로 허용 |
| 3 **깊이** | "간단해서 리뷰 불필요"는 거부 신호. 작은 PR도 리뷰(단 Step 0 end-loaded는 이미 B·C 완료) |
| 4 **주권 존중** | 사용자가 리뷰 생략을 명시 지시하지 않는 한 항상 리뷰 요청(단 Step 0 end-loaded·batch lite skip 예외) |
| 5 **한계 고백** | 리뷰어 컨텍스트 부족 감지 시 "이 부분은 리뷰 범위 밖" 기록 |

## 참조

- 리뷰어 에이전트: `agents/code-reviewer-ko.md` (Phase C — `subagent_type: "devfsd:code-reviewer-ko"`)
- specops-ko 한국어 선례: `skills/requesting-code-review-ko/SKILL.md`

## session-progress append (v0.4-pre P1 신설)

review-request 작성 + 외부 리뷰어 dispatch 후(또는 Step 0 skip 후), receiving-code-review-ko 호출 직전에:
```
# 정상
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /request-review 완료 "review-request.md, 외부 reviewer dispatch"
# Step 0 end-loaded skip
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /request-review 완료 "review-skip.md (end-loaded)"
```

## 다음 skill

리뷰 피드백 수령 + session-progress append 직후 즉시 호출:

```
Skill: devfsd:receiving-code-review-ko
```

receiving-code-review-ko가 피드백을 어떻게 수용·검증·구현할지 강제한다. 본 requesting-code-review-ko는 **receiving-code-review-ko 이외의 다음 스킬을 호출하지 않는다**.
