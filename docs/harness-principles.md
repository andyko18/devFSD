# Harness 원칙 5종

devFSD 가 서브에이전트·산출물·세션을 다루는 다섯 원칙의 규범 문서다. 종전에는 layer 3 skill 5개(`*-ko`)였으나, Skill 로 호출되지 않고 다른 본문이 인용만 했기 때문에 문서 1장으로 합쳤다(20261114 · 최근 30일 호출 0회). 내용은 옮기기 전과 같다 — 다른 본문·테스트가 여기 문구를 계약으로 읽는다.

| 원칙 | 한 줄 | 주로 읽는 곳 |
|---|---|---|
| 스프린트 계약 | 수용 기준(AC)이 범위 계약이다 — 계약 밖 변경 금지 | specifying · decomposing · karpathy |
| 아티팩트 구조 규약 | `.specops/<FID>/` 경로·파일·handoff 4필드 | 전 engine skill |
| 생성·평가 분리 | 만든 쪽이 판정하지 않는다 — Evaluator 는 Write/Edit 박탈 | implementing · planning · `/start-all` |
| 컨텍스트 리셋 | 단계 사이 맥락은 파일에서만 다시 읽는다 — 진행 기록 줄 순서 불변식 | implementing · 세션 시작 훅 |
| 파일 기반 전달 | 서브에이전트에는 경로만 넘긴다 — 리뷰 보고서 저장 예외 | implementing · 리뷰어 |

---

## 스프린트 계약


### 개념

`acceptance-criteria.md`는 **계약서**다. 이후 모든 단계의 판정 기준이 된다. Evaluator는 계약서와 산출물만 비교하고, 구현 세부사항을 평가하지 않는다.

### 계약 항목 템플릿 (Given/When/Then)

```markdown
### AC-1: <기능 이름>

**Given** <전제 조건·초기 상태>
**When** <사용자/시스템 동작>
**Then** <관찰 가능한 결과>

**검증 방법**: <수동 재현 단계 또는 자동 테스트 경로>
**우선순위**: must | should | nice-to-have
```

예:

```markdown
### AC-3: 캐시 만료 재조회

**Given** 캐시 유효기간이 60초로 설정되어 있고, 60초가 경과한 상태에서
**When** 동일 키로 조회 요청이 들어오면
**Then** 원본 API가 호출되고 응답이 새 캐시에 저장된다

**검증 방법**: `pytest tests/test_cache.py::test_expiry_refetch`
**우선순위**: must
```

### 규칙

1. `acceptance-criteria.md`는 `/specify` 시점에 작성. `/clarify`에서만 **수정 가능**, 이후 단계는 **읽기 전용**.
2. 모든 AC는 **관찰 가능한 결과**로 서술. "내부적으로 ... 호출" 같은 구현 디테일 금지.
3. 우선순위: `must` 항목 전부 충족되지 않으면 `/verify`는 PASS 불가.
4. Evaluator는 계약서의 AC 번호로 참조(`AC-3 실패`)하여 판정.
5. **AC 필드는 기계 검증된다** — 판정 SoT = `scripts/_internal/check-ac-format.sh` (20260807, `emit-context.sh` 가 구현 직전 자동 호출). AC 블록마다 **Given·When·Then·우선순위** 필수, 값은 `must`·`should`·`nice-to-have`. `**우선순위**` 누락은 단순 서식 문제가 아니다 — `emit-context.sh` 의 **must AC 역방향 커버리지** 검사가 `**우선순위**: must` 인 AC 만 대상으로 삼으므로, 필드가 없으면 그 검사가 **무음으로 꺼진다**(필수 AC 가 태스크 매핑 없이 통과 → 영영 미구현). 회귀 AC(`AC-R-*`)는 대상 밖 — SoT 는 `check-regression-ac.sh`.

### 체크리스트 (Evaluator)

