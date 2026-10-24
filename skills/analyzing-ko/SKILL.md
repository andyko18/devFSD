---
name: analyzing-ko
description: 유지보수 진입 시 specifying-ko 앞에서 호출 — 변경 대상의 baseline (current-state.md) 과 외부 영향 (impact-analysis.md) 을 산출하고 사용자 검토 ★ HARD GATE 발동
layer: 2
reference_upstream: specops-ko 독자 추가 (본가 obra/superpowers@v5.0.7 미존재 — brainstorming SKILL 흡수 패턴 분석 결과)
specops_version: 2.14.0
used_by: using-specops-ko (maintenance flag = true 시), /maintain, /maintain-lite, /promote (promote-fid 분기)
---

# Engine 스킬 — 분석 (analyzing)

## 개요

유지보수 진입 (`<!-- entry: maintain -->` 또는 `<!-- entry: maintain-lite -->` args 첫 줄) 시 specifying-ko **앞에서** 호출. 기존 시스템 baseline 캡처 + 외부 영향 분석 → 두 산출물 + ★ HARD GATE → specifying-ko가 본 결과를 참조 (재분석 생략).

- **`entry: maintain`** → 아래 **풀 체크리스트** (Step 0~8)
- **`entry: maintain-lite`** → **[lite-mini 분기]** (토큰 절감 — 대상·호출자·회귀 요약만)

<HARD-GATE>
두 산출물 (`current-state.md` + `impact-analysis.md`) 사용자 검토 통과 전 specifying-ko 호출 금지.

**판정 분리 (20260806)**:
- **산출물 존재·채움** → 기계 판정. SoT = `scripts/_internal/check-maintain-baseline.sh` (구현 직전 `emit-context.sh` 가 자동 호출 — 부재·placeholder 잔존 시 dispatch 가 열리지 않는다).
- **사용자 검토 통과** → 대화 게이트라 **기계화 불가**. 본 skill Step 7 이 [y/n] 로 받는다.

> 종전엔 둘 다 산문이라 유지보수 FID 가 **analyzing 산출물 0개로 구현까지** 갔다(실측). 2차 피해가 크다 — `check-regression-ac` 의 **스키마 override 판정이 `current-state.md` 를 읽으므로**, 파일이 없으면 파괴적 스키마 변경에도 **AC-R-2(데이터 보존)가 요구되지 않는다**(안전망 무음 해제). AC-R-1 도 baseline 없이는 "무엇을 보존하는지" 근거가 없다.
</HARD-GATE>

## [lite-mini 분기] (`<!-- entry: maintain-lite -->`)

풀 Step 1~6 대신 아래만 수행한다. Step 0 FID 생성·브랜치는 동일.

1. **args**: `<!-- entry: maintain-lite -->` 첫 줄 제거 후 대상 설명 추출 (`<!-- step: true -->` 줄도 뺀다) (FID slug 규칙은 Step 0과 동일).
2. **★ strict 승격 가드**: auth·oauth·jwt·rbac·credential·migration·ALTER/DROP·결제/PII·파괴적 스키마·public API 등 strict 신호가 보이면 lite-mini **중단** — "`/maintain`으로 진행하세요" 안내 (강제 진행 금지).
3. **current-state.md (mini)**:
   - §1 변경 대상 파일·심볼·라인 범위(합산 명시) — grep/`wc -l` 실측
   - §2 직접 호출자만(1-hop, `grep -rn` head 제한) — 광역 의존 맵 생략
   - §3~§5: 기존 테스트 유무 1줄 + 관찰 동작 1~2줄 + 회귀 위험 1줄 (상세 표 생략 가능)
4. **impact-analysis.md (mini)**:
   - 회귀 영향·롤백·데이터 영향 **요약 각 3~5줄** (풀 5항목 루프 축소)
   - 스키마/데이터 변경이면 expand-contract·데이터 보존 포인트를 **반드시** 1줄 이상
   - `## 4. Advisor 협의 기록`: 불확실 없으면 `해당 없음 — lite-mini 분석 중 불확실 지점 없음` 1줄 (R-5)
