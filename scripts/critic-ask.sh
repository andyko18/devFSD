#!/usr/bin/env bash
# 외부 모델 critic 위탁 래퍼 — advisory only (판정 권한 없음, provider 오류·timeout 도 exit 0)
# 사용: bash scripts/critic-ask.sh <prompt-file> [--files <f1> [f2 ...]]
# 환경: CRITIC_BIN (강제 provider — stdin 합성 프롬프트 / stdout 의견 계약) · CRITIC_TIMEOUT (기본 120s)
#       CRITIC_CLAUDE_MODEL (기본 opus) · CRITIC_CLAUDE_FALLBACK (기본 sonnet) — claude provider 모델 선택
# 출력: "CRITIC[<provider>]:" + 의견 / "CRITIC: SKIP (외부 CLI 부재)" / "CRITIC: FAIL (<사유>)"
# 종료: 항상 0 — prompt-file 부재만 1 (사용 오류)
set -uo pipefail

PROMPT_FILE="${1:?prompt-file required}"
# 플러그인이 싣고 온 프롬프트(`templates/critic-prompt-*.md`)를 상대경로로 부른 경우 — cwd 에 없으면 플러그인 루트에서 찾는다.
#   하류 저장소에는 templates/ 가 없어, 문서가 적어 둔 상대경로 그대로는 "prompt-file 부재" 로 끝났다(20261009).
#   폴백은 그 이름 형태에만 건다 — 아무 상대경로나 플러그인 루트에서 찾으면 오타 난 경로가 우연히 맞는 파일(README.md 등)을
#   조용히 외부 모델에 보내고, `..` 로 플러그인 밖을 읽는다. 폴백이 일어나면 무엇을 집었는지 stderr 로 알린다.
if [ ! -f "$PROMPT_FILE" ]; then
  case "$PROMPT_FILE" in
    *..*) ;;
    templates/critic-prompt-*.md)
       _ca_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
       if [ -f "$_ca_root/$PROMPT_FILE" ] && [ ! -L "$_ca_root/$PROMPT_FILE" ]; then
         PROMPT_FILE="$_ca_root/$PROMPT_FILE"
         echo "CRITIC: prompt-file 을 플러그인에서 찾음: $PROMPT_FILE" >&2
       fi ;;
  esac
fi
if [ ! -f "$PROMPT_FILE" ]; then
  echo "ERROR: prompt-file 부재: $PROMPT_FILE" >&2
  exit 1
