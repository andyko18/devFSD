#!/usr/bin/env bash
# test-design-screen.sh — scripts/_internal/design-screen.sh 검증
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)

PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCRIPT="$PLUGIN/scripts/_internal/design-screen.sh"
PASS=0; FAIL=0

# 격리 임시 디렉토리
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$PLUGIN/templates/screen.md"  "$TMP/screen.md"
cp "$PLUGIN/templates/screen.html" "$TMP/screen.html"

# T1: 스크립트 존재 + exec-bit
[ -f "$SCRIPT" ] && [ -x "$SCRIPT" ] \
  && ok  "T1.a design-screen.sh 존재 + exec-bit" \
  || nope "T1.a design-screen.sh 존재 + exec-bit" "$SCRIPT 없거나 exec-bit 없음"

# --- 이하 테스트는 임시 디렉토리를 프로젝트 루트로 사용 ---
cd "$TMP"

# T2: 유효 이름 → 파일 생성
bash "$SCRIPT" login >/dev/null 2>&1
[ -f "screens/login.md" ] && [ -f "screens/login.html" ] \
  && ok  "T2.a 유효 이름 → screens/login.md + screens/login.html 생성" \
  || nope "T2.a 유효 이름 → 파일 생성" "screens/login.{md,html} 없음"

# T2.b: screen.md frontmatter screen: 필드 확인
grep -q 'screen: "login"' "screens/login.md" 2>/dev/null \
  && ok  "T2.b screen.md frontmatter screen: 올바름" \
  || nope "T2.b screen.md frontmatter screen:" "screen: \"login\" 없음"

# T3: DESIGN.md Primary 색상이 HTML --color-primary에 반영
# DESIGN.md 없을 때 fallback #7C3AED
grep -q -- '--color-primary:' "screens/login.html" 2>/dev/null \
  && ok  "T3.a HTML --color-primary 변수 존재" \
  || nope "T3.a HTML --color-primary" "--color-primary 없음"

# T3.b: DESIGN.md 있을 때 색상 추출 적용
cat > "$TMP/DESIGN.md" <<'DEOF'
## 1. Color System
| Role | Value | Usage |
|---|---|---|
| Primary | `#123456` | 주요 버튼 |
DEOF
bash "$SCRIPT" profile --force >/dev/null 2>&1
grep -q '#123456' "screens/profile.html" 2>/dev/null \
  && ok  "T3.b DESIGN.md Primary 색상 추출 → HTML 반영" \
  || nope "T3.b DESIGN.md 색상 추출" "#123456 이 HTML 에 없음"

# T3.c: 전체 팔레트(9색) 주입 — Primary 외 Background/Surface/Text 등도 반영 (half-fix 회귀 차단)
# light 테마 DESIGN.md 로 부트스트랩 시 --color-bg 가 다크 기본값(#0F0F10)에서 실제값으로 바뀌어야 함.
cat > "$TMP/DESIGN.md" <<'DEOF'
## 1. Color System
| Role | Value | Usage |
|---|---|---|
| Primary | `#000000` | 주요 버튼 |
| Secondary | `#2383E2` | 보조 |
| Background | `#FFFFFF` | 페이지 배경 |
| Surface | `#F7F7F5` | 카드 |
| Text Primary | `#37352F` | 본문 |
| Text Secondary | `#787774` | 보조 텍스트 |
| Border | `#E9E9E7` | 테두리 |
| Error | `#EB5757` | 에러 |
| Success | `#0F7B6C` | 성공 |
DEOF
bash "$SCRIPT" palette --force >/dev/null 2>&1
if grep -q -- '--color-bg: #FFFFFF' "screens/palette.html" 2>/dev/null \
   && grep -q -- '--color-surface: #F7F7F5' "screens/palette.html" 2>/dev/null \
   && grep -q -- '--color-text: #37352F' "screens/palette.html" 2>/dev/null \
   && ! grep -q -- '--color-bg: #0F0F10' "screens/palette.html" 2>/dev/null; then
  ok  "T3.c 전체 팔레트 주입 (Background/Surface/Text — half-fix 차단)"
else
  nope "T3.c 전체 팔레트 주입" "--color-bg/surface/text 미반영 또는 다크 기본값 잔존"
fi

# T3.d: 미확정 색상(#______ placeholder)은 skip → 템플릿 기본값 유지 (Phase 6 단독 시점 안전)
cat > "$TMP/DESIGN.md" <<'DEOF'
## 1. Color System
| Role | Value | Usage |
|---|---|---|
| Primary | `#000000` | 주요 버튼 |
| Background | `#______` | 미확정 |
DEOF
bash "$SCRIPT" partial --force >/dev/null 2>&1
if grep -q -- '--color-primary: #000000' "screens/partial.html" 2>/dev/null \
   && grep -q -- '--color-bg: #0F0F10' "screens/partial.html" 2>/dev/null; then
  ok  "T3.d 미확정 색상 skip → 템플릿 기본값 유지"
