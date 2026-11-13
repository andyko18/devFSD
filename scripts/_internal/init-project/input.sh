#!/usr/bin/env bash
# library-only — sourced by init-project.sh
# 입력 계층(답변 파일·stdin) · 프로젝트 종류 기록 · 답변 파일 사전 점검

# ── 입력 계층 — 질문 하나에 답 하나를 받는 유일한 통로 ─────────────
# 왜: 이 마법사는 질문을 stdin 에서 **순서대로** 읽는데, 실제 호출자(Claude Code 의 Bash 도구)는 터미널이 아니다.
#   질문 수는 종류·기존 파일·메모 유무로 달라지므로 답이 한 줄만 밀려도 전부 어긋났고, 모자란 답은 `read … || true`
#   가 기본값으로 덮어 rc=0 으로 끝났다(20261009 설치본 재현 · 실기록 2건에서 호출자가 스크립트 원문을 읽어 순서를
#   알아냈다). 그래서 통로를 하나로 모으고 두 가지를 한다:
#   ① 답변 파일 모드(`--answers <파일>`) — 순서가 아니라 **키**로 답한다. 빠진 키·잘못된 값은 쓰기 전에 전부 알린다.
#   ② stdin 모드는 그대로 두되(터미널 사용·기존 호출자), 터미널이 아닐 때 입력이 바닥나거나 선택지가 아닌 값이
#      들어오면 기본값으로 이어 가지 않고 rc=2 로 멈춘다.
ANSWERS_FILE="${ANSWERS_FILE:-}"
ANSWER_KEYS="kind rebootstrap conflict principles principle.1 principle.2 principle.3 principle.4 principle.5 prd.oneline prd.persona prd.values prd.m1 prd.m2 prd.m3 design screens db api api.consumer"

# 비대화인가 — 답변 파일 모드이거나 stdin 이 터미널이 아니다.
_noninteractive() {
  [ -n "$ANSWERS_FILE" ] || [ ! -t 0 ]
}

# 터미널을 **실제로 열 수 있는가**. `/dev/tty` 의 존재만 보면 안 된다 — 존재하지만 열 수 없는 환경이 있다
#   (Claude Code 의 Bash 도구 · CI). SPECOPS_INIT_NO_TTY=1 은 "터미널 없음"으로 고정한다(자동화·테스트).
_tty_ok() {
  [ "${SPECOPS_INIT_NO_TTY:-0}" != "1" ] || return 1
  { : < /dev/tty; } 2>/dev/null
}

# 답변 파일에서 키의 값을 낸다(첫 `=` 뒤 전부 · 앞뒤 공백과 CR 제거). rc 1 = 키 없음.
#   키는 줄 맨 앞에서 완전 일치로 찾는다 — 정규식이 아니라 문자열 비교다(키에 `.` 이 있다).
_ans_get() {
  [ -n "$ANSWERS_FILE" ] && [ -f "$ANSWERS_FILE" ] || return 1
  # `키 = 값` 처럼 `=` 앞뒤에 공백을 둔 줄도 같은 키다 — 손으로 쓴 설정 파일에서 흔한 표기다.
  #   종전엔 이 줄이 "모르는 키: kind " 와 "빠짐: kind" 로 함께 나와 원인(공백)을 알 수 없었다.
  K="$1" awk '
    BEGIN { k = ENVIRON["K"] }
    {
      i = index($0, "="); if (i == 0) next
      key = substr($0, 1, i - 1); sub(/^[ \t]+/, "", key); sub(/[ \t]+$/, "", key)
      if (key != k) next
      v = substr($0, i + 1)
      sub(/\r$/, "", v); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      print v; found = 1; exit
    }
    END { exit(found ? 0 : 1) }
  ' "$ANSWERS_FILE"
}
_ans_has() {
  _ans_get "$1" >/dev/null 2>&1
}

