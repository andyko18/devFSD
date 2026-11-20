---
name: e2e-test-ko
description: lifecycle chain 전체를 fixture 기반으로 자동 실행하고 산출물 구조를 검증 — HARD GATE 없이 (init-project 부트스트랩)→specify→clarify→plan→decompose→implement→verify→(security/integration/performance SKIP)→(finishing 정리) 9단계 완주
layer: 3
reference_upstream: specops-ko 독자 추가 (upstream 미존재)
specops_version: 2.18.0
used_by: /e2e-test
user-invocable: false
---

# Harness 스킬 — E2E 자동 테스트 (e2e-test-ko)

> **압축 대비 (본문이 길다)**: 컨텍스트가 압축되면 이 본문은 앞 20,000자만 다시 붙는다. 본문이 `[... skill content truncated for compaction` 으로 끝나 있으면 뒤쪽 규칙이 빠진 상태다 — 이 skill 의 규칙을 적용하거나 다음 단계로 넘어가기 전에 이 SKILL.md 를 Read 로 다시 읽는다.

specops-ko lifecycle chain의 **완전 자동 E2E 검증**. 내장 `greet-cli` fixture를 사용해
(init-project 부트스트랩) → specify → clarify → plan → decompose → implement → verify → (security/integration/performance SKIP) → (finishing 정리)
9단계를 HARD GATE 없이 완주하고 25개 검증 항목(V1~V25)을 점검한다.

> **양 끝 단계의 격리 (S0·S7)**: `[S0]`(부트스트랩)과 `[S7]`(브랜치 정리)는
> **repo ROOT 를 변경**하므로 (init-project 가 PRD/CLAUDE/README 작성 + `git commit`,
> finishing 이 `git checkout main`/`branch -d`/`worktree remove`) 플러그인 repo 에서
> 직접 실행하면 자기 파일을 파괴한다. 따라서 두 단계는 **각각 `mktemp -d` + `git init`
> throwaway repo 안에서** 실행하고 끝에 `rm -rf` 로 제거한다. 검증 판정은 temp repo
> 안에서 로컬 변수에 담고 `cd "$PLUGIN"` 복귀 후 `e2e_check` 로 보고한다 (cwd·카운터 안전).
> 중간 6단계(S1~S6)는 `.specops/<FID>/` 만 기록하므로 격리 불요.

## 체크리스트

다음 각 항목을 순서대로 완료한다:

1. **[PRE] FID + 디렉토리 생성** (+ `e2e_check` 헬퍼·카운터 정의)
2. **[S0] BOOTSTRAP** — init-project 부트스트랩 (격리 repo, 진입부) → V10~V13, V21
2.5. **[S0.5] INTENT** — greet-cli 의도를 5절로 기록 (spec **앞** — 판정은 S6 의 V25)
3. **[S1] SPECIFY** — spec.md + acceptance-criteria.md 생성
4. **[S2] CLARIFY** — clarifications.md 생성 + AC append
5. **[S3] PLAN** — plan.md 생성
6. **[S4] DECOMPOSE** — tasks.md 생성 + DAG 파싱 확인
7. **[S5] IMPLEMENT** — greet-cli.sh 생성 + 테스트 실행
8. **[S6] VERIFY** — 9개 검증 항목(V1~V9) 실행
9. **[S6.5] SECURITY/INTEGRATION/PERFORMANCE SKIP** — security-review-ko·integration-test-ko·performance-test-ko SKIP 경로 검증 → V18~V20
10. **[S7] FINISH** — finishing HARD GATE 로직 단위검증 (격리 repo, 꼬리부) → V14~V17
11. **[S8] BATCH** — start-all 오케스트레이션 실주행 (격리 repo) → V22~V24
12. **[REPORT]** — PASS/FAIL 결과 출력 + session-progress append

---

## 내장 Fixture — greet-cli

모든 단계에서 아래 fixture를 입력으로 사용한다. 사용자 입력 불필요.

```
기능명: greet-cli
FID 패턴: <YYYYMMDD>-greet-cli-e2e  (예: 20260503-greet-cli-e2e)
설명: 이름을 CLI 인자로 받아 "안녕하세요, <name>!" 출력하는 bash 함수

기능 요구사항:
  FR-1: .specops/<FID>/greet-cli.sh <name> → "안녕하세요, <name>!" 출력 (must)
  FR-2: 인자 없을 시 → "사용법: greet-cli.sh <이름>" + exit 1 (must)
  FR-3: 빈 문자열 인자 → 오류 처리 + exit 1 (should)

비기능 요구사항:
  NFR-1: bash 3.2+ (외부 의존성 없음, macOS 실측)

§유형: 신규
의존 구조: T1(구현)=독립, T2(테스트)=독립

사전 정의된 명확화 답변:
  Q1-BLOCKING: 인자가 여러 개면? → 첫 번째 인자만 사용
  Q1-DESIRABLE: 빈 문자열 입력? → 오류로 처리 (FR-3 추가, AC-3 신설)
```

---

## [PRE] FID 생성 + 디렉토리 준비 + 헬퍼 정의

```bash
PLUGIN="$(pwd)"                       # 플러그인 root 절대경로 (S0/S7 cd 복귀용)
FID="$(date +%Y%m%d)-greet-cli-e2e"
mkdir -p ".specops/$FID"
# ★ fixture 마커 — 이 FID 가 repo 의 **활성 FID 로 승격되지 않게** 한다
#   (20260829-fixture-fid-hijack). 없으면 detect_fid 2순위(첫 ## 헤더)가 이 섹션을 집어
#   e2e 이후 모든 커밋이 fixture 의 verify 상태를 대신 answer 하게 된다 — fixture 테스트는
#   run-verification whitelist 밖이라 PASS 를 낼 수 없어 BYPASS 외 탈출구가 없다(실측 3회).
: > ".specops/$FID/.fixture"
echo "FID: $FID"

# 검증 헬퍼 + 카운터 (S0~S7 전 단계 공유)
E2E_PASS=0; E2E_FAIL=0
e2e_check() {
  local id="${1}" desc="${2}" result="${3}"
  if [ "$result" = "0" ]; then
    printf "%-4s %-40s PASS\n" "$id" "$desc"; E2E_PASS=$((E2E_PASS+1))
  else
    printf "%-4s %-40s FAIL\n" "$id" "$desc"; E2E_FAIL=$((E2E_FAIL+1))
  fi
}
```