- [ ] `acceptance-criteria.md` 전문을 읽었는가?
- [ ] 산출물이 각 `must` AC를 충족하는지 하나씩 확인했는가?
- [ ] 미충족 AC를 명시적으로 나열했는가? (번호·이유)
- [ ] 계약에 없는 기능을 평가하지 않았는가? (scope creep 방지)
- [ ] 판정 결과를 `analysis.md`/`review.md`/`verify.md`에 JSON 블록으로 기록했는가?
- [ ] 유지보수 FID (`spec.md §유형 = 유지보수`) 인 경우 회귀 방지 must AC (`AC-R-*`) ≥ 1 포함 확인 — 미포함 시 `verdict = BLOCK`. 단 `§유형 = trivial` (변경 라인 ≤ 5 자동) 인 경우 면제

### 판정 JSON 블록 포맷

```json
{
  "fid": "20260420-rss-cache",
  "evaluator": "spec-reviewer-ko",
  "timestamp": "2026-04-20T12:00:00Z",
  "verdict": "PASS | BLOCK",
  "ac_results": [
    {"ac": "AC-1", "pass": true},
    {"ac": "AC-3", "pass": false, "reason": "캐시 만료 후 재조회 시 stale 값 반환됨 (tests/test_cache.py::test_expiry_refetch 실패)"}
  ],
  "blocking_acs": ["AC-3"]
}
```

### 안티패턴

- 계약서에 **구현 방법**을 적음 (예: "Redis를 사용한다") → Given/When/Then 형식 이탈
- `/specify` 이후 계약 변경 — 추가 요구사항은 `/clarify`에서만 반영
- Evaluator가 계약에 없는 품질 기준으로 BLOCK (개인 취향) → 계약 재협상이 필요
- `must`와 `should`를 구분하지 않음 — 우선순위 없이 모두 BLOCK 사유가 됨
- **회귀 AC 없는 유지보수 FID** — `§유형 = 유지보수` 인데 `AC-R-*` 0 개로 작성. **회귀 검증 근거 없음** → BLOCK. clarifying-ko 단계에서 `AC-R-*` append 가능. `§유형 = trivial` (변경 라인 ≤ 5 자동) 시에만 면제

### 예시: BLOCK 판정

```markdown
# analysis.md

## 판정: BLOCK

### 차단 AC
- AC-3 (캐시 만료 재조회): `tasks.md`의 태스크 5가 만료 처리 로직을 포함하지 않음
- AC-7 (에러 로깅): `plan.md` §3에서 로깅 모듈 책임 미명시

### 권고
`planning-ko` 재실행 필요. `/plan 20260420-rss-cache` 재실행.
```

---

## 아티팩트 구조 규약


### 개념

긴 실행 작업에서 에이전트 간 상태 전달을 **메시지 페이로드가 아닌 파일**로 한다. 모든 산출물은 약속된 경로 규약(`.specops/<FID>/*.md`)을 따른다.

**왜 필요한가.** 대화 메시지는 컨텍스트에 남아 오염된다. 파일은 다음 커맨드가 필요할 때만 읽는다. 이것이 "context resets"와 쌍을 이룬다.

### FID 규약

**정규식**: `^\d{8}-[a-z0-9-]+$` (예: `20260420-rss-cache`)

- 날짜: 기능 착수일 `YYYYMMDD`
- 슬러그: 영문 소문자·숫자·하이픈만. 공백·한글·대문자 금지
- 유일성: 기존 `.specops/` 하위 디렉토리와 충돌 시 뒤에 `-2`, `-3` 접미

### 디렉토리 구조

```
.specops/
├── <FID>/                         # 기능별 작업 공간
│   ├── intent.md                  # specifying 1.5 생성 (설계 전 승인)
│   ├── spec.md                    # /specify 생성
│   ├── acceptance-criteria.md     # /specify 생성, /clarify 수정
│   ├── clarifications.md          # /clarify 생성
│   ├── plan.md                    # /plan 생성
│   ├── data-model.md              # /plan 생성 (선택)
│   ├── contracts/                 # /plan 생성 (선택)
│   ├── tasks.md                   # /tasks 생성, /implement 상태 마킹
│   ├── handoffs/                  # Stage handoff 문서 (OMC 패턴 차용)
│   │   ├── specifying.md          # specifying-ko 완료 시 생성
│   │   ├── planning.md            # planning-ko 완료 시 생성
│   │   ├── decomposing.md         # decomposing-ko 완료 시 생성
│   │   └── implementing.md        # implementing-ko 완료 시 생성
│   ├── analysis.md                # /analyze 생성
│   ├── review.md                  # /code-review 생성
│   ├── verify.md                  # /verify 생성
│   ├── verify-loop.md             # bounded verify→fix 루프 카운터 (P2-2)
│   ├── auto-state.md              # 전역 재시도 카운터 (v1.10.0 §auto 전용 → v2.13.0 모드 무관)
│   └── dev-decisions.md           # 개발 구간에서 묻지 않고 정한 결정 — dev-decision.sh 가 기록 (v2.13.0)
└── session-progress.md            # 전역, 모든 커맨드 append
```

