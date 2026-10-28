---
name: clarifying-ko
description: specifying-ko 완료 후 호출 — spec.md의 모호성·열린 질문을 사용자와 대화로 해소하고 clarifications.md 생성. BLOCKING 해소 전 planning-ko 진행 금지
layer: 2
reference_upstream: obra/superpowers@v5.0.7 skills/brainstorming/SKILL.md
  - obra/superpowers@v5.0.7 skills/brainstorming/SKILL.md (후반 "Spec Self-Review" + "User Review Gate" 분리)
  - github/spec-kit commands/clarify.md (specops-ko 경유)
  - specops-ko commands/clarify.md
  - mattpocock/skills@5beb35b skills/engineering/domain-modeling/SKILL.md (MIT — 용어 정밀화·설명과 코드 대조·개념 경계 시나리오, 한국어 재작성)
specops_version: 2.9.0
used_by: specifying-ko (chain 진입), planning-ko (chain 출구)
---

# Engine 스킬 — 명확화 (clarifying)

`spec.md`의 모호성·열린 질문을 **사용자와 대화로 해소**하고 `clarifications.md`에 기록한다. 필요 시 `acceptance-criteria.md`를 append-only로 보강.

<HARD-GATE>
**BLOCKING 우선순위의 명확화 질문이 RESOLVED 상태가 되기 전까지** `devfsd:planning-ko`를 호출할 수 없다. DESIRABLE만 남았거나 전부 RESOLVED일 때만 planning-ko 진입 허용.

**판정: 부분 기계화 + 대화 게이트** — "모든 BLOCKING 이 RESOLVED 인가" 는 BLOCKING 목록 자체가 모델 판단이라 전수 검사가 불가하다. 단 **가장 비싼 축(foundation 기술스택)은 기계 판정**한다 — 판정 SoT = `scripts/_internal/check-stack-decided.sh` (구현 직전 `emit-context.sh` 가 원장 확정 행 또는 clarifications.md 의 스택 `RESOLVED` 를 재검, `ASSUMED` 불인정). 원장 확정값 판정도 `scripts/_internal/check-decisions-ledger.sh` 로 눈대중을 대체했다.

**[§auto 모드]** (`grep -qE '^\*\*§auto\*\*:[[:space:]]*true' .specops/<FID>/spec.md`):
BLOCKING 항목을 **best-guess 자동 응답**으로 처리한다:
- 합리적 기본값·컨텍스트 기반 추론으로 답변 선택
- clarifications.md Q-block에 `status: ASSUMED` 기재 + `**가정 근거**: <한 줄 이유>` 필드 추가
- **advisor() 보조 자문** (고영향 가정 한정 — 비용 통제): 가정이 **아키텍처·저장소·프로토콜·핵심 동작 입출력** 선택이면(또는 batch FR당 1회 묶음) best-guess 확정 **전** `advisor()` 1회 호출 → 권고를 best-guess 입력에 반영하고 `**가정 근거**`에 `advisor 의견: <요지>` 기록. **UI 세부·로깅·비치명 엣지·trivial 가정은 advisor 트리거 제외**(기존 best-guess 단독).
- **graceful fallback**: `advisor()` 미연결·미응답·실패 시 즉시 기존 best-guess 단독 진행 + `**가정 근거**`에 `advisor 미연결 — 자기추론` 기록(투명성). advisor 하드 의존 금지.
- **주권 보존**: advisor 반영 가정도 `status: ASSUMED` 유지 — advisor 는 1 의견이며 최종 확인은 PR 게이트 다이제스트의 사용자 몫.
- 이 가정은 performance-test-ko PR 게이트의 **가정 다이제스트**로 집계된다
- BLOCKING 자동 처리 후 planning-ko 직행 (사용자 응답 대기 없음)
</HARD-GATE>

## 필수 전제

본 skill 은 `specifying-ko` 완료 후 **반드시 한 번 호출**된다. spec §열린질문 카운트가 0 이더라도 호출해 BLOCKING 탐지·DESIRABLE 발굴을 수행한다. 생략 금지 — negotiable 아님.

**근거**: dogfood FID `20260422-csv-lines` 실측 — specifying 이 Q1~Q4 수집 후에도 clarifying 가 추가 DESIRABLE 3 건 (exit code · 에러 포맷 · 빈 파일 동작) 을 발굴해 AC-6/AC-7 신규 append. specifying 단독으로는 AC 계약 완결 불가 (FRICTION-LOG F-11).