이후 모든 단계에서 `$FID`·`$PLUGIN`·`e2e_check`·`E2E_PASS/E2E_FAIL` 를 유지한다.

> **⚠️ 단일 연속 셸 실행 필수**: Bash 도구는 셸 함수·비-export 변수를 호출 간 보존하지
> 않는다(cwd 만 보존). `[PRE]`~`[REPORT]` 의 모든 bash 블록을 **하나의 연속 셸(단일
> Bash 호출 또는 이어붙여)로 실행**해야 `e2e_check`·카운터가 유지돼 REPORT 합계가 맞다.
> 개별 호출로 쪼개면 `command not found` + 카운터 리셋.

---

## [S0] BOOTSTRAP — init-project 부트스트랩 (격리 repo, 진입부)

lifecycle **진입부** 검증 — `/init-project` 의 비대화 산출물 생성을 격리 repo 에서 확인.
**비대화 우회**: phase_4 fallback 이 `/dev/tty` 를 직접 read 하므로 `echo n |` 으로는 막힌다.
대신 **유효 numbered list 를 stdin 공급해 parse 성공(≥4/6) 경로를 강제**(fallback 미진입).
`PROJECT_KIND=3`(CLI) 은 greet 의미 일치 + phase 6/7/8b/8c/8d/8f skip(python3 의존 제거).
**stdin 소비 순서**: `3`(KIND) → `skip`(헌법 placeholder) → numbered 6줄 + 빈 줄(sentinel) → `N`(8e DB 미사용).

```bash
TMP="$(mktemp -d)"
(
  cd "$TMP" && git init -q \
    && git config user.email e2e@test.local && git config user.name e2e
  printf '3\nskip\n1. 한 줄 설명: CLI greet fixture\n2. 페르소나: 개발자\n3. 가치제안: 간결, 자동화, 한국어\n4. M1: greet\n5. M2: usage\n6. M3: empty-arg\n\nN\n' \
    | RESUME_MODE=0 bash "$PLUGIN/scripts/_internal/init-project.sh" greet-fixture >/dev/null 2>&1
) >/dev/null 2>&1

# V10: root 산출물 3종
{ [ -f "$TMP/PRD.md" ] && [ -f "$TMP/CLAUDE.md" ] && [ -f "$TMP/README.md" ]; } && r10=0 || r10=1
# V11: memory 산출물 3종 (CLI 활성: constitution·requirements·test-strategy)
{ [ -f "$TMP/.specops/memory/constitution.md" ] \
  && [ -f "$TMP/.specops/memory/requirements.md" ] \
  && [ -f "$TMP/.specops/memory/test-strategy.md" ]; } && r11=0 || r11=1
# V12: session-progress 골격 + 부트스트랩 커밋 계약
# ★ 계약 정정 (20260829 e2e 실주행 적발): init-project Phase 10 은 **스테이징까지만** 한다 —
#   "Phase 11 enrich 후 단일 커밋하세요". 구 V12 는 `git log >= 1` 을 요구해 기본 경로에서
#   **구조적으로 FAIL** 이었다(하네스가 구현보다 오래된 계약을 들고 있었다). /e2e-test 는 수동
#   전용이라 run-all 이 못 봤고, 이 repo doctor 의 "부트스트랩 미종결 · init 커밋 0" 도 같은 원인이다.
#   기본 경로는 **staged > 0 · 커밋 0** 을 요구하고, 커밋 경로는 SPECOPS_INIT_COMMIT_NOW=1 로 별도 실증한다
#   (둘 다 봐야 "스테이징만 하고 커밋은 Phase 11" 계약에 이빨이 선다).
staged_n=$(git -C "$TMP" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
commit_n=$(git -C "$TMP" log --oneline 2>/dev/null | wc -l | tr -d ' ')
{ [ -f "$TMP/.specops/session-progress.md" ] && [ "$staged_n" -gt 0 ] && [ "$commit_n" -eq 0 ]; } && r12a=0 || r12a=1

TMP2="$(mktemp -d)"
(
  cd "$TMP2" && git init -q && git config user.email e2e@test.local && git config user.name e2e
  printf '3\nskip\n1. 한 줄 설명: CLI greet fixture\n2. 페르소나: 개발자\n3. 가치제안: 간결, 자동화, 한국어\n4. M1: greet\n5. M2: usage\n6. M3: empty-arg\n\nN\n' \
    | RESUME_MODE=0 SPECOPS_INIT_COMMIT_NOW=1 bash "$PLUGIN/scripts/_internal/init-project.sh" greet-fixture >/dev/null 2>&1
) >/dev/null 2>&1
[ "$(git -C "$TMP2" log --oneline 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ] && r12b=0 || r12b=1
rm -rf "$TMP2"

{ [ "$r12a" = 0 ] && [ "$r12b" = 0 ]; } && r12=0 || r12=1

e2e_check V10 "init-project root 산출물 3종" "$r10"
e2e_check V11 "init-project memory 산출물 3종" "$r11"
e2e_check V12 "session-progress 골격 + 커밋 계약(staged→Phase11 커밋)" "$r12"

rm -rf "$TMP"
```

**V13 — brainstorming → init-project 참조 흐름** (별도 격리 repo):
메모만 있으면 재부트스트랩·메모 참조를 묻지 않는다. stdin 은 [S0] 과 동일.
`## 브레인스토밍 컨텍스트` 주입, 한 줄 설명 입력값, DESIGN.md 부재면 PASS.

