#!/usr/bin/env bash
# e2e-mode.sh — 실제 브라우저 시나리오 게이트의 모드·기준을 정한다 (20261120 · 소스 전용)
#
# 사용: . e2e-mode.sh ; e2e_resolve          → E2E_MODE(off|observe|enforce) · E2E_MIN(0~100) · E2E_NOTES(줄바꿈 구분 알림)
#       e2e_observe_record <FID> <coverage|run> <true|false> <요약>   → $SPECOPS/e2e-observe.jsonl 에 한 줄
# 읽는 변수: SPECOPS(기본 .specops) · CONFIG(기본 $SPECOPS/config.yaml)
#
# 모드 (`.specops/config.yaml` 의 `browser_e2e.mode` · 환경변수 DEVFSD_BROWSER_E2E_MODE):
#   off      돌리지 않는다(기본)
#   observe  돌리되 막지 않는다 — 막았을 판정을 기록만 한다. 새 게이트는 여기서 시작해 오탐을 본 뒤 올린다
#   enforce  기준 미달이면 막는다
#   옛 표기 `enabled: true`(DEVFSD_BROWSER_E2E=1)는 mode 가 없을 때 enforce 로 읽는다.
#
# 왜 기준 브랜치에서 읽나 (20261120): 변경이 자기를 심사하는 기준을 고칠 수 있으면 그 검사는 깨진 것이다 —
#   같은 변경 안에서 min_coverage 를 95→50 으로 낮추거나 enforce 를 observe 로 바꾸면 통과할 수 있었다.
#   config 가 git 에 추적되면 **기준 브랜치(기본 브랜치와의 갈림점)의 값과 작업 트리 값 가운데 더 엄한 쪽**을 쓴다.
#   느슨하게 바꾸려면 그 변경을 먼저 기본 브랜치에 넣는다. 엄하게 바꾸는 것은 바로 적용된다.
#   환경변수는 엄하게만 바꿀 수 있다(낮추는 값은 무시하고 알린다).
#   한계: config 가 추적되지 않으면(.specops 를 통째로 ignore 한 저장소) 대조할 수 없다 — 그 사실을 알림 줄로 남긴다.
#         FID 마다 새로 만드는 `e2e-scope.txt` 는 기준 브랜치에 없으므로 이 방식으로 지키지 못한다(사유 필수·건수 표시로 드러낸다).

SPECOPS="${SPECOPS:-${SPECOPS_ROOT:-.specops}}"
CONFIG="${CONFIG:-${SPECOPS_CONFIG:-$SPECOPS/config.yaml}}"

# <파일> 의 browser_e2e: 블록에서 한 단계 키를 읽는다. 없으면 빈 문자열
e2e_cfg_from() {
  [ -r "$1" ] || return 0
  awk -v key="$2" '
    /^browser_e2e:[[:space:]]*(#.*)?$/ { inb = 1; next }
    inb && /^[^[:space:]#]/ { inb = 0 }
    inb {
      line = $0; sub(/[[:space:]]+#.*$/, "", line)
      if (match(line, "^[[:space:]]+" key ":[[:space:]]*")) {
        v = substr(line, RLENGTH + 1); sub(/[[:space:]]+$/, "", v); gsub(/^["\047]|["\047]$/, "", v); print v; exit
      }
    }' "$1"
}

_e2e_lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# <mode 값> <enabled 값> → off|observe|enforce. 모르는 mode 값은 가장 엄한 enforce 로 읽는다(오타로 게이트가 꺼지지 않게)
e2e_norm_mode() {
  local m e; m=$(_e2e_lower "$1"); e=$(_e2e_lower "$2")
  case "$m" in
    off|observe|enforce) printf '%s' "$m" ;;
    '') case "$e" in true|yes|on|1) printf 'enforce' ;; *) printf 'off' ;; esac ;;
    *) printf 'enforce' ;;
  esac
}

e2e_rank() { case "$1" in enforce) echo 2 ;; observe) echo 1 ;; *) echo 0 ;; esac; }

# 0~100 정수면 그대로, 아니면 빈 문자열
_e2e_pct() { case "$1" in ''|*[!0-9]*) return 0 ;; esac; [ "$1" -le 100 ] && printf '%s' "$1" || printf '100'; }

# 기준 브랜치의 config 를 임시 파일로 꺼낸다. stdout=임시 파일 경로 · rc 1=대조할 수 없음(추적 안 됨·git 아님·기준 없음)
_e2e_base_config() {
  command -v git >/dev/null 2>&1 || return 1
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  local tracked ref base tmp
  tracked=$(git ls-files --full-name --error-unmatch -- "$CONFIG" 2>/dev/null) || return 1
  ref=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -z "$ref" ]; then
    for ref in origin/main origin/develop origin/master main develop master; do
      git rev-parse --verify --quiet "$ref^{commit}" >/dev/null 2>&1 && break
      ref=""
    done
  fi
  [ -n "$ref" ] || return 1
  base=$(git merge-base HEAD "$ref" 2>/dev/null) || return 1
  [ -n "$base" ] || return 1
  tmp=$(mktemp) || return 1
  # 기준 시점에 파일이 없었으면 빈 파일 — "그때는 꺼져 있었다"로 읽는다
  git show "$base:$tracked" > "$tmp" 2>/dev/null || : > "$tmp"
  printf '%s' "$tmp"
}