## 체크리스트

다음 각 항목을 순서대로 태스크로 만들어 완료한다:

1. **입력 아티팩트 확인** — `.specops/<FID>/spec.md` + `.specops/<FID>/acceptance-criteria.md` 존재. 없으면 specifying-ko 선행 요청하고 **중단**
   - 입력에 `.specops/<FID>/intent.md` 포함(있으면) — 부재 시 graceful 진행
2. **모호성 탐지** — spec.md §열린 질문 + AC Given/When/Then 완결성 + 충돌·이중 해석 소지
   - **intent 열린 질문 미처리**: intent 의 IQ 가 spec §8 에서 답변·이월 중 어느 쪽으로도 처리되지 않았으면 BLOCKING 후보
   - **범주표 훑기**: 아래 `### 범주표 (빈 곳 훑기)` 의 8범주를 확인됨·부분·빠짐으로 본다. 결과는 clarifications.md 의 `**범주 점검**` 줄로 남긴다
3. **우선순위 분류** — BLOCKING vs DESIRABLE. (BLOCKING=0 이고 §auto 아니면 → 아래 `## 경량 모드 (lite)` 섹션 참조)
4. **사용자 대화** — 존댓말, BLOCKING은 한 번에 하나, DESIRABLE은 독립 시 최대 3건 묶음
5. **기존 clarifications.md 회전** — 있으면 `bash "${CLAUDE_PLUGIN_ROOT}"/hooks/rotate-evaluator-artifact.sh .specops/<FID>/clarifications.md` 실행
6. **clarifications.md 작성** — 판정 JSON + 질문별 답변
7. **acceptance-criteria.md append** — 신규 AC만 추가, 기존 AC 수정 금지. 추가하는 AC 도 `### AC-<n>:` 헤더 + **Given·When·Then·우선순위**(`must`·`should`·`nice-to-have`)를 갖춰야 한다 — 판정 SoT = `scripts/_internal/check-ac-format.sh` (구현 직전 `emit-context.sh` 자동 호출). `**우선순위**` 누락 시 must 커버리지 검사가 그 AC 를 보지 못한다.
8. **timestamp 주입** — `bash "${CLAUDE_PLUGIN_ROOT}"/hooks/inject-evaluator-timestamp.sh .specops/<FID>/clarifications.md`
9. **session-progress append** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /clarify 완료 "clarifications.md (N 쟁점 해소)"` 호출. `devfsd:planning-ko` 다음 단계 안내
10. **전환** — `devfsd:planning-ko` 호출

## §일괄 모드 — 질문 묶음 2회째와 승인 묶음

`grep -qE '^\*\*§일괄\*\*:[[:space:]]*true' .specops/<FID>/spec.md` 이면 아래가 이 skill 의 다른 절(사용자 대화 규칙의 'BLOCKING 은 한 번에 한 질문'·경량 모드의 묶음 1회)보다 우선한다. 규칙 원본 `../specifying-ko/once-approval.md` 를 Read 해 따른다.

1. 모호성 탐지·범주표·분류(Step 2~3)는 그대로 한다. clarifications.md 머리 `**mode**` 는 `once`(형식 블록의 `**mode**: full | lite` 줄도 `full | lite | once` 로 고친다). Step 7 에서 더할 AC 는 승인 묶음 4번에 미리 싣는다.
2. BLOCKING·DESIRABLE 후보를 **한 번에 묶어** 묻는다 — 질문 묶음 2회째 · 많아야 4개 · 추천 먼저(AskUserQuestion 이 있으면 그것으로). 서로 답에 의존하는 질문은 먼저 정할 것만 넣는다.
3. 묶음에 넣지 못한 것은 묻지 않고 `status: ASSUMED` + `**가정 근거**` 로 적는다.
4. 질문이 끝나면(후보가 없었으면 곧바로) 승인 묶음을 제시한다. 승인 전에는 planning-ko 를 호출하지 않는다. 수정 요청은 반영한 뒤 승인 묶음을 다시 제시한다.
5. 승인되면 once-approval.md 의 기록을 남기고 Step 5~10 을 마친 뒤 planning-ko 로 간다.

## 경량 모드 (lite) — BLOCKING 0 자동 탐지

**[§auto 이외 분기]**: Step 2 모호성 탐지 결과가 `spec §열린질문=0 AND AC Given/When/Then 완결`이면 **BLOCKING=0 판정** → 경량 분기:

1. BLOCKING 질문 생략 (0건이므로 정당).
2. **DESIRABLE 발굴 1회 수행** (F-11 보존 — specifying 단독 AC 완결 불가 근거) — 아래 범주표로 훑어 부분·빠짐 범주에서 찾는다:
   - DESIRABLE 발굴 ≥1건 → 최대 3건 묶음 질문 1회 (사용자 응답).
   - DESIRABLE 0건 → 즉시 통과 (묶음 불필요).
3. clarifications.md 상단에 `**mode**: lite` 명시 (투명성 — 경량 분기 적용 기록).
4. 이후 Step 6~10 정상 수행 (clarifications.md 작성·AC append·timestamp·session-progress·전환).

**경량 모드 금지 조건**: spec §열린질문 ≥1 OR AC Given/When/Then 미완결 → 기존 풀 모드(BLOCKING 한 번에 하나). §auto 모드는 이미 best-guess 자동이므로 경량 분기 비적용(중복 회피).

> 근거: 실측 최근 8 FID 중 7개 BLOCKING≈0 형식 통과. 경량 모드는 비용 절감하되 F-11(DESIRABLE 발굴) 보존.

## 결정 원장 소비 (HARD — 재질문 금지)

`.specops/memory/decisions.md` 가 존재하고 결정 표에 **확정값**이 있는 주제(스택·인증·배포·데이터 경계·UI 유무 등)는:

- BLOCKING 재질문 **금지**
- §열린질문으로 동일 주제를 다시 올리는 것 **금지**
- `status: ASSUMED` 우회 재질문 **금지** (이미 확정된 값을 가정으로 덮지 않음)
- **예외**: 현재 spec과 표의 확정값이 **충돌**할 때만 1회 재확인 → RESOLVED 후 표 행 upsert(`출처=clarify <FID>`)

`.specops/memory/project-context.md` §2 스택·제약은 위 표의 요약이다 — 표에 행이 있으면 컨텍스트만으로 재묻지 않는다.

## 모호성 탐지 기준

### 범주표 (빈 곳 훑기)

spec·AC 를 아래 8범주로 훑어 범주마다 **확인됨 · 부분 · 빠짐** 으로 본다. 부분·빠짐 가운데 **답에 따라 AC 나 설계가 달라지는 것만** 질문 후보로 삼는다 — 나머지는 묻지 않고 `**범주 점검**` 줄에 범주 이름만 남긴다. 후보를 BLOCKING·DESIRABLE 로 나누는 기준과 DESIRABLE 묶음 최대 3건은 그대로다. 해당하지 않는 범주는 "해당 없음"으로 적는다.

| 범주 | 보는 것 |
|---|---|
| 기능 범위 | 포함·제외가 분명한가 · 두 가지로 읽히는 요구가 없는가 |
| 데이터 | 다루는 데이터·형식·저장 위치·보존 기간이 정해졌는가 |
| 화면 흐름 | 주요 흐름과 빈 화면·로딩·오류 상태가 정해졌는가 |
| 비기능 | 성능·보안·관측(로그·지표)에 **수치 기준**이 있는가 ("빠르게" 대신 "2초 이내") |
| 외부 연동 | 의존하는 외부 서비스·파일·다른 단계와, 그것이 실패할 때의 동작이 정해졌는가 |
| 예외·경계 | 빈 입력·최대치·중복·동시 실행 같은 경계 동작이 정해졌는가 · **개념의 경계**를 시나리오 하나로 시험했는가 (예: "부분 환불된 주문은 '취소된 주문'인가?") |
| 용어 | 같은 것을 다른 말로 부르지 않는가 · 새 용어가 정의됐는가 · 한 말이 둘을 가리키면("거래처" = 매입처? 매출처?) **정할 이름 하나**를 추천하고 **쓰지 않을 말**을 함께 정했는가 |
| 완료 신호 | 무엇을 보면 끝났다고 판정하는지 AC 로 관찰 가능한가 |

결과는 clarifications.md 머리에 한 줄로 남긴다(무인 포함 모든 모드) — `**범주 점검**: 빠짐 N · 부분 M (범주 이름)`.

**BLOCKING** (해소 없이 plan 진행 불가):
- 핵심 동작의 입출력이 결정 안 됨
- 아키텍처 선택지가 미확정 (저장소·프레임워크·프로토콜) — **단** `decisions.md`에 동일 주제가 확정되어 있으면 본 항목에서 제외
- AC Given/When/Then 중 필수 분기가 비어 있음
- 스펙이 두 가지로 해석되어 **근본적으로 다른 구현**을 초래
- **§유형=`foundation`** 이고 `.specops/memory/frontend-architecture.md` 또는 `.specops/memory/backend-architecture.md` 에 `<...>` 형태의 미해소 placeholder 가 있으면 **기술 프레임워크 확정을 BLOCKING 질문으로 강제** — RESOLVED 전 planning-ko 진입 차단. **단** `decisions.md`에 프론트/백엔드 스택이 이미 확정되어 있으면 placeholder가 남아 있어도 BLOCKING 재질문 금지(원장 우선 — init이 채운 값을 신뢰). placeholder와 원장이 충돌할 때만 1회 재확인

> **★ 원장 면제는 눈대중 금지 — 판정기로 확인한다** (20260806). 위 두 항목의 "`decisions.md`에 확정되어 있으면 제외" 는 반드시 아래로 판정한다:
> ```bash
> bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-decisions-ledger.sh '<주제 regex>'   # 0=확정 · 1=미확정
> bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-decisions-ledger.sh --list            # 확정 주제 일람
> ```
> **후속 관문 (건너뛰어도 잡힌다)**: foundation 의 스택 확정은 구현 직전 `emit-context.sh` 가 `scripts/_internal/check-stack-decided.sh` 로 재검한다 — 원장 확정 행 **또는** clarifications.md 의 스택 `RESOLVED` 중 하나가 없으면 dispatch 가 열리지 않는다(`status: ASSUMED` 는 결정이 아니므로 불인정). 즉 본 절을 생략하면 여기서 막힌다. RESOLVED 시 원장 upsert 를 반드시 함께 하라 — 안 하면 후속 FR 이 같은 질문을 반복한다.
>
> `/init-project` 가 만드는 **원장 골격에는 예시 행이 들어 있다** — `| D-001 | (예시) UI 유무 | 있음 | … |`. 표를 눈으로 보면 "행이 있으니 확정된 원장" 으로 오독하기 쉽고, 그러면 foundation 기술스택 BLOCKING 이 **근거 없이 면제**돼 미확정 스택으로 plan 에 진입한다. 판정기는 `(예시)` 접두 행·빈칸·`<...>` placeholder·`TBD`/`(미정)` 류 무정보 값을 **모두 미확정**으로 본다. `1` 이면 면제 없이 BLOCKING 질문을 진행한다.

**DESIRABLE** (가정으로 진행 가능):
- UI 세부 (색상·버튼 텍스트)
- 비-치명적 엣지 케이스 처리 선택
- 로깅 수준·포맷
- 성능 임계값 (합리적 기본값 존재)

## 사용자 대화 규칙

- **추천 먼저 (BLOCKING·DESIRABLE 공통)**: 선택지마다 영향 한 줄을 적고, **추천 선택지와 근거 한 줄을 맨 앞에** 둔다. 사용자는 "추천대로"로 답할 수 있다. 선택은 사용자가 한다 — 추천은 판단 재료이지 결정이 아니다. 근거를 댈 수 없으면 추천하지 않고 그렇다고 적는다
- **BLOCKING**: 한 번에 한 질문, **객관식 선호**. 답변 결과가 다음 질문에 영향을 주므로 묶지 않음
- **DESIRABLE**: 주제가 동질·상호 독립이면 최대 3건 묶음 허용. 답변 간 의존 발생 시 즉시 개별 모드로 전환
- 질문은 **코드·구현이 아니라 의도**를 물음. "어느 라이브러리?" 대신 "어느 조건에 최적화할까요?"
- **설명은 코드와 대조**: spec 이나 사용자가 **기존 동작**을 설명하면, 묻기 전에 그 동작을 코드에서 grep·Read 로 확인한다. 다르면 둘을 나란히 보여 주고 묻는다 — "코드는 마감된 전표를 고치지 못하게 막는데, 마감 뒤에도 고칠 수 있다고 하셨습니다. 어느 쪽이 맞나요?" 코드는 근거로 보여 줄 뿐이고, 묻는 것은 여전히 의도다(바로 위 규칙). 설명과 코드가 다른 채로 plan 에 가면 둘 중 하나가 조용히 버려진다. 어긋남이 **핵심 동작**이면 BLOCKING 이다 — 경량 모드였어도 풀 모드로 바꾼다. §auto 에서는 묻지 않고 `ASSUMED` 로 적되 `**가정 근거**` 에 코드 동작과 설명을 둘 다 적는다. 대조할 코드가 없으면(신규 기능) 건너뛴다
- RESOLVED된 아키텍처·스택·인증·배포 결정은 `.specops/memory/decisions.md`에 행 upsert (후속 FR/foundation이 재묻지 않도록). 그 행에 **이유 한 줄과 검토한 대안**(버린 선택지와 짧은 이유)도 적는다 — 근거가 없으면 비운다. 칸이 5개뿐인 기존 원장이면 머리·구분선 끝에 `이유`·`검토한 대안` 두 칸을 붙이고 새 행만 7칸으로 쓴다(기존 행은 그대로 — 판독기는 칸 위치로 읽는다)

## 예시

```
/start 트랜스크립트 캐시 기능 → specifying-ko 완료 → clarifying-ko 진입