else
  nope "T3.d 미확정 색상 skip" "placeholder 를 잘못 주입했거나 primary 미반영"
fi

# T4: screens-overview.md 갱신
mkdir -p .specops/memory
cp "$PLUGIN/templates/screens-overview.md" .specops/memory/screens-overview.md
sed -i.bak 's/<PROJECT_NAME>/TestProj/' .specops/memory/screens-overview.md
bash "$SCRIPT" contact >/dev/null 2>&1
grep -q 'contact' ".specops/memory/screens-overview.md" 2>/dev/null \
  && ok  "T4.a screens-overview.md 표에 신규 행 추가됨" \
  || nope "T4.a screens-overview.md 갱신" "contact 행 없음"

# T5: 잘못된 이름 → exit 1
bash "$SCRIPT" "../evil" 2>/dev/null; code=$?
[ "$code" -ne 0 ] \
  && ok  "T5.a 잘못된 이름 ../evil → exit 1" \
  || nope "T5.a 잘못된 이름 ../evil" "exit code=$code (0이면 안 됨)"

bash "$SCRIPT" "a b" 2>/dev/null; code=$?
[ "$code" -ne 0 ] \
  && ok  "T5.b 잘못된 이름 'a b' → exit 1" \
  || nope "T5.b 잘못된 이름 'a b'" "exit code=$code (0이면 안 됨)"

# T6: 충돌 보호
bash "$SCRIPT" login 2>/dev/null; code=$?
[ "$code" -ne 0 ] \
  && ok  "T6.a 기존 파일 + --force 없음 → exit 1" \
  || nope "T6.a 충돌 보호" "exit code=$code (0이면 안 됨)"

# T6.b: --force 시 덮어쓰기
bash "$SCRIPT" login --force >/dev/null 2>&1; code=$?
[ "$code" -eq 0 ] && [ -f "screens/login.md" ] \
  && ok  "T6.b --force → 덮어쓰기 성공" \
  || nope "T6.b --force 덮어쓰기" "exit code=$code"

# T7: screens-overview.md 없을 때 exit 0 + 파일 생성 성공
bash "$SCRIPT" about >/dev/null 2>&1; code=$?
[ "$code" -eq 0 ] && [ -f "screens/about.md" ] \
  && ok  "T7.a screens-overview.md 없을 때 exit 0 + 파일 생성 성공" \
  || nope "T7.a overview 부재 graceful" "exit=$code"

# T8: 동일 이름 중복 추가 → overview 표에 1행만
mkdir -p .specops/memory
cp "$PLUGIN/templates/screens-overview.md" .specops/memory/screens-overview.md
sed -i.bak 's/<PROJECT_NAME>/TestProj/' .specops/memory/screens-overview.md
bash "$SCRIPT" dup >/dev/null 2>&1
bash "$SCRIPT" dup --force >/dev/null 2>&1  # 동일 이름 재실행
count=$(grep -c '| dup |' .specops/memory/screens-overview.md 2>/dev/null || echo 0)
[ "$count" -eq 1 ] \
  && ok  "T8.a 동일 이름 중복 → overview 1행만 (중복 없음)" \
  || nope "T8.a 중복 방어" "dup 행 수=$count (기대 1)"


# T9: DESIGN.md 템플릿 §1 에 Border 행 존재 (9색 헬퍼 매핑 정합 — P1-1 audit 20260710)
grep -q '| Border |' "$PLUGIN/templates/DESIGN.md" \
  && ok  "T9.a 템플릿 DESIGN.md Border 행 존재 (9색 매핑 정합)" \
  || nope "T9.a 템플릿 Border 행" "lib.sh 9매핑 vs 템플릿 8행 — Border 주입 영구 no-op"

# ── T10: screens-overview 골격 예시 행 (20260806 design 계열 정밀분석) ──────
# 결함: §1 fence 가 home/login/dashboard **예시 3행**을 담은 채 배포된다.
#   init Phase 7 은 fence 를 통째로 교체하므로 무해하지만, /design-screen 은 **append**
#   경로라 예시가 남는다 → 존재하지 않는 screens/home.md·dashboard.md 를 가리키는 행이
#   화면 목록 마스터에 잔존(유령 화면). Phase 2.5-A UI 표면 검출·design-reviewer 정합
#   검사가 이 유령을 실 화면으로 읽는다. (decisions.md 예시 행과 동일 클래스)
# T10.a: 템플릿 fence 는 비어 있어야 한다 — "아직 화면 없음" 이 진실
tpl_rows=$(awk '/screens-table:start/{f=1;next} /screens-table:end/{f=0} f&&/^\|/' \
  "$PLUGIN/templates/screens-overview.md" | grep -c . || true)
