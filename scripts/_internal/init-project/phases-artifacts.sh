#!/usr/bin/env bash
# library-only — sourced by init-project.sh
# phase_8~10 (산출물 매트릭스/README/commit) — init-project.sh 에서 이동

# 8a~8h 헬퍼 — 활성 매트릭스 (plan §4.4)
_phase_8a_requirements() {
  local target=".specops/memory/requirements.md"
  _should_skip "$target" && { echo "→ ${target} skip"; return; }
  cp "$PLUGIN/templates/requirements.md" "$target"
  _replace_token "$target" "<PROJECT_NAME>" "$PROJECT_NAME"
  # 화면이 없는 종류(2 백엔드/API · 3 CLI/라이브러리)에는 화면 전용 NFR 예시(접근성·브라우저 호환성)를 넣지 않는다 —
  #   CLI 프로젝트의 요구사항 문서에 WCAG·브라우저 버전 행이 채울 수 없는 자리표시자로 남았다.
  case "$PROJECT_KIND" in
    2|3) sed -i.bak -e '/^| NFR-4 | 접근성 |/d' -e '/^| NFR-5 | 호환성 |/d' "$target" && rm -f "$target.bak" ;;
  esac
  # §1 프로젝트 줄 — 템플릿이 "자동 인용" 이라고 적어 둔 자리다. 종전엔 채우지 않아 LLM 보강이 옮겨 적었다(20261113).
  #   한 줄이 없거나 <TODO> 면 자리표시자를 그대로 둔다(미채움 스캔에 잡혀야 한다).
  case "${PRD_ONELINE:-}" in ''|'<TODO>') ;; *) _replace_line_prefix "$target" '**프로젝트**:' "**프로젝트**: ${PRD_ONELINE}" ;; esac
  # 전략 C: PRD 마일스톤(PRD_F4/F5/F6) → §5 이름 치환 + §2 FR 시드행
  _seed_fr_row() {  # $1=FR-N $2=텍스트 $3=마일스톤 $4=우선순위
    [ -z "$2" ] || [ "$2" = "<TODO>" ] && return
    # 표 구분자와 겹치는 `|` 는 `/` 로 바꿔 넣는다 — 그대로 두면 칸이 밀려 FR 판독기가 마일스톤을 틀리게 읽는다.
    #   `\|` 로 이스케이프하지 않는 이유: 판독기들이 `|` 로 나누므로 이스케이프도 칸을 가른다. PRD.md 원문은 그대로다.
    local text="${2//|//}"
    _replace_line_prefix "$target" "| $1 |" "| $1 | ${text} | $3 | $4 | (TBD) |"
  }
  _seed_ms_name() { # $1=마일스톤헤더 prefix $2=텍스트
    [ -z "$2" ] || [ "$2" = "<TODO>" ] && return
    _replace_line_prefix "$target" "$1" "$1$2"
  }
  _seed_ms_name "### M1 — " "${PRD_F4:-}"
  _seed_ms_name "### M2 — " "${PRD_F5:-}"
  _seed_ms_name "### M3 — " "${PRD_F6:-}"
  _seed_fr_row "FR-1" "${PRD_F4:-}" "M1" "must"
  _seed_fr_row "FR-2" "${PRD_F5:-}" "M2" "should"
  _seed_fr_row "FR-3" "${PRD_F6:-}" "M3" "nice"
  # 안내 주석 — 실제 시드값(<TODO> 아닌 비어있지 않은 값) 1건 이상일 때만 (critic 권고 반영)
  if [ "${PRD_F4:-}" != "" ] && [ "${PRD_F4:-}" != "<TODO>" ] \
     || { [ "${PRD_F5:-}" != "" ] && [ "${PRD_F5:-}" != "<TODO>" ]; } \
     || { [ "${PRD_F6:-}" != "" ] && [ "${PRD_F6:-}" != "<TODO>" ]; }; then
    _replace_line_prefix "$target" "각 FR 은 고유 ID" \
      "각 FR 은 고유 ID + 마일스톤 매핑 + 우선순위. > 아래 FR-1~3 은 PRD 마일스톤 시드 — 세부 FR 로 분해하세요."
  fi
  echo "→ ${target} (8a 모든 종류, FR 합성)"
}