명확화 질문 #1 (BLOCKING)
  "spec.md §3에 캐시 저장소가 미확정입니다.
   추천: (1) 파일 캐시 — 서버가 필요 없고 기존 .cache/ 관례와 맞습니다.
   (1) 파일 캐시 (.cache/ 디렉토리) — 서버 불필요
   (2) Redis — 서버 필요
   (3) SQLite — 단일 파일
  "추천대로" 또는 번호로 답해 주세요."

사용자: "추천대로"

→ clarifications.md §Q1에 RESOLVED 기록
→ AC-5 신규 append: "캐시 파일은 .cache/ 디렉토리에 저장된다"

명확화 질문 #2 (BLOCKING)
...

모든 BLOCKING RESOLVED → planning-ko 진입 허용
```

## clarifications.md 포맷

```markdown
# Clarifications — <FID>

**status**: RESOLVED | BLOCKED | ASSUMED
**timestamp**: <auto-injected ISO-8601>
**mode**: full | lite | once   (경량 모드 적용 시 lite — BLOCKING 0 자동 탐지)
**범주 점검**: 빠짐 N · 부분 M (범주 이름)   (범주표 결과)

## Q1 · <topic> · BLOCKING

**질문**: <사용자에게 제시한 질문>

**추천**: <선택지 — 근거 한 줄>

