---
name: using-specops-ko
description: 모든 대화 시작 시 활성 — specops-ko 한국어 자율 Lifecycle 메타 skill. 사용자 입력에서 기능 요청 신호 감지 시 devfsd:specifying-ko 자동 호출 강제 (5원칙 주입)
layer: 1
reference_upstream: obra/superpowers@v5.0.7 skills/using-superpowers/SKILL.md
specops_version: 2.20.0
used_by: 모든 Claude Code 세션 (SessionStart 자동 주입)
---

# Harness 메타 스킬 — specops-ko 자율 Lifecycle 진입

<SUBAGENT-STOP>
서브에이전트로 dispatch되어 특정 task를 실행 중이라면 본 skill 건너뜀.
</SUBAGENT-STOP>

<EXTREMELY-IMPORTANT>
1% 가능성이라도 specops-ko Lifecycle skill이 적용될 수 있다면 **반드시** 호출한다.

특히 사용자 입력이 다음 신호를 포함하면 즉시 `devfsd:specifying-ko` 호출:

**[신규 신호]** — `maintenance flag = false`:
- "X 기능을 만들고 싶어"
- "Y CLI / API / 모듈 신규"
- "Z를 구현해줘"
- "/start <기능>" 슬래시
- 명확한 신규 산출물 요청

**[유지보수 신호]** (Phase D — 신규 추가) — `maintenance flag = true`:
- "X 버그 고쳐줘 / 수정해줘"
- "Y 리팩터링 해줘"
- "Z 개선 / 변경"
- "/maintain <대상>" 슬래시

> **배제 조건** (완주율 개선 — 20260713-signal-coding-gate): 위 신호가 있어도, 요청이 **명백히 repo 밖 산출물**만 만드는 경우에는 chain 진입을 보류한다 — PPT·Excel·외부 기획서/요구사항 정의서 · 데이터 분석 보고 · 단순 질의응답. 이런 작업은 **테스트할 코드가 없어서** 후속 단계(clarify·plan·decompose·implement·verify)가 전부 공회전하고, 사용자를 도구 밖으로 밀어낸다 (실측: `sales-ppt` PPT 12장 · `iken-webapp` 요구사항 133건 — 둘 다 spec 에서 사망, 후자는 사용자가 Excel 로 이탈).
>
> **repo 내 파일**(코드·설정·스크립트·스키마 **및 README·CLAUDE.md 등 문서**)을 만들거나 고치면 **진입한다** — 문서만 고치려다 코드까지 건드리는 일이 흔하다.
>
> **애매하면 호출한다.** 배제는 명백할 때만이다 — 진짜 코딩 작업을 놓치는 것(false-negative)이 그 반대보다 훨씬 나쁘다.
>
> **배제 시 1줄 고지**: "(코딩 작업이 아니라 판단해 lifecycle 을 진입하지 않았습니다. 필요하면 `/start <설명>` 으로 강제 진입할 수 있습니다.)" — `/start` 슬래시는 무조건 직행하므로(`commands/start.md` SoT), 판정이 틀렸을 때 사용자가 즉시 뒤집을 수 있다.

> **경계**: `/start <인자>` 슬래시의 동작 정의는 `commands/start.md` 가 Source of Truth. 본 메타 skill 은 **자연어 입력** 의 신호 감지만 책임한다. `/start` 에 붙은 인자 내용이 "기능 설명으로 보이지 않는다"는 이유로 specifying-ko 호출을 보류하는 2차 판단은 `commands/start.md` 안티패턴 "인자 내용 2차 판단" 에 의해 금지 — 슬래시 진입은 무조건 specifying-ko 로 직행.

> **lite 추론 금지**: "가볍게", "토큰 아끼고", "짧게 해줘" 등 자연어로 `/start-lite`·`/maintain-lite`·`/quick-fix`를 **추론하지 않는다**. 셋 다 슬래시 전용(`commands/`의 각 파일이 SoT). 자연어 신규/유지보수는 기존대로 `/start`·`/maintain` 경로(또는 풀 chain)만.

이는 협상 사항이 아니다. 합리화로 우회 금지.
</EXTREMELY-IMPORTANT>

## 우선순위

specops-ko skill은 기본 시스템 동작을 override하나 **사용자 명시 지시가 항상 최우선**:

1. CLAUDE.md / 사용자 직접 지시 (최우선)
2. specops-ko skill (기본 시스템 override)
3. 기본 시스템 프롬프트 (최하위)

CLAUDE.md가 "TDD 쓰지 말 것"이고 skill이 "항상 TDD"라면 → 사용자 지시 따름.

