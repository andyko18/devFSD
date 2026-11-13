#!/usr/bin/env bash
# split-session.sh — 구현 구간을 새 대화 맥락(헤드리스 자식 세션)에서 돌린다 (20261112)
#
# 사용:
#   split-session.sh decide <FID>                  분리 여부 판정 — `SPLIT: yes|no (<사유>)` · rc 0=yes 1=no 2=사용법
#   split-session.sh run <FID> [--resume "<전달문>"]  자식 세션 실행(끝날 때까지 대기 — 부모는 백그라운드로 부른다)
#                                                   마지막 줄 `SPLIT-RESULT: DONE|HELD|FAILED|TIMEOUT …`
#                                                   rc 0=DONE 10=HELD 1=FAILED 124=TIMEOUT 2=사용법
#   split-session.sh status <FID>                  자식 세션 진행 상황(진행 기록 끝 5줄 + 자식의 최근 도구 호출)
#   split-session.sh warn-size [<transcript 경로>]  현재 대화가 기준보다 크면 1줄 고지(차단 아님 · 항상 rc 0)
#
# 왜 필요한가 (20261112 실측): 작업 1건 비용의 약 70%가 주 세션이 커진 대화를 호출마다 다시 읽는 것이었다
#   (호출 255회 · 대화 213K→792K 토큰). 호출이 가장 많은 구간이 구현(62~82분)인데 그 구간은 설계 단계의
#   대화를 쓰지 않는다 — 필요한 것은 전부 `.specops/<FID>/` 파일에 있다. 그래서 구현~성능 게이트 구간만
#   맥락이 빈 자식 세션(`claude -p`)에 맡기고, 주 세션은 결과 1줄만 받는다.
#
# 왜 서브에이전트가 아니라 자식 세션인가 (희생용 저장소 실측): 서브에이전트의 도구 호출은 훅에
#   **주 세션의** transcript 경로로 들어온다. R-1/R-2 의 실행 증거 판정은 그 파일을 읽으므로, 서브에이전트가
#   돌린 검증·테스트는 증거로 잡히지 않아 커밋이 막힌다. 자식 세션은 자기 transcript 를 가진 온전한
#   주 세션이라 거버넌스 훅을 고치지 않고 그대로 통과한다.
#
# 권한: `--dangerously-skip-permissions`·`bypassPermissions` 는 **쓰지 않는다**(설정에 적어도 거절).
#   기본(inherit)은 아무 권한 옵션도 넘기지 않는다 — 자식은 사용자의 settings(`permissions.defaultMode`·allow)를
#   그대로 따른다. 그 기본 모드가 프롬프트 없이 셸을 돌릴 수 없으면(auto 아님) 분리하지 않는다.
#
# 설정 (`.specops/config.yaml` 의 `session_split:` 블록 · 환경변수가 우선):
#   enabled: true|false            SPECOPS_NO_SPLIT=1 이면 끈다
#   permission_mode: inherit|auto|acceptEdits     SPECOPS_SPLIT_PERMISSION_MODE
#   model: <별칭>                  SPECOPS_SPLIT_MODEL          (기본: 넘기지 않음 — 사용자 기본 모델)
#   timeout_min: 180               SPECOPS_SPLIT_TIMEOUT_MIN
#   max_budget_usd: <수>           SPECOPS_SPLIT_MAX_BUDGET_USD (기본: 넘기지 않음)
#   warn_context_tokens: 150000    SPECOPS_SPLIT_WARN_TOKENS
set -u

SPECOPS="${SPECOPS_ROOT:-.specops}"
CONFIG="${SPECOPS_CONFIG:-$SPECOPS/config.yaml}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
DEFAULT_TIMEOUT_MIN=180
# 기준 150K 토큰의 근거(20261112 실측): 이 플러그인을 켠 새 세션의 첫 호출이 48~52K 토큰이다(5개 세션).
#   150K 면 이미 약 100K 가 쌓인 것이고, 풀 경로 1건은 호출이 255회라 그 100K 를 호출마다 다시 읽는다.
DEFAULT_WARN_TOKENS=150000
# transcript 에서 usage 를 읽지 못할 때만 쓰는 근사 — 압축 전 기록은 토큰당 약 10바이트였다(3.2MB↔299K · 0.46MB↔74K).
BYTES_PER_TOKEN=10