e2e_resolve() {
  E2E_NOTES=""
  local w_mode w_min b_mode b_min basef env_mode env_min
  w_mode=$(e2e_norm_mode "$(e2e_cfg_from "$CONFIG" mode)" "$(e2e_cfg_from "$CONFIG" enabled)")
  w_min=$(_e2e_pct "$(e2e_cfg_from "$CONFIG" min_coverage)"); [ -n "$w_min" ] || w_min=95
  E2E_MODE="$w_mode"; E2E_MIN="$w_min"

  if basef=$(_e2e_base_config); then
    b_mode=$(e2e_norm_mode "$(e2e_cfg_from "$basef" mode)" "$(e2e_cfg_from "$basef" enabled)")
    b_min=$(_e2e_pct "$(e2e_cfg_from "$basef" min_coverage)"); [ -n "$b_min" ] || b_min=95
    rm -f "$basef"
    if [ "$(e2e_rank "$w_mode")" -lt "$(e2e_rank "$b_mode")" ]; then
      E2E_MODE="$b_mode"
      E2E_NOTES="${E2E_NOTES}  - 게이트 설정: 이 변경이 mode 를 $b_mode → $w_mode 로 느슨하게 바꿨다 — 기준 브랜치 값($b_mode)을 쓴다\n"
    fi
    # 기준 시점에 게이트가 켜져 있었을 때만 그때의 기준을 바닥으로 삼는다(처음 켜는 변경은 스스로 기준을 정한다)
    if [ "$b_mode" != off ] && [ "$w_min" -lt "$b_min" ]; then
      E2E_MIN="$b_min"
      E2E_NOTES="${E2E_NOTES}  - 게이트 설정: 이 변경이 min_coverage 를 $b_min → $w_min 으로 낮췄다 — 기준 브랜치 값(${b_min}%)을 쓴다\n"
    fi
  elif [ "$w_mode" != off ]; then
    E2E_NOTES="${E2E_NOTES}  - 게이트 설정 출처: 작업 트리(기준 브랜치와 대조하지 못했다 — $CONFIG 가 git 에 추적되지 않거나 기준 브랜치를 찾지 못했다)\n"
  fi

  # 환경변수는 엄하게만 바꾼다
  env_mode="${DEVFSD_BROWSER_E2E_MODE:-}"
  [ -n "$env_mode" ] || case "$(_e2e_lower "${DEVFSD_BROWSER_E2E:-}")" in true|yes|on|1) env_mode=enforce ;; esac
  if [ -n "$env_mode" ]; then
    env_mode=$(e2e_norm_mode "$env_mode" "")
    if [ "$(e2e_rank "$env_mode")" -ge "$(e2e_rank "$E2E_MODE")" ]; then E2E_MODE="$env_mode"
    else E2E_NOTES="${E2E_NOTES}  - 게이트 설정: 환경변수로 mode 를 낮출 수 없다($E2E_MODE → $env_mode 무시)\n"; fi
  fi
  env_min=$(_e2e_pct "${DEVFSD_E2E_MIN_COVERAGE:-}")
  if [ -n "$env_min" ]; then
    if [ "$env_min" -ge "$E2E_MIN" ]; then E2E_MIN="$env_min"
    else E2E_NOTES="${E2E_NOTES}  - 게이트 설정: 환경변수로 기준을 낮출 수 없다(${E2E_MIN}% → ${env_min}% 무시)\n"; fi
  fi
}

# 관찰 기록 한 줄 — 막았을 판정인지와 요약. 쓰지 못해도 판정을 바꾸지 않는다
e2e_observe_record() {
  local fid="$1" kind="$2" would="$3" detail="$4" f="$SPECOPS/e2e-observe.jsonl" ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p "$SPECOPS" 2>/dev/null || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ts "$ts" --arg fid "$fid" --arg kind "$kind" --argjson would "$would" --arg detail "$detail" \
      '{ts:$ts, fid:$fid, kind:$kind, would_block:$would, detail:$detail}' >> "$f" 2>/dev/null || true
  else
    detail=$(printf '%s' "$detail" | tr -d '"\\' | tr '\n' ' ')
    printf '{"ts":"%s","fid":"%s","kind":"%s","would_block":%s,"detail":"%s"}\n' "$ts" "$fid" "$kind" "$would" "$detail" >> "$f" 2>/dev/null || true
  fi
}