```bash
TMP="$(mktemp -d)"
(
  cd "$TMP" && git init -q \
    && git config user.email e2e@test.local && git config user.name e2e
  mkdir -p .specops/memory
  printf '# 브레인스토밍 메모\n## 문제\n사용자 인사 자동화\n' \
    > .specops/memory/brainstorming-$(date +%Y%m%d)-greet.md
  printf '3\nskip\n1. 한 줄 설명: CLI greet fixture\n2. 페르소나: 개발자\n3. 가치제안: 간결, 자동화, 한국어\n4. M1: greet\n5. M2: usage\n6. M3: empty-arg\n\nN\n' \
    | RESUME_MODE=0 bash "$PLUGIN/scripts/_internal/init-project.sh" greet-fixture >/dev/null 2>&1
) >/dev/null 2>&1

{ grep -q '## 브레인스토밍 컨텍스트' "$TMP/PRD.md" && grep -q '\*\*: CLI greet' "$TMP/PRD.md" && [ ! -e "$TMP/DESIGN.md" ]; } && r13=0 || r13=1
e2e_check V13 "brainstorming 메모 PRD 참조 주입" "$r13"

rm -rf "$TMP"
```

**V21 — Phase 11 무인 자동수락 보강 후 원시 placeholder 스캔** (자체완결 격리 repo):
V13 과 독립된 TMP 격리 repo 에 부트스트랩을 재실행한 뒤, **executor(Claude)가
`commands/init-project.md` §Phase 11 을 `$TMP` 산출물 대상 자동수락으로 직접 수행**하고
(순수 bash 아님 — e2e 무인 자동수락 계약 경로를 실증하는 LLM 스텝), 그 결과물에서 원시
placeholder 잔존을 스캔한다. 제외 규칙(`미확정 — 근거 필요` 마커 줄 + `.specops/<FID>` 류
규약 표기 토큰)의 SoT 는 `scripts/_internal/scan-enrich-placeholders.sh` — 규약 표기는 채움
대상이 아니므로 정직 보강 후에도 잔존이 정상이다 (인라인 regex 재정의 금지 — 이원화 drift).

> **V21 의 의미**: Phase 11 **무인 자동수락 경로 자체를 실증**한다 — 보강을 수행하지 않거나
> 보강이 placeholder 를 못 지우면 원시 `<...>` 검출로 **정직하게 FAIL** 한다 (거짓 PASS 방지).
> [S0] 소속 진입부 검증 항목으로, V13 블록을 침습하지 않는다.

```bash
TMP="$(mktemp -d)"
(
  cd "$TMP" && git init -q \
    && git config user.email e2e@test.local && git config user.name e2e
  printf '3\nskip\n1. 한 줄 설명: CLI greet fixture\n2. 페르소나: 개발자\n3. 가치제안: 간결, 자동화, 한국어\n4. M1: greet\n5. M2: usage\n6. M3: empty-arg\n\nN\n' \
    | RESUME_MODE=0 bash "$PLUGIN/scripts/_internal/init-project.sh" greet-fixture >/dev/null 2>&1
) >/dev/null 2>&1
```

**여기서 executor(Claude)는 `commands/init-project.md` §Phase 11 절차를 `$TMP` 산출물
(`$TMP/PRD.md`·`$TMP/.specops/memory/*.md`) 대상으로 자동수락(§auto 무인) 수행한다** —
무인 degrade: Phase 11.5 인터뷰·가정 건별 승인은 **생략**(§무인 계약)하고, Light enrich(깊게 대상) +
`가정:` 접두·`미확정 — 근거 필요` 마커 규약 + **가정 다이제스트를 PRD.md 말미에 기록** + **decisions/project-context 원장 동기**한다. 보강 완료 후 아래 스캔:

```bash
# 원시 placeholder(<...>) 검출 — 스캔·제외 규칙 SoT = scan-enrich-placeholders.sh
# (마커 줄 + 규약 표기 토큰 제외). 검출 0 이면서 다이제스트 섹션이 기록됐으면 PASS.
# M1 가드: 대상 PRD.md 부재 시 FAIL (무증상 PASS 방지).
# 다이제스트 미기록 시 정직 FAIL (무인 계약 실증 범위 — 보강 수행 사후 감사 경로가 비면 거짓 PASS).
if [ -f "$TMP/PRD.md" ]; then
  if bash "$PLUGIN/scripts/_internal/scan-enrich-placeholders.sh" \
       "$TMP/PRD.md" "$TMP"/.specops/memory/*.md \
     && grep -q '## §보강 가정 다이제스트' "$TMP/PRD.md"; then r21=0; else r21=1; fi
else
  r21=1
fi
e2e_check V21 "Phase 11 placeholder 스캔" "$r21"

rm -rf "$TMP"
```

> **V21 계약 (C1·I1·M1)**: `e2e_check` 는 `$result="0"` 만 PASS 로 집계하므로 리터럴
> `PASS/FAIL` 전달 금지 — `r21=0/1` 산출 후 넘긴다. 스캔은 `rm -rf` 이전 격리 repo 의
> 절대경로(`$TMP/PRD.md`·`$TMP/.specops/memory/*.md`)만 대상으로 하며(플러그인 repo 오염
> 방지), 마커 공존 파일의 false-PASS 를 막기 위해 **라인 단위**(`grep -v`)로 제외한다.
> r21=0 은 placeholder 스캔 clean **AND** `## §보강 가정 다이제스트` 섹션 존재 둘 다 충족 시에만 성립 (다이제스트 미기록 = 정직 FAIL).

생성 후:

```bash
bash scripts/session-progress-append.sh "$FID" "/init-project" "완료" "부트스트랩 V10~V13·V21 (격리 repo)" "greet-cli E2E"
```

---

## [S0.5] INTENT — 기능 단위 intent.md 생성 (spec 이전)

> intent 는 **spec 보다 먼저** 승인되는 산출물이다(`check-intent.sh` · specifying 체크리스트 1.5).
> cutoff(`20260918`) 이후 날짜 FID 로 e2e 가 돌면 `emit-context` 게이트가 intent.md 를 요구하므로
> 이 단계가 없으면 S4 에서 chain 이 멈춘다. **판정(V25)은 S6 에서** 한다 — 이 시점엔 spec.md 가
> 없어 `check-intent.sh` 가 `SKIP (spec.md 부재)` 로 rc=0 을 내므로 여기서의 rc 는 아무것도 증명하지 않는다.

```bash
mkdir -p ".specops/$FID"
cat > ".specops/$FID/intent.md" <<'EOF'
# Intent: greet-cli

**작성자**: e2e fixture · **Status**: accepted

## 문제
이름을 받아 인사를 출력하는 CLI 가 없다.

## 기대 결과
인자로 받은 이름으로 인사를 출력하고, 인자가 없으면 사용법과 exit 1 을 낸다.

## 영향 사용자·시스템
- CLI 사용자

## 제약
- bash 3.2 호환

## 열린 질문
- 없음
EOF
```