### Stage Handoff 문서 규약 (OMC 차용)

각 engine skill은 `## 다음 skill` 진입 **직전** `.specops/<FID>/handoffs/<stage>.md`를 기록한다. context reset/compact 이후에도 다음 skill이 결정 맥락을 복원할 수 있게 한다.

**필수 4필드** (10-20줄):

```markdown
# Handoff — <stage> → <next-stage>

## Decided
- <이 단계에서 확정된 핵심 결정 1-3개>

## Rejected
- <검토했으나 기각한 대안 + 한 줄 사유>

## Risks
- <다음 단계가 주의해야 할 리스크·제약>

## Remaining
- <미해결 열린 질문 또는 다음 단계로 넘기는 사항>
```

**규칙**:
- 항목 없는 섹션은 `- (없음)` 기재 (섹션 생략 금지)
- 파일 부재 시 다음 skill이 해당 섹션 없이 진행 가능 (graceful skip). 단 handoff 존재 시 첫 단계에서 반드시 읽음.

`.specops/`는 프로젝트 루트의 `.gitignore`에 반드시 포함. 플러그인 레포가 아닌 **사용 프로젝트**의 `.gitignore`다.

### 무인 모드 술어 (v1.10.0 신규)

**공통 술어** — 모든 게이트 스킬이 참조하는 단일 출처:

```bash
# 무인 모드 감지 (§batch OR §auto)
if grep -qE '^\*\*§batch\*\*:' .specops/<FID>/spec.md; then
  MODE="batch"
elif grep -qE '^\*\*§auto\*\*:[[:space:]]*true' .specops/<FID>/spec.md; then
  MODE="auto"
else
  MODE="single"
fi
```

| MODE | 동작 |
|---|---|
| `batch` | 기존 §batch halt 신호 (BATCH-PHASE1-DONE, BATCH-PERF-DONE) |
| `auto` | 가역 게이트 자동 통과, PR 게이트에서 가정 다이제스트 + 단일 [y/n] |
| `single` | 기존 단일 모드 동작 (모든 게이트에서 사용자 입력 대기) |

**주의**: 모드별 halt 동작은 mode-specific이다. `§batch`의 halt 신호(`BATCH-PHASE1-DONE`)는 `§auto`에 적용되지 않는다. 모든 분기점에서 3-way 검사를 사용한다.

### auto-state.md 규약 (v1.10.0 §auto 전용 → v2.13.0 재시도 카운터는 모드 무관)

**경로**: `.specops/<FID>/auto-state.md`

**형식**:

```markdown
auto_retry_count: 0
escalations: []
```

**필드**:
- `auto_retry_count`: per-FID 전역 재시도 카운터 (상한 1). implementing-ko와 verifying-evidence-ko가 공유.
- `escalations`: 에스컬레이션 이력 목록. `[{stage: "...", reason: "...", ts: "..."}]` 형식. PR 게이트 가정 다이제스트에 포함.

**파일 부재 시**: `auto_retry_count=0`으로 간주 (graceful init).
**삭제 시점**: FID Lifecycle 완료 후 (PR 생성 또는 Lifecycle 종료 시).

### 체크리스트 (커맨드 Process 첫 스텝)

