#!/usr/bin/env bash
# foundation 기술스택 확정 게이트 (clarify 층 봉합) — 20260806
#
# clarifying-ko 는 "§유형=foundation 이고 architecture 문서에 placeholder 가 있으면
#   기술 프레임워크 확정을 BLOCKING 으로 강제, RESOLVED 전 planning 진입 차단" 을 선언한다.
#   판정기(check-decisions-ledger.sh)를 만들었지만 **호출은 여전히 산문 의무**였다 —
#   clarify 단계엔 스크립트가 반드시 지나는 관문이 없기 때문.
# 그래서 결정의 **증거**를 다음 하드 관문(emit-context, 구현 직전)에서 검사한다.
#   증거 = ① 원장에 스택 확정 행(clarifying HARD 규약: RESOLVED → decisions.md upsert)
#        또는 ② clarifications.md 에 스택 관련 RESOLVED 기록
#   둘 다 없으면 = 아무도 스택을 정하지 않았는데 구현으로 넘어가는 것 → 차단.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-stack-decided.sh"

_base() {  # $1=dir $2=fid $3=§유형 $4=arch placeholder(y/n)
  mkdir -p "$1/.specops/$2" "$1/.specops/memory"
  printf '**§유형**: %s\n' "$3" > "$1/.specops/$2/spec.md"
  if [ "$4" = "y" ]; then
    printf '# 프론트 아키텍처\n- 프레임워크: <확정 필요>\n' \
      > "$1/.specops/memory/frontend-architecture.md"
  else
    printf '# 프론트 아키텍처\n- 프레임워크: React 19\n' \
      > "$1/.specops/memory/frontend-architecture.md"
  fi
}
_ledger() {  # $1=dir $2=행 (빈 문자열이면 골격 예시행만)
  { printf '| DECISION-ID | 주제 | 확정값 | 출처 | 갱신일 |\n|---|---|---|---|---|\n'
    printf '| D-001 | (예시) UI 유무 | 있음 | init Phase11.5 | YYYY-MM-DD |\n'
    [ -n "$2" ] && printf '%s\n' "$2"
  } > "$1/.specops/memory/decisions.md"
  return 0
}

