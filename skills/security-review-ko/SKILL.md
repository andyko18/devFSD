---
name: security-review-ko
description: lifecycle chain에서 코드 변경 표면 검출 시 SAST(semgrep+gitleaks) 보안 스캔을 실행·판정·증거화. Critical/High 발견 시 chain 차단, 표면 부재·도구 미설치 시 graceful skip
layer: 2
reference_upstream: specops-ko 독자 추가 (integration-test-ko 게이트 패턴 번안)
specops_version: 2.18.0
used_by: receiving-code-review-ko (단일 모드 chain 진입), /start-all (batch 모드 직접 호출), integration-test-ko (chain 출구)
---

# Engine 스킬 — 보안 리뷰 (security-review, SAST)

## 개요

**PR 직전, 리뷰 완료된 결과물에 정적 보안 분석(SAST)을 실시한다.**

코드 리뷰는 사람 관점에서 품질·로직을 검사했지만, **알려진 취약 패턴**—주입(injection)·하드코딩 secret·안전하지 않은 역직렬화·경로 순회 등—은 자동 스캐너(semgrep·gitleaks)가 더 폭넓고 일관되게 검출한다.

**핵심 원칙**: "주장 전에 증거." verifying-evidence-ko의 철칙을 계승. 스캔을 실행하지 않고 "안전"을 주장하는 것은 부정직이다.

**선결 조건**: 본 skill은 `receiving-code-review-ko` 완료 후 호출된다. 코드 리뷰 이슈가 미해결이면 본 skill 진입 전에 해결한다.

---

## 적용성 판정 게이트

진입 즉시 `spec.md`의 §범위·§2 포함 항목을 읽어 **코드 변경 표면 신호**를 검출한다.

**코드 변경 표면 신호 (하나라도 존재 시 → 보안 스캔 단계 진행)**:
- 소스 코드 파일 신규/수정 (애플리케이션 로직)
- 사용자 입력 처리 (폼·쿼리 파라미터·파일 업로드)
- 인증/인가·secret·토큰·자격증명 취급
- DB 쿼리·외부 명령 실행·역직렬화
- 네트워크 요청·파일시스템 접근

**신호 없는 경우 (graceful skip)**:
```
SECURITY: SKIP — <근거: spec.md §섹션명 Lxx-yy, 표현 예: "§범위 L12-15 — 문서 전용 변경, 실행 코드 표면 없음">
```
위 문자열을 `.specops/<FID>/evidence.md`에 append 후 **즉시 `## 다음 skill`로 chain** (나머지 절차 스킵).

> **SKIP 근거 의무** (V3): SKIP 근거에 spec.md **섹션명 + 라인 번호**를 반드시 인용한다 (예: `§범위 L12`) — `§유형` 과 무관하다(`release-ready.sh` 가 인용 없는 SKIP 을 NOT_READY 로 본다). 근거 없는 SKIP 은 형식화 — 거부.
> **관측**: `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/skip-tracker.sh` 로 게이트별 누적 SKIP 비율(참고)과 **근거 없는(라인인용 없는) SKIP 건수**를 확인할 수 있다 (advisory — bare SKIP 이 형식화 신호). 판정 무기록 FID 는 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gate-coverage.sh ~/repoA ~/repoB` (scripts/README).

> 한계 고백: spec.md가 없거나 §범위 섹션이 없는 경우 → 사용자에게 "spec.md §범위 미발견 — 보안 스캔 대상을 수동으로 알려주세요 [혹은 skip?]" 1줄 질문. 사용자 응답에 따라 진행 또는 SKIP 처리.

---

## 보안 스캔 단계 (표면 신호 존재 시)

### Step 1: 스캔 대상 결정

변경 표면에 해당하는 **소스 디렉토리·파일**을 대상으로 한다. 기본은 변경된 파일/디렉토리, 범위가 불명확하면 프로젝트 루트.

```bash
# 변경 파일 기준 (권장 — 리뷰 직후)
git diff --name-only main...HEAD
```

### Step 2: SAST 스캔 실행

`scripts/security-scan.sh`를 실행한다. 이 래퍼는 먼저 설치 필요 없는 self-check(bash 정규식 기반 secret·위험함수 룰)를 항상 실행하고, 그 후 `semgrep`·`gitleaks` 설치 여부를 `command -v`로 확인하여 설치된 스캐너만 실행한 뒤 심각도를 집계한다.

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/security-scan.sh <스캔대상 디렉토리/파일>
# 예: bash "${CLAUDE_PLUGIN_ROOT}"/scripts/security-scan.sh src/
# 예: bash "${CLAUDE_PLUGIN_ROOT}"/scripts/security-scan.sh .
```

출력 형식:
- 스캐너가 없어도 `SECURITY: SKIP` 은 나오지 않는다 — 설치가 필요 없는 self-check 가 항상 돈다. semgrep·gitleaks 가 둘 다 없으면 아래 줄 끝에 `(self-check only — semgrep·gitleaks 미설치)` 가 붙는다
- `SECURITY: crit=<N> high=<N> med=<N>` — 스캔 실행됨. crit/high>0 이면 exit 1
  - 접미 `(룰셋: 로컬 bash-injection)` 이 붙으면 semgrep 이 실제로 완주했다는 **실행 receipt** 다. 부재하면 semgrep 층이 돌지 않은 것이다(미설치·룰셋 부재·시간초과·하드 실패) — `crit=0` 만 보고 통과로 읽지 않는다
  - 강등 사유는 `(외부 SAST 미반영 — …)` 접미로 함께 표기된다

### Step 3: 결과 판정

