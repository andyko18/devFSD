---
name: receiving-code-review-ko
description: 코드 리뷰 피드백을 수령한 직후, 제안 구현 전 사용 — 기술적 엄밀성과 검증을 요구하며 수행적 동의·맹목적 구현을 금지
layer: 2
reference_upstream: obra/superpowers@v5.0.7 skills/receiving-code-review/SKILL.md
  - obra/superpowers@v5.0.7 skills/receiving-code-review/SKILL.md
  - skills/receiving-code-review-ko/SKILL.md
specops_version: 2.13.0
used_by: requesting-code-review-ko (chain 진입), security-review-ko (단일 모드 chain 출구), /start-all (batch 모드 BATCH-REVIEW-DONE halt 진출)
---

# Engine 스킬 — 코드 리뷰 수용 (receiving-code-review)

## 개요

코드 리뷰는 **감정적 수행**이 아니라 **기술적 평가**를 요구한다.

**핵심 원칙**: **구현 전 검증. 가정 전 질문. 사회적 편안함보다 기술적 정확성.**

## 대응 패턴

```
코드 리뷰 피드백 수령 시:

1. READ — 반응 없이 피드백 완독
2. UNDERSTAND — 요구사항을 자기 말로 재진술 (또는 질문)
3. VERIFY — 코드베이스 현실과 대조 확인
4. EVALUATE — 이 코드베이스에 기술적으로 타당한가?
5. RESPOND — 기술적 인정 또는 근거 있는 pushback
6. IMPLEMENT — 한 번에 한 항목, 각각 테스트
```

## 금지 응답

**절대 금지**:
- "당신이 완전히 맞습니다!" (CLAUDE.md 명시 위반)
- "훌륭한 지적!" / "좋은 피드백!" (수행적)
- "지금 구현하겠습니다" (검증 전)

**대신**:
- 기술 요구사항 재진술
- 명확화 질문
- 틀렸으면 기술 근거로 pushback
- 그냥 작업 시작 (말보다 행동)

## 불명확한 피드백 처리

> **lifecycle chain 안(개발 구간)에서는 `skills/implementing-ko/dev-autonomy.md` 가 우선한다** — 아래의 "명확화 요청"·"할까요?"·"먼저 논의" 는 사용자에게 묻는 대신 그 문서의 기준으로 정하고 `dev-decision.sh add` 로 기록한다(계약 안이면 처리, 밖이면 `backlog`). 사용자에게 묻는 것은 그 문서 §3 의 경우뿐이다 — 사용자의 이전 결정(설계 승인·AC)을 뒤집어야 하는 지적은 구현하지 않고 `backlog` 로 넘긴다. chain 밖에서 리뷰를 받았을 때는 아래 그대로다.

```
어떤 항목이든 불명확하면:
  중단 — 아무것도 구현하지 말 것
  불명확 항목에 명확화 요청

이유: 항목들이 연관될 수 있음. 부분 이해 = 잘못된 구현.
```

**예시**:
```
사용자 파트너: "1-6 고쳐"
1,2,3,6은 이해. 4,5는 불명확.

❌ 잘못: 1,2,3,6 지금 구현, 4,5는 나중에 질문
✅ 올바름: "1,2,3,6은 이해했습니다. 진행 전 4,5에 명확화 필요합니다."
```

## 소스별 처리

### 사용자 파트너로부터

- **신뢰** — 이해 후 구현
- 범위 불명확하면 **여전히 질문**
- **수행적 동의 금지**
- 행동으로 건너뛰거나 기술적 인정

### 외부 리뷰어로부터

```
구현 전:
  1. 확인: 이 코드베이스에 기술적으로 올바른가?
  2. 확인: 기존 기능을 깨는가?
  3. 확인: 현재 구현의 이유?
  4. 확인: 모든 플랫폼·버전에서 동작?
  5. 확인: 리뷰어가 전체 맥락을 이해?

제안이 틀려 보이면:
  기술 근거로 pushback

쉽게 검증할 수 없으면:
  그렇게 말하라: "[X] 없이는 검증 불가. [조사/질문/진행] 할까요?"

사용자 파트너의 이전 결정과 충돌하면:
  멈추고 사용자 파트너와 먼저 논의
```

**사용자 파트너의 규칙**: "외부 피드백 — 의심하되 꼼꼼히 확인"

## "전문적" 기능에 대한 YAGNI 체크

```
리뷰어가 "제대로 구현하자" 제안 시:
  코드베이스를 grep — 실제 사용 여부 확인

  미사용이면: "이 엔드포인트는 호출되지 않음. 제거(YAGNI)?"
  사용 중이면: 그때 제대로 구현
```

**사용자 파트너의 규칙**: "당신과 리뷰어 모두 내게 보고한다. 우리가 이 기능이 필요 없다면, 추가하지 말라."

## 구현 순서

```
다항목 피드백:
  1. 불명확한 것부터 명확화
  2. 이 순서로 구현:
     - 차단 이슈 (파손, 보안)
     - 단순 수정 (오타, 임포트)
     - 복잡 수정 (리팩터링, 로직)
  3. 각 수정 개별 테스트
  4. 회귀 없음 검증
```

## Pushback 시점

