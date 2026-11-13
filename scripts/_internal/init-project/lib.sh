#!/usr/bin/env bash
# library-only — sourced by init-project.sh
# 공용 헬퍼 9개 (init-project.sh 에서 이동)

# 입력 계층은 이 파일이 함께 올린다 — phase 함수는 lib.sh 만 source 한 호출자(테스트·design-screen.sh)에서도
#   돌아야 한다. 따로 올리게 두면 `_ask` 가 없는 채로 질문이 **조용히 빈 답**이 된다(구현 중 실측:
#   디자인 방향 2 를 고른 입력이 방향 1 로 만들어졌다 — test-design-contract P6.2).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/input.sh"

# ── 헬퍼 ─────────────────────────────────────
# repo 루트로 이동 — 이동만 책임진다(판정·에러는 _check_git 소관).
#   Phase 1~10 의 산출물 경로·git add 가 전부 cwd 상대라 루트가 아니면 엉뚱한 곳에 만들어진다.
#   호출 위치는 init-project.sh main() 의 phase_1_precheck **앞** — phases-early.sh:7 의
#   PROJECT_NAME=$(basename "$PWD") 가 _check_git 보다 먼저 계산되기 때문이다.
#   왜 -n 을 먼저 보나: `cd ""` 는 bash 에서 rc=0 이라 조용히 제자리에 머문다. 이 가드를 빼면
#   비-git 에서 빈 경로로 고지까지 출력하고 "이동한 척" 진행한다(변이 M3 로 격추 확인).
_cd_repo_root() {
  local _root _here
  _root=$(git rev-parse --show-toplevel 2>/dev/null)
  [ -n "$_root" ] || return 0                      # 비-git — _check_git 이 판정한다
  # 물리경로로 정규화한 뒤 비교한다. git 은 toplevel 을 **물리경로**로 주는데 $PWD 는 논리경로라
  #   심링크 환경(macOS /var → /private/var)에서 같은 디렉토리가 문자열로 어긋난다 — 그러면
  #   repo 루트인데도 "이동" 분기로 빠져 고지가 새어 나온다(실측 확인).
  _here=$(pwd -P)
  [ "$_root" = "$_here" ] && return 0              # 루트(worktree 루트 포함) — 무음 통과
  echo "[init] repo 루트로 이동합니다: $_root" >&2
  echo "     (현재 위치: ${_here#"$_root"/} — 부트스트랩은 repo 루트 기준)" >&2
  cd "$_root" || { echo "[init] repo 루트 이동 실패: $_root" >&2; return 1; }
}

_check_git() {
  # rev-parse 판정 — `.git` 이 **파일**인 형태(worktree·submodule)도 정상 repo 로 인식한다.
  #   `[ -d .git ]` 는 worktree 루트를 오탐 차단했다(repo 전역에서 이 관용구를 쓰던 유일한 곳).
  # 왜 `--git-dir` 가 아니라 `--is-inside-work-tree` 의 **출력** 비교인가:
  #   `.git` 내부·bare repo 에서 `--git-dir` 는 성공(rc=0)해 구 `[ -d .git ]` 이 차단하던 두
  #   위치를 통과시킨다(회귀). `--is-inside-work-tree` 는 그 두 곳에서 `false` 를 **출력**하되
  #   rc 는 0 이므로, rc 만 보면 여전히 뚫린다 — 문자열 비교가 필수다(실측·T28.h 가 격추).
  #   부트스트랩은 작업트리에 파일을 쓰므로 "작업트리 안인가" 가 올바른 질문이다.
  if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != true ]; then
    echo "git 저장소가 아닙니다. git init 을 먼저 실행하세요." >&2
    exit 1
  fi
}