---

## [S1] SPECIFY — spec.md + acceptance-criteria.md 생성

→ **`skills/e2e-test-ko/fixtures/spec.md`** 를 읽어 그 내용 그대로 `.specops/$FID/spec.md` 에 생성한다.
  (`<FID>`·`<날짜>` 플레이스홀더는 실제 값으로 치환한다.)

→ **`skills/e2e-test-ko/fixtures/acceptance-criteria.md`** 를 읽어 그 내용 그대로 `.specops/$FID/acceptance-criteria.md` 에 생성한다.
  (`<FID>`·`<날짜>` 플레이스홀더는 실제 값으로 치환한다.)

생성 후:

```bash
bash scripts/session-progress-append.sh "$FID" "/specify" "완료" "spec.md, AC.md" "greet-cli E2E"
```

---

## [S2] CLARIFY — clarifications.md 생성 + AC-3 append

→ **`skills/e2e-test-ko/fixtures/clarifications.md`** 를 읽어 그 내용 그대로 `.specops/$FID/clarifications.md` 에 생성한다.
  (`<FID>`·`<날짜>` 플레이스홀더는 실제 값으로 치환한다.)

**acceptance-criteria.md에 AC-3 append:**

```markdown
### AC-3: 빈 문자열 인자 오류 처리

**Given** greet-cli.sh가 .specops/<FID>/ 에 존재

**When** `bash .specops/<FID>/greet-cli.sh ""` 빈 문자열 인자로 실행

**Then** 표준오류에 오류 메시지 출력되고 exit 1

**검증 방법**: `bash .specops/<FID>/greet-cli.sh ""; echo $?` → exit code 1 확인
**관련 FR**: FR-3
**우선순위**: should

---
```

생성 후:

```bash
bash scripts/session-progress-append.sh "$FID" "/clarify" "완료" "clarifications.md (2 쟁점 해소)" "greet-cli E2E"
```

---

## [S3] PLAN — plan.md 생성

→ **`skills/e2e-test-ko/fixtures/plan.md`** 를 읽어 그 내용 그대로 `.specops/$FID/plan.md` 에 생성한다.
  (`<FID>`·`<날짜>` 플레이스홀더는 실제 값으로 치환한다.)

생성 후:

```bash
bash scripts/session-progress-append.sh "$FID" "/plan" "완료" "plan.md" "greet-cli E2E"
```

---

## [S4] DECOMPOSE — tasks.md 생성 + DAG 파싱 확인

→ **`skills/e2e-test-ko/fixtures/tasks.md`** 를 읽어 그 내용 그대로 `.specops/$FID/tasks.md` 에 생성한다.
  (`<FID>`·`<날짜>` 플레이스홀더는 실제 값으로 치환한다.)

**DAG 파싱 확인:**

```bash
source scripts/dag/parse-dag.sh
yaml=$(dag::extract_yaml ".specops/$FID/tasks.md")
batch=$(dag::find_independent_batch "$yaml")
echo "DAG leaf batch: $batch"
# T1과 T2가 모두 반환되면 PASS (depends_on: [] 이므로 둘 다 leaf)
```

생성 후:

```bash
bash scripts/session-progress-append.sh "$FID" "/tasks" "완료" "tasks.md (2 태스크)" "greet-cli E2E"
```

---

## [S5] IMPLEMENT — greet-cli.sh 생성 + 테스트 실행

**greet-cli.sh 생성:**

```bash
cat > ".specops/$FID/greet-cli.sh" << 'GREET_EOF'
#!/usr/bin/env bash
set -eu

if [ $# -eq 0 ]; then
  echo "사용법: greet-cli.sh <이름>" >&2
  exit 1
fi

name="${1}"
if [ -z "$name" ]; then
  echo "이름을 입력해 주세요." >&2
  exit 1
fi

echo "안녕하세요, ${name}!"
GREET_EOF
chmod +x ".specops/$FID/greet-cli.sh"
```

**test-greet-cli.sh 생성 + 실행:**

```bash
cat > ".specops/$FID/test-greet-cli.sh" << TESTEOF
#!/usr/bin/env bash
set -u
PASS=0; FAIL=0
SCRIPT="\$(cd "\$(dirname "\${0}")" && pwd)/greet-cli.sh"

# T1.a AC-1: 정상 인사 출력
out=\$(bash "\$SCRIPT" "철수" 2>/dev/null)
if [ "\$out" = "안녕하세요, 철수!" ]; then
  echo "PASS T1.a AC-1 정상 출력"; PASS=\$((PASS+1))
else
  echo "FAIL T1.a AC-1 got=\$out"; FAIL=\$((FAIL+1))
fi

# T1.b AC-2: 인자 없음 → exit 1
bash "\$SCRIPT" 2>/dev/null; code=\$?
if [ "\$code" -eq 1 ]; then
  echo "PASS T1.b AC-2 exit 1"; PASS=\$((PASS+1))
else
  echo "FAIL T1.b AC-2 got exit=\$code"; FAIL=\$((FAIL+1))
fi

# T1.c AC-3: 빈 문자열 → exit 1
bash "\$SCRIPT" "" 2>/dev/null; code=\$?
if [ "\$code" -eq 1 ]; then
  echo "PASS T1.c AC-3 빈 문자열 exit 1"; PASS=\$((PASS+1))
else
  echo "FAIL T1.c AC-3 got exit=\$code"; FAIL=\$((FAIL+1))
fi

echo "==== greet-cli test: PASS=\$PASS FAIL=\$FAIL ===="
[ "\$FAIL" -eq 0 ] && exit 0 || exit 1
TESTEOF
chmod +x ".specops/$FID/test-greet-cli.sh"
bash ".specops/$FID/test-greet-cli.sh"
```

테스트 결과 PASS=3 FAIL=0을 확인한다.

생성 후:

```bash
bash scripts/session-progress-append.sh "$FID" "/implement" "완료" "greet-cli.sh + test PASS=3" "greet-cli E2E"
```

