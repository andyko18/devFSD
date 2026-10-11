#!/usr/bin/env bash
# DESIGN.md 템플릿·소비측 배선 계약 + 외부 디자인 플러그인 재유입 금지 — FID 20260928-uiux-promax-removal-design-master
#   이관 원본: test-uiux-assets.sh(삭제). 그 스위트에 promax 무관 가드가 섞여 있어 통째 삭제하면 조용히 사라졌다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# 상속된 GIT_* 가 N 절의 git grep·ls-files 를 다른 repo/빈 인덱스로 돌려 위반이 45/0 으로 위장됐다(Phase C 2회차 ④a~④d 실측) — doc-lock 선례(a24e039)와 동형
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
PASS=0; FAIL=0
ok()   { echo "PASS $1"; PASS=$((PASS+1)); }
nope() { echo "FAIL $1 — $2"; FAIL=$((FAIL+1)); }

# ── Task 2: DESIGN.md 템플릿 확장 ──
_T="$PLUGIN/templates/DESIGN.md"

# U9 — 신설 섹션 (AC-9)
for sec in "Motion" "레이아웃 패턴" "상태 표현"; do
  grep -q "^## .*${sec}" "$_T" && ok "U9.$sec 섹션 존재 (AC-9)" || nope "U9.$sec" "템플릿에 없음"
done

# U10 — 신규 토큰 행 (A안 추가분)
for lbl in Accent Muted Ring "Card Foreground" "On Primary" "On Destructive"; do
  grep -q "^| ${lbl} |" "$_T" && ok "U10.$lbl 토큰 행 존재" || nope "U10.$lbl" "행 없음"
done

# U11 — ★ 기존 9라벨 보존 (AC-10 근거 — _inject_design_palette 가 grep 하는 것)
#   하나라도 사라지면 screens/*.html 색 주입이 **무음으로** 죽는다(lib.sh 의 continue).
for lbl in Primary Secondary Background Surface "Text Primary" "Text Secondary" Border Error Success; do
  grep -q "^| ${lbl} |" "$_T" && ok "U11.$lbl 기존 라벨 보존" || nope "U11.$lbl" "라벨 소실 — 화면 주입이 죽는다"
done

# U11b — Success 는 템플릿에서 값을 발명하지 않는다 — 자리표시자로 두고 Phase 6 이 방향 팔레트로 채운다
grep -qE '^\| Success \| `#______`' "$_T" \
  && ok "U11b 템플릿 Success 자리표시자 (값 발명 없음)" || nope "U11b" "Success 에 임의 값 또는 형식 불일치"

# ── U24: 패턴 라이브러리 확장 (FID 20260821-design-pattern-library) ──
# §6.1 화면 원형 (AC-1)
grep -q '^## 6\.1 ' "$_T" && ok "U24.a §6.1 화면 원형 섹션 존재 (AC-1)" \
  || nope "U24.a" "## 6.1 섹션 없음"
_arch_miss=""
for a in 목록 상세 폼 대시보드; do
  grep -q "^| ${a} |" "$_T" || _arch_miss="$_arch_miss $a"
done
[ -z "$_arch_miss" ] && ok "U24.b 4원형 행 존재 (AC-1)" || nope "U24.b" "누락:$_arch_miss"

# §7 구간 한정 placeholder 0 (AC-2) — ★ 전역 스캔 금지: §8 의 [원칙 N]·[금지 패턴 N] 은 보존 대상(AC-R-1)
#   한계: §7 산문에 '[인라인 편집]' 처럼 세 단어로 **시작하는** 대괄호를 쓰면 오탐한다.
#   placeholder 재유입 차단이 목적이라 fail-safe 방향으로 남긴다 — 정당한 FAIL 로 오독 말 것.
_s7=$(awk '/^## 7\. /{f=1;next} /^## /{f=0} f' "$_T")
_s7ph=$(printf '%s\n' "$_s7" | grep -cE '\[(스켈레톤|일러스트|인라인)[^]]*\]' || true)
_s7hit=$(printf '%s\n' "$_s7" | grep -E '\[(스켈레톤|일러스트|인라인)[^]]*\]' | head -1)
[ "${_s7ph:-99}" -eq 0 ] && ok "U24.c §7 placeholder 0 (AC-2)" || nope "U24.c" "잔존 ${_s7ph}건 — 예: ${_s7hit}"
printf '%s\n' "$_s7" | grep -q '값 채움은' \
  && nope "U24.d" "'값 채움은 후속 FID' 유도 주석 잔존 (AC-2)" \
  || ok "U24.d §7 유도 주석 삭제 (AC-2)"
_row_miss=""
for r in 로딩 "빈 상태" 에러; do
  printf '%s\n' "$_s7" | grep -q "^| ${r} |" || _row_miss="$_row_miss [$r]"
done
[ -z "$_row_miss" ] && ok "U24.e §7 3행 보존 (AC-2)" || nope "U24.e" "누락:$_row_miss"
printf '%s\n' "$_s7" | grep -E '^\| 빈 상태 \|' | grep -q '근거' \
  && ok "U24.f 빈 상태 행이 근거를 밝힌다 (AC-5)" || nope "U24.f" "빈 상태 비고에 근거 명시 없음"

# 회귀 — 기존 9섹션 제목 포함 검사 (AC-R-3) ★ 개수 검사 금지 — §6.1 추가로 10이 된다
_sec_miss=""
while IFS= read -r sec; do
  grep -qF -e "$sec" "$_T" || _sec_miss="$_sec_miss [$sec]"
done <<'SECS'
## 1. Color System
## 2. Typography
## 3. Spacing & Layout
## 4. Components
## 5. Motion
## 6. 레이아웃 패턴
## 7. 상태 표현
## 8. Design Principles
## 9. AI Usage Guidelines
SECS
[ -z "$_sec_miss" ] && ok "U24.h 기존 섹션 제목 보존 (AC-R-3)" || nope "U24.h" "소실:$_sec_miss"