# 비대화 입력 오류로 멈춘다(rc 2). 기본값으로 이어 가지 않는 것이 계약이다.
_stop_input() {
  echo "" >&2
  echo "[init] $1" >&2
  echo "       기본값으로 이어 가지 않습니다. 이 실행이 이미 만든 파일은 그대로 남습니다(stage·커밋 전) —" >&2
  echo "       밀린 답으로 만들어졌을 수 있으니 확인해 지우고 다시 실행하거나, 맞으면 --resume 으로 이어 가세요." >&2
  echo "       질문 순서에 기대지 않으려면 --answers <파일> 을 쓰세요 (키 목록: --answers-template)." >&2
  exit 2
}

# 답 하나를 REPLY 에 받는다. $1=키 $2=질문 이름(오류 문구용)
#   답변 파일 모드: 키가 없으면 멈춘다(사전 점검이 먼저 잡지만, 점검과 질문이 어긋났을 때의 마지막 방어선이다).
#   stdin 모드: 터미널이 아닌데 입력이 끝났으면 멈춘다. 빈 줄은 "기본값"이라는 **명시적인 답**이라 그대로 받는다.
_ask() {
  REPLY=""
  if [ -n "$ANSWERS_FILE" ]; then
    REPLY=$(_ans_get "$1") || _stop_input "답변 파일에 '$1' 이 없습니다 ($2)."
    return 0
  fi
  if ! read -r REPLY; then
    [ -n "$REPLY" ] && return 0     # 마지막 줄에 개행이 없었다 — 내용은 읽혔다
    [ -t 0 ] && return 0            # 터미널에서 Ctrl-D — 빈 답으로 본다
    _stop_input "입력이 '$2' 질문에서 끝났습니다 (답이 모자랍니다)."
  fi
  return 0
}

# 선택지 질문. $1=키 $2=질문 이름 $3=빈 답일 때 값 $4=허용 값 ERE(전체 일치) $5=허용 값 설명
#   선택지가 아닌 값은 답이 밀렸다는 가장 확실한 신호다 — 비대화면 멈추고, 터미널이면 다시 묻는다.
_ask_choice() {
  while :; do
    _ask "$1" "$2"
    if [ -z "$REPLY" ]; then
      REPLY="$3"
      return 0
    fi
    printf '%s' "$REPLY" | grep -qxE -- "$4" && return 0
    if _noninteractive; then
      _stop_input "'$2' 에 선택지가 아닌 값이 들어왔습니다: '${REPLY}' (허용: $5) — 답이 한 줄 밀렸을 수 있습니다."
    fi
    printf "  허용 값: %s — 다시 입력: " "$5"
  done
}

# ── 프로젝트 종류 기록 ─────────────────────────────────────────────
# 왜: 종류를 어디에도 적지 않아 뒤 단계가 파일 존재와 자유 서술로 추정했다 — CLI 로 init 한 직후 foundation
#   필수 판정이 FAIL 이었고, 답 없이 `--resume` 하면 풀스택으로 잡혀 CLI 저장소에 풀스택 파일이 생겼다.
#   project-context.md 머리에 주석 한 줄로 적는다(읽는 쪽: 이 파일의 `_recorded_kind` · foundation-kind.sh).
_recorded_kind() {
  local f=".specops/memory/project-context.md"
  [ -f "$f" ] || return 0
  sed -n 's/^<!-- specops:project-kind: \([1-6]\)[^0-9].*/\1/p' "$f" 2>/dev/null | head -1
}

