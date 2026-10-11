#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCRIPT="$PLUGIN/scripts/_internal/init-project.sh"

# T-split.a 임의 cwd 에서 source 시 헬퍼+phase 전 함수 로드 (main 미실행)
out=$(cd /tmp && source "$SCRIPT" 2>/dev/null; type -t _replace_line_prefix; type -t phase_8_artifacts; type -t phase_1_precheck)
if [ "$(printf '%s' "$out" | grep -c '^function$')" = "3" ]; then
  ok "T-split.a source 시 lib+early+artifacts 함수 로드"
else
  nope "T-split.a source 로드" "함수 미로드 (got: $out)"
fi

# T-split.b source 가드 — source 시 main 자동 실행 안 됨 (산출물 생성 없음)
tmpd=$(mktemp -d) || exit 1
( cd "$tmpd" && source "$SCRIPT" 2>/dev/null )
if [ ! -f "$tmpd/CLAUDE.md" ]; then ok "T-split.b source 가드 — main 미자동실행"; else nope "T-split.b 가드" "source 가 main 실행함"; fi
rm -rf "$tmpd"

# ── _parse_numbered 값 정확성 (20260806 init-project 정밀분석) ───────────────
# 실측 결함: 라벨 없는 `N. <값>` 형식이 번호를 벗기지 못해 값에 "1. " 이 그대로 남는다.
#   → PRD.md §1 · CLAUDE.md · README.md · requirements.md FR 시드행까지 전파.
#   기존 테스트는 파일 **존재·개수**만 봐서 이 형식을 먹이고도 전부 PASS 했다(값 미검증).
#   `_phase_4_count_filled` 는 "비어있지 않음"만 세므로 오파싱은 fallback 도 못 깨운다 —
#   silent garbage 경로.
# 두 형식 모두 지원해야 한다: 프롬프트가 보여주는 라벨형 + Phase 0 파이프의 자연스러운 무라벨형.
source "$SCRIPT" 2>/dev/null

_pn() { _parse_numbered "$1" "$2"; }

_LABELED='1. 한 줄 설명: 사내 일정 관리
2. 페르소나: 팀장
4. M1: 로그인'
[ "$(_pn "$_LABELED" 1)" = "사내 일정 관리" ] \
  && ok "T-pn.a 라벨형 — 번호+라벨 제거" || nope "T-pn.a" "got='$(_pn "$_LABELED" 1)'"
[ "$(_pn "$_LABELED" 4)" = "로그인" ] \
  && ok "T-pn.b 라벨형 M1" || nope "T-pn.b" "got='$(_pn "$_LABELED" 4)'"

_BARE='1. 사내 일정 관리
2. 팀장
4. 로그인'
[ "$(_pn "$_BARE" 1)" = "사내 일정 관리" ] \
  && ok "T-pn.c 무라벨형 — 번호 제거 (실측 결함)" || nope "T-pn.c" "got='$(_pn "$_BARE" 1)'"
[ "$(_pn "$_BARE" 4)" = "로그인" ] \
  && ok "T-pn.d 무라벨형 M1" || nope "T-pn.d" "got='$(_pn "$_BARE" 4)'"

# 값에 콜론이 늦게 등장하는 긴 문장은 라벨로 오인해 잘라내면 안 된다
_LONG='1. 사용자가 일정을 등록하고 팀원과 공유하는 서비스인데 목표는 다음과 같다: 빠른 조회'
[ "$(_pn "$_LONG" 1)" = "사용자가 일정을 등록하고 팀원과 공유하는 서비스인데 목표는 다음과 같다: 빠른 조회" ] \
  && ok "T-pn.e 긴 문장 내 콜론 보존 (라벨 오인 금지)" || nope "T-pn.e" "got='$(_pn "$_LONG" 1)'"

# T-pn.wire: awk index() 단위 고정 (로케일 이식성) — 20260807 Linux CI red 회귀 락
#   awk(BWK, macOS)=바이트 · gawk(UTF-8, Linux)=문자. 한글 3배 차이로 임계 40 이 갈린다.
#   T-pn.e 는 **macOS 에서는 LC_ALL=C 없이도 통과**하므로 행동 테스트만으로는 이 축을 못 잡는다
#   (실측: macOS index=102 / gawk UTF-8 index=40 — 경계에 정확히 걸림).
grep -q 'LC_ALL=C awk' "$PLUGIN/scripts/_internal/init-project/lib.sh" \
  && ok "T-pn.wire _parse_numbered awk 로케일 고정(LC_ALL=C)" \
  || nope "T-pn.wire" "LC_ALL=C 부재 — gawk 에서 index() 가 문자 단위가 되어 긴 문장이 절단된다"

# T-pn.gawk: gawk 가 있으면 **awk 를 gawk 로 강제**하고 UTF-8 로케일에서 행동 확인.
#   PATH 앞에 gawk→awk 심볼릭 링크 디렉터리를 끼워 _parse_numbered 내부의 `awk` 를 실제로 바꾼다
#   (앞선 시도는 bash -c 로 함수를 export 하려 해서 정작 _pn 은 정상 awk 를 썼다 — 공허했다).
if command -v gawk >/dev/null 2>&1; then
  _shim=$(mktemp -d)
  ln -s "$(command -v gawk)" "$_shim/awk"
  _g=$(PATH="$_shim:$PATH" LC_ALL=en_US.UTF-8 bash -c '
        source "$1/scripts/_internal/init-project/lib.sh" 2>/dev/null || exit 9
        _parse_numbered "$2" 1' _ "$PLUGIN" "$_LONG" 2>/dev/null)
  rm -rf "$_shim"
  [ "$_g" = "사용자가 일정을 등록하고 팀원과 공유하는 서비스인데 목표는 다음과 같다: 빠른 조회" ] \
    && ok "T-pn.gawk gawk+UTF-8 로케일에서도 보존 (Linux 거동 재현)" \
    || nope "T-pn.gawk" "got='$_g' — gawk 문자 단위 index() 로 절단됨"
else
  skip "T-pn.gawk (gawk 부재 — CI Linux 가 실제 커버)"
fi

# 부재 번호는 빈 문자열
[ -z "$(_pn "$_BARE" 3)" ] && ok "T-pn.f 부재 번호 → 빈 값" || nope "T-pn.f" "got='$(_pn "$_BARE" 3)'"

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