5. ★ HARD GATE: "lite-mini 분석 검토. 진행? [y/n]" — [n] 시 chain 중단 (**§일괄** 이면 Step 7 의 [§일괄] 과 같이 묻지 않고 지난다 — 요약은 specifying 끝의 승인 묶음에 실린다)
6. session-progress append `/analyze 완료` 후 `specops-ko:specifying-ko` — **args 그대로** (`<!-- entry: maintain-lite -->` 유지). specifying-ko **[maintain-lite 분기]**가 참조.

> mini는 baseline·AC-R-1 근거를 남기기 위한 축소이지 analyzing **완전 skip이 아니다**.

## 체크리스트 (풀 `/maintain`)

### Step 0: FID 생성 + 디렉토리 보장 (AC-1)

**[promote-fid 분기]** (신규 — `/promote` 진입): args 둘째 줄이 `<!-- promote-fid: <FID> -->` 이면:
- **★ 검증 재실행 (분기 첫 동작 — 20260806)**: `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/promote-validate.sh <FID>` 를 실행해 `OK` 확인. `REJECT:*` 면 사유 출력 후 **분기 중단**(chain 진행 금지). 검증은 `/promote` command 레이어에도 있지만, 재개 세션·스킬 직접 호출로 여기 도달하는 경로엔 그 레이어가 없다 — `already-promoted`(spec.md 존재) FID 로 진행하면 specifying 유지보수 분기가 **진행 중 lifecycle 의 spec.md 를 덮어쓴다**.
- 해당 `<FID>` 를 그대로 사용 — **새 FID 슬러그 생성 skip**. `mkdir -p .specops/<FID>`·`bash "${CLAUDE_PLUGIN_ROOT}"/scripts/git-branch-create.sh <FID>` 는 그대로(idempotent — FID 이미 존재).
- current-state.md §1 변경 대상을 **`.specops/<FID>/freework.md` 의 `files`** + 실제 변경(`git diff HEAD` 미커밋 우선, 빈손이면 `git log` 최근 커밋 변경 fallback)으로 시드한다.
- §4 관찰 동작은 freework.md 요약 + 위 변경 상태로 캡처.
- **사용자 메시지**: promote-fid 분기는 `"FID: <FID> — mini-FID 승격 분석을 시작합니다."` 로 출력(아래 Step 0 기본 메시지 대신 — 승격 진입 명시, 투명성).
- promote-fid 신호가 **없으면** 아래 기존 FID 생성 절차를 그대로 수행한다(무손상).

args에서 `<!-- entry: maintain -->` 또는 `<!-- entry: maintain-lite -->` 첫 줄을 제거한 나머지 텍스트가 대상 설명이다. `<!-- step: true -->` 줄도 함께 뺀다(`--step` 표지 — 대상 설명·슬러그에 넣지 않는다). (`maintain-lite`면 위 **[lite-mini 분기]**로 — 본 풀 체크리스트를 돌리지 않는다.) 파일명·심볼명·핵심 명사를 우선 추출해 kebab-slug를 구성하고, `YYYYMMDD-<slug>` 형식으로 FID를 생성한다.

**FID 생성 절차:**
```bash
# 날짜 부분
date +%Y%m%d  # 예: 20260515

# 슬러그 규칙:
# - 파일명·심볼명·핵심 명사 우선
# - 공백/특수문자 → `-`, 연속 `-` → `-`, 대소문자 → 소문자
# - 최대 40자 kebab-slug
# 예시:
#   "auth.js 토큰 만료 버그" → "auth-token-expiry"
#   "skills/analyzing-ko/SKILL.md 본체 구현" → "analyzing-ko-impl"
#   "validate-task-dependencies.sh 오탐 수정" → "validate-task-dep-fix"
```

**FID 생성 후 즉시 디렉토리 보장:**
```bash
mkdir -p .specops/<FID>
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/git-branch-create.sh <FID>
# 단계 소요 측정의 기준점 — 실패해도 chain 을 막지 않는다(graceful).
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/record-metric.sh --fid <FID> --phase fid-start >/dev/null 2>&1 || true
```

**사용자에게 FID 명시**: `"FID: <FID> — 유지보수 분석을 시작합니다."`

---

### Step 1: current-state.md §1 — 변경 대상 식별 (AC-2)

`templates/current-state.md` §1 포맷으로 작성. 실제 grep 결과로 채움.