_record_kind() {
  local f=".specops/memory/project-context.md" line
  [ -f "$f" ] || return 0
  case "$PROJECT_KIND" in [1-6]) ;; *) return 0 ;; esac
  [ "$(_recorded_kind)" = "$PROJECT_KIND" ] && return 0
  line="<!-- specops:project-kind: ${PROJECT_KIND} ($(_kind_label "$PROJECT_KIND")) -->"
  if grep -q '^<!-- specops:project-kind: ' "$f"; then
    L="$line" awk '/^<!-- specops:project-kind: / && !d { print ENVIRON["L"]; d = 1; next } { print }' \
      "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
  else
    # 머리의 **한 줄 주석** 묶음 바로 뒤에 넣는다. 그 형태가 아니면(여러 줄 주석·frontmatter 로 시작하는 파일 —
    #   손으로 고쳤거나 보강이 구조를 바꾼 경우) 끼워 넣지 않고 파일 끝에 붙인다: 주석 안이나 frontmatter 위에
    #   넣으면 바깥 구조가 깨진다(독립 리뷰 재현). 읽는 쪽은 줄 위치를 가리지 않는다.
    L="$line" awk '
      NR == 1 && $0 !~ /^<!--.*-->[[:space:]]*$/ { tail = 1 }
      !tail && !d && $0 !~ /^<!--.*-->[[:space:]]*$/ { print ENVIRON["L"]; d = 1 }
      { print }
      END { if (!d) print ENVIRON["L"] }
    ' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
  fi
}

# `.specops/memory/` 가 **부트스트랩 산출물**을 담고 있는가. 브레인스토밍 메모와 학습 기록만 있으면 아니다 —
#   둘은 init 전에 생긴다(/brainstorming · 자유작업 기록). 종전엔 디렉토리 존재만 봐서 메모가 먼저 있으면
#   "이미 부트스트랩됨" 질문이 떴고, 첫 답이 거기 소비돼 "취소됨" rc=0 · 산출물 0 으로 끝났다(권장 흐름 그대로).
_memory_is_bootstrap() {
  [ -d .specops/memory ] || return 1
  local f
  # 숨김 파일은 보지 않는다 — `.DS_Store`·`.gitkeep` 은 산출물이 아니다(산출물은 전부 보이는 이름이다).
  for f in .specops/memory/*; do
    [ -e "$f" ] || continue
    case "${f##*/}" in
      brainstorming-*.md|learnings.jsonl) ;;
      *) return 0 ;;
    esac
  done
  return 1
}

# ── 답변 파일 사전 점검 — 아무것도 쓰기 전에 빠진 키·잘못된 값을 **전부** 알린다 ──
#   조건은 각 Phase 의 질문 조건과 같아야 한다(test-init-project T33.a 가 종류 1~6 으로 잠근다:
#   `kind` 만 주고 → 알려 준 키만 채우면 → 완주). 어긋나면 `_ask` 가 마지막 방어선으로 멈춘다.
PF_ERRS=""
_pf_need() {  # $1=키 $2=설명 $3=허용 ERE(빈 문자열=자유 값) $4=허용 설명 $5=1 이면 빈 값 허용
  local v
  if ! v=$(_ans_get "$1"); then
    PF_ERRS="${PF_ERRS}  - 빠짐: $1 — $2
"
    return 1
  fi
  if [ -z "$v" ]; then
    [ "${5:-0}" = "1" ] && return 0
    PF_ERRS="${PF_ERRS}  - 빠짐: $1 — $2 (값이 비어 있음)
"
    return 1
  fi
  if [ -n "$3" ] && ! printf '%s' "$v" | grep -qxE -- "$3"; then
    PF_ERRS="${PF_ERRS}  - 잘못된 값: $1=${v} (허용: $4)
"
    return 1
  fi
  return 0
}

_answers_preflight() {
  local line k kind="" policy="skip" rec n i f s seen=" "
  if [ ! -f "$ANSWERS_FILE" ] || [ ! -r "$ANSWERS_FILE" ]; then
    echo "[init] 답변 파일을 읽을 수 없습니다: $ANSWERS_FILE" >&2
    exit 2
  fi
  PF_ERRS=""
  # BOM 이 붙으면 첫 키가 "모르는 키"이자 "빠짐"으로 함께 나와 원인을 알 수 없다 — 먼저 말한다.
  if [ "$(head -c 3 "$ANSWERS_FILE" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
    echo "[init] 답변 파일 앞에 BOM 이 있습니다 — BOM 없는 UTF-8 로 저장한 뒤 다시 실행하세요: $ANSWERS_FILE" >&2
    exit 2
  fi
  # ① 형식·모르는 키 (오타가 조용히 무시되지 않게)
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    # 들여쓴 주석과 공백만 있는 줄도 건너뛴다 — _ans_get 이 그렇게 읽는다(둘이 다르면 값은 읽히는데 형식 오류가 난다).
    k=${line#"${line%%[![:space:]]*}"}
    case "$k" in ''|'#'*) continue ;; esac
    case "$line" in
      *=*) ;;
      *) PF_ERRS="${PF_ERRS}  - 형식 오류: '${line}' (키=값 이어야 합니다)