다음 경우 pushback:
- 제안이 기존 기능을 깸
- 리뷰어가 전체 맥락 결여
- YAGNI 위반 (미사용 기능)
- 이 스택에 기술적으로 부정확
- 레거시·호환성 이유 존재
- 사용자 파트너의 아키텍처 결정과 충돌

**Pushback 방법**:
- 방어가 아닌 **기술 근거**로
- 구체 질문
- 동작하는 테스트/코드 참조
- 아키텍처 문제면 **사용자 파트너 개입**

## 올바른 피드백 인정

피드백이 맞을 때:
```
✅ "수정됨. [무엇이 바뀌었는지 간략 설명]"
✅ "좋은 캐치 — [구체 이슈]. [위치]에서 수정."
✅ [그냥 고치고 코드로 보여주기]

❌ "당신이 완전히 맞습니다!"
❌ "훌륭한 지적!"
❌ "잡아주셔서 감사!"
❌ "[무엇이든] 감사합니다"
❌ 어떤 감사 표현이라도
```

**감사 금지 이유**: 행동이 말함. 그냥 고쳐라. 코드 자체가 당신이 피드백을 들었음을 보여준다.

**"감사"라고 쓰려 할 때**: **삭제**. 대신 수정 내용을 진술.

## Pushback이 틀렸을 때 우아한 정정

Pushback했는데 당신이 틀렸을 때:
```
✅ "당신이 맞았습니다 — [X]를 확인했고 [Y]가 맞습니다. 지금 구현합니다."
✅ "검증했고 당신 말이 맞습니다. 제 초기 이해가 [이유] 때문에 틀렸습니다. 수정 중."

❌ 긴 사과
❌ pushback 이유 방어
❌ 과도한 설명
```

정정 사실을 진술하고 넘어간다.

## 흔한 실수

| 실수 | 수정 |
|---|---|
| 수행적 동의 | 요구사항 진술 또는 그냥 행동 |
| 맹목적 구현 | 코드베이스 먼저 검증 |
| 테스트 없이 배치 | 한 번에 하나, 각 테스트 |
| 리뷰어가 맞다고 가정 | 파손 여부 확인 |
| Pushback 회피 | 기술적 정확성 > 편안함 |
| 부분 구현 | 먼저 모든 항목 명확화 |
| 검증 불가 + 진행 | 한계 진술, 방향 요청 |

## GitHub 스레드 답글

GitHub 인라인 리뷰 코멘트 답글은 **스레드 내**에서 (`gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies`), 최상위 PR 코멘트로가 아니라.

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 구현 결정 이유를 **인라인 답글에 기록**. "수용" vs "pushback + 근거" |
| 2 **문지기** | 수행적 동의 감지 시 즉시 중단. 감사 표현 삭제 |
| 3 **깊이** | 부분 이해로 구현 금지. 항상 전체 명확화 먼저 |
| 4 **주권 존중** | 사용자 파트너 결정과 충돌 시 **사용자 파트너 개입 요청** |
| 5 **한계 고백** | "검증 불가" 항목은 그대로 선언 |

## 결론

**외부 피드백 = 평가할 제안이지 따를 명령이 아니다.**

검증. 질문. **그런 다음** 구현.

수행적 동의 없음. 기술적 엄밀성 항상.

## 참조

- specops-ko 한국어 선례: `skills/receiving-code-review-ko/SKILL.md`

## session-progress append (v0.4-pre P1 신설)

리뷰 피드백 수용·구현 완료 직후:
```
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /receive-review 완료 "Critical N건 / Important N건 / fix 라운드 N회"
```

## 다음 skill

피드백 구현 완료 + session-progress append 후:

**[review-skip 통과]** `.specops/<FID>/review-skip.md`가 있고 `review-request.md`가 없으면(end-loaded 또는 lite batch-review-skip):
- 피드백 루프 **없음** — Critical/Important 수정 단계 skip
- session-progress: `/receive-review 완료 "review-skip 통과 (<사유 1줄>)"`
- **batch** → `BATCH-REVIEW-DONE: <FID>` + halt
- **단일** → 즉시 `security-review-ko`

**[batch 모드 분기]** 먼저 spec.md `**§batch**` 라벨 감지 확인:

```bash
grep -qE '^\*\*§batch\*\*:' .specops/<FID>/spec.md && echo "BATCH" || echo "SINGLE"
```

- **batch 모드** (`**§batch**` 라벨 감지) → `BATCH-REVIEW-DONE: <FID>` 출력 + **halt**. security-review-ko(및 하위 chain) 미호출. `/start-all` 오케스트레이터가 다음 단계를 제어한다

**[단일 모드]** (`**§batch**` 라벨 없는 경우) — **리뷰 이슈가 모두 해결된 상태** → 즉시 호출:

```
Skill: devfsd:security-review-ko
```

security-review-ko가 SAST 보안 스캔을 점검하고 → integration-test-ko → performance-test-ko → PR 생성 게이트로 chain한다.

- **Important 이슈 수정 필요** → `devfsd:implementing-ko`로 복귀 (수정 태스크를 새로 dispatch)
- **재검증 필요** → `devfsd:verifying-evidence-ko` 재호출

본 receiving-code-review-ko는 단일 모드에서 **security-review-ko 이외의 다음 스킬을 호출하지 않는다** (수정 루프 복귀 및 batch halt 제외).