**[promote-fid 분기]** (Step 0 에서 promote-fid 감지 시 — 아래 일반 grep 대신 다음으로 §1 시드):
1. **`freework.md` 의 `files` 필드를 1차 소스**로 — 각 파일을 §1 표에 나열(`wc -l` 라인수 포함).
2. files 가 비었거나 `(빈값 — …)` 플레이스홀더면 실제 변경에서 추출:
   - `git diff HEAD --name-only` (미커밋 우선)
   - 빈손이면 `git log -n 1 --name-only --format=` (직전 1커밋 — promote 대상 자유작업=단일 커밋 가정. 다중 커밋이면 `> 한계: git log -n 1 만 시드 — 추가 커밋 수동 확인 필요` 명시)
3. **위 1·2 모두 빈손이면** §1 에 `> ⚠️ 변경 대상 미확정 — freework.md files·git diff·git log 모두 빈손. 사용자 확인 필요.` 명시(빈 §1 금지 — 한계 고백). trivial 판정 보류 후 사용자에게 변경 대상 질문.
4. 이후 trivial 판정·§2~§5 는 시드된 파일 목록 기준으로 아래 일반 절차 수행.

**탐색 명령:**
```bash
# 파일 직접 지정된 경우
ls -la <target-file>
wc -l <target-file>                           # 전체 라인 수
grep -n "<symbol>" <target-file> | head -10  # 진입점 라인 번호

# 심볼명으로 탐색 (언어 무관)
grep -rn "<symbol>" . \
  --include="*.md" --include="*.sh" \
  --include="*.py" --include="*.ts" \
  2>/dev/null | head -20

# 섹션·함수 경계 탐색
grep -n "^## \|^### \|^def \|^function \|^class \|^export " \
  <target-file> | head -20
```

**trivial 판정 (AC-3, AC-4 분기점):**
- §1에 나열한 파일들의 라인 범위를 합산
- **합산 ≤ 5 → trivial**: Step 6에서 impact-analysis.md §1·§2 생략
- **합산 > 5 → 유지보수**: Step 6에서 §1~3 전체 작성
- **★ 스키마 override (데이터 안전 — 라인수에 우선)**: §1 변경 대상에 **DB 스키마 변경**(마이그레이션 파일·`ALTER`/`DROP`/`CREATE TABLE`/타입 변경·ORM 스키마·`data-model.md`)이 포함되면 **라인수 무관 강제 비trivial** 로 판정한다. 파괴적 스키마는 1줄이어도 데이터 손실 위험이라 trivial 면제(§2 생략·AC-R 면제)를 **금지** — §2(마이그레이션·롤백) 항상 작성 + 회귀 AC(데이터 보존/역가역성) 강제.
- §1 마지막 줄에 반드시 명시: `**라인 범위 합산: N줄 → trivial|유지보수**` (스키마 override 발동 시 `→ 유지보수(스키마 override)`)

---

### Step 2: current-state.md §2 — 호출자/의존 매핑 (AC-11)

```bash
# 호출자 탐색 (파일명·심볼명으로)
grep -rn "source .*<target-basename>\|import.*<symbol>\|<symbol>" \
  commands/ skills/ hooks/ scripts/ \
  --include="*.md" --include="*.sh" \
  --include="*.py" --include="*.ts" \
  2>/dev/null | grep -v "^Binary" | head -20

# 의존 탐색 (target 파일 내 외부 참조)
grep -E "^source |^\. |^import |^require " <target-file> 2>/dev/null | head -10
```

동적 호출자(runtime 결정)는 정적 분석으로 미식별 — 이 경우 `> 한계: 동적 호출자 — 정적 분석 불가` 명시 (AC-14).

---

### Step 3: current-state.md §3 — 기존 테스트 커버리지 (AC-11)

```bash
# 대상 파일명·심볼명으로 테스트 파일 탐색
find scripts/tests -name "*.sh" 2>/dev/null \
  | xargs grep -l "<target-basename>" 2>/dev/null

find . \( -name "test_*.py" -o -name "*.test.ts" \) -print0 2>/dev/null \
  | xargs -0 grep -l "<symbol>" 2>/dev/null

# 커버되지 않는 경로: 탐색 결과 없으면
echo "> 관련 테스트 파일 없음 — 회귀 AC 추가 권고"
```

---

### Step 4: current-state.md §4 — 관찰 가능 동작 (Baseline) (AC-11, AC-15)

