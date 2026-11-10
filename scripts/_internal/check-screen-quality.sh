#!/usr/bin/env bash
# check-screen-quality.sh — 화면 쌍(.md + .html) 정적 품질 계측
#
# 계기: design-reviewer-ko 의 8관점이 전부 구조·정합이라 "구조는 맞물리는데 쓸 수 없는 화면"이
#       게이트를 그대로 지나갔다. 껍데기 판정도 마커 grep + 섹션 '제목' 존재만 본다.
#
# ★ 계측 전용 — 항상 exit 0. 판정은 design-reviewer-ko 가 한다.
#   휴리스틱이라 오탐이 불가피한데, exit code 로 차단하면 오탐 1건이 배치를 세운다
#   (check-ci-status.sh 와 동형 계약).
#
# 계약: read-only · stdout=리포트 · exit 항상 0 · jq 불요(grep/awk/sed)
# usage: check-screen-quality.sh <screen.md> <screen.html>
#        check-screen-quality.sh --all            # screens/ 전체
set -uo pipefail

_count() { printf '%s' "${1:-0}" | tr -d ' \n'; }

# 판정 불가를 '위반 0' 으로 보고하지 않는다 — 무음 낙관 금지 (doctor.sh v1.78.0 교훈)
_readable() { [ -f "$1" ] && [ -r "$1" ]; }

_NL='
'
_TAB=$(printf '\t')

# ── 규칙 카탈로그 (FID 20260929-design-rule-id-catalog) — 규칙 ID·심각도의 단일 SoT ──
# 한 줄 = id|severity|snippet|fix. severity 는 Important · Minor · 단계형(개수 기준 — snippet 에 명시).
# Critical 은 두지 않는다 — /start-all-auto 가 Critical≥1 에서 무인 실행을 정지시킨다(design-reviewer-ko).
# snippet·fix 에 '|' 금지 — --rules 표 열이 밀린다(test R1.a 가 NF 로 잠금).
_RULES=$(cat <<'RULES'
S-STATES-EMPTY|Important|States 에 empty(빈 상태) 정의 없음|빈 상태 문구와 다음 행동(CTA)을 States 에 적는다
S-STATES-ERROR|Important|States 에 error(오류) 정의 없음|오류 표현과 복구 방법을 States 에 적는다
S-STATES-LOADING|Minor|States 에 loading(로딩) 정의 없음|로딩 표현(스켈레톤·스피너)을 States 에 적는다
S-A11Y-LABEL|Important|label 없는 입력 요소(hidden 제외)|입력마다 label 을 연결한다
S-LANDMARK|Minor|랜드마크 요소(main·nav·header·section·aside·footer) 0개|영역을 랜드마크 요소로 감싼다
S-TOKEN-HEX|단계형|--이름: 정의부 밖 색 hex 리터럴 (1~2건 Minor · 3건 이상 Important)|var(--토큰) 으로 바꾼다
S-COPY-VAGUE|단계형|에러 메시지가 오류·실패·에러 단독 (일부 Minor · 전부 Important)|사용자가 무엇을 해야 하는지 쓴다
G-LIST-PAGING|Important|목록 원형 — 페이징과 총 건수 표시 없음|페이징(또는 무한 스크롤)과 총 건수를 적는다
G-LIST-SORT|Important|목록 원형 — 기본 정렬 기준 없음|기본 정렬 기준을 적는다
G-LIST-EMPTY-KIND|Important|목록 원형 — 빈 상태 두 종류 구분 없음|States 에 데이터 없음과 검색·필터 결과 없음을 나눠 적는다
G-FORM-SUBMIT|Important|폼 원형 — 제출 중 비활성 없음|제출 중 버튼 비활성과 중복 제출 방지를 적는다
G-FORM-CANCEL|Important|폼 원형 — 취소 경로 없음|취소 경로를 적는다
G-WIZARD-STEP|Important|다단 폼 원형 — 단계 표시·이전·중간 저장 중 누락|단계 표시·이전 단계·중간 저장(또는 이탈 시 보존)을 적는다
G-DASH-PERIOD|Important|대시보드 원형 — 기간 선택 없음|기간 선택을 적는다
G-ARCHETYPE-UNDECLARED|Minor|원형 미선언·자리표시자·목록 밖 값|화면 스펙 머리에 원형 선언 줄을 적는다(DESIGN.md §6.1)
G-OVERRIDE-UNREASONED|Minor|사유 없는 genre-override|override 주석에 사유를 적는다
G-OVERRIDE-INVALID|Minor|원형 밖 ID override 또는 판독 불가 override 주석|한 줄 주석으로 이 화면 원형의 규칙 ID 와 사유를 적는다
A-PLACEHOLDER-NAME|Important|.html 화면 텍스트의 Lorem·John Doe·Jane Doe·Acme|실제 데이터 형태의 예시로 바꾼다
A-SCROLL-LISTENER|Minor|script 안 scroll 이벤트 리스너|IntersectionObserver 또는 CSS(position: sticky 등)로 대체한다
A-VIEWPORT-HEIGHT|Minor|height: 100vh 또는 h-screen 클래스 (min-·max- 제외)|min-height 또는 dvh 단위를 쓴다
A-MEDIA-NONE|Minor|완결 페이지(html 태그 또는 doctype 포함)에 @media 0건|좁은 폭 배치를 @media 로 정한다(templates/screen.html 의 768px 골격)
A-TABLE-NOWRAP|Minor|표가 있는데 가로 스크롤 선언(overflow-x auto·scroll) 없음|표를 가로 스크롤 래퍼로 감싼다(templates/screen.html 의 table-wrap)
RULES
)

_rules_print() {
  printf '| id | severity | snippet | fix |\n|---|---|---|---|\n'
  printf '%s\n' "$_RULES" | awk -F'|' 'NF == 4 { printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4 }'
}