# 배선 리터럴 4파일 (AC-1·AC-4·AC-5·AC-10 + 20260829-design-consume-sync AC-1)
# start-all.md 는 Phase 2.5-A 가 [공통] 블록을 상속하지 않아 별도 기재가 필요하다
#   (실측 20260829: specifying-ko 만 §2·§3 보유 → batch 화면만 새 축을 몰랐다)
for f in skills/specifying-ko/SKILL.md commands/design-screen.md commands/design-screens.md commands/start-all.md; do
  _wire_n=$(grep -cF '**DESIGN.md 준수**' "$PLUGIN/$f" 2>/dev/null || true)
  _line=$(grep -F '**DESIGN.md 준수**' "$PLUGIN/$f" 2>/dev/null | head -1)
  if [ "${_wire_n:-0}" -eq 1 ] \
     && printf '%s' "$_line" | grep -q '§2 ' \
     && printf '%s' "$_line" | grep -q '§3 ' \
     && printf '%s' "$_line" | grep -q '§6 ' \
     && printf '%s' "$_line" | grep -q '§6\.1' \
     && printf '%s' "$_line" | grep -q '§7' \
     && printf '%s' "$_line" | grep -q '§8' \
     && printf '%s' "$_line" | grep -q '§9'; then
    ok "U24.i.$(basename "$f") 배선 1줄 + §2·§3·§6~§9 (AC-10)"
  else
    nope "U24.i.$(basename "$f")" "매칭 ${_wire_n:-0}건 / 섹션 참조 불충족"
  fi
done

# U24.k — 배선줄 § 토큰 집합의 canonical 대칭 (Phase C Important-1, 20260829)
#   U24.i 는 '알려진 7토큰의 존재'만 본다 → canonical 에 새 축(§4 등)이 늘어도 나머지 3파일은 무음 통과했다
#   (리뷰어 프로브 P1 실증 20260829: specifying-ko 에만 §4 추가 → 4파일 전부 PASS).
#   여기서는 존재가 아니라 **집합 동일성**을 잠근다 — 축이 늘든 줄든 4파일이 같이 움직여야 한다.
#   줄 전체에서 추출한다: start-all 배선줄 꼬리의 batch 부연에는 § 토큰이 0건이다(실측 20260829).
#   미래에 부연이 §를 달면 여기서 **보이는 FAIL** 이 난다 — 무음 드리프트보다 낫다(§2 앵커와 같은 tripwire 입장).
_canon_f="skills/specifying-ko/SKILL.md"
_sect_of() {
  grep -F '**DESIGN.md 준수**' "$PLUGIN/$1" 2>/dev/null | head -1 \
    | grep -oE '§[0-9]+(\.[0-9]+)?' | LC_ALL=C sort -u | tr '\n' ' '
}
_canon=$(_sect_of "$_canon_f")
if [ -z "$_canon" ]; then
  # 추출이 깨지면 빈 집합끼리 같아져 U24.k 가 공허하게 PASS 한다 — 그건 두 번째 스냅샷 잠금일 뿐이다
  nope "U24.k" "canonical($_canon_f) 배선줄에서 § 토큰 0건 — 추출/배선이 깨졌다"
else
  _sym_bad=""
  for f in commands/design-screen.md commands/design-screens.md commands/start-all.md; do
    _o=$(_sect_of "$f")
    [ "$_o" = "$_canon" ] && continue
    _miss=""; _extra=""
    for t in $_canon; do
      case " $_o " in *" $t "*) ;; *) _miss="$_miss$t " ;; esac
    done
    for t in $_o; do
      case " $_canon " in *" $t "*) ;; *) _extra="$_extra$t " ;; esac
    done
    _sym_bad="$_sym_bad$(basename "$f") 누락[${_miss% }] 잉여[${_extra% }]; "
  done
  if [ -z "$_sym_bad" ]; then
    ok "U24.k 배선줄 § 토큰 집합 4파일 대칭 [${_canon% }] (AC-10)"
  else
    nope "U24.k" "canonical[${_canon% }] 과 비대칭 — ${_sym_bad%; }"
  fi
fi

# U24.l — 생성 4경로 `**입력 접근성**` 한 줄 (FID 20261005-screen-label-guidance AC-3)
#   기존 `**DESIGN.md 준수**` 배선줄(U24.i·U24.k)은 건드리지 않고 별도 줄을 4경로에 같이 둔다 — 한 줄이 사라지거나 한 파일만 문구가 달라지면 FAIL.
#   줄은 파일마다 정확히 1건이고 앞 공백을 뗀 전문이 specifying-ko 의 canonical 과 같으며, 핵심 토큰 6개를 모두 가진다.
_ia_toks='for 속성| id |감싸|aria-label|fieldset|legend'
_ia_ok() {  # <줄 전문> → 핵심 토큰 6개가 모두 있으면 0
  local l="$1" t; local IFS='|'
  for t in $_ia_toks; do case "$l" in *"$t"*) ;; *) return 1 ;; esac; done
  return 0
}
_ia_line() { grep -F '**입력 접근성**' "$PLUGIN/$1" 2>/dev/null | sed 's/^[[:space:]]*//'; }
_ia_n() { grep -cF '**입력 접근성**' "$PLUGIN/$1" 2>/dev/null || true; }
_ia_canon=$(_ia_line skills/specifying-ko/SKILL.md)
_ia_bad=""
for f in skills/specifying-ko/SKILL.md commands/design-screen.md commands/design-screens.md commands/start-all.md; do
  if [ "$(_ia_n "$f")" != "1" ]; then _ia_bad="$_ia_bad $(basename "$f")(건수 $(_ia_n "$f"))"; continue; fi
  _l=$(_ia_line "$f")
  _ia_ok "$_l" || _ia_bad="$_ia_bad $(basename "$f")(토큰 누락)"
  [ "$_l" = "$_ia_canon" ] || _ia_bad="$_ia_bad $(basename "$f")(canonical 불일치)"