# T1: ★ foundation + arch placeholder + 원장 골격(예시행만) + clarifications 없음 → FAIL
TD=$(mktemp -d); _base "$TD" 20260806-f foundation y; _ledger "$TD" ""
out=$(cd "$TD" && bash "$CHK" 20260806-f 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T1 스택 결정 증거 전무 → FAIL" || nope "T1" "rc=$rc out=$out"
rm -rf "$TD"

# T2: 원장에 실제 스택 확정 행 → PASS
TD=$(mktemp -d); _base "$TD" 20260806-f foundation y
_ledger "$TD" '| D-002 | 프론트엔드 스택 | React 19 + Vite | clarify 20260806-f | 2026-08-06 |'
(cd "$TD" && bash "$CHK" 20260806-f >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T2 원장 스택 확정 → PASS" || nope "T2" "rc=$rc"
rm -rf "$TD"

# T3: 원장엔 없지만 clarifications.md 에 스택 RESOLVED → PASS (upsert 누락은 경고)
TD=$(mktemp -d); _base "$TD" 20260806-f foundation y; _ledger "$TD" ""
printf '## Q-1 기술 프레임워크\nstatus: RESOLVED\n답변: React 19 + Vite\n' \
  > "$TD/.specops/20260806-f/clarifications.md"
out=$(cd "$TD" && bash "$CHK" 20260806-f 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'upsert' \
  && ok "T3 clarifications RESOLVED → PASS + upsert 경고" || nope "T3" "rc=$rc out=$out"
rm -rf "$TD"

# T4: clarifications 에 스택 언급은 있으나 status: ASSUMED → 증거 불인정 → FAIL
TD=$(mktemp -d); _base "$TD" 20260806-f foundation y; _ledger "$TD" ""
printf '## Q-1 기술 프레임워크\nstatus: ASSUMED\n**가정 근거**: 흔한 선택\n' \
  > "$TD/.specops/20260806-f/clarifications.md"
(cd "$TD" && bash "$CHK" 20260806-f >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T4 ASSUMED → 증거 불인정 FAIL" || nope "T4" "rc=$rc"
rm -rf "$TD"

# T5: arch 문서에 placeholder 없음(이미 확정) → 게이트 비발동
TD=$(mktemp -d); _base "$TD" 20260806-f foundation n; _ledger "$TD" ""
(cd "$TD" && bash "$CHK" 20260806-f >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T5 arch placeholder 없음 → skip" || nope "T5" "rc=$rc"
rm -rf "$TD"

# T6: §유형≠foundation → skip (일반 기능은 본 게이트 대상 아님)
TD=$(mktemp -d); _base "$TD" 20260806-f 신규 y; _ledger "$TD" ""
(cd "$TD" && bash "$CHK" 20260806-f >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T6 비-foundation → skip" || nope "T6" "rc=$rc"
rm -rf "$TD"

# T7: arch 문서 자체가 없음 → skip (UI 없는 프로젝트 등)
TD=$(mktemp -d); mkdir -p "$TD/.specops/20260806-f" "$TD/.specops/memory"
printf '**§유형**: foundation\n' > "$TD/.specops/20260806-f/spec.md"
(cd "$TD" && bash "$CHK" 20260806-f >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T7 arch 문서 부재 → skip" || nope "T7" "rc=$rc"
rm -rf "$TD"

# T8: spec.md 부재 → fail-open
TD=$(mktemp -d); mkdir -p "$TD/.specops/20260806-f"
(cd "$TD" && bash "$CHK" 20260806-f >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T8 spec.md 부재 → fail-open" || nope "T8" "rc=$rc"
rm -rf "$TD"

# T9: emit-context 배선 (구현 직전 하드 관문)
grep -q 'check-stack-decided.sh' "$PLUGIN/scripts/dag/emit-context.sh" \
  && ok "T9 emit-context 배선" || nope "T9" "미배선 — clarify 층 여전히 산문"

# T10: clarifying-ko 가 후속 관문 존재를 명시 (건너뛰어도 잡힌다는 계약)
grep -q 'check-stack-decided.sh' "$PLUGIN/skills/clarifying-ko/SKILL.md" \
  && ok "T10 clarifying-ko 후속 관문 명시" || nope "T10" "스킬 본문 미갱신"

# ── T11~: clarifications.md 의 **실제 형식** (20261009 /start-foundation 점검) ──────
# 결함: 경로 ②가 읽던 형식(`## Q` 아래 `status: RESOLVED`)은 위 T3·T4 픽스처에만 있었다.
#   clarifying-ko 가 규정한 형식은 파일 머리 `**status**: RESOLVED` 한 줄 + `## Q1 · <주제> · BLOCKING` 블록이고,
#   실기록 foundation clarifications 3건이 전부 그 형식이다 — 판정기와 실파일이 구조적으로 만날 수 없었다.
_clar() {  # $1=id $2=설명 $3=기대 rc · stdin=clarifications.md 본문
  local td out rc
  td=$(mktemp -d); _base "$td" 20260806-f foundation y; _ledger "$td" ""
  cat > "$td/.specops/20260806-f/clarifications.md"
  out=$(cd "$td" && bash "$CHK" 20260806-f 2>&1); rc=$?
  [ "$rc" -eq "$3" ] && ok "$1 $2" || nope "$1" "rc=$rc(기대 $3) out=$out"
  rm -rf "$td"
}
_clar T11 '파일 머리 **status**: RESOLVED + 스택 Q 블록에 답 → PASS' 0 <<'EOF'
# Clarifications — 20260806-f

**status**: RESOLVED
**timestamp**: 2026-08-06T00:00:00Z

## Q1 · 프론트 프레임워크 · BLOCKING

**질문**: 어느 조건에 최적화할까요?

**답변**: React 19 + Vite

**영향**: AC-2
EOF
_clar T12 '채우지 않은 머리줄(RESOLVED | BLOCKED | ASSUMED)은 확정이 아니다 → FAIL' 1 <<'EOF'
# Clarifications — 20260806-f

**status**: RESOLVED | BLOCKED | ASSUMED

## Q1 · 프론트 프레임워크 · BLOCKING

**답변**: React 19 + Vite
EOF
_clar T13 '머리는 RESOLVED 여도 그 Q 가 ASSUMED 표기면 결정이 아니다 → FAIL' 1 <<'EOF'
# Clarifications — 20260806-f

**status**: RESOLVED

## Q1 · 프론트 프레임워크 · BLOCKING · ASSUMED

**답변 (자동)**: React 19

**가정 근거**: 흔한 선택
EOF
_clar T14 '머리는 RESOLVED 인데 스택 Q 에 답이 없다 → FAIL' 1 <<'EOF'
# Clarifications — 20260806-f

**status**: RESOLVED

## Q1 · 프론트 프레임워크 · BLOCKING

**질문**: 어느 조건에 최적화할까요?

**답변**: <사용자 응답>
EOF
_clar T15 '머리가 BLOCKED → FAIL' 1 <<'EOF'
# Clarifications — 20260806-f

**status**: BLOCKED

## Q1 · 프론트 프레임워크 · BLOCKING

**답변**: React 19 + Vite
EOF
_clar T16 '머리 RESOLVED 지만 스택을 다룬 Q 가 없다 → FAIL' 1 <<'EOF'
# Clarifications — 20260806-f

**status**: RESOLVED

## Q1 · 자격증명 출처 · BLOCKING

**답변**: 환경변수
EOF
_clar T17 '스택 Q 가 둘 — 하나는 가정, 하나는 답 있음 → PASS' 0 <<'EOF'
# Clarifications — 20260806-f

**status**: RESOLVED

## Q1 · 백엔드 프레임워크 · DESIRABLE · ASSUMED

**답변 (자동)**: FastAPI

## Q2 · 프론트 프레임워크 · BLOCKING

**답변**: React 19 + Vite
EOF

# ── T18~: 독립 리뷰 반영 ────────────────────────────────────────────────────────
_clar T18 'Q 블록 안의 3단 소제목이 블록을 끊지 않는다 → PASS' 0 <<'EOF'
# Clarifications — 20260806-f

**status**: RESOLVED

## Q1 · 프론트 프레임워크 · BLOCKING

### 옵션

- React
- Vue

**답변**: React 19 + Vite
EOF
_clar T19 '답을 다음 줄에 적은 형태 → PASS' 0 <<'EOF'
# Clarifications — 20260806-f

**status**: RESOLVED

## Q1 · 프론트 프레임워크 · BLOCKING

**답변**:
React 19 + Vite

**영향**: AC-2
EOF
_clar T20 '답 자리 다음이 곧바로 다음 필드면 빈 답이다 → FAIL' 1 <<'EOF'
# Clarifications — 20260806-f

**status**: RESOLVED

## Q1 · 프론트 프레임워크 · BLOCKING

**답변**:

**영향**: AC-2
EOF
_clar T21 '답이 "미정" 이면 결정이 아니다 → FAIL' 1 <<'EOF'
# Clarifications — 20260806-f

**status**: RESOLVED

## Q1 · 프론트 프레임워크 · BLOCKING

**답변**: 미정
EOF
_clar T22 'CRLF + 빈 답 → FAIL' 1 < <(printf '# C\r\n\r\n**status**: RESOLVED\r\n\r\n## Q1 · 프레임워크 · BLOCKING\r\n\r\n**답변**: \r\n')
_clar T23 'CRLF + 정상 답 → PASS' 0 < <(printf '# C\r\n\r\n**status**: RESOLVED\r\n\r\n## Q1 · 프레임워크 · BLOCKING\r\n\r\n**답변**: Next.js\r\n')

# ── T24~: 미확정 판정·사각 (20261009 /start-foundation 점검 묶음 D) ──────────────────
# 결함 ①: 아키텍처 문서의 미확정 여부를 범용 미채움 스캐너로 봤다 — 다 채운 문서의 `useState<string>`·`<cmd>` 를
#   미확정으로 읽어, 원장 행이 없으면 "스택 확정 증거 없음" 으로 막았다(거짓 차단). 템플릿의 자리표시자와
#   한글 꺾쇠 표기(`<미확정 — 근거 필요>`)만 미확정으로 본다. 경로 규약 표기(`<feature>`·`<name>`)는 채울 자리가 아니다.
_arch_case() {  # $1=id $2=설명 $3=기대 rc $4=출력에 있어야 할 문자열(선택) · stdin=frontend-architecture.md 본문
  local td out rc
  td=$(mktemp -d); mkdir -p "$td/.specops/20260806-f" "$td/.specops/memory"
  printf '**§유형**: foundation\n' > "$td/.specops/20260806-f/spec.md"
  cat > "$td/.specops/memory/frontend-architecture.md"
  _ledger "$td" "${ARCH_LEDGER:-}"
  out=$(cd "$td" && bash "$CHK" 20260806-f 2>&1); rc=$?
  if [ "$rc" -eq "$3" ] && { [ -z "${4:-}" ] || printf '%s' "$out" | grep -qF -- "$4"; }; then ok "$1 $2"
  else nope "$1" "rc=$rc(기대 $3) out=$out"; fi
  rm -rf "$td"
}
ARCH_LEDGER=''
_arch_case T24 '다 채운 문서의 코드 표기(useState<string>·<cmd>)는 미확정이 아니다 → 비발동' 0 '이미 확정' <<'EOF'
# 프론트 아키텍처

- 프레임워크: React 19 (`app/<feature>/page.tsx` 파일 기반 · 화면 문서 `screens/<name>.md`)
- 상태: `useState<string>` 로 폼 값을 둔다
- 실행: `pnpm --filter web <cmd>`
- 기능 폴더: `src/features/<feature>/` · 화면: `screens/<name>.md`
EOF
_arch_case T25 '템플릿 자리표시자가 남으면 미확정 → 증거 없으면 FAIL' 1 'STACK-DECIDED: FAIL' <<'EOF'
# 프론트 아키텍처

- 프레임워크: <React 18 / Vue 3 / Svelte / Solid / Next.js / Nuxt>
EOF
_arch_case T26 '스택 줄의 <미확정 — 근거 필요> → 미확정 → FAIL + 그 줄을 보여 준다' 1 '주 프레임워크**: <미확정' <<'EOF'
# 프론트 아키텍처

- **주 프레임워크**: <미확정 — 근거 필요>
- **언어**: TypeScript
EOF
_arch_case T26b '스택이 아닌 줄(호스팅)의 미확정은 이 게이트의 일이 아니다 → 비발동' 0 '이미 확정' <<'EOF'
# 프론트 아키텍처

- **주 프레임워크**: React 19
- **언어**: TypeScript
- **호스팅**: <미확정 — 근거 필요> (Vercel / Netlify 중 택일)
- 테스트: <Vitest + Testing Library / Jest + RTL>
EOF
_arch_case T26c '손대지 않은 템플릿 그대로 → 미확정 → FAIL' 1 'STACK-DECIDED: FAIL' < "$PLUGIN/templates/frontend-architecture.md"
# T26c2: FAIL 안내의 확인 명령은 절대경로다 — 하류 저장소에는 scripts/ 가 없다
_arch_case T26c2 'FAIL 안내의 확인 명령이 플러그인 절대경로' 1 "확인: bash \"$PLUGIN/scripts/_internal/check-decisions-ledger.sh\" --list" < "$PLUGIN/templates/frontend-architecture.md"
# 템플릿과 글자가 다른 자리표시자도 스택 줄의 **값 자리**에 있으면 미확정이다 (독립 리뷰: 템플릿 토큰만 대조하면 놓친다)
okv=ok
for v in '<Express / Fastify>' '<React>' '<확정 필요>' '`<TypeScript>`' '**<Next.js 또는 Remix>**'; do
  td=$(mktemp -d); mkdir -p "$td/.specops/20260806-f" "$td/.specops/memory"; printf '**§유형**: foundation\n' > "$td/.specops/20260806-f/spec.md"
  printf '# FE\n\n- **주 프레임워크**: %s\n- **호스팅**: Vercel\n' "$v" > "$td/.specops/memory/frontend-architecture.md"
  (cd "$td" && bash "$CHK" 20260806-f >/dev/null 2>&1); rc=$?; [ "$rc" -eq 1 ] || okv="no($v → rc=$rc)"
  printf '# FE\n\n| 항목 | 값 |\n|---|---|\n| 언어 | %s |\n' "$v" > "$td/.specops/memory/frontend-architecture.md"
  (cd "$td" && bash "$CHK" 20260806-f >/dev/null 2>&1); rc=$?; [ "$rc" -eq 1 ] || okv="no(표: $v → rc=$rc)"
  rm -rf "$td"
done
[ "$okv" = ok ] && ok "T26d 스택 줄의 값이 꺾쇠 표기로 시작(목록·표 5종) → 미확정 → FAIL" || nope "T26d" "$okv"
# 템플릿의 자리표시자는 값 **중간**에 남아 있어도 미확정이다(값 자리 규칙과 별개의 근거 — 템플릿 토큰 대조)
_arch_case T26h '스택 줄 값 중간에 남은 템플릿 선택지 토큰 → 미확정 → FAIL' 1 'frontend-architecture.md:3:' <<'EOF'
# 프론트 아키텍처

- **주 프레임워크**: 아직 못 정함 — <React 18 / Vue 3 / Svelte / Solid / Next.js / Nuxt> 중 택일
EOF
# 값 중간의 코드 표기·한글 경로 규약·비교식·펜스 안은 미확정이 아니다
_arch_case T26e '스택 줄 값 중간의 코드 표기·한글 경로 규약 → 비발동' 0 '이미 확정' <<'EOF'
# 프론트 아키텍처

- **주 프레임워크**: Next.js 15 — `app/<페이지명>/page.tsx` 파일 기반 · `useQuery<사용자[]>()`
- **런타임**: Node 22 (`node --import <loader>` 로 계측) · 응답 < 200ms 이고 처리량 > 100
- **언어**: TypeScript — 제네릭 `Result<T, E>` 를 쓴다

```ts
// 프레임워크: <여기는 코드펜스 안>
```
EOF
# 경로에 framework·runtime 이 들어 있어도 줄 내용만 본다 (절대경로 SPECOPS_ROOT)
td=$(mktemp -d); d2="$td/my-framework-runtime-x"; mkdir -p "$d2/.specops/20260806-f" "$d2/.specops/memory"
printf '**§유형**: foundation\n' > "$d2/.specops/20260806-f/spec.md"
printf '# FE\n\n- **주 프레임워크**: React 19\n- **호스팅**: <미확정 — 근거 필요>\n' > "$d2/.specops/memory/frontend-architecture.md"
out=$(cd / && SPECOPS_ROOT="$d2/.specops" bash "$CHK" 20260806-f 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '이미 확정' && ok "T26f 경로에 framework·runtime 이 든 프로젝트 — 호스팅 미확정은 스택 줄이 아니다" || nope "T26f" "rc=$rc out=$out"
rm -rf "$td"
# 문서가 둘이고 같은 행 번호에 미확정이 있어도 둘 다 보여 준다
td=$(mktemp -d); mkdir -p "$td/.specops/20260806-f" "$td/.specops/memory"; printf '**§유형**: foundation\n' > "$td/.specops/20260806-f/spec.md"
printf '# FE\n\n- **주 프레임워크**: <미확정 — 근거 필요>\n' > "$td/.specops/memory/frontend-architecture.md"
printf '# BE\n\n- **런타임**: <미확정 — 근거 필요>\n' > "$td/.specops/memory/backend-architecture.md"
out=$(cd "$td" && bash "$CHK" 20260806-f 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'frontend-architecture.md:3:' && printf '%s' "$out" | grep -q 'backend-architecture.md:3:' \
  && ok "T26g 두 문서의 미확정 줄을 문서 이름과 함께 모두 보여 준다" || nope "T26g" "rc=$rc out=$out"
rm -rf "$td"
# 결함 ②: 결정 원장의 확정값이 백틱으로 감싼 자리표시자면 "확정" 으로 읽었다(foundation-kind.sh 는 벗겨 읽는다 — 같은 표를 두 판정기가 다르게 읽었다)
ARCH_LEDGER='| D-002 | 프론트 프레임워크 | `<미확정 — 근거 필요>` | init | 2026-10-09 |'
_arch_case T27 '원장 확정값이 백틱 자리표시자 → 확정 아님 → FAIL' 1 'STACK-DECIDED: FAIL' <<'EOF'
# 프론트 아키텍처

- 프레임워크: <React 18 / Vue 3 / Svelte / Solid / Next.js / Nuxt>
EOF
ARCH_LEDGER='| D-002 | 프론트 프레임워크 | `React 19` | clarify | 2026-10-09 |'
_arch_case T28 '원장 확정값이 백틱으로 감싼 실값 → 확정' 0 'decisions.md 확정 행' <<'EOF'
# 프론트 아키텍처

- 프레임워크: <React 18 / Vue 3 / Svelte / Solid / Next.js / Nuxt>
EOF
ARCH_LEDGER=''

# 결함 ③: 아키텍처 문서가 없는 프로젝트(CLI·라이브러리 · init 을 거치지 않은 저장소)는 통째로 SKIP 이라
#   스택 근거가 하나도 없어도 조용히 구현에 들어갔다. 막지는 않되(그런 프로젝트에 아키텍처 문서를 강제하지 않는다) 알린다.
_noarch() {  # $1=id $2=설명 $3=NOTE 기대(y|n) $4=원장 행 $5=clarifications 본문
  local td out rc n
  td=$(mktemp -d); mkdir -p "$td/.specops/20260806-f" "$td/.specops/memory"
  printf '**§유형**: foundation\n' > "$td/.specops/20260806-f/spec.md"
  [ -n "$4" ] && _ledger "$td" "$4"
  [ -n "$5" ] && printf '%b' "$5" > "$td/.specops/20260806-f/clarifications.md"
  out=$(cd "$td" && bash "$CHK" 20260806-f 2>&1); rc=$?
  n=n; printf '%s' "$out" | grep -q '^STACK-DECIDED: NOTE' && n=y
  [ "$rc" -eq 0 ] && [ "$n" = "$3" ] && ok "$1 $2" || nope "$1" "rc=$rc note=$n(기대 $3) out=$out"
  rm -rf "$td"
}
_noarch T29 '아키텍처 문서 없음 + 스택 근거 없음 → 통과하되 알린다' y '' ''
_noarch T30 '아키텍처 문서 없음 + 원장에 구현 언어 행 → 조용히 통과' n '| D-002 | 구현 언어 | Python 3.12 | init | 2026-10-09 |' ''
_noarch T31 '아키텍처 문서 없음 + 원장은 예시 행뿐 → 알린다' y '' ''
_noarch T32 '아키텍처 문서 없음 + clarifications 에 스택 RESOLVED → 조용히 통과' n '' '# C\n\n**status**: RESOLVED\n\n## Q1 · 런타임·프레임워크 · BLOCKING\n\n**답변**: Node 22\n'
_noarch T33 '아키텍처 문서 없음 + 무관한 원장 행만 → 알린다' y '| D-002 | 배포 방식 | 수동 | init | 2026-10-09 |' ''

# T34: emit-context 가 그 알림을 중계한다(통과 출력은 삼키므로 중계하지 않으면 보이지 않는다)
grep -qF 'case "$stack_out" in *"STACK-DECIDED: NOTE"*)' "$PLUGIN/scripts/dag/emit-context.sh" \
  && ok "T34 emit-context 가 STACK-DECIDED: NOTE 를 중계" || nope "T34" "미중계 — 알림이 삼켜진다"

finish