# states 누락 항목(empty,loading,error) → 규칙 ID 목록(쉼표)
_states_ids() {
  local x out=""
  for x in $(printf '%s' "$1" | tr ',' ' '); do
    case "$x" in
      empty)   out="$out,S-STATES-EMPTY" ;;
      loading) out="$out,S-STATES-LOADING" ;;
      error)   out="$out,S-STATES-ERROR" ;;
    esac
  done
  printf '%s' "${out#,}"
}

# ── anti: 금지 패턴 (specops-ko 독자 작성 — FID 20260929-design-rule-id-catalog) ──
# .html 에서 HTML <!-- --> · CSS/JS /* */ 블록 주석(다중줄)과 <script> 안 // 줄끝 주석을 걷어낸다.
#   // 는 앞 문자가 줄머리·공백·; · { · } 일 때만 — https:// 의 // 는 보존.
_strip_comments() {  # $1=html → stdout
  awk '
    {
      line = $0; out = ""
      while (length(line) > 0) {
        if (inh) { j = index(line, "-->"); if (!j) { line = ""; break } line = substr(line, j + 3); inh = 0; continue }
        if (inc) { j = index(line, "*/");  if (!j) { line = ""; break } line = substr(line, j + 2); inc = 0; continue }
        a = index(line, "<!--"); b = index(line, "/*")
        # /* 는 앞 문자가 줄머리·공백·; · { · } · > 일 때만 주석 — accept="image/*" 같은 속성값 보존
        if (b > 1 && substr(line, b - 1, 1) !~ /[ \t;{}>]/) b = 0
        if (!a && !b) { out = out line; line = ""; break }
        if (a && (!b || a < b)) { out = out substr(line, 1, a - 1); line = substr(line, a + 4); inh = 1 }
        else                    { out = out substr(line, 1, b - 1); line = substr(line, b + 2); inc = 1 }
      }
      # // 줄끝 주석은 script 구간 안에서만 — 줄을 <script…>~</script 구간 단위로 잘라 각 구간의 첫 // 부터 구간 끝까지만 지운다.
      #   script 밖 텍스트 // 와 </script 태그 자체는 보존(한 줄 두 블록 사이·</script> 뒤 텍스트가 잘리면 블록·자리표시 무음 누락).
      rest = out; out = ""
      while (length(rest) > 0) {
        if (!insc) {
          sp = index(tolower(rest), "<script")
          if (!sp) { out = out rest; rest = ""; break }
          out = out substr(rest, 1, sp + 6); rest = substr(rest, sp + 7); insc = 1
        }
        k = index(tolower(rest), "</script")
        seg = (k ? substr(rest, 1, k - 1) : rest)
        if (match(seg, /(^|[ \t;{}])\/\//)) seg = substr(seg, 1, RSTART + RLENGTH - 3)
        out = out seg
        if (!k) { rest = ""; break }
        rest = substr(rest, k); insc = 0
        out = out substr(rest, 1, 8); rest = substr(rest, 9)
      }
      print out
    }' "$1"
}

# $1=태그(script|style) $2=in|out — 블록 안 내용만 / 블록 밖 내용만 (다중줄 상태 추적)
_blocks() {
  awk -v t="$1" -v mode="$2" '
    BEGIN { o = "<" t; c = "</" t ">" }
    {
      l = $0; keep = ""
      while (1) {
        if (!inb) {
          i = index(tolower(l), o)
          if (!i) { keep = keep l; break }
          keep = keep substr(l, 1, i - 1); l = substr(l, i + length(o)); inb = 1
        } else {
          j = index(tolower(l), c)
          if (!j) { if (mode == "in") print l; l = ""; break }
          if (mode == "in") print substr(l, 1, j - 1)
          l = substr(l, j + length(c)); inb = 0
        }
      }
      if (mode == "out") print keep
    }'
}

# 결과: anti · anti_det (호출자 _analyze 의 local). 규칙마다 적중 수 한 줄 — 변이가 sed 한 줄로 가능해야 한다.
_anti() {  # $1=html
  anti="unknown"; anti_det=""
  _readable "$1" || return 0
  local hs ap as av am=0 at=0
  hs=$(_strip_comments "$1")
  ap=$(_count "$(printf '%s\n' "$hs" | _blocks script out | _blocks style out | grep -oiE 'lorem|john doe|jane doe|acme' | wc -l)")
  as=$(_count "$(printf '%s\n' "$hs" | _blocks script in | grep -oE "addEventListener\([[:space:]]*['\"]scroll['\"]" | wc -l)")
  av=$(_count "$(printf '%s\n' "$hs" | grep -oE '(^|[^a-z-])height[[:space:]]*:[[:space:]]*100vh|class="[^"]*"' | grep -oE 'height[[:space:]]*:[[:space:]]*100vh|(["[:space:]:!])h-screen(["[:space:]])' | wc -l)")  # 앞 문자 : ! 허용 — md:h-screen · !h-screen 도 위반, min-/max- 는 - 라 제외
  # 반응형·표 넘침 (FID 20261110-design-visual-review-loop) — 주석을 걷은 본문 기준 · 파일 단위 근사(표 바로 바깥을 감쌌는지는 보지 않는다).
  #   완결 페이지(html 태그 또는 doctype)만 @media 를 요구한다 — 조각 html(style 블록만 있는 것 포함)은 판정하지 않는다. 일치 판정은 here-string 으로(pipefail 아래 파이프 뒤 grep -q 금지).
  if grep -qiE '<html|<!doctype' <<<"$hs"; then grep -qi '@media' <<<"$hs" || am=1; fi
  if grep -qi '<table' <<<"$hs"; then
    grep -qiE 'overflow(-x)?[[:space:]]*:[[:space:]]*(auto|scroll)|overflow-x-(auto|scroll)|overflow-auto' <<<"$hs" || at=1
  fi
  anti=$((ap + as + av + am + at))
  [ "$ap" -gt 0 ] && anti_det="${anti_det:+$anti_det$_NL}  [anti] 자리표시 이름 ${ap}건 — 실제 데이터 형태의 예시로 바꾼다  rule=A-PLACEHOLDER-NAME"
  [ "$as" -gt 0 ] && anti_det="${anti_det:+$anti_det$_NL}  [anti] 스크롤 이벤트 리스너 ${as}건 — IntersectionObserver 또는 CSS 로 대체  rule=A-SCROLL-LISTENER"
  [ "$av" -gt 0 ] && anti_det="${anti_det:+$anti_det$_NL}  [anti] 뷰포트 높이 고정 ${av}건 — min-height 또는 dvh 사용  rule=A-VIEWPORT-HEIGHT"
  [ "$am" -gt 0 ] && anti_det="${anti_det:+$anti_det$_NL}  [anti] @media 0건 — 좁은 폭 배치가 정해지지 않았다  rule=A-MEDIA-NONE"
  [ "$at" -gt 0 ] && anti_det="${anti_det:+$anti_det$_NL}  [anti] 표에 가로 스크롤 래퍼 없음 — 좁은 폭에서 열이 접히거나 잘린다  rule=A-TABLE-NOWRAP"
  return 0
}

# ── regress: 화면 회귀 (FID 20260929-screen-regression-guard — specops-ko 독자 구현) ──
# 기준 커밋(인자 또는 main/master merge-base)의 같은 화면과 내용 바이트를 비교한다.
# 원시 바이트는 .html 의 style 블록이 지배해 부적합하고(마크업 절반 손실이 거의 안 보인다),
# 템플릿 채움 자체가 0.35배 '축소'로 보이므로 기준이 껍데기면 비교하지 않는다(current-state §4).
_RG_DEF_RATIO='0.60'

_md_bytes() {  # $1=md → frontmatter·껍데기 마커 줄 제외, 공백 제거 바이트
  awk 'NR == 1 && /^---[[:space:]]*$/ { f = 1; next } f && /^---[[:space:]]*$/ { f = 0; next } !f' "$1" \
    | grep -vF 'specops:screen-placeholder' | tr -d ' \t\n\r' | wc -c | tr -d ' '
}
_html_bytes() {  # $1=html → 주석·script·style 제거 후 공백 제거 바이트
  _strip_comments "$1" | _blocks script out | _blocks style out | tr -d ' \t\n\r' | wc -c | tr -d ' '
}
# 판정은 원시 바이트로 한다(현재 < 기준 × 임계값) — 반올림된 비율 문자열로 비교하면 0.596 이 '0.60' 이 되어 빠진다
_rg_is_shrink() { awk -v c="$1" -v b="$2" -v t="$3" 'BEGIN { exit !(c + 0 < (b + 0) * (t + 0)) }'; }

_rg_ratio() {  # → rg_thr · rg_cfg
  local v="${SPECOPS_SCREEN_SHRINK_RATIO:-}"
  rg_cfg=""; rg_thr="$_RG_DEF_RATIO"
  [ -n "$v" ] || return 0
  if grep -qE '^(0?\.[0-9]+|1(\.0+)?)$' <<<"$v" && awk -v x="$v" 'BEGIN { exit !(x > 0 && x <= 1) }'; then
    rg_thr=$(awk -v x="$v" 'BEGIN { printf "%.2f", x }')
  else
    rg_cfg="  [config] SPECOPS_SCREEN_SHRINK_RATIO='$v' 판독 불가 — 기본 $_RG_DEF_RATIO 적용"
  fi
}

_rg_base() {  # $1=기준 ref(선택) → rg_base · rg_short. 실패 rc 1 + rg_why
  local ref="${1:-}" b
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { rg_why='git 저장소가 아니다'; return 1; }
  if [ -z "$ref" ]; then
    # 로컬 main/master 우선, 없으면 원격 추적 브랜치(CI·worktree 에서 origin/* 만 있는 경우)
    for b in main master origin/main origin/master; do
      case "$b" in origin/*) git show-ref -q --verify "refs/remotes/$b" && break ;; *) git show-ref -q --verify "refs/heads/$b" && break ;; esac
      b=""
    done
    [ -n "$b" ] || { rg_why='main·master 브랜치가 없다(로컬·origin) — 기준 ref 를 인자로 준다'; return 1; }
    ref=$(git merge-base "$b" HEAD 2>/dev/null) || { rg_why="$b 와 HEAD 의 merge-base 를 구하지 못했다"; return 1; }
  fi
  rg_base=$(git rev-parse --verify -q "${ref}^{commit}" 2>/dev/null) || { rg_why="기준 ref '$ref' 를 찾지 못했다"; return 1; }
  rg_short=$(git rev-parse --short "$rg_base" 2>/dev/null)
}

_rg_unknown_line() {  # $1=사유
  printf 'SCREEN-REGRESSION: (none)  base=unknown  md=unknown  html=unknown  new-rules=unknown\n'
  printf '  [scope] %s — 비교하지 못했다(회귀 없음이 아니다)\n' "$1"
}

_rg_side() {  # $1=화면명 $2=ext → rv(값) · rb(기준 바이트) · rc(현재 바이트)
  local cur="screens/$1.$2" bf="$_rg_tmp/$1.$2"
  rv="unknown"; rb=""; rc=""
  if ! git show "$rg_base:./$cur" > "$bf" 2>/dev/null; then
    rm -f "$bf"; [ -f "$cur" ] && rv="new"; return 0
  fi
  [ -f "$cur" ] || { rv="deleted"; return 0; }
  grep -qF 'specops:screen-placeholder' "$bf" && { rv="shell"; return 0; }
  if [ "$2" = md ]; then rb=$(_md_bytes "$bf"); rc=$(_md_bytes "$cur"); else rb=$(_html_bytes "$bf"); rc=$(_html_bytes "$cur"); fi
  [ "${rb:-0}" -gt 0 ] || { rv="n/a"; return 0; }
  rv=$(awk -v a="$rc" -v b="$rb" 'BEGIN { printf "%.2f", a / b }')
}

_rg_lineage() {  # $1=ext $2=값 → 상세줄(없으면 무출력)
  case "$2" in
    new)     printf '  [lineage] .%s 이전 버전 없음 — 새 화면, 비교하지 않았다\n' "$1" ;;
    shell)   printf '  [lineage] .%s 이전 버전이 템플릿 상태 — 비교하지 않았다\n' "$1" ;;
    deleted) printf '  [lineage] .%s 기준 커밋에 있던 파일이 없다 — 삭제(또는 이름 변경)\n' "$1" ;;
    unknown) printf '  [lineage] .%s 기준·작업 트리 모두 없음 — 비교하지 않았다\n' "$1" ;;
  esac
}

_regress_one() {  # $1=화면명
  local n="$1" vm vh bm bh cm ch nr="unknown" det="" lbl
  _rg_side "$n" md;   vm="$rv"; bm="$rb"; cm="$rc"
  _rg_side "$n" html; vh="$rv"; bh="$rb"; ch="$rc"
  det="$(_rg_lineage md "$vm")${_NL}$(_rg_lineage html "$vh")"
  case "$vm" in [0-9]*) _rg_is_shrink "$cm" "$bm" "$rg_thr" && det="${det}${_NL}  [shrink] .md 본문 $bm → $cm 바이트 ($vm < $rg_thr) — 내용이 줄었다" ;; esac
  case "$vh" in [0-9]*) _rg_is_shrink "$ch" "$bh" "$rg_thr" && det="${det}${_NL}  [shrink] .html 마크업 $bh → $ch 바이트 ($vh < $rg_thr) — 내용이 줄었다" ;; esac
  # 새 위반 — 기준 사본과 현재 파일을 각각 _analyze(서브셸 — local 격리)로 계측해 rule= ID 차집합
  #   md·html 둘 다 숫자 계보일 때만 — 한쪽이 shell/new/unknown 이면 "비교하지 않았다" 와 [new-rule] 이 동시에 나온다(Phase C R3)
  case "$vm/$vh" in
    [0-9]*/[0-9]*)
      _analyze "$_rg_tmp/$n.md" "$_rg_tmp/$n.html" 2>/dev/null | sed -n 's/.*  rule=//p' | tr ',' '\n' | sort -u > "$_rg_tmp/$n.ids.base"
      _analyze "screens/$n.md" "screens/$n.html" 2>/dev/null | sed -n 's/.*  rule=//p' | tr ',' '\n' | sort -u > "$_rg_tmp/$n.ids.cur"
      lbl=$(comm -13 "$_rg_tmp/$n.ids.base" "$_rg_tmp/$n.ids.cur")
      nr=$(printf '%s\n' "$lbl" | grep -c . || true)
      for _rg_id in $lbl; do det="${det}${_NL}  [new-rule] $_rg_id — 이전 버전에 없던 위반"; done
      ;;
  esac
  printf 'SCREEN-REGRESSION: %s  base=%s  md=%s  html=%s  new-rules=%s\n' "$n" "$rg_short" "$vm" "$vh" "$nr"
  printf '%s\n' "$det" | grep -v '^$' || true
}

# ── genre: 화면 원형별 장르 규칙 (DESIGN.md §6.1 — FID 20260929-enterprise-genre-rules) ──
# 계측 규칙 ID 단일 선언 — test-design-contract 가 이 줄만 읽어 §6.1 표와 대조한다.
_GENRE_IDS='G-LIST-PAGING G-LIST-SORT G-LIST-EMPTY-KIND G-FORM-SUBMIT G-FORM-CANCEL G-WIZARD-STEP G-DASH-PERIOD'

_genre_rules() {  # $1=원형 → 계측 규칙 ID(공백 구분). rc 1 = 허용 목록 밖
  case "$1" in
    목록)      echo 'G-LIST-PAGING G-LIST-SORT G-LIST-EMPTY-KIND' ;;
    폼)        echo 'G-FORM-SUBMIT G-FORM-CANCEL' ;;
    '다단 폼') echo 'G-FORM-SUBMIT G-FORM-CANCEL G-WIZARD-STEP' ;;
    대시보드)  echo 'G-DASH-PERIOD' ;;
    상세|기타) echo '' ;;
    *) return 1 ;;
  esac
}

