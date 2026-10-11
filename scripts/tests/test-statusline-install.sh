#!/usr/bin/env bash
# statusline-install.sh 인자 계약 (FID 20260829-statusline-check)
#
# 왜: 이 스크립트는 **인자 처리가 전혀 없었다**. `--help` 를 줘도 그대로 설치를 실행해
#   `.claude/settings.json` 을 고쳤다(커맨드 전수 점검 중 실측 — 의도치 않게 설치됨).
#   `.claude/` 는 gitignore 라 `git status` 에도 안 보여서, 파일을 직접 열기 전엔 모른다.
#   이 repo 의 다른 도구는 전부 미리보기 경로를 갖는다 — design-screen `--check` ·
#   release `--dry-run` · mutation-score `--check-conf` · validate-structure `--json`.
#   설치기만 없었고, 하필 **부작용이 사용자 설정**이라 가장 필요한 자리였다.
# 종료코드 계약(--check): 0 = 이미 동일(변경 없음) · 1 = 변경 발생 예정 · 2 = 사용 오류.
#   `--check-conf` 의 0/1 관용구와 같다 — 1 은 "에러" 가 아니라 "차이 있음" 이다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0
SH="$PLUGIN/scripts/statusline-install.sh"
[ -f "$SH" ] || { echo "FATAL: $SH 부재" >&2; exit 1; }

_sb() { mktemp -d; }   # 각 케이스는 격리 cwd 에서 — 실 .claude 를 절대 건드리지 않는다

# ── T1: --help → usage 출력 + **설치 안 함** + exit 0 ──
sb=$(_sb); out=$(cd "$sb" && bash "$SH" --help 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qi 'usage' && [ ! -e "$sb/.claude" ]; } \
  && ok "T1 --help → usage + 설치 안 함 (rc=0)" \
  || nope "T1 --help" "rc=$rc claude존재=$([ -e "$sb/.claude" ] && echo Y || echo N) out=${out:0:60}"
rm -rf "$sb"

# ── T2: 알 수 없는 인자 → exit 2 + 설치 안 함 (조용한 설치 금지) ──
sb=$(_sb); out=$(cd "$sb" && bash "$SH" --nope 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && [ ! -e "$sb/.claude" ]; } \
  && ok "T2 ★ 미지 인자 → exit 2, 설치 안 함" \
  || nope "T2 미지 인자" "rc=$rc claude존재=$([ -e "$sb/.claude" ] && echo Y || echo N)"
rm -rf "$sb"

# ── T3: --check (미설치) → 예정 내용 표시 + 파일 미생성 + exit 1 ──
sb=$(_sb); out=$(cd "$sb" && bash "$SH" --check 2>&1); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'statusline.sh' && [ ! -e "$sb/.claude" ]; } \
  && ok "T3 ★ --check 미설치 → 차이 보고(rc=1), 파일 미생성" \
  || nope "T3 --check 미설치" "rc=$rc claude존재=$([ -e "$sb/.claude" ] && echo Y || echo N) out=${out:0:70}"
rm -rf "$sb"

# ── T4: --check (이미 동일) → exit 0 + 내용 무변경 ──
sb=$(_sb)
( cd "$sb" && bash "$SH" >/dev/null 2>&1 )
before=$(cat "$sb/.claude/settings.json" 2>/dev/null)
out=$(cd "$sb" && bash "$SH" --check 2>&1); rc=$?
after=$(cat "$sb/.claude/settings.json" 2>/dev/null)
{ [ "$rc" -eq 0 ] && [ "$before" = "$after" ]; } \
  && ok "T4 --check 동일 → rc=0, 내용 무변경" \
  || nope "T4 --check 동일" "rc=$rc 변경=$([ "$before" = "$after" ] && echo N || echo Y)"
rm -rf "$sb"

# ── T5: 인자 없음 → 실제 설치 + 멱등 (기존 동작 회귀) ──
sb=$(_sb)
out=$(cd "$sb" && bash "$SH" 2>&1); rc=$?
first=$(cat "$sb/.claude/settings.json" 2>/dev/null)
out2=$(cd "$sb" && bash "$SH" 2>&1); rc2=$?
second=$(cat "$sb/.claude/settings.json" 2>/dev/null)
{ [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] && [ -n "$first" ] && [ "$first" = "$second" ]; } \
  && ok "T5 무인자 설치 + 멱등 (기존 동작 보존)" \
  || nope "T5 설치" "rc=$rc rc2=$rc2 멱등=$([ "$first" = "$second" ] && echo Y || echo N)"
rm -rf "$sb"

# ── T6: 기존 statusLine 존재 시 .bak 백업 (기존 동작 회귀) ──
sb=$(_sb); mkdir -p "$sb/.claude"
printf '{"statusLine":{"type":"command","command":"/old/x.sh"}}\n' > "$sb/.claude/settings.json"
( cd "$sb" && bash "$SH" >/dev/null 2>&1 )
[ -f "$sb/.claude/settings.json.bak" ] \
  && ok "T6 기존 statusLine → .bak 백업" || nope "T6 백업" ".bak 미생성"
rm -rf "$sb"

# ── T7: --check 는 기존 키를 보존한다 (설정 오염 0) ──
# 왜 별건인가: 미리보기가 다른 키를 건드리면 "안전한 확인" 이라는 말이 거짓이 된다.
sb=$(_sb); mkdir -p "$sb/.claude"
printf '{"enabledPlugins":{"x":true}}\n' > "$sb/.claude/settings.json"
b=$(cat "$sb/.claude/settings.json")
( cd "$sb" && bash "$SH" --check >/dev/null 2>&1 )
a=$(cat "$sb/.claude/settings.json")
[ "$b" = "$a" ] && ok "T7 --check 는 기존 설정 무접촉" || nope "T7 오염" "settings.json 변경됨"
rm -rf "$sb"

echo ""
finish