fi
shift
FILES=()
if [ "${1:-}" = "--files" ]; then
  shift
  while [ $# -gt 0 ]; do FILES+=("$1"); shift; done
fi
TIMEOUT_S="${CRITIC_TIMEOUT:-120}"
MAX_BYTES=204800

# provider 감지: CRITIC_BIN > claude > codex > gemini > ollama (A-1)
# claude: advisor 백엔드 최우선 — claude code 사용자는 항상 보유. 모델은 opus 우선·sonnet fallback
#   (CRITIC_CLAUDE_MODEL / CRITIC_CLAUDE_FALLBACK 로 override). opus overload 시 claude 내장
#   --fallback-model 이 sonnet 으로 전환한다(공식 문서상 한도·과금 오류는 전환 대상이 아니다). 기본에 fable 을 쓰지 않는다(플랜에 따라 usage credits 과금·접근 불가 가능).
provider=""; bin=""
CLAUDE_MODEL="${CRITIC_CLAUDE_MODEL:-opus}"
CLAUDE_FALLBACK="${CRITIC_CLAUDE_FALLBACK:-sonnet}"
# preflight — command -v 는 PATH 의 stale shim(파일은 있으나 실행 불가·rc=127)을 못 걸러낸다
#   (dogfood 20260717 test2: claude 감지 후 실행 rc=127 → 외부 critic 실효 0 이 FAIL 로 위장).
#   --version 1회로 실행 가능성을 확인하고, 실패 시 그 provider 를 부재로 강등해 다음 후보로 cascade.
#   stale shim 은 즉시 실패하므로 hang 위험 낮음(</dev/null 로 stdin 대기 차단). CRITIC_BIN 은
#   사용자 강제 지정이라 preflight 제외(계약: stdin/stdout 만 요구 — --version 미보장).
_usable() {
  "$1" --version </dev/null >/dev/null 2>&1 && return 0
  echo "CRITIC: $1 감지됐으나 실행 불가(--version rc≠0) — stale shim/PATH 의심, 다음 후보 시도" >&2
  return 1
}
# 읽기 전용 호출 플래그를 이 CLI 가 지원하는지 --help 로 검출한다(버전 비교 대신 기능 검출).
#   미지원이면 플래그 없는 약한 호출로 되돌리지 않고 부재로 강등한다(fail closed — 도구·쓰기가 열린 채 위탁하지 않는다).
_sandboxable() {
  local h=""
  case "$1" in
    claude) h=$("$1" --help </dev/null 2>&1); case "$h" in *--tools*) case "$h" in *--strict-mcp-config*) return 0 ;; esac ;; esac ;;
    codex)  h=$("$1" exec --help </dev/null 2>&1); case "$h" in *--sandbox*) return 0 ;; esac ;;
    *) return 0 ;;
  esac
  echo "CRITIC: $1 가 읽기 전용 플래그를 지원하지 않음 — 다음 후보 시도" >&2
  return 1
}
if [ -n "${CRITIC_BIN:-}" ]; then
  provider="custom"; bin="$CRITIC_BIN"
elif command -v claude >/dev/null 2>&1 && _usable claude && _sandboxable claude; then
  provider="claude"; bin="claude"
elif command -v codex >/dev/null 2>&1 && _usable codex && _sandboxable codex; then
  provider="codex"; bin="codex"
elif command -v gemini >/dev/null 2>&1 && _usable gemini; then
  provider="gemini"; bin="gemini"
elif command -v ollama >/dev/null 2>&1 && curl -sf -m 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
  provider="ollama"; bin="ollama"   # 로컬 — 외부 송신 0
else
  echo "CRITIC: SKIP (외부 CLI 부재)"
  exit 0
fi

syn=""; out_f=""; err_f=""; mark=""; flag=""; pid=""
cleanup() { [ -n "${pid:-}" ] && { kill -TERM -- "-$pid"; pkill -P "$pid"; kill "$pid"; } 2>/dev/null; rm -f "$syn" "$syn.cut" "$out_f" "$err_f" "$mark" "$flag" 2>/dev/null; }
trap cleanup EXIT

# 프롬프트 합성: prompt-file + 구분자 + 대상 파일들 (NFR-3 200KB 절단)
syn=$(mktemp)
cat "$PROMPT_FILE" > "$syn"
for f in ${FILES+"${FILES[@]}"}; do
  [ -f "$f" ] || continue
  printf '\n--- 파일: %s ---\n' "$f" >> "$syn"
  cat "$f" >> "$syn"
done
size=$(wc -c < "$syn" | tr -d ' ')
if [ "$size" -gt "$MAX_BYTES" ]; then
  if command -v iconv >/dev/null 2>&1; then
    # UTF-8 불완전 꼬리 바이트 제거 (iconv 부재 시 기존 동작 graceful)
    head -c "$MAX_BYTES" "$syn" | iconv -c -f UTF-8 -t UTF-8 > "$syn.cut"
  else
    head -c "$MAX_BYTES" "$syn" > "$syn.cut"
  fi
  mv "$syn.cut" "$syn"
  printf '\n[절단: 합성 %sB > %sB — 앞부분만 위탁]\n' "$size" "$MAX_BYTES" >> "$syn"
  echo "CRITIC: 절단 적용 (${size}B → ${MAX_BYTES}B)" >&2
fi