# States 섹션 추출 — stdin 의 md 에서 `## States`·`## 상태` 헤딩(대소문자 무시·접두 일치) 아래 다음 `## ` 앞까지.
#   states 계측과 genre(G-LIST-EMPTY-KIND 입력)가 같은 규칙을 쓰도록 한 곳에 둔다 — 한쪽만 확장하면
#   states=3/3 인데 G-LIST-EMPTY-KIND 는 미충족인 모순이 생긴다(FID 20261004-screen-lint-gaps clarify).
_states_sec() { awk 'tolower($0) ~ /^## (states|상태)/{f=1;next} f&&/^## /{exit} f'; }

# 원형 선언 줄 — 첫 `## ` 앞에서 `**원형**:`·`**원형:**`·`원형:` (앞 `- `·`> ` 허용 · 콜론 앞 공백 · 전각 콜론 `：`) 첫 줄.
_ARCH_RE='^([-*>]|[[:space:]])*([*][*])?원형([*][*])?[[:space:]]*(:|：)'
_arch_line() { awk -v re="$_ARCH_RE" '/^## /{exit} $0 ~ re {print; exit}' "$1"; }
_arch_value() { printf '%s' "$1" | sed -E "s/${_ARCH_RE}([*][*])?//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

# here-string — `set -o pipefail` 아래 `printf | grep -q` 는 grep 조기 종료로 printf 가 SIGPIPE 를 받으면
#   큰 본문에서 충족을 미충족으로 오판한다(외부 critic 지적).
_has() { grep -qiE "$2" <<<"$1"; }

# 규칙 판정 — rc 0 = 충족. 언급 여부 근사(부정문도 충족 — clarify Q2). 규칙마다 한 줄:
#   되돌려-관찰 변이가 sed 한 줄로 가능해야 한다.
_genre_check() {  # $1=ID $2=본문(override 주석 제거) $3=States 섹션
  case "$1" in
    G-LIST-PAGING)     _has "$2" '페이지네이션|페이징|무한 스크롤|pagination' && _has "$2" '총 건수|전체 건수|(총|전체) ?[0-9nN][0-9nN,]* ?건|total' ;;
    G-LIST-SORT)       _has "$2" '정렬 기준|기본 정렬|sort by|default sort|최신순|오래된순|오름차순|내림차순|으로 정렬' ;;
    G-LIST-EMPTY-KIND) _has "$3" '데이터 없음|no data' && _has "$3" '결과 없음|no results' ;;
    G-FORM-SUBMIT)     _has "$2" '제출 중|저장 중|submitting|(처리|요청|전송|로그인|등록|가입) ?중($|[][:space:].,;:!?"()]|입|이|일|인|으로|에)' && _has "$2" '비활성|disabled|중복 제출' ;;
    G-FORM-CANCEL)     _has "$2" '취소|cancel|닫기 버튼|닫기 링크|돌아가기|뒤로|(^|[^A-Za-z0-9_])close([^A-Za-z0-9_]|$)' ;;
    G-WIZARD-STEP)     _has "$2" '단계 표시|진행 단계|step indicator|(^|[^A-Za-z0-9_])stepper([^A-Za-z0-9_]|$)|스테퍼|진행 표시' && _has "$2" '이전 단계|이전 버튼|이전으로|previous|(^|[^A-Za-z0-9_])prev([^A-Za-z0-9_]|$)' && _has "$2" '임시 ?저장|중간 저장|이탈 시 보존|draft|자동 저장|(^|[^A-Za-z0-9_])autosave([^A-Za-z0-9_]|$)' ;;
    G-DASH-PERIOD)     _has "$2" '기간 선택|기간 필터|date range|조회 기간|기간 설정|기간을 선택|기간을 설정' ;;
    *) return 1 ;;
  esac
}