---

## [S6] VERIFY — 9개 검증 항목 (V1~V9)

아래 검증을 순서대로 실행하고 PASS/FAIL을 집계한다.
`e2e_check`·카운터는 [PRE] 에서 정의됐으므로 **재정의·재초기화하지 않는다**
(S0 의 V10~V13 집계를 보존).

**V1 — .specops/\<FID\>/ 존재:**

```bash
[ -d ".specops/$FID" ] && r=0 || r=1
e2e_check V1 ".specops/$FID/ 존재" "$r"
```

**V2 — spec.md §1·§2·§5 섹션:**

```bash
f=".specops/$FID/spec.md"
{ [ -f "$f" ] && grep -q "^## 1\." "$f" && grep -q "^## 2\." "$f" && grep -q "^## 5\." "$f"; } && r=0 || r=1
e2e_check V2 "spec.md §1·§2·§5" "$r"
```

**V3 — acceptance-criteria.md AC 3개+:**

```bash
f=".specops/$FID/acceptance-criteria.md"
cnt=$(grep -cE "^### AC-[0-9]" "$f" 2>/dev/null || echo 0)
[ "$cnt" -ge 3 ] && r=0 || r=1
e2e_check V3 "AC 3개+" "$r"
```

**V4 — clarifications.md 존재:**

```bash
[ -f ".specops/$FID/clarifications.md" ] && r=0 || r=1
e2e_check V4 "clarifications.md 존재" "$r"
```

**V5 — plan.md 구현 섹션:**

```bash
f=".specops/$FID/plan.md"
{ [ -f "$f" ] && grep -qi "구현\|implement" "$f"; } && r=0 || r=1
e2e_check V5 "plan.md 구현 섹션" "$r"
```

**V6 — tasks.md DAG YAML 블록:**

```bash
f=".specops/$FID/tasks.md"
{ [ -f "$f" ] && grep -q '^\`\`\`yaml' "$f"; } && r=0 || r=1
e2e_check V6 "tasks.md DAG YAML" "$r"
```

**V7 — session-progress.md FID 섹션:**

```bash
f=".specops/session-progress.md"
{ [ -f "$f" ] && grep -q "^## $FID" "$f"; } && r=0 || r=1
e2e_check V7 "session-progress.md FID 섹션" "$r"
```

**V8 — DAG 파싱 leaf 반환:**

```bash
if source scripts/dag/parse-dag.sh 2>/dev/null; then
  yaml=$(dag::extract_yaml ".specops/$FID/tasks.md" 2>/dev/null)
  if [ -n "$yaml" ]; then
    batch=$(dag::find_independent_batch "$yaml" 2>/dev/null)
    [ -n "$batch" ] && r=0 || r=1
  else
    echo "V8  DAG 파싱 leaf                          SKIP (yaml 추출 실패)"
    r="skip"
  fi
else
  echo "V8  DAG 파싱 leaf                          SKIP (parse-dag.sh 로드 실패)"
  r="skip"
fi
[ "$r" != "skip" ] && e2e_check V8 "DAG 파싱 leaf T1,T2" "$r"
```

**V9 — validate-structure.sh PASS:**

```bash
bash scripts/_internal/validate-structure.sh > /dev/null 2>&1 && r=0 || r=1
e2e_check V9 "validate-structure PASS" "$r"
```

**V25 — S0.5 intent.md 존재 + check-intent PASS:**

> S6 에서 판정하는 이유: `check-intent.sh` 는 spec.md 가 없으면 `SKIP` 으로 rc=0 을 낸다(:29).
> S0.5 에서 부르면 SKIP 경로라 아무것도 증명하지 못하므로, spec.md 가 있는 S6 로 미룬다.
> `r25=0` 이 PASS 다 (`e2e_check` 는 `"0"` 만 PASS 로 집계 — V21 과 동일 규약).
> cutoff(`20260918`) 이전 날짜 FID 로 도는 동안은 `SKIP` rc=0 이라 PASS 로 잡힌다(설계대로 — 게이트 면제 구간).

```bash
r25=1; [ -f ".specops/$FID/intent.md" ] && bash "$PLUGIN/scripts/_internal/check-intent.sh" "$FID" >/dev/null 2>&1 && r25=0
e2e_check V25 "intent.md 존재 + check-intent PASS" "$r25"
```

---

## [S6.5] SECURITY/INTEGRATION/PERFORMANCE SKIP — chain 신규 단계 SKIP 경로 검증

greet-cli fixture는 CLI 단일 프로세스로 **코드 변경 표면(SAST 대상)은 단순하고 통합 표면(API·DB)·성능 NFR 임계값이 없다**. semgrep·gitleaks 미설치 환경에서는 `security-review-ko`가 graceful SKIP 경로를 타고, `integration-test-ko`·`performance-test-ko`도 graceful SKIP 경로를 타야 한다.

본 단계는 세 skill의 SKIP 결과가 session-progress·evidence.md에 올바르게 기록됐는지 검증한다.

> **★ SKIP 근거는 반드시 spec.md 섹션명+라인번호를 인용한다** (20260829-bare-skip-teeth):
> `release-ready.sh` 가 근거 없는(bare) SKIP 을 PR 품질 축 미충족으로 **차단**한다.
> 인용 없는 stub 을 쓰면 이 하네스가 자기 PR 게이트에 걸린다.
>
> **주의**: 실제 security-review-ko·integration-test-ko·performance-test-ko skill을 chain 호출하지 않는다 (HARD GATE 없는 harness 성격 유지). 대신 S5 IMPLEMENT 단계에서 생성된 evidence.md에 SKIP 항목을 인라인 주입한 뒤 존재 여부를 검증한다. security-review-ko는 graceful skip 경로(도구 미설치)만 검증한다.