## 자율 Lifecycle 진입 흐름

```
[선택] /brainstorming → brainstorming-ko (아이디어 탐색·수요 검증)
    ↓ (선택적 연결 — 강제 아님)
사용자 입력
    ↓
본 메타 skill 자동 활성 (대화 시작 시)
    ↓
신호 감지?
    ↓ YES                              ↓ NO
maintenance flag 분류 (Phase D 추가)        일반 응답
    ├─ false (신규)  → specifying-ko 직행 (args 그대로)
    └─ true (유지보수) → analyzing-ko 먼저 (★ HARD GATE) → specifying-ko (args 첫 줄 "<!-- entry: maintain -->" prepend)
    ↓
spec.md + acceptance-criteria.md 작성
    ↓
HARD GATE: "spec 검토. 다음 skill(clarifying-ko) 진행? [y/n]"
    ↓ y
devfsd:clarifying-ko (skill 본문이 다음 chain 명시)
    ↓
... → planning-ko → decomposing-ko → implementing-ko (subagent dispatch) → verifying-evidence-ko → requesting-code-review-ko → receiving-code-review-ko → security-review-ko → integration-test-ko → performance-test-ko → PR
    ↓
"PR 생성? [y/n]"
```

> **기본 동작 `§일괄`**: 질문 묶음 → 승인 1회 → PR 까지 무정지. 위 단계별 확인은 `--step` — 슬래시로만(자연어 추론 금지).

**핵심**: Conductor 에이전트 없음. 본 메타 skill + 각 engine skill 본문이 chain 형성.

## maintenance flag 분류 로직 (Phase D — 신규 추가)

신호 감지 후 신규/유지보수 1 회 분류 → chain 진입 args 합성:

| flag | chain 진입 | args 합성 |
|---|---|---|
| `false` (신규) | specifying-ko 직행 | 원본 args 그대로 |
| `true` (유지보수) | **analyzing-ko 먼저** → specifying-ko (Phase C 적용 후) | args 첫 줄에 `<!-- entry: maintain -->` HTML 주석 prepend → 줄바꿈 후 원본 args |

**Phase C chain 재배선** (analyzing-ko 신설 후):
- maintenance flag = `true` → **analyzing-ko 호출** (★ HARD GATE) → analyzing-ko 가 specifying-ko 로 chain (args 그대로 전달, 첫 줄 약속어 유지)
- analyzing-ko 가 두 산출물 (current-state.md + impact-analysis.md) 산출 후 사용자 검토 통과 시 specifying-ko Step 1 [유지보수 분기] 가 두 산출물 참조

**announce 메시지** (5 원칙 1 투명성):
- `false` → "Using specifying-ko to <purpose>"
- `true` → "Using analyzing-ko (maintenance) to <purpose>"

**분류 모호** (양쪽 신호 혼재) 시 사용자에게 1 문항 확인 — "신규 / 유지보수 어느 쪽?".

## 프로젝트 최초 진입 감지 (v2.0 신규)

신호 감지 후 maintenance 분류 **전에**, 프로젝트 부트스트랩 상태를 1 회 점검한다 (clarifications.md Q5 결정 — AND 조건 + 부분 부트 감지).

| `.specops/` | `CLAUDE.md` | 안내 | 메시지 |
|---|---|---|---|
| 부재 | 부재 | **전체 안내** | "프로젝트가 초기화되지 않았습니다. `/init-project` 권장 [y/N]" |
| 존재 | 부재 | 부분 안내 | "`CLAUDE.md` 가 없습니다. `/init-project --resume` 권장 [y/N]" |
| 부재 | 존재 | 부분 안내 | "`.specops/` 가 없습니다. `/init-project --resume` 권장 [y/N]" |
| 존재 | 존재 | 안내 X | (정상 specifying-ko 진입) |

**원칙**:
- **강제 X — 1 회 1 줄 안내**. 5원칙 4 (사용자 주권) 준수.
- `y` 응답 시: `/init-project` 호출 → 부트스트랩 완료 → 사용자에게 "이제 `/start \"<기능>\"` 재실행" 안내.
- `N` 또는 무응답 시: 그대로 specifying-ko 진입 (사용자가 부트스트랩 없이 진행 의지).
- `--resume` 은 기존 파일을 보존하고 누락분만 만든다 (`commands/init-project.md`).

## 미완 lifecycle 재개 통보 (v1.26.3 신규)