_genre_miss() {  # $1=ID → 빠진 요소(상세줄 문구)
  case "$1" in
    G-LIST-PAGING)     echo '페이징(또는 무한 스크롤)과 총 건수 표시' ;;
    G-LIST-SORT)       echo '기본 정렬 기준' ;;
    G-LIST-EMPTY-KIND) echo "States 에서 '데이터 없음'과 '검색·필터 결과 없음' 구분" ;;
    G-FORM-SUBMIT)     echo '제출 중 비활성(중복 제출 방지)' ;;
    G-FORM-CANCEL)     echo '취소 경로' ;;
    G-WIZARD-STEP)     echo '단계 표시 · 이전 단계 · 중간 저장(또는 이탈 시 보존)' ;;
    G-DASH-PERIOD)     echo '기간 선택' ;;
  esac
}

_gadd() {  # $1=상세줄 $2=규칙 ID(없으면 접미 없음 — 판정 불가 사유줄)
  local l="$1"
  [ -n "${2:-}" ] && l="$l  rule=$2"
  genre_det="${genre_det:+$genre_det$_NL}$l"
}

# 결과: genre · genre_det (호출자 _analyze 의 local — bash 동적 스코프)
_genre() {  # $1=md
  genre="unknown"; genre_det=""
  local why='장르 규칙을 계측하지 않았다(위반 없음이 아니다)'
  if ! _readable "$1"; then _gadd "  [genre] 화면 스펙 판독 불가 — $why"; return 0; fi
  local line val a rs r rules="" nv=0
  line=$(_arch_line "$1")
  if [ -z "$line" ]; then _gadd "  [genre] 원형 미선언 — $why" G-ARCHETYPE-UNDECLARED; return 0; fi
  val=$(_arch_value "$line")
  case "$val" in ''|\[*) _gadd "  [genre] 원형 자리표시자 그대로 — $why" G-ARCHETYPE-UNDECLARED; return 0 ;; esac
  # 복합 원형(쉼표) — 하나라도 목록 밖이면 전체 unknown (부분 계측으로 위장 금지)
  while IFS= read -r a; do
    a=$(printf '%s' "$a" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$a" ] || continue
    if ! rs=$(_genre_rules "$a"); then _gadd "  [genre] 원형 값 판독 불가: $a — $why" G-ARCHETYPE-UNDECLARED; return 0; fi
    nv=$((nv+1))
    for r in $rs; do case " $rules " in *" $r "*) ;; *) rules="$rules $r" ;; esac; done
  done <<EOF