_phase_8b_architecture() {
  if [ "$PROJECT_KIND" = "3" ]; then
    echo "→ architecture.md skip (8b CLI 디폴트)"
    return
  fi
  local target=".specops/memory/architecture.md"
  _should_skip "$target" && return
  cp "$PLUGIN/templates/architecture.md" "$target"
  _replace_token "$target" "<PROJECT_NAME>" "$PROJECT_NAME"
  echo "→ ${target} (8b)"
}

_phase_8c_frontend() {
  case "$PROJECT_KIND" in 1|4|5) ;; *) return ;; esac
  local target=".specops/memory/frontend-architecture.md"
  _should_skip "$target" && return
  cp "$PLUGIN/templates/frontend-architecture.md" "$target"
  _replace_token "$target" "<PROJECT_NAME>" "$PROJECT_NAME"
  echo "→ ${target} (8c UI/Full/Mobile)"
}

_phase_8d_backend() {
  case "$PROJECT_KIND" in 2|4) ;; *) return ;; esac
  local target=".specops/memory/backend-architecture.md"
  _should_skip "$target" && return
  cp "$PLUGIN/templates/backend-architecture.md" "$target"
  _replace_token "$target" "<PROJECT_NAME>" "$PROJECT_NAME"
  echo "→ ${target} (8d BE/Full)"
}

_phase_8e_data_model() {
  # _should_skip 선검사 (다른 phase 와 정합) — resume·재실행 시 기존 파일 보존 + 불필요 프롬프트 회피
  local target=".specops/memory/data-model.md"
  _should_skip "$target" && { echo "→ data-model.md 보존 (skip 정책)"; return; }
  printf "[Phase 8e] DB 사용? — 서버 DB(Postgres/MySQL/MongoDB) 또는 클라이언트 영속(localStorage/IndexedDB)도 y [y/N/skip]: "
  local ans=""
  _ask_choice db "DB 사용" "n" 'y|Y|n|N|skip' "y · n"
  ans="$REPLY"
  case "$ans" in y|Y) ;; *) echo "→ data-model.md skip (8e ${ans:-N})"; return ;; esac
  cp "$PLUGIN/templates/data-model.md" "$target"
  _replace_token "$target" "<PROJECT_NAME>" "$PROJECT_NAME"
  echo "→ ${target} (8e DB=y)"
}

