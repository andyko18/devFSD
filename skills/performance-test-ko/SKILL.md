---
name: performance-test-ko
description: lifecycle chain에서 NFR 성능 임계값 검출 시 성능 테스트를 작성·실행·증거화. 임계값 부재 시 graceful skip. Lifecycle 최종 단계 — PASS/SKIP 후 PR 생성 게이트 진행
layer: 2
reference_upstream: specops-ko 독자 추가 (test-master 패턴 번안)
specops_version: 2.18.0
used_by: integration-test-ko (chain 진입), PR gate (단일 모드 chain 출구), /start-all (batch 모드 BATCH-PERF-DONE halt 진출)
---

# Engine 스킬 — 성능 테스트 (performance-test)

## 개요

**PR 직전 마지막 검문소 — 성능 NFR 임계값을 실측으로 검증한다.**

코드 리뷰·통합 테스트를 통과한 결과물이 **응답시간·처리량·동시성** 요구사항을 실제로 충족하는지 확인한다. 검증 후 PR 생성 게이트로 진행한다.

**핵심 원칙**: "측정하지 않은 것은 주장하지 않는다." 성능 NFR이 있으면 실측, 없으면 graceful skip — 두 경우 모두 evidence.md에 기록한다.

**선결 조건**: 본 skill은 `integration-test-ko` 완료(PASS 또는 SKIP) 후 호출된다.

---

## 적용성 판정 게이트

진입 즉시 `spec.md`의 §NFR 섹션을 읽어 **성능 임계값 신호**를 검출한다.

**성능 임계값 신호 (하나라도 존재 시 → 성능 테스트 단계 진행)**:
- 응답시간 요구: "p95 < Xms", "평균 응답 < Xms", "최대 응답 < Xms"
- 처리량 요구: "N RPS 이상", "N TPS 이상", "동시 N명 처리"
- 동시성 요구: "N개 동시 연결", "N 동시 사용자"
- 부하 민감 엔드포인트 명시: "대용량 처리", "고트래픽 API"
- **Web Vitals (프론트 성능)**: "LCP < Xs", "CLS < X", "FCP < Xs", "번들 크기 < XKB" — 브라우저 렌더 성능 임계값 (측정: Lighthouse·web-vitals, downstream 스택)

**신호 없는 경우 (graceful skip)**:
```
PERFORMANCE: SKIP — <근거: spec.md §NFR Lxx-yy, 표현 예: "§NFR L8-12 — 성능 임계값 없음, CLI 도구">
```
위 문자열을 `.specops/<FID>/evidence.md`에 append 후 **즉시 `## PR 생성 게이트`로 진행** (나머지 절차 스킵).

> **SKIP 근거 의무** (V3): SKIP 근거에 spec.md **§NFR 섹션명 + 라인 번호**를 반드시 인용한다 (예: `§NFR-3 L54`) — `§유형` 과 무관하다(`release-ready.sh` 가 인용 없는 SKIP 을 NOT_READY 로 본다). 근거 없는 SKIP 은 형식화 — 거부.
> **관측**: `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/skip-tracker.sh` 로 게이트별 누적 SKIP 비율(참고)과 **근거 없는(라인인용 없는) SKIP 건수**를 확인할 수 있다 (advisory — bare SKIP 이 형식화 신호). 판정 무기록 FID 는 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gate-coverage.sh ~/repoA ~/repoB` (scripts/README).

> 한계 고백: spec.md §NFR 섹션이 없거나 모호한 경우 → 사용자에게 "spec.md §NFR에서 성능 임계값을 찾을 수 없습니다. [임계값 명시 / skip]" 1줄 질문.

---

## 성능 테스트 단계 (임계값 신호 존재 시)

### Step 1: 테스트 시나리오 설계

spec.md §NFR에서 임계값을 추출하여 테스트 시나리오를 작성한다.

**Load 테스트 패턴** (k6 예시 — downstream 부하 도구로 등가 구현):

```javascript
// tests/performance/load.js
import http from 'k6/http'
import { check, sleep } from 'k6'

export const options = {
  stages: [
    { duration: '1m', target: 50 },   // ramp up
    { duration: '3m', target: 50 },   // steady
    { duration: '1m', target: 0 },    // ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<200'],  // spec.md §NFR p95 < 200ms
    http_req_failed: ['rate<0.01'],    // 에러율 < 1%
  },
}