$(printf '%s\n' "$val" | tr ',' '\n')
EOF
  [ "$nv" -gt 0 ] || { _gadd "  [genre] 원형 자리표시자 그대로 — $why" G-ARCHETYPE-UNDECLARED; return 0; }
  rules="${rules# }"
  [ -n "$rules" ] || { genre="n/a"; return 0; }

  # override — 주석 구간만 본문에서 지운다(같은 줄 다른 내용 보존 · 사유가 키워드로 새지 않게)
  #   `genre-override:` 부터 `-->` 까지를 지운다 — 다중줄·사유에 '>' 가 든 주석은 아래 단일줄 정규식이
  #   못 잡으므로(Phase C Important) 여기서 상태 추적으로 걷어내야 사유 키워드가 판정에 새지 않는다.
  local body st o id reason ovmap="" ok=0 n=0 raw=0 parsed=0
  body=$(awk '
    function strip(s,  i, j, pre, rest) {
      while ((i = index(s, "genre-override:")) > 0) {
        pre = substr(s, 1, i - 1); rest = substr(s, i)
        sub(/<!--[[:space:]]*$/, "", pre)
        j = index(rest, "-->")
        if (j == 0) { skip = 1; return pre }
        s = pre substr(rest, j + 3)
      }
      return s
    }
    skip { j = index($0, "-->"); if (j == 0) next; $0 = substr($0, j + 3); skip = 0 }
    { print strip($0) }' "$1")
  st=$(printf '%s\n' "$body" | _states_sec)
  # 판독 불가(원문 출현 수 > 단일줄 정규식 파싱 수)를 무음 통과시키지 않는다 — 원칙 5
  raw=$(grep -o 'genre-override:' "$1" 2>/dev/null | grep -c . || true)
  parsed=$(grep -oE '<!--[[:space:]]*genre-override:[^>]*-->' "$1" 2>/dev/null | grep -c . || true)
  [ "$raw" -gt "$parsed" ] && _gadd "  [genre] override 구문 판독 불가 $((raw - parsed))건 — 한 줄 주석으로 적는다(<!-- genre-override: <ID> <사유> -->)" G-OVERRIDE-INVALID
  while IFS= read -r o; do
    [ -n "$o" ] || continue
    o=$(printf '%s' "$o" | sed -E 's/^<!--[[:space:]]*genre-override:[[:space:]]*//; s/[[:space:]]*-->$//')
    id=${o%%[[:space:]]*}; reason=""
    [ "$id" = "$o" ] || reason=$(printf '%s' "${o#"$id"}" | sed 's/^[[:space:]]*//')
    case " $rules " in
      *" $id "*)
        if [ -n "$reason" ]; then ovmap="${ovmap}${id}${_TAB}${reason}${_NL}"
        else _gadd "  [genre] $id override 사유 없음 — 억제하지 않음" G-OVERRIDE-UNREASONED; fi ;;
      *) _gadd "  [genre] $id override 대상 아님 — 이 화면 원형의 계측 규칙이 아니다" G-OVERRIDE-INVALID ;;
    esac
  done <<EOF