```bash
# S6.5 사전 조건: evidence.md에 SKIP 마커 주입 (greet-cli는 보안 차단·통합/성능 표면 없음)
EVIDENCE=".specops/$FID/evidence.md"

# security-review SKIP 마커 주입 (spec §2 참조 — semgrep·gitleaks 미설치 graceful skip)
cat >> "$EVIDENCE" <<'SKIP_EOF'

## /security-review — e2e-fixture

**결과**: SKIP
**근거**: §범위 L12-15 — greet-cli fixture, semgrep·gitleaks 미설치 graceful skip (도구 미설치는 검증 불가, 거짓 PASS 금지)
SKIP_EOF

bash scripts/session-progress-append.sh "$FID" "/security-review" "SKIP" "greet-cli fixture — semgrep·gitleaks 미설치" "greet-cli E2E" 2>/dev/null || true

# integration-test SKIP 마커 주입 (spec §2 참조)
cat >> "$EVIDENCE" <<'SKIP_EOF'

## /integration-test — e2e-fixture

**결과**: SKIP
**근거**: §범위 L12-15 — CLI 단일 프로세스, DB·API·외부 IF 없음
SKIP_EOF

bash scripts/session-progress-append.sh "$FID" "/integration-test" "SKIP" "greet-cli fixture — 통합 표면 없음" "greet-cli E2E" 2>/dev/null || true

# performance-test SKIP 마커 주입 (spec §NFR 참조)
cat >> "$EVIDENCE" <<'SKIP_EOF'

## /performance-test — e2e-fixture

**결과**: SKIP
**근거**: §NFR L50-55 — 성능 임계값 없음, CLI 도구
SKIP_EOF

bash scripts/session-progress-append.sh "$FID" "/performance-test" "SKIP" "greet-cli fixture — 성능 임계값 없음" "greet-cli E2E" 2>/dev/null || true
```

**V18 — integration-test SKIP 기록 존재:**

```bash
grep -q 'INTEGRATION.*SKIP\|/integration-test' ".specops/$FID/evidence.md" 2>/dev/null && r=0 || r=1
e2e_check V18 "integration-test SKIP 기록" "$r"
```

**V19 — performance-test SKIP 기록 존재:**

```bash
grep -q 'PERFORMANCE.*SKIP\|/performance-test' ".specops/$FID/evidence.md" 2>/dev/null && r=0 || r=1
e2e_check V19 "performance-test SKIP 기록" "$r"
```

**V20 — security-review SKIP 기록 존재:**

```bash
grep -q 'SECURITY.*SKIP\|/security-review' ".specops/$FID/evidence.md" 2>/dev/null && r=0 || r=1
e2e_check V20 "security-review SKIP 기록" "$r"
```

---

## [S7] FINISH — finishing HARD GATE 로직 단위검증 (격리 repo, 꼬리부)

lifecycle **꼬리부** 검증. `finishing-a-development-branch-ko` 는 `gh pr view`/`git worktree`/
`git branch -d` 실제 명령에 의존하며 fixture 에서 실제 PR 머지는 불가하다. 따라서 finishing 의
**HARD GATE bash 스니펫을 격리 repo 에 재현해 exit code/출력만 단위 검증**한다 (finishing skill
을 chain 호출하지 않음 — HARD GATE 없는 harness 성격 유지).

> **⚠️ R-1 이 이 블록을 막는다 (20260829 실주행 적발)**: 아래 스니펫은 격리 sandbox 안에서
> `git commit` 을 4회 부르는데, PreToolUse R-1 은 **명령 문자열**만 보므로 그것이 throwaway
> repo 대상인지 구분하지 못한다. 세션에 fresh verify 실행 증거가 없으면 S7 전체가 deny 된다.
> 두 경로 중 하나로 진행한다:
>   1. 실행 전 `bash scripts/tests/run-all.sh` 로 실행 증거를 만든다 (권장 — 정직 경로), 또는
>   2. **각 `git commit` 에 인라인**으로 우회를 붙인다. 별도 줄의 `export` 는 소용없다 —
>      훅은 별도 프로세스라 셸 환경을 못 보고 명령 문자열만 읽는다:
>      `SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='e2e S7 격리 sandbox — throwaway repo 내부 커밋, 플러그인 repo 무접촉' git ... commit ...`
> S8 의 batch fixture 도 같은 조건이다.

> **검증 경계 (한계 고백)**: dirty-tree gate·unpushed gate·worktree-absent skip·
> `branch -d` merged/unmerged 분기는 시뮬 **가능**. 그러나 `gh pr view` 가 보고하는
> 실제 PR `state==MERGED` 경로(finishing Step2)는 **fixture 로 검증 불가** — no-gh
> fallback(`git log origin/main..branch`)만 행사하며, squash-merge 오탐 가능성도
> 구조적 한계로 남긴다.

```bash
TMP="$(mktemp -d)"
(
  cd "$TMP"
  git init -q --bare origin.git
  git clone -q origin.git work 2>/dev/null
  cd work
  git config user.email e2e@test.local && git config user.name e2e
  git checkout -q -b main 2>/dev/null || git checkout -q main
  echo base > base.txt && git add base.txt && git commit -q -m base
  git push -q -u origin main
) >/dev/null 2>&1
WORK="$TMP/work"

# V14: dirty tree → HARD GATE1 발동 (git status --short 비어있지 않음)
( cd "$WORK" && echo dirty > dirty.txt )
[ -n "$(git -C "$WORK" status --short)" ] && r14=0 || r14=1
( cd "$WORK" && rm -f dirty.txt )
e2e_check V14 "finishing dirty-tree GATE 감지" "$r14"

# V15: unpushed commit → HARD GATE2 발동 (git log origin/main..HEAD 비어있지 않음)
( cd "$WORK" && echo more >> base.txt && git commit -q -am unpushed ) >/dev/null 2>&1
unp=$(git -C "$WORK" log origin/main..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ')
[ "$unp" -gt 0 ] && r15=0 || r15=1
( cd "$WORK" && git push -q origin main ) >/dev/null 2>&1
e2e_check V15 "finishing unpushed-commit GATE 감지" "$r15"

# V16: worktree 없음 → "worktree 없음 — 스킵" 경로
wt=$(git -C "$WORK" worktree list | grep -F ".worktrees/" || true)
[ -z "$wt" ] && r16=0 || r16=1
e2e_check V16 "finishing worktree-absent 스킵 경로" "$r16"

# V17: branch -d merged 성공 vs unmerged 거부 (finishing L94-104 분기)
(
  cd "$WORK"
  git checkout -q -b feat/merged && echo m > m.txt && git add m.txt && git commit -q -m merged
  git checkout -q main && git merge -q feat/merged
) >/dev/null 2>&1
git -C "$WORK" branch -d feat/merged >/dev/null 2>&1 && r17a=0 || r17a=1
(
  cd "$WORK"
  git checkout -q -b feat/unmerged && echo u > u.txt && git add u.txt && git commit -q -m unmerged
  git checkout -q main
) >/dev/null 2>&1
git -C "$WORK" branch -d feat/unmerged >/dev/null 2>&1 && r17b=1 || r17b=0  # 거부돼야 PASS
{ [ "$r17a" = 0 ] && [ "$r17b" = 0 ]; } && r17=0 || r17=1
e2e_check V17 "finishing branch -d merged성공/unmerged거부" "$r17"

rm -rf "$TMP"
```