"; continue ;;
    esac
    k=${line%%=*}
    k=${k#"${k%%[![:space:]]*}"}; k=${k%"${k##*[![:space:]]}"}   # 키 앞뒤 공백은 키의 일부가 아니다(_ans_get 과 같은 규칙)
    case " $ANSWER_KEYS " in
      *" $k "*) ;;
      *) PF_ERRS="${PF_ERRS}  - 모르는 키: '${k}'
" ;;
    esac
    # 같은 키가 두 번이면 첫 줄만 쓰이고 뒤 줄은 조용히 버려진다 — 고친 줄이 무시되는 사고를 막는다.
    case "$seen" in
      *" $k "*) PF_ERRS="${PF_ERRS}  - 중복된 키: '${k}' (한 번만 적으세요 — 첫 줄만 쓰입니다)
" ;;
      *) seen="${seen}${k} " ;;
    esac
  done < "$ANSWERS_FILE"
  # ② 재부트스트랩 — 가장 먼저 본다. `n` 이면 Phase 1 에서 취소로 끝나므로 나머지 키(종류 포함)는 쓰이지 않는다.
  if [ "$RESUME_MODE" != "1" ] && _memory_is_bootstrap; then
    if _pf_need rebootstrap "이미 부트스트랩된 저장소에서 다시 진행할지 (이어받기는 --resume)" 'y|Y|n|N' "y · n"; then
      case "$(_ans_get rebootstrap)" in n|N) _pf_report; return 0 ;; esac
    fi
  fi
  # ③ 종류 — --resume 이고 기록이 있으면 생략할 수 있다(빈 값 `kind=` 도 생략으로 본다)
  rec=$(_recorded_kind)
  if [ "$RESUME_MODE" = "1" ] && [ -n "$rec" ] && [ -z "$(_ans_get kind 2>/dev/null)" ]; then
    kind="$rec"
  elif _ans_has kind; then
    _pf_need kind "프로젝트 종류" '[1-6]' "1~6" && kind=$(_ans_get kind)
  else
    PF_ERRS="${PF_ERRS}  - 빠짐: kind — 프로젝트 종류 (1 Web/UI · 2 백엔드/API · 3 CLI/라이브러리 · 4 풀스택 · 5 모바일 · 6 기타)
"
  fi
  # 충돌 정책 — --resume 이 아니고 산출물이 이미 있을 때만 묻는다
  if [ "$RESUME_MODE" != "1" ]; then
    for f in "${ARTIFACTS_ROOT[@]}" "${ARTIFACTS_MEMORY[@]}"; do
      if [ -e "$f" ]; then
        _pf_need conflict "이미 있는 산출물 처리 (skip=보존 · overwrite=덮어쓰기)" 'skip|overwrite' "skip · overwrite" \
          && policy=$(_ans_get conflict)
        break
      fi
    done
  fi
  # ④ 산출물별 — "이번에 쓰는 파일"의 질문만 필요하다
  if _pf_writes .specops/memory/constitution.md "$policy"; then
    # principles=skip · principle.1=skip(stdin 모드와 같은 뜻) · principle.1~5 중 하나여야 한다.
    #   빈 `principles=` 는 "안 적었다"로 본다 — 템플릿의 빈 줄을 둔 채 principle.N 을 적어도 된다.
    s=$(_ans_get principles 2>/dev/null || true)
    if [ "$s" = "skip" ] || [ "$(_ans_get principle.1 2>/dev/null)" = "skip" ]; then
      :
    elif [ -n "$s" ]; then
      PF_ERRS="${PF_ERRS}  - 잘못된 값: principles=${s} (허용: skip — 원칙을 적으려면 principle.1~principle.5)