$(grep -oE '<!--[[:space:]]*genre-override:[^>]*-->' "$1" 2>/dev/null)
EOF
  for id in $rules; do
    n=$((n+1))
    reason=$(printf '%s' "$ovmap" | awk -F"$_TAB" -v k="$id" '$1==k{print $2; exit}')
    if [ -n "$reason" ]; then ok=$((ok+1)); _gadd "  [genre] $id override — $reason" "$id"
    elif _genre_check "$id" "$body" "$st"; then ok=$((ok+1))
    else _gadd "  [genre] $id 미충족 — $(_genre_miss "$id")" "$id"; fi
  done
  genre="$ok/$n"
}

_analyze() {  # $1=md $2=html
  local md="$1" html="$2" name
  name=$(basename "$md" .md)

  # ── states: empty·loading·error 3종. 영문+한글 둘 다 인정 ──
  # 영문만 보면 한국어 문서에서 항상 0/3 이 나와 검사가 무의미해진다.
  local st=0 sec miss="" states a11y semantic token microcopy mc_total=0 genre genre_det anti anti_det
  if _readable "$md"; then
    # 종료 앵커를 `^## ` 로 두고 시작줄만 제외한다 — `/^## [^S]/` 는 후속 헤딩이 S 로
    # 시작하면(## Summary 등) 범위가 새어 다음 섹션까지 먹는다(외부 critic 지적).
    sec=$(_states_sec < "$md")
    # ★ 누락 '항목명' 을 남긴다 — 리뷰어 표는 심각도를 종류로 가른다
    #   (empty·error 미정의=Important / loading 만 누락=Minor). 비율만 내면 그 판정을
    #   계측 결과에서 도출할 수 없어 리뷰어가 md 를 재독하게 되고, 그건 추측 판정 금지 계약과 어긋난다.
    if _has "$sec" 'empty|빈 상태|빈상태|데이터 없음|결과 없음|no data|no results'; then st=$((st+1)); else miss="$miss,empty"; fi
    if _has "$sec" 'loading|로딩'; then st=$((st+1)); else miss="$miss,loading"; fi
    if _has "$sec" 'error|오류|에러'; then st=$((st+1)); else miss="$miss,error"; fi
    miss="${miss#,}"
    states="$st/3"
  else
    states="unknown"
  fi

  # ── microcopy: 에러 메시지 섹션의 무정보 문구 단독 행 ──
  if _readable "$md"; then
    # States 와 동일한 종료 앵커를 쓴다 — `/^## 에러 메시지/,0` 은 EOF 까지 열려 있어
    # 뒤따르는 섹션의 `- 오류` 같은 행까지 먹는다(States 에서 막은 것과 같은 범위 누수).
    sec=$(awk '/^## 에러 메시지/{f=1;next} f&&/^## /{exit} f' "$md")
    # 불릿(`- 오류`)과 표 데이터 행의 둘째 칸(템플릿 `| 상황 | 사용자에게 보이는 문구 | 복구 경로 |`)을 센다 — 정확 일치만.
    #   헤더(구분 행 바로 앞 줄)·구분 행·자리표시자 `[…]`·빈 칸은 분모에서도 제외한다.
    mc=$(printf '%s\n' "$sec" | awk '
      function trim(x) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", x); return x }
      /^-[ \t]*[^ \t-]/ { t = trim(substr($0, 2)); if (t !~ /^\[/) { tot++; if (t ~ /^(오류|실패|에러)$/) bad++ } ; next }
      /^[ \t]*\|/ { n++; row[n] = $0; next }
      END {
        for (i = 1; i <= n; i++) { c = row[i]; gsub(/[ \t\r|:-]/, "", c); sep[i] = (c == "") }
        for (i = 1; i <= n; i++) {
          if (sep[i] || (i < n && sep[i + 1])) continue
          m = split(row[i], f, "|"); t = trim(f[3])
          if (m < 4 || t == "" || t ~ /^\[/) continue
          tot++; if (t ~ /^(오류|실패|에러)$/) bad++
        }
        printf "%d %d", bad + 0, tot + 0
      }')
    microcopy=$(_count "${mc% *}"); mc_total=$(_count "${mc#* }")
  else
    microcopy="unknown"
  fi

  if _readable "$html"; then
    # ── a11y-label: 이름 있는 입력 수 / 입력 요소 수 ──
    local nrm
    # 주석·<script> 를 걷고 줄바꿈·탭을 공백으로 정규화 — 여러 줄 태그를 한 줄로 만든 뒤 label 열림·닫힘과 입력 태그(input·select·textarea, 커스텀 엘리먼트 <input-group> 제외, hidden·버튼형 제외)를 문서 순서대로 토큰화해 _a11y_named 가 입력별로 이름 유무를 판정한다(분자: aria-label·aria-labelledby 보유 · id 가 label for 값과 일치 · for 없는 label 이 감싼 첫 입력). 한계: ① 닫히지 않은 <script·/*(CSS 블록 주석)·<!-- 이후 입력은 집계되지 않는다(본문·속성값 안의 ' /*' 도 걸린다) ② 속성값 안의 '>' 에서 태그가 끊긴다 ③ 공백 없이 붙은 속성(<input/type=hidden>)의 hidden 제외는 좁다 ④ aria 는 속성 존재만 본다(빈 값·참조 id 실재 미검사) ⑤ 중복 id 는 모두 이름 있음으로 센다 ⑥ for 없이 형제로 놓인 <label> 은 이름이 아니다(의도된 엄격화) ⑦ fieldset·legend·title 은 이름으로 보지 않는다
    nrm=$(_strip_comments "$html" | _blocks script out | tr '\n\t' '  ')
    a11y=$(printf '%s' "$nrm" | grep -oiE '</?label([[:space:]][^>]*)?>|<(input|select|textarea)([[:space:]/][^>]*)?>' | grep -viE "^<(input|select|textarea)[^>]*[[:space:]]type[[:space:]]*=[[:space:]]*[\"']?(hidden|submit|button|reset|image)" | _a11y_named)
    # ── semantic: 랜드마크 요소 수 ──
    semantic=$(_count "$(grep -oE '<(main|nav|header|section|aside|footer)\b' "$html" | wc -l)")
    # ── token: 색 리터럴 중 `--이름:` 정의부를 뺀 하드코딩 ──
    # ★ 정의부(`--color-primary: #7C3AED;`)는 정상이다 — 실측(screens/login.html 전수):
    #   hex 12건 중 정의부 10건, 하드코딩 2건(:70 #6B7280 · :89 #6D28D9). 정의부를 빼지
    #   않으면 정상 코드 10건이 전부 위반으로 잡힌다. rgba() 등가색은 세지 않는다 — 정당한 투명도(그림자 등)까지
    #   물들이면 노이즈가 급증해 리뷰어가 검사를 무시하게 된다.
    #   ★ var 명 문자셋은 `[A-Za-z0-9-]` — `[a-z-]` 로 좁히면 `--gray-100`·`--Color-Primary`
    #     같은 scale/대문자 명명을 정의부로 못 잡아 **정상 코드가 전부 하드코딩으로 오탐**된다
    #     (실측: 정의부 3건 fixture 가 def=0 → token=4). 리뷰어 기준이 "3건 이상=Important" 라
    #     그 오탐이 곧바로 오판정이 된다.
    local all def
    all=$(_count "$(grep -oE '#[0-9A-Fa-f]{6}' "$html" | wc -l)")
    def=$(_count "$(grep -oE '\-\-[A-Za-z0-9-]+:[[:space:]]*#[0-9A-Fa-f]{6}' "$html" | wc -l)")
    token=$((all - def))
    [ "$token" -lt 0 ] && token=0
  else
    a11y="unknown"; semantic="unknown"; token="unknown"
  fi

  _genre "$md"
  _anti "$html"

  printf 'SCREEN-QUALITY: %s  states=%s  a11y-label=%s  semantic=%s  token=%s  microcopy=%s  genre=%s  anti=%s\n' \
    "$name" "$states" "$a11y" "$semantic" "$token" "$microcopy" "$genre" "$anti"

  # 상세 — 위반이 있을 때만
  case "$states" in
    0/3|1/3|2/3) printf '  [states] 미정의: %s (%s)  rule=%s\n' "${miss:-?}" "$states" "$(_states_ids "$miss")" ;;
  esac
  if [ "$a11y" != "unknown" ]; then
    local l="${a11y%%/*}" i="${a11y##*/}"
    [ "$i" -gt "$l" ] && printf '  [a11y-label] 입력 %s개 중 label %s개 — %s개 누락  rule=S-A11Y-LABEL\n' "$i" "$l" "$((i-l))"
  fi
  [ "$semantic" = "0" ] && printf '  [semantic] 랜드마크 요소 0개 — div 수프 의심  rule=S-LANDMARK\n'
  case "$token" in unknown|0) ;; *) printf '  [token] 색 리터럴 하드코딩 %s건 — var(--…) 사용 권고  rule=S-TOKEN-HEX\n' "$token" ;; esac
  case "$microcopy" in unknown|0) ;; *) printf '  [microcopy] 무정보 에러 문구 %s건 (전체 %s건) — 사용자가 무엇을 해야 하는지 쓰기  rule=S-COPY-VAGUE\n' "$microcopy" "$mc_total" ;; esac
  [ -n "$genre_det" ] && printf '%s\n' "$genre_det"
  [ -n "$anti_det" ] && printf '%s\n' "$anti_det"
  return 0
}

