#!/usr/bin/env bash
# e2e-run.sh — 이 FID 의 실제 브라우저 시나리오(*.e2e.mjs)를 돌리고 한 줄로 판정한다 (20261119 · 선택 기능)
#
# 사용: e2e-run.sh <FID>
# 출력(마지막 줄):
#   E2E-RUN: PASS (<N>개 · 통과 <p> · 판정 보류 <t>)
#   E2E-RUN: FAIL (<N>개 · 통과 <p> · 실패 <f> · 판정 보류 <t>)   — 그 위에 실패한 시나리오 이름
#   E2E-RUN: SKIP (NO_TOOL|NO_SPEC|TIMEOUT — 사유)                  — 판정하지 못함. PASS 로 적지 않는다
#   전문은 .specops/<FID>/e2e/run.txt
# rc: 0 PASS · 1 FAIL · 3 SKIP · 2 사용법
#
# 무엇을 돌리나: 이름이 `*.e2e.mjs|js|cjs` 이고 본문에 `FID: <FID>` 줄이 있는 파일을 `node --test` 로 돌린다.
#   서버를 띄우고 끄는 일은 시나리오 쪽 몫이다(templates/e2e-support.mjs 의 startServer). 이 스크립트는 서버를 모른다.
#   파일은 하나씩 차례로 돈다(--test-concurrency=1) — 파일마다 같은 포트로 서버를 띄우면 동시에 돌 때 부딪힌다.
#   Playwright 는 시나리오가 e2e-support.mjs 로 찾는다 — 하류 node_modules → ~/.cache/devfsd/ui-harness (ui-probe 와 같은 곳).
# 판정 보류(todo): 시나리오가 `{ todo: '<사유>' }` 로 표시한 것 — 실패로 세지 않지만 숫자로 드러낸다.
# 상한: DEVFSD_E2E_TIMEOUT_SEC (기본 600).
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SPECOPS="${SPECOPS_ROOT:-.specops}"
FID="${1:-}"
case "$FID" in ''|*/*|*..*|-*) sed -n '4,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;; esac

skip() { echo "E2E-RUN: SKIP ($1)"; exit 3; }
command -v node >/dev/null 2>&1 || skip "NO_TOOL — node 없음"

files=()
while IFS= read -r f; do
  grep -qE "FID:[[:space:]]*$FID([^A-Za-z0-9-]|\$)" "$f" 2>/dev/null && files+=("$f")
done < <(find . \( -name node_modules -o -name .git -o -name dist -o -name build \) -prune -o \
           -type f \( -name '*.e2e.mjs' -o -name '*.e2e.js' -o -name '*.e2e.cjs' \) -print 2>/dev/null | sort)
[ "${#files[@]}" -gt 0 ] || skip "NO_SPEC — \`FID: $FID\` 줄이 있는 *.e2e 파일이 없다"

OUT_DIR="$SPECOPS/$FID/e2e"; mkdir -p "$OUT_DIR"; OUT="$OUT_DIR/run.txt"
limit="${DEVFSD_E2E_TIMEOUT_SEC:-600}"; case "$limit" in ''|*[!0-9]*|0) limit=600 ;; esac

# shellcheck source=/dev/null
. "$HERE/run-bounded.sh"
DEVFSD_UI_HARNESS_DIR="${DEVFSD_UI_HARNESS_DIR:-$HOME/.cache/devfsd/ui-harness}" \
  bounded_run "$limit" node --test --test-concurrency=1 --test-reporter=tap "${files[@]}" > "$OUT" 2>&1
rc=$?
if bounded_timed_out "$rc"; then skip "TIMEOUT — ${limit}초 초과($OUT)"; fi

num() { grep -E "^# $1 " "$OUT" | tail -n 1 | awk '{print $3}'; }
total=$(num tests); pass=$(num pass); fail=$(num fail); todo=$(num todo)
case "$total" in ''|*[!0-9]*) echo "  (요약을 읽지 못했다 — $OUT 확인)"; echo "E2E-RUN: FAIL (실행 실패 rc=$rc)"; exit 1 ;; esac
[ "$total" -gt 0 ] || skip "NO_SPEC — 시나리오가 0개 실행됐다($OUT)"

if [ "${fail:-0}" -gt 0 ] || [ "$rc" -ne 0 ]; then
  # 실패한 시나리오 이름(판정 보류는 `# TODO` 가 붙어 나온다 — 뺀다)
  grep -E '^[[:space:]]*not ok ' "$OUT" | grep -v '# TODO' | sed -E 's/^[[:space:]]*not ok [0-9]+ - /  - /' | head -n 20
  echo "E2E-RUN: FAIL (${total}개 · 통과 ${pass:-0} · 실패 ${fail:-0} · 판정 보류 ${todo:-0})"; exit 1
fi
echo "E2E-RUN: PASS (${total}개 · 통과 ${pass:-0} · 판정 보류 ${todo:-0})"