| 결과 | 처리 |
|---|---|
| `crit=0 high=0` + `(self-check only — …)` 접미 | PASS 로 진행하되 evidence.md 에 **접미까지 그대로** 남긴다 — 외부 스캐너가 돌지 않았다는 뜻이다(전체 SAST 통과로 적지 않는다) |
| `crit=0 high=0` (exit 0) | `SECURITY: PASS — crit=0 high=0 med=<N>` → evidence.md append → `## 다음 skill` |
| `crit>0` 또는 `high>0` (exit 1) | → **차단 분기** (아래) |
| 실행 자체 실패 (스크립트 없음 등) | → 사용자에게 "security-scan.sh를 찾을 수 없습니다" 보고 + 해결 후 재시도 |

> med(중간 심각도)는 차단하지 않는다. evidence.md에 집계만 기록하고 chain 진행한다 (후속 backlog 판단 대상).

---

## 차단 분기 (chain 차단)

스캔을 실행했으나 Critical 또는 High가 1건이라도 검출되면:

```
SECURITY: FAIL — crit=<N> high=<N>:
  - <semgrep rule / gitleaks 검출 항목 요약>
  ...
```

위 내용을 `.specops/<FID>/evidence.md`에 append 후 **chain 차단** → `devfsd:systematic-debugging-ko` 호출.

systematic-debugging-ko가 원인 분석·수정을 완료하면 다음 경로로 복귀:
```
수정 완료 → verifying-evidence-ko 재호출 → requesting-code-review-ko → receiving-code-review-ko → security-review-ko (재진입)
```

> 5원칙 2 문지기: Critical/High를 숨기거나 "med"으로 격하해 통과시키는 것은 금지. 1건이라도 crit/high = chain 차단.

---

## 증거화 (evidence.md append)

PASS·SKIP·FAIL 모든 경우에 `.specops/<FID>/evidence.md`에 결과를 append한다:

```markdown
## /security-review — <ISO-8601>

**결과**: PASS | SKIP | FAIL
**근거**: <spec.md 섹션 인용(SKIP) 또는 security-scan.sh 출력 요약>

<security-scan.sh 출력 전문 — PASS/FAIL 시>
```

미실행 상태에서 "PASS"를 주장하는 것은 **verifying-evidence-ko 절칙 위반**이다.

---

## session-progress append

evidence.md append 직후:
```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /security-review DONE|SKIP|FAIL "<요약>"
# 예: bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh 20260605-login /security-review SKIP "§범위 L12-15 — 문서 전용 변경"
# 예: bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh 20260605-login /security-review DONE "crit=0 high=0 med=2"
# 예: bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh 20260605-login /security-review FAIL "crit=1 — systematic-debugging-ko 호출"
```

---

## §auto 모드 처리

`spec.md`에 `**§auto**` 라벨이 있어도 (완전자동 모드), **Critical/High 자동 통과는 금지**한다.

- SKIP(표면 없음)·PASS(crit=0 high=0 — `self-check only` 접미 포함) → §auto에서 자동 진행 허용
- crit/high>0 (FAIL) → §auto여도 **차단**. systematic-debugging-ko 경유 필수. 보안 결함은 가역 게이트가 아니다

> 5원칙 2 문지기: 자동 모드는 "가역적·저위험" 게이트만 자동 통과한다. Critical 취약점 통과는 비가역적 위험이므로 자동 통과 대상이 아니다.

---

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 판정 근거를 spec.md 특정 섹션 인용 또는 스캐너 출력으로 명시 — "아마 안전할 것" 추측 금지 |
| 2 **문지기** | Critical/High 1건 = chain 차단. §auto여도 자동 통과 금지. "med으로 격하" 금지 |
| 3 **깊이** | 스캔 실행 없이 PASS 주장 금지. 출력 전문을 evidence.md에 기록 |
| 4 **주권 존중** | SKIP 처리 시 근거를 spec.md 라인 번호로 명시 — 사용자가 판단 가능하게 |
| 5 **한계 고백** | 스캐너 미설치 시 `self-check only` 접미를 그대로 기록(전체 SAST 통과로 쓰지 않는다). 도구 부재는 "검증 불가"이지 "안전"이 아님 |

---

## 참조

- 번안 원본 패턴: `skills/integration-test-ko/SKILL.md` (적용성 게이트·graceful skip·증거화 구조)
- SAST 래퍼: `scripts/security-scan.sh` (semgrep + gitleaks, graceful skip)
- 선행 skill: `skills/receiving-code-review-ko/SKILL.md`
- 증거 원칙: `skills/verifying-evidence-ko/SKILL.md`
- 실패 우회: `skills/systematic-debugging-ko/SKILL.md`
- 후속 게이트: `skills/integration-test-ko/SKILL.md`

---

## 다음 skill

PASS 또는 SKIP + session-progress append 직후 즉시 호출:

**[batch 모드 분기]** 먼저 spec.md `**§batch**` 라벨 감지 확인:

```bash
grep -qE '^\*\*§batch\*\*:' .specops/<FID>/spec.md && echo "BATCH" || echo "SINGLE"
```

- **batch 모드** (`**§batch**` 라벨 감지) → `BATCH-SECURITY-DONE: <FID>` 출력 + **halt**. integration-test-ko 미호출. `/start-all` 오케스트레이터가 다음 단계(통합)를 제어한다

**[단일 모드]** (`**§batch**` 라벨 없는 경우) — **Critical/High 0건 (PASS) 또는 표면 없음(SKIP)** → 즉시 호출:

```
Skill: devfsd:integration-test-ko
```

integration-test-ko가 통합 표면을 판정하고 → performance-test-ko → PR 생성 게이트로 chain한다.

본 security-review-ko는 단일 모드에서 **integration-test-ko 이외의 다음 스킬을 호출하지 않는다** (FAIL 시 systematic-debugging-ko 경유 후 chain 복귀, batch halt 제외).
