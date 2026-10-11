#!/usr/bin/env bash
# test-screen-template.sh — screen.md 템플릿 8+4 섹션 + 소비처 문구 동기화 검증
# AC-7(필수 8) · AC-8(조건부 4 규약) · AC-9(데이터 소스 Step 5.6 연계) · AC-10(소비처 양방향)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)

PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
T="$PLUGIN/templates/screen.md"
PASS=0; FAIL=0

# T1: 필수 코어 8섹션 헤더 (AC-7)
for s in "목적" "Layout" "Components" "States" "Interactions" "필드 정의표" "데이터 소스" "에러 메시지"; do
  grep -qE "^## ${s}\$" "$T" \
    && ok  "T1 필수 섹션 '## ${s}' 존재" \
    || nope "T1 필수 섹션 '## ${s}'" "헤더 없음"
done

# T2: 조건부 4섹션 + 적용 조건 + 미해당 시 제거 규약 (AC-8)
for s in "RBAC 권한별 표시" "반응형 브레이크포인트" "접근성" "진입/이탈 경로"; do
  grep -qF "$s" "$T" \
    && ok  "T2 조건부 섹션 '${s}' 기재" \
    || nope "T2 조건부 '${s}'" "미기재"
done

grep -qF '적용 조건' "$T" \
  && ok  "T2.e 조건부 섹션 적용 조건 명시" \
  || nope "T2.e 적용 조건" "'적용 조건' 앵커 없음"

grep -qF '섹션 자체를 넣지 않는다' "$T" \
  && ok  "T2.f 미해당 시 섹션 자체 제거 규약 (— 채우기 금지)" \
  || nope "T2.f 제거 규약" "앵커 없음"

# T3: 데이터 소스 Step 5.6 연계 (AC-9)
grep -qF '.specops/memory/api-spec.md' "$T" \
  && ok  "T3.a 데이터 소스에 api-spec.md 참조" \
  || nope "T3.a api-spec 참조" "앵커 없음"

grep -qF '.specops/memory/data-model.md' "$T" \
  && ok  "T3.b 데이터 소스에 data-model.md 참조" \
  || nope "T3.b data-model 참조" "앵커 없음"

# T4: 소비처 문구 동기화 — 양방향 단언 (AC-10)
for f in design-screen.md design-screens.md; do
  p="$PLUGIN/commands/$f"
  [ "$(grep -cF '목적, Layout, Components, States, Interactions 섹션 완성' "$p")" -eq 0 ] \
    && ok  "T4.$f 구 '5섹션 완성' 문구 부재" \
    || nope "T4.$f 구 문구 부재" "5섹션 표현 잔존 — drift"

  grep -qF '필수 8섹션' "$p" \
    && ok  "T4.$f 신 '필수 8섹션' 문구 존재" \
    || nope "T4.$f 신 문구" "'필수 8섹션' 앵커 없음"

  grep -qF '마커 줄을 삭제' "$p" \
    && ok  "T4.$f 마커 제거 지시 존재 (AC-12 ③)" \
    || nope "T4.$f 마커 제거" "앵커 없음"
done

# T5: 마커 보존 — 태스크 1 의 마커가 확장 후에도 남아 있어야 함
grep -qF 'specops:screen-placeholder' "$T" \
  && ok  "T5.a 템플릿 확장 후에도 껍데기 마커 보존" \
  || nope "T5.a 마커 보존" "확장 중 마커 소실 — 판정 무력화"


# T6: screen.html 씨앗 토큰 — 타입/간격 스케일 + §2·§3 대응 주석 (AC-5)
#   ★ grep -o + sort -u 로 **토큰 종류**를 센다: 한 줄에 여러 토큰이 있어 grep -c(행수)는 과소계수.
#   ★ `--` 필수: 패턴이 `-` 로 시작해 없으면 grep 이 옵션으로 오파싱 → 영구 FAIL.
H="$PLUGIN/templates/screen.html"
_ts=$(grep -o -- '--text-[a-z0-9]*:' "$H" 2>/dev/null | sort -u | wc -l | tr -d ' ')
{ [ "${_ts:-0}" -ge 5 ] && grep -qF 'DESIGN.md §2 Typography' "$H"; } \
  && ok  "T6.a screen.html 타입 토큰 ${_ts}종(≥5) + §2 대응 주석" \
  || nope "T6.a 타입 토큰" "--text-* ${_ts}종 (기대 ≥5) 또는 '§2 Typography' 대응 주석 부재"

