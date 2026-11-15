#!/usr/bin/env bash
# library-only — sourced by init-project.sh
# phase_5~7 (CLAUDE/DESIGN/screens) — init-project.sh 에서 이동

phase_5_claude() {
  local target="CLAUDE.md"
  if _should_skip "$target"; then
    echo "→ ${target} 보존 (skip 정책)"
    return
  fi
  cp "$PLUGIN/templates/CLAUDE.md" "$target"
  _replace_token "$target" "<PROJECT_NAME>" "$PROJECT_NAME"
  # PRD §1 한 줄 인용
  _replace_line_prefix "$target" "<PRD §1 한 줄 설명" "${PRD_ONELINE:-<TODO>}"
  _replace_line_prefix "$target" "<constitution.md §원칙 5개" "constitution.md 의 핵심 5 원칙:"
  # 원칙 5개 인덱스 (constitution.md ### 원칙 N: NAME 에서 NAME 추출)
  local i name
  for i in 1 2 3 4 5; do
    name=$(grep -m1 "^### 원칙 ${i}:" .specops/memory/constitution.md 2>/dev/null \
      | sed "s/^### 원칙 ${i}: *//" || echo "원칙${i}")
    # 원칙이 아직 없으면(헌법 skip · 파일 부재) **미확정 마커**를 쓴다 — 종전의 "원칙N" 은 채워진 값처럼 보여
    #   미채움 스캔에도 안 걸렸다(실기록: "원칙 1: 원칙1" 인 채 FID 60개). raw placeholder(<PRINCIPLE_N_NAME>)를
    #   그대로 옮기지 않는 것은 종전과 같다.
    [ -z "$name" ] && name="<미확정 — 근거 필요>"
    case "$name" in '<'*'>') name="<미확정 — 근거 필요>" ;; esac
    _replace_line_prefix "$target" "- 원칙 ${i}:" "- 원칙 ${i}: ${name}"
  done
  echo "→ ${target} 작성 완료"
}

# 디자인 방향 카탈로그 — templates/design-directions.md 표를 읽는다 (FID 20260928-design-direction-catalog).
#   stdout: 행마다 탭 구분 16필드 (id 이름 요약 특성 V M D Primary Secondary Background Surface
#   Text Primary · Text Secondary · Border · Error · Success). 카탈로그 부재·0행이면 빈 출력.
_design_directions() {
  [ -f "$PLUGIN/templates/design-directions.md" ] || return 0
  awk -F'|' '
    NF >= 18 && $2 ~ /^[ ]*[0-9]+[ ]*$/ {
      out = ""
      # 셀 내부 탭은 공백으로 — 출력이 탭 구분이라 남기면 필드가 밀려 §1 이 엇갈려 주입된다(Phase C 프로브 ②)
      for (i = 2; i <= 17; i++) { v = $i; gsub(/^[ \t]+|[ \t]+$/, "", v); gsub(/\t/, " ", v); out = out (i > 2 ? "\t" : "") v }
      print out
    }' "$PLUGIN/templates/design-directions.md"
}

# 고른 방향으로 DESIGN.md 를 만든다. $1=target $2=_design_directions 한 행.
#   머리 3줄 · §1 9라벨(백틱 hex — _inject_design_palette 계약) · §8 방향 특성 bullet.
#   값은 ENVIRON 으로 넘긴다 — awk -v 와 sed 는 역슬래시·& 를 해석한다.
_design_apply_direction() {
  local target="$1" row="$2"
  cp "$PLUGIN/templates/DESIGN.md" "$target" || return 1
  _replace_line_prefix "$target" "# DESIGN.md — [Project Name]" "# DESIGN.md — ${PROJECT_NAME}"
  ROW="$row" awk '
    BEGIN {
      split(ENVIRON["ROW"], f, "\t")
      split("Primary|Secondary|Background|Surface|Text Primary|Text Secondary|Border|Error|Success", L, "|")
      for (i = 1; i <= 9; i++) hex[L[i]] = f[7 + i]
    }
    !head && /^# DESIGN\.md — / {
      print; print ""
      print "> **디자인 방향**: " f[2] " — " f[3]
      print "> **다이얼**: VARIANCE " f[5] " · MOTION " f[6] " · DENSITY " f[7] " (1~10)"
      print "> 선택 기록: /init-project Phase 11 이 decisions.md 결정 표에 행으로 남긴다."
      head = 1; next
    }
    /^\| [A-Za-z ]+ \| `#______`/ {
      lbl = $0; sub(/^\| /, "", lbl); sub(/ \|.*/, "", lbl)
      if ((lbl in hex) && hex[lbl] ~ /^#[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$/) sub(/`#______`/, "`" hex[lbl] "`")
      print; next
    }
    /^## 8\. Design Principles/ {
      print; print ""
      print "**디자인 방향 특성** (" f[2] "):"
      m = split(f[4], t, ";")
      for (i = 1; i <= m; i++) { s = t[i]; gsub(/^[ ]+|[ ]+$/, "", s); if (s != "") print "- " s }
      next
    }
    { print }
  ' "$target" > "${target}.tmp" && mv "${target}.tmp" "$target" || return 1
}