1. 사용자 입력에서 FID를 추출하거나 새로 생성한다 (정규식 검증).
2. `.specops/<FID>/` 디렉토리 존재 여부 확인. 없으면 생성.
3. 입력 아티팩트(커맨드별 `specops_artifact_in` 명시)가 모두 존재하는지 확인. 누락 시 **문지기로서 중단**하고 앞 단계 실행을 요청.
4. 출력 아티팩트 경로를 계산하되 **아직 쓰지 않는다**. 본 Process 완료 시에만 쓴다.
5. `session-progress.md` FID 섹션 상단에 "<timestamp> <command> <FID> 시작" 한 줄 prepend(최신=위).
6. 종료 시 "<timestamp> <command> <FID> 완료 (출력: ...)" 한 줄 prepend. (줄 순서 불변식 — `docs/harness-principles.md` 「컨텍스트 리셋」 참조: 거버넌스 verify-lookback 이 의존.)

### 예시

**입력**: `/plan 20260420-rss-cache`

- 입력 아티팩트 확인: `.specops/20260420-rss-cache/spec.md`·`acceptance-criteria.md`·`clarifications.md` 존재해야 함
- `clarifications.md` 없으면 "`/clarify 20260420-rss-cache` 먼저 실행하세요" 라고 응답 후 중단
- 모두 있으면 Process 진행, 종료 시 `plan.md` 작성

### 안티패턴

- 에이전트 프롬프트에 파일 **내용**을 붙여넣기 (파일 경로만 전달해야 함 — file-based-communication 참조)
- FID 없이 작업 — 어디에 속한 작업인지 추적 불가
- 이전 단계 아티팩트를 수정 — spec은 spec이 만든 소유물, 이후 커맨드는 **읽기 전용**
- `.specops/`를 git에 커밋 — 세션별 맥락이라 팀 공유 불필요하며 프라이버시 위험

---

## 생성·평가 분리


### 개념

같은 에이전트가 자기 산출물을 평가하면 **확증 편향**이 발생한다. 생성(Generator)과 평가(Evaluator)를 다른 에이전트·다른 세션·다른 역할로 분리해 교차 금지 원칙을 강제한다.

### 페어 매트릭스

분리가 **성립하는 곳은 서브에이전트 dispatch 지점뿐**이다. 명세·설계·분해·검증(`specifying-ko`·`planning-ko`·`decomposing-ko`·`verifying-evidence-ko`)은 서브에이전트가 아니라 **skill 이 메인 세션에서** 수행한다 — 그 단계에는 Gen/Eval 에이전트 페어가 존재하지 않는다. `/start-all` Phase 2.5 화면·IF 산출은 오케스트레이터가 만들고 `design-reviewer-ko`가 판정한다.

| 지점 | Generator | 산출 | Evaluator (서브에이전트) | 검증 산출 |
|---|---|---|---|---|
| 설계 리뷰 | `planning-ko` (메인 세션) | plan.md | `plan-reviewer-ko` | 판정 보고 (PASS/BLOCK) |
| batch 설계 리뷰 | `/start-all` Phase 2.5 (오케스트레이터) | screens + api-spec + data-model | `design-reviewer-ko` | design-review.md + `DESIGN-REVIEW-RESULT` |
| 구현 Phase B | `implementer-ko` | 코드 + 테스트 | `spec-reviewer-ko` | 스펙 준수 판정 |
| 구현 Phase C | `implementer-ko` | (동일 산출) | `code-reviewer-ko` | 코드 품질·보안·커버리지·DB 판정 |
| 이해 검사 | `planning-ko` (메인 세션) | plan.md | `comprehension-reviewer-ko` | 이해 검사 보고 (Minor 경고 — `COMPREHENSION-RESULT`) |
| self-config 감사 | — | (플러그인 자기 번들) | `red-team-ko` → `blue-team-ko` → `auditor-ko` | risk 등급 리포트 |

**실재 에이전트는 `agents/` 16종뿐**: Generator 8 (`implementer-ko`·`req-designer-ko`·`ui-designer-ko`·`db-designer-ko`·`arch-designer-ko`·`api-designer-ko`·`security-designer-ko`·`test-designer-ko`) / Evaluator 8 (`spec-reviewer-ko`·`code-reviewer-ko`·`plan-reviewer-ko`·`design-reviewer-ko`·`red-team-ko`·`blue-team-ko`·`auditor-ko`·`comprehension-reviewer-ko`). 이 표에 없는 에이전트를 dispatch 하지 마라 — 존재하지 않는다.