# 입력별 이름 판정 — stdin: label 열림·닫힘·입력 태그 토큰(1줄 1개, 문서 순서) · stdout: 이름있는입력수/입력수.
# 속성명은 대소문자 무관·값(for·id)은 대소문자 구분, 따옴표·무따옴표 모두 읽는다. gensub·구간 {n} 미사용(BSD awk·mawk 공통).
_a11y_named() {
  awk '
    function attr(tag, name,   lt, v, q, e) {
      A_FOUND = 0; A_VAL = ""
      lt = tolower(tag)
      if (!match(lt, "[ /]" name "[ ]*=[ ]*")) return
      A_FOUND = 1
      v = substr(tag, RSTART + RLENGTH)
      q = substr(v, 1, 1)
      if (q == "\"" || q == "\047") {
        v = substr(v, 2); e = index(v, q)
        A_VAL = (e > 0 ? substr(v, 1, e - 1) : v)
      } else {
        e = match(v, /[ >]/)
        A_VAL = (e > 0 ? substr(v, 1, e - 1) : v)
        sub(/\/$/, "", A_VAL)
      }
    }
    BEGIN { total = 0 }
    { t = $0; gsub(/\r/, " ", t); lt = tolower(t) }
    lt ~ /^<\/label/ { wrap = 0; next }
    lt ~ /^<label/ { wrap = 1; used = 0; attr(t, "for"); lfor = A_FOUND; forset[A_VAL] = 1; next }
    {
      total++
      first = 0
      if (wrap) { first = !used; used = 1 }
      if (lt ~ /[ \/]aria-label(ledby)?[ ]*=/) nm[total] = 1
      else if (first) { if (!lfor) nm[total] = 1 }
      attr(t, "id"); ids[total] = A_VAL
    }
    END {
      n = 0
      for (i = 1; i <= total; i++) { if (nm[i]) n++; else if (ids[i] != "") { if (ids[i] in forset) n++ } }
      print n "/" total
    }'
}