_invoke_provider() {
  # stdin=합성 프롬프트 → stdout=의견.
  # 단일 명령 provider 는 exec — 백그라운드 서브셸이 곧 provider 가 되어 워치독의 `pkill -P "$pid"` 가
  #   provider 의 자식까지 닿는다(exec 없으면 시간초과 시 provider 자손이 남는다 — 20260929-run-evals-orphan-sleep 실측)
  # 읽기 전용 호출 — 실측(2026-10-02, claude 2.1.287 · codex-cli 0.153.2): claude 는 기본 호출에서 도구(Bash)를 실제 실행했고
  #   `--tools ""` 는 내장 도구만 끄고 사용자 전역 MCP 도구는 그대로 노출돼(실측: mcp__ 도구 보유 YES) `--strict-mcp-config` 를 함께 줘야 닫힌다(NO — 의견 생성 정상). codex 는 `exec --help` 가 `--sandbox read-only`·`--ephemeral`·stdin 프롬프트(`-`)를 내고,
  #   실제 호출은 외부 전송이라 하지 않았다. gemini 는 미설치라 실측하지 못했다 — 추측 플래그를 넣지 않았다(설치 후 본 함수만 보정).
  case "$provider" in
    custom) exec "$bin" ;;
    claude) exec claude -p --tools "" --strict-mcp-config --model "$CLAUDE_MODEL" --fallback-model "$CLAUDE_FALLBACK" ;;
    codex)  exec codex exec --sandbox read-only --ephemeral - ;;
    gemini) exec gemini -p - ;;
    ollama) jq -Rs --arg m "${CRITIC_MODEL:-qwen2.5:7b}" '{model:$m, prompt:., stream:false}' \
              | curl -sS -m "$TIMEOUT_S" http://localhost:11434/api/generate -d @- \
              | jq -r '.response // empty' ;;
  esac
}

out_f=$(mktemp); err_f=$(mktemp); mark=$(mktemp); rm -f "$mark"; flag=$(mktemp)
# 잡 컨트롤(set -m)로 실행기를 자기 프로세스 그룹의 리더로 띄운다 — 시간초과 때 `kill -- -$pid` 로 전 자손을 한 번에 끝낸다.
#   종전 `pkill -P` → `kill` 두 단계는 그 사이에 본체가 띄운 새 자식을 놓쳤다(20261112-flaky-tests-stabilize 실측 12회 중 8회 잔존).
set -m
_invoke_provider < "$syn" > "$out_f" 2>"$err_f" &
pid=$!
set +m
# 워치독 — 출력 차단 + 마커 + 자식 정리 (bash 3.2). 부모는 신호를 보내지 않고 flag 만 지운다 —
#   워치독이 1초 안에 스스로 끝난다(run-bounded.sh 와 같은 방식 · 신호 정리는 고아 sleep·멈춤을 남긴다 — 20260929-run-evals-orphan-sleep)
( lim=$TIMEOUT_S; case "$lim" in ''|*[!0-9]*) lim=${lim%%.*}; case "$lim" in ''|*[!0-9]*) lim=0 ;; esac; lim=$((lim + 1)) ;; esac
  n=0; while [ "$n" -lt "$lim" ]; do [ -e "$flag" ] || exit 0; sleep 1; n=$((n + 1)); done
  [ -e "$flag" ] || exit 0; : > "$mark"; kill -TERM -- "-$pid" 2>/dev/null; pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
wait "$pid" 2>/dev/null; rc=$?
pid=""
rm -f "$flag"

if [ -f "$mark" ]; then
  echo "CRITIC: FAIL (timeout ${TIMEOUT_S}s)"
  head -1 "$err_f" >&2 2>/dev/null || true
  exit 0
fi
if [ "$rc" -ne 0 ] || [ ! -s "$out_f" ]; then
  echo "CRITIC: FAIL (provider rc=$rc)"
  head -1 "$err_f" >&2 2>/dev/null || true
  exit 0
fi
echo "CRITIC[$provider]:"
cat "$out_f"
exit 0