# `PRD.md` 와 **대소문자만 다른** 파일(prd.md 등)이 있으면 쓰기 전에 멈춘다 — 대소문자를 구분하지 않는
#   파일시스템(macOS 기본)에서만 걸린다.
#   종전엔 `prd.md` 가 있으면 `[ -e PRD.md ]` 가 참이라 "PRD.md 보존" 으로 빠졌고, 확정한 PRD 6필드가 버려져
#   CLAUDE.md 는 `<TODO>` · FR 시드는 자리표시자였다(20261009 재현 — 명령 문서의 사용 예 그대로).
#   PRD 만 보는 이유: README·CLAUDE·DESIGN 은 대소문자가 달라도 보존 정책으로 그대로 두면 되고 잃는 것이 없다
#   (`readme.md` 는 흔한 이름이다 — 막으면 정상 저장소가 멈춘다. 독립 리뷰 지적). PRD 는 사정이 다르다:
#   기획 원문(prd.md)과 specops 형식의 산출물(PRD.md)이 서로 다른 문서인데 한 파일을 놓고 겹친다.
#   이름은 글롭으로 읽는다 — `ls` 출력은 색 설정에 따라 이스케이프가 섞인다.
_check_case_collision() {
  local e other="" exact=0
  for e in [Pp][Rr][Dd].[Mm][Dd]; do
    [ -e "$e" ] || continue
    if [ "$e" = "PRD.md" ]; then exact=1; else other="$e"; fi
  done
  [ -n "$other" ] || return 0
  # 정확한 이름(PRD.md)도 따로 있으면 구분하는 파일시스템이다 — 둘은 다른 파일이고 충돌이 아니다.
  #   구분하지 않는 파일시스템에서는 디렉토리에 이름이 하나뿐이라 exact 와 other 가 함께 서지 않는다.
  [ "$exact" = "0" ] && [ -e "PRD.md" ] || return 0
  echo "[init] ${other} 가 있습니다 — 이 파일시스템은 대소문자를 구분하지 않아 산출물 PRD.md 와 같은 파일입니다." >&2
  echo "       아무것도 쓰지 않았습니다. 둘 중 하나를 고른 뒤 다시 실행하세요:" >&2
  echo "       · 기획 원문으로 남길 파일이면 다른 이름으로 옮긴다  (예: git mv ${other} docs/prd-source.md)" >&2
  echo "         → init 이 PRD.md 를 새로 쓴다." >&2
  echo "       · 그 파일을 그대로 PRD 로 쓸 거면 이름을 맞춘다      (예: git mv ${other} PRD.md)" >&2
  echo "         → PRD.md 는 보존되고(내용을 고치지 않는다) 확정한 PRD 6필드는 CLAUDE.md·README.md·FR 시드에만 쓰인다." >&2
  exit 2
}

_check_memory() {
  # 메모·학습 기록만 있는 디렉토리는 부트스트랩이 아니다(input.sh `_memory_is_bootstrap`) — 묻지 않고 진행한다.
  if _memory_is_bootstrap; then
    if [ "${RESUME_MODE}" = "1" ]; then
      return 0
    fi
    # M2: 경고/안내·prompt·취소 결과 모두 stderr (자동화 일관성 — _check_git 와 동등)
    echo ".specops/memory/ 가 이미 존재합니다 (이미 부트스트랩됨)." >&2
    printf "재부트스트랩 진행? [y/N]: " >&2
    _ask_choice rebootstrap "재부트스트랩 진행" "n" 'y|Y|n|N' "y · n"
    case "$REPLY" in
      y|Y) ;;
      *) echo "취소됨." >&2; exit 0 ;;
    esac
  fi
}

_print_artifacts_table() {
  echo ""
  echo "산출물 현황 ($(( ${#ARTIFACTS_ROOT[@]} + ${#ARTIFACTS_MEMORY[@]} ))종):"
  local f
  for f in "${ARTIFACTS_ROOT[@]}" "${ARTIFACTS_MEMORY[@]}"; do
    if [ -e "$f" ]; then
      echo "  [✓] $f"
    else
      echo "  [✗] $f"
    fi
  done
  echo ""
}

_resolve_conflict_policy() {
  local conflicts=0 f p=""
  for f in "${ARTIFACTS_ROOT[@]}" "${ARTIFACTS_MEMORY[@]}"; do
    [ -e "$f" ] && conflicts=$((conflicts + 1))
  done
  if [ "$conflicts" -gt 0 ]; then
    if [ "${RESUME_MODE}" = "1" ]; then
      CONFLICT_POLICY="skip"
      return 0
    fi
    echo "충돌 파일 ${conflicts}개 감지."
    printf "기존 파일 처리 정책? (skip/overwrite/merge) [skip]: "
    _ask_choice conflict "기존 파일 처리 정책" "skip" 'skip|overwrite|merge' "skip · overwrite"
    p="$REPLY"
    case "$p" in
      overwrite) CONFLICT_POLICY="overwrite" ;;
      merge)     CONFLICT_POLICY="skip"; echo "⚠️  merge 정책 미구현 — skip 으로 fallback. 기존 파일은 보존됩니다." >&2 ;;
      *)         CONFLICT_POLICY="skip" ;;
    esac
  fi
}