[ "${tpl_rows:-0}" -eq 0 ] \
  && ok  "T10.a 템플릿 fence 예시 행 0 (유령 화면 배포 안 함)" \
  || nope "T10.a 템플릿 예시 행 잔존" "fence 내 ${tpl_rows}행 — 존재하지 않는 화면 참조"

# T10.b: 골격에서 첫 화면 추가 → 그 화면 1행만 (유령과 섞이지 않음)
mkdir -p .specops/memory
cp "$PLUGIN/templates/screens-overview.md" .specops/memory/screens-overview.md
sed -i.bak 's/<PROJECT_NAME>/TestProj/' .specops/memory/screens-overview.md
rm -f .specops/memory/screens-overview.md.bak
bash "$SCRIPT" solo >/dev/null 2>&1
rows=$(awk '/screens-table:start/{f=1;next} /screens-table:end/{f=0} f&&/^\|/' \
  .specops/memory/screens-overview.md | grep -c . || true)
{ [ "${rows:-0}" -eq 1 ] && grep -q '| solo |' .specops/memory/screens-overview.md; } \
  && ok  "T10.b 골격 + 첫 화면 → 1행만" \
  || nope "T10.b" "행수=${rows}"

# T10.c: 실제로 파일이 없는 화면을 마스터가 참조하지 않는다 (유령 참조 0)
ghost=0
while IFS= read -r n; do
  [ -z "$n" ] && continue
  [ -f "screens/${n}.md" ] || ghost=$((ghost+1))
done < <(awk '/screens-table:start/{f=1;next} /screens-table:end/{f=0} f&&/^\|/{split($0,x,"|"); gsub(/^[[:space:]]+|[[:space:]]+$/,"",x[2]); print x[2]}' \
  .specops/memory/screens-overview.md)
[ "$ghost" -eq 0 ] \
  && ok  "T10.c 마스터의 유령 화면 참조 0" \
  || nope "T10.c 유령 참조" "${ghost}건 — 파일 없는 화면이 목록에 있음"

# T11: 중복 skip 시 정직 보고 — 행이 추가되지 않았는데 '갱신됨' 은 거짓 보고
out=$(bash "$SCRIPT" solo --force 2>&1)
printf '%s' "$out" | grep -qE '이미 등록|기존 행 유지|중복' \
  && ok  "T11 중복 이름 → 정직 보고(갱신 아님 명시)" \
  || nope "T11 거짓 보고" "행 미추가인데 '갱신됨' 만 출력: $out"

# T12: 새 화면 추가가 기존 행을 건드리지 않는다 (20261009 init 점검)
#   종전엔 표를 이름 목록으로 통째 재구성해, 손으로 채운 제목·목적(보강 표기 포함)이 전부 `TODO` 가 됐다.
_ov=.specops/memory/screens-overview.md
sed -i.bak 's#^| solo | solo | TODO |#| solo | 단독 화면 | init 보강 (미확정 2) |#' "$_ov"; rm -f "$_ov.bak"
bash "$SCRIPT" billing >/dev/null 2>&1
{ grep -qF '| solo | 단독 화면 | init 보강 (미확정 2) |' "$_ov" && [ "$(grep -cE '^\| billing \|' "$_ov")" = "1" ] \
  && [ "$(grep -cE '^\| solo \|' "$_ov")" = "1" ]; } \
  && ok  "T12.a 새 화면 추가 → 기존 행(제목·목적) 무변경 · 새 행 1건" \
  || nope "T12.a 기존 행 훼손" "solo=[$(grep -E '^\| solo \|' "$_ov" | tr '\n' ' ')]"
# T12.b 새 행은 표 끝(끝 fence 바로 앞)에 들어간다
last=$(awk '/screens-table:start/{f=1;next} /screens-table:end/{f=0} f&&/^\|/' "$_ov" | tail -1)
case "$last" in '| billing |'*) ok "T12.b 새 행은 표 끝에 추가" ;; *) nope "T12.b" "마지막 행=[$last]" ;; esac
# T12.c fence 가 없는 표에는 쓰지 않고, 갱신했다고 말하지 않는다
grep -v 'screens-table:' "$_ov" > "$_ov.nf" && mv "$_ov.nf" "$_ov"
_b=$(cat "$_ov"); out=$(bash "$SCRIPT" nofence 2>&1)
{ [ "$_b" = "$(cat "$_ov")" ] && ! printf '%s' "$out" | grep -q 'screens-overview.md 갱신됨'; } \
  && ok  "T12.c fence 없는 표 → 무변경 · '갱신됨' 거짓 보고 없음" \
  || nope "T12.c" "out=$out"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