**실행 가능한 경우 (스크립트·CLI):**
```bash
# 현재 동작 2~3건 직접 실행·캡처
bash <target-script> 2>&1 | head -5        # 사용법·오류 케이스
bash <target-script> <normal-input> 2>&1   # 정상 케이스
bash <target-script> <edge-input> 2>&1     # 경계 케이스
```
결과를 §4 표에 그대로 인용.

**실행 불가한 경우 (SKILL.md·설정 파일·문서 등 — AC-15):**
```bash
# 관련 테스트 실행 결과 인용
bash <related-test-script> 2>&1 | tail -5
```
§4 첫 줄: `> ⚠️ 직접 실행 불가 — <이유>. 아래는 관련 테스트/문서 기반 baseline.`
관련 테스트도 없으면: `> ⚠️ 직접 실행 불가 + 관련 테스트 없음 — spec.md 기대 동작 기준으로 baseline 기술.`

---

### Step 5: current-state.md §5 — 회귀 위험 메모 (AC-11)

1줄 요약. 형식: `- <변경이 X 흐름에 영향 → Y 케이스 검증 필요>`

예시:
```
- analyzing-ko SKILL.md 변경 → /maintain 진입 chain 전체 영향
  (using-specops-ko → analyzing-ko → specifying-ko [유지보수 분기])
```

---

### Step 6: impact-analysis.md 작성 (AC-4~AC-6)

> 산출 포맷의 단일 소스: `templates/impact-analysis.md` — 아래 §1~§3 인라인 정의와 충돌 시 템플릿 우선 (고아 템플릿 방지).

**gh CLI 가용성 감지 (AC-5, AC-6):**
```bash
gh --version 2>/dev/null && echo "gh available" || echo "gh unavailable"
```

**trivial 시 (§1 라인 합산 ≤ 5 — AC-3):**
- §1(외부 영향)·§2(마이그레이션·롤백) 생략
- §3(히스토리)만 작성

**비trivial 시 (> 5 — AC-4):**

§1 — 외부 영향:
```bash
# 공유 모듈 사용처 탐색
grep -rn "<target-module>" . \
  --include="*.md" --include="*.sh" 2>/dev/null | head -10
# API/DB 변경 여부: "해당 없음" 또는 구체 설명
```

§2 — 마이그레이션·롤백:
```bash
# 롤백 가능성 확인
git log --oneline -3  # 마지막 커밋 SHA
# → git revert <SHA> 로 원복 가능 여부 판단
```

**★ 코드 롤백 ≠ 데이터 롤백 (DB 스키마 변경 시 필수 구분)**:
- `git revert` 는 **코드만** 원복한다 — 이미 적용된 DB 스키마·데이터는 복원되지 않는다.
- 파괴적 스키마 변경(`ALTER TABLE DROP COLUMN/TABLE`, 타입 변경, NOT NULL 추가)은 git revert 로 **데이터 복원 불가** → 별도 **데이터 마이그레이션 down**(reverse migration) 이 필요하며, drop 류는 down 으로도 원본 데이터 복구 불가임을 명시.
- **안전 패턴 — expand-contract**: ① 신 컬럼 추가 + backfill → ② 코드 전환 → ③ 구 컬럼 제거를 **별도 릴리즈로 분리**(즉시 drop 금지). 이렇게 각 단계가 가역.
- `impact-analysis.md` 의 "데이터 이전 필요" 가 yes 면 → 롤백 전략에 **data-down + 데이터 보존 정책**(백업·shadow 컬럼)을 명시한다. decomposing-ko 의 마이그레이션 forward+reverse 쌍 분해로 이어진다.

§3 — 관련 PR·이슈 히스토리:

**gh 가용 시 (AC-5):**
```bash
gh pr list --search "<target-basename>" --state merged --limit 5
gh issue list --search "<target-basename>" --limit 5
```

**gh 미가용 시 (AC-6):**
```bash
# git log 는 --limit 미지원 — -n N 사용 (gh CLI 의 --limit 와 혼동 주의)
git log --oneline --grep="<target-basename>" -n 10
git log --oneline --grep="<symbol>" -n 5
```
§3 첫 줄: `> 데이터 출처: git log (gh CLI 미가용 — 이슈 추적 미수행)` (AC-6, AC-14)