**답변**: <사용자 응답>

**영향**: AC-5 신규 추가

**용어** (이름을 정했을 때만): <정한 이름> — 쓰지 않음: <같은 것을 가리키던 말들>

## Q2 · <topic> · BLOCKING · ASSUMED   ← §auto 모드 자동 응답

**질문**: <판단이 필요했던 질문>

**답변 (자동)**: <best-guess 선택된 답변>

**가정 근거**: <컨텍스트 기반 추론 한 줄>

**영향**: AC-X 반영 예정

## Q3 · ...
```

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 질문의 **근거**를 함께 제시 — "왜 이걸 물어야 하는가" |
| 2 **문지기** | BLOCKING 미해결 상태로 planning 진입 시도는 **거절** |
| 3 **깊이** | "아마 이럴 것"으로 답 대체 금지. 반드시 사용자에게 물음 |
| 4 **주권 존중** | 추천은 근거와 함께 먼저 제시하되 선택은 사용자가 한다. 대신 고르지 않음 |
| 5 **한계 고백** | 답변이 범위 밖이면 "이 부분은 이후 단계에서 결정" 기록 |

## 안티패턴

- 스펙 본문 **수정** — `spec.md`는 specifying-ko 소유. 여기서는 읽기만
- **기존 AC 수정** — append만 허용
- 사용자 답변 **추측** — 모르면 반드시 물음
- **구현 제안** — planning-ko 단계

## 참조

- `skills/specifying-ko/SKILL.md` — 선행 스킬
- `skills/structured-artifacts-ko/SKILL.md` — 아티팩트 경로 규약
- `templates/acceptance-criteria.md` — AC 포맷
- specops-ko 선례: `commands/clarify.md`

## 다음 skill

모든 BLOCKING RESOLVED + clarifications.md 저장 + AC append 완료 후 즉시 호출:

```
Skill: devfsd:planning-ko
```

BLOCKED 상태로 남으면 chain 정지. 사용자 개입 필요.