### 엄격 규칙

1. **교차 금지**: Generator는 판정하지 않고, Evaluator는 새 산출물을 만들지 않는다.
2. **프롬프트 헤더 의무 선언**: 서브에이전트 dispatch 프롬프트 첫 줄에 다음 중 하나를 명시.
   - `You are a GENERATOR. You MUST produce <output artifact>. You MUST NOT judge prior outputs.`
   - `You are an EVALUATOR. You MUST produce ONLY a judgment artifact (PASS/BLOCK). You MUST NOT modify prior artifacts.`
3. **세션 분리**: Generator 세션과 Evaluator 세션은 별개 서브에이전트 호출로 분리. context-resets 스킬 준수.
4. **파일 통로만**: Evaluator는 Generator의 산출 파일만 읽는다. Generator의 사고 과정·중간 메모에 접근 금지.

### 체크리스트 (커맨드 구현 시)

- [ ] Evaluator 에이전트 frontmatter 에 `role: evaluator` marker 가 있는가? (validate-structure `agent_tools` 가 Write/Edit 박탈을 하드 검사)
- [ ] Generator 는 산출 **파일**을 만들고, Evaluator 는 **판정 보고**만 반환하는가? (판정 파일 저장은 부모 소관 — file-based-communication)
- [ ] 서브에이전트 호출 시 역할 선언 헤더를 포함하는가?
- [ ] Evaluator가 BLOCK 판정 시, 수정은 Generator 재호출로 이뤄지는가? (Evaluator가 직접 고치지 않음)

### 안티패턴

- 같은 에이전트가 "쓰고 검토하고 수정" 전부 수행 → 자기평가 편향
- Evaluator가 "빠르니까 내가 고칠게요" 라며 산출물 수정 → 재현 불가능한 수정 사슬 발생
- Generator가 "내가 봐도 문제없어 보여요" 라며 평가 생략 → Evaluator 우회
- Gen/Eval 페어 바깥의 에이전트가 산출물 수정 → 소유권 위반

### 예시

**GOOD**: `implementing-ko`가 태스크 구현을 `implementer-ko`에 dispatch → 완료 후 **fresh** `spec-reviewer-ko` dispatch → `spec-reviewer-ko`가 코드와 `acceptance-criteria.md`를 읽고 "BLOCK: AC-2 미충족" 판정만 반환 → `implementing-ko`가 BLOCK 사유를 담아 `implementer-ko`를 재dispatch 해 수정.

**BAD**: `spec-reviewer-ko`가 "빠르니까 내가 고칠게요" 라며 코드를 직접 수정. → 계약 위반. Generator 의 소유물을 건드림 (`role: evaluator` frontmatter 가 Write/Edit 를 박탈해 도구 수준에서 차단된다).

---

## 컨텍스트 리셋


### 개념

장시간 Lifecycle을 한 세션에 이어가면 컨텍스트가 오염된다. 이전 단계의 시행착오·폐기된 가설·중간 산출물이 다음 단계 판단에 섞여 들어온다. **각 커맨드 종료 시 의도적으로 맥락을 끊고**, 다음 커맨드는 **`session-progress.md`** 와 **`.specops/<FID>/`** 에서만 필요한 것을 읽어 재시작한다.

### 원칙

- 서브에이전트는 **매번 fresh 세션**에서 호출한다. 프롬프트에는 읽어야 할 파일 경로만 담는다.
- 에이전트는 **이전 대화 내용을 기억하지 못한다고 가정**하고 항상 파일에서 시작한다.
- 재주입 경로는 오직 두 개: (a) `session-progress.md` (무엇까지 했는가), (b) `.specops/<FID>/*.md` (산출물).

### 체크리스트

1. 커맨드 종료 시 `session-progress.md` FID 섹션 **상단에 한 줄 prepend**(최신=맨 위).
2. 다음 커맨드 착수 시 `session-progress.md` **상단 10~20줄**만 읽어 "현재 FID", "직전 단계", "차단 요소"를 파악.
3. 직전 단계 산출물이 필요하면 **파일로 다시 읽어라**. 대화에서 기억나는 내용으로 진행하지 마라 — 부정확하다.
4. Generator/Evaluator 전환 시 반드시 리셋. 예: `implementer-ko` 종료 → `spec-reviewer-ko` dispatch 시 대화 맥락 단절 (Evaluator 는 Generator 의 사고 과정이 아니라 산출 **파일**만 본다).
5. 세션이 실제로 종료(Claude Code 재시작)되어도 `session-progress.md`만으로 복귀 가능해야 한다.