_phase_8f_api_spec() {
  # 기타(6)도 묻는다(20261113) — 종전엔 백엔드·풀스택만이라 기타로 분류한 프로젝트(파이프라인·봇·서버리스 등)는
  #   API 가 있어도 설계서를 만들 경로가 없었다. Web/UI·모바일(1·5)은 프론트만이라 소비 계약(8g)을 묻는다.
  case "$PROJECT_KIND" in 2|4|6) ;; *) return ;; esac
  # _should_skip 선검사 (다른 phase 와 정합) — resume·재실행 시 기존 파일 보존 + 불필요 프롬프트 회피
  local target=".specops/memory/api-spec.md"
  _should_skip "$target" && { echo "→ api-spec.md 보존 (skip 정책)"; return; }
  echo "[Phase 8f] API 정의 방식? (1)Markdown (2)OpenAPI (3)GraphQL (4)RPC (5)skip"
  printf "선택 [1]: "
  local m=""
  _ask_choice api "API 정의 방식" "1" '[1-5]' "1~5"
  m="$REPLY"
  case "$m" in 5) echo "→ api-spec.md skip"; return ;; esac
  case "$m" in 1|2|3|4) ;; *) m="1" ;; esac
  cp "$PLUGIN/templates/api-spec.md" "$target"
  _replace_token "$target" "<PROJECT_NAME>" "$PROJECT_NAME"
  local fmt_label fmt_sec
  case "$m" in
    1) fmt_label="Markdown 엔드포인트 표"; fmt_sec="§1" ;;
    2) fmt_label="OpenAPI 3.1 YAML";       fmt_sec="§2" ;;
    3) fmt_label="GraphQL SDL";             fmt_sec="§3" ;;
    4) fmt_label="RPC / TS 시그니처";       fmt_sec="§4" ;;
  esac
  sed -i.bak "s/\[ \] ${fmt_sec} /[x] ${fmt_sec} /" "$target" && rm -f "${target}.bak"
  _replace_token "$target" "<\`/init-project\` 입력값>" "${fmt_label} (${fmt_sec})"
  # 고르지 않은 방식 절(§1~§4)을 지운다. awk 로 한다 — 종전의 python3 호출은 python3 가 없으면 절 4개가
  #   전부 남는데도 아래 "→ api-spec.md (8f …)" 를 그대로 출력했다(20261009 재현).
  #   절 번호는 match 로 찾는다: `§` 는 여러 바이트라 substr 위치가 awk 구현(바이트·문자 단위)마다 다르다.
  if K="$m" awk '
      /^## §[1-4]\./ { match($0, /[1-4]\./); skip = (substr($0, RSTART, 1) != ENVIRON["K"]) }
      /^## §[5-9]\./ { skip = 0 }
      !skip { print }
    ' "$target" > "${target}.tmp" && [ -s "${target}.tmp" ]; then
    mv "${target}.tmp" "$target"
  else
    rm -f "${target}.tmp"
    echo "  ⚠️  api-spec.md 의 방식 절 정리에 실패했습니다 — 고르지 않은 절(§1~§4)이 남아 있습니다" >&2
  fi
  echo "→ ${target} (8f 방식=${m} ${fmt_label})"
}

_phase_8g_api_consumer() {
  case "$PROJECT_KIND" in 1|5) ;; *) return ;; esac
  local target=".specops/memory/api-spec-consumer.md"
  _should_skip "$target" && { echo "→ api-spec-consumer.md 보존 (skip 정책)"; return; }
  printf "[Phase 8g] 외부 API 소비 계약 문서 작성? [y/N]: "
  local ans=""
  _ask_choice api.consumer "외부 API 소비 계약" "n" 'y|Y|n|N' "y · n"
  ans="$REPLY"
  case "$ans" in y|Y) ;; *) echo "→ api-spec-consumer.md skip (8g ${ans:-N})"; return ;; esac
  cp "$PLUGIN/templates/api-spec-consumer.md" "$target"
  _replace_token "$target" "<PROJECT_NAME>" "$PROJECT_NAME"
  echo "→ ${target} (8g 소비 IF)"
}

_phase_8h_test_strategy() {
  local target=".specops/memory/test-strategy.md"
  _should_skip "$target" && return
  cp "$PLUGIN/templates/test-strategy.md" "$target"
  _replace_token "$target" "<PROJECT_NAME>" "$PROJECT_NAME"
  echo "→ ${target} (8h 모든 종류)"
}

# 8i 프로세스 설계서 — KIND 무관(CLI 도 `사용자 → 명령 → 처리 → 출력` 흐름을 갖는다).
#   종전엔 bash 가 만들지 않고 Phase 11 LLM 보강이 "새로 생성"했다 — 보강이 빠지면 문서 자체가 없었고
#   정본 목록(ARTIFACTS_MEMORY) 밖이라 사전검사 표·활성 카운트에도 잡히지 않았다. 골격은 bash 가 보장하고
#   본문(프로세스 목록·상세)은 Phase 11 이 채운다(placeholder 는 scan-enrich-placeholders 가 미채움으로 판정).
_phase_8i_process_design() {
  local target=".specops/memory/process-design.md"
  _should_skip "$target" && { echo "→ process-design.md 보존 (skip 정책)"; return; }
  cp "$PLUGIN/templates/process-design.md" "$target"
  _replace_token "$target" "<프로젝트명>" "$PROJECT_NAME"
  echo "→ ${target} (8i 모든 종류)"
}