export default function () {
  const res = http.get('http://localhost:3000/api/health')
  check(res, { 'status 200': (r) => r.status === 200 })
  sleep(1)
}
```

**Stress 테스트 패턴** (점진 부하 — k6 예시):

```javascript
export const options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '5m', target: 100 },
    { duration: '2m', target: 200 },
    { duration: '5m', target: 200 },
    { duration: '2m', target: 0 },
  ],
}
```

> **주의**: 위 예시는 k6 기준. downstream 프로젝트가 Artillery·JMeter·Gatling·wrk 등을 사용하면 **동등한 검증**을 해당 도구로 구현한다. 임계값(thresholds) 설정은 spec.md §NFR 수치를 직접 반영한다.

### Step 2: 테스트 환경 전제 확인

- 서버가 실행 중인지 확인 (로컬 또는 스테이징)
- 부하 도구 설치 확인 (k6, artillery 등)
- 프로덕션 DB·외부 서비스 연결 여부 확인 (부하 테스트는 격리 환경 권장)
- 환경 미비 시 → "성능 테스트 실행 환경이 준비되지 않았습니다. [환경 설정 후 재실행 / skip]"

### Step 3: 테스트 실행 및 결과 판정

```bash
# k6 예시
k6 run tests/performance/load.js

# Artillery 예시
artillery run tests/performance/load.yml

# wrk 예시
wrk -t12 -c400 -d30s http://localhost:3000/api/health
```

**결과 분기**:

| 결과 | 처리 |
|---|---|
| 전 thresholds PASS | `PERFORMANCE: PASS — <임계값 목록> 전부 충족` → evidence.md append → **PR 생성 게이트** |
| 1개 이상 threshold FAIL | → **FAIL 분기** (아래) |
| 부하 도구 실행 자체 실패 | 사용자에게 보고 + 해결 후 재시도 |

---

## FAIL 분기 (chain 차단)

1개 이상 임계값이 초과되면:

```
PERFORMANCE: FAIL — thresholds 초과:
  - http_req_duration p(95): 실측 XXXms > 기준 200ms
  - http_req_failed rate: 실측 2.3% > 기준 1%
```

위 내용을 `.specops/<FID>/evidence.md`에 append 후 **chain 차단** → `specops-ko:systematic-debugging-ko` 호출.

systematic-debugging-ko가 성능 문제 원인 분석·수정을 완료하면 다음 경로로 복귀:
```
수정 완료 → verifying-evidence-ko 재호출 → requesting-code-review-ko → receiving-code-review-ko → (chain 대로 security-review-ko →) integration-test-ko → performance-test-ko (재진입)
```

> 5원칙 2 문지기: 임계값 초과를 "큰 문제 아님"으로 격하해 PR을 생성하는 것은 금지. spec.md §NFR이 계약이다.

---

## 증거화 (evidence.md append)

PASS·SKIP·FAIL 모든 경우에 `.specops/<FID>/evidence.md`에 결과를 append한다:

```markdown
## /performance-test — <ISO-8601>

**결과**: PASS | SKIP | FAIL
**근거**: <spec.md §NFR 인용 또는 임계값 목록>

<부하 도구 출력 요약 — PASS/FAIL 시>
```

---

## session-progress append

evidence.md append 직후:
```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /performance-test DONE|SKIP|FAIL "<요약>"
# 예: bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh 20260605-login /performance-test SKIP "§NFR L8-12 — 성능 임계값 없음"
# 예: bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh 20260605-login /performance-test DONE "p95=120ms < 200ms 기준"
```

---

## PR 생성 게이트

PASS 또는 SKIP + session-progress append 완료 후 PR 생성 게이트를 진행한다.

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

- **batch 모드** (`**§batch**` 라벨 감지) → `BATCH-PERF-DONE: <FID>` 출력 + **PR 게이트 전체 skip**. `/start-all` 오케스트레이터가 batch PR을 소유한다.

- **auto 모드** (`**§auto**` 라벨 감지) → **가정 다이제스트 제시 + 단일 [y/n] 확인** (아래 §auto 게이트 참조).

- **단일 모드** (`**§batch**`, `**§auto**` 라벨 없는 경우) → 아래 단일 모드 게이트 진행:

### §auto 게이트 (auto 모드 전용)

**가정 다이제스트 수집**:

```bash
# 1. clarifications.md ASSUMED 항목
grep -A5 "ASSUMED" .specops/<FID>/clarifications.md | grep -E "질문|가정 근거"