### session-progress.md 포맷

```markdown
# Session Progress — <project-name>

## <FID-1> · <제목>
- 2026-04-20 13:20 /analyze PASS
- 2026-04-20 13:00 /plan 재실행 완료
- 2026-04-20 12:00 /analyze BLOCK (analysis.md — 태스크 3 계약 위반)
- 2026-04-20 11:30 /tasks 완료 (tasks.md — 12 바이트-사이즈 태스크)
- 2026-04-20 11:10 /plan 완료 (plan.md, data-model.md)
- 2026-04-20 10:30 /clarify 완료 (clarifications.md — 3개 쟁점 해소)
- 2026-04-20 10:00 /specify 완료 (spec.md, acceptance-criteria.md)

## <FID-2> · ...
```

한 줄 규칙: `<YYYY-MM-DD HH:MM> <command> <상태> (<산출·메모>)`.

**줄 순서 불변식**: FID 섹션 내 줄은 **최신이 위(prepend, 작은 줄번호)** — 블록 단위뿐 아니라 줄 단위도 내림차순. 거버넌스 verify-lookback(`hooks/governance-lib.sh` `_verify_passed_in_progress`)이 "verify 줄번호 < 코드변경 줄번호 = verify 가 최신" 판정에 이 순서를 직접 의존하므로, 오름차순(최신=하단)으로 작성하면 R-1/R-2 가 commit/PR 을 false-allow 한다.

### 안티패턴

- 세션 맥락만 믿고 파일 재독 없이 다음 커맨드 진행
- `session-progress.md` 업데이트 누락 — 세션 재시작 후 복귀 불가
- 전역 로그에 **모든 대화 내용**을 담으려 함 — 의도는 "재시작에 필요한 최소 단서"뿐
- 이전 커맨드의 피드백을 구두로 전달받아 구현 — 반드시 Evaluator가 쓴 `analysis.md` 또는 `review.md` 파일을 읽어라

### v0.0 자동 주입

`hooks/session-start.sh`가 새 세션 진입을 감지해 자동으로 메타 skill 본문과 함께 `session-progress.md` 마지막 블록을 `additionalContext`로 주입 (`<session-progress-rehydrate>` 래퍼). 조립 순서상 `session-progress-rehydrate` 는 **최후미**에 위치한다 — harness 인라인 절단 시 행동 지시 블록(pending·reconcile)과 메타 본문을 우선 노출하기 위함이다 (FID 20260814-sessionstart-payload-order).

---

## 파일 기반 전달


### 개념

서브에이전트를 호출할 때 프롬프트에 **파일 경로만 전달**한다. 파일 본문을 프롬프트에 붙여넣지 않는다. 이것이 대규모 아티팩트에서 컨텍스트 낭비를 막고, 에이전트가 스스로 필요한 부분만 읽는 자기조절 능력을 부여한다.

### 규칙

1. 서브에이전트 호출 프롬프트는 **경로 + 지시사항**의 두 요소만 갖는다.
2. 경로는 **절대 경로** 또는 프로젝트 루트 기준 **상대 경로**. 모호성 금지.
3. 에이전트가 읽어야 할 파일이 여러 개면 **우선순위를 매겨 나열**. "AC 파일을 먼저, 그다음 plan.md."
4. 에이전트가 **쓸** 파일도 경로로 지시. "결과를 `.specops/<FID>/analysis.md`에 JSON 블록으로 저장."
5. 호출자는 서브에이전트 응답에서 **산출 파일 경로만 확인**하고 본문을 다시 읽는다. 응답에 본문이 와도 그걸 신뢰하지 말고 파일을 직접 읽는다.

### 프롬프트 템플릿