"
    elif _ans_has principle.1; then
      for i in 1 2 3 4 5; do _pf_need "principle.$i" "헌법 원칙 $i 이름" "" ""; done
    else
      PF_ERRS="${PF_ERRS}  - 빠짐: principles — 헌법 원칙 (skip, 또는 principle.1~principle.5 다섯 줄)
"
    fi
  fi
  if _pf_writes PRD.md "$policy"; then
    _pf_need prd.oneline "PRD 한 줄 설명" "" ""
    _pf_need prd.persona "PRD 주요 페르소나" "" ""
    if _pf_need prd.values "PRD 가치제안 (콤마로 3개)" "" ""; then
      # 정확히 3개 — 모자라면 PRD 에 자리표시자가 남고, 넘치면 넷째부터 조용히 버려진다(Phase 4 가 앞 3개만 쓴다).
      n=$(_ans_get prd.values | awk -F',' '{ c = 0; for (i = 1; i <= NF; i++) { x = $i; gsub(/^[ \t]+|[ \t]+$/, "", x); if (x != "") c++ } printf "%d/%d", c, NF }')
      if [ "${n%%/*}" != "${n##*/}" ]; then
        PF_ERRS="${PF_ERRS}  - 잘못된 값: prd.values — 빈 항목이 있습니다(콤마가 겹치거나 끝에 붙었습니다). 콤마로 구분한 3개를 적으세요
"
      elif [ "$n" != "3/3" ]; then
        PF_ERRS="${PF_ERRS}  - 잘못된 값: prd.values — 콤마로 구분한 3개가 필요합니다(지금 ${n%%/*}개)
"
      fi
    fi
    _pf_need prd.m1 "PRD 마일스톤 M1" "" ""
    _pf_need prd.m2 "PRD 마일스톤 M2" "" ""
    _pf_need prd.m3 "PRD 마일스톤 M3" "" ""
  fi
  case "$kind" in
    1|4|5)
      if _pf_writes DESIGN.md "$policy"; then
        n=$(_design_directions | grep -c . || true)
        if [ "${n:-0}" -gt 0 ] && _pf_need design "디자인 방향 번호 (1~${n} — templates/design-directions.md)" '[0-9]{1,3}' "1~${n}"; then
          i=$(_ans_get design)
          { [ "$i" -ge 1 ] && [ "$i" -le "$n" ]; } 2>/dev/null \
            || PF_ERRS="${PF_ERRS}  - 잘못된 값: design=${i} (허용: 1~${n})
"
        fi
      fi
      if _pf_need screens "초기 화면 이름 (콤마 구분 · 없으면 빈 값 'screens=')" "" "" 1; then
        # 줄 단위로 나눠 읽는다 — 단어 분리에 맡기면 `*` 같은 값이 파일 이름으로 펼쳐진다
        while IFS= read -r s; do
          [ -n "$s" ] || continue
          [[ "$s" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || PF_ERRS="${PF_ERRS}  - 잘못된 값: screens 의 '${s}' (허용: 영숫자/-/_ 1~64자)
"
        done <<EOF
$(_ans_get screens | tr ', ' '\n\n')
EOF
      fi
      ;;
  esac
  if [ -n "$kind" ]; then
    _pf_writes .specops/memory/data-model.md "$policy" \
      && _pf_need db "DB 사용 여부 (서버 DB·클라이언트 영속 포함)" 'y|Y|n|N|skip' "y · n"
    case "$kind" in 2|4|6)   # 기타(6)도 API 를 가질 수 있다 — 8f 와 같은 조건이어야 한다(T33.a 가 잠근다)
      _pf_writes .specops/memory/api-spec.md "$policy" \
        && _pf_need api "API 정의 방식 (1 Markdown · 2 OpenAPI · 3 GraphQL · 4 RPC · 5 만들지 않음)" '[1-5]' "1~5" ;;
    esac
    case "$kind" in 1|5)
      _pf_writes .specops/memory/api-spec-consumer.md "$policy" \
        && _pf_need api.consumer "외부 API 소비 계약 문서 작성 여부" 'y|Y|n|N' "y · n" ;;
    esac
  fi
  _pf_report
}