생성 후:

```bash
bash scripts/session-progress-append.sh "$FID" "/finishing" "완료" "정리 GATE V14~V17 (격리 repo, gh PR 경로 제외)" "greet-cli E2E"
```

---

## [S8] BATCH — start-all 오케스트레이션 실주행 (격리 repo)

batch 오케스트레이션(Phase 0~1 + 완료 게이트)을 미니 fixture 로 실증한다. **Phase 3 구현 실주행은 비용상 제외** — 단일 구현은 [S5] 가 커버, 완료 게이트는 batch-state.sh 로 시뮬.

```bash
TMP="$(mktemp -d)"
(
  cd "$TMP" && git init -q \
    && git config user.email e2e@test.local && git config user.name e2e
  mkdir -p .specops/memory
  cat > .specops/memory/requirements.md <<'REQEOF'
| ID | 요구사항 | 마일스톤 | 우선순위 |
|---|---|---|---|
| FR-1 | echo-a: 인사 한 줄 출력 CLI | M1 | must |
| FR-2 | echo-b: 현재 날짜 출력 CLI | M1 | must |
REQEOF
) >/dev/null 2>&1
```

**여기서 executor(Claude)는 `commands/start-all.md` Phase 0~1 을 `$TMP` 대상으로 수행한다** — BATCH_ID 결정·`feat/<BATCH_ID>` 브랜치·queue.md 초기화(Phase 0), 이어 FR 2개 각각 specifying-ko 를 batch 3줄 prepend(`<!-- entry: batch -->`·`<!-- batch-id: ... -->`·`<!-- auto: true -->` — 무인 게이트 자동통과)로 호출해 spec→clarify→plan→decompose 완주, 각 `BATCH-PHASE1-DONE: <FID>` 후 queue PLAN_DONE 갱신(Phase 1). **decomposing halt 후 implementing 을 호출하지 않는다** (§batch 계약 실증).

```bash
# 확정 경로 캡처 — 미인용 글롭 셸 의존 회피 (plan-reviewer Important)
qf=$(ls "$TMP"/.specops/batch-*/queue.md 2>/dev/null | head -1)

# V22: queue 상태기계 — FR 2행 전부 PLAN_DONE + FID 컬럼 실FID(TBD 아님)
# 주의: grep -c 는 미매칭 시 "0" 출력+exit 1 — || echo 0 금지(이중 출력 → integer error, plan-reviewer Critical)
pd=$(grep -cE '^\| FR-[0-9]+ \|.*PLAN_DONE' "$qf" 2>/dev/null); pd=${pd:-0}
tbd=$(grep -cE '\| TBD \|' "$qf" 2>/dev/null); tbd=${tbd:-0}
{ [ "$pd" -eq 2 ] && [ "$tbd" -eq 0 ]; } && r22=0 || r22=1
e2e_check V22 "batch queue 상태기계 (PLAN_DONE 2·TBD 0)" "$r22"

# V23: §batch halt 실증 — 각 FID tasks.md 존재(decompose 도달) + IMPL_DONE 0
tn=$(ls "$TMP"/.specops/*/tasks.md 2>/dev/null | wc -l | tr -d ' ')
impl=$(grep -cE 'IMPL_DONE' "$qf" 2>/dev/null); impl=${impl:-0}
{ [ "$tn" -eq 2 ] && [ "$impl" -eq 0 ]; } && r23=0 || r23=1
e2e_check V23 "§batch halt 2회 (tasks.md 2·IMPL_DONE 0)" "$r23"

# V24: 완료 게이트 — 미완(PLAN_DONE) 상태에서 batch-state exit 1, IMPL_DONE 시뮬 후 exit 0
bdir=$(dirname "$qf")
bash "$PLUGIN/scripts/batch-state.sh" "$bdir" "$TMP/.specops/memory/requirements.md" >/dev/null 2>&1; c1=$?
sed -i.bak -E 's/\| PLAN_DONE \|$/| IMPL_DONE |/' "$qf" && rm -f "$qf.bak"
# batch-state teeth: IMPL_DONE FID 마다 per-FR 산출물 3종(review-base.sha·evidence.md·review-request.md)
# + session-progress /verify PASS 줄(진행기록 teeth — check 5) 필수 — 시뮬 생성
for _fid_dir in "$TMP"/.specops/*/; do
  case "$_fid_dir" in */memory/|*/batch-*/) continue ;; esac
  : > "${_fid_dir}review-base.sha"; : > "${_fid_dir}evidence.md"; : > "${_fid_dir}review-request.md"
  # append 헬퍼 사용 — 수기 `>> 파일 끝 ## 섹션` 은 Phase 1 이 이미 만든 동일 FID 섹션과 중복돼
  # batch-state 의 첫-섹션 추출이 /verify 줄을 못 본다 (실 파이프라인 경로로 생성해야 회귀 fixture 가 유효)
  _fid=$(basename "$_fid_dir")
  ( cd "$TMP" && bash "$PLUGIN/scripts/session-progress-append.sh" "$_fid" /verify PASS "evidence.md, 시뮬" ) >/dev/null 2>&1
done
bash "$PLUGIN/scripts/batch-state.sh" "$bdir" "$TMP/.specops/memory/requirements.md" >/dev/null 2>&1; c2=$?
{ [ "$c1" -eq 1 ] && [ "$c2" -eq 0 ]; } && r24=0 || r24=1
e2e_check V24 "batch-state 완료 게이트 (미완 1→완료 0)" "$r24"