```
You are <agent-name>, a <Generator|Evaluator> in the specops-ko Lifecycle.

READ (in order):
1. /path/to/.specops/<FID>/acceptance-criteria.md (contract)
2. /path/to/.specops/<FID>/plan.md (artifact under review)
3. /path/to/knowledge/constitution/five-principles.md (Layer 5)

TASK:
<구체 작업 지시 — 한국어 존댓말로>

WRITE:
/path/to/.specops/<FID>/analysis.md (JSON block per sprint-contracts schema)

CONSTRAINTS:
- Do NOT modify the artifact files you read.
- Do NOT embed file contents in your response — write to the output path.
- Use 한국어 존댓말 in the output file.
```

### 체크리스트

- [ ] 프롬프트에 파일 본문이 들어가지 않았는가?
- [ ] READ·TASK·WRITE 3 섹션이 명확한가?
- [ ] 경로가 절대 경로 또는 루트 기준 상대 경로인가?
- [ ] 에이전트 응답 후 호출자가 WRITE 파일을 **직접 다시 읽는가**?
- [ ] 한국어 응답을 요구했는가? (CLAUDE.md §9)

### 안티패턴

- 프롬프트에 "여기 plan.md 내용입니다: ..." + 전체 붙여넣기 → 컨텍스트 낭비, 재사용성 0
- 경로 없이 "방금 그 plan 문서 기반으로 분석해줘" → 서브에이전트는 이전 대화를 모름
- 서브에이전트 응답에 담긴 파일 내용을 그대로 신뢰하여 다음 단계 진행 → 파일 실제 내용과 불일치 위험
- WRITE 경로를 지정하지 않고 "결과 알려줘" → 산출물이 대화 메시지에 휘발됨

### 예시

**GOOD**:
```
You are plan-reviewer-ko (Evaluator).
READ:
1. /Users/mac/Project/foo/.specops/20260420-rss-cache/acceptance-criteria.md
2. /Users/mac/Project/foo/.specops/20260420-rss-cache/plan.md
TASK: 각 AC가 plan의 태스크에 1:1로 매핑되는지 확인하고, 미매핑 AC를 BLOCK 사유로 분류하세요.
REPORT: 판정(PASS/BLOCK)과 근거만 반환하세요. 읽은 산출물을 수정하지 마세요 — 판정 파일 저장은 호출자 소관입니다.
```
> Evaluator 에이전트(`role: evaluator`)는 Write/Edit 가 **박탈**돼 있다. WRITE 경로 지시는 Generator(`implementer-ko`) dispatch 에만 쓴다.

**BAD**:
```
방금 만든 plan.md 내용:

# Plan
...전체 2000줄 붙여넣기...

이거 검토해줘.
```

#### 예외 — Phase B/C 리뷰어 보고서 저장 (20260914)

`spec-reviewer-ko`·`code-reviewer-ko` 의 보고서는 호출자가 아니라 SubagentStop 훅(`hooks/save-review-report.sh`)이 저장한다. 리뷰어는 여전히 read-only 이고, 전문을 `<<<REVIEW …>>>` 블록으로 내면 훅이 `reviews/<tid>-<phase>-report.md` 로 옮긴 뒤 요약 재종료를 요구한다.

- 판정 SoT = reviews 파일 — 반환 요약은 경로 포인터일 뿐이다. 판정은 파일을 읽어 확정한다
- report 부재 시 부모 fallback 저장 — 훅이 돌지 않았거나 형식이 틀리면 전문이 그대로 반환되므로 부모가 태스크별로 저장한다. 반환에 훅 요약이 없으면 파일 존재와 무관하게 덮어쓰기 저장한다(이전 라운드 report 가 남아 옛 판정을 읽는 경로 차단) · 반환 뒤 `review-saved.sh check` 가 rc 0 이면(훅이 이번 dispatch 뒤 저장) 다시 쓰지 않는다 — 규약 원본은 implementing-ko 「end-loaded B/C 산출물 규약」
- dispatch-log 행은 부모가 기록 — 훅은 파일만 쓴다
- 한계: `SPECOPS_GOVERNANCE_PROFILE` 이 `standard`·`minimal` 이면 is-hook-enabled 가 이 훅을 끄므로 저장은 전부 부모 fallback 경로로 간다