# 2. handoffs/*.md Decided 필드
grep -A10 "## Decided" .specops/<FID>/handoffs/*.md

# 3. spec.md 자동 결정 intent + 화면 + 인터페이스 (Step 1.5·5.5·5.6 auto-generated)
grep -E "자동 결정 화면|자동 결정 인터페이스|자동 결정 intent|자동 결정 분석|자동 승격" .specops/<FID>/spec.md

# 4. auto-state.md escalations (있으면)
cat .specops/<FID>/auto-state.md 2>/dev/null | grep escalations -A10
```

수집 결과를 다음 형식으로 사용자에게 제시:

```
## §auto 가정 다이제스트 — <FID>

### 자동 응답된 명확화 질문
<clarifications.md ASSUMED Q-blocks>

### 단계별 주요 결정
<handoffs/*.md Decided 항목>

### 자동 통과한 분석 · 자동 승격 (유지보수·경량 무인)
<spec.md "자동 결정 분석"·"자동 승격" 줄 + `current-state.md` 의 변경 대상·보존할 동작 요약 2~3줄 — 없으면 "(없음)">

### 자동 결정 intent (Step 1.5)
<spec.md "자동 결정 intent" 목록 — 없으면 "(없음)">

### 자동 생성된 화면 (Step 5.5)
<spec.md "자동 결정 화면" 목록>

### 자동 결정된 인터페이스 (Step 5.6)
<spec.md "자동 결정 인터페이스" 목록 — 엔드포인트/테이블. 없으면 "(없음)">

### 에스컬레이션 이력
<auto-state.md escalations — 없으면 "(없음)">

### 개발 중 결정
<`dev-decision.sh show <FID>` 출력 그대로>

---
위 가정 위에 구현됐습니다. PR을 생성하시겠습니까? [y/n]
```

- `y` → 아래 §1~§4 PR 생성 단계 진행
- `n` → "PR 생성 보류. 나중에 직접 `gh pr create` 실행 가능." → Lifecycle 종료

### 1. 커밋 전제 확인

```bash
FID="<현재 FID>"
if [ -z "$(git log main..HEAD --oneline)" ]; then
  echo "ERROR: feat/$FID 에 커밋 없음 — main과 동일. PR 생성 불가." >&2
  exit 1
fi
```

### 2. 끝 보고 + 사용자 확인

개발 구간에서는 묻지 않고 진행했으므로(`skills/implementing-ko/dev-autonomy.md`) 여기가 사용자가 **대신 정해진 것**을 보는 지점이다. 먼저 아래 출력을 **줄이지 않고 그대로** 보여 준다(0건이어도 그 줄을 보여 준다):

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dev-decision.sh show <FID>
```

`§일괄` 이면(`grep -qE '^\*\*§일괄\*\*:[[:space:]]*true' .specops/<FID>/spec.md`) 묻지 않고 정한 항목도 보인다 — `grep -n 'ASSUMED' .specops/<FID>/clarifications.md .specops/<FID>/intent.md .specops/<FID>/spec.md 2>/dev/null` 출력(없는 파일은 건너뛴다 · 0건이면 그 사실 1줄)과, `.specops/<FID>/auto-state.md` 가 있으면 그 escalations(묻지 않고 한 재시도).

이어서 묻는다:

> "모든 테스트 통과 (또는 skip). PR을 생성하시겠습니까? [y/n]"

`n` 시: "PR 생성 보류. 나중에 직접 `gh pr create` 실행 가능." → Lifecycle 종료.

### 3. PR 생성 (y 응답 시)

```bash
FID="<현재 FID>"
BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||'); BASE=${BASE:-main}   # 기본 브랜치가 main 이 아닌 repo 대응
gh pr create \
  --base "$BASE" \
  --head "feat/$FID" \
  --title "feat: <기능명> (#$FID)" \
  --body "$(cat <<'EOF'
## Summary
- <주요 변경 1~3 bullet>

## Test plan
- [ ] 프로젝트 테스트(`tasks.md` 의 test_command) 전 항목 PASS — 근거: `.specops/<FID>/evidence.md` `VERIFY: PASS`
- [ ] security / integration / performance 게이트 결과: `.specops/<FID>/evidence.md`

## 이번에 고치지 않고 넘긴 것
<`dev-decision.sh show <FID> --backlog` 출력 — 비면 "없음">

🤖 Generated with specops-ko Lifecycle (FID: $FID)
EOF
)"
```

### 4. PR 생성 후 session-progress append

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /lifecycle DONE "PR 생성 완료"
```

---

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 임계값 기준(spec.md §NFR 수치)과 실측값을 evidence.md에 나란히 기록 |
| 2 **문지기** | 임계값 초과 = chain 차단. "이 정도면 OK" 자의적 판단 금지 |
| 3 **깊이** | 부하 테스트 미실행 상태에서 "성능 문제 없음" 주장 금지 |
| 4 **주권 존중** | SKIP 근거를 spec.md 라인 번호로 명시 — 사용자가 SKIP 타당성 직접 확인 가능 |
| 5 **한계 고백** | 부하 도구 미설치·환경 미비 시 "성능 테스트 불가" 명시 후 사용자 결정 요청 |

---

## 참조

- 번안 원본 패턴: Jeffallan/claude-skills `skills/test-master/references/performance-testing.md` (HEAD SHA e8be415)
- 선행 skill: `skills/integration-test-ko/SKILL.md`
- 증거 원칙: `skills/verifying-evidence-ko/SKILL.md`
- 실패 우회: `skills/systematic-debugging-ko/SKILL.md`
- PR 생성 패턴: `skills/receiving-code-review-ko/SKILL.md` §PR 생성에서 이전

---

## 학습 추출 (learning-loop)

PR 게이트 처리 직후 (y/n 결과 무관 — 작업 자체는 완료됐으므로) 다음을 수행한다:

1. `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gbrain-collect.sh <FID>` 실행 — handoffs Decided/Risks + evidence 결과 요약 수집
1b. **성공지표 환류**: spec.md §1 `### 성공지표` 가 존재하면, 해당 measurable target과 evidence.md 실측 결과를 대조해 "목표 달성 여부"를 1줄로 gbrain-append 인사이트에 포함한다(가치 입증 환류). §성공지표 부재(trivial 등) 시 skip.
2. 수집 출력에서 **차기 기능에 재사용 가능한 교훈만** 정제 — FID 당 ≤3건 (일회성 사실·당연한 절차는 제외)
3. 각 건마다 호출:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gbrain-append.sh "<인사이트 1줄>" --fid <FID> --tags "<tag1,tag2>" --confidence <low|medium|high>
   ```
   tags 는 **영문 소문자 kebab 2~4개** — gbrain-recall 토큰 매칭 안정성 (한국어 토큰화 한계 보완)
4. `COLLECT: EMPTY` 면 추출 skip — 기록 없음도 정직한 결과 (억지 인사이트 금지)

**[batch 모드]**: `BATCH-PERF-DONE: <FID>` 출력 **직전** 에 동일 수행 (FID 별 추출).

---

## 다음 skill

본 skill은 specops-ko Lifecycle의 **최종 단계**다.

- **단일 모드 PASS·SKIP** → PR 생성 게이트 진행 → Lifecycle 종료
- **batch 모드 PASS·SKIP** → `BATCH-PERF-DONE: <FID>` 출력 → `/start-all` 오케스트레이터로 제어 반환 (PR 게이트 skip)
- **FAIL** → `specops-ko:systematic-debugging-ko` 호출 (수정 후 chain 복귀)
- **PR 생성·머지 후** worktree/branch 정리가 필요하면 `specops-ko:finishing-a-development-branch-ko` 스킬로 마무리 (PR `state==MERGED` HARD GATE이므로 **자동 chain하지 않음** — 머지 확인 후 수동 진입)

본 performance-test-ko는 단일 모드에서 **PR 게이트 이후 어떤 스킬도 자동 chain하지 않는다**.