# 토큰 치환: <TOKEN> → value (sed | 구분자, LHS 토큰 BRE 메타문자 + RHS value 의 |·& escape)
_replace_token() {
  local file="$1" token="$2" value="$3"
  local esc_token esc
  # 토큰(LHS)은 BRE 리터럴로 — . * [ ] ^ $ \ 및 구분자 | escape (`.` any-char 오매치 차단)
  esc_token=$(printf '%s' "$token" | sed 's/[].[*^$\|]/\\&/g')
  esc=$(printf '%s' "$value" | sed 's/[|&\\]/\\&/g')
  sed -i.bak "s|${esc_token}|${esc}|g" "$file" && rm -f "${file}.bak"
}

# DESIGN.md 색상 표 → screen.html :root CSS 변수 주입
#   ★ 매핑 대상은 아래 map 의 **9라벨**이다. §1 표는 17행으로 늘었으나(20260810 자산 확장)
#     이 함수는 라벨 grep 이라 신규 행을 무시한다 — 의도된 동작이다.
# 사용: _inject_design_palette <html-file>
# - DESIGN.md 부재 또는 대상 파일 부재 시 no-op (return 0)
# - 색상별 hex 검증 — 미확정(`#______` placeholder)·비hex 는 skip → 템플릿 기본값 유지
#   (Phase 6 단독 시점엔 Primary 만 확정, 나머지는 Phase 11 후 확정 — 부분 주입 안전)
# - DESIGN.md 행 라벨 ≠ CSS 변수명 (Background→--color-bg, Text Primary→--color-text) — 명시 매핑
# 공유: phases-design.sh Phase 7 + design-screen.sh 양쪽에서 호출 (DRY)
_inject_design_palette() {
  local html="$1"
  [ -f "$html" ] || return 0
  [ -f "DESIGN.md" ] || return 0
  local map="Primary|--color-primary
Secondary|--color-secondary
Background|--color-bg
Surface|--color-surface
Text Primary|--color-text
Text Secondary|--color-text-secondary
Border|--color-border
Error|--color-error
Success|--color-success"
  local label var hex
  while IFS='|' read -r label var; do
    [ -z "$label" ] && continue
    # 행 앵커 `| <label> |` — "| Primary |" 가 "| Text Primary |" 오매치 안 함
    hex=$(grep -m1 "| ${label} |" DESIGN.md 2>/dev/null \
      | grep -Eo '`#[A-Fa-f0-9]{3,6}`' | tr -d '`' | head -1)
    [ -z "$hex" ] && continue
    # `${var}: ` 의 콜론+공백이 --color-text 와 --color-text-secondary 를 분리
    sed -i.bak "s|${var}: #[A-Fa-f0-9]\{3,6\}|${var}: ${hex}|g" "$html" \
      && rm -f "${html}.bak"
  done <<< "$map"
}