usage() { sed -n '4,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; }

# `session_split:` 블록의 한 단계 키만 읽는다(YAML 파서 의존 없음). 없으면 빈 문자열.
cfg() {
  [ -r "$CONFIG" ] || return 0
  awk -v key="$1" '
    /^session_split:[[:space:]]*(#.*)?$/ { inb = 1; next }
    inb && /^[^[:space:]#]/ { inb = 0 }
    inb {
      line = $0; sub(/[[:space:]]+#.*$/, "", line)
      if (match(line, "^[[:space:]]+" key ":[[:space:]]*")) {
        v = substr(line, RLENGTH + 1); gsub(/^["\047]|["\047]$/, "", v); print v; exit
      }
    }' "$CONFIG"
}

setting() {  # $1=환경변수 값 $2=config 키 $3=기본값
  local v="$1"
  [ -n "$v" ] || v=$(cfg "$2")
  [ -n "$v" ] || v="$3"
  printf '%s' "$v"
}

is_fid() { case "$1" in ''|*/*|*..*|-*) return 1 ;; esac; return 0; }

spec_has() { grep -qE "$1" "$SPECOPS/$FID/spec.md" 2>/dev/null; }

# 사용자 settings 의 기본 권한 모드(가까운 파일 우선). 읽지 못하면 빈 문자열.
settings_default_mode() {
  command -v jq >/dev/null 2>&1 || return 0
  local f m
  for f in .claude/settings.local.json .claude/settings.json "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; do
    [ -r "$f" ] || continue
    m=$(jq -r '.permissions.defaultMode // .defaultMode // empty' "$f" 2>/dev/null)
    [ -n "$m" ] && { printf '%s' "$m"; return 0; }
  done
}

# 자식에 넘길 권한 모드를 정한다. stdout=모드(inherit 면 빈 줄) · rc 1=분리 불가(사유는 stderr)
resolve_permission_mode() {
  local want; want=$(setting "${SPECOPS_SPLIT_PERMISSION_MODE:-}" permission_mode inherit)
  case "$want" in
    auto|acceptEdits) printf '%s' "$want" ;;
    inherit)
      case "$(settings_default_mode)" in
        auto) : ;;
        bypassPermissions) echo "사용자 기본 권한 모드가 bypassPermissions — 자식 세션에 물려주지 않는다" >&2; return 1 ;;
        *) echo "사용자 기본 권한 모드가 auto 가 아니라 자식 세션이 셸 명령을 거부당한다 — config session_split.permission_mode 지정 필요" >&2; return 1 ;;
      esac ;;
    *) echo "permission_mode '$want' 는 허용하지 않는다(inherit|auto|acceptEdits)" >&2; return 1 ;;
  esac
}

cmd_decide() {
  no() { echo "SPLIT: no ($1)"; exit 1; }
  [ "${SPECOPS_SPLIT_CHILD:-}" = 1 ] && no "이미 분리된 자식 세션"
  [ "${SPECOPS_NO_SPLIT:-}" = 1 ] && no "SPECOPS_NO_SPLIT=1"
  case "$(cfg enabled)" in false|no|off|0) no "config session_split.enabled: false" ;; esac
  [ -r "$SPECOPS/$FID/spec.md" ] || no "spec.md 없음"
  spec_has '^\*\*§분리\*\*:[[:space:]]*(off|false)' && no "--no-split (spec §분리: off)"
  spec_has '^\*\*§batch\*\*:' && no "§batch — 오케스트레이터가 구현을 소유"
  spec_has '^\*\*§lite\*\*:[[:space:]]*true' && no "§lite 경로"
  spec_has '^\*\*§유형\*\*:[[:space:]]*trivial' && no "trivial 경로"
  [ -r "$SPECOPS/$FID/plan.md" ] || no "plan.md 없음 — 풀 경로가 아니다"
  [ -r "$SPECOPS/$FID/tasks.md" ] || no "tasks.md 없음"
  command -v "$CLAUDE_BIN" >/dev/null 2>&1 || no "claude CLI 없음"
  command -v jq >/dev/null 2>&1 || no "jq 없음 — 자식 결과를 읽을 수 없다"
  local why
  why=$(resolve_permission_mode 2>&1 >/dev/null) || no "$why"
  echo "SPLIT: yes"
}

child_prompt() {
  cat <<EOF
[분리 자식 세션 — FID $FID]
이 세션은 구현 구간만 맡는다. 설계(spec·AC·plan·tasks)는 다른 세션에서 끝났고 사용자가 승인했다 — 다시 설계하거나 다시 묻지 않는다. 필요한 것은 전부 \`$SPECOPS/$FID/\` 파일에 있다.

할 일: \`Skill: devfsd:implementing-ko\` 를 호출해 FID $FID 를 구현하고, 각 skill 의 \`## 다음 skill\` 을 따라 performance-test-ko 의 판정까지 간다.

이 세션의 규칙:
1. 사용자 채널이 없다. 사용자에게 물어야 하는 지점(NEEDS_APPROVAL · NEEDS_DISCUSSION · HARD GATE · 승인 기록 없는 비가역/repo 밖 작업 · 실행 환경 부재 질문)에서는 묻지 말고, \`$SPECOPS/$FID/split/held.md\` 에 ① 무엇이 막혔는지 ② 선택지 ③ 답을 받으면 어디서 이어 가는지를 적고 마지막 줄을 \`SPLIT-CHILD-HELD: $FID\` 로 끝낸다.
2. PR 생성 게이트(demo-ko · PR 질문 · gh pr create)는 하지 않는다 — 주 세션의 몫이다. performance-test-ko 의 판정과 기록까지 끝나면 마지막 줄을 \`SPLIT-CHILD-DONE: $FID\` 로 끝낸다.
3. 더 진행할 수 없으면(도구 거부 · 환경 문제) 마지막 줄을 \`SPLIT-CHILD-FAILED: $FID <사유 한 줄>\` 로 끝낸다.
4. 마지막 메시지에는 위 마커 줄과 요약 5줄 이내만 쓴다(커밋 범위 · 테스트 결과 · 넘긴 결정 수).
EOF
}

# 워치독: 상한을 넘기면 자식과 그 자손을 프로세스 그룹째 끝낸다(run-bounded.sh 와 같은 방식).
run_child() {  # $1=상한(초) · 나머지=명령. stdout→$OUT
  local limit="$1"; shift
  local flag; flag=$(mktemp)
  set -m
  "$@" < /dev/null > "$OUT" 2> "$ERR" &
  local pid=$!
  set +m
  ( local waited=0
    while [ -e "$flag" ] && kill -0 "$pid" 2>/dev/null; do
      sleep 5; waited=$((waited + 5))
      if [ "$waited" -ge "$limit" ] && [ -e "$flag" ]; then
        : > "$DIR/timed-out"
        kill -TERM -- "-$pid" 2>/dev/null; sleep 3; kill -KILL -- "-$pid" 2>/dev/null
        break
      fi
    done ) >/dev/null 2>&1 &
  wait "$pid" 2>/dev/null; local rc=$?
  rm -f "$flag"
  return "$rc"
}

cmd_run() {
  local resume_msg="" resume=0
  if [ "${1:-}" = "--resume" ]; then resume=1; resume_msg="${2:-이어서 진행하라.}"; fi
  command -v jq >/dev/null 2>&1 || { echo "SPLIT-RESULT: FAILED fid=$FID detail=jq 없음"; exit 1; }
  [ -r "$SPECOPS/$FID/tasks.md" ] || { echo "SPLIT-RESULT: FAILED fid=$FID detail=tasks.md 없음"; exit 1; }

  DIR="$SPECOPS/$FID/split"; mkdir -p "$DIR"
  OUT="$DIR/child.jsonl"; ERR="$DIR/child.err"
  local mode model budget tmin sid="" prompt
  mode=$(resolve_permission_mode) || { echo "SPLIT-RESULT: FAILED fid=$FID detail=권한 모드를 정할 수 없다"; exit 1; }
  model=$(setting "${SPECOPS_SPLIT_MODEL:-}" model "")
  budget=$(setting "${SPECOPS_SPLIT_MAX_BUDGET_USD:-}" max_budget_usd "")
  tmin=$(setting "${SPECOPS_SPLIT_TIMEOUT_MIN:-}" timeout_min "$DEFAULT_TIMEOUT_MIN")
  case "$tmin" in ''|*[!0-9]*|0) tmin=$DEFAULT_TIMEOUT_MIN ;; esac

  if [ "$resume" = 1 ]; then
    sid=$(cat "$DIR/session-id" 2>/dev/null)
    [ -n "$sid" ] || { echo "SPLIT-RESULT: FAILED fid=$FID detail=이어 갈 자식 세션 id 가 없다($DIR/session-id)"; exit 1; }
    prompt="[분리 자식 세션 재개 — FID $FID] $resume_msg
(규칙은 처음과 같다 — 마지막 줄은 SPLIT-CHILD-DONE|HELD|FAILED: $FID)"
    [ -f "$OUT" ] && mv -f "$OUT" "$DIR/child.prev.jsonl"
    rm -f "$DIR/held.md"
  else
    prompt=$(child_prompt)
  fi
  rm -f "$DIR/timed-out" "$DIR/result.json"

  local args=(-p "$prompt" --output-format stream-json --verbose)
  [ -n "$mode" ] && args+=(--permission-mode "$mode")
  [ -n "$model" ] && args+=(--model "$model")
  [ -n "$budget" ] && args+=(--max-budget-usd "$budget")
  [ -n "$sid" ] && args+=(--resume "$sid")

  local started; started=$(date +%s)
  # 백그라운드 대기 상한을 끈다(20261113): print 모드는 백그라운드 서브에이전트를 마지막 턴 뒤 10분까지만 기다리고 그 뒤 끝낸다 —
  #   구현자가 10분을 넘으면 자식이 끝 마커 없이 종료됐다(실측). 전체 상한은 위 워치독(timeout_min)이 본다. 사용자가 준 값은 그대로 둔다.
  SPECOPS_SPLIT_CHILD=1 CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS="${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS:-0}" \
    run_child $((tmin * 60)) "$CLAUDE_BIN" "${args[@]}"
  local child_rc=$? mins=$(( ($(date +%s) - started) / 60 ))

  # 결과 판독. 자식은 백그라운드 작업 알림으로 턴이 다시 열릴 때마다 result 줄을 낸다(실측: 1회 실행에 4줄 ·
  #   마지막 줄의 본문이 빈 경우도 있다). 종료 상태는 마지막 줄에서, 끝 마커는 **모든** result 본문 중 마지막 것에서,
  #   호출 수는 합으로 읽는다. 비용은 누적값이라 마지막 줄 것이다. result 가 없으면(강제 종료) init 줄에서 세션 id 만 건진다.
  local results res subtype text cost turns status detail marker
  results=$(grep '"type":"result"' "$OUT" 2>/dev/null)
  res=$(printf '%s\n' "$results" | tail -n 1)
  [ -n "$sid" ] || sid=$(printf '%s' "$res" | jq -r '.session_id // empty' 2>/dev/null)
  [ -n "$sid" ] || sid=$(grep -m1 '"subtype":"init"' "$OUT" 2>/dev/null | jq -r '.session_id // empty' 2>/dev/null)
  [ -n "$sid" ] && printf '%s\n' "$sid" > "$DIR/session-id"
  subtype=$(printf '%s' "$res" | jq -r '.subtype // empty' 2>/dev/null)
  cost=$(printf '%s' "$res" | jq -r '.total_cost_usd // empty' 2>/dev/null)
  turns=$(printf '%s\n' "$results" | jq -rs 'map(.num_turns // 0) | add // empty' 2>/dev/null)
  text=$(printf '%s\n' "$results" | jq -rs 'map(.result // "" | select(. != "")) | last // empty' 2>/dev/null)
  marker=$(printf '%s\n' "$results" | jq -r '.result // empty' 2>/dev/null \
           | grep -E "SPLIT-CHILD-(DONE|HELD|FAILED): $FID( |\$)" | tail -n 1)

  if [ -e "$DIR/timed-out" ]; then
    status=TIMEOUT; detail="상한 ${tmin}분 초과"
  elif [ "$subtype" != success ]; then
    status=FAILED; detail="자식 종료 rc=$child_rc subtype=${subtype:-없음} — $ERR 확인"
  else
    case "$marker" in
      *"SPLIT-CHILD-DONE: $FID"*) status=DONE; detail="구현~성능 게이트 완료" ;;
      *"SPLIT-CHILD-HELD: $FID"*) status=HELD; detail="사용자 결정 필요 — $DIR/held.md" ;;
      *"SPLIT-CHILD-FAILED: $FID"*) status=FAILED; detail=$(printf '%s' "$marker" | cut -c1-200) ;;
      *) status=FAILED; detail="자식이 끝 마커 없이 종료" ;;
    esac
  fi

  jq -n --arg status "$status" --arg fid "$FID" --arg sid "$sid" --arg detail "$detail" \
        --arg cost "$cost" --arg turns "$turns" --arg mins "$mins" --arg text "$text" \
        '{status:$status, fid:$fid, session_id:$sid, detail:$detail, cost_usd:$cost, turns:$turns, minutes:$mins, summary:$text}' \
        > "$DIR/result.json" 2>/dev/null
  [ -n "$text" ] && printf '%s\n' "$text" | tail -n 8
  echo "SPLIT-RESULT: $status fid=$FID session=${sid:-없음} turns=${turns:-?} cost_usd=${cost:-?} minutes=$mins detail=$detail"
  case "$status" in DONE) exit 0 ;; HELD) exit 10 ;; TIMEOUT) exit 124 ;; *) exit 1 ;; esac
}

cmd_status() {
  local dir="$SPECOPS/$FID/split"
  if [ -r "$dir/result.json" ]; then
    jq -r '"결과: \(.status) — \(.detail) (\(.minutes)분 · 호출 \(.turns) · $\(.cost_usd))"' "$dir/result.json" 2>/dev/null
  elif [ -r "$dir/child.jsonl" ]; then
    echo "자식 세션 실행 중 — 이벤트 $(grep -c . "$dir/child.jsonl")줄"
  else
    echo "자식 세션 기록 없음($dir)"
  fi
  if [ -r "$SPECOPS/session-progress.md" ]; then
    awk -v fid="$FID" '$0 ~ "^## " { on = ($0 ~ fid) } on && /^- /' "$SPECOPS/session-progress.md" | head -n 5
  fi
  if [ -r "$dir/child.jsonl" ] && command -v jq >/dev/null 2>&1; then
    tail -n 60 "$dir/child.jsonl" \
      | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
               | "  · \(.name) \((.input.description // .input.skill // .input.subagent_type // .input.file_path // "") | tostring | .[0:70])"' 2>/dev/null \
      | tail -n 5
  fi
  return 0
}

# 현재 대화 크기 고지. 마지막 주 세션 응답의 usage(입력+캐시)가 곧 지금 맥락 크기다.
cmd_warn_size() {
  local t="${1:-}" limit tokens="" basis=usage
  limit=$(setting "${SPECOPS_SPLIT_WARN_TOKENS:-}" warn_context_tokens "$DEFAULT_WARN_TOKENS")
  case "$limit" in ''|*[!0-9]*) limit=$DEFAULT_WARN_TOKENS ;; esac
  [ "$limit" -gt 0 ] || return 0
  if [ -z "$t" ] && [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    local cand
    for cand in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$CLAUDE_CODE_SESSION_ID".jsonl; do
      [ -r "$cand" ] && { t="$cand"; break; }
    done
  fi
  [ -n "$t" ] && [ -r "$t" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    tokens=$(tail -n 400 "$t" | jq -r 'select(.type=="assistant" and (.isSidechain|not)) | .message.usage
              | ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))' 2>/dev/null | tail -n 1)
  fi
  case "$tokens" in ''|*[!0-9]*)
    basis="파일 크기 근사"
    tokens=$(( $(wc -c < "$t" | tr -d ' ') / BYTES_PER_TOKEN )) ;;
  esac
  [ "$tokens" -gt "$limit" ] || return 0
  echo "CONTEXT-LARGE: 현재 대화가 약 $((tokens / 1000))K 토큰입니다(기준 $((limit / 1000))K · $basis). 새 세션에서 시작하면 호출마다 다시 읽는 양이 줄어듭니다 — 그대로 진행해도 됩니다."
  return 0
}

sub="${1:-}"; [ "$#" -gt 0 ] && shift
case "$sub" in
  warn-size) cmd_warn_size "${1:-}" ;;
  decide|run|status)
    FID="${1:-}"; [ "$#" -gt 0 ] && shift
    is_fid "$FID" || { usage; exit 2; }
    case "$sub" in decide) cmd_decide ;; run) cmd_run "$@" ;; status) cmd_status ;; esac ;;
  *) usage; exit 2 ;;
esac