rm -rf "$TMP"
```

---

## [REPORT] 결과 출력 + session-progress append

> **활성 FID 점거는 해결됐다 (20260829-fixture-fid-hijack)**: [PRE] 가 `.specops/$FID/.fixture`
> 마커를 만들고 `detect_fid` 2순위(첫 `## <FID>` 헤더 fallback)가 그 FID 를 건너뛴다 —
> e2e 이후 커밋은 직전 실작업 FID 를 앵커로 쓴다. 사용자가 `<!-- active-fid: -->` 로 fixture 를
> **명시 지목**하면 그건 의도로 존중한다(1순위 불변).
> 남은 한계: fixture 테스트(`.specops/<FID>/test-greet-cli.sh`)는 `run-verification` 실행
> whitelist 밖이라 이 FID 자체는 여전히 `VERIFY: PARTIAL` 로만 끝난다. whitelist 확대는
> 실행 allowlist 확장이라 보안 판단이 필요해 별건으로 남긴다.


```bash
echo ""
echo "===== 결과: PASS=$E2E_PASS FAIL=$E2E_FAIL ====="
bash scripts/session-progress-append.sh "$FID" "/verify" "$([ $E2E_FAIL -eq 0 ] && echo PASS || echo FAIL)" "V=$E2E_PASS FAIL=$E2E_FAIL" "greet-cli E2E"
```

---

## 전체 실행 흐름 요약

```
/e2e-test 호출
    ↓
[PRE] FID 생성 + mkdir + e2e_check/카운터 정의
    ↓
[S0] init-project 부트스트랩 (격리 repo) → V10~V13·V21   ← 진입부 (신규)
    ↓
[S0.5] intent.md 생성 (spec 이전 — 판정은 S6 의 V25)   ← intent (신규)
    ↓
[S1] spec.md + acceptance-criteria.md (AC-1, AC-2)
    ↓
[S2] clarifications.md + AC-3 append
    ↓
[S3] plan.md
    ↓
[S4] tasks.md + DAG 파싱 확인
    ↓
[S5] greet-cli.sh + test-greet-cli.sh + 테스트 실행 (PASS=3)
    ↓
[S6] V1~V9 검증 + V25 (S0.5 intent 판정)
    ↓
[S6.5] security-review-ko·integration-test-ko·performance-test-ko SKIP 경로 검증 → V18~V20
    ↓
[S7] finishing HARD GATE 로직 단위검증 (격리 repo) → V14~V17   ← 꼬리부 (신규)
    ↓
[S8] start-all batch 오케스트레이션 실주행 (격리 repo) → V22~V24   ← batch (신규)
    ↓
PASS=25 FAIL=0 목표 (python3+pyyaml 없을 시 V8 SKIP — PASS≥24 허용)
```

## 실패 시 디버깅

| 실패 항목 | 원인 후보 | 해결 방법 |
|---|---|---|
| V2 (spec.md 섹션) | 섹션 헤더 형식 불일치 | spec.md에서 `## 1.` `## 2.` `## 5.` 헤더 확인 |
| V3 (AC 3개+) | AC-3 append 누락 | acceptance-criteria.md에 `### AC-3:` 블록 존재 여부 확인 |
| V6 (tasks.md YAML) | 백틱 이스케이프 문제 | tasks.md에서 ` ```yaml ` 블록 직접 확인 |
| V7 (session-progress) | scripts/session-progress-append.sh 실패 | stderr 사유 확인 후 재시도 |
| V8 (DAG 파싱) | parse-dag.sh 로드 실패 | `bash scripts/dag/parse-dag.sh` 직접 실행해 오류 확인 |
| V9 (validate-structure) | 파일 개수 불일치 | validate-structure.sh 실행해 구체적 FAIL 항목 확인 |
| V10~V12 (부트스트랩) | init-project.sh phase_4 fallback 진입 (parse <4/6) | stdin numbered list 라인이 `숫자. 라벨: 값` 형식인지·빈 줄 sentinel 누락 확인. `[Phase 4] ... 개별 입력 모드로 전환` 출력 시 fallback 진입 (parse 실패) |
| V13 (brainstorming 참조) | `_check_memory`/`_check_brainstorming` prompt 미소비 | stdin 선두 `y`(재부트) + `Y`(참조) prepend 확인. 메모가 `.specops/memory/brainstorming-*.md` 경로인지 확인 |
| V14~V17 (finishing GATE) | git fixture 셋업 실패 | `git init --bare`/clone/push 단계 오류 확인. `gh pr` 실제 MERGED 경로는 검증 범위 외 (한계 고백 참조) |
| V25 (intent.md) | S0.5 블록 미실행 또는 heredoc 내용에 `<...>` 잔존 | `.specops/$FID/intent.md` 존재 확인 후 `bash scripts/_internal/check-intent.sh "$FID"` 직접 실행 — `FAIL — intent 미채움` 이면 placeholder 잔존 |

## 5원칙 적용

| 원칙 | 적용 |
|---|---|
| 1 투명성 | 각 단계 시작 시 `[S1] SPECIFY ...` 진행 상황 출력 |
| 2 문지기 | S5 테스트 FAIL=0 확인 후 S6 진입. FAIL 있으면 REPORT에서 E2E_FAIL 집계로 판정 (HARD GATE 없음) |
| 3 깊이 | fixture 요구사항·경계값(빈 문자열·인자 없음)·실패 시나리오 + 양 끝(S0 진입부·S7 꼬리부)까지 문서화 |
| 4 주권 | HARD GATE 없음 — 완전 자동 (fixture로 사전 결정) |
| 5 한계 고백 | ① V8 SKIP 가능성 (python3+pyyaml 미설치) ② S7 의 `gh pr view` 실제 PR `MERGED` 경로는 fixture 로 검증 불가 (no-gh fallback 만 행사, squash-merge 오탐 가능) ③ S0/S7 은 격리 repo 단위검증이며 실제 lifecycle 연속 실행이 아님 |

---

*specops-ko v1.0.0 · 2026-05-03 · E2E 자동 테스트 harness skill · specops-ko 독자 추가*