phase_8_artifacts() {
  echo ""
  echo "[Phase 8] 종류별 산출물 매트릭스 (KIND=${PROJECT_KIND}):"
  mkdir -p .specops/memory
  _phase_8a_requirements
  _phase_8b_architecture
  _phase_8c_frontend
  _phase_8d_backend
  _phase_8e_data_model
  _phase_8f_api_spec
  _phase_8g_api_consumer
  _phase_8h_test_strategy
  _phase_8i_process_design
}
phase_9_readme() {
  local target="README.md"
  if _should_skip "$target"; then
    echo "→ ${target} 보존 (skip 정책)"
    return
  fi
  cp "$PLUGIN/templates/README.md" "$target"
  _replace_token "$target" "<PROJECT_NAME>" "$PROJECT_NAME"
  _replace_line_prefix "$target" "<PRD §1 한 줄 설명" "${PRD_ONELINE:-<TODO>}"
  _replace_token "$target" "<YYYY-MM-DD>" "$(date +%Y-%m-%d)"
  echo "→ ${target} 작성 완료"
}
_kind_label() {
  case "$1" in
    1) echo "Web/UI" ;;
    2) echo "백엔드/API" ;;
    3) echo "CLI/라이브러리" ;;
    4) echo "풀스택" ;;
    5) echo "모바일" ;;
    *) echo "기타" ;;
  esac
}

# 14종 중 실제 생성된 파일 카운트
_count_active() {
  local n=0 f
  for f in "${ARTIFACTS_ROOT[@]}" "${ARTIFACTS_MEMORY[@]}"; do
    [ -f "$f" ] && n=$((n + 1))
  done
  echo "$n"
}