# ★ 무출력 exit 0 금지 — 리뷰어가 "위반 없음" 으로 읽는다(T1.h 가 막으려던 무음 낙관과 같은 클래스).
#   대상이 없거나 인자가 틀려도 반드시 unknown 1줄을 낸다.
_unknown_line() {  # $1=name $2=사유
  printf 'SCREEN-QUALITY: %s  states=unknown  a11y-label=unknown  semantic=unknown  token=unknown  microcopy=unknown  genre=unknown  anti=unknown\n' "$1"
  printf '  [scope] %s — 계측하지 못했다(위반 없음이 아니다)\n' "$2"
}

if [ "${1:-}" = "--rules" ]; then
  _rules_print
  exit 0
fi

if [ "${1:-}" = "--regress" ]; then
  _rg_ratio
  if ! _rg_base "${2:-}"; then
    _rg_unknown_line "$rg_why"; [ -n "$rg_cfg" ] && printf '%s\n' "$rg_cfg"; exit 0
  fi
  _rg_names=$( { for f in screens/*.md; do [ -f "$f" ] && basename "$f" .md; done
                 # core.quotePath=false — 기본값은 비ASCII 경로를 "screens/\353…" 로 인용해 sed 가 놓치고 삭제된 한글 화면이 무음이 된다(Phase C R1)
                 git -c core.quotePath=false ls-tree --name-only "$rg_base" -- screens/ 2>/dev/null | sed -n 's#^screens/\(.*\)\.md$#\1#p'; } | sort -u )
  if [ -z "$_rg_names" ]; then
    _rg_unknown_line 'screens/*.md 대상 0개 (작업 트리·기준 커밋 모두) — cwd 가 repo 루트인지 확인'
    [ -n "$rg_cfg" ] && printf '%s\n' "$rg_cfg"; exit 0
  fi
  _rg_tmp=$(mktemp -d 2>/dev/null) || { _rg_unknown_line '임시 디렉터리 생성 실패'; exit 0; }
  trap 'rm -rf "$_rg_tmp"' EXIT
  while IFS= read -r _rg_n; do
    [ -n "$_rg_n" ] && _regress_one "$_rg_n"
  done <<EOF
$_rg_names
EOF
  # 기준 == HEAD(main 위·merge 후·--regress HEAD)면 전부 1.00 이라 "회귀 없음" 과 구별되지 않는다 — 한계 고백 1줄(Phase C Q1)
  [ "$rg_base" = "$(git rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" ] \
    && printf '  [scope] 기준 커밋이 HEAD 와 같다 — 커밋된 변경은 비교되지 않는다(미커밋분만)\n'
  [ -n "$rg_cfg" ] && printf '%s\n' "$rg_cfg"
  exit 0
fi

if [ "${1:-}" = "--all" ]; then
  # cwd 상대 경로다. repo 루트 밖에서 부르면 대상 0개가 된다 — 그때도 침묵하지 않는다.
  n=0
  for f in screens/*.md; do
    [ -f "$f" ] || continue
    _analyze "$f" "${f%.md}.html"
    n=$((n+1))
  done
  [ "$n" -eq 0 ] && _unknown_line '(none)' 'screens/*.md 대상 0개 — cwd 가 repo 루트인지 확인'
  exit 0
fi

if [ $# -lt 2 ]; then
  echo "usage: check-screen-quality.sh <screen.md> <screen.html> | --all" >&2
  _unknown_line '(none)' '인자 부족'
  exit 0
fi
_analyze "$1" "$2"
exit 0
