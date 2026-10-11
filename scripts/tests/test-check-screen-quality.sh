#!/usr/bin/env bash
# test-check-screen-quality.sh — 화면 품질 계측기 계약 (FID 20260820-design-quality-gate)
# 실 screens/ 미변경 — tmpdir fixture 로 결정적 검증.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCRIPT="$PLUGIN/scripts/_internal/check-screen-quality.sh"
AGENT="$PLUGIN/agents/design-reviewer-ko.md"

TD=$(mktemp -d) || exit 1
trap 'rm -rf "$TD"' EXIT

# ── fixture: 위반(bad) / 정상(good) 쌍 ──
cat > "$TD/bad.html" <<'H'
<html><head><style>
:root { --color-primary: #7C3AED; --color-bg: #0F0F10; }
.btn { color: #7C3AED; background: #0F0F10; }
.shadow { box-shadow: 0 0 0 2px rgba(124,58,237,0.2); }
</style></head>
<body><div><input type="text"><input type="password"><select></select></div></body></html>
H
cat > "$TD/good.html" <<'H'
<html><head><style>
:root { --color-primary: #7C3AED; }
.btn { color: var(--color-primary); }
</style></head>
<body><main><nav></nav><section>
<label for="a">이메일</label><input id="a">
</section></main></body></html>
H
cat > "$TD/bad.md" <<'M'
## States
- Default: 빈 폼
- Loading: 버튼 비활성
- Error: 테두리 빨강
## 에러 메시지
- 오류
- 실패
M
cat > "$TD/good.md" <<'M'
## States
- 기본: 빈 상태 안내 표시
- 로딩: 스피너
- 오류: 재시도 버튼
## 에러 메시지
- 이메일 형식이 올바르지 않습니다
M

_val() {  # $1=출력 $2=키 → 값 추출
  printf '%s' "$1" | head -1 | grep -oE "$2=[^ ]+" | cut -d= -f2
}
_NLT='
'

bad=$(bash "$SCRIPT" "$TD/bad.md" "$TD/bad.html" 2>/dev/null)
good=$(bash "$SCRIPT" "$TD/good.md" "$TD/good.html" 2>/dev/null)

# ── T1.a: 5종 키를 모두 낸다 (AC-1) ──
miss=""
for k in states a11y-label semantic token microcopy; do
  printf '%s' "$bad" | head -1 | grep -q "$k=" || miss="$miss $k"
done
# 헤더 이름은 fixture 에서 파생한다 — 하드코딩하면 fixture 를 고칠 때 어서션이 조용히 낡는다
want_name=$(basename "$TD/bad.md" .md)
if printf '%s' "$bad" | head -1 | grep -q "^SCREEN-QUALITY: $want_name" && [ -z "$miss" ]; then
  ok "T1.a 5종 키 + SCREEN-QUALITY 헤더"
else
  nope "T1.a" "want=$want_name 누락:$miss head=$(printf '%s' "$bad" | head -1)"
fi

# ── T1.b~f: 각 검사가 양성·음성을 구분한다 (AC-2) ──
# 한쪽만 보면 항상통과 어서션이 된다 — bad/good 값이 서로 달라야 한다.
_diff_check() {  # $1=키 $2=TEST-ID $3=기대(bad) $4=기대(good)
  local kb kg; kb=$(_val "$bad" "$1"); kg=$(_val "$good" "$1")
  if [ "$kb" = "$3" ] && [ "$kg" = "$4" ] && [ "$kb" != "$kg" ]; then
    ok "$2 $1 양성·음성 구분 (bad=$kb good=$kg)"
  else
    nope "$2" "$1 bad=$kb(기대 $3) good=$kg(기대 $4)"
  fi
}
_diff_check states      T1.b "2/3" "3/3"
_diff_check a11y-label  T1.c "0/3" "1/1"
_diff_check semantic    T1.d "0"   "3"
_diff_check token       T1.e "2"   "0"
_diff_check microcopy   T1.f "2"   "0"

# ── T1.g: 항상 exit 0 (AC-3) ──
bash "$SCRIPT" "$TD/bad.md"  "$TD/bad.html"  >/dev/null 2>&1; r1=$?
bash "$SCRIPT" "$TD/good.md" "$TD/good.html" >/dev/null 2>&1; r2=$?
bash "$SCRIPT" "$TD/none.md" "$TD/none.html" >/dev/null 2>&1; r3=$?
if [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$r3" -eq 0 ]; then
  ok "T1.g 항상 exit 0 (위반=$r1 정상=$r2 부재=$r3) — 계측 전용"
else
  nope "T1.g" "위반=$r1 정상=$r2 부재=$r3"
fi

# ── T1.h: 판정 불가는 unknown (AC-4) ──
# .html 부재를 '위반 0' 으로 보고하면 무음 낙관이다 (doctor.sh v1.78.0 교훈).
out=$(bash "$SCRIPT" "$TD/good.md" "$TD/absent.html" 2>/dev/null)
uk_a=$(_val "$out" a11y-label); uk_s=$(_val "$out" semantic); st=$(_val "$out" states)
if [ "$uk_a" = "unknown" ] && [ "$uk_s" = "unknown" ] && [ "$st" = "3/3" ]; then
  ok "T1.h html 부재 → html 검사만 unknown, md 검사는 계속 (states=$st)"
else
  nope "T1.h" "a11y=$uk_a semantic=$uk_s states=$st (0 이 아니라 unknown 이어야)"
fi

# ── T1.i: read-only (AC-3) ──
b1=$(shasum "$TD/bad.html" | awk '{print $1}'); n1=$(ls -1 "$TD" | wc -l | tr -d ' ')
bash "$SCRIPT" "$TD/bad.md" "$TD/bad.html" >/dev/null 2>&1
b2=$(shasum "$TD/bad.html" | awk '{print $1}'); n2=$(ls -1 "$TD" | wc -l | tr -d ' ')
[ "$b1" = "$b2" ] && [ "$n1" = "$n2" ] && ok "T1.i read-only — sha·파일수 불변" \
  || nope "T1.i" "sha $b1→$b2 files $n1→$n2"

# ── 품질 관점 목록 (단일 소스 — 관점 추가 시 여기만 늘린다) ──
QP='상태 설계
접근성
디자인 시스템 준수
콘텐츠 품질
DESIGN 준수
장르 규칙
안티패턴'
QP_N=$(printf '%s\n' "$QP" | wc -l | tr -d ' ')

# ── T1.j: 리뷰어에 품질 관점 전건 + 실측 명령 (AC-5 · 20260821 AC-8) ──
pmiss=""
while IFS= read -r p; do
  grep -qF -e "$p" "$AGENT" || pmiss="$pmiss $p"
done <<EOF2
$QP
EOF2
cmd=$(grep -c 'check-screen-quality' "$AGENT" || true)
if [ -z "$pmiss" ] && [ "${cmd:-0}" -ge 1 ]; then
  ok "T1.j 품질 관점 ${QP_N}개 + 실측 명령 참조 (${cmd}건)"
else
  nope "T1.j" "누락:$pmiss cmd=$cmd"
fi

# ── T1.k: 품질 관점 전건에 Critical 없음 (AC-6) ──
# /start-all-auto 는 Critical>=1 에서 무인 실행을 정지한다 — 주관 판정으로 배치를 세우지 않는다.
badrow=""
while IFS= read -r p; do
  row=$(grep -F "| $p |" "$AGENT" | head -1)
  [ -n "$row" ] || { badrow="$badrow [$p:행없음]"; continue; }
  # 2번째 칸(Critical)이 '—' 또는 공백이어야 한다
  crit=$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')
  case "$crit" in ''|'—'|'-') ;; *) badrow="$badrow [$p:$crit]" ;; esac
done <<EOF2
$QP
EOF2
[ -z "$badrow" ] && ok "T1.k 품질 관점 ${QP_N}개 Critical 칸 비움" || nope "T1.k" "Critical 기재:$badrow"

# ── T1.l: 무출력 exit 0 금지 (외부 critic — T1.h 동일 클래스) ──
# 대상이 없거나 인자가 틀려도 침묵하면 리뷰어가 "위반 없음" 으로 읽는다.
o1=$(bash "$SCRIPT" 2>/dev/null); r1=$?
o2=$(cd "$TD" && bash "$SCRIPT" --all 2>/dev/null); r2=$?   # screens/ 없는 cwd
if [ "$r1" -eq 0 ] && printf '%s' "$o1" | grep -q 'SCREEN-QUALITY:.*unknown' \
   && [ "$r2" -eq 0 ] && printf '%s' "$o2" | grep -q 'SCREEN-QUALITY:.*unknown'; then
  ok "T1.l 대상 0개·인자 부족에도 unknown 1줄 출력 (무음 낙관 차단)"
else
  nope "T1.l" "인자부족 rc=$r1 out='$(printf '%s' "$o1" | head -1)' / --all rc=$r2 out='$(printf '%s' "$o2" | head -1)'"
fi

# ── T1.m: token 정의부 정규식이 scale·대문자 var 명을 인정한다 (Phase C I-1) ──
# `[a-z-]` 로 좁히면 --gray-100·--Color-Primary 를 정의부로 못 잡아 정상 코드가
# 전부 하드코딩으로 오탐된다. 리뷰어 기준이 "3건 이상=Important" 라 곧바로 오판정.
cat > "$TD/scale.html" <<'H'
<style>:root { --gray-100: #F3F4F6; --Color-Primary: #7C3AED; --c1: #ABCDEF; }
.x { color: #F3F4F6; }</style>
H
cp "$TD/good.md" "$TD/scale.md"
tk=$(_val "$(bash "$SCRIPT" "$TD/scale.md" "$TD/scale.html" 2>/dev/null)" token)
[ "$tk" = "1" ] && ok "T1.m token 정의부 — scale·대문자 var 명 인정 (token=$tk)" \
  || nope "T1.m" "token=$tk (기대 1 — 정의부 3건 제외 후 하드코딩 1건). [a-z-] 로 좁히면 4 가 나온다"

# ── T1.n: states 상세가 누락 '항목명' 을 낸다 (Phase C I-2) ──
# 리뷰어 표는 심각도를 종류로 가른다(empty·error=Important / loading만=Minor).
# 비율만 내면 그 판정을 계측 결과에서 도출할 수 없다.
det=$(bash "$SCRIPT" "$TD/bad.md" "$TD/bad.html" 2>/dev/null | grep '\[states\]')
if printf '%s' "$det" | grep -q 'empty'; then
  ok "T1.n states 상세에 누락 항목명 표기 ($(printf '%s' "$det" | sed 's/^ *//'))"
else
  nope "T1.n" "det='$det' (누락 항목명이 없으면 리뷰어가 심각도를 도출할 수 없다)"
fi

# ── T1.o: hidden input 은 label 대상에서 제외 (Phase C M-1) ──
cat > "$TD/hid.html" <<'H'
<main><label for="a">이메일</label><input id="a"><input type="hidden" name="csrf"></main>
H
cp "$TD/good.md" "$TD/hid.md"
al=$(_val "$(bash "$SCRIPT" "$TD/hid.md" "$TD/hid.html" 2>/dev/null)" a11y-label)
[ "$al" = "1/1" ] && ok "T1.o hidden input 제외 (a11y-label=$al)" \
  || nope "T1.o" "a11y-label=$al (기대 1/1 — hidden 은 label 대상 아님)"

# ══ genre 축 — 화면 원형별 장르 규칙 (FID 20260929-enterprise-genre-rules) ══
_gmd() {  # $1=파일 $2=원형 값('-'=원형 줄 생략) $3=본문
  { printf '# 픽스처\n\n'; [ "$2" = "-" ] || printf '**원형**: %s\n\n' "$2"; printf '%s\n' "$3"; } > "$1"
}
_gout() { bash "$SCRIPT" "$1" "$TD/good.html" 2>/dev/null; }
_gdet() { printf '%s\n' "$1" | grep -F '[genre]'; }

LIST_OK='## States
- Empty: 데이터 없음이면 첫 등록 안내, 검색 결과 없음이면 조건 초기화
- Loading: 스켈레톤
- Error: 재시도 버튼
## Interactions
- 페이지네이션 20건 단위 · 총 건수 표시
- 기본 정렬 기준: 등록일 내림차순'
FORM_OK='## States
- Empty: 빈 입력 폼
- Loading: 제출 중 버튼 비활성
- Error: 입력 단위 인라인 메시지
## Interactions
- 취소 버튼은 목록으로 이동'
WIZ_OK="$FORM_OK
- 단계 표시 1/3 · 이전 버튼 · 임시 저장"
DASH_OK='## States
- Empty: 지표 없음 안내
- Loading: 스켈레톤
- Error: 재시도
## Interactions
- 기간 선택 (최근 7일 기본)'
LNEG="${LIST_OK/기본 정렬 기준: 등록일 내림차순/제목 셀 중앙 정렬}"

# ── G1: 판정 불가·계측 규칙 없음 경로 (AC-1) — 숫자로 위장하지 않는다 ──
cp "$PLUGIN/templates/screen.md" "$TD/tpl.md"
_g1() {  # $1=라벨 $2=md $3=기대(unknown|n/a)
  local o v c; o=$(_gout "$2"); v=$(_val "$o" genre)
  c=$(_gdet "$o" | grep -c . || true)
  if [ "$v" != "$3" ] || _gdet "$o" | grep -q '미충족'; then
    nope "G1.$1" "genre=$v (기대 $3) det=$(_gdet "$o" | tr '\n' ' ')"
  elif [ "$3" = unknown ] && [ "$c" != 1 ]; then
    nope "G1.$1" "unknown 사유 상세줄 ${c}개 (기대 1)"
  elif [ "$3" = n/a ] && [ "$c" != 0 ]; then
    nope "G1.$1" "n/a 인데 상세줄 ${c}개"
  else
    ok "G1.$1 genre=$v"
  fi
}
_gmd "$TD/g-none.md" - "$LIST_OK";  _g1 원형없음 "$TD/g-none.md" unknown
_gmd "$TD/g-ph.md" '[목록 | 상세 | 폼 | 다단 폼 | 대시보드 | 기타]' "$LIST_OK"; _g1 자리표시자 "$TD/g-ph.md" unknown
_gmd "$TD/g-bad.md" 갤러리 "$LIST_OK"; _g1 목록밖 "$TD/g-bad.md" unknown
_gmd "$TD/g-det.md" 상세 "$LIST_OK";  _g1 상세 "$TD/g-det.md" n/a
_gmd "$TD/g-etc.md" 기타 "$LIST_OK";  _g1 기타 "$TD/g-etc.md" n/a
_g1 md부재 "$TD/absent-genre.md" unknown
_g1 login "$PLUGIN/screens/login.md" unknown
_g1 템플릿복사 "$TD/tpl.md" unknown

# G1.k 요약줄 키 순서 — 기존 5키 뒤 genre 가 마지막 (전체 줄 일치)
_kre='^SCREEN-QUALITY: [^ ]+  states=[^ ]+  a11y-label=[^ ]+  semantic=[^ ]+  token=[^ ]+  microcopy=[^ ]+  genre=[^ ]+  anti=[^ ]+$'
_gk=$(_gout "$TD/g-none.md" | head -1)
printf '%s\n' "$_gk" | grep -qE "$_kre" && ok "G1.k 요약줄 키 순서 — genre 마지막" || nope "G1.k" "head='$_gk'"
_gu1=$(bash "$SCRIPT" 2>/dev/null | head -1); _gu2=$(cd "$TD" && bash "$SCRIPT" --all 2>/dev/null | head -1)
if printf '%s\n' "$_gu1" | grep -qE '  genre=unknown  anti=unknown$' && printf '%s\n' "$_gu2" | grep -qE '  genre=unknown  anti=unknown$'; then
  ok "G1.u _unknown_line 도 genre=unknown 으로 끝남"
else
  nope "G1.u" "인자부족='$_gu1' --all='$_gu2'"
fi

# ── G2: 계측 규칙 7개 판별력 (AC-2) — 양성 통과 · 음성은 그 ID 만 적발 ──
_gcase() {  # $1=ID $2=원형 $3=양성 본문 $4=음성 본문 $5=규칙 수
  local p n pv nv want_n
  want_n="$(( $5 - 1 ))/$5"
  _gmd "$TD/gp.md" "$2" "$3"; p=$(_gout "$TD/gp.md"); pv=$(_val "$p" genre)
  _gmd "$TD/gn.md" "$2" "$4"; n=$(_gout "$TD/gn.md"); nv=$(_val "$n" genre)
  if [ "$pv" = "$5/$5" ] && [ "$nv" = "$want_n" ] \
     && ! _gdet "$p" | grep -q '미충족' \
     && [ "$(_gdet "$n" | grep -c '미충족' || true)" = 1 ] \
     && _gdet "$n" | grep -qF "[genre] $1 미충족 — "; then
    ok "G2.$1 양성 $pv · 음성 $nv — $1 만 적발"
  else
    nope "G2.$1" "양성=$pv(기대 $5/$5) 음성=$nv(기대 $want_n) det=$(_gdet "$n" | tr '\n' ' ')"
  fi
}
_gcase G-LIST-PAGING     목록      "$LIST_OK" "${LIST_OK/ · 총 건수 표시/}" 3
_gcase G-LIST-SORT       목록      "$LIST_OK" "$LNEG" 3
_gcase G-LIST-EMPTY-KIND 목록      "$LIST_OK" "${LIST_OK/, 검색 결과 없음이면 조건 초기화/}" 3
_gcase G-FORM-SUBMIT     폼        "$FORM_OK" "${FORM_OK/제출 중 버튼 비활성/스피너 표시}" 2
_gcase G-FORM-CANCEL     폼        "$FORM_OK" "${FORM_OK/취소 버튼은 목록으로 이동/저장 후 상세로 이동}" 2
_gcase G-WIZARD-STEP     '다단 폼' "$WIZ_OK"  "${WIZ_OK/ · 임시 저장/}" 3
_gcase G-DASH-PERIOD     대시보드  "$DASH_OK" "${DASH_OK/기간 선택 (최근 7일 기본)/지표 카드 4개}" 1

# ── G3: override 계약 (AC-3) — 조용히 제외하지 않는다 ──
_gmd "$TD/ov1.md" 목록 "$LNEG
<!-- genre-override: G-LIST-SORT 시간순 고정 스트림 -->"
o=$(_gout "$TD/ov1.md")
if [ "$(_val "$o" genre)" = 3/3 ] && _gdet "$o" | grep -qF '[genre] G-LIST-SORT override — 시간순 고정 스트림' \
   && ! _gdet "$o" | grep -q '미충족'; then
  ok "G3.a 사유 있는 override — 충족으로 세고 항상 출력"
else nope "G3.a" "genre=$(_val "$o" genre) det=$(_gdet "$o" | tr '\n' ' ')"; fi

_gmd "$TD/ov2.md" 목록 "$LNEG
<!-- genre-override: G-LIST-SORT -->"
o=$(_gout "$TD/ov2.md")
if [ "$(_val "$o" genre)" = 2/3 ] && _gdet "$o" | grep -qF '[genre] G-LIST-SORT 미충족' \
   && _gdet "$o" | grep -qF '[genre] G-LIST-SORT override 사유 없음 — 억제하지 않음'; then
  ok "G3.b 사유 없는 override — 억제 안 함 + 경고"
else nope "G3.b" "genre=$(_val "$o" genre) det=$(_gdet "$o" | tr '\n' ' ')"; fi

_gmd "$TD/ov3.md" 목록 "$LNEG
<!-- genre-override: G-DASH-PERIOD 무관 -->"
o=$(_gout "$TD/ov3.md")
if [ "$(_val "$o" genre)" = 2/3 ] && _gdet "$o" | grep -qF '[genre] G-DASH-PERIOD override 대상 아님' \
   && _gdet "$o" | grep -qF '[genre] G-LIST-SORT 미충족'; then
  ok "G3.c 원형 밖 ID override — 경고 · 판정 불변"
else nope "G3.c" "genre=$(_val "$o" genre) det=$(_gdet "$o" | tr '\n' ' ')"; fi

# G3.d 주석 구간만 제거 — 같은 줄의 본문은 판정에 남는다
_gmd "$TD/ov4.md" 목록 "$LNEG
- 기본 정렬 기준: 최신순 <!-- genre-override: G-DASH-PERIOD 무관 -->"
o=$(_gout "$TD/ov4.md")
[ "$(_val "$o" genre)" = 3/3 ] && ok "G3.d override 주석과 같은 줄 본문 보존" \
  || nope "G3.d" "genre=$(_val "$o" genre) (같은 줄 '정렬 기준' 이 사라짐)"

# G3.e 사유 문구가 다른 규칙 키워드로 새지 않는다
_gmd "$TD/ov5.md" 목록 "$LNEG
<!-- genre-override: G-DASH-PERIOD 정렬 기준 없음 -->"
o=$(_gout "$TD/ov5.md")
_gdet "$o" | grep -qF '[genre] G-LIST-SORT 미충족' && ok "G3.e override 사유가 판정 본문에 새지 않음" \
  || nope "G3.e" "det=$(_gdet "$o" | tr '\n' ' ')"

# G3.f·g 판독 불가 override(다중줄 · 사유에 '>') — 무음 통과 금지 (Phase C Important)
# 정규식이 못 잡으면 사유 키워드('기간 선택')가 본문으로 새어 충족으로 위장되고 override 줄도 안 나온다.
_gunparse() {  # $1=라벨 $2=md
  local o; o=$(_gout "$2")
  if [ "$(_val "$o" genre)" = 0/1 ] && _gdet "$o" | grep -qF '[genre] override 구문 판독 불가 1건' \
     && _gdet "$o" | grep -qF '[genre] G-DASH-PERIOD 미충족'; then
    ok "G3.$1 판독 불가 override — 경고 + 사유 키워드 미누설"
  else nope "G3.$1" "genre=$(_val "$o" genre) det=$(_gdet "$o" | tr '\n' ' ')"; fi
}
_gmd "$TD/ov6.md" 대시보드 "${DASH_OK/기간 선택 (최근 7일 기본)/지표 카드 4개}
<!-- genre-override: G-DASH-PERIOD
     기간 선택 없음 — 실시간 뷰 -->"
_gunparse f "$TD/ov6.md"
_gmd "$TD/ov7.md" 대시보드 "${DASH_OK/기간 선택 (최근 7일 기본)/지표 카드 4개}
<!-- genre-override: G-DASH-PERIOD 상단 > 기간 선택 대신 실시간 -->"
_gunparse g "$TD/ov7.md"

# ── G7: 복합 원형 (AC-7 · clarify Q1) ──
_gmd "$TD/c1.md" '목록, 상세' "$LIST_OK"; o=$(_gout "$TD/c1.md")
[ "$(_val "$o" genre)" = 3/3 ] && ok "G7.a 목록, 상세 → 3/3" || nope "G7.a" "genre=$(_val "$o" genre)"
_gmd "$TD/c1n.md" '목록, 상세' "$LNEG"; o=$(_gout "$TD/c1n.md")
{ [ "$(_val "$o" genre)" = 2/3 ] && _gdet "$o" | grep -qF '[genre] G-LIST-SORT 미충족'; } \
  && ok "G7.b 복합 원형 음성 → G-LIST-SORT 적발" || nope "G7.b" "genre=$(_val "$o" genre)"
_gmd "$TD/c2.md" '폼, 다단 폼' "$WIZ_OK"; o=$(_gout "$TD/c2.md")
[ "$(_val "$o" genre)" = 3/3 ] && ok "G7.c 폼, 다단 폼 → 중복 1회 3/3" || nope "G7.c" "genre=$(_val "$o" genre)"
_gmd "$TD/c3.md" '상세, 기타' "$LIST_OK"; o=$(_gout "$TD/c3.md")
[ "$(_val "$o" genre)" = n/a ] && ok "G7.d 상세, 기타 → n/a" || nope "G7.d" "genre=$(_val "$o" genre)"
_gmd "$TD/c4.md" '목록, 갤러리' "$LIST_OK"; o=$(_gout "$TD/c4.md")
{ [ "$(_val "$o" genre)" = unknown ] && _gdet "$o" | grep -F '원형 값 판독 불가: ' | grep -qF '갤러리'; } \
  && ok "G7.e 목록, 갤러리 → 전체 unknown" || nope "G7.e" "genre=$(_val "$o" genre)"

# ── G6: verify backstop 배선 (AC-6 · AC-8) — 화면 껍데기 점검과 같은 목록 ──
VS="$PLUGIN/skills/verifying-evidence-ko/SKILL.md"
_l_sh=$(grep -n '화면 껍데기 점검' "$VS" | head -1 | cut -d: -f1)
_l_cv=$(grep -n '테스트=spec 커버 점검' "$VS" | head -1 | cut -d: -f1)
_l_q=$(grep -n 'check-screen-quality\.sh --all' "$VS" | head -1 | cut -d: -f1)
if [ -n "$_l_sh" ] && [ -n "$_l_cv" ] && [ -n "$_l_q" ] && [ "$_l_q" -gt "$_l_sh" ] && [ "$_l_q" -lt "$_l_cv" ]; then
  _blk=$(sed -n "${_l_q},$((_l_cv - 1))p" "$VS")
  { printf '%s' "$_blk" | grep -qF '## 화면 품질 계측' && printf '%s' "$_blk" | grep -qF 'VERIFY: FAIL' \
    && printf '%s' "$_blk" | grep -qF 'graceful skip'; } \
    && ok "G6.a verify SKILL 계측 실행 · evidence 섹션 · 비차단 · skip" \
    || nope "G6.a" "블록에 '## 화면 품질 계측'·'VERIFY: FAIL'(승급 금지)·'graceful skip' 중 누락"
  printf '%s' "$_blk" | grep -qF '상세줄이 있는 화면' \
    && ok "G6.b 사용자 출력은 상세줄 있는 화면만 (AC-8)" || nope "G6.b" "출력 수준 문구 없음"
else
  nope "G6.a" "배선 위치 — 껍데기=${_l_sh:-없음} 계측=${_l_q:-없음} 커버=${_l_cv:-없음} (껍데기 < 계측 < 커버 기대)"
  nope "G6.b" "배선 부재로 판정 불가"
fi

# ══ 규칙 ID 카탈로그 (FID 20260929-design-rule-id-catalog) ══
_rules=$(bash "$SCRIPT" --rules 2>/dev/null); _rrc=$?
# 규칙 행 = 첫 셀이 S-/G-/A- 로 시작. NF==6 강제 — snippet/fix 안 '|' 가 열을 밀면 드러난다
_rrows=$(printf '%s\n' "$_rules" | awk -F'|' '{c=$2; gsub(/^ +| +$/,"",c)} c ~ /^[SGA]-/')
_rids=$(printf '%s\n' "$_rrows" | awk -F'|' '{c=$2; gsub(/^ +| +$/,"",c); print c}')
_rn=$(printf '%s\n' "$_rids" | grep -c . || true)
_rdup=$(printf '%s\n' "$_rids" | sort | uniq -d | tr '\n' ' ')
_rbad=$(printf '%s\n' "$_rrows" | awk -F'|' '{
  id=$2; s=$3; sn=$4; fx=$5; gsub(/^ +| +$/,"",id); gsub(/^ +| +$/,"",s); gsub(/^ +| +$/,"",sn); gsub(/^ +| +$/,"",fx)
  if (NF != 6) print "nf:" id
  if (s != "Important" && s != "Minor" && s != "단계형") print "sev:" id
  if (sn == "" || fx == "") print "empty:" id }' | tr '\n' ' ')
_rR=$(printf '%s\n' "$_rules" | awk -F'|' '{c=$2; gsub(/^ +| +$/,"",c)} c ~ /^R-/' | grep -c . || true)
if [ "$_rrc" -eq 0 ] && [ "${_rn:-0}" -eq 20 ] && [ -z "$_rdup" ] && [ -z "$_rbad" ] && [ "${_rR:-0}" -eq 0 ]; then
  ok "R1.a --rules 20행 · 4필드 · ID 유일 · severity 3종 · R- 없음"
else
  nope "R1.a" "rc=$_rrc n=$_rn dup='$_rdup' bad='$_rbad' R=$_rR"
fi
_gids=$(sed -n "s/^_GENRE_IDS='\(.*\)'\$/\1/p" "$SCRIPT")
_gmiss=""
for id in $_gids; do printf '%s\n' "$_rids" | grep -qx -- "$id" || _gmiss="$_gmiss $id"; done
{ [ -n "$_gids" ] && [ -z "$_gmiss" ]; } && ok "R1.b _GENRE_IDS 7개 전부 카탈로그에 있음" \
  || nope "R1.b" "gids='$_gids' 누락:$_gmiss"

# ── R2: 위반·경고 상세줄은 전부 카탈로그 ID 로 끝난다 (판정 불가 사유줄 제외) ──
printf '## States\n- Loading: 스피너\n' > "$TD/st2.md"          # empty·error 누락
_gmd "$TD/g-comma.md" ',' "$LIST_OK"                             # nv=0 경로(원형 자리표시자)
_rdl=""
for p in "$TD/bad.md|$TD/bad.html" "$TD/st2.md|$TD/good.html" \
         "$TD/g-none.md|$TD/good.html" "$TD/g-ph.md|$TD/good.html" "$TD/g-bad.md|$TD/good.html" "$TD/g-comma.md|$TD/good.html" \
         "$TD/ov1.md|$TD/good.html" "$TD/ov2.md|$TD/good.html" "$TD/ov3.md|$TD/good.html" "$TD/ov6.md|$TD/good.html" \
         "$TD/gn.md|$TD/good.html"; do
  _rdl="$_rdl$(bash "$SCRIPT" "${p%%|*}" "${p##*|}" 2>/dev/null | grep '^  \[')$_NLT"
done
_rdl=$(printf '%s\n' "$_rdl" | grep '^  \[' | grep -vF '[scope]' | grep -vF '화면 스펙 판독 불가')
_rchk=$(printf '%s\n' "$_rdl" | grep -c . || true)
_rno=$(printf '%s\n' "$_rdl" | grep -vE '  rule=[SGA]-[A-Z0-9-]+(,[SGA]-[A-Z0-9-]+)*$' | head -3)
_rukn=""
for id in $(printf '%s\n' "$_rdl" | sed -n 's/.*  rule=//p' | tr ',' '\n' | sort -u); do
  printf '%s\n' "$_rids" | grep -qx -- "$id" || _rukn="$_rukn $id"
done
if [ "${_rchk:-0}" -ge 12 ] && [ -z "$_rno" ] && [ -z "$_rukn" ]; then
  ok "R2.a 상세줄 ${_rchk}건 전부 카탈로그 ID 로 끝남"
else
  nope "R2.a" "검사 ${_rchk}건(기대 ≥12) ID 없음='$_rno' 카탈로그 밖:$_rukn"
fi
bash "$SCRIPT" "$TD/st2.md" "$TD/good.html" 2>/dev/null | grep -F '[states]' | grep -qE '  rule=S-STATES-EMPTY,S-STATES-ERROR$' \
  && ok "R2.b [states] 누락 항목별 ID (empty·error)" || nope "R2.b" "$(bash "$SCRIPT" "$TD/st2.md" "$TD/good.html" 2>/dev/null | grep -F '[states]')"
for want in G-ARCHETYPE-UNDECLARED G-OVERRIDE-INVALID G-OVERRIDE-UNREASONED S-A11Y-LABEL S-LANDMARK S-TOKEN-HEX S-COPY-VAGUE; do
  printf '%s\n' "$_rdl" | grep -qE "  rule=$want\$" || _rmiss2="${_rmiss2:-} $want"
done
[ -z "${_rmiss2:-}" ] && ok "R2.c 경고 규칙 7종이 각 발화 지점에서 실제로 나온다" || nope "R2.c" "미발화:$_rmiss2"
# R2.d [genre] <ID> 미충족 / <ID> override — 줄은 본문 ID 와 rule ID 가 같다
_rmm=$(printf '%s\n' "$_rdl" | grep -E '^  \[genre\] G-[A-Z-]+ (미충족|override) — ' \
  | awk '{ id=$2; r=$0; sub(/.*  rule=/, "", r); if (id != r) print id "≠" r }')
_rmn=$(printf '%s\n' "$_rdl" | grep -cE '^  \[genre\] G-[A-Z-]+ (미충족|override) — ' || true)
{ [ "${_rmn:-0}" -ge 3 ] && [ -z "$_rmm" ]; } && ok "R2.d genre 본문 ID == rule ID (${_rmn}줄)" || nope "R2.d" "검사 ${_rmn}줄 불일치:$_rmm"


# ══ anti 축 — 금지 패턴 3개 (FID 20260929-design-rule-id-catalog) ══
_aout() { bash "$SCRIPT" "$TD/good.md" "$1" 2>/dev/null; }
_adet() { printf '%s\n' "$1" | grep -F '[anti]'; }
_acase() {  # $1=라벨 $2=ID $3=양성 html $4=음성 html
  printf '%s\n' "$3" > "$TD/ap.html"; printf '%s\n' "$4" > "$TD/an.html"
  local p n; p=$(_aout "$TD/ap.html"); n=$(_aout "$TD/an.html")
  if [ "$(_val "$p" anti)" != 0 ] && [ -n "$(_val "$p" anti)" ] && _adet "$p" | grep -qE "  rule=$2\$" \
     && [ "$(_val "$n" anti)" = 0 ] && [ -z "$(_adet "$n")" ]; then
    ok "A1.$1 $2 양성 anti=$(_val "$p" anti) · 음성 anti=0"
  else
    nope "A1.$1" "$2 양성 anti=$(_val "$p" anti) det='$(_adet "$p")' · 음성 anti=$(_val "$n" anti) det='$(_adet "$n")'"
  fi
}
_acase a A-PLACEHOLDER-NAME '<main><p>John Doe</p></main>' '<main><!-- 예시
Lorem ipsum --><p>홍길동</p></main>'
_acase b A-SCROLL-LISTENER '<script>window.addEventListener("scroll", f);</script>' '<script>/* 예전 코드
window.addEventListener("scroll", f); */</script>'
_acase c A-VIEWPORT-HEIGHT '<style>.x { height: 100vh; }</style>' '<style>body { min-height: 100vh; }</style>'
_acase d A-VIEWPORT-HEIGHT '<div class="flex h-screen"></div>' '<div class="min-h-screen"></div>'
_acase f A-PLACEHOLDER-NAME '<script>foo(); // c</script><p>John Doe</p>' '<script>foo(); // John Doe</script><p>홍길동</p>'
_acase g A-PLACEHOLDER-NAME '<input type="file" accept="image/*"><p>John Doe</p>' '<input type="file" accept="image/*"><p>홍길동</p>'
_acase e A-SCROLL-LISTENER "<script>fetch('https://x.example/a'); window.addEventListener('scroll', g);</script>" "<script>
  // window.addEventListener('scroll', g);
</script>"
# Tailwind 변형 접두(md: · !)는 같은 위반 — min-/max- 는 계속 제외 (Phase C Important 1)
_acase h A-VIEWPORT-HEIGHT '<div class="md:h-screen"></div>' '<div class="min-h-screen"></div>'
_acase j A-VIEWPORT-HEIGHT '<div class="!h-screen"></div>' '<div class="max-h-screen"></div>'
# <script 앞의 텍스트 // 는 주석이 아니다 — 여는 태그를 지우면 스크립트 블록 통째로 무음 누락 (Phase C Important 2)
_acase i A-SCROLL-LISTENER '<p>a // b</p><script>window.addEventListener("scroll", f)</script>' '<p>a // b</p><script>foo()</script>'
# // 절단은 script 구간 안에서만 — 한 줄 두 블록 사이 텍스트 // 가 둘째 여는 태그를 지우면 안 되고 (Phase C 2회차 Important),
#   </script> 뒤 텍스트 // 도 절단 대상이 아니다 (Minor)
_acase k A-SCROLL-LISTENER '<script>a()</script><p>x // y</p><script>window.addEventListener("scroll", f)</script>' '<script>a()</script><p>x // y</p><script>foo()</script>'
_acase l A-PLACEHOLDER-NAME '<script>a()</script><p>x // John Doe</p>' '<script>a() // John Doe</script><p>홍길동 // z</p>'

# ── A4: 기준 화면 오탐 0 (AC-4) — 템플릿 복사본 · design-screen 스캐폴드 · screens/login ──
cp "$PLUGIN/templates/screen.md" "$TD/tplA.md"; cp "$PLUGIN/templates/screen.html" "$TD/tplA.html"
mkdir -p "$TD/sc/screens"
( cd "$TD/sc" && bash "$PLUGIN/scripts/_internal/design-screen.sh" demo >/dev/null 2>&1 )
_a4=""
for p in "$TD/tplA.md|$TD/tplA.html" "$TD/sc/screens/demo.md|$TD/sc/screens/demo.html" \
         "$PLUGIN/screens/login.md|$PLUGIN/screens/login.html"; do
  [ -f "${p##*|}" ] || { _a4="$_a4 부재:${p##*|}"; continue; }
  o=$(bash "$SCRIPT" "${p%%|*}" "${p##*|}" 2>/dev/null)
  { [ "$(_val "$o" anti)" = 0 ] && [ -z "$(_adet "$o")" ]; } || _a4="$_a4 $(basename "${p##*|}"):anti=$(_val "$o" anti)"
done
[ -z "$_a4" ] && ok "A4 템플릿 복사본·스캐폴드·login 모두 anti=0" || nope "A4" "$_a4"

# ── A6: 판정 불가 (AC-6) ──
o=$(bash "$SCRIPT" "$TD/good.md" "$TD/absent.html" 2>/dev/null)
{ [ "$(_val "$o" anti)" = unknown ] && [ -z "$(_adet "$o")" ]; } \
  && ok "A6 .html 부재 → anti=unknown · 금지 패턴 상세줄 없음" || nope "A6" "anti=$(_val "$o" anti) det='$(_adet "$o")'"

# ── A7: anti= 는 적중 건수 합 · 자리표시 이름은 .html 만 (AC-7) ──
printf '<main><p>John Doe</p><p>john doe</p><div class="h-screen"></div></main>\n' > "$TD/a7.html"
{ cat "$TD/good.md"; printf '## 필드 정의표\n| 이름 | John Doe |\n'; } > "$TD/a7.md"
o=$(bash "$SCRIPT" "$TD/a7.md" "$TD/a7.html" 2>/dev/null)
_a7p=$(_adet "$o" | grep -E '  rule=A-PLACEHOLDER-NAME$')
_a7v=$(_adet "$o" | grep -E '  rule=A-VIEWPORT-HEIGHT$')
if [ "$(_val "$o" anti)" = 3 ] && printf '%s' "$_a7p" | grep -q ' 2건 ' && printf '%s' "$_a7v" | grep -q ' 1건 '; then
  ok "A7 anti=3 (자리표시 2 + 뷰포트 1) · .md 예시값 미집계"
else
  nope "A7" "anti=$(_val "$o" anti) p='$_a7p' v='$_a7v'"
fi

# ══ --regress 화면 회귀 (FID 20260929-screen-regression-guard) ══
#   임시 git repo 격리 — 상속 GIT_* 가 실패를 가린 전례(FID 1b N0) · hooks 비활성 · 브랜치명 비의존
_RG="$TD/rg"
mkdir -p "$_RG/screens" || { nope "RG0 임시 repo" "mkdir 실패"; finish; exit 1; }
_rgit() { ( cd "$_RG" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git -c user.name=t -c user.email=t@example.invalid -c core.hooksPath= "$@" ) >/dev/null 2>&1; }
_rgrun() {  # $1=기준 ref(빈값=인자 없음) · 환경은 호출자가 export
  ( cd "$_RG" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && bash "$SCRIPT" --regress ${1:+"$1"} 2>/dev/null )
}
_rv() { printf '%s\n' "$1" | grep -E "^SCREEN-REGRESSION: $2 " | head -1 | grep -oE "$3=[^ ]+" | cut -d= -f2; }

# 기준 화면: a(채움 · 랜드마크 없음 · 색 하드코딩 없음) · b(삭제·이름변경용) · s(기준이 껍데기)
_rg_rows() { i=1; while [ "$i" -le "$1" ]; do printf '<div class="row"><label for="f%s">필드 %s</label><input id="f%s"></div>\n' "$i" "$i" "$i"; i=$((i+1)); done; }
_rg_lines() { i=1; while [ "$i" -le "$1" ]; do printf -- '- 항목 %s 설명 텍스트입니다\n' "$i"; i=$((i+1)); done; }
_rg_html() { printf '<html><head><style>:root { --c: #112233; } .row { color: var(--c); }</style></head><body>\n'; _rg_rows "$1"; printf '</body></html>\n'; }
_rg_md() { printf -- '---\nscreen: "a"\n---\n# A\n\n## 목적\n\n'; _rg_lines "$1"; }
_rg_html 30 > "$_RG/screens/a.html"; _rg_md 30 > "$_RG/screens/a.md"
_rg_html 20 > "$_RG/screens/b.html"; _rg_md 20 > "$_RG/screens/b.md"
{ printf '<!-- specops:screen-placeholder — 실제 내용으로 채우면 이 줄을 삭제한다 -->\n'; _rg_html 30; } > "$_RG/screens/s.html"
{ printf '<!-- specops:screen-placeholder — 실제 내용으로 채우면 이 줄을 삭제한다 -->\n'; _rg_md 30; } > "$_RG/screens/s.md"
_rgit init -q && _rgit add -A && _rgit commit -q -m base
_RGB=$( cd "$_RG" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git rev-parse HEAD 2>/dev/null )
[ -n "$_RGB" ] || { nope "RG0 임시 repo" "base 커밋 실패"; finish; exit 1; }
_rg_reset() { _rgit checkout -q -- screens/ ; _rgit clean -fdq -- screens/ ; }

# RG1 축소 감지 (AC-1)
_rg_html 10 > "$_RG/screens/a.html"; o=$(_rgrun "$_RGB")
h=$(_rv "$o" a html)
if awk -v r="$h" 'BEGIN{exit !(r+0 > 0 && r+0 < 0.60)}' && [ "$(printf '%s\n' "$o" | grep -c '^  \[shrink\] \.html ' || true)" = 1 ]; then
  ok "RG1.a .html 축소 → html=$h · [shrink] .html 1줄"
else nope "RG1.a" "html=$h out=$(printf '%s' "$o" | tr '\n' '|')"; fi
_rg_reset
_rg_md 8 > "$_RG/screens/a.md"; o=$(_rgrun "$_RGB")
m=$(_rv "$o" a md)
if awk -v r="$m" 'BEGIN{exit !(r+0 > 0 && r+0 < 0.60)}' && [ "$(printf '%s\n' "$o" | grep -c '^  \[shrink\] \.md ' || true)" = 1 ]; then
  ok "RG1.b .md 축소 → md=$m · [shrink] .md 1줄"
else nope "RG1.b" "md=$m out=$(printf '%s' "$o" | tr '\n' '|')"; fi
_rg_reset

# RG2 정상 개편 통과 (AC-2)
_rg_rev() { awk '{a[NR]=$0} END{for(i=NR;i>0;i--) print a[i]}' "$1" > "$1.t" && mv "$1.t" "$1"; }
_rg2() {  # $1=라벨
  o=$(_rgrun "$_RGB"); m=$(_rv "$o" a md); h=$(_rv "$o" a html)
  if ! printf '%s\n' "$o" | grep -q '^  \[shrink\]' && printf '%s' "$m" | grep -qE '^[0-9]+\.[0-9]{2}$' && printf '%s' "$h" | grep -qE '^[0-9]+\.[0-9]{2}$'; then
    ok "RG2.$1 정상 개편 통과 (md=$m html=$h)"
  else nope "RG2.$1" "md=$m html=$h out=$(printf '%s' "$o" | tr '\n' '|')"; fi
  _rg_reset
}
_rg_rev "$_RG/screens/a.md"; _rg_rev "$_RG/screens/a.html"; _rg2 a
_rg_html 36 > "$_RG/screens/a.html"; _rg_md 36 > "$_RG/screens/a.md"; _rg2 b
_rg_html 26 > "$_RG/screens/a.html"; _rg_md 26 > "$_RG/screens/a.md"; _rg2 c

# RG3 비교하지 않는 경로는 사유를 밝힌다 (AC-3)
_rg_html 30 > "$_RG/screens/n.html"; _rg_md 30 > "$_RG/screens/n.md"; o=$(_rgrun "$_RGB")
{ [ "$(_rv "$o" n md)" = new ] && [ "$(_rv "$o" n html)" = new ] && [ "$(_rv "$o" n new-rules)" = unknown ] \
  && printf '%s\n' "$o" | grep -q '^  \[lineage\] \.md 이전 버전 없음'; } \
  && ok "RG3.a 새 화면 → new · [lineage]" || nope "RG3.a" "$(printf '%s' "$o" | tr '\n' '|')"
_rg_reset
o=$(_rgrun "$_RGB")
{ [ "$(_rv "$o" s md)" = shell ] && [ "$(_rv "$o" s html)" = shell ] \
  && printf '%s\n' "$o" | grep -q '^  \[lineage\] \.md 이전 버전이 템플릿 상태' \
  && ! printf '%s\n' "$o" | awk '/^SCREEN-REGRESSION: s /{f=1; next} /^SCREEN-REGRESSION: /{f=0} f' | grep -q '\[shrink\]'; } \
  && ok "RG3.b 기준이 껍데기 → shell · [lineage] · [shrink] 없음" || nope "RG3.b" "$(printf '%s' "$o" | tr '\n' '|')"
mkdir -p "$TD/nogit/screens"; cp "$_RG/screens/a.md" "$_RG/screens/a.html" "$TD/nogit/screens/"
o=$( cd "$TD/nogit" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE GIT_CEILING_DIRECTORIES="$TD" bash "$SCRIPT" --regress 2>/dev/null )
{ printf '%s\n' "$o" | grep -qE '^SCREEN-REGRESSION: \(none\)  base=unknown  md=unknown  html=unknown  new-rules=unknown$' \
  && printf '%s\n' "$o" | grep -q '^  \[scope\] '; } && ok "RG3.c git 저장소 아님 → unknown · [scope]" || nope "RG3.c" "$o"
o=$(_rgrun "no-such-ref-xyz")
{ printf '%s\n' "$o" | grep -q 'base=unknown' && printf '%s\n' "$o" | grep -q '^  \[scope\] '; } \
  && ok "RG3.d 없는 기준 ref → unknown · [scope]" || nope "RG3.d" "$o"
mkdir -p "$TD/rg0"; ( cd "$TD/rg0" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git init -q && printf 'x\n' > x && git -c user.name=t -c user.email=t@example.invalid -c core.hooksPath= add x && git -c user.name=t -c user.email=t@example.invalid -c core.hooksPath= commit -qm x ) >/dev/null 2>&1
_rg0b=$( cd "$TD/rg0" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git rev-parse HEAD 2>/dev/null )
o=$( cd "$TD/rg0" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && bash "$SCRIPT" --regress "$_rg0b" 2>/dev/null )
{ printf '%s\n' "$o" | grep -q '^SCREEN-REGRESSION: (none) ' && printf '%s\n' "$o" | grep -q '^  \[scope\] '; } \
  && ok "RG3.e 화면 0개 → (none) · [scope]" || nope "RG3.e" "$o"
( cd "$TD/rg0" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git branch -m "$(git symbolic-ref --short HEAD)" trunk-x ) >/dev/null 2>&1   # HEAD 만 옮기면 refs/heads/main 이 남는다 — 실제 개명
o=$( cd "$TD/rg0" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && bash "$SCRIPT" --regress 2>/dev/null )
{ printf '%s\n' "$o" | grep -q 'base=unknown' && printf '%s\n' "$o" | grep -qF '[scope] main·master 브랜치가 없다'; } \
  && ok "RG3.f 기준 인자 없고 main·master 없음 → unknown · [scope] 브랜치 없음 경로" || nope "RG3.f" "$o"

# RG5 임계값 조정 (AC-5) — 26/30 행 ≈ 0.85
_rg_html 26 > "$_RG/screens/a.html"
o=$(_rgrun "$_RGB"); printf '%s\n' "$o" | grep -q '^  \[shrink\] \.html ' && nope "RG5.a" "기본 0.60 인데 [shrink]" || ok "RG5.a 기본 0.60 — 0.85 는 통과"
o=$(export SPECOPS_SCREEN_SHRINK_RATIO=0.9; _rgrun "$_RGB")
printf '%s\n' "$o" | grep -qE '^  \[shrink\] \.html .* < 0\.90\) ' && ok "RG5.b 0.9 로 조정 → [shrink]" || nope "RG5.b" "$(printf '%s' "$o" | tr '\n' '|')"
o=$(export SPECOPS_SCREEN_SHRINK_RATIO=abc; _rgrun "$_RGB")
{ ! printf '%s\n' "$o" | grep -q '^  \[shrink\] \.html ' && printf '%s\n' "$o" | grep -q '^  \[config\] '; } \
  && ok "RG5.c 잘못된 값 → 기본 적용 + [config]" || nope "RG5.c" "$(printf '%s' "$o" | tr '\n' '|')"
_rg_reset

# RG7 삭제·이름 변경 (AC-7)
rm -f "$_RG/screens/b.md" "$_RG/screens/b.html"; o=$(_rgrun "$_RGB")
{ [ "$(_rv "$o" b md)" = deleted ] && [ "$(_rv "$o" b html)" = deleted ] && [ "$(_rv "$o" b new-rules)" = unknown ] \
  && printf '%s\n' "$o" | grep -q '^  \[lineage\] \.md 기준 커밋에 있던 파일이 없다'; } \
  && ok "RG7.a 삭제 → deleted · [lineage]" || nope "RG7.a" "$(printf '%s' "$o" | tr '\n' '|')"
_rg_reset
mv "$_RG/screens/b.md" "$_RG/screens/c.md"; mv "$_RG/screens/b.html" "$_RG/screens/c.html"; o=$(_rgrun "$_RGB")
{ [ "$(_rv "$o" b md)" = deleted ] && [ "$(_rv "$o" c md)" = new ]; } && ok "RG7.b 이름 변경 → 옛 이름 deleted · 새 이름 new" || nope "RG7.b" "$(printf '%s' "$o" | tr '\n' '|')"
_rg_reset

# RGR 작업 트리·인덱스 불변 · exit 0 (AC-R-1)
_rg_html 10 > "$_RG/screens/a.html"
_st1=$( cd "$_RG" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git status --porcelain 2>/dev/null )
( cd "$_RG" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && bash "$SCRIPT" --regress "$_RGB" >/dev/null 2>&1 ); _rgrc=$?
_st2=$( cd "$_RG" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git status --porcelain 2>/dev/null )
{ [ "$_rgrc" -eq 0 ] && [ "$_st1" = "$_st2" ] && [ -n "$_st1" ]; } && ok "RGR --regress exit 0 · 작업 트리·인덱스 불변" || nope "RGR" "rc=$_rgrc st1='$_st1' st2='$_st2'"
_rg_reset

# RG4 새 위반만 보고 (AC-4) — 기준 a 는 이미 S-LANDMARK(랜드마크 0) 보유
o=$(_rgrun "$_RGB")
[ "$(_rv "$o" a new-rules)" = 0 ] && ok "RG4.b 변화 없음 → new-rules=0" || nope "RG4.b" "new-rules=$(_rv "$o" a new-rules)"
{ _rg_html 30 | sed 's#</body>#<p style="color: \#AB12CD">x</p></body>#'; } > "$_RG/screens/a.html"
o=$(_rgrun "$_RGB")
_rg4=$(printf '%s\n' "$o" | awk '/^SCREEN-REGRESSION: a /{f=1; next} /^SCREEN-REGRESSION: /{f=0} f')
if [ "$(_rv "$o" a new-rules)" = 1 ] && printf '%s\n' "$_rg4" | grep -q '^  \[new-rule\] S-TOKEN-HEX — ' \
   && ! printf '%s\n' "$_rg4" | grep -q '\[new-rule\] S-LANDMARK'; then
  ok "RG4.a 새 위반 S-TOKEN-HEX 만 보고 (기존 S-LANDMARK 제외)"
else nope "RG4.a" "new-rules=$(_rv "$o" a new-rules) det='$(printf '%s' "$_rg4" | tr '\n' '|')'"; fi
_rg_reset

# ── 2차 기준 커밋: 로그인(비ASCII 이름) · mdonly(.html 없음) · mix(md 채움 · html 껍데기) — Phase C 재dispatch ──
_rg_html 20 > "$_RG/screens/로그인.html"; _rg_md 20 > "$_RG/screens/로그인.md"
_rg_md 20 > "$_RG/screens/mdonly.md"
_rg_md 20 > "$_RG/screens/mix.md"
{ printf '<!-- specops:screen-placeholder — 실제 내용으로 채우면 이 줄을 삭제한다 -->\n'; _rg_html 20; } > "$_RG/screens/mix.html"
_rgit add -A && _rgit commit -q -m base2
_RGB2=$( cd "$_RG" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git rev-parse HEAD 2>/dev/null )
if [ -z "$_RGB2" ] || [ "$_RGB2" = "$_RGB" ]; then nope "RG0.b 2차 기준 커밋" "commit 실패"; else

# RG7.c 비ASCII 화면명 삭제 → deleted (Critical — ls-tree 인용 출력이 기준-전용 화면을 무음으로 만들었다)
rm -f "$_RG/screens/로그인.md" "$_RG/screens/로그인.html"; o=$(_rgrun "$_RGB2")
{ [ "$(_rv "$o" 로그인 md)" = deleted ] && [ "$(_rv "$o" 로그인 html)" = deleted ]; } \
  && ok "RG7.c 비ASCII 이름(로그인) 삭제 → deleted 줄 존재" || nope "RG7.c" "$(printf '%s' "$o" | tr '\n' '|')"
_rg_reset

# RG3.g 기준 == HEAD → [scope] 1줄 (커밋된 변경은 비교되지 않는다) · 기준 ≠ HEAD 면 없음
o=$(_rgrun HEAD)
printf '%s\n' "$o" | grep -qF '  [scope] 기준 커밋이 HEAD 와 같다' && ok "RG3.g --regress HEAD → [scope] 기준==HEAD 고백" || nope "RG3.g" "$(printf '%s' "$o" | tr '\n' '|')"
o=$(_rgrun "$_RGB")
printf '%s\n' "$o" | grep -qF '  [scope] 기준 커밋이 HEAD 와 같다' && nope "RG3.g-neg" "기준 ≠ HEAD 인데 [scope] 줄" || ok "RG3.g-neg 기준 ≠ HEAD → [scope] 없음"

# RG3.h .html 이 기준·작업 트리 모두 없음 → html=unknown + 사유줄
o=$(_rgrun "$_RGB2")
{ [ "$(_rv "$o" mdonly html)" = unknown ] \
  && printf '%s\n' "$o" | awk '/^SCREEN-REGRESSION: mdonly /{f=1; next} /^SCREEN-REGRESSION: /{f=0} f' | grep -qF '[lineage] .html 기준·작업 트리 모두 없음 — 비교하지 않았다'; } \
  && ok "RG3.h .html 양측 부재 → html=unknown · [lineage] 사유" || nope "RG3.h" "$(printf '%s' "$o" | tr '\n' '|')"

# RG4.c 혼합 계보(md 숫자 · html shell) → new-rules=unknown · [new-rule] 없음 (T2 Important — 자기모순 출력 차단)
{ _rg_html 20 | sed 's#</body>#<p style="color: \#AB12CD">x</p></body>#'; } > "$_RG/screens/mix.html"
o=$(_rgrun "$_RGB2")
_rg4c=$(printf '%s\n' "$o" | awk '/^SCREEN-REGRESSION: mix /{f=1; next} /^SCREEN-REGRESSION: /{f=0} f')
{ [ "$(_rv "$o" mix html)" = shell ] && [ "$(_rv "$o" mix new-rules)" = unknown ] && ! printf '%s\n' "$_rg4c" | grep -q '\[new-rule\]'; } \
  && ok "RG4.c md 숫자 · html shell → new-rules=unknown · [new-rule] 없음" || nope "RG4.c" "new-rules=$(_rv "$o" mix new-rules) det='$(printf '%s' "$_rg4c" | tr '\n' '|')'"
_rg_reset
fi

# RG6 verify 배선 (AC-6) — 화면 품질 계측 bullet 과 테스트=spec 커버 점검 사이
_l_rq=$(grep -n 'check-screen-quality\.sh --all' "$VS" | head -1 | cut -d: -f1)
_l_rr=$(grep -n 'check-screen-quality\.sh --regress' "$VS" | head -1 | cut -d: -f1)
_l_rc=$(grep -n '테스트=spec 커버 점검' "$VS" | head -1 | cut -d: -f1)
if [ -n "$_l_rq" ] && [ -n "$_l_rr" ] && [ -n "$_l_rc" ] && [ "$_l_rr" -gt "$_l_rq" ] && [ "$_l_rr" -lt "$_l_rc" ]; then
  _rblk=$(sed -n "${_l_rr},$((_l_rc - 1))p" "$VS")
  { printf '%s' "$_rblk" | grep -qF '## 화면 회귀' && printf '%s' "$_rblk" | grep -qF 'VERIFY: FAIL' \
    && printf '%s' "$_rblk" | grep -qF '승급' && printf '%s' "$_rblk" | grep -qF 'graceful skip'; } \
    && ok "RG6 verify SKILL --regress 실행 · ## 화면 회귀 · 비차단 · 승급 조건 · skip" \
    || nope "RG6" "블록에 '## 화면 회귀'·'VERIFY: FAIL'·'승급'·'graceful skip' 중 누락"
else
  nope "RG6" "배선 위치 — 계측=${_l_rq:-없음} 회귀=${_l_rr:-없음} 커버=${_l_rc:-없음}"
fi

# ── H: FID 20261004-screen-lint-gaps — 표 형식 에러 문구 · 한글 States · 원형 선언 변형 (양성·음성 쌍) ──
_hq() { bash "$SCRIPT" "$1" "$TD/good.html" 2>/dev/null; }
_hbase() { printf '# X\n\n**원형**: 기타\n\n## States\n- Empty: e\n- Loading: l\n- Error: x\n\n## 에러 메시지\n\n'; }
_hhead='| 상황 | 사용자에게 보이는 문구 | 복구 경로 |
|---|---|---|'

# H1: S-COPY-VAGUE — 표 데이터 행의 둘째 칸 (정확 일치만 · 자리표시자·헤더·구분 행 제외)
{ _hbase; printf '%s\n| 검증 | 오류 | 포커스 |\n| 네트워크 | 실패 | 재시도 |\n| 권한 | 접근 권한이 없습니다 | 문의 |\n' "$_hhead"; } > "$TD/h1a.md"
o=$(_hq "$TD/h1a.md")
if [ "$(_val "$o" microcopy)" = "2" ] && printf '%s' "$o" | grep -q '무정보 에러 문구 2건 (전체 3건).*rule=S-COPY-VAGUE'; then
  ok "H1.a 표 형식 무정보 2/3행 → microcopy=2 · 상세줄 '(전체 3건)' 분모"; else nope "H1.a" "microcopy=$(_val "$o" microcopy) out=$(printf '%s' "$o" | grep microcopy)"; fi
{ _hbase; printf '%s\n| a | [예: 오류] | b |\n| c | "오류" | d |\n| e | **실패** | f |\n| g | 에러. | h |\n' "$_hhead"; } > "$TD/h1b.md"
o=$(_hq "$TD/h1b.md")
if [ "$(_val "$o" microcopy)" = "0" ] && ! printf '%s' "$o" | grep -q 'S-COPY-VAGUE'; then
  ok "H1.b 음성 — 자리표시자·따옴표·굵게·마침표 변형·헤더 행은 집계하지 않는다(정확 일치만)"; else nope "H1.b" "microcopy=$(_val "$o" microcopy)"; fi
{ _hbase; printf -- '- 오류\n- 저장에 실패했습니다\n| 상황 | 문구 | 경로 |\n|---|---|---|\n| a | 에러 | b |\n'; } > "$TD/h1c.md"
o=$(_hq "$TD/h1c.md")
if [ "$(_val "$o" microcopy)" = "2" ] && printf '%s' "$o" | grep -q '(전체 3건)'; then
  ok "H1.c 불릿+표 혼합 → 무정보 2 · 전체 3"; else nope "H1.c" "microcopy=$(_val "$o" microcopy) $(printf '%s' "$o" | grep microcopy)"; fi
o=$(_hq "$TD/bad.md")
if [ "$(_val "$o" microcopy)" = "2" ] && printf '%s' "$o" | grep -q '(전체 2건)'; then
  ok "H1.d 불릿 전용(기존 fixture) 결과 불변 — microcopy=2 · 전체 2"; else nope "H1.d" "microcopy=$(_val "$o" microcopy)"; fi

{ _hbase; printf -- '- [예: 오류]\n%s\n| a | [예: 실패] | b |\n| c | 오류 | d |\n' "$_hhead"; } > "$TD/h1e.md"
o=$(_hq "$TD/h1e.md")
if [ "$(_val "$o" microcopy)" = "1" ] && printf '%s' "$o" | grep -q '(전체 1건)'; then
  ok "H1.e 분모 — 불릿·표 자리표시자 [예: …] 는 전체 건수에서도 제외(무정보 1 · 전체 1)"; else nope "H1.e" "microcopy=$(_val "$o" microcopy) $(printf '%s' "$o" | grep microcopy)"; fi

{ _hbase; printf -- '---\n- 오류\n%s\n| a | 에러 | b |\n' "$_hhead"; } > "$TD/h1f.md"
o=$(_hq "$TD/h1f.md")
if [ "$(_val "$o" microcopy)" = "2" ] && printf '%s' "$o" | grep -q '(전체 2건)'; then
  ok "H1.f 수평선 --- 은 불릿이 아니다 — 분모에서 제외(무정보 2 · 전체 2)"; else nope "H1.f" "microcopy=$(_val "$o" microcopy) $(printf '%s' "$o" | grep microcopy)"; fi

# CRLF 줄끝 — 구 grep 은 [[:space:]] 로 \r 을 흡수했다(Phase C Critical). \r 을 공백처럼 걷지 않으면 불릿은 0건이 되고 표는 헤더·구분 행이 분모로 샌다.
{ _hbase; printf -- '- 오류\r\n- 실패\r\n- 저장에 실패했습니다\r\n'; } > "$TD/h1g.md"
o=$(_hq "$TD/h1g.md")
if [ "$(_val "$o" microcopy)" = "2" ] && printf '%s' "$o" | grep -q '(전체 3건)'; then
  ok "H1.g CRLF 불릿 — \\r 을 공백처럼 걷는다(무정보 2 · 전체 3)"; else nope "H1.g" "microcopy=$(_val "$o" microcopy) $(printf '%s' "$o" | grep microcopy)"; fi
{ _hbase; printf '| 상황 | 사용자에게 보이는 문구 | 복구 경로 |\r\n|---|---|---|\r\n| a | 오류 | b |\r\n'; } > "$TD/h1h.md"
o=$(_hq "$TD/h1h.md")
if [ "$(_val "$o" microcopy)" = "1" ] && printf '%s' "$o" | grep -q '(전체 1건)'; then
  ok "H1.h CRLF 표 — 헤더·구분 행이 분모로 새지 않는다(무정보 1 · 전체 1)"; else nope "H1.h" "microcopy=$(_val "$o" microcopy) $(printf '%s' "$o" | grep microcopy)"; fi

# H1.i 표 파서 경계 — 빈 둘째 칸(분모 제외) · 끝 파이프 없는 행(집계·분모 모두 제외)
{ _hbase; printf '%s\n| a | 오류 | b |\n| c |  | d |\n| e | 오류\n' "$_hhead"; } > "$TD/h1i.md"
o=$(_hq "$TD/h1i.md")
if [ "$(_val "$o" microcopy)" = "1" ] && printf '%s' "$o" | grep -q '(전체 1건)'; then
  ok "H1.i 표 경계 — 빈 둘째 칸·끝 파이프 없는 행은 집계·분모에서 제외(무정보 1 · 전체 1)"; else nope "H1.i" "microcopy=$(_val "$o" microcopy) $(printf '%s' "$o" | grep microcopy)"; fi

# H2: S-STATES — `## 상태` 헤딩 · 한글 empty 어휘, states 와 G-LIST-EMPTY-KIND 가 같은 섹션 규칙
printf '# L\n\n**원형**: 목록\n\n## 상태\n- 데이터 없음: 등록 유도\n- 결과 없음: 필터 초기화\n- 로딩\n- 오류\n\n## 기타\n페이징 총 건수 표시. 기본 정렬 기준 최신순.\n' > "$TD/h2a.md"
o=$(_hq "$TD/h2a.md")
if [ "$(_val "$o" states)" = "3/3" ] && [ "$(_val "$o" genre)" = "3/3" ] && ! printf '%s' "$o" | grep -q 'S-STATES-EMPTY'; then
  ok "H2.a ## 상태 + 데이터 없음/결과 없음 → states=3/3 ∧ genre=3/3 (G-LIST-EMPTY-KIND 와 모순 없음)"; else nope "H2.a" "states=$(_val "$o" states) genre=$(_val "$o" genre)"; fi
printf '# L\n\n**원형**: 기타\n\n## states\n- empty\n- loading\n- error\n' > "$TD/h2b.md"
o=$(_hq "$TD/h2b.md")
if [ "$(_val "$o" states)" = "3/3" ]; then ok "H2.b 소문자 ## states 헤딩 인정"; else nope "H2.b" "states=$(_val "$o" states)"; fi
printf '# L\n\n**원형**: 기타\n\n## 상태\n- 로딩\n- 오류\n' > "$TD/h2c.md"
o=$(_hq "$TD/h2c.md")
if [ "$(_val "$o" states)" = "2/3" ] && printf '%s' "$o" | grep -q '미정의: empty (2/3).*rule=S-STATES-EMPTY'; then
  ok "H2.c 음성 — empty 어휘 없는 ## 상태 는 empty 만 미정의(loading·error 판정 불변)"; else nope "H2.c" "states=$(_val "$o" states)"; fi
printf '# L\n\n**원형**: 목록\n\n## 상태\n- 결과 없음: 필터 초기화\n- 로딩\n- 오류\n\n## 기타\n페이징 총 건수. 기본 정렬 기준 최신순.\n' > "$TD/h2d.md"
o=$(_hq "$TD/h2d.md")
if [ "$(_val "$o" genre)" = "2/3" ] && printf '%s' "$o" | grep -q 'G-LIST-EMPTY-KIND'; then
  ok "H2.d genre 입력도 ## 상태 에서 읽는다 — 한 종류만 있으면 G-LIST-EMPTY-KIND 미충족"; else nope "H2.d" "genre=$(_val "$o" genre)"; fi

# H3: G-ARCHETYPE — 선언 변형 인식(양성) · 미선언·자리표시자·목록 밖·첫 ## 뒤(음성)
_hbad=""
for v in '**원형:** 목록' '원형: 목록' '- **원형**: 목록' '> **원형**: 목록' '**원형** : 목록' '원형：목록'; do
  printf '# A\n\n%s\n\n## States\n- Empty\n- Loading\n- Error\n' "$v" > "$TD/h3a.md"
  o=$(_hq "$TD/h3a.md"); g=$(_val "$o" genre)
  case "$g" in */3) ;; *) _hbad="$_hbad [$v → genre=$g]" ;; esac
done
[ -z "$_hbad" ] && ok "H3.a 원형 선언 변형 6종(**원형:**·원형:·불릿·인용·콜론 앞 공백·전각 콜론) → 목록 규칙 계측" || nope "H3.a" "$_hbad"
_hbad=""
for v in '' '**원형**: [목록]' '**원형**: 달력'; do
  printf '# A\n\n%s\n\n## States\n- Empty\n- Loading\n- Error\n' "$v" > "$TD/h3b.md"
  o=$(_hq "$TD/h3b.md")
  { [ "$(_val "$o" genre)" = "unknown" ] && printf '%s' "$o" | grep -q 'rule=G-ARCHETYPE-UNDECLARED'; } || _hbad="$_hbad [$v]"
done
printf '# A\n\n## States\n- Empty\n- Loading\n- Error\n\n**원형**: 목록\n' > "$TD/h3c.md"
o=$(_hq "$TD/h3c.md")
{ [ "$(_val "$o" genre)" = "unknown" ] && printf '%s' "$o" | grep -q 'rule=G-ARCHETYPE-UNDECLARED'; } || _hbad="$_hbad [첫 ## 뒤]"
[ -z "$_hbad" ] && ok "H3.b 음성 — 미선언·자리표시자·목록 밖 값·첫 ## 뒤 원형 줄은 종전처럼 G-ARCHETYPE-UNDECLARED" || nope "H3.b" "$_hbad"

# H4: 계약 불변 — 어떤 입력에서도 exit 0, 요약줄 키 순서 불변
bash "$SCRIPT" "$TD/h1a.md" "$TD/good.html" >/dev/null 2>&1; r1=$?
bash "$SCRIPT" "$TD/h3c.md" "$TD/good.html" >/dev/null 2>&1; r2=$?
o=$(_hq "$TD/h1a.md")
if [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && printf '%s' "$o" | head -1 | grep -qE "$_kre"; then
  ok "H4 신규 경로에서도 exit 0 · 요약줄 키 순서 불변"; else nope "H4" "rc=$r1/$r2"; fi

# H5: FR-5 영문 empty 어휘 — `no data`·`no results` 각각이 단독으로 empty 를 충족한다(어휘를 지우면 states=2/3)
printf '# L\n\n**원형**: 기타\n\n## States\n- No data\n- Loading\n- Error\n' > "$TD/h5a.md"
o=$(_hq "$TD/h5a.md")
if [ "$(_val "$o" states)" = "3/3" ]; then ok "H5.a '- No data' → empty 인정(states=3/3)"; else nope "H5.a" "states=$(_val "$o" states)"; fi
printf '# L\n\n**원형**: 기타\n\n## States\n- No results\n- Loading\n- Error\n' > "$TD/h5b.md"
o=$(_hq "$TD/h5b.md")
if [ "$(_val "$o" states)" = "3/3" ]; then ok "H5.b '- No results' → empty 인정(states=3/3)"; else nope "H5.b" "states=$(_val "$o" states)"; fi

# ── K: FID 20261004-screen-lint-gaps — 변이 생존 9곳 격추 (되돌려-관찰 · mutation-score.sh 생존 `&&` 사이트) ──
# K1 _readable 의 `&&` — 디렉터리는 -f 가 거짓이라 판독 불가(unknown). `||` 로 바뀌면 -r 만 보고 읽으려 든다.
o=$(bash "$SCRIPT" "$TD" "$TD/good.html" 2>/dev/null)
[ "$(_val "$o" states)" = "unknown" ] && ok "K1 md 자리에 디렉터리 → 판독 불가 states=unknown(-f 와 -r 둘 다 요구)" || nope "K1" "states=$(_val "$o" states)"

# K2 _strip_comments 의 `<!--` 선행 판정 — `/* */` 만 있는 줄에서 주석 앞 텍스트는 남기고 주석 안만 걷는다
#   (앞의 Lorem 1건은 세고 주석 안의 Acme 는 세지 않는다 → anti=1. `<!--` 분기로 오인하면 앞 텍스트까지 잃어 anti=0)
printf '<main><p>Lorem</p> /* Acme */ <p>끝</p></main>\n' > "$TD/k2.html"
o=$(bash "$SCRIPT" "$TD/good.md" "$TD/k2.html" 2>/dev/null)
[ "$(_val "$o" anti)" = "1" ] && ok "K2 본문 속 /* */ — 앞 텍스트(Lorem)는 세고 주석 안(Acme)은 걷는다(anti=1)" || nope "K2" "anti=$(_val "$o" anti)"

# K3·K4 --regress 설정 오류 줄 — SPECOPS_SCREEN_SHRINK_RATIO 판독 불가 고백이 두 조기 종료 경로에서 나온다
#   K3: git 저장소 밖(+ '0x' — 숫자 모양 검사 grep 이 거짓이어야 한다: awk 단독이면 0x 가 통과한다)
_k=$(mktemp -d); o=$(cd "$_k" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && GIT_CEILING_DIRECTORIES="$(dirname "$_k")" SPECOPS_SCREEN_SHRINK_RATIO=0x bash "$SCRIPT" --regress 2>/dev/null)
printf '%s' "$o" | grep -q "\[config\] SPECOPS_SCREEN_SHRINK_RATIO='0x' 판독 불가" && ok "K3 git 밖 --regress + 비정상 비율(0x) → [config] 판독 불가 줄(숫자 모양 검사)" || nope "K3" "$(printf '%s' "$o" | tr '\n' '|')"
#   K4: 저장소는 있으나 screens/ 가 어느 쪽에도 없을 때
( cd "$_k" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git init -q && git symbolic-ref HEAD refs/heads/main && git -c user.email=t@t -c user.name=t -c core.hooksPath= -c commit.gpgsign=false commit -q --allow-empty -m base ) >/dev/null 2>&1
o=$(cd "$_k" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && SPECOPS_SCREEN_SHRINK_RATIO=abc bash "$SCRIPT" --regress 2>/dev/null)
printf '%s' "$o" | grep -q "대상 0개" && printf '%s' "$o" | grep -q "\[config\] SPECOPS_SCREEN_SHRINK_RATIO='abc' 판독 불가" && ok "K4 screens 없는 저장소 --regress + 비정상 비율 → 대상 0개 + [config] 줄" || nope "K4" "$(printf '%s' "$o" | tr '\n' '|')"
rm -rf "$_k"

# K5 G-FORM-SUBMIT — 두 조건(제출 중 · 비활성) 중 하나만으로는 충족이 아니다
printf '# F\n\n**원형**: 폼\n\n## States\n- Empty\n- Loading: 제출 중 표시\n- Error\n\n## 흐름\n취소 버튼으로 이전 화면 복귀\n' > "$TD/k5a.md"
printf '# F\n\n**원형**: 폼\n\n## States\n- Empty\n- Loading: 버튼 비활성\n- Error\n\n## 흐름\n취소 버튼으로 이전 화면 복귀\n' > "$TD/k5b.md"
_kbad=""
for f in k5a k5b; do o=$(bash "$SCRIPT" "$TD/$f.md" "$TD/good.html" 2>/dev/null); printf '%s' "$o" | grep -q 'G-FORM-SUBMIT' || _kbad="$_kbad [$f]"; done
[ -z "$_kbad" ] && ok "K5 G-FORM-SUBMIT — '제출 중' 만 · '비활성' 만 있으면 미충족(둘 다 요구)" || nope "K5" "미보고:$_kbad"

# K6 G-WIZARD-STEP — 세 조건 중 '단계 표시' 가 빠지면 미충족(이전·중간 저장만으로 충족되지 않는다)
printf '# W\n\n**원형**: 다단 폼\n\n## States\n- Empty\n- Loading: 제출 중 버튼 비활성\n- Error\n\n## 흐름\n취소 버튼 · 이전 버튼 · 중간 저장\n' > "$TD/k6.md"
o=$(bash "$SCRIPT" "$TD/k6.md" "$TD/good.html" 2>/dev/null)
printf '%s' "$o" | grep -q 'G-WIZARD-STEP' && ok "K6 G-WIZARD-STEP — 단계 표시 없이 이전·중간 저장만 있으면 미충족" || nope "K6" "$(printf '%s' "$o" | grep genre)"

# K7·K8 정상 화면은 a11y-label·semantic 상세줄이 없다(위반이 있을 때만 출력)
o=$(bash "$SCRIPT" "$TD/good.md" "$TD/good.html" 2>/dev/null)
printf '%s' "$o" | grep -q '\[a11y-label\]' && nope "K7" "정상 화면에 a11y-label 상세줄" || ok "K7 label 1/입력 1 → [a11y-label] 상세줄 없음"
printf '%s' "$o" | grep -q '\[semantic\]' && nope "K8" "정상 화면에 semantic 상세줄" || ok "K8 랜드마크 있음 → [semantic] 상세줄 없음"

# ── N: FID 20261004-screen-lint-gaps-2 — G-* 자연 표현 어휘·위장 문구 (양성·음성 쌍) ──
_nmd() { printf '# X\n\n**원형**: %s\n\n## States\n- Empty%s\n- Loading\n- Error\n\n## 기타\n%s\n' "$1" "$3" "$2"; }
_nrun() { _nmd "$1" "$2" "${3:-}" > "$TD/n.md"; bash "$SCRIPT" "$TD/n.md" "$TD/good.html" 2>/dev/null; }
_nmiss() { printf '%s' "$1" | grep -q "$2 미충족"; }   # 출력에 규칙 미충족 상세줄이 있다
_nlist=': 데이터 없음 · 결과 없음'

# N1: 목록 — 총 N건(총/전체 + 숫자·N + 건) · 정렬 표현
o=$(_nrun 목록 '페이징. 목록 상단에 총 123건 표시. 최신순으로 정렬한다.' "$_nlist")
[ "$(_val "$o" genre)" = "3/3" ] && ok "N1.a 목록 '총 123건'·'최신순으로 정렬한다' → genre=3/3" || nope "N1.a" "genre=$(_val "$o" genre)"
_nbad=""
for w in '전체 50건' '총 N건' '총 7 건'; do o=$(_nrun 목록 "페이징. $w 표시. 정렬 기준 최신순." "$_nlist"); _nmiss "$o" G-LIST-PAGING && _nbad="$_nbad [$w]"; done
for w in 최신순 오래된순 오름차순 내림차순 '으로 정렬'; do o=$(_nrun 목록 "페이징. 총 건수 표시. 목록은 $w 한다." "$_nlist"); _nmiss "$o" G-LIST-SORT && _nbad="$_nbad [$w]"; done
[ -z "$_nbad" ] && ok "N1.b 총 건수 변형 3종·정렬 표현 5종(최신순 포함) 각각 충족" || nope "N1.b" "미충족:$_nbad"
o=$(_nrun 목록 '페이징. 등록된 5건. 정렬 기준 최신순.' "$_nlist")
_nmiss "$o" G-LIST-PAGING && ok "N1.c 음성 — '등록된 5건'(총/전체 없음)·'건수' 단독은 총 건수가 아니다" || nope "N1.c" "$(printf '%s' "$o" | grep -c G-LIST-PAGING)"

# N2: 폼 — 진행 중 표현·닫기·뒤로 (영문 close 단어 경계)
_nbad=""
for w in '로그인 중' '처리 중' '요청 중' '전송 중' '등록 중' '가입 중' '처리 중일 때' '로그인 중인' '요청 중이면' '전송 중으로' '등록 중(예약)'; do o=$(_nrun 폼 '취소 버튼.' ": 버튼 비활성 + $w"); _nmiss "$o" G-FORM-SUBMIT && _nbad="$_nbad [$w]"; done
for w in '닫기 버튼' '닫기 링크' '돌아가기 버튼' '뒤로 버튼' 'close 버튼' 'close버튼'; do o=$(_nrun 폼 "$w." ': 제출 중 버튼 비활성'); _nmiss "$o" G-FORM-CANCEL && _nbad="$_nbad [$w]"; done
[ -z "$_nbad" ] && ok "N2.a 폼 진행 중 표현 11종(중일 때·중인·중이면·중으로·중( 후행 포함)·취소 경로 6종(닫기 버튼·닫기 링크·돌아가기·뒤로·close·close버튼 붙여쓰기) 각각 충족" || nope "N2.a" "미충족:$_nbad"
_nbad=""
o=$(_nrun 폼 '취소 버튼.' ': 로그인 중 표시'); _nmiss "$o" G-FORM-SUBMIT || _nbad="$_nbad [중만→충족]"
o=$(_nrun 폼 'prevent double submit. disclose info. background.' ': 제출 중 버튼 비활성'); _nmiss "$o" G-FORM-CANCEL || _nbad="$_nbad [prevent·disclose·background→충족]"
o=$(_nrun 폼 '키보드: Esc 로 모달 닫기.' ': 제출 중 버튼 비활성'); _nmiss "$o" G-FORM-CANCEL || _nbad="$_nbad [모달 닫기 단독→충족]"
o=$(_nrun 폼 '취소 버튼.' ': 요청 중복 방지 · 가입 중복 확인 후 버튼 비활성'); _nmiss "$o" G-FORM-SUBMIT || _nbad="$_nbad [요청 중복·가입 중복→충족]"
for w in '전송 중단' '등록 중지' '처리 중간' '처리 중요 항목'; do o=$(_nrun 폼 '취소 버튼.' ": $w 시 버튼 비활성"); _nmiss "$o" G-FORM-SUBMIT || _nbad="$_nbad [${w}→충족]"; done
for w in '로그인 중입니다' '처리중...' '요청 중에도' '가입 중'; do o=$(_nrun 폼 '취소 버튼.' ": $w 버튼 비활성"); _nmiss "$o" G-FORM-SUBMIT && _nbad="$_nbad [${w}→미충족]"; done
[ -z "$_nbad" ] && ok "N2.b 음성 — '중' 표현만(비활성 없음)은 미충족 · '요청 중복'·'가입 중복'·'전송 중단'·'등록 중지'·'처리 중간'·'처리 중요 항목' 은 진행 중이 아니고 '로그인 중입니다'·'처리중...'·'요청 중에도' 는 진행 중이다 · prevent/disclose/background·템플릿 '모달 닫기' 단독은 취소 경로가 아니다" || nope "N2.b" "$_nbad"

# N3: 다단 폼 — stepper·이전 단계·임시저장 · 위장 문구 제거
_nbad=""
for st in 'stepper' '스테퍼' '진행 표시'; do o=$(_nrun '다단 폼' "$st 로 현재 위치를 안내한다. 이전 단계 버튼. 중간 저장. 닫기." ': 제출 중 비활성'); _nmiss "$o" G-WIZARD-STEP && _nbad="$_nbad [단계:$st]"; done
for pv in '이전 단계' '이전 버튼' '이전으로' 'previous' 'prev' 'prev버튼'; do o=$(_nrun '다단 폼' "단계 표시. $pv 이동. 중간 저장. 닫기." ': 제출 중 비활성'); _nmiss "$o" G-WIZARD-STEP && _nbad="$_nbad [이전:$pv]"; done
for sv in '임시저장' '임시 저장' '자동 저장' 'autosave'; do o=$(_nrun '다단 폼' "단계 표시. 이전 단계. $sv 지원. 닫기." ': 제출 중 비활성'); _nmiss "$o" G-WIZARD-STEP && _nbad="$_nbad [저장:$sv]"; done
o=$(_nrun '다단 폼' 'stepper로 위치 안내. 이전 단계 버튼. 중간 저장. 닫기.' ': 제출 중 비활성'); _nmiss "$o" G-WIZARD-STEP && _nbad="$_nbad [단계:stepper로 붙여쓰기]"
[ -z "$_nbad" ] && ok "N3.a 다단 폼 단계 표시 3종(+stepper로 붙여쓰기)·이전 6종(+prev버튼)·중간 저장 4종 각각 충족" || nope "N3.a" "미충족:$_nbad"
_nbad=""
o=$(_nrun '다단 폼' '단계 표시. [이전 화면으로] 링크. 중간 저장. 취소.' ': 제출 중 비활성'); _nmiss "$o" G-WIZARD-STEP || _nbad="$_nbad [이전 화면으로 위장→충족]"
o=$(_nrun '다단 폼' '단계 표시. prevent 중복. 중간 저장. 취소.' ': 제출 중 비활성'); _nmiss "$o" G-WIZARD-STEP || _nbad="$_nbad [prevent→충족]"
o=$(_nrun '다단 폼' 'stepperx 로 위치 안내. 이전 단계. 중간 저장. 취소.' ': 제출 중 비활성'); _nmiss "$o" G-WIZARD-STEP || _nbad="$_nbad [stepperx→충족]"
o=$(_nrun '다단 폼' '단계 표시. 이전 단계. autosavex 지원. 취소.' ': 제출 중 비활성'); _nmiss "$o" G-WIZARD-STEP || _nbad="$_nbad [autosavex→충족]"
[ -z "$_nbad" ] && ok "N3.b 음성 — 템플릿 '[이전 화면으로]'·prevent·stepperx·autosavex 는 단계 표시·이전 단계·중간 저장이 아니다(위장·부분 일치 제거)" || nope "N3.b" "$_nbad"

# N4: 대시보드 — 기간 표현
_nbad=""
for w in '조회 기간(최근 7일)' '기간 설정(최근 7일)' '기간을 선택한다' '기간을 설정한다'; do o=$(_nrun 대시보드 "$w"); _nmiss "$o" G-DASH-PERIOD && _nbad="$_nbad [$w]"; done
[ -z "$_nbad" ] && ok "N4.a 대시보드 기간 표현 4종 각각 충족" || nope "N4.a" "미충족:$_nbad"
o=$(_nrun 대시보드 '쿠폰 만료 기간이 지나면 숨긴다.'); _nmiss "$o" G-DASH-PERIOD && ok "N4.b 음성 — 무관한 '기간'(만료 기간) 은 기간 선택이 아니다" || nope "N4.b" "$(printf '%s' "$o" | grep genre | head -n 1)"

# ── P: FID 20261004-screen-lint-gaps-2 — S-A11Y-LABEL 태그 단위 계측 (aria·버튼형·hidden 변형·경계·정규화) ──
_ph() { printf '%s' "$1" > "$TD/p.html"; bash "$SCRIPT" "$TD/good.md" "$TD/p.html" 2>/dev/null; }
_pa() { _val "$(_ph "$1")" a11y-label; }
_pbad=""
[ "$(_pa '<main><input aria-label="이메일"></main>')" = "1/1" ] || _pbad="$_pbad [aria-label]"
[ "$(_pa '<main><span id=t>이름</span><input aria-labelledby="t"></main>')" = "1/1" ] || _pbad="$_pbad [aria-labelledby]"
[ "$(_pa "$(printf '<main><INPUT\tTYPE=text\tARIA-LABEL="x"></main>')")" = "1/1" ] || _pbad="$_pbad [대문자·탭 aria]"
[ -z "$_pbad" ] && ok "P1 aria-label·aria-labelledby 입력(대문자·탭 변형 포함)은 접근 가능한 이름 있음 → 1/1" || nope "P1" "$_pbad"
_pbad=""
[ "$(_pa '<main><input type=submit><input type=button><input type=reset><input type=image></main>')" = "0/0" ] || _pbad="$_pbad [버튼형]"
[ "$(_pa '<main><input type=HIDDEN name=c></main>')" = "0/0" ] || _pbad="$_pbad [HIDDEN]"
[ "$(_pa '<main><input type = "hidden" name=c></main>')" = "0/0" ] || _pbad="$_pbad [type = hidden]"
[ "$(_pa "$(printf '<main><input\n type="hidden" name=c></main>\n')")" = "0/0" ] || _pbad="$_pbad [여러 줄 hidden]"
[ "$(_pa "$(printf '<main><input\r\n\ttype="hidden" name=c></main>\r\n')")" = "0/0" ] || _pbad="$_pbad [CRLF·탭 hidden]"
[ -z "$_pbad" ] && ok "P2 버튼형 4종·hidden 변형(대문자·공백·여러 줄·CRLF·탭)은 입력 집계에서 제외 → 0/0" || nope "P2" "$_pbad"
_pbad=""
[ "$(_pa '<main><input-group></input-group><select-box></select-box></main>')" = "0/0" ] || _pbad="$_pbad [커스텀 엘리먼트]"
[ "$(_pa '<main><!-- <input> --><p>x</p></main>')" = "0/0" ] || _pbad="$_pbad [주석]"
[ "$(_pa '<main><script>var s="<input>";</script></main>')" = "0/0" ] || _pbad="$_pbad [script 문자열]"
[ -z "$_pbad" ] && ok "P3 커스텀 엘리먼트(<input-group>)·주석·<script> 문자열 속 <input> 은 입력이 아니다 → 0/0" || nope "P3" "$_pbad"
o=$(_ph '<main><input type=text><input type=password><select></select><input type=hidden><input type=submit><!-- <input> --></main>')
if [ "$(_val "$o" a11y-label)" = "0/3" ] && printf '%s' "$o" | grep -q '\[a11y-label\] 입력 3개 중 label 0개 — 3개 누락  rule=S-A11Y-LABEL'; then
  ok "P4 음성 — 이름 없는 일반 입력 3개는 종전 문구·형식 그대로 누락 보고(버튼형·hidden·주석은 제외)"; else nope "P4" "a11y=$(_val "$o" a11y-label)"; fi
[ "$(_pa '<main><input data-type=button id=a><input data-aria-label=x id=b></main>')" = "0/2" ] && [ "$(_pa '<main><!-- <label>x</label> --><label-x>y</label-x><input></main>')" = "0/1" ] && ok "P7 data-type=button·data-aria-label 은 type·aria 속성이 아니다(입력으로 센다, 구 스크립트가 잡던 누락 유지) · 주석 속 <label>·<label-x> 는 label 이 아니다" || nope "P7" "$(_pa '<main><input data-type=button id=a><input data-aria-label=x id=b></main>') $(_pa '<main><!-- <label>x</label> --><label-x>y</label-x><input></main>')"
[ "$(_pa '<main><input/><textarea></textarea></main>')" = "0/2" ] && ok "P5 자기 닫힘 <input/>·<textarea> 는 입력으로 센다 → 0/2" || nope "P5" "$(_pa '<main><input/><textarea></textarea></main>')"
[ "$(_pa '<LABEL for=a>A</LABEL><input id=a>')" = "1/1" ] && ok "P8 대문자 <LABEL> 도 label 로 센다(-i 잠금) → 1/1" || nope "P8" "$(_pa '<LABEL for=a>A</LABEL><input id=a>')"
[ "$(_pa "$(printf '<main><label for=a>A</label>\r\n<input\r\n id=a></main>\r\n')")" = "1/1" ] && ok "P6 CRLF 여러 줄 label+input 정상 화면 → 1/1(상세줄 없음 — 오탐 없음)" || nope "P6" "$(_pa "$(printf '<main><label for=a>A</label>\r\n<input\r\n id=a></main>\r\n')")"

# ── N1.d·L: FID 20261004-screen-lint-gaps-3 — 총 건수 천 단위 쉼표 · 영문 어휘 경계 로케일 매트릭스 ──
_loc_utf8=$(_lx=$(locale -a 2>/dev/null || true); printf '%s\n' "$_lx" | grep -iE -m1 '^(en_US|C)\.utf-?8$' || true)
# N1.d: 총 건수 천 단위 쉼표
o1=$(_nrun 목록 '페이징. 목록 상단에 총 1,234건 표시. 정렬 기준 최신순.' "$_nlist"); o2=$(_nrun 목록 '페이징. 전체 12,345건 표시. 정렬 기준 최신순.' "$_nlist")
if _nmiss "$o1" G-LIST-PAGING || _nmiss "$o2" G-LIST-PAGING; then nope "N1.d" "쉼표 건수가 미충족으로 읽힘"; else ok "N1.d 총 건수 천 단위 쉼표('총 1,234건'·'전체 12,345건') 충족"; fi
o1=$(_nrun 목록 '페이징. 총 ,,, 건 표시. 정렬 기준 최신순.' "$_nlist"); o2=$(_nrun 목록 '페이징. 총 , 건 표시. 정렬 기준 최신순.' "$_nlist")
if _nmiss "$o1" G-LIST-PAGING; then if _nmiss "$o2" G-LIST-PAGING; then ok "N1.e 음성 — 숫자·N 없이 쉼표만('총 ,,, 건'·'총 , 건')은 총 건수가 아니다"; else nope "N1.e" "'총 , 건' 이 충족으로 읽힘"; fi; else nope "N1.e" "'총 ,,, 건' 이 충족으로 읽힘"; fi

# L: 로케일 매트릭스 — 영문 어휘 단어 경계(ASCII 경계 클래스)는 LC_ALL=C 와 UTF-8 에서 같은 결과여야 한다
_lbad=""; _llocs="C"; [ -n "$_loc_utf8" ] && _llocs="C $_loc_utf8"
for _l in $_llocs; do
  o=$(LC_ALL=$_l _nrun '다단 폼' 'stepper로 위치 안내. 이전 단계 버튼. 중간 저장. 닫기.' ': 제출 중 비활성'); _nmiss "$o" G-WIZARD-STEP && _lbad="$_lbad [$_l:stepper로]"
  o=$(LC_ALL=$_l _nrun '다단 폼' '단계 표시. prev버튼. 중간 저장. 취소.' ': 제출 중 비활성'); _nmiss "$o" G-WIZARD-STEP && _lbad="$_lbad [$_l:prev버튼]"
  o=$(LC_ALL=$_l _nrun '폼' '제출 중 비활성. close버튼.' ''); _nmiss "$o" G-FORM-CANCEL && _lbad="$_lbad [$_l:close버튼]"
  o=$(LC_ALL=$_l _nrun '다단 폼' '단계 표시. prevent 중복. 중간 저장. 취소.' ': 제출 중 비활성'); _nmiss "$o" G-WIZARD-STEP || _lbad="$_lbad [$_l:prevent]"
  o=$(LC_ALL=$_l _nrun '다단 폼' 'stepperx 로 위치 안내. 이전 단계. 중간 저장. 취소.' ': 제출 중 비활성'); _nmiss "$o" G-WIZARD-STEP || _lbad="$_lbad [$_l:stepperx]"
  o=$(LC_ALL=$_l _nrun '폼' '제출 중 비활성. disclose 안내.' ''); _nmiss "$o" G-FORM-CANCEL || _lbad="$_lbad [$_l:disclose]"
done
if [ -z "$_lbad" ]; then
  if [ -n "$_loc_utf8" ]; then ok "L1 영문 어휘 경계 6종(양성 stepper로·prev버튼·close버튼 / 음성 prevent·stepperx·disclose)이 LC_ALL=C·$_loc_utf8 양쪽에서 같은 결과"
  else ok "L1 (UTF-8 로케일 없음 — C 만 실행, UTF-8 단언 건너뜀) 영문 어휘 경계 6종 LC_ALL=C 결과 일치"; fi
else nope "L1" "$_lbad"; fi

# ── Q: FID 20261004-screen-lint-gaps-3 — S-A11Y-LABEL 이름 있는 입력 수(aria · label for↔id 짝 · label 감쌈) ──
_qchk() {  # $1=html $2=기대 값 → 일치하면 0 (실패 시 _qbad 에 사유 누적)
  [ "$(_pa "$1")" = "$2" ] || _qbad="$_qbad [$2≠$(_pa "$1")]"
}
_qbad=""
_qchk '<main><label for=a>A</label><input id=a></main>' "1/1"
_qchk '<main><label>A <input></label></main>' "1/1"
_qchk '<main><input id=a><label for=a>A</label></main>' "1/1"
_qchk '<main><label for=s>S</label><select id=s></select><label for=t>T</label><textarea id=t></textarea></main>' "2/2"
_qchk '<main><label for=a>A</label><input id=a aria-label=x><input id=b></main>' "1/2"
_qchk '<main><label>A <input><input></label></main>' "1/2"
_qchk '<main><label>A <input aria-label=q><input></label></main>' "1/2"
_qchk '<main><label for=a><input id=a></label></main>' "1/1"
_qchk '<main><label>S <select></select></label><label>T <textarea></textarea></label></main>' "2/2"
_qchk '<main><label for=a>A</label><input id=a><label>B <input></label></main>' "2/2"
[ -z "$_qbad" ] && ok "Q1 이름 인정 — for/id 짝(앞·뒤 순서)·label 감쌈(select·textarea 포함)·select/textarea 짝·aria 겹침(이름 없는 입력 1개는 누락 유지)·감싼 label 의 둘째 입력은 이름 아님·label 사이 for 상태 비누수" || nope "Q1" "$_qbad"
_qbad=""
_qchk '<main><label for=a>A</label><input id=b></main>' "0/1"
_qchk '<main><label for=a>A</label><input></main>' "0/1"
_qchk '<main><label for=a>A</label><input id=a><input id=b><label for=zz>Z</label></main>' "1/2"
_qchk '<main><label for=a>A</label><label for=a>B</label><input id=a><input id=b></main>' "1/2"
_qchk '<main><label>이름</label><input></main>' "0/1"
_qchk '<main><label for=x><input id=y></label></main>' "0/1"
_qchk '<main><label for=h>H</label><input type=hidden id=h><input></main>' "0/1"
_qchk '<main><fieldset><legend>성별</legend><input type=radio name=g id=r1><input type=radio name=g id=r2></fieldset></main>' "0/2"
_qchk '<main><label for=a>A</label></main>' "0/0"
_qchk '<main><label for=a type=button>A</label><input id=a></main>' "1/1"
_qchk '<main><label for=a>A</label><input data-id=a></main>' "0/1"
[ -z "$_qbad" ] && ok "Q2 음성 — for/id 불일치·for 대상 없음·짝 없는 label 상쇄·중복 for·sibling label·for 우선(감싼 id 다름)·숨김 입력 짝·legend 만·입력 없는 label(0/0)은 이름 없음, label 태그의 type 속성은 입력 제외 필터에 걸리지 않는다(1/1)·data-id 접두 속성은 id 가 아니다" || nope "Q2" "$_qbad"
o=$(_ph '<main><label for=a>A</label><input id=a><input id=b><label for=zz>Z</label></main>')
printf '%s' "$o" | grep -q '\[a11y-label\] 입력 2개 중 label 1개 — 1개 누락  rule=S-A11Y-LABEL' && ok "Q2.b orphan label 이 상쇄하던 누락이 종전 문구·형식 그대로 보고된다" || nope "Q2.b" "$(printf '%s' "$o" | grep a11y | head -n 1)"

# Q3: 속성 파싱 변형 — 로케일 두 개로 같은 값이어야 한다(_loc_utf8 은 위 L 블록 앞에서 정의)
_qloc() {  # $1=html $2=기대 → LC_ALL=C·UTF-8 양쪽에서 같은 기대 값
  _qlocs="C"; [ -n "$_loc_utf8" ] && _qlocs="C $_loc_utf8"
  for _l in $_qlocs; do [ "$(LC_ALL=$_l _pa "$1")" = "$2" ] || _qbad="$_qbad [$_l:$2≠$(LC_ALL=$_l _pa "$1")]"; done
}
_qbad=""
_qloc '<main><LABEL FOR=A>A</LABEL><INPUT ID=A></main>' "1/1"
_qloc "$(printf '<main><label for=a>A</label>\r\n<input\r\n id=a></main>\r\n')" "1/1"
_qloc "$(printf '<main><label\tfor=a>A</label><input\ttype=text\tid=a></main>')" "1/1"
_qloc "$(printf '<main><label for=a\r\n>A</label><input\r\n id=a\r\n></main>\r\n')" "1/1"
_qloc "$(printf '<main><label for=a\r\n>A</label><input id=a></main>\r\n')" "1/1"
_qloc "$(printf '<main><label\nfor="a">A</label>\n<input\nid=\x27a\x27></main>\n')" "1/1"
_qloc '<main><label for = "a">A</label><input id = a/></main>' "1/1"
_qloc '<main><label for=이름>이름</label><input id=이름></main>' "1/1"
_qloc '<main><label for=A>A</label><input id=a></main>' "0/1"
_qloc '<main><label for="">A</label><input id=""></main>' "0/1"
[ -z "$_qbad" ] && ok "Q3 속성명 대소문자·따옴표 3종·공백·CRLF(값 뒤 줄바꿈 포함)·탭·여러 줄·자기 닫힘·한글 id 는 같은 짝(1/1), 값 대소문자 불일치·빈 값은 짝 아님(0/1) — LC_ALL=C·UTF-8 양쪽 동일" || nope "Q3" "$_qbad"

# ── S: FID 20261011-script-pipe-grep — States 판정이 절 크기와 무관하다 ──
#   왜: 계측기는 `set -uo pipefail` 이다. States 의 세 판정이 `printf "$sec" | grep -qiE` 였을 때, grep 이 첫 일치에서
#   끝나면 printf 가 SIGPIPE 로 죽어 충족이 미충족으로 읽혔다 — 절이 파이프 버퍼(64KB)를 넘으면 매번 states=0/3.
#   지금은 같은 파일의 _has(here-string)로 읽는다. 절은 파일로 읽히므로 exec 인자 한도와 무관하다.
_sbig() {  # <줄 본문> → 그 줄을 3000번 되풀이한 States 절을 가진 화면 문서
  printf '# L\n\n**원형**: 기타\n\n## States\n'
  awk -v s="$1" 'BEGIN { for (i = 1; i <= 3000; i++) printf "- %s %04d\n", s, i }'
}
_sbig 'empty 데이터 없음 · loading 로딩 · error 오류' > "$TD/s1a.md"
_ssz=$(wc -c < "$TD/s1a.md" | tr -d ' ')
_sbad=""
for _si in 1 2 3; do
  o=$(_hq "$TD/s1a.md"); [ "$(_val "$o" states)" = "3/3" ] || _sbad="$_sbad $(_val "$o" states)"
done
if [ -z "$_sbad" ] && [ "$_ssz" -gt 65536 ]; then
  ok "S1.a 큰 States 절(${_ssz}바이트) — 세 상태가 다 있으면 states=3/3 (3회 반복)"; else nope "S1.a" "크기=${_ssz} · 3/3 이 아닌 값:$_sbad"; fi
_sbig 'loading 로딩 · error 오류' > "$TD/s1b.md"
o=$(_hq "$TD/s1b.md")
if [ "$(_val "$o" states)" = "2/3" ] && printf '%s' "$o" | grep -q '미정의: empty (2/3)'; then
  ok "S1.b 큰 States 절에서 empty 만 없으면 empty 만 미정의(2/3) — 크기가 판정을 바꾸지 않는다"; else nope "S1.b" "states=$(_val "$o" states)"; fi

finish