done
if [ -z "$_ia_canon" ]; then nope "U24.l" "specifying-ko 에 **입력 접근성** 줄이 없다(canonical 부재)"
elif [ -n "$_ia_bad" ]; then nope "U24.l" "canonical='${_ia_canon:0:30}…' 위반:$_ia_bad"
else ok "U24.l 생성 4경로 **입력 접근성** 1줄 — 핵심 토큰 6개·전문 대칭 (AC-3)"; fi
# U24.l.neg — 판정기가 공허하지 않다: 토큰 하나를 지우거나 문구가 달라진 줄은 거부한다
if ! _ia_ok "$(printf '%s' "$_ia_canon" | sed 's/legend/lg/')" && ! _ia_ok "$(printf '%s' "$_ia_canon" | sed 's/aria-label/aria/')" && ! _ia_ok ""; then ok "U24.l.neg 토큰 하나라도 빠진 줄·빈 줄은 판정기가 거부한다"; else nope "U24.l.neg" "판정기가 결손 줄을 통과시킨다"; fi

# start-all **Phase 2.5-A 구간 안**이 화면 템플릿을 참조하는가 (AC-2)
#   전체 파일 grep 은 위치를 안 잠근다 — 참조를 파일 끝으로 옮겨도 통과했다(프로브 P3 실증 20260829).
#   AC-2 는 "화면 산출물 생성 문맥 안"을 요구하므로 A~B 구간으로 잘라 본다.
#   구간 경계가 사라지면 awk 범위가 EOF 까지 흘러 위치 잠금이 되살아난다 → 경계 존재를 먼저 단언한다.
_sa="$PLUGIN/commands/start-all.md"
_bnd_a=$(grep -cE '^#### A\.' "$_sa" 2>/dev/null || true)
_bnd_b=$(grep -cE '^#### B\.' "$_sa" 2>/dev/null || true)
if [ "${_bnd_a:-0}" -ne 1 ] || [ "${_bnd_b:-0}" -ne 1 ]; then
  nope "U24.j" "Phase 2.5 구간 경계 소실 (#### A.=${_bnd_a:-0} / #### B.=${_bnd_b:-0}, 각 1건 기대) — 구간 한정 검사 불가"
else
  _tmpl_n=$(awk '/^#### A\./,/^#### B\./' "$_sa" | grep -c 'templates/screen\.html' || true)
  if [ "${_tmpl_n:-0}" -ge 1 ]; then
    ok "U24.j start-all Phase 2.5-A 구간 내 templates/screen.html 참조 (AC-2)"
  else
    nope "U24.j" "Phase 2.5-A 구간 내 templates/screen.html 참조 0건 — batch 화면이 --text-*/--space-* 토큰을 못 받는다"
  fi
fi


# U16 — _inject_design_palette 무손상 (3변수). 입력은 인라인 픽스처 — 자산 경로 DESIGN.md 는 제거됐다.
_hd=$(mktemp -d); _h="$_hd/s.html"
printf '| Surface | `#111111` |\n| Text Primary | `#222222` |\n| Error | `#333333` |\n' > "$_hd/DESIGN.md"
printf '<style>:root{--color-surface: #000000; --color-text: #000000; --color-error: #000000;}</style>' > "$_h"
( cd "$_hd" && . "$PLUGIN/scripts/_internal/init-project/lib.sh" && _inject_design_palette "$_h" )
_left=$(grep -o -- '#000000' "$_h" 2>/dev/null | wc -l | tr -d ' ')
[ "${_left:-9}" -eq 0 ] && ok "U16 _inject_design_palette 3변수 치환" \
  || nope "U16" "미치환 ${_left}개 — 라벨 매핑이 깨졌다(무음 sink)"