SessionStart 가 `<session-progress-rehydrate>` 블록을 주입했으면, **데이터만 있고 통보 규칙이 없던** 공백을 메운다 (재접속 사용자가 "어디까지 했나" 헤매는 것 방지). 사용자 입력 처리 전에 1 회 점검:

1. 최신 FID 섹션의 **최상단 활동 줄**(가장 최근 — session-progress 는 prepend 포맷)을 본다.
2. **종결 마커**(`/lifecycle DONE`·`/finishing 완료`·`PR #N 생성`·`DONE (PR`)면 → 완료된 작업. **통보 불필요** (노이즈 회피, 침묵).
3. **종결 마커 아니면**(미완) → 분기:
   - **사용자가 새 신호**(신규/유지보수)를 보냈으면 → **신호 처리 우선** (5원칙 4 주권 — 새 작업 의지 명확). 단 **1 줄 참고** 첨부: "(참고: 진행 중 `<FID>` 미완 — 직전 `<단계>`. 이어서 하려면 알려주세요)".
   - **신호 없는 일반 입력**이면 → **능동 재개 제안**: "진행 중 `<FID>` — 직전 `<단계>`, 다음 `<chain 다음 단계>`. 이어서 진행할까요? [y/n]".
4. **다음 단계 추론**: chain 순서(specify→clarify→plan→decompose→implement→verify→request-review→receive-review→security-review→integration-test→performance-test→PR)에서 최신 완료 단계의 **다음** 단계.

**원칙**:
- **강제 X — 미완일 때만 1 회**. 완료 FID 는 침묵 (5원칙 4 주권).
- **새 신호가 항상 우선** — 재개통보가 새 작업 진입을 막지 않는다 (재개는 신호 없을 때만 능동 제안).

## skill 호출 방법

Claude Code: `Skill` 도구 사용. skill 호출 시 내용이 로드되어 제시됨 — 그대로 따른다. skill 파일을 `Read` 도구로 직접 읽지 말 것.
단, `using-specops-ko/` 의 참조 파일(예: `freework-pending.md`)은 skill 이 아니라 지시된 시점에 `Read` 하는 절차 문서다.

호출 형식: skill 이름은 `devfsd:specifying-ko` 같은 namespace 포함.

## 적색 플래그 — 중단

다음 생각이 떠오르면 **중단하고 메타 skill 다시 검토**:

| 생각 | 실제 |
|---|---|
| "이건 단순 질문이라 skill 불필요" | 신호가 있는지 다시 보라 |
| "맥락 더 필요하니 clarifying부터" | specifying이 먼저. clarify는 specifying 종료 후 chain |
| "사용자가 이미 코드 보여줬으니 implementing 직진" | spec 없이 구현 금지. 5원칙 4·5 위반 |
| "skill 너무 무거워 보임" | 단순 질문이면 NO 분기로. '무겁다'는 배제 사유가 아니다 — 배제 조건(repo 밖 산출물)에 해당하지 않으면 호출 |
| "기억나는 skill이라 다시 안 읽음" | skill은 진화함. 매번 호출 |
| "PPT·요구사항서도 산출물이니 chain 태우자" | **테스트할 코드가 없으면 후속 단계가 공회전한다.** 배제 조건 확인 — 과잉 발동도 적색 플래그다 |

## 5원칙 주입

| 원칙 | 본 skill 연결 |
|---|---|
| 1 투명성 | skill 호출 시 "Using <skill> to <purpose>" 명시 — 침묵 진행 금지 |
| 2 문지기 | 신호 감지는 binary — 판정 유보 금지. 애매함은 '호출' 쪽으로 해소한다 (배제는 명백할 때만) |
| 4 주권 | HARD GATE는 engine skill이 본문에서 강제. 메타 skill은 진입만 책임 |
| 5 한계 고백 | skill이 적합하지 않다고 판단되면 후행 단계에서 사용자에게 "이 skill로 충분한가?" 질문 가능 |

## Karpathy·Advisor (cross-cutting)

- 구현 단계는 `devfsd:karpathy-ko` 4원칙(가정 명시·단순성·외과적 변경·목표 기반 검증)을 따른다.
- 기획·분석·설계·개발 중 애매하거나 모르는 지점은 단정하지 말고 advisor 를 호출한다(자명한 typo·1줄 rename 제외). 단계별 호출 시점: `devfsd:advisor-ko`.

## 자유작업 pending 처리

SessionStart 가 `<freecomment-pending>` 블록을 주입했을 때만 해당한다 — 블록에 적힌 절차 파일(`using-specops-ko/freework-pending.md`)을 `Read` 해 **다음 사용자 턴 시작 시** 그대로 수행한다.