_sp=$(grep -o -- '--space-[a-z0-9]*:' "$H" 2>/dev/null | sort -u | wc -l | tr -d ' ')
{ [ "${_sp:-0}" -ge 4 ] && grep -qF 'DESIGN.md §3 Spacing' "$H"; } \
  && ok  "T6.b screen.html 간격 토큰 ${_sp}종(≥4) + §3 대응 주석" \
  || nope "T6.b 간격 토큰" "--space-* ${_sp}종 (기대 ≥4) 또는 '§3 Spacing' 대응 주석 부재"

# T7: 화면 원형 선언 + States Empty (FID 20260929-enterprise-genre-rules AC-5)
_pre=$(awk '/^## /{exit} {print}' "$T")
_arch=$(printf '%s\n' "$_pre" | grep -E '^\*\*원형\*\*:' | head -1)
_am=""
for a in 목록 상세 폼 '다단 폼' 대시보드 기타; do
  printf '%s' "$_arch" | grep -qF "$a" || _am="$_am $a"
done
{ [ -n "$_arch" ] && [ -z "$_am" ]; } \
  && ok  "T7.a 첫 ## 앞 **원형**: 줄 + 허용 원형 6개" \
  || nope "T7.a 원형 줄" "줄='${_arch}' 누락:${_am}"

_st=$(awk '/^## States/{f=1;next} f&&/^## /{exit} f' "$T")
{ printf '%s\n' "$_st" | grep -qE '^- Empty:' && printf '%s\n' "$_st" | grep -qF 'G-LIST-EMPTY-KIND'; } \
  && ok  "T7.b States Empty 행 + §6.1 규칙 포인터" \
  || nope "T7.b Empty 행" "States 에 '- Empty:' 또는 G-LIST-EMPTY-KIND 포인터 없음"

# 힌트가 판정 앵커를 담으면 원형만 채운 빈 복사본이 G-LIST-EMPTY-KIND 를 공짜로 통과한다
printf '%s\n' "$_st" | grep -qE '데이터 없음|결과 없음' \
  && nope "T7.c Empty 힌트" "판정 앵커(데이터 없음/결과 없음) 포함 — 빈 복사본이 규칙을 공짜로 통과" \
  || ok  "T7.c Empty 힌트에 판정 앵커 없음"

Q="$PLUGIN/scripts/_internal/check-screen-quality.sh"
TMPD=$(mktemp -d) || { nope "T7 mktemp" "임시 디렉터리 생성 실패"; finish; exit 1; }
trap 'rm -rf "$TMPD"' EXIT
cp "$T" "$TMPD/c.md"; cp "$PLUGIN/templates/screen.html" "$TMPD/c.html"
_o=$(bash "$Q" "$TMPD/c.md" "$TMPD/c.html" 2>/dev/null)
_h=$(printf '%s\n' "$_o" | head -1)
{ printf '%s' "$_h" | grep -q 'states=3/3' && printf '%s' "$_h" | grep -qE 'genre=unknown  anti=0$' \
  && ! printf '%s\n' "$_o" | grep -qF '[states] 미정의'; } \
  && ok  "T7.d 템플릿 복사본 states=3/3 · genre=unknown" \
  || nope "T7.d 템플릿 복사본" "head='$_h'"