rm -rf "$_hd"
# U17 — AC-R-1: 기존 DESIGN.md 를 덮지 않는다
_sd=$(mktemp -d); printf '# 기존 파일\n' > "$_sd/DESIGN.md"
_m1=$(cksum < "$_sd/DESIGN.md")
( cd "$_sd" && PLUGIN="$PLUGIN" PROJECT_KIND=1 PROJECT_NAME=T CONFLICT_POLICY=skip \
    bash -c '. "$PLUGIN/scripts/_internal/init-project/lib.sh"
             . "$PLUGIN/scripts/_internal/init-project/phases-design.sh"
             phase_6_design </dev/null' >/dev/null 2>&1 )
_m2=$(cksum < "$_sd/DESIGN.md")
[ "$_m1" = "$_m2" ] && ok "U17 기존 DESIGN.md 보존 (AC-R-1)" || nope "U17" "덮어썼다 — _should_skip 뒤에 넣었는가?"
rm -rf "$_sd"

# ── 시한폭탄 회귀 잠금 (2026-08-10 실발화) ──
# 계기: test-verification-state.sh·test-verdict-board.sh 가 waiver 만료일을
#   "2026-08-10T00:00:00Z" 로 **하드코딩**해, 그 시각이 지나자 WAIVED 가 NOT_RUN 으로
#   계산돼 두 스위트가 동시에 FAIL 했다(현재 UTC 가 24분 지난 시점에 실발화).
#   프로덕션(verification-state.sh)은 정상이다 — 조회 시점에 만료를 계산하는 게 설계다.
#   테스트가 "미래" 라고 가정한 값이 과거가 된 것뿐이다.
# ★ 미래 날짜 하드코딩은 **언젠가 반드시** 터진다. 상대 날짜만 쓴다.
# ★ **미래** 날짜만 잡는다. 과거 날짜(2020-01-01)는 "만료된 waiver 는 거부된다" 를
#   증명하는 의도적 고정값이라 시한폭탄이 아니다 — 시간이 지나도 계속 과거다.
_today=$(date -u +%Y-%m-%d)
_tb=$(cd "$PLUGIN" && grep -rhoE -- '--waiver-expires-at "[0-9]{4}-[0-9]{2}-[0-9]{2}' scripts/tests/*.sh 2>/dev/null \
      | sed 's/.*"//' | awk -v t="$_today" '$0 >= t' | wc -l | tr -d ' ')
[ "$_tb" -eq 0 ] && ok "TB1 미래 만료일 하드코딩 0건 (시한폭탄 잠금)" \
  || nope "TB1" "하드코딩 ${_tb}곳 — 그 날짜가 지나면 스위트가 스스로 터진다"


# E10 소비측 배선 (AC-5)
grep -q '§2 타이포·§3 간격' "$PLUGIN/skills/specifying-ko/SKILL.md" \
  && ok "E10 Step 5.5 소비 목록에 §2·§3" || nope "E10" "소비측 미배선"
grep -q -- '--text-base' "$PLUGIN/templates/screen.html" \
  && ok "E11 screen.html 타입 토큰" || nope "E11" "토큰 부재"
grep -q -- '--space-4' "$PLUGIN/templates/screen.html" \
  && ok "E12 screen.html 간격 토큰" || nope "E12" "토큰 부재"

# ── C: 디자인 방향 카탈로그 (FID 20260928-design-direction-catalog) ──
_DD="$PLUGIN/templates/design-directions.md"
if [ ! -f "$_DD" ]; then
  nope "C0" "카탈로그 부재 — $_DD"
else
  _crows=$(awk -F'|' 'NF >= 18 && $2 ~ /^[ ]*[0-9]+[ ]*$/' "$_DD")
  _cn=$(printf '%s\n' "$_crows" | grep -c . || true)
  [ "${_cn:-0}" -eq 9 ] && ok "C1 방향 9개 (AC-7)" || nope "C1" "방향 ${_cn:-0}개 — 9개여야 한다"
  _cbad=$(printf '%s\n' "$_crows" | awk -F'|' '
    { id=$2; gsub(/ /,"",id); want++
      if (id != want) print "id:" id "≠" want
      if ($0 ~ /\t/) print "탭:" id
      for (i=3;i<=5;i++){ v=$i; gsub(/^[ ]+|[ ]+$/,"",v); if (v=="") print "빈칸:" id "/" i }
      for (i=6;i<=8;i++){ v=$i; gsub(/ /,"",v); if (v !~ /^([1-9]|10)$/) print "다이얼:" id "=" v }
      for (i=9;i<=17;i++){ v=$i; gsub(/ /,"",v); if (v !~ /^#[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$/) print "hex:" id "=" v } }')
  [ -z "$_cbad" ] && ok "C2 스키마 — 연속 id·필드 완비·다이얼 1~10·#RRGGBB (AC-2)" \
    || nope "C2" "$(printf '%s' "$_cbad" | head -3 | tr '\n' ' ')"
  read -r _clum _cdark <<<"$(printf '%s\n' "$_crows" | awk -F'|' '
    function h(s,  i,v){ v=0; for(i=1;i<=length(s);i++) v=v*16+index("0123456789ABCDEF",substr(s,i,1))-1; return v }
    function lin(c){ c=c/255; return (c<=0.03928)? c/12.92 : ((c+0.055)/1.055)^2.4 }
    function lum(x){ return 0.2126*lin(h(substr(x,2,2)))+0.7152*lin(h(substr(x,4,2)))+0.0722*lin(h(substr(x,6,2))) }
    { bg=$11; gsub(/ /,"",bg); L=lum(bg); if (NR==1) first=L; if (L<0.5) dark++ }
    END { printf "%.3f %d\n", first, dark }')"
  _c1sum=$(printf '%s\n' "$_crows" | head -1 | awk -F'|' '{print $4}')
  if awk -v l="${_clum:-0}" 'BEGIN{exit !(l>=0.8)}' \
     && printf '%s' "$_c1sum" | grep -q '업무형' && printf '%s' "$_c1sum" | grep -q '저채도' \
     && printf '%s' "$_c1sum" | grep -q '중밀도' && printf '%s' "$_c1sum" | grep -q '단일 강조색'; then
    ok "C3 방향 1 라이트 업무형 (휘도 ${_clum}) (AC-7)"
  else
    nope "C3" "방향 1 휘도 ${_clum:-?} 또는 요약에 업무형·저채도·중밀도·단일 강조색 누락"
  fi
  [ "${_cdark:-0}" -ge 2 ] && [ "${_cdark:-0}" -le 3 ] && ok "C4 다크 방향 ${_cdark}개 (AC-7)" \
    || nope "C4" "다크 방향 ${_cdark:-?}개 — 2~3개여야 한다"
fi
# ── D: 템플릿 죽은 슬롯 — 제거된 엔진·자산이 채우던 자리 (AC-5) ──
_DEAD_RE='자산 미제공|app-interface\.csv|motion\.csv|engine 미연결|엔진 연결됨|\[Recommended_Pattern\]|\[Style_Priority\]|\[Key_Effects\]'
if [ -f "$_T" ]; then
  _dd=$(grep -nE "$_DEAD_RE" "$_T" | head -3)
  [ -z "$_dd" ] && ok "D1 템플릿 죽은 슬롯 0건" || nope "D1" "잔존: $(printf '%s' "$_dd" | tr '\n' ' ')"
else
  nope "D1" "템플릿 부재"
fi
# B2 — 카탈로그 원천 slug 음성 잠금 (AC-1). 판정 리터럴이라 이 파일에만 둔다.
#   -w 필수: 없으면 `cal` 이 템플릿의 Scale·Call 에 오탐한다(plan-review 실측).
_SLUG_RE='mintlify|ibm|linear|notion|minimax|miro|mongodb|hashicorp|posthog|airtable|cal|clay|clickhouse|figma|sentry|raycast|sanity|intercom'
if [ -f "$_DD" ] && [ -f "$_T" ]; then
  _sl=$(grep -niwE "$_SLUG_RE" "$_DD" "$_T" 2>/dev/null | head -3)
  [ -z "$_sl" ] && ok "B2 카탈로그·템플릿 원천 slug 0건 (AC-1)" || nope "B2" "잔존: $(printf '%s' "$_sl" | tr '\n' ' ')"
else
  nope "B2" "판정 대상 부재 — 카탈로그 또는 템플릿"
fi
# ── B1: brand-pick 리터럴 음성 잠금 (AC-1) ──
_BR_RE='Stripe|Notion|#635BFF|#5E6AD2|#7C3AED|brand-pick|_design_brand_|디자인 브랜드'
_bmiss=""; for _bf in scripts/_internal/init-project/phases-design.sh templates/design-directions.md templates/DESIGN.md commands/init-project.md; do
  [ -f "$PLUGIN/$_bf" ] || _bmiss="$_bmiss $_bf"; done
if [ -n "$_bmiss" ]; then
  nope "B1" "판정 대상 부재:$_bmiss"
else
  _bh=$(cd "$PLUGIN" && grep -niE "$_BR_RE" scripts/_internal/init-project/phases-design.sh templates/design-directions.md templates/DESIGN.md commands/init-project.md | head -3)
  [ -z "$_bh" ] && ok "B1 brand-pick 브랜드명·hex 0건" || nope "B1" "잔존: $(printf '%s' "$_bh" | tr '\n' ' ')"
  # B1b — Linear 는 단어 경계(-w)로만 본다: 현재 4파일에 부분 문자열 0건이나 향후 linear-gradient 유입 대비. Claude 는 CLAUDE.md 정당 참조라 잠그지 않는다(§6 한계).
  _bl=$(cd "$PLUGIN" && grep -niw 'linear' scripts/_internal/init-project/phases-design.sh templates/design-directions.md templates/DESIGN.md commands/init-project.md | head -3)
  [ -z "$_bl" ] && ok "B1b brand-pick Linear 0건" || nope "B1b" "잔존: $(printf '%s' "$_bl" | tr '\n' ' ')"
fi
# ── P6: Phase 6 방향 선택 → DESIGN.md (AC-3) ──
#   mktemp 실패 시 빈 문자열 + return 1 — bash 는 `cd ""` 를 성공으로 처리하므로 무가드면 스위트 cwd 의
#   실 DESIGN.md 를 overwrite 하고 이어 `rm -rf /` 경로가 된다(Phase C 프로브 ⑥).
_p6d() { # $1=stdin 한 줄 → 생성된 DESIGN.md 경로 (실패 시 빈 문자열, rc 1)
  local d; d=$(mktemp -d 2>/dev/null) && [ -n "$d" ] && [ -d "$d" ] || { printf ''; return 1; }
  ( cd "$d" && printf '%s\n' "$1" | PLUGIN="$PLUGIN" PROJECT_KIND=1 PROJECT_NAME=TestProj CONFLICT_POLICY=overwrite \
      bash -c '. "$PLUGIN/scripts/_internal/init-project/lib.sh"
               . "$PLUGIN/scripts/_internal/init-project/phases-design.sh"
               phase_6_design' >/dev/null 2>&1 )
  printf '%s' "$d/DESIGN.md"
}
# 임시 디렉터리만 지운다 — 빈 값·`/`·`.`·mktemp 가 만든 것이 아닌 경로는 거부(단일 가드)
_p6rm() {
  case "$1" in ''|/|.|./|..) return 1 ;; esac
  [ -d "$1" ] && case "$1" in "${TMPDIR:-/tmp}"/*|/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) rm -rf "$1" ;; *) return 1 ;; esac
}
_catrow() { awk -F'|' -v id="$1" 'NF >= 18 { v=$2; gsub(/ /,"",v); if (v == id) print }' "$_DD"; }
_cell() { printf '%s' "$1" | awk -F'|' -v i="$2" '{ v=$i; gsub(/^[ ]+|[ ]+$/,"",v); print v }'; }
# "+2"·"02" — sed -n "+2p" 는 BSD 에서 오류라 빈 행 → 자리표시자 DESIGN.md 에 "작성 완료"(Phase C 프로브 ⑤). 선행 0 은 10진 해석.
for _case in "1:1" "2:2" ":1" "99:1" "+2:1" "02:2" "18446744073709551618:1"; do
  _in=${_case%%:*}; _want=${_case##*:}
  _f=$(_p6d "$_in") || _f=""
  if [ -z "$_f" ]; then nope "P6.${_in:-빈입력}" "임시 디렉터리 생성 실패 — 판정 불가"; continue; fi
  _row=$(_catrow "$_want"); _ok=1
  [ -n "$_row" ] && [ -f "$_f" ] || _ok=0
  grep -qF "> **디자인 방향**: $(_cell "$_row" 3)" "$_f" 2>/dev/null || _ok=0
  grep -qF "VARIANCE $(_cell "$_row" 6) · MOTION $(_cell "$_row" 7) · DENSITY $(_cell "$_row" 8)" "$_f" 2>/dev/null || _ok=0
  _i=9
  for _lbl in Primary Secondary Background Surface "Text Primary" "Text Secondary" Border Error Success; do
    grep -qF "| $_lbl | \`$(_cell "$_row" $_i)\` |" "$_f" 2>/dev/null || _ok=0
    _i=$((_i+1))
  done
  _t1=$(_cell "$_row" 5 | cut -d';' -f1 | sed 's/^ *//; s/ *$//')
  awk '/^## 8\./{f=1;next} /^## /{f=0} f' "$_f" 2>/dev/null | grep -qF -- "- $_t1" || _ok=0
  [ "$_ok" = 1 ] && ok "P6.${_in:-빈입력} → 방향 $_want 산출 (AC-3)" || nope "P6.${_in:-빈입력}" "방향 $_want 산출 불일치"
  _p6rm "$(dirname "$_f")"
done
_f=$(_p6d "1") || _f=""
if [ -z "$_f" ]; then nope "P6.inject" "임시 디렉터리 생성 실패 — 판정 불가"; _d=""; else _d=$(dirname "$_f"); fi
if [ -n "$_d" ]; then
  printf '<style>:root{--color-primary: #000000; --color-secondary: #000000; --color-bg: #000000; --color-surface: #000000; --color-text: #000000; --color-text-secondary: #000000; --color-border: #000000; --color-error: #000000; --color-success: #000000;}</style>' > "$_d/s.html"
  ( cd "$_d" && . "$PLUGIN/scripts/_internal/init-project/lib.sh" && _inject_design_palette "$_d/s.html" ) 2>/dev/null
  _left=$(grep -o -- '#000000' "$_d/s.html" 2>/dev/null | wc -l | tr -d ' ')
  [ "${_left:-9}" -eq 0 ] && ok "P6.inject 생성 DESIGN.md → 화면 9변수 치환 (AC-3)" || nope "P6.inject" "미치환 ${_left:-?}개"
  _p6rm "$_d"
fi
# P6.doc — 머리 선언이 약속한 Phase 11 decisions.md upsert 지시가 실제로 문서에 있다 (외부 critic 반영)
grep -E '^- `DESIGN\.md` — \*\*UI KIND일 때만\*\*' "$PLUGIN/commands/init-project.md" | grep -q 'decisions.md' \
  && ok "P6.doc Phase 11 디자인 방향 upsert 지시 존재" || nope "P6.doc" "init-project.md Phase 11 DESIGN.md 항목에 decisions.md upsert 지시 없음"

# ── S9: DESIGN.md AI 지침 섹션 번호 정합 (AC-6) ──
_ain=$(grep -oE '^## [0-9]+\. AI Usage' "$_T" 2>/dev/null | grep -oE '[0-9]+')
_aref=$(cd "$PLUGIN" && grep -n 'AI Usage' templates/*.md | grep -v '^templates/DESIGN.md:')
_adrift=$(printf '%s\n' "$_aref" | grep . | grep -v "§${_ain:-X}" || true)
_arefn=$(printf '%s\n' "$_aref" | grep -c . || true)
if [ -z "$_ain" ] || [ "${_arefn:-0}" -lt 3 ]; then
  nope "S9" "판정 불가 — AI 지침 섹션(${_ain:-없음}) 또는 참조 ${_arefn:-0}건(3건 기대)"
elif [ -z "$_adrift" ]; then
  ok "S9 AI 지침 참조가 §${_ain} 과 일치 (${_arefn}건)"
else
  nope "S9" "번호 어긋남: $(printf '%s' "$_adrift" | head -3 | tr '\n' ' ')"
fi


# ── N: 외부 디자인 플러그인 재유입 금지 (FID 20260928-uiux-promax-removal-design-master) ──
#   판정 리터럴 보유 3파일과 과거 기록(CHANGELOG·docs/audit)은 제외한다(AC-6 ④).
#   한계 ①: `_nl` 은 git grep 이라 **tracked 파일만** 본다 — untracked 주입은 여기서 안 잡힌다(커밋 시 추적되므로 CI 에서 잡힘).
#   한계 ②: 제외는 **파일 단위**다 — 판정 리터럴 3파일 내부의 재유입은 검사하지 않는다.
#   N0 — git 판정 가능 여부 가드. git 오류 시 git grep 은 빈 문자열, ls-files 는 0 을 내고 그 값이 곧 PASS 조건이라
#     판정 불가가 PASS 로 위장됐다(Phase C 프로브 P5 실측 20260928). 양성 앵커(plugin.json 이 **이 트리의 인덱스에** 추적됨)로
#     묻는다 — `rev-parse --is-inside-work-tree` 는 타 repo 하위 untracked 사본·인덱스 손상·GIT_* 오염에서도 true 라
#     "git 트리인가" 만 답했다(Phase C 2회차 ①②④ 실측: 전부 45/0). 보장 범위: 앵커가 없으면(비-git·타 repo 하위·인덱스
#     손상) FAIL N0, 앵커 통과 뒤 호출별 git 오류(rc>1)는 _nl 이 FAIL. 동시 실행 index.lock 경합은 재현·보장하지 않았다.
_NL_GIT_OK=0
git -C "$PLUGIN" ls-files --error-unmatch -- .claude-plugin/plugin.json >/dev/null 2>&1 && _NL_GIT_OK=1 \
  || nope "N0" "git 판정 불가(앵커 .claude-plugin/plugin.json 미추적) — 음성 잠금(N2.a·N2.b·N3·N4)을 평가할 수 없다"
_NL_RE='ui-ux-pro-max|uiux::|uiux-assets|UIUX_'   # UIUX_ = 제거된 엔진·자산 env(UIUX_ENGINE_DISABLE 등) 재유입
_nl() { # $1=라벨, 나머지=pathspec
  local lbl="$1"; shift
  local hits rc
  [ "$_NL_GIT_OK" -eq 1 ] || { nope "$lbl" "git 판정 불가 (N0)"; return; }
  # rc 를 head 파이프에 잃지 않도록 grep 출력과 rc 를 먼저 분리 캡처한다 — 인덱스 손상(rc=128)이 빈 hits → PASS 로 위장됐다
  hits=$(cd "$PLUGIN" && git grep -nE "$_NL_RE" -- "$@" \
    ':!CHANGELOG.md' ':!docs/audit' ':!scripts/tests/test-design-contract.sh' \
    ':!scripts/tests/test-batch-orchestration.sh' ':!scripts/tests/test-screen-routing-doc.sh' 2>/dev/null); rc=$?
  if [ "$rc" -gt 1 ]; then nope "$lbl" "git grep 오류 rc=$rc — 판정 불가"; return; fi
  hits=$(printf '%s\n' "$hits" | head -3)
  [ -z "$hits" ] && ok "$lbl 재유입 0건" || nope "$lbl" "잔존: $(printf '%s' "$hits" | tr '\n' ' ')"
}
# N1 — 매니페스트 의존 선언 0 (AC-1)
_pj="$PLUGIN/.claude-plugin/plugin.json"; _mj="$PLUGIN/.claude-plugin/marketplace.json"
grep -q '"ui-ux-pro-max' "$_pj" && nope "N1.a" "plugin.json 에 의존 선언" || ok "N1.a plugin.json 의존 0"
grep -q 'allowCrossMarketplaceDependenciesOn' "$_mj" && nope "N1.b" "marketplace.json 에 cross-marketplace 허용" \
  || ok "N1.b marketplace.json cross-marketplace 0"
if command -v jq >/dev/null 2>&1; then
  jq -e . "$_pj" >/dev/null 2>&1 && jq -e . "$_mj" >/dev/null 2>&1 \
    && ok "N1.c 매니페스트 JSON 유효" || nope "N1.c" "JSON 파싱 실패"
fi
# N2 — bash 어댑터·픽스처 부재 (AC-2·AC-6 ③)
_nl "N2.a scripts/·.claude-plugin/" scripts .claude-plugin
if [ "$_NL_GIT_OK" -eq 1 ]; then
  _fxl=$(cd "$PLUGIN" && git ls-files scripts/_internal/uiux-assets.sh scripts/tests/fixtures/uiux scripts/tests/fixtures/uiux-engine 2>/dev/null); _fxrc=$?
  _fx=$(printf '%s' "$_fxl" | grep -c . || true)
  if [ "$_fxrc" -ne 0 ]; then nope "N2.b" "git ls-files 오류 rc=$_fxrc — 판정 불가"
  elif [ "$_fx" -eq 0 ]; then ok "N2.b 어댑터·픽스처 추적 0건"
  else nope "N2.b" "추적 ${_fx}건 잔존"; fi
else
  nope "N2.b" "git 판정 불가 (N0)"
fi
# N3 — 산문 표면(skills/commands/agents/hooks/templates) 재유입 0 (AC-2·AC-5)
_nl "N3 skills/·commands/·agents/·hooks/·templates/" skills commands agents hooks templates
# N4 — 저장소 전역(README·CONTRIBUTING 등 나머지 표면) 재유입 0 (AC-2 완결)
_nl "N4 저장소 전역" .

# ── T0: N0 가드의 이빨 (회귀 잠금 — a24e039 T4.a/T4.b 선례) ──
#   가드 3줄을 지워도 run-all 이 green 이었다(Phase C 2회차 ⑤). 현재 작업본 스위트를 판정 불가 트리에 복사해 돌려 `FAIL N0` 를 단언한다.
#   복사본 안에서 이 블록이 다시 돌지 않도록 DESIGN_CONTRACT_TEETH=1 로 재귀를 끊는다.
if [ "${DESIGN_CONTRACT_TEETH:-0}" != "1" ]; then
  _T0=$(mktemp -d); trap 'rm -rf "$_T0"' EXIT
  _t0_run() { # $1=대상 루트 → 복사본 스위트 출력
    mkdir -p "$1/scripts/tests" && cp "${BASH_SOURCE[0]}" "$1/scripts/tests/test-design-contract.sh" \
      && (cd "$1" && DESIGN_CONTRACT_TEETH=1 bash scripts/tests/test-design-contract.sh 2>/dev/null)
  }
  # T0.a — 비-git 디렉터리
  _t0a=$(_t0_run "$_T0/nogit")
  printf '%s\n' "$_t0a" | grep -q '^FAIL N0' && ok "T0.a 비-git 트리에서 FAIL N0 (N0 이빨)" \
    || nope "T0.a" "비-git 트리에서 N0 무검출 — $(printf '%s\n' "$_t0a" | grep '^PASS=' | tail -1)"
  # T0.b — 타 git repo 하위의 untracked 사본 (rev-parse 는 true 를 내던 클래스)
  mkdir -p "$_T0/outer" && git -C "$_T0/outer" init -q 2>/dev/null
  _t0b=$(_t0_run "$_T0/outer/sub")
  printf '%s\n' "$_t0b" | grep -q '^FAIL N0' && ok "T0.b 타 repo 하위 untracked 사본에서 FAIL N0 (N0 이빨)" \
    || nope "T0.b" "타 repo 하위에서 N0 무검출 — $(printf '%s\n' "$_t0b" | grep '^PASS=' | tail -1)"
fi

# ── G4: §6.1 장르 규칙 표 ↔ 계측기 ID 정합 (FID 20260929-enterprise-genre-rules AC-4) ──
#   ID 는 계측기의 _GENRE_IDS 선언 줄에서만 읽는다 — 주석 속 ID 가 섞이지 않게.
_GQ="$PLUGIN/scripts/_internal/check-screen-quality.sh"
_s61=$(awk '/^## 6\.1 /{f=1;next} f&&/^## /{exit} f' "$_T")
_gids=$(sed -n "s/^_GENRE_IDS='\(.*\)'\$/\1/p" "$_GQ" 2>/dev/null)
_gn=$(printf '%s\n' $_gids | grep -c '^G-' || true)
if [ "${_gn:-0}" -ne 7 ]; then
  nope "G4.a" "계측기 ID 추출 ${_gn}개 (기대 7) — _GENRE_IDS 선언 줄 확인 (판정 불가를 PASS 로 위장 금지)"
else
  _gm=""
  for id in $_gids; do
    printf '%s\n' "$_s61" | grep -E "^\| $id \|" | grep -qE '\| 계측 \|[[:space:]]*$' || _gm="$_gm $id"
  done
  [ -z "$_gm" ] && ok "G4.a 계측기 ID 7개 전부 §6.1 계측 행" || nope "G4.a" "§6.1 계측 행 누락:$_gm"
fi
_pm=""
for p in 'G-TABLE-' 'G-PAGING-SERVER' 'G-RBAC-'; do
  printf '%s\n' "$_s61" | grep -E "^\| ${p}" | grep -qE '\| 산문 \|[[:space:]]*$' || _pm="$_pm $p"
done
[ -z "$_pm" ] && ok "G4.b 산문 규칙(표·서버 페이징·권한별 표시) 행" || nope "G4.b" "누락:$_pm"
printf '%s\n' "$_s61" | grep -q '^| 다단 폼 |' && ok "G4.c §6.1 원형 표 다단 폼 행" || nope "G4.c" "다단 폼 행 없음"
printf '%s\n' "$_s61" | grep -qF 'genre-override' && ok "G4.d override 문법 안내" || nope "G4.d" "genre-override 안내 없음"

# ── G4 역방향: §6.1 판정 라벨 ↔ 계측기 정직성 (FID 20260930-prose-linter-honesty-lock) ──
#   G4.a 는 계측기 ID ⊂ §6.1 계측 행만 본다. 표가 "자동 검사한다" 고 거짓 주장하는 계측 행,
#   계측기가 검사하는데 산문으로 적힌 행, 같은 ID 의 중복 행은 G4.a~d 를 모두 통과했다(분석 변이 실측).
#   판정 대상 = §6.1 의 `### 장르 규칙` 소절(원형 표는 행 수 대조를 오염시키므로 제외).
#   규칙 행 = (앞 공백·탭 허용) `|` 다음 G- 로 시작하는 행 · 라벨 = 마지막 칸.
#   데이터 행(`|` 시작 · 헤더(둘째 칸 ID)·구분선 제외) 중 규칙 행으로 추출되지 않은 행은 g 에 첫 칸으로 보고한다 —
#   정상 행이 하나라도 있으면 `X-`·백틱 ID 의 거짓 계측 행이 조용히 버려져 G4.e 를 통과했다(Phase C 프로브 P9).
#   $_gids 는 G4 가 _GENRE_IDS 선언 줄에서 sed 로 뽑은 공백 분리 ID 목록이다 — 부분 추출은 G4.a 의 개수(7) 검사가 막는다.
_g4_honesty() {  # <장르 규칙 소절 본문> <계측기 ID 목록> → 위반 없으면 무출력 · 있으면 "e|f|g<TAB>사유" 줄 · 추출 0건이면 "none"
  local body="$1" ids="$2" rows id lb fake="" mis="" bad="" dup unx
  rows=$(printf '%s\n' "$body" | awk -F'|' '/^[ \t]*\|[ \t]*G-/{id=$2; lb=$(NF-1); gsub(/^[ \t]+|[ \t]+$/,"",id); gsub(/^[ \t]+|[ \t]+$/,"",lb); print id" "lb}')
  unx=$(printf '%s\n' "$body" | awk -F'|' '/^[ \t]*\|/ && !/^[ \t]*\|[ \t]*G-/ && !/^[ \t|:-]+$/{c=$2; gsub(/^[ \t]+|[ \t]+$/,"",c); if (c!="ID") printf " %s", c}')
  if [ -z "$rows" ] || [ -z "$ids" ]; then echo none; return; fi
  while read -r id lb; do
    case "$lb" in
      계측) printf '%s\n' $ids | grep -qxF -- "$id" || fake="$fake $id" ;;
      산문) printf '%s\n' $ids | grep -qxF -- "$id" && mis="$mis $id" ;;
      *)    bad="$bad $id($lb)" ;;
    esac
  done <<EOF2
$rows
EOF2
  dup=$(printf '%s\n' "$rows" | awk '{print $1}' | sort | uniq -d | tr '\n' ' ')
  [ -n "$fake" ] && printf 'e\t%s\n' "$fake"
  [ -n "$mis" ] && printf 'f\t%s\n' "$mis"
  { [ -n "$dup" ] || [ -n "$bad" ] || [ -n "$unx" ]; } \
    && printf 'g\t중복 ID:%s · 라벨 계측/산문 외:%s · 미추출 행:%s\n' "${dup:- 없음}" "${bad:- 없음}" "${unx:- 없음}"
  return 0
}
_s61g=$(printf '%s\n' "$_s61" | awk '/^### 장르 규칙/{f=1;next} f&&/^#/{exit} f')
_h=$(_g4_honesty "$_s61g" "$_gids")
if [ "$_h" = none ]; then
  nope "G4.e" "판정 불가 — §6.1 장르 규칙 소절 규칙 행 또는 계측기 ID 추출 0건 (PASS 로 위장 금지)"
  nope "G4.f" "판정 불가 — 위와 같음"
  nope "G4.g" "판정 불가 — 위와 같음"
else
  _he=$(printf '%s\n' "$_h" | sed -n 's/^e\t//p'); _hf=$(printf '%s\n' "$_h" | sed -n 's/^f\t//p'); _hg=$(printf '%s\n' "$_h" | sed -n 's/^g\t//p')
  # 소절 축소의 역구멍 봉합 — §6.1 의 장르 규칙 소절 밖(원형 표 등)에 놓인 G- 규칙 행은 판정 대상에서 빠지므로 여기서 보고
  _hout=$(printf '%s\n' "$_s61" | awk -F'|' '/^### 장르 규칙/{f=1;next} f&&/^#/{f=0} !f&&/^[ \t]*\|[ \t]*G-/{c=$2; gsub(/^[ \t]+|[ \t]+$/,"",c); printf " %s", c}')
  [ -n "$_hout" ] && _hg="${_hg:+$_hg · }소절 밖 규칙 행:$_hout"
  [ -z "$_he" ] && ok "G4.e §6.1 계측 행 전부 계측기 _GENRE_IDS 에 있음" || nope "G4.e" "§6.1 계측 행인데 계측기 _GENRE_IDS 에 없음:$_he"
  [ -z "$_hf" ] && ok "G4.f §6.1 산문 행은 계측기가 검사하지 않음" || nope "G4.f" "계측기가 검사하는데 §6.1 산문 행:$_hf"
  [ -z "$_hg" ] && ok "G4.g §6.1 규칙 ID 유일 · 판정 라벨 계측/산문 뿐 · 미추출 행 없음" || nope "G4.g" "$_hg"
fi
# G4.h 잠금의 잠금 — 판정 함수가 합성 표의 거짓 계측·산문 오표기·중복·라벨 오타·공백 없는 행을 실제로 잡는지 자기 검증
_fx=$(printf '%s\n' '| G-A | 목록 | 규칙 | 계측 |' '|G-FAKE | 목록 | 규칙 | 계측 |' '| G-A | 목록 | 규칙 | 산문 |' '	| G-B | 목록 | 규칙 | 계층 |' '| G-AX | 목록 | 접두 충돌 | 계측 |' '| X-FAKE | 목록 | 정규식 미매칭 | 계측 |')
_fh=$(_g4_honesty "$_fx" "G-A G-C G-AXY")   # G-AX ⊂ G-AXY 접두 — 부분 일치로 통과하면 안 된다(실 ID G-LIST-EMPTY-KIND 와 같은 모양)
if printf '%s\n' "$_fh" | grep -q $'^e\t.*G-FAKE.*G-AX' && printf '%s\n' "$_fh" | grep -q $'^f\t.*G-A' \
   && printf '%s\n' "$_fh" | grep -q $'^g\t.*G-A.*G-B(계층).*미추출 행:.*X-FAKE' && [ "$(_g4_honesty "" "G-A")" = none ]; then
  ok "G4.h 판정 함수 자기 검증 — 거짓 계측·산문 오표기·중복·라벨 오타·공백 없는 행·접두 충돌·미추출 행·추출 0건"
else nope "G4.h" "합성 표 판정 불일치: $(printf '%s' "$_fh" | tr '\n\t' '  ')"; fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