phase_6_design() {
  if [ "$PROJECT_KIND" != "1" ] && [ "$PROJECT_KIND" != "4" ] && [ "$PROJECT_KIND" != "5" ]; then
    echo "[Phase 6] DESIGN.md skip (PROJECT_KIND=${PROJECT_KIND}, UI/풀스택/모바일만 활성)"
    return
  fi
  local target="DESIGN.md"
  if _should_skip "$target"; then
    echo "→ ${target} 보존 (skip 정책)"
    return
  fi
  local rows n pick="" row
  rows=$(_design_directions)
  n=$(printf '%s\n' "$rows" | grep -c . || true)
  if [ "${n:-0}" -eq 0 ]; then
    # read 를 소비하지 않는다 — 카탈로그가 깨져도 뒤 Phase 의 stdin 순서는 그대로다
    echo "  ⚠️  디자인 방향 카탈로그를 읽지 못했습니다 — 템플릿 골격만 복사합니다" >&2
    cp "$PLUGIN/templates/DESIGN.md" "$target"
    _replace_line_prefix "$target" "# DESIGN.md — [Project Name]" "# DESIGN.md — ${PROJECT_NAME}"
    return
  fi
  echo ""
  echo "[Phase 6] DESIGN.md — 디자인 방향 선택:"
  printf '%s\n' "$rows" | awk -F'\t' '{ printf "  (%s) %s — %s%s\n", $1, $2, $3, (NR == 1 ? " ← 기본" : "") }'
  printf "선택 [1]: "
  _ask design "디자인 방향"
  pick="$REPLY"
  # 숫자만 통과 → 선행 0 제거(02 → 2) → 자릿수 상한 → 범위 검사. 빈 입력·비숫자·범위 밖은 방향 1.
  #   `+2` 는 [ -ge ] 를 통과하지만 BSD sed -n "+2p" 가 오류라 빈 행이 됐다(Phase C 프로브 ⑤) — 부호도 비숫자로 본다.
  #   `$((10#$pick))` 는 2^64 를 넘는 입력을 무음 wrap 해(2^64+2 → 2) 방향 2 를 골랐다(Phase C 2회차) —
  #   산술 변환 없이 문자열로 다룬다: 방향 수 n 의 자릿수를 넘는 입력은 범위 밖이다.
  case "$pick" in ''|*[!0-9]*) pick=1 ;; esac
  pick=${pick#"${pick%%[!0]*}"}          # 선행 0 제거 — "0"·"000" 은 빈 값이 된다
  [ -n "$pick" ] || pick=1
  [ "${#pick}" -le "${#n}" ] || pick=1   # 자릿수 상한 — 산술 오버플로 경로 차단
  { [ "$pick" -ge 1 ] && [ "$pick" -le "$n" ]; } 2>/dev/null || pick=1
  row=$(printf '%s\n' "$rows" | sed -n "${pick}p")
  # 어떤 이유로든 행이 비면 방향 1 로 — 그래도 비면 빈 행으로 자리표시자 DESIGN.md 를 만들고 "완료" 라 하지 않는다
  [ -n "$row" ] || row=$(printf '%s\n' "$rows" | sed -n '1p')
  if [ -z "$row" ]; then
    echo "  ⚠️  디자인 방향 행을 읽지 못했습니다(선택 ${pick}) — 템플릿 골격만 복사합니다" >&2
    cp "$PLUGIN/templates/DESIGN.md" "$target"
    _replace_line_prefix "$target" "# DESIGN.md — [Project Name]" "# DESIGN.md — ${PROJECT_NAME}"
    return
  fi
  if _design_apply_direction "$target" "$row"; then
    echo "→ ${target} 작성 완료 (디자인 방향: $(printf '%s' "$row" | cut -f2))"
  else
    echo "  ⚠️  ${target} 작성 실패 — 방향 주입 중 오류" >&2
  fi
}
# screens-overview.md §1 표를 <!-- screens-table:start/end --> fence 내부에 교체.
# fence 패턴은 템플릿 예시 행 이름 (home/login/dashboard) 에 비의존 — 향후 템플릿 변경에 안정.
# 회귀: fence 가 존재하지 않으면 silent no-op (caller 검증 책임).
_rebuild_screens_table() {
  local file="$1"
  shift
  local n rows=""
  for n in "$@"; do
    rows="${rows}| ${n} | ${n} | 예정 — /start-all Phase 2.5 | [screens/${n}.md](../../screens/${n}.md) | [screens/${n}.html](../../screens/${n}.html) |
"
  done
  ROWS="$rows" awk '
    /^<!-- screens-table:start -->/ {
      print
      printf "%s", ENVIRON["ROWS"]
      inside = 1
      next
    }
    /^<!-- screens-table:end -->/ {
      inside = 0
      print
      next
    }
    inside { next }
    { print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

phase_7_screens() {
  case "$PROJECT_KIND" in 1|4|5) ;; *) echo "[Phase 7] screens skip (KIND=${PROJECT_KIND})"; return ;; esac
  echo ""
  echo "[Phase 7] 초기 화면 이름 목록 (콤마/공백 구분, 비우면 skip):"
  echo "  ※ screens/*.{md,html} 껍데기는 만들지 않음 — 화면 본문은 Phase 11(M1 범위) · /start-all Phase 2.5 · /design-screen"
  printf "예) home, login, dashboard: "
  local input=""
  _ask screens "초기 화면 이름"
  input="$REPLY"
  mkdir -p .specops/memory
  # 기존 표는 보존한다 — 재실행·`--resume` 이 템플릿으로 덮어 보강 표기와 손으로 쓴 줄을 지웠다(20261009 재현).
  #   이름 입력은 보존할 때도 **읽는다**: 질문을 건너뛰면 뒤 Phase 의 답 순서가 밀린다.
  local ov=".specops/memory/screens-overview.md" keep=0
  if _should_skip "$ov"; then
    keep=1
  else
    cp "$PLUGIN/templates/screens-overview.md" "$ov"
    _replace_token "$ov" "<PROJECT_NAME>" "$PROJECT_NAME"
    # 꼬리 줄 날짜 — 이 문서는 보강(Phase 11)이 골격을 유지해 다른 산출물처럼 뒤에서 채워지지 않는다(20261116 실주행).
    _replace_token "$ov" "<YYYY-MM-DD>" "$(date +%Y-%m-%d)"
  fi
  if [ -z "${input// }" ]; then
    if [ "$keep" = "1" ]; then
      echo "→ 화면 입력 비움. 기존 screens-overview.md 보존."
    else
      echo "→ 화면 입력 비움. screens-overview.md placeholder 유지."
    fi
    return
  fi
  local IFS=', '
  local -a raw_names=($input) names=()
  IFS=$' \t\n'
  # path traversal 방어: 영숫자/-/_ 1~64 만 허용
  local n
  for n in "${raw_names[@]}"; do
    [ -z "$n" ] && continue
    if [[ ! "$n" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
      echo "→ 화면명 '$n' 무시 (영숫자/-/_ 1~64 만 허용)" >&2
      continue
    fi
    names+=("$n")
  done
  if [ ${#names[@]} -eq 0 ]; then
    echo "→ 유효한 화면명 0개. screens-overview.md placeholder 유지."
    return
  fi
  if [ "$keep" = "1" ]; then
    # 보존 경로: 표에 없는 이름만 끝에 덧붙인다
    local have
    local -a fresh=()
    have=$(_screens_table_names "$ov")
    for n in "${names[@]}"; do
      printf '%s\n' "$have" | grep -qxF -- "$n" || fresh+=("$n")
    done
    if [ ${#fresh[@]} -eq 0 ]; then
      echo "→ 기존 screens-overview.md 보존 (입력한 이름은 이미 표에 있음)"
    elif _append_screen_rows "$ov" "예정 — /start-all Phase 2.5" "${fresh[@]}"; then
      echo "→ 기존 screens-overview.md 보존 · 새 화면 ${#fresh[@]}개만 표 끝에 추가"
    else
      echo "  ⚠️  기존 screens-overview.md 에 표 fence 가 없어 화면 이름을 추가하지 못했습니다 (파일은 그대로)" >&2
    fi
    return
  fi
  _rebuild_screens_table "$ov" "${names[@]}"
  echo "→ .specops/memory/screens-overview.md 목록 ${#names[@]}개 기록 (screens/ 파일 미생성 — Phase 2.5 예정)"
}