# 원형만 채운 빈 복사본 — 계측 규칙이 전부 미충족이어야 정직한 측정이다
_fm=""
for pair in '목록:0/3' '폼:0/2' '다단 폼:0/3' '대시보드:0/1' '상세:n/a'; do
  a=${pair%%:*}; want=${pair#*:}
  sed "s/^\*\*원형\*\*:.*/**원형**: $a/" "$T" > "$TMPD/f.md"
  v=$(bash "$Q" "$TMPD/f.md" "$TMPD/c.html" 2>/dev/null | head -1 | grep -oE 'genre=[^ ]+' | cut -d= -f2)
  [ "$v" = "$want" ] || _fm="$_fm $a=$v(기대 $want)"
done
[ -z "$_fm" ] && ok "T7.e 원형만 채운 빈 복사본 — 계측 규칙 전부 미충족" || nope "T7.e" "$_fm"

# T8: 입력 label 연결 지침 (FID 20261005-screen-label-guidance AC-1·AC-2)
#   템플릿 html 주석 속 입력 예시는 복사하면 계측기에서 정상(N/N), 원본은 입력 0개, 지침 문구는 문서에 존재한다.
#   음성 대조: 예시에서 for 속성을 지우면 0/N + 상세줄, 지침 줄을 지운 사본은 존재 단언이 FAIL — 단언이 공허하지 않다.
H8="$PLUGIN/templates/screen.html"
TMP8=$(mktemp -d) || { nope "T8 mktemp" "임시 디렉터리 생성 실패"; finish; exit 1; }
printf '# X\n\n**원형**: 기타\n\n## States\n- Empty\n- Loading\n- Error\n' > "$TMP8/m.md"
_m8() { printf '<main>%s</main>\n' "$1" > "$TMP8/e.html"; bash "$Q" "$TMP8/m.md" "$TMP8/e.html" 2>/dev/null; }
_ex8=$(awk '/<!-- 입력 예시/{f=1;next} f&&/^[ \t]*-->/{f=0} f' "$H8")
_o8=$(_m8 "$_ex8")
if [ -n "$_ex8" ] && [ "$(printf '%s\n' "$_o8" | sed -n 1p | grep -o 'a11y-label=[^ ]*')" = "a11y-label=3/3" ] && ! printf '%s\n' "$_o8" | grep -qF '[a11y-label]'; then
  ok "T8.a 템플릿 html 주석 속 입력 예시(텍스트 2·select 1)를 복사하면 a11y-label=3/3·상세줄 없음"
else nope "T8.a" "예시 비었거나 계측 불일치: $(printf '%s\n' "$_o8" | sed -n 1p | grep -o 'a11y-label=[^ ]*')"; fi
_neg8=$(printf '%s\n' "$_ex8" | sed 's/ for="[^"]*"//')
_on8=$(_m8 "$_neg8")
if [ "$(printf '%s\n' "$_on8" | sed -n 1p | grep -o 'a11y-label=[^ ]*')" = "a11y-label=0/3" ] && printf '%s\n' "$_on8" | grep -qF '[a11y-label]'; then
  ok "T8.b 음성 — 예시에서 for 속성을 지우면 0/3 + [a11y-label] 상세줄(단언이 for 짝을 실제로 본다)"
else nope "T8.b" "$(printf '%s\n' "$_on8" | sed -n 1p | grep -o 'a11y-label=[^ ]*')"; fi
_orig8=$(bash "$Q" "$TMP8/m.md" "$H8" 2>/dev/null | sed -n 1p | grep -o 'a11y-label=[^ ]*')
[ "$_orig8" = "a11y-label=0/0" ] && ok "T8.c 템플릿 원본 html 은 a11y-label=0/0(예시는 주석이라 계측기가 걷는다)" || nope "T8.c" "원본 a11y=$_orig8"
_g8_screen() { grep -qE '^- 입력 이름:.*for 속성.*id.*fieldset.*legend' "$1"; }
_g8_screen "$T" && ok "T8.d screen.md 접근성에 입력 이름 지침(for 속성·id·fieldset·legend)" || nope "T8.d" "templates/screen.md 접근성에 '- 입력 이름:' 지침 없음"
grep -v '^- 입력 이름:' "$T" > "$TMP8/s.md"
if ! _g8_screen "$TMP8/s.md"; then ok "T8.e 음성 — 지침 줄을 지운 screen.md 사본은 존재 단언이 FAIL(공허하지 않다)"; else nope "T8.e" "지침 줄을 지워도 단언이 통과"; fi
rm -rf "$TMP8"

# T8.f~h: DESIGN.md 2종의 입력 label 연결 지침 (FID 20261005-screen-label-guidance AC-2)
D8="$PLUGIN/templates/DESIGN.md"; R8="$PLUGIN/DESIGN.md"
TMP9=$(mktemp -d) || { nope "T8 mktemp2" "임시 디렉터리 생성 실패"; finish; exit 1; }
_g8_input() { sed -n '/^### Input/,/^### Card/p' "$1" | grep -qE '^Label:.*for 속성.*id.*fieldset'; }
_g8_form() { grep -E '^\| 폼 \|' "$1" | grep -q 'for 속성과 입력 id'; }
_g8_guide() { sed -n '/^## 9\./,$p' "$1" | grep -qE '^- 입력마다 label 의 for 속성.*fieldset.*legend'; }
_g8_root6() { sed -n '/^## 6\./,$p' "$1" | grep -qE '^- 입력마다 label 의 for 속성.*fieldset.*legend'; }
_b8=""; _g8_input "$D8" || _b8="$_b8 [§4 Input]"; _g8_form "$D8" || _b8="$_b8 [§6.1 폼 행]"; _g8_guide "$D8" || _b8="$_b8 [§9]"
[ -z "$_b8" ] && ok "T8.f templates/DESIGN.md — §4 Input · §6.1 폼 행 · §9 컴포넌트 생성 지침에 label 연결 규칙" || nope "T8.f" "누락:$_b8"
_b8=""; _g8_input "$R8" || _b8="$_b8 [§4 Input]"; _g8_root6 "$R8" || _b8="$_b8 [§6]"
[ -z "$_b8" ] && ok "T8.g 루트 DESIGN.md — §4 Input · §6 컴포넌트 생성 지침에 label 연결 규칙" || nope "T8.g" "누락:$_b8"
grep -v '^Label:' "$D8" > "$TMP9/d.md"; grep -v '^- 입력마다 label 의 for 속성' "$R8" > "$TMP9/r.md"; sed 's/for 속성과 입력 id/for/' "$D8" > "$TMP9/f.md"
if ! _g8_input "$TMP9/d.md" && ! _g8_root6 "$TMP9/r.md" && ! _g8_form "$TMP9/f.md"; then ok "T8.h 음성 — Input 줄·§6 줄·§6.1 폼 행 문구를 지운 사본은 각 단언이 FAIL(공허하지 않다)"; else nope "T8.h" "지침을 지워도 단언이 통과"; fi
# T8.i — 지침의 선택지 규칙(선택지마다 자기 label, 그룹 이름은 fieldset 과 legend)이 계측기와 어긋나지 않는다(지침 주장 ↔ 계측 정합)
printf '# X\n\n**원형**: 기타\n\n## States\n- Empty\n- Loading\n- Error\n' > "$TMP9/m.md"
_m9() { printf '<main>%s</main>\n' "$1" > "$TMP9/e.html"; bash "$Q" "$TMP9/m.md" "$TMP9/e.html" 2>/dev/null | sed -n 1p | grep -o 'a11y-label=[^ ]*'; }
_ok9=$(_m9 '<fieldset><legend>역할</legend><label for="r-a">관리자</label><input type="radio" name="r" id="r-a"><label for="r-b">작성자</label><input type="radio" name="r" id="r-b"></fieldset>')
_lg9=$(_m9 '<fieldset><legend>역할</legend><input type="radio" name="r" id="r-a"><input type="radio" name="r" id="r-b"></fieldset>')
if [ "$_ok9" = "a11y-label=2/2" ] && [ "$_lg9" = "a11y-label=0/2" ]; then ok "T8.i 선택지마다 label(for/id) 이면 2/2, legend 만 두면 0/2 — 지침의 선택지 규칙이 계측기와 일치"; else nope "T8.i" "선택지 label=$_ok9 · legend 만=$_lg9"; fi
rm -rf "$TMP9"

finish