# 이번 실행이 그 파일을 쓰는가 — `_should_skip` 의 판정만 빌린다(기록은 남기지 않는다).
_pf_writes() {
  [ ! -e "$1" ] || [ "$2" = "overwrite" ]
}

_pf_report() {
  [ -n "$PF_ERRS" ] || return 0
  echo "[init] 답변 파일을 그대로 쓸 수 없습니다 — 아무것도 쓰지 않았습니다: $ANSWERS_FILE" >&2
  printf '%s' "$PF_ERRS" >&2
  echo "       위 항목을 고친 뒤 같은 명령으로 다시 실행하세요 (키 목록·설명: --answers-template)." >&2
  exit 2
}

# 답변 파일의 키 목록과 설명 — 호출자가 스크립트 원문을 읽지 않고도 쓸 수 있게 한다.
_answers_template() {
  local n
  n=$(_design_directions | grep -c . || true)
  cat <<EOF
# /init-project 답변 파일 — 키=값 (순서 무관 · '#' 로 시작하는 줄은 주석)
# 실행: bash init-project.sh --answers <이 파일> "<프로젝트명>"   (이어받기는 --resume 추가)
# 빠진 키·잘못된 값이 있으면 아무것도 쓰지 않고 rc=2 로 전부 알려 준다. 해당 없는 키는 있어도 쓰이지 않는다.

# 프로젝트 종류 — 1 Web/UI · 2 백엔드/API · 3 CLI/라이브러리 · 4 풀스택 · 5 모바일 · 6 기타
#   (--resume 이고 종류가 이미 기록돼 있으면 비워 두거나 생략 가능)
kind=

# 값이 비어 있는 키는 "빠짐"으로 본다 — 사용자가 정한 값만 적는다(기본값을 지어 넣지 않는다).

# 헌법 원칙 — principles=skip(나중에 채움), 또는 이 줄을 지우고 principle.1~principle.5 다섯 줄
principles=
# principle.1=
# principle.2=
# principle.3=
# principle.4=
# principle.5=

# PRD 6필드 — PRD.md 를 새로 만들 때 필요
prd.oneline=
prd.persona=
# 가치제안은 콤마로 3개
prd.values=
prd.m1=
prd.m2=
prd.m3=

# 디자인 방향 번호${n:+ 1~${n}} (templates/design-directions.md) — 종류 1·4·5
design=
# 초기 화면 이름, 콤마 구분(영숫자/-/_). 없으면 빈 값 그대로 — 종류 1·4·5
screens=

# DB 사용 여부 y/n (서버 DB·localStorage/IndexedDB 포함)
db=
# API 정의 방식 — 1 Markdown · 2 OpenAPI · 3 GraphQL · 4 RPC · 5 만들지 않음 — 종류 2·4·6
#   (종류 1·5 는 프론트만이다 — 백엔드를 함께 만들면 종류 4 로 고른다. 기타(6)는 API 가 없으면 5)
api=
# 외부 API 소비 계약 문서 작성 여부 y/n — 종류 1·5
api.consumer=

# 이미 부트스트랩된 저장소에서 --resume 없이 다시 실행할 때만 필요
# rebootstrap=y
# 산출물 파일이 이미 있을 때만 필요 — skip(보존) 또는 overwrite(덮어쓰기)
# conflict=skip
EOF
}