---

**§4 — Advisor 협의 기록 (advisor-ko 계약)**: impact 5 항목 작성 중 외부 영향 범위·롤백 전략이 애매하면 `advisor()` 호출 후 §4 표에 기록. 불확실 지점 없으면 "해당 없음 — 본 분석 중 불확실 지점 없음" 1줄 (R-5 거버넌스가 impact-analysis.md 수정 시 본 섹션을 검사).

---

### Step 7: ★ HARD GATE (AC-7, AC-8)

**[§일괄]** (args 앞쪽 주석 줄에 `<!-- step: true -->` 가 없을 때 — `../specifying-ko/SKILL.md` 의 §일괄 판정과 같다): [y/n] 을 묻지 않고 Step 8 로 간다. 분석 요약(변경 대상 · 보존할 동작 · 회귀 위험)은 승인 묶음에 실린다(`../specifying-ko/once-approval.md`) — 한 줄 출력: `분석 검토는 승인 묶음으로 넘깁니다(§일괄)`. 아래는 `--step` 일 때의 동작이다.

두 산출물 경로를 명시하고 사용자 응답 대기:

**trivial 시 (§1 합산 ≤ 5):**
```
분析 산출물 작성 완료 (trivial 자동 판정 — §1 라인 합산 N줄 ≤ 5):
  - .specops/<FID>/current-state.md
  - .specops/<FID>/impact-analysis.md (§1·§2 생략, §3만 작성)

분析 결과 검토. 진행? [y/n]
```

**비trivial 시 (§1 합산 > 5):**
```
분析 산출물 작성 완료:
  - .specops/<FID>/current-state.md  (§1 라인 합산: N줄 → 유지보수)
  - .specops/<FID>/impact-analysis.md

분析 결과 검토. 진행? [y/n]
```

**[y]** → Step 8으로 진행
**[n]** → "재분석이 필요하거나 수정할 항목을 알려주세요." 출력 후 **chain 중단** (AC-8)

---

### Step 8: session-progress append + chain (AC-9, AC-10)

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /analyze 완료 "current-state.md, impact-analysis.md"
```

이어서 즉시 `specops-ko:specifying-ko` 호출. **args 그대로 전달** — `<!-- entry: maintain -->` 또는 `<!-- entry: maintain-lite -->` 첫 줄 유지 (AC-10).

---

## 5원칙 주입

| 원칙 | 본 skill 적용 |
|---|---|
| 1 **투명성** | grep·gh 출력 결과를 산출물에 직접 인용 (요약만 금지) (AC-13) |
| 2 **문지기** | HARD GATE 전 specifying-ko 호출 절대 금지 |
| 3 **깊이** | 정적 grep 한계 시 "동적 호출자 미식별" 명시 — 추측 금지. trivial 임계값(≤5줄) 적용 시 경계 판단 신중히 |
| 4 **주권** | HARD GATE [n] 시 chain 즉시 중단, 사용자 재지시 대기 (AC-8) |
| 5 **한계 고백** | 동적 호출자 미식별·gh 미가용·실행 불가 대상 → 명시 문구 포함 (AC-14). lite-mini는 축소 범위 명시 |

## 안티패턴

- **변경 규모 평가 생략** — §1 라인 합산 명시 없으면 specifying-ko §유형 라벨 부정확
- **gh 강제 사용** — gh 미가용 환경에서 HARD GATE 차단 금지. git log fallback 항상 준비 (AC-6)
- **§4 플레이스홀더** — 실행 불가 시에도 관련 테스트·문서 기반 baseline 채움. 빈 표 금지 (AC-15)
- **specifying-ko 본문 중복** — 본 skill은 분석만. specifying-ko [유지보수·maintain-lite 분기]가 산출물을 참조 (재분석 안 함)
- **FID 미확인 진행** — Step 0에서 FID 사용자에게 명시 후 진행
- **maintain-lite에서 analyzing 완전 skip** — mini라도 두 산출물 + HARD GATE 필수
- **strict를 lite-mini로 우회** — 승격 가드 무시 금지

## 다음 skill

```
Skill: specops-ko:specifying-ko
```

args 그대로 전달. `entry: maintain` → specifying [유지보수 분기]. `entry: maintain-lite` → specifying [maintain-lite 분기].