# `.specops/.gitignore` 규칙 본문 — 새 프로젝트는 이대로 쓰고, 기존 파일에는 빠진 규칙만 보충한다.
#   정책: memory/ · session-progress.md · <FID>/intent.md 는 commit, 그 밖의 FID 산출물은 ignore.
#   intent.md 예외(20261008): 의도 문서는 PR 리뷰어·제품 오너가 볼 수 있어야 하고 git 이력이 곧 감사 추적이다
#   (Anthropic AI-native SDLC playbook 의 intent.md 규약 — 버전 관리되는 공유 위치).
#   git 은 **무시된 디렉토리 안의 파일을 다시 포함할 수 없다** — 그래서 디렉토리(`…-*/`)가 아니라 내용(`…-*/*`)을 무시한다.
#   로컬 상태 파일(20261009): 훅이 쓰는 pending-capture 는 프롬프트 캡처라 `git add -A` 한 번에 커밋되면 안 된다.
#   freelog.md 는 넣지 않았다 — 자유작업 **기록물**이라 커밋 여부는 프로젝트가 정한다.
_specops_gitignore_template() {
  cat <<'EOF'
# specops-ko 정책: memory/ · session-progress.md · <FID>/intent.md 는 commit, 그 밖의 FID 산출물은 ignore
# FID 컨벤션: YYYYMMDD-slug (8자리 날짜 + dash). 일반 디렉토리 false positive 차단.
# 디렉토리가 아니라 내용을 무시한다 — 무시된 디렉토리 안의 파일은 `!` 로 되살릴 수 없다.
[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*/*
![0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*/intent.md
# 설계 통합 뷰 — .md 에서 생성되는 읽기 전용 파일(/design-overview). 원본이 아니라 커밋하지 않는다.
design-overview.html
# 로컬 상태 — 훅·스크립트가 쓰는 파일(프롬프트 캡처·우회 기록·백업·init 중간 파일). 커밋하지 않는다.
pending-capture.jsonl
redact-failures.log
friction-log.jsonl
*.bak
.init-*
EOF
}

# `.specops/.gitignore` 를 만들거나 **병합**한다 — 통째로 다시 쓰지 않는다.
#   종전엔 실행마다 `cat >` 로 덮어써, 하류가 직접 넣은 규칙(batch-*/ · *.bak 등 — 실물 4곳 중 2곳)이
#   `--resume` 한 번에 사라졌다(20261009 재현). 기존 파일에는 두 가지만 한다:
#   ① 구 규칙(FID 디렉토리 통째 무시)을 **제자리에서** 새 규칙으로 바꾼다 — 디렉토리가 무시되면 intent.md 예외가
#      듣지 않는다. 제자리인 이유는 뒤에 오는 사용자 규칙과의 순서를 지키기 위해서다.
#   ② 본문의 규칙 중 파일에 없는 줄만 보충한다(완전 일치 비교 — 재실행해도 늘지 않는다).
_specops_gitignore_sync() {
  local gi=".specops/.gitignore" fid='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*'
  if [ ! -f "$gi" ]; then
    _specops_gitignore_template > "$gi"
    return
  fi
  local has_new=0 has_neg=0
  grep -qxF -- "${fid}/*" "$gi" && has_new=1
  grep -qxF -- "!${fid}/intent.md" "$gi" && has_neg=1
  if grep -qxF -- "${fid}/" "$gi"; then
    LEG="${fid}/" NEW="${fid}/*" NEG="!${fid}/intent.md" HAS_NEW="$has_new" HAS_NEG="$has_neg" \
    LEGC="# specops-ko 정책: memory/ 와 session-progress.md 는 commit, FID 디렉토리는 ignore" \
    NEWC="# specops-ko 정책: memory/ · session-progress.md · <FID>/intent.md 는 commit, 그 밖의 FID 산출물은 ignore" \
    awk '
      $0 == ENVIRON["LEGC"] { print ENVIRON["NEWC"]; next }
      $0 == ENVIRON["LEG"] {
        if (!done) {
          if (ENVIRON["HAS_NEW"] != "1") print ENVIRON["NEW"]
          if (ENVIRON["HAS_NEW"] != "1" && ENVIRON["HAS_NEG"] != "1") print ENVIRON["NEG"]
          done = 1
        }
        next
      }
      { print }
    ' "$gi" > "${gi}.tmp" && mv "${gi}.tmp" "$gi"
  fi
  # ② 빠진 규칙을 **파일 맨 위에** 보충한다 — 뒤에 오는 규칙이 이기므로 사용자 규칙이 항상 우선한다.
  #    끝에 붙이면 보충한 `*.bak` 이 사용자의 `!keep.bak` 을 뒤집는다(독립 리뷰 재현).
  #    예외는 intent.md 예외 줄이다: 내용 무시 규칙 **뒤**에 있어야 들으므로, 그 규칙이 이미 파일에 있으면 바로 뒤에 끼운다.
  local line supp="" added=0 neg="!${fid}/intent.md"
  if grep -qxF -- "${fid}/*" "$gi" && ! grep -qxF -- "$neg" "$gi"; then
    NEW="${fid}/*" NEG="$neg" awk '
      { print }
      $0 == ENVIRON["NEW"] && !done { print ENVIRON["NEG"]; done = 1 }
    ' "$gi" > "${gi}.tmp" && mv "${gi}.tmp" "$gi" && added=$((added + 1))
  fi
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    grep -qxF -- "$line" "$gi" && continue
    supp="${supp}${line}
"
    added=$((added + 1))
  done <<EOF
$(_specops_gitignore_template)
EOF
  if [ -n "$supp" ]; then
    { printf '# specops-ko 가 보충한 규칙 (/init-project) — 아래에 오는 규칙이 우선한다\n%s\n' "$supp"; cat "$gi"; } \
      > "${gi}.tmp" && mv "${gi}.tmp" "$gi"
  fi
  [ "$added" -eq 0 ] || echo "→ .specops/.gitignore 기존 규칙 보존 · 빠진 규칙 ${added}줄 보충"
}

# 하류 CLAUDE.md 의 산출물 인덱스에서 **이 프로젝트에 없는 문서**의 줄을 뺀다(20261113).
#   템플릿은 14종을 전부 나열하고 "활성 산출물만" 이라고 적는데, 종전엔 다듬지 않아 CLI 프로젝트의 CLAUDE.md 가
#   없는 파일 6개(구조·프론트·백엔드·API·소비 API·화면 목록)를 가리켰다 — 매 세션 읽히는 문서다.
#   산출물이 다 만들어진 뒤(Phase 10)에 한다. init 이 이번에 쓴 CLAUDE.md 만 고친다 — 보존한 사용자 문서는 건드리지 않는다.
#   빼는 것은 `- <라벨>: \`<경로>\`` 꼴의 줄 가운데 그 경로(.specops/memory/*.md · DESIGN.md)가 없는 것뿐이다.
_claude_index_prune() {
  local f="CLAUDE.md" line p ui=0
  [ -f "$f" ] && _init_written "$f" || return 0
  case "$PROJECT_KIND" in 1|4|5) ui=1 ;; esac
  while IFS= read -r line || [ -n "$line" ]; do
    p=$(printf '%s\n' "$line" | sed -n -e 's/^- [^`]*`\(\.specops\/memory\/[a-z-]*\.md\)`.*/\1/p' -e 's/^- [^`]*`\(DESIGN\.md\)`.*/\1/p' | head -1)
    if [ -n "$p" ] && [ ! -f "$p" ]; then continue; fi
    [ "$ui" = "0" ] && [ "$line" = "UI 프로젝트인 경우:" ] && continue
    printf '%s\n' "$line"
  done < "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
}

