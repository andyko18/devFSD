#!/usr/bin/env bash
# foundation manifest 산출 게이트 기계화 (20260806 /start-foundation 정밀분석)
#
# 배경: verifying-evidence-ko 는 이 게이트를 **HARD** 로 선언하고, 그 근거로
#   "생산은 planning-ko 산문 지시뿐(강제 evaluator 부재)이라 verify 가 실제 산출물을
#    확인하지 않으면 후속 /start 재사용 게이트가 침묵 무발동(no-op) 한다" 고 적어 뒀다.
#   그런데 run-verification.sh·release-ready.sh·DAG 스크립트 어디에도 구현이 없었다 —
#   **침묵 무발동을 막으려는 게이트 자체가 침묵 무발동**이었다.
# 부가: 구 산문의 채움 판정은 `grep -q '<경로>'` 단일 토큰이라, 경로만 채우고
#   <설명>·<import 예시>·<확정된 프레임워크> 가 전부 남아도 통과했다.
#   채움 판정은 placeholder SoT(scan-enrich-placeholders.sh)로 통일한다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-foundation-manifest.sh"

_mk() {  # $1=dir $2=fid $3=§유형
  mkdir -p "$1/.specops/$2" "$1/.specops/memory"
  printf '**§유형**: %s\n' "$3" > "$1/.specops/$2/spec.md"
}
_mk_paths() {  # $1=저장소 루트 $2=manifest — 표에 백틱으로 적힌 경로를 실제 파일로 만든다(최소 내용 게이트: 실재 경로 ≥1)
  local p
  grep -E '^\|' "$2" | grep -oE '`[^` ]+/[^` ]+`' | tr -d '`' | while IFS= read -r p; do
    case "$p" in *[\(\)\{\}\<\>=\;,\*]*|@*|/*|http*) continue ;; esac
    mkdir -p "$1/$(dirname "$p")" && : > "$1/$p"
  done
}
_filled_manifest() {  # $1=경로 — 실제로 채운 manifest
  cat > "$1" <<'EOF'
<!-- OWNER_COMMAND: /start-foundation (planning-ko 산출) -->
<!-- layer: Lifecycle-Artifact -->

# Foundation Manifest — mychat

## 제공 모듈

| 모듈 | 경로 | 역할 (1줄) | 재사용 방법 |
|---|---|---|---|
| 라우팅 | `src/router/index.ts` | 앱 라우트 정의 | `import { router } from '@/router'` |
| 인증 | `src/auth/session.ts` | 세션 검증 | `import { requireAuth } from '@/auth/session'` |

## 기술 스택

- **프론트엔드**: React 19 + Vite
- **백엔드**: Fastify 5
- **DB**: PostgreSQL 17

---

*산출: specops-ko · planning-ko · FID: 20260806-foundation · 경로: `.specops/memory/foundation-manifest.md`*
EOF
  _mk_paths "$(dirname "$(dirname "$(dirname "$1")")")" "$1"
}

# T1: §유형=foundation + manifest 부재 → FAIL(1)
TD=$(mktemp -d); _mk "$TD" 20260806-fnd foundation
(cd "$TD" && bash "$CHK" 20260806-fnd >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T1 foundation + manifest 부재 → FAIL" || nope "T1" "rc=$rc"
rm -rf "$TD"

# T2: §유형=foundation + 채워진 manifest → PASS(0)
TD=$(mktemp -d); _mk "$TD" 20260806-fnd foundation
_filled_manifest "$TD/.specops/memory/foundation-manifest.md"
(cd "$TD" && bash "$CHK" 20260806-fnd >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T2 foundation + 채워진 manifest → PASS" || nope "T2" "rc=$rc"
rm -rf "$TD"

# T3: 원본 템플릿 그대로(전 필드 placeholder) → FAIL
TD=$(mktemp -d); _mk "$TD" 20260806-fnd foundation
cp "$PLUGIN/templates/foundation-manifest.md" "$TD/.specops/memory/foundation-manifest.md"
(cd "$TD" && bash "$CHK" 20260806-fnd >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T3 raw 템플릿 → FAIL" || nope "T3" "rc=$rc"
rm -rf "$TD"

# T4: ★ 부분 채움 — 경로만 채우고 나머지 placeholder → FAIL
#     구 산문 판정(`grep -q '<경로>'`)은 여기서 통과했다.
TD=$(mktemp -d); _mk "$TD" 20260806-fnd foundation
cp "$PLUGIN/templates/foundation-manifest.md" "$TD/.specops/memory/foundation-manifest.md"
sed -i.bak 's|`<경로>`|`src/x.ts`|g' "$TD/.specops/memory/foundation-manifest.md"
rm -f "$TD/.specops/memory/foundation-manifest.md.bak"
(cd "$TD" && bash "$CHK" 20260806-fnd >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T4 경로만 채움(<설명>·<import 예시> 잔존) → FAIL" || nope "T4" "rc=$rc"
rm -rf "$TD"

# T5: §유형≠foundation → graceful skip(0), manifest 없어도 무관
TD=$(mktemp -d); _mk "$TD" 20260806-feat 신규
(cd "$TD" && bash "$CHK" 20260806-feat >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T5 비-foundation → skip PASS" || nope "T5" "rc=$rc"
rm -rf "$TD"

# T6: spec.md 부재 → 판정 불가 fail-open(0)
TD=$(mktemp -d); mkdir -p "$TD/.specops/20260806-x"
(cd "$TD" && bash "$CHK" 20260806-x >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T6 spec.md 부재 → fail-open" || nope "T6" "rc=$rc"
rm -rf "$TD"

# T7: HTML 주석 헤더는 미채움 근거가 아니다 (구조 계약 — 스캐너 정합)
TD=$(mktemp -d); _mk "$TD" 20260806-fnd foundation
_filled_manifest "$TD/.specops/memory/foundation-manifest.md"
grep -q '<!-- layer:' "$TD/.specops/memory/foundation-manifest.md" \
  && (cd "$TD" && bash "$CHK" 20260806-fnd >/dev/null 2>&1) \
  && ok "T7 HTML 주석 보유 manifest 도 PASS" || nope "T7" "주석이 FAIL 유발"
rm -rf "$TD"

# T8: run-verification 배선 — 게이트가 VERIFY 관문에 실제로 연결됐는가
grep -q 'check-foundation-manifest.sh' "$PLUGIN/scripts/_internal/run-verification.sh" \
  && ok "T8 run-verification 배선" || nope "T8" "run-verification 미배선 — 산문 게이트 잔존"

# T9: 스킬 본문이 스크립트를 SoT 로 지목 (산문 ↔ 구현 이원화 방지)
grep -q 'check-foundation-manifest.sh' "$PLUGIN/skills/verifying-evidence-ko/SKILL.md" \
  && ok "T9 verifying-evidence-ko 가 스크립트 지목" || nope "T9" "스킬 본문 미갱신"

# ── CLI/라이브러리 foundation — 템플릿 경직성 (20260806 시나리오 검증) ────────
# 템플릿 모듈 5행이 라우팅·인증·레이아웃·공통컴포넌트·DB 로 고정이라 CLI foundation 엔
# 전부 무관하다. 채움 판정을 엄격화한 뒤 실측하니 **모델의 자연스러운 선택**(무관 행을
# 템플릿 그대로 방치)이 FAIL 이 된다 — 체커가 틀린 게 아니라 템플릿이 실패 형태로 유도한다.
# 해법은 판정 완화가 아니라 **"해당 없는 행·항목은 삭제"** 를 템플릿에 명시하는 것.
# 느슨한 grep(`삭제|예시`)은 표 안의 `<import 예시>`·기술스택 주석에 걸려 공허하게 통과한다
# (mutation 으로 실증). 계약의 **세 요소**를 모두 요구한다:
#   ① 행 자체 삭제 허용 ② 판정기 이름(SoT) ③ 미채움 → VERIFY: FAIL 귀결
TPL="$PLUGIN/templates/foundation-manifest.md"
_t10=0
grep -qE '행 자체를 삭제|행·항목은 삭제|해당 없는 것은 행' "$TPL" || _t10=1
grep -q 'check-foundation-manifest' "$TPL" || _t10=1
grep -q 'VERIFY: FAIL' "$TPL" || _t10=1
if [ "$_t10" -eq 0 ]; then
  ok "T10 템플릿에 행 삭제 허용 + 판정기 + FAIL 귀결 명시"
else
  nope "T10" "템플릿 지침 불완전 — CLI foundation 이 placeholder 방치로 유도됨"
fi

# T11: CLI 형태(라우팅·인증·DB 무관, 모듈 3행 교체) manifest → PASS
TD=$(mktemp -d); _mk "$TD" 20260806-cli foundation
cat > "$TD/.specops/memory/foundation-manifest.md" <<'EOF'
<!-- layer: Lifecycle-Artifact -->
# Foundation Manifest — mycli
## 제공 모듈
| 모듈 | 경로 | 역할 (1줄) | 재사용 방법 |
|---|---|---|---|
| 인자 파싱 | `src/cli/args.sh` | 공통 옵션 파싱 | `source src/cli/args.sh` |
| 로깅 | `src/cli/log.sh` | 레벨별 로깅 | `source src/cli/log.sh` |
## 기술 스택
- **런타임**: bash 5.2
EOF
_mk_paths "$TD" "$TD/.specops/memory/foundation-manifest.md"
(cd "$TD" && bash "$CHK" 20260806-cli >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T11 CLI 형태 manifest(행 교체·스택 축소) → PASS" || nope "T11" "rc=$rc"
rm -rf "$TD"

# T12: 무관 행을 '해당 없음' 으로 채운 형태도 PASS (삭제·명시 둘 다 허용)
TD=$(mktemp -d); _mk "$TD" 20260806-cli foundation
cat > "$TD/.specops/memory/foundation-manifest.md" <<'EOF'
<!-- layer: Lifecycle-Artifact -->
# Foundation Manifest — mycli
## 제공 모듈
| 모듈 | 경로 | 역할 (1줄) | 재사용 방법 |
|---|---|---|---|
| 인자 파싱 | `src/cli/args.sh` | 공통 옵션 파싱 | `source src/cli/args.sh` |
| 라우팅 | 해당 없음 | 해당 없음 | 해당 없음 |
## 기술 스택
- **런타임**: bash 5.2
EOF
_mk_paths "$TD" "$TD/.specops/memory/foundation-manifest.md"
(cd "$TD" && bash "$CHK" 20260806-cli >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T12 '해당 없음' 명시 형태 → PASS" || nope "T12" "rc=$rc"
rm -rf "$TD"

# ── T13: 템플릿의 **안내문**이 미채움으로 잡히면 안 된다 (20261009 /start-foundation 점검) ──
# 결함: 표·스택·제목·FID 를 전부 채워도 템플릿 자신의 안내문(`<경로>` 를 인용한 경고)과
#   `재사용 게이트 규약` 절의 꺾쇠 예시가 스캐너에 걸려 VERIFY: FAIL 이 났다 — 채울 값이 아닌 줄이다.
#   판정기(스캐너)는 6곳이 함께 쓰므로 건드리지 않고, 템플릿의 안내문에서 꺾쇠 표기를 뺀다.
# 채워야 하는 자리: 머리 FID 주석 · 제목의 프로젝트명 · 모듈 표 · 기술 스택 · 꼬리말 FID.
_fill_real() {  # $1=출력 경로 — 템플릿의 **실제 자리표시자만** 채운다(안내문은 손대지 않는다)
  sed -e 's/<YYYYMMDD-kebab-slug>/20260806-foundation/' \
      -e 's/<프로젝트명>/mychat/' \
      -e 's/^| \([^|]*\) | `<경로>` | <설명> | `<import 예시>` |$/| \1 | `src\/x.ts` | 역할 설명 | `import x` |/' \
      -e 's/<확정된 프레임워크>/React 19/; s/<확정된 DB>/PostgreSQL 17/' \
      -e 's/FID: <FID>/FID: 20260806-foundation/' \
      "$TPL" > "$1"
  _mk_paths "$(dirname "$(dirname "$(dirname "$1")")")" "$1"
}
TD=$(mktemp -d); _mk "$TD" 20260806-foundation foundation
_fill_real "$TD/.specops/memory/foundation-manifest.md"
out=$(cd "$TD" && bash "$CHK" 20260806-foundation 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T13.a 실제 자리표시자만 채운 템플릿 → PASS (안내문은 미채움이 아니다)" \
  || nope "T13.a" "rc=$rc out=$(printf '%s' "$out" | head -8)"
rm -rf "$TD"

# T13.b: 그렇다고 실제 자리표시자가 풀린 건 아니다 — 하나씩 남기면 여전히 FAIL
for keep in '<프로젝트명>' '<확정된 DB>' 'FID: <FID>'; do
  TD=$(mktemp -d); _mk "$TD" 20260806-foundation foundation
  _fill_real "$TD/.specops/memory/foundation-manifest.md"
  # 채운 값 하나를 템플릿 원문으로 되돌린다
  case "$keep" in
    '<프로젝트명>') sed -i.bak 's/^# Foundation Manifest — mychat/# Foundation Manifest — <프로젝트명>/' "$TD/.specops/memory/foundation-manifest.md" ;;
    '<확정된 DB>')  sed -i.bak 's/PostgreSQL 17/<확정된 DB>/' "$TD/.specops/memory/foundation-manifest.md" ;;
    'FID: <FID>')   sed -i.bak 's/· FID: 20260806-foundation ·/· FID: <FID> ·/' "$TD/.specops/memory/foundation-manifest.md" ;;
  esac
  grep -qF -- "$keep" "$TD/.specops/memory/foundation-manifest.md" || nope "T13.b-setup" "되돌리기 실패: $keep"
  (cd "$TD" && bash "$CHK" 20260806-foundation >/dev/null 2>&1); rc=$?
  [ "$rc" -eq 1 ] && ok "T13.b 실제 자리표시자 잔존($keep) → FAIL" || nope "T13.b" "$keep rc=$rc"
  rm -rf "$TD"
done

# T13.c: 안내문이 사라진 게 아니라 표기만 바뀐 것이다 — 재사용 규약 두 필드명은 그대로 보인다
grep -qF '**재사용 foundation**:' "$TPL" && grep -qF '**미재사용 근거**:' "$TPL" \
  && ok "T13.c 템플릿이 재사용 규약 두 필드를 여전히 안내" || nope "T13.c" "필드 안내 소실"

# ── T14: 최소 내용 (20261009 /start-foundation 점검 묶음 C) ─────────────────────
# 결함: 게이트가 자리표시자 유무만 봤다 — 내용이 `x` 한 줄이어도, 모듈 행이 0개여도, 저장소에 없는 경로만
#   적어도 PASS 였다. 표에 적힌 경로 가운데 **실재하는 것이 하나는** 있어야 한다. 없는 경로는 경고(차단 아님).
_mf_case() {  # $1=id $2=설명 $3=기대 rc $4=출력에 있어야 할 문자열(빈 문자열=검사 안 함) $5=있으면 안 되는 문자열 · stdin=manifest
  local td out rc
  td=$(mktemp -d); _mk "$td" 20260806-fnd foundation
  cat > "$td/.specops/memory/foundation-manifest.md"
  [ -n "${MF_SETUP:-}" ] && (cd "$td" && eval "$MF_SETUP") >/dev/null 2>&1
  out=$(cd "$td" && bash "$CHK" 20260806-fnd 2>&1); rc=$?
  if [ "$rc" -eq "$3" ] && { [ -z "$4" ] || printf '%s' "$out" | grep -qF -- "$4"; } \
     && { [ -z "${5:-}" ] || ! printf '%s' "$out" | grep -qF -- "$5"; }; then ok "$1 $2"
  else nope "$1" "rc=$rc(기대 $3) out=$out"; fi
  rm -rf "$td"
}
MF_SETUP=''
_mf_case T14.a '내용이 한 줄뿐 → FAIL' 1 '실재하는 모듈 경로가 하나도 없다' '' <<'EOF'
x
EOF
_mf_case T14.b '모듈 행이 0개인 표 → FAIL' 1 '실재하는 모듈 경로가 하나도 없다' '' <<'EOF'
# Foundation Manifest — demo

| 모듈 | 경로 | 역할 (1줄) | 재사용 방법 |
|---|---|---|---|
EOF
_mf_case T14.c '저장소에 없는 경로만 → FAIL + 없는 경로 지목' 1 '없음: src/router.ts' '' <<'EOF'
| 모듈 | 경로 |
|---|---|
| 라우팅 | `src/router.ts` |
EOF
MF_SETUP='mkdir -p src && : > src/router.ts'
_mf_case T14.d '실재 경로 1 + 없는 경로 1 → PASS + 경고' 0 'WARN — 표의 경로 가운데 저장소에 없는 것' '' <<'EOF'
| 모듈 | 경로 |
|---|---|
| 라우팅 | `src/router.ts` |
| 인증 | `src/gone.ts` |
EOF
_mf_case T14.d2 '경고가 없는 경로를 지목하고 실재 경로는 지목하지 않는다' 0 '  - src/gone.ts' '  - src/router.ts' <<'EOF'
| 모듈 | 경로 |
|---|---|
| 라우팅 | `src/router.ts` |
| 인증 | `src/gone.ts` |
EOF
_mf_case T14.e '전부 실재 → 경고 없음' 0 'FOUNDATION-MANIFEST: PASS' 'WARN' <<'EOF'
| 모듈 | 경로 |
|---|---|
| 라우팅 | `src/router.ts` |
EOF
# 경로가 아닌 표기(심볼·호스트·라우트·사용 예)는 "없는 경로"로 세지 않는다 — 실 manifest 재생에서 나온 오탐 꼴
_mf_case T14.f '심볼·호스트·라우트·import 예는 누락으로 세지 않는다' 0 'FOUNDATION-MANIFEST: PASS' 'WARN' <<'EOF'
| 모듈 | 경로 | 재사용 방법 |
|---|---|---|
| 라우팅 | `src/router.ts` | `import { router } from '@/router'` · `yf.download` · `openapi.naver.com` · `/stocks/[ticker]` · `/api/health` · `.field` |
EOF
# 표가 하위 패키지 기준 상대경로로 적힌 경우 — 추적 파일이 그 경로로 끝나면 실재다
MF_SETUP='git init -q . && git config user.email t@t && git config user.name t && mkdir -p apps/web/components && : > apps/web/components/Button.tsx && git add apps && git commit -qm init'
_mf_case T14.g '하위 패키지 기준 상대경로(추적 파일의 끝부분) → 실재' 0 'FOUNDATION-MANIFEST: PASS' 'WARN' <<'EOF'
| 모듈 | 경로 |
|---|---|
| 버튼 | `components/Button.tsx` |
EOF
# 루트의 단일 파일(슬래시 없는 이름.확장자)도 실재하면 근거다
MF_SETUP=': > package.json'
_mf_case T14.h '슬래시 없는 파일 이름만 적은 표 → 실재하면 PASS' 0 'FOUNDATION-MANIFEST: PASS' '' <<'EOF'
| 모듈 | 경로 |
|---|---|
| 워크스페이스 | `package.json` |
EOF
MF_SETUP=''

# T14.i: 덮어쓰기 경고 — base 브랜치의 manifest 에 있던 모듈이 사라졌으면 알린다(차단 아님)
TD=$(mktemp -d); _mk "$TD" 20260806-fnd foundation
( cd "$TD" && git init -q -b main . && git config user.email t@t && git config user.name t \
  && mkdir -p src && : > src/router.ts && : > src/auth.ts \
  && printf '| 모듈 | 경로 |\n|---|---|\n| 라우팅 | `src/router.ts` |\n| 인증 | `src/auth.ts` |\n' > .specops/memory/foundation-manifest.md \
  && git add -A && git commit -qm base && git checkout -qb feat/20260806-fnd ) >/dev/null 2>&1
printf '| 모듈 | 경로 |\n|---|---|\n| 라우팅 | `src/router.ts` |\n| 결제 | `src/router.ts` |\n' > "$TD/.specops/memory/foundation-manifest.md"
out=$(cd "$TD" && bash "$CHK" 20260806-fnd 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '이전 manifest 에 있던 모듈이 사라졌다' && printf '%s' "$out" | grep -qx '  - 인증' \
  && ! printf '%s' "$out" | grep -qx '  - 라우팅' \
  && ok "T14.i 사라진 모듈(인증)을 지목 · 남은 모듈은 지목하지 않음 · 통과" || nope "T14.i" "rc=$rc out=$out"
# 행을 더하기만 했으면 경고 없음
printf '| 모듈 | 경로 |\n|---|---|\n| 라우팅 | `src/router.ts` |\n| 인증 | `src/auth.ts` |\n| 결제 | `src/router.ts` |\n' > "$TD/.specops/memory/foundation-manifest.md"
out=$(cd "$TD" && bash "$CHK" 20260806-fnd 2>&1)
! printf '%s' "$out" | grep -q '사라졌다' && ok "T14.j 행 추가만 → 경고 없음" || nope "T14.j" "out=$out"
rm -rf "$TD"

# T14.k: 공통부 FR 의 `관련 spec` 칸이 비어 있으면 적는 명령을 알린다(차단 아님) · 다 적혀 있으면 침묵
TD=$(mktemp -d); _mk "$TD" 20260806-fnd foundation; mkdir -p "$TD/src"; : > "$TD/src/router.ts"
printf '| 모듈 | 경로 |\n|---|---|\n| 라우팅 | `src/router.ts` |\n' > "$TD/.specops/memory/foundation-manifest.md"
printf '| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |\n|---|---|---|---|---|\n| FR-4 | [공통] 스캐폴딩 | M1 | must | (TBD) |\n| FR-5 | [공통] 인증 | M1 | must | 20260806-fnd |\n| FR-6 | 주문 | M1 | must | (TBD) |\n' > "$TD/.specops/memory/requirements.md"
out=$(cd "$TD" && bash "$CHK" 20260806-fnd 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'NOTE — 공통부 FR' && printf '%s' "$out" | grep -q 'FR-4' \
  && ! printf '%s' "$out" | grep -qE 'FR-5|FR-6' && printf '%s' "$out" | grep -qE 'bash "/[^"]*/scripts/_internal/fr-set-fid\.sh" 20260806-fnd' \
  && ok "T14.k 빈 공통 FR(FR-4)만 안내 + 명령 제시(절대경로 — 하류 저장소에는 scripts/ 가 없다)" || nope "T14.k" "rc=$rc out=$out"
sed -i.bak 's/| FR-4 | \[공통\] 스캐폴딩 | M1 | must | (TBD) |/| FR-4 | [공통] 스캐폴딩 | M1 | must | 20260806-fnd |/' "$TD/.specops/memory/requirements.md"
out=$(cd "$TD" && bash "$CHK" 20260806-fnd 2>&1)
! printf '%s' "$out" | grep -q 'NOTE' && ok "T14.l 공통 FR 이 다 적혀 있으면 안내 없음" || nope "T14.l" "out=$out"
rm -rf "$TD"

# ── T15: 채움 판정은 "이 템플릿의 자리표시자가 남았는가" 다 (20261009 실 프로젝트 재생) ──────
# 결함: 범용 미채움 스캐너가 꺾쇠 모양을 전부 세어, 사용 예를 적은 **다 채운** manifest 를 막았다 —
#   실 프로젝트의 226줄 manifest 가 `<AppShell …>`·`apiFetch<T>(path)`·`<input>` 때문에 verify 와 /start-all 입구
#   양쪽에서 "템플릿 placeholder 잔존" 이었다. manifest 는 사용 예를 적으라는 문서다.
_jsx_manifest() {  # $1=manifest 경로
  cat > "$1" <<'EOF'
# 공통부 매니페스트

| 모듈 | 역할 | 재사용 방법 |
|---|---|---|
| `frontend/lib/api-client.ts` | fetch 래퍼 · `ApiError` | `apiFetch<T>(path)` — 상태코드·본문 보존 |
| `frontend/components/AppShell.tsx` | 셸·사이드바 | `<AppShell universeCount={n}>{children}</AppShell>` |
| `Input` | `.field` 는 40px 이고 내부 `<input>` 이 `height: 100%` 다 | `Map<string, Row[]>` |
EOF
  _mk_paths "$(dirname "$(dirname "$(dirname "$1")")")" "$1"
}
TD=$(mktemp -d); _mk "$TD" 20260806-fnd foundation; _jsx_manifest "$TD/.specops/memory/foundation-manifest.md"
out=$(cd "$TD" && bash "$CHK" 20260806-fnd 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T15.a JSX·제네릭·HTML 태그를 적은 다 채운 manifest → PASS" || nope "T15.a" "rc=$rc out=$out"
# 그렇다고 느슨해진 것은 아니다 — 템플릿이 가진 자리표시자는 **어느 것이든** 하나만 남아도 FAIL
okt=ok; ntok=0
while IFS= read -r tok; do
  [ -n "$tok" ] || continue
  ntok=$((ntok + 1))
  _jsx_manifest "$TD/.specops/memory/foundation-manifest.md"
  printf '\n- 남은 자리: %s\n' "$tok" >> "$TD/.specops/memory/foundation-manifest.md"
  (cd "$TD" && bash "$CHK" 20260806-fnd >/dev/null 2>&1); rc=$?
  [ "$rc" -eq 1 ] || okt="no($tok → rc=$rc)"
done <<EOF
$(LC_ALL=C grep -oE '<[^<>]{1,60}>' "$TPL" | grep -v '^<!--' | LC_ALL=C sort -u)
EOF
[ "$okt" = ok ] && [ "$ntok" -ge 6 ] && ok "T15.b 템플릿 자리표시자 ${ntok}종 각각 잔존 → FAIL" || nope "T15.b" "$okt ntok=$ntok"
# 템플릿에 없어도 미채움을 뜻하는 표기는 잡는다
okm=ok
for tok in '<TODO>' '<TBD>' '<미정>' '<미확정 — 근거 필요>'; do
  _jsx_manifest "$TD/.specops/memory/foundation-manifest.md"
  printf '\n- DB: %s\n' "$tok" >> "$TD/.specops/memory/foundation-manifest.md"
  (cd "$TD" && bash "$CHK" 20260806-fnd >/dev/null 2>&1); rc=$?
  [ "$rc" -eq 1 ] || okm="no($tok → rc=$rc)"
done
[ "$okm" = ok ] && ok "T15.c 미채움 표기(<TODO>·<TBD>·<미정>·<미확정 …>) → FAIL" || nope "T15.c" "$okm"
rm -rf "$TD"

# ── T14.m~ · T15.d~: 독립 리뷰 반영 ─────────────────────────────────────────────
# 형식이 달라서 막히던 정상 manifest — 괄호·대괄호가 든 경로(Next.js) · 백틱 없는 표 · 공백이 든 경로 · 표 밖 목록
MF_SETUP='mkdir -p "src/app/(main)" "src/app/[id]" && : > "src/app/(main)/layout.tsx" && : > "src/app/[id]/page.tsx"'
_mf_case T14.m '괄호·대괄호가 든 경로만 있는 표 → PASS' 0 'FOUNDATION-MANIFEST: PASS' 'WARN' <<'EOF'
| 모듈 | 경로 |
|---|---|
| 레이아웃 | `src/app/(main)/layout.tsx` |
| 상세 | `src/app/[id]/page.tsx` |
EOF
MF_SETUP='mkdir -p src "my docs" && : > src/router.ts && : > "my docs/guide.md"'
_mf_case T14.n '백틱 없이 적은 표 → PASS' 0 'FOUNDATION-MANIFEST: PASS' '' <<'EOF'
| 모듈 | 경로 |
|---|---|
| 라우팅 | src/router.ts |
EOF
_mf_case T14.o '공백이 든 경로 → PASS' 0 'FOUNDATION-MANIFEST: PASS' '' <<'EOF'
| 모듈 | 경로 |
|---|---|
| 안내서 | `my docs/guide.md` |
EOF
_mf_case T14.p '표 없이 목록에 백틱으로 적은 manifest → PASS' 0 'FOUNDATION-MANIFEST: PASS' '' <<'EOF'
# 공통부

- 라우팅: `src/router.ts` — 경로 표
EOF
_mf_case T14.q '넓게 찾아도 실재하는 것이 없으면 여전히 FAIL' 1 '실재하는 모듈 경로가 하나도 없다' '' <<'EOF'
| 모듈 | 경로 |
|---|---|
| 라우팅 | src/nowhere.ts |

- 인증: `lib/none.ts`
EOF
MF_SETUP=''
# SPECOPS_ROOT 에 끝 슬래시가 붙어 와도 같은 루트다
TD=$(mktemp -d); _mk "$TD" 20260806-fnd foundation; mkdir -p "$TD/src"; : > "$TD/src/router.ts"
printf '| 모듈 | 경로 |\n|---|---|\n| 라우팅 | `src/router.ts` |\n' > "$TD/.specops/memory/foundation-manifest.md"
(cd / && SPECOPS_ROOT="$TD/.specops/" bash "$CHK" 20260806-fnd >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T14.r SPECOPS_ROOT 끝 슬래시 → 같은 루트(PASS)" || nope "T14.r" "rc=$rc"
rm -rf "$TD"

# T15.d: 고쳐 쓴 미채움도 잡는다 — 템플릿 토큰 대조로 바꾸며 느슨해지지 않게
TD=$(mktemp -d); _mk "$TD" 20260806-fnd foundation
okv=ok
for tok in '< 경로 >' '<경로 입력>' '<설명 작성>' '<TODO: 채움>' '<tbd>' '<확정된 DB 이름>' '<미정 — 추후>'; do
  _jsx_manifest "$TD/.specops/memory/foundation-manifest.md"
  printf '\n- 값: %s\n' "$tok" >> "$TD/.specops/memory/foundation-manifest.md"
  (cd "$TD" && bash "$CHK" 20260806-fnd >/dev/null 2>&1); rc=$?
  [ "$rc" -eq 1 ] || okv="no($tok → rc=$rc)"
done
[ "$okv" = ok ] && ok "T15.d 고쳐 쓴 미채움 7종 → FAIL" || nope "T15.d" "$okv"
# 반대로 코드 표기는 미채움이 아니다
okc=ok
for tok in '<Todo />' '<TodoList items={x}>' '<FIDBadge />' '`Promise<void>`' '<TBDatePicker>'; do
  _jsx_manifest "$TD/.specops/memory/foundation-manifest.md"
  printf '\n- 사용: %s\n' "$tok" >> "$TD/.specops/memory/foundation-manifest.md"
  (cd "$TD" && bash "$CHK" 20260806-fnd >/dev/null 2>&1); rc=$?
  [ "$rc" -eq 0 ] || okc="no($tok → rc=$rc)"
done
[ "$okc" = ok ] && ok "T15.e 컴포넌트·제네릭 표기 5종은 미채움이 아니다 → PASS" || nope "T15.e" "$okc"
rm -rf "$TD"

# T15.f: 한글이 든 꺾쇠 표기 전부를 미채움으로 보지 않는다 — 채운 manifest 에 실제로 나오는 표기들(독립 리뷰 실측)
#   manifest 게이트는 VERIFY FAIL 이라 오탐에 풀 길이 없다. 미채움 표기는 `<미정…`·`<미확정…`·템플릿 토큰으로만 잡는다.
TD=$(mktemp -d); _mk "$TD" 20260806-fnd foundation
okh=ok
while IFS= read -r line; do
  [ -n "$line" ] || continue
  _jsx_manifest "$TD/.specops/memory/foundation-manifest.md"
  printf '\n%s\n' "$line" >> "$TD/.specops/memory/foundation-manifest.md"
  (cd "$TD" && bash "$CHK" 20260806-fnd >/dev/null 2>&1); rc=$?
  [ "$rc" -eq 0 ] || okh="no($line → rc=$rc)"
done <<'EOF'
- 각 기능은 `src/features/<기능명>/` 아래에 둔다
- 성능: 응답 < 200ms 이고 처리량 > 100 건
- 조회: `useQuery<사용자[]>()`
- 관계: Base <<상속>> Derived
- 문서: <https://example.com/한글>
- 담당: 홍길동 <홍길동@example.com>
- 흐름: B <-- 한글 --> C
- 버튼: <Button label="저장">
EOF
[ "$okh" = ok ] && ok "T15.f 채운 문서의 한글 꺾쇠 표기 8종 → PASS" || nope "T15.f" "$okh"
rm -rf "$TD"

# ── T16: 모듈명 추출과 경로 토큰 규칙 — 규칙 하나를 꺼도 통과하던 것들 (변이 실측 20261009) ──
LIBC="$PLUGIN/scripts/_internal/foundation-manifest-content.sh"
# shellcheck source=/dev/null
. "$LIBC"
# T16.a 모듈명 — 머리행(구분행 앞 행)·구분행(`---`·`:---:`)·한 글자 칸은 이름이 아니다
names=$(printf '%s\n' '| 모듈 | 경로 |' '|:---:|---|' '| 라우팅 | `src/router.ts` |' '| A | `src/a.ts` |' '| 인증 | `src/auth.ts` |' | fmc_module_names -)
[ "$(printf '%s\n' "$names" | LC_ALL=C sort | tr '\n' ',')" = "$(printf '%s\n' 라우팅 인증 | LC_ALL=C sort | tr '\n' ',')" ] \
  && ok "T16.a 모듈명 — 머리행·구분행·한 글자 칸 제외" || nope "T16.a" "names=$(printf '%s' "$names" | tr '\n' ',')"
# T16.b URL 은 경로가 아니다 — 없는 경로로 세지 않는다
TD=$(mktemp -d); _mk "$TD" 20260806-fnd foundation; mkdir -p "$TD/src"; : > "$TD/src/router.ts"
printf '| 모듈 | 경로 |\n|---|---|\n| 라우팅 | `src/router.ts` |\n| 문서 | `https://example.com/docs/api` |\n' > "$TD/.specops/memory/foundation-manifest.md"
fmc_scan "$TD/.specops/memory/foundation-manifest.md" "$TD"
[ "$FMC_TOTAL" -eq 1 ] && [ -z "$FMC_MISSING" ] \
  && ok "T16.b URL 은 경로 토큰이 아니다 (TOTAL=1 · 누락 없음)" || nope "T16.b" "TOTAL=$FMC_TOTAL MISSING=$FMC_MISSING"
# T16.c 괄호·대괄호가 든 경로 표기는 없다고 누락으로 세지 않는다 (호출·라우트 표기와 모양이 같다)
printf '| 모듈 | 경로 |\n|---|---|\n| 라우팅 | `src/router.ts` |\n| 화면 | `src/app/(main)/layout.tsx` |\n| 상세 | `src/app/[id]/page.tsx` |\n' > "$TD/.specops/memory/foundation-manifest.md"
fmc_scan "$TD/.specops/memory/foundation-manifest.md" "$TD"
[ "$FMC_TOTAL" -eq 1 ] && [ -z "$FMC_MISSING" ] \
  && ok "T16.c 괄호·대괄호 경로는 누락으로 세지 않는다" || nope "T16.c" "TOTAL=$FMC_TOTAL MISSING=$FMC_MISSING"
rm -rf "$TD"
# T16.d 저장소 밖을 가리키는 표기(`..`)는 실재 근거가 아니다 — 밖에 그 파일이 있어도 "실재 경로 없음" 이다
TD=$(mktemp -d); mkdir -p "$TD/repo"; _mk "$TD/repo" 20260806-fnd foundation; : > "$TD/outside.md"
printf '# 공통부\n\n- `../outside.md` 를 참고한다\n' > "$TD/repo/.specops/memory/foundation-manifest.md"
fmc_scan "$TD/repo/.specops/memory/foundation-manifest.md" "$TD/repo"
[ "$FMC_REAL" -eq 0 ] \
  && ok "T16.d 저장소 밖(..) 표기는 실재로 세지 않는다" || nope "T16.d" "REAL=$FMC_REAL"
# 대조 — 같은 문서가 저장소 안의 파일을 가리키면 센다
: > "$TD/repo/inside.md"
printf '# 공통부\n\n- `inside.md` 를 참고한다\n' > "$TD/repo/.specops/memory/foundation-manifest.md"
fmc_scan "$TD/repo/.specops/memory/foundation-manifest.md" "$TD/repo"
[ "$FMC_REAL" -ge 1 ] \
  && ok "T16.e 대조 — 저장소 안의 파일은 센다" || nope "T16.e" "REAL=$FMC_REAL"
rm -rf "$TD"

finish