# 라인 교체: prefix 가 일치하는 줄을 content 로 바꿈 (awk dynamic regex backslash 회피)
# M4 주의: 같은 prefix 가 본문에 2회 이상 등장하면 **모두** 치환. 호출 사이트는
# prefix 의 유일성을 보장해야 한다 (현재 모든 호출처는 1회만 등장하는 prefix 사용).
# 다중 매칭이 필요한 케이스가 등장하면 fence 패턴 (_rebuild_screens_table 참조) 으로 전환.
_replace_line_prefix() {
  local file="$1" prefix="$2" content="$3"
  P="$prefix" C="$content" awk '
    BEGIN { plen = length(ENVIRON["P"]) }
    substr($0, 1, plen) == ENVIRON["P"] { print ENVIRON["C"]; next }
    { print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# 충돌 시 보존 정책: 대상 파일 존재 + overwrite 가 아니면 true (보존)
# 방어 깊이: 새 정책 추가 시에도 안전 디폴트 (overwrite 만 명시 통과)
#   보존하지 않는다(=쓴다)로 판정하면 그 경로를 init 이 쓴 파일로 기록한다(`_init_mark_written`) —
#   종결 커밋이 "init 이 쓴 것"과 "사용자가 두고 있던 것"을 가르는 근거다.
_should_skip() {
  if [ -e "$1" ] && [ "$CONFLICT_POLICY" != "overwrite" ]; then
    return 0
  fi
  _init_mark_written "$1"
  return 1
}

# ── 화면 목록 표(screens-overview.md §1 fence) ─────────────────────
# fence 안 name 컬럼만 낸다 — fence 밖 예시 행·헤더를 실데이터로 세면 유령 화면이 된다.
#   start·end 가 **둘 다** 있어야 표로 본다(check-screens-overview.sh `_fence_ok` 와 같은 규칙).
_screens_table_names() {
  local file="$1"
  [ -f "$file" ] || return 0
  grep -q '^<!-- screens-table:start -->' "$file" 2>/dev/null || return 0
  grep -q '^<!-- screens-table:end -->'   "$file" 2>/dev/null || return 0
  awk '
    /^<!-- screens-table:start -->/ { inside=1; next }
    /^<!-- screens-table:end -->/   { inside=0; next }
    inside && /^\|/ {
      split($0, f, "|"); gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[2])
      if (f[2] != "name" && f[2] != "") print f[2]
    }
  ' "$file"
}

# 표 끝(끝 fence 바로 앞)에 행을 **덧붙인다** — 기존 행은 한 글자도 건드리지 않는다.
#   $1=파일 $2=목적 셀 문구 $3..=화면 이름. rc 1 = fence 가 없어 쓰지 않았다(호출부가 알린다).
#   왜 덧붙이기인가: 종전엔 표를 이름 목록으로 통째 재구성해, 손으로 채운 제목·목적(보강 표기 포함)이
#   화면 하나를 추가할 때마다 전부 초기값으로 돌아갔다(20261009 재현).
#   행은 ENVIRON 으로 넘긴다 — awk -v 는 여러 줄 값을 받지 못한다(BSD awk "newline in string").
_append_screen_rows() {
  local file="$1" cell="$2" rows="" n
  shift 2
  grep -q '^<!-- screens-table:start -->' "$file" 2>/dev/null || return 1
  grep -q '^<!-- screens-table:end -->'   "$file" 2>/dev/null || return 1
  for n in "$@"; do
    rows="${rows}| ${n} | ${n} | ${cell} | [screens/${n}.md](../../screens/${n}.md) | [screens/${n}.html](../../screens/${n}.html) |
"
  done
  ROWS="$rows" awk '
    /^<!-- screens-table:end -->/ && !done { printf "%s", ENVIRON["ROWS"]; done = 1 }
    { print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# ── init 이 커밋에 담는 범위 (Phase 10 스테이징 · init-finalize.sh 종결 커밋 공용) ──
# 왜 범위를 따로 두나: 종전엔 `git commit` 에 경로가 없어 **인덱스 전체**가 `chore(init)` 커밋에 들어갔다 —
#   미리 stage 해 둔 무관 파일(API 키가 든 notes.env) · 사용자가 고치던 README · 기존 앱의 screens/ 파일
#   (20261009 설치본 재현). 범위는 init 이 만들거나 보강하는 경로뿐이다:
#   루트 4종 · .specops/memory/ · 화면 목록에 있는 screens/<name>.{md,html} · .specops/.gitignore · session-progress.md.
INIT_HOLD_FILE=".specops/.init-hold"
INIT_WRITTEN_FILE=".specops/.init-written"
INIT_TIMING_FILE=".specops/.init-timing"

# 단계가 끝난 시각을 적는다 — `<epoch>\t<단계 이름>` 한 줄(20261113).
#   왜: /init-project 는 종결 때 진행 기록 한 줄만 남겨, 어느 단계(질문 왕복·보강·설계 리뷰)에서 시간이 가는지
#   잴 수 없었다. 무시 규칙 `.init-*` 에 걸리는 로컬 파일이고, 종결 커밋이 요약을 출력한 뒤 지운다.
#   rc 1 = 이름 형식이 아니다. .specops 가 없으면 만들지 않는다(관할은 여는 쪽만 연다) — 그때도 rc 0.
_init_mark_time() {
  printf '%s' "$1" | grep -qxE '[a-z0-9-]{1,32}' || return 1
  [ -d .specops ] && [ ! -L .specops ] || return 0
  [ ! -L "$INIT_TIMING_FILE" ] || return 0
  printf '%s\t%s\n' "$(date +%s)" "$1" >> "$INIT_TIMING_FILE" 2>/dev/null
  return 0
}
# 기록을 `<단계> <분>m<초>s` 의 나열로 낸다 — 각 값은 **앞 표시부터 그 표시까지** 걸린 시간이다. 표시가 2개 미만이면 빈 출력.
_init_timing_summary() {
  [ -f "$INIT_TIMING_FILE" ] || return 0
  NOW="$(date +%s)" awk -F'\t' '
    $1 ~ /^[0-9]+$/ && $2 != "" { n++; t[n] = $1; l[n] = $2 }
    END {
      if (n < 1) exit
      n++; t[n] = ENVIRON["NOW"]; l[n] = "finalize"
      for (i = 2; i <= n; i++) {
        d = t[i] - t[i-1]; if (d < 0) d = 0
        printf "%s%s %dm%02ds", (i > 2 ? " · " : ""), l[i], int(d / 60), d % 60
      }
      d = t[n] - t[1]; if (d < 0) d = 0
      printf " (합계 %dm%02ds)\n", int(d / 60), d % 60
    }' "$INIT_TIMING_FILE"
}

# init 이 **이번 부트스트랩에서 쓴** 파일의 기록 — `_should_skip` 이 "쓴다" 로 판정할 때 남긴다.
#   왜 필요한가: git 상태만으로는 "이전 실행이 만든 골격"과 "사용자가 만든 미커밋 파일"이 구분되지 않는다
#   (둘 다 미추적이거나 staged-new 다). 이 기록이 있으면 중단된 부트스트랩을 이어받을 때(`--resume` 이든
#   재실행이든) 이전 실행의 골격은 커밋하고, 사용자의 파일은 보류할 수 있다.
#   실행을 넘어 누적되고, 종결 커밋이 성공하면 지운다.
_init_mark_written() {
  mkdir -p .specops 2>/dev/null || return 0
  _init_written "$1" || printf '%s\n' "$1" >> "$INIT_WRITTEN_FILE" 2>/dev/null
  return 0
}
_init_written() {
  [ -f "$INIT_WRITTEN_FILE" ] && grep -qxF -- "$1" "$INIT_WRITTEN_FILE"
}
# 기록이 **아직 유효한가** — HEAD 에 이미 있는 경로의 기록은 믿지 않는다.
#   skip 정책에서 init 은 없던 경로만 쓰므로, 기록된 경로가 HEAD 에 있다면 그 뒤에 커밋이 있었다는 뜻이다
#   (사용자가 종결 스크립트 대신 손으로 커밋한 경우 — 기록은 남는다). 그 뒤의 수정분은 사용자의 것이다.
_init_written_fresh() {
  _init_written "$1" || return 1
  git cat-file -e "HEAD:$1" 2>/dev/null && return 1
  return 0
}

# 보존하는 기존 파일 중 **미커밋 내용이 있는 사용자 파일**을 기록한다 — 커밋에 쓸어 담지 않기 위해서다.
#   ① 정본 산출물 자리에 이미 있는 파일(skip 정책으로 보존)이고, init 이 쓴 기록이 없고, git 상태가 깨끗하지
#      않으면(미추적·staged·수정) 보류한다. 깨끗한 추적 파일은 커밋할 것이 없으니 대상이 아니다.
#   ② memory/ 의 그 밖의 파일과 화면 파일은 HEAD 대비 수정분(--diff-filter=M)만 보류한다 — 진행 중 FID 의
#      미커밋 설계 수정이 여기 해당한다. 미추적 파일(브레인스토밍 메모·원장)은 memory 정책대로 커밋한다.
#   overwrite 정책이면 기록하지 않는다 — 덮어쓴 파일은 init 의 산출물이다(사용자가 고른 결과).
#   session-progress.md 는 범위 밖 — 훅이 세션마다 덧붙이는 specops 기록이고 종결 커밋이 한 줄을 더한다.
#   기록은 실행마다 새로 쓰고, 종결 커밋이 성공하면 지운다.
_init_hold_scan() {
  rm -f "$INIT_HOLD_FILE" 2>/dev/null
  [ "$CONFLICT_POLICY" != "overwrite" ] || return 0
  local held="" f m
  for f in "${ARTIFACTS_ROOT[@]}" "${ARTIFACTS_MEMORY[@]}" .specops/memory/api-spec-consumer.md; do
    [ -e "$f" ] || continue
    _init_written_fresh "$f" && continue
    [ -n "$(git status --porcelain -- "$f" 2>/dev/null)" ] && held="${held}${f}
"
  done
  if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      _init_written_fresh "$m" || held="${held}${m}
"
    done <<EOF
$(git diff -z --name-only --diff-filter=M HEAD -- .specops/memory 'screens/*.md' 'screens/*.html' 2>/dev/null | tr '\0' '\n')
EOF
  fi
  held=$(printf '%s' "$held" | grep . | sort -u || true)
  [ -n "$held" ] || return 0
  mkdir -p .specops
  printf '%s\n' "$held" > "$INIT_HOLD_FILE"
  # 앞줄이 줄바꿈 없는 프롬프트일 수 있어(충돌 정책 질문) 빈 줄로 끊는다
  echo "" >&2
  echo "→ 미커밋 내용이 있는 기존 파일은 init 커밋에 넣지 않습니다: $(printf '%s' "$held" | tr '\n' ' ')" >&2
}

_init_held() {
  [ -f "$INIT_HOLD_FILE" ] && grep -qxF -- "$1" "$INIT_HOLD_FILE"
}

# 화면 목록의 이름 중 파일명으로 쓸 수 있는 것만 낸다(영숫자/-/_ 1~64 — Phase 7·design-screen 과 같은 규칙).
#   손으로 고친 표에 `../x` 같은 이름이 있으면 git 이 경로 오류를 내고, 그 오류가 "커밋 대상 없음"으로
#   둔갑한다(독립 리뷰 재현) — 범위에 넣기 전에 거른다.
_init_screen_names() {
  local n
  while IFS= read -r n; do
    [[ "$n" =~ ^[A-Za-z0-9_-]{1,64}$ ]] && printf '%s\n' "$n"
  done <<EOF
$(_screens_table_names .specops/memory/screens-overview.md)
EOF
  return 0
}

# 범위 안의 경로를 stage 한다. 경로마다 따로 add 한다 — 하나가 무시 규칙에 걸려 실패해도 나머지는 들어간다.
#   screens/ 는 디렉토리째 넣지 않는다: 화면 목록에 있는 이름의 .md·.html 만이다.
_init_stage_own() {
  local f n
  local -a excl=()
  # memory/ 안의 보류 파일만 제외 인자로 만든다. 디렉토리 **밖** 경로를 `:(exclude)` 로 섞으면
  #   git 은 rc=0 으로 **아무것도 stage 하지 않는다**(git 2.50 실측 — README 가 보류되자 memory/ 전체가 빠졌다).
  if [ -f "$INIT_HOLD_FILE" ]; then
    while IFS= read -r f; do
      case "$f" in .specops/memory/?*) excl+=(":(exclude,literal)$f") ;; esac
    done < "$INIT_HOLD_FILE"
  fi
  for f in "${ARTIFACTS_ROOT[@]}"; do
    [ -f "$f" ] && ! _init_held "$f" && git add -- "$f" 2>/dev/null
  done
  # memory/ 는 디렉토리 단위 — 조건부 산출물(api-spec-consumer.md 등 정본 배열 밖)과 삭제·개명을 함께 담는다.
  #   `${excl[@]+…}` — bash 3.2 는 set -u 에서 빈 배열 전개를 unbound 로 본다.
  [ -d .specops/memory ] && git add -- .specops/memory ${excl[@]+"${excl[@]}"} 2>/dev/null
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    for f in "screens/${n}.md" "screens/${n}.html"; do
      [ -f "$f" ] && ! _init_held "$f" && git add -- "$f" 2>/dev/null
    done
  done <<EOF
$(_init_screen_names)
EOF
  for f in .specops/.gitignore .specops/session-progress.md; do
    [ -f "$f" ] && git add -- "$f" 2>/dev/null
  done
  return 0
}

# 범위 안에서 staged 인 경로를 줄단위로 낸다(보류 기록 제외) — 종결 커밋의 경로 인자이자 건수의 출처다.
#   rc 2 = git 이 판정하지 못했다. 호출부는 이것을 "대상 없음"으로 읽지 않는다.
#   --no-renames: 개명을 새 이름 한 줄로 접으면 옛 경로의 삭제가 커밋에서 빠진다.
#   -z: 따옴표·제어문자가 든 이름을 git 이 "…" 로 감싸면 그 문자열은 경로 인자로 다시 쓸 수 없다.
_init_staged_own() {
  local f n out
  local -a scope=("${ARTIFACTS_ROOT[@]}" .specops/memory .specops/.gitignore .specops/session-progress.md)
  while IFS= read -r n; do
    [ -n "$n" ] && scope+=("screens/${n}.md" "screens/${n}.html")
  done <<EOF
$(_init_screen_names)
EOF
  out=$(git diff -z --cached --name-only --no-renames -- "${scope[@]}" 2>/dev/null | tr '\0' '\n'
        exit "${PIPESTATUS[0]}") || return 2
  while IFS= read -r f; do
    [ -n "$f" ] && ! _init_held "$f" && printf '%s\n' "$f"
  done <<EOF
$out
EOF
  return 0
}

# numbered list 의 N 번 항목 추출
#
# 두 형식을 모두 받는다 (20260806 실측 결함 수정):
#   라벨형  `1. 한 줄 설명: 사내 일정 관리`  → "사내 일정 관리"   (프롬프트가 보여주는 형식)
#   무라벨형 `1. 사내 일정 관리`             → "사내 일정 관리"   (Phase 0 파이프의 자연 형식)
#
# 구 구현은 `[0-9]+\.[^:]*:` 를 **한 덩어리로** 요구해 무라벨형이면 sub 가 통째로 실패했다
#   → 값에 "1. " 가 남은 채 PRD.md §1 · CLAUDE.md · README.md · requirements.md FR 시드행까지
#     전파(실측). `_phase_4_count_filled` 는 "비어있지 않음"만 세므로 fallback 도 안 깨어난다.
# 또 하나: 라벨 길이 무제한(`[^:]*:`)이라 값 중간에 콜론이 늦게 나오는 긴 문장이면
#   콜론 앞 전체를 라벨로 오인해 잘라냈다 (실측: 60자 손실).
#
# 그래서 ① 번호 접두는 **무조건** 제거 ② 라벨 제거는 콜론이 앞쪽(≤40바이트)에 있을 때만.
#   interval 정규식 `{1,40}` 은 구형 awk 비호환이라 index() 로 판정한다(이식성).
#
# ⚠️ LC_ALL=C 필수 — `index()` 의 단위가 로케일·구현에 따라 다르다:
#   awk(BWK, macOS) → **바이트** · gawk(UTF-8 로케일, 대부분의 Linux) → **문자**
#   한글은 UTF-8 에서 3바이트라 같은 문자열이 102 vs 40 으로 갈린다(실측).
#   임계 40 은 **바이트** 기준으로 설계됐으므로(라벨은 짧다 ≈ 한글 13자) 단위를 고정한다.
#   미고정 시 gawk 에서 40 이하로 계산돼 **긴 문장의 콜론 앞이 라벨로 오인·절단**된다 —
#   macOS 로컬은 green 인데 Linux CI 만 red 가 되는 형태로 나타난다
#   (20260807 실측: T-pn.e 가 gawk index=40 으로 경계에 정확히 걸렸다).
_parse_numbered() {
  local raw="$1" num="$2"
  printf '%s\n' "$raw" | LC_ALL=C awk -v n="$num" '
    BEGIN { pat = "^[[:space:]]*" n "\\." }
    $0 ~ pat {
      sub(/^[[:space:]]*[0-9]+\.[[:space:]]*/, "")
      c = index($0, ":")
      if (c > 0 && c <= 40) {
        $0 = substr($0, c + 1)
        sub(/^[[:space:]]+/, "")
      }
      print
      exit
    }'
}

_check_brainstorming() {
  local bm_files
  bm_files=$(ls -t .specops/memory/brainstorming-*.md 2>/dev/null | head -3)
  if [ -n "$bm_files" ]; then
    echo ""
    echo "브레인스토밍 메모 발견 (Phase 0에서 이미 확인했다고 가정 — 재질문 생략):"
    echo "$bm_files" | sed 's/^/  /'
    BM_REF="y"
  fi
}