phase_10_commit() {
  echo ""
  echo "[Phase 10] commit + .specops/.gitignore"
  mkdir -p .specops
  _specops_gitignore_sync
  # session-progress.md 골격
  if [ ! -f .specops/session-progress.md ]; then
    cp "$PLUGIN/templates/session-progress.md" .specops/session-progress.md
    # N6: raw sed 대신 _replace_token(|·&·\ escape) — PROJECT_NAME 의 sed 메타문자
    #   일관 처리(lib.sh 의 다른 호출처와 정합). self-input robustness.
    _replace_token .specops/session-progress.md "<project-name>" "$PROJECT_NAME"
  fi
  # 분모는 정본 배열의 길이다 — 숫자를 따로 적어 두면 배열이 늘 때 어긋난다(풀스택이 "14/13" 으로 찍혔다).
  local active label total=$(( ${#ARTIFACTS_ROOT[@]} + ${#ARTIFACTS_MEMORY[@]} ))
  active=$(_count_active)
  label=$(_kind_label "$PROJECT_KIND")
  # 결정 원장 골격 (enrich가 채움 — bash에서 존재만 보장)
  local ledger
  for ledger in project-context.md decisions.md; do
    if [ ! -f ".specops/memory/${ledger}" ]; then
      cp "$PLUGIN/templates/${ledger}" ".specops/memory/${ledger}"
      _replace_token ".specops/memory/${ledger}" "<PROJECT_NAME>" "$PROJECT_NAME"
      # 프로젝트 컨텍스트 §1 의 한 줄·페르소나 — bash 가 이미 아는 값이다(20261113). 표 칸이라 `|` 는 `/` 로 바꾼다
      #   (FR 시드와 같은 이유 — 판독기가 `|` 로 칸을 나눈다). 값이 없으면 자리표시자를 둔다.
      if [ "$ledger" = "project-context.md" ]; then
        case "${PRD_ONELINE:-}" in ''|'<TODO>') ;; *) _replace_line_prefix ".specops/memory/${ledger}" '| 한 줄 |' "| 한 줄 | ${PRD_ONELINE//|//} |" ;; esac
        [ -z "${PRD_F2:-}" ] || _replace_line_prefix ".specops/memory/${ledger}" '| 페르소나 |' "| 페르소나 | ${PRD_F2//|//} |"
      fi
      echo "→ .specops/memory/${ledger} 골격 생성"
    fi
  done
  # 종류를 적는다 — 뒤 단계(foundation 필수 판정)와 다음 `--resume` 이 추정 대신 이 값을 쓴다.
  _record_kind
  _claude_index_prune
  # stage — init 범위만(lib.sh `_init_stage_own`). screens/ 를 디렉토리째 넣지 않는다:
  #   이 시점엔 specops 화면 파일이 아직 없어, 넣으면 기존 앱의 screens/ 소스만 딸려 들어간다.
  _init_stage_own
  local own f
  if ! own=$(_init_staged_own); then
    echo "  ⚠️  staged 산출물을 판정하지 못했습니다 (git diff 실패) — 커밋·스테이징 요약을 건너뜁니다" >&2
    return 1
  fi
  if [ -z "$own" ]; then
    echo "→ commit 대상 없음 (skip 정책으로 모두 보존된 듯)"
    return
  fi
  # 단일 커밋 계약: Phase 11 enrich 후 1회 커밋이 기본.
  # SPECOPS_INIT_COMMIT_NOW=1 이면 bash 단계에서 즉시 커밋 (테스트·enrich 생략 경로).
  if [ "${SPECOPS_INIT_COMMIT_NOW:-0}" = "1" ]; then
    # 경로를 지정해 커밋한다 — 미리 stage 돼 있던 무관한 파일은 인덱스에 그대로 남는다.
    local -a cpaths=()
    while IFS= read -r f; do [ -n "$f" ] && cpaths+=("$f"); done <<EOF
$own
EOF
    if git commit -q -m "chore(init): /init-project 부트스트랩 (${label} · ${total}종 중 ${active}종)" -- "${cpaths[@]}"; then
      rm -f "$INIT_HOLD_FILE" "$INIT_WRITTEN_FILE" 2>/dev/null
      echo "→ git commit 완료 (${label} · ${active}/${total}) [SPECOPS_INIT_COMMIT_NOW=1]"
    else
      echo "  ⚠️  git commit 실패 — 산출물은 staged 로 남아 있습니다" >&2
    fi
  else
    echo "→ 스테이징 완료 (${label} · ${active}/${total}). Phase 11 enrich 후 단일 커밋하세요."
    echo "  (즉시 커밋: SPECOPS_INIT_COMMIT_NOW=1)"
  fi
  echo ""
  echo "초기화(bash) 완료. 활성 산출물 ${active}종."
  # 다음 단계 안내는 종류를 따른다(20261113) — 종전엔 종류와 무관하게 "/start … 공통 먼저면 /start-foundation" 이었고
  #   명령 본문의 두 안내와도 문구가 달랐다. /start-all 은 UI·백엔드·풀스택·모바일에서 공통부(foundation)가 끝나지
  #   않았으면 Phase 0 에서 멈춘다(foundation-kind.sh 와 같은 종류 구분).
  echo "이어서 Phase 11 LLM 보강 → 단일 커밋으로 부트스트랩을 마칩니다. 그다음:"
  case "$PROJECT_KIND" in
    1|2|4|5) echo "  /start-foundation 으로 공통부를 먼저 만들고 → /start-all 로 FR 을 일괄 개발합니다 (기능 하나만이면 /start · 현황 /status)" ;;
    *)       echo "  /start 뒤에 첫 기능을 적어 lifecycle 로 들어갑니다 (FR 이 여럿이면 /start-all · 현황 /status)" ;;
  esac
}
