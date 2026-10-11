#!/usr/bin/env bash
# foundation-manifest Phase 0 선행 게이트 (20260812)
#
# 결함: start-all 이 foundation 없이 들어가면 check-foundation-reuse 가 SKIP —
#   공통 재구현이 침묵 통과한다. 본 스위트가 check-foundation-present.sh 를 잠근다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-foundation-present.sh"

_mk_mem() { mkdir -p "$1/.specops/memory"; }

_mk_paths() {  # $1=저장소 루트 $2=manifest — 표에 백틱으로 적힌 경로를 실제 파일로 만든다(최소 내용 게이트: 실재 경로 ≥1)
  local p
  grep -E '^\|' "$2" | grep -oE '`[^` ]+/[^` ]+`' | tr -d '`' | while IFS= read -r p; do
    case "$p" in *[\(\)\{\}\<\>=\;,\*]*|@*|/*|http*) continue ;; esac
    mkdir -p "$1/$(dirname "$p")" && : > "$1/$p"
  done
}
_filled_manifest() {
  cat > "$1" <<'EOF'
<!-- OWNER_COMMAND: /start-foundation (planning-ko 산출) -->
<!-- layer: Lifecycle-Artifact -->

# Foundation Manifest — test

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

*산출: specops-ko · planning-ko · FID: test · 경로: `.specops/memory/foundation-manifest.md`*
EOF
  _mk_paths "$(dirname "$(dirname "$(dirname "$1")")")" "$1"
}

# T1: FE arch 있음 + manifest 없음 → FAIL
TD=$(mktemp -d); _mk_mem "$TD"
echo '# FE' > "$TD/.specops/memory/frontend-architecture.md"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'FOUNDATION-PRESENT: FAIL' \
  && printf '%s' "$out" | grep -q 'foundation-manifest.md 부재' \
  && ok "T1 FE arch + manifest 없음 → FAIL" \
  || nope "T1" "rc=$rc out=$out"
rm -rf "$TD"

# T2: FE arch + 채운 manifest → PASS
TD=$(mktemp -d); _mk_mem "$TD"
echo '# FE' > "$TD/.specops/memory/frontend-architecture.md"
_filled_manifest "$TD/.specops/memory/foundation-manifest.md"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'FOUNDATION-PRESENT: PASS' \
  && ok "T2 FE arch + 채운 manifest → PASS" \
  || nope "T2" "rc=$rc out=$out"
rm -rf "$TD"

# T3: FE arch + raw 템플릿 → FAIL 미채움
TD=$(mktemp -d); _mk_mem "$TD"
echo '# FE' > "$TD/.specops/memory/frontend-architecture.md"
cp "$PLUGIN/templates/foundation-manifest.md" "$TD/.specops/memory/foundation-manifest.md"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qE 'placeholder|미채움' \
  && ok "T3 raw 템플릿 → FAIL 미채움" \
  || nope "T3" "rc=$rc out=$out"
rm -rf "$TD"

# T4: FE/BE/decisions 없음 → SKIP/WARN rc=0
TD=$(mktemp -d); _mk_mem "$TD"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 0 ] \
  && printf '%s' "$out" | grep -qE 'FOUNDATION-PRESENT: (SKIP|WARN)' \
  && ok "T4 신호 없음 → SKIP/WARN rc=0" \
  || nope "T4" "rc=$rc out=$out"
rm -rf "$TD"

# T5: decisions 풀스택만 (arch 파일 없음) + manifest 없음 → FAIL
TD=$(mktemp -d); _mk_mem "$TD"
cat > "$TD/.specops/memory/decisions.md" <<'EOF'
| DECISION-ID | 주제 | 확정값 | 출처 | 갱신일 |
|---|---|---|---|---|
| D-001 | 프로젝트 종류 | 풀스택 | init Phase2 | 2026-08-10 |
| D-002 | UI 유무 | 있음 — 화면 4개 | init Phase7 | 2026-08-10 |
EOF
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'FOUNDATION-PRESENT: FAIL' \
  && ok "T5 decisions 풀스택만 → FAIL" \
  || nope "T5" "rc=$rc out=$out"
rm -rf "$TD"

# T6: start-all 배선
grep -q 'check-foundation-present.sh' "$PLUGIN/commands/start-all.md" \
  && ok "T6 start-all Phase 0 배선" \
  || nope "T6" "start-all 미배선"

# T7: start-all-auto 승계
grep -q 'check-foundation-present' "$PLUGIN/commands/start-all-auto.md" \
  && ok "T7 start-all-auto 승계" \
  || nope "T7" "start-all-auto 승계 불명"

# T8 mutation: required 를 항상 0으로 만들면 T1 fixture 가 FAIL 대신 WARN/SKIP
TD=$(mktemp -d); _mk_mem "$TD"
echo '# FE' > "$TD/.specops/memory/frontend-architecture.md"
MUT=$(mktemp)
# _is_required 본체를 즉시 return 1 로 교체하는 대신, FE arch 존재 검사를 무력화
sed \
  -e 's|\[ -f "\$MEM/frontend-architecture.md" \] \&\& return 0|# mutation: fe arch disabled|' \
  -e 's|\[ -f "\$MEM/backend-architecture.md" \] \&\& return 0|# mutation: be arch disabled|' \
  "$CHK" >"$MUT"
chmod +x "$MUT"
out=$(cd "$TD" && bash "$MUT" 2>&1); rc=$?
if [ "$rc" -eq 1 ]; then
  nope "T8 mutation" "FE 검사 무력화 후에도 FAIL — mutation 이 required 경로를 못 껐거나 decisions 오탐"
else
  printf '%s' "$out" | grep -qE 'WARN|SKIP' \
    && ok "T8 mutation: FE 검사 무력화 → WARN/SKIP (비-vacuous)" \
    || nope "T8" "rc=$rc out=$out"
fi
rm -rf "$TD" "$MUT"

# T9: 경로 토큰 정합
grep -q '\.specops/memory/foundation-manifest\.md' "$CHK" \
  && grep -q 'foundation-manifest.md' "$PLUGIN/commands/start-all.md" \
  && ok "T9 foundation-manifest 경로 정합" \
  || nope "T9" "경로 drift"

# T10: 비필수 + raw 템플릿만 있어도 FAIL (채움 항상 요구)
TD=$(mktemp -d); _mk_mem "$TD"
cp "$PLUGIN/templates/foundation-manifest.md" "$TD/.specops/memory/foundation-manifest.md"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T10 비필수·raw 템플릿 → FAIL" \
  || nope "T10" "rc=$rc out=$out"
rm -rf "$TD"

# ── T11~T13: 종류 판정이 자리표시자를 실값으로 읽지 않는다 · 기록된 종류를 쓴다 (20261009 init 점검) ──
# 결함: project-context.md 골격의 칸은 백틱으로 감싼 미확정 마커다(`<미확정 — 근거 필요>`). 판정기가 백틱을
#   벗기지 않아 그 칸을 "값 있음"으로 읽었고, `UI 유무` 칸의 선택지 표기(`<있음 | 없음>`)는 "있음"으로 읽었다 —
#   CLI 로 init 한 직후 foundation 필수 판정이 FAIL 이었다(설치본 재현).
_ctx() {  # $1=dir $2=머리 마커(없으면 빈 값) — /init-project 가 만드는 골격 그대로
  { printf '<!-- OWNER_COMMAND: /init-project -->\n<!-- layer: Project-Memory -->\n'
    [ -n "$2" ] && printf '%s\n' "$2"
    printf '\n# t 프로젝트 컨텍스트\n\n## 2. 스택·제약\n\n| 영역 | 확정값 | 출처 |\n|---|---|---|\n'
    printf '| 프론트 | `<미확정 — 근거 필요>` | |\n| 백엔드 | `<미확정 — 근거 필요>` | |\n| UI 유무 | `<있음 \\| 없음>` | |\n'
  } > "$1/.specops/memory/project-context.md"
}
# T11: 골격 그대로(마커 없음 · 칸은 전부 자리표시자) → 필수 아님
TD=$(mktemp -d); _mk_mem "$TD"; _ctx "$TD" ""
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'FAIL'; } \
  && ok "T11 project-context 골격(자리표시자뿐) → 필수 판정 아님" || nope "T11" "rc=$rc out=$out"
rm -rf "$TD"
# T12: 기록된 종류 3(CLI) + 자유 서술 칸에 값이 있어도 → 필수 아님 (기록이 추정보다 먼저)
TD=$(mktemp -d); _mk_mem "$TD"; _ctx "$TD" "<!-- specops:project-kind: 3 -->"
sed -i.bak 's#| 백엔드 | `<미확정 — 근거 필요>` |#| 백엔드 | Python 3.11 CLI |#' "$TD/.specops/memory/project-context.md"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'FAIL'; } \
  && ok "T12 기록된 종류=CLI → 자유 서술 칸으로 필수 판정하지 않음" || nope "T12" "rc=$rc out=$out"
rm -rf "$TD"
# T13: 기록된 종류 4(풀스택) + 칸은 자리표시자 → 필수(FAIL — manifest 부재)
TD=$(mktemp -d); _mk_mem "$TD"; _ctx "$TD" "<!-- specops:project-kind: 4 -->"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'FOUNDATION-PRESENT: FAIL'; } \
  && ok "T13 기록된 종류=풀스택 → 필수 (manifest 없으면 FAIL)" || nope "T13" "rc=$rc out=$out"
rm -rf "$TD"
# T14: 종류 3 이 기록돼 있어도 프론트 아키텍처 문서가 실제로 있으면 필수다 (나중에 UI 가 붙은 프로젝트)
TD=$(mktemp -d); _mk_mem "$TD"; _ctx "$TD" "<!-- specops:project-kind: 3 -->"
echo '# FE' > "$TD/.specops/memory/frontend-architecture.md"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T14 기록=CLI 여도 FE 아키텍처 문서가 있으면 필수" || nope "T14" "rc=$rc out=$out"
rm -rf "$TD"

# T15: 종류 3 이 기록돼 있어도 **명시적 신호**(UI 유무=있음)는 그대로 본다 — 기록은 init 시점의 값이라 낡을 수 있다
#   (독립 리뷰: 기록 3 이 추정을 전부 건너뛰면, CLI 로 시작해 UI 가 붙은 프로젝트가 문서를 만들기 전까지 조용히 빠진다)
TD=$(mktemp -d); _mk_mem "$TD"; _ctx "$TD" "<!-- specops:project-kind: 3 -->"
sed -i.bak 's#| UI 유무 | `<있음 \\| 없음>` |#| UI 유무 | 있음 |#' "$TD/.specops/memory/project-context.md"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T15 기록=CLI + UI 유무=있음 → 필수" || nope "T15" "rc=$rc out=$out ctx=$(grep 'UI 유무' "$TD/.specops/memory/project-context.md")"
rm -rf "$TD"

# ── T16: 최소 내용 (20261009 /start-foundation 점검 묶음 C) — /start-all 입구에서도 같은 기준 ──
# 결함: 내용이 `x` 한 줄인 manifest 로 입구 게이트가 PASS 였다(필수 KIND 포함).
TD=$(mktemp -d); _mk_mem "$TD"; echo '# FE' > "$TD/.specops/memory/frontend-architecture.md"
printf 'x\n' > "$TD/.specops/memory/foundation-manifest.md"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '실재하는 모듈 경로가 하나도 없다' \
  && ok "T16.a 한 줄짜리 manifest → FAIL" || nope "T16.a" "rc=$rc out=$out"
# 공통 모듈이 옮겨졌거나 지워진 뒤 — 남은 실재 경로가 있으면 통과하되 없는 경로를 알린다
mkdir -p "$TD/src"; : > "$TD/src/router.ts"
printf '| 모듈 | 경로 |\n|---|---|\n| 라우팅 | `src/router.ts` |\n| 인증 | `src/moved-away.ts` |\n' > "$TD/.specops/memory/foundation-manifest.md"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'WARN' && printf '%s' "$out" | grep -q 'src/moved-away.ts' \
  && printf '%s' "$out" | tail -1 | grep -q 'FOUNDATION-PRESENT: PASS' \
  && ok "T16.b 없는 경로는 경고 · 판정은 PASS" || nope "T16.b" "rc=$rc out=$out"
rm -rf "$TD"

# T16.c: 사용 예(JSX·제네릭)를 적은 다 채운 manifest 가 입구에서 막히지 않는다 (실 프로젝트 재생에서 나온 거짓 차단)
TD=$(mktemp -d); _mk_mem "$TD"; echo '# FE' > "$TD/.specops/memory/frontend-architecture.md"
mkdir -p "$TD/frontend/lib"; : > "$TD/frontend/lib/api-client.ts"
printf '| 모듈 | 역할 | 재사용 방법 |\n|---|---|---|\n| `frontend/lib/api-client.ts` | fetch 래퍼 | `apiFetch<T>(path)` · `<AppShell n={1}>` · 내부 `<input>` |\n' > "$TD/.specops/memory/foundation-manifest.md"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T16.c JSX·제네릭을 적은 manifest → PASS" || nope "T16.c" "rc=$rc out=$out"
# 템플릿 자리표시자가 남으면 여전히 FAIL
printf '\n- **DB**: <확정된 DB>\n' >> "$TD/.specops/memory/foundation-manifest.md"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'placeholder 잔존' && ok "T16.d 템플릿 자리표시자 잔존 → FAIL" || nope "T16.d" "rc=$rc out=$out"
rm -rf "$TD"

finish
