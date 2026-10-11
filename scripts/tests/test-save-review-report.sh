#!/usr/bin/env bash
# test-save-review-report — SubagentStop 리뷰 저장 훅 (AC-1~5·9~11) + hooks.json 배선 (AC-6)
# FID 20260914-review-return-summary
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq 필요" >&2; exit 1; }
HOOK="$PLUGIN/hooks/save-review-report.sh"
# 전용 루트 아래에 작업 디렉토리를 둔다 — T1.g 가 $TD 상위 목록을 비교하므로 상위가 공유 $TMPDIR 이면 동시 실행 프로세스 때문에 오탐한다
TDROOT=$(mktemp -d); TD="$TDROOT/w"; mkdir -p "$TD"; trap 'rm -rf "$TDROOT"' EXIT
FID=20260914-demo
R="$TD/.specops/$FID/reviews"

_reset() { rm -rf "$TD/.specops"; mkdir -p "$R"; }
# $1=tid $2=phase $3=verdict $4=body
_block() { printf '<<<REVIEW fid=%s tid=%s phase=%s verdict=%s>>>\n%s\n<<<END>>>\n' "$FID" "$1" "$2" "$3" "$4"; }
# $1=message $2=true|false → RC, ERR, OUT
# stdout 은 버리지 않고 파일로 받는다 — FR-3(stdout 공백)은 위생이 아니라 FR-1 의 성립 전제다
#   (stdout 에 JSON 을 쓰면 종료 코드가 통째로 무시된다). 훅은 1회만 실행한다 —
#   두 번 돌리면 저장 부작용이 두 번 나서 파일 상태를 단언하는 T1.* 가 깨진다.
# mktemp 는 $TD·$TDROOT **밖**에 만든다 — 안에 두면 _files()·T1.g 의 트리 비교에 잡혀 오탐한다.
_run() {
  local json so
  json=$(jq -n --arg cwd "$TD" --arg m "$1" --argjson a "$2" \
    '{hook_event_name:"SubagentStop",agent_type:"specops-ko:code-reviewer-ko",cwd:$cwd,stop_hook_active:$a,last_assistant_message:$m}')
  so=$(mktemp)
  ERR=$(printf '%s' "$json" | env -u SPECOPS_GOVERNANCE_PROFILE PATH="${RUN_PATH:-$PATH}" SPECOPS_CONFIG="$TD/none.yaml" bash "$HOOK" 2>&1 >"$so")
  RC=$?
  OUT=$(cat "$so"); rm -f "$so"
}
_files() { (cd "$TD" && find . -type f | LC_ALL=C sort); }
_leftover() { ls -A "$R" | grep -E '\.(tmp|bak)\.' ; }  # 이번 실행의 임시·백업 파일 잔존

# ── T1.a AC-1 다중 tid 분할 저장 ──
_reset
msg="요약 전 전문
$(_block T1 C READY_TO_MERGE '# T1 본문
## 🔴 Critical
없음')
$(_block T2 C READY_TO_MERGE '# T2 본문')
$(_block T3 C READY_TO_MERGE '# T3 본문')"
_run "$msg" false
if [ "$(cat "$R/T1-C-report.md" 2>/dev/null)" = "$(printf '# T1 본문\n## 🔴 Critical\n없음')" ] \
   && [ "$(cat "$R/T2-C-report.md" 2>/dev/null)" = "# T2 본문" ] \
   && [ "$(cat "$R/T3-C-report.md" 2>/dev/null)" = "# T3 본문" ]; then
  ok "T1.a AC-1 tid 3개 분할 저장 · 본문 혼입 0"
else nope "T1.a AC-1" "rc=$RC $(ls "$R" 2>/dev/null | tr '\n' ' ')"; fi
if ! ls "$R"/*-feedback.md >/dev/null 2>&1; then ok "T1.b AC-1 통과 판정 → feedback 미생성"
else nope "T1.b AC-1" "feedback 생성됨"; fi

# ── T1.c AC-3 2단 종료 신호 (첫 실행 exit 2 + 경로·요약 지시) ──
if [ "$RC" -eq 2 ] && echo "$ERR" | grep -qF ".specops/$FID/reviews/T1-C-report.md" \
   && echo "$ERR" | grep -qF ".specops/$FID/reviews/T3-C-report.md" && echo "$ERR" | grep -qF "요약만 출력"; then
  ok "T1.c AC-3 exit 2 + 저장 경로 + 요약 지시"
else nope "T1.c AC-3" "rc=$RC err=$ERR"; fi

# ── T1.d AC-3 재발화(stop_hook_active=true) → exit 0 · 내용·mtime 불변 ──
before=$(cd "$R" && cksum *.md)
touch "$TD/stamp"; sleep 1
_run "$(_block T1 C NEEDS_FIX '다른 본문')" true
after=$(cd "$R" && cksum *.md)
newer=$(find "$R" -type f -newer "$TD/stamp")
if [ "$RC" -eq 0 ] && [ "$before" = "$after" ] && [ -z "$newer" ] && [ ! -f "$R/T1-C-feedback.md" ]; then
  ok "T1.d AC-3 stop_hook_active=true → exit 0 내용·mtime 불변"
else nope "T1.d AC-3" "rc=$RC"; fi

# ── T1.e AC-2 비통과 판정 feedback 병기 ──
_reset
_run "$(_block T2 B NEEDS_FIX '# B 지적')
$(_block T3 C NEEDS_DISCUSSION '# C 논의')" false
if [ "$RC" -eq 2 ] && cmp -s "$R/T2-B-report.md" "$R/T2-B-feedback.md" \
   && cmp -s "$R/T3-C-report.md" "$R/T3-C-feedback.md" && [ "$(cat "$R/T2-B-feedback.md")" = "# B 지적" ]; then
  ok "T1.e AC-2 NEEDS_FIX·NEEDS_DISCUSSION → report+feedback 동일 본문"
else nope "T1.e AC-2" "rc=$RC $(ls "$R" | tr '\n' ' ')"; fi

# ── T1.f AC-4 fail-open 4경우 (기존 파일 보존 · 신규 0) ──
#  $1=desc $2=message $3=runner(선택: jq-less) $4=기대 rc(선택: 기본 0)
#  기대 rc 를 인자로 받는다 — f1·f2·f4 는 계약 판정이라 exit 1 이고 f3(jq 부재)만 인프라라 exit 0 이다.
#  헬퍼 본문에 0 을 박으면 두 성격이 같은 기대를 공유해 계약 변경이 인프라 침묵까지 끌고 간다.
#  $5=silent 이면 stderr 공백까지 단언한다 — AC-3 은 인프라 경로(f3=jq 부재)에 stderr 길이 0 을 요구한다.
#  f1·f2·f4 는 계약 판정이라 사유 1줄이 있어야 하므로 헬퍼 본문에 무조건 걸 수 없다.
_fail_open() {
  _reset; printf 'X\n' > "$R/T1-C-report.md"; local pre so errok=0; pre=$(_files)
  if [ "${3:-}" = "nojq" ]; then
    mkdir -p "$TD/bin"
    for t in cat dirname mktemp awk cp mv rm mkdir bash env; do ln -sf "$(command -v $t)" "$TD/bin/$t"; done
    json=$(jq -n --arg cwd "$TD" --arg m "$2" '{cwd:$cwd,stop_hook_active:false,last_assistant_message:$m}')
    # 이 분기는 _run 을 타지 않으므로 OUT 을 여기서 직접 채운다 — 안 채우면 직전 _run 의
    #   값이 남아 아래 [ -z "$OUT" ] 가 이번 실행이 아닌 과거를 단언한다(AC-6 이 막는 빈 단언).
    #   mktemp·cat 은 PATH= 접두 밖이라 실제 PATH 를 쓴다($TD/bin 과 무관).
    so=$(mktemp)
    ERR=$(printf '%s' "$json" | PATH="$TD/bin" SPECOPS_CONFIG="$TD/none.yaml" "$BASH" "$HOOK" 2>&1 >"$so"); RC=$?
    OUT=$(cat "$so"); rm -f "$so"
    rm -rf "$TD/bin"
  else
    _run "$2" false
  fi
  if [ "${5:-}" = "silent" ] && [ -n "$ERR" ]; then errok=1; fi
  if [ "$RC" -eq "${4:-0}" ] && [ "$errok" -eq 0 ] && [ -z "$OUT" ] && [ "$(cat "$R/T1-C-report.md")" = "X" ] && [ "$(_files)" = "$pre" ]; then ok "$1"
  else nope "$1" "rc=$RC out=$OUT err=$ERR files=$(_files | tr '\n' ' ')"; fi
}
_fail_open "T1.f1 AC-4 마커 0개" "그냥 보고서 텍스트" "" 1
_fail_open "T1.f2 AC-4 END 없는 미완 블록" "$(printf '<<<REVIEW fid=%s tid=T1 phase=C verdict=READY_TO_MERGE>>>\n본문' "$FID")" "" 1
_fail_open "T1.f3 AC-4·AC-3 jq 부재 → rc=0 · stdout·stderr 공백" "$(_block T1 C READY_TO_MERGE '본문')" nojq 0 silent
_fail_open "T1.f4 AC-4 FID 디렉토리 부재" "$(printf '<<<REVIEW fid=20260101-nope tid=T1 phase=C verdict=READY_TO_MERGE>>>\n본문\n<<<END>>>')" "" 1

# ── T1.g AC-5 경로 안전 — 비정상 값은 전부 무생성 ──
for bad in 'fid=../../etc tid=T1 phase=C verdict=PASS' \
           "fid=$FID tid=T1/../x phase=C verdict=PASS" \
           "fid=$FID tid=T1a phase=C verdict=PASS" \
           "fid=$FID tid=T1 phase=D verdict=PASS" \
           "fid=$FID tid=T1 phase=C verdict=OK"; do
  # 이탈 목표가 실제로 존재해야 이빨이 선다 — 없으면 정규식이 없어도 디렉토리 검사·cp 실패가 대신 막는다
  #   fid=../../etc → $TD/.specops/../../etc = $TDROOT/etc · tid=T1/../x → 임시 $R/.T1/.. · 목적지 $R/T1/..
  _reset; mkdir -p "$TDROOT/etc" "$R/.T1" "$R/T1"
  up_pre=$(cd "$TDROOT" && find . -type f | LC_ALL=C sort)
  _run "$(printf '<<<REVIEW %s>>>\n본문\n<<<END>>>' "$bad")" false
  if [ "$RC" -eq 1 ] && [ "$(cd "$TDROOT" && find . -type f | LC_ALL=C sort)" = "$up_pre" ]; then ok "T1.g AC-5 거부: $bad"
  else nope "T1.g AC-5 $bad" "rc=$RC files=$(_files | tr '\n' ' ')"; fi
done
rm -rf "$TDROOT/etc"
_reset
_run "$(_block T1 B PASS '# B 통과')
$(_block T1 C READY_TO_MERGE '# C 통과')" false
if [ "$RC" -eq 2 ] && [ -f "$R/T1-B-report.md" ] && [ -f "$R/T1-C-report.md" ] && ! ls "$R"/*-feedback.md >/dev/null 2>&1; then
  ok "T1.h AC-5 정상 PASS·READY_TO_MERGE → report 만"
else nope "T1.h AC-5" "rc=$RC $(ls "$R" | tr '\n' ' ')"; fi

# ── T1.i AC-9 부분 유효 → 전부 포기 ──
_reset; printf 'X\n' > "$R/T1-C-report.md"; pre=$(_files)
_run "$(_block T1 C READY_TO_MERGE '새 T1')
$(_block T2 C READY_TO_MERGE '새 T2')
$(printf '<<<REVIEW fid=%s tid=T3 phase=C verdict=READY_TO_MERGE>>>\n끝 없음' "$FID")" false
if [ "$RC" -eq 1 ] && [ "$(cat "$R/T1-C-report.md")" = "X" ] && [ "$(_files)" = "$pre" ]; then
  ok "T1.i AC-9 블록 1개 오류 → 전체 무저장 exit 1"
else nope "T1.i AC-9" "rc=$RC files=$(_files | tr '\n' ' ')"; fi
_reset; pre=$(_files)
_run "$(_block T1 C READY_TO_MERGE '정상')
$(printf '<<<REVIEW fid=%s tid=T2 phase=C verdict=OK>>>\n본문\n<<<END>>>' "$FID")" false
if [ "$RC" -eq 1 ] && [ "$(_files)" = "$pre" ]; then ok "T1.j AC-9 허용값 밖 속성 섞임 → 전체 무저장"
else nope "T1.j AC-9" "rc=$RC"; fi

# ── T1.k AC-10 동일 tid·phase 중복 ──
_reset; pre=$(_files)
_run "$(_block T1 C READY_TO_MERGE '첫째')
$(_block T1 C READY_TO_MERGE '둘째')" false
if [ "$RC" -eq 1 ] && [ "$(_files)" = "$pre" ]; then ok "T1.k AC-10 중복 tid·phase → 무저장"
else nope "T1.k AC-10" "rc=$RC"; fi
_reset
_run "$(_block T1 B PASS 'B')
$(_block T1 C READY_TO_MERGE 'C')" false
if [ "$RC" -eq 2 ] && [ -f "$R/T1-B-report.md" ] && [ -f "$R/T1-C-report.md" ]; then ok "T1.l AC-10 같은 tid 다른 phase → 둘 다 저장"
else nope "T1.l AC-10" "rc=$RC"; fi

# ── T1.m AC-11 재리뷰 덮어쓰기 · feedback 보존 ──
_reset; printf 'A\n' > "$R/T2-C-report.md"; printf 'A\n' > "$R/T2-C-feedback.md"
_run "$(_block T2 C READY_TO_MERGE 'B')" false
if [ "$RC" -eq 2 ] && [ "$(cat "$R/T2-C-report.md")" = "B" ] && [ "$(cat "$R/T2-C-feedback.md")" = "A" ] \
   && [ -z "$(_leftover)" ]; then
  ok "T1.m AC-11 report 덮어쓰기 · 이전 feedback 보존 · 임시·백업 파일 잔존 0"
else nope "T1.m AC-11" "rc=$RC report=$(cat "$R/T2-C-report.md") $(ls -A "$R" | tr '\n' ' ')"; fi

# ── T1.n AC-9 2단계 이동 부분 실패 → 전부 되돌림 · exit 0 · stderr 없음 ──
# 이동 실패 주입: PATH 앞 가짜 mv (목적지가 *-C-report.md 일 때만 무음 실패) — chflags 는 macOS 전용
REALMV=$(command -v mv)
FAKEBIN=$(mktemp -d); trap 'rm -rf "$TDROOT" "$FAKEBIN"' EXIT
cat > "$FAKEBIN/mv" <<EOF
#!/usr/bin/env bash
for last in "\$@"; do :; done
case "\$last" in *-C-report.md) exit 1 ;; esac
exec "$REALMV" "\$@"
EOF
chmod +x "$FAKEBIN/mv"
_reset; printf 'OLD\n' > "$R/T1-C-report.md"; pre=$(_files)
RUN_PATH="$FAKEBIN:$PATH" _run "$(_block T1 C NEEDS_FIX 'NEW')" false
if [ "$RC" -eq 0 ] && [ -z "$ERR" ] && [ -z "$OUT" ] && [ "$(cat "$R/T1-C-report.md")" = "OLD" ] && [ ! -e "$R/T1-C-feedback.md" ] \
   && [ "$(_files)" = "$pre" ] && [ -z "$(_leftover)" ]; then
  ok "T1.n1 AC-9 이동 실패 → 기존 report 보존 · feedback 미생성 · 임시·백업 잔존 0 · stdout 공백"
else nope "T1.n1 AC-9" "rc=$RC err=$ERR out=$OUT report=$(cat "$R/T1-C-report.md" 2>/dev/null) $(ls -A "$R" | tr '\n' ' ')"; fi
# 앞 블록 이동 성공 후 뒤 블록 실패 — 기존 파일은 백업에서 복원, 새로 생긴 파일은 제거
_reset; printf 'OLD-B\n' > "$R/T2-B-report.md"; pre=$(_files)
RUN_PATH="$FAKEBIN:$PATH" _run "$(_block T2 B NEEDS_FIX 'NEW-B')
$(_block T3 B PASS 'NEW-T3')
$(_block T1 C NEEDS_FIX 'NEW-C')" false
if [ "$RC" -eq 0 ] && [ -z "$ERR" ] && [ -z "$OUT" ] && [ "$(cat "$R/T2-B-report.md")" = "OLD-B" ] \
   && [ ! -e "$R/T2-B-feedback.md" ] && [ ! -e "$R/T3-B-report.md" ] && [ "$(_files)" = "$pre" ] && [ -z "$(_leftover)" ]; then
  ok "T1.n2 AC-9 뒤 블록 이동 실패 → 옮긴 파일 복원(기존)·제거(신규) · 잔존 0 · stdout 공백"
else nope "T1.n2 AC-9" "rc=$RC err=$ERR out=$OUT files=$(_files | tr '\n' ' ') $(ls -A "$R" | tr '\n' ' ')"; fi

# ── T1.o AC-9 공백만 있는 본문 → 전체 무저장 ──
_reset; pre=$(_files)
_run "$(_block T1 C READY_TO_MERGE 'ok')
$(printf '<<<REVIEW fid=%s tid=T2 phase=C verdict=NEEDS_FIX>>>\n   \n\t\n\n<<<END>>>' "$FID")" false
if [ "$RC" -eq 1 ] && [ "$(_files)" = "$pre" ]; then ok "T1.o AC-9 공백만 있는 본문 → 전체 무저장 exit 1"
else nope "T1.o AC-9" "rc=$RC files=$(_files | tr '\n' ' ')"; fi

# ── T1.p AC-9 대상 경로가 일반 파일 아님(디렉토리) → 전체 무저장 · 거짓 보고 없음 ──
_reset; mkdir -p "$R/T2-C-report.md"; pre=$(cd "$TD" && find . | LC_ALL=C sort)
_run "$(_block T1 C READY_TO_MERGE 'T1')
$(_block T2 C READY_TO_MERGE 'T2')" false
if [ "$RC" -eq 0 ] && [ -z "$ERR" ] && [ -z "$OUT" ] && [ "$(cd "$TD" && find . | LC_ALL=C sort)" = "$pre" ]; then
  ok "T1.p AC-9 대상이 디렉토리 → 전체 무저장 exit 0 · 저장 보고 없음 · stdout 공백"
else nope "T1.p AC-9" "rc=$RC err=$ERR out=$OUT tree=$(cd "$TD" && find . | tr '\n' ' ')"; fi

# ── T1.q AC-9 FID 혼합 → 전체 무저장 (두 FID 모두 실재 · tid 달리해 중복 검사와 분리) ──
FID2=20260914-other
_reset; mkdir -p "$TD/.specops/$FID2"; pre=$(cd "$TD" && find . | LC_ALL=C sort)
_run "$(_block T1 C READY_TO_MERGE 'A')
$(printf '<<<REVIEW fid=%s tid=T2 phase=C verdict=READY_TO_MERGE>>>\nB\n<<<END>>>' "$FID2")" false
if [ "$RC" -eq 1 ] && [ "$(cd "$TD" && find . | LC_ALL=C sort)" = "$pre" ]; then ok "T1.q AC-9 FID 혼합 → 전체 무저장 exit 1"
else nope "T1.q AC-9" "rc=$RC tree=$(cd "$TD" && find . | tr '\n' ' ')"; fi

# ── T1.r AC-9 이동 실패 후 복원 cp 까지 실패 → 그 파일의 백업 보존 · exit 0 · stderr 없음 ──
# 주입: 가짜 mv(목적지 *-feedback.md 만 실패) + 가짜 cp(목적지에 .tmp.·.bak. 없으면 실패 = 복원 cp 만 실패)
REALCP=$(command -v cp)
FAKEBIN_R="$FAKEBIN/restore-fail"; mkdir -p "$FAKEBIN_R"
cat > "$FAKEBIN_R/mv" <<EOF
#!/usr/bin/env bash
for last in "\$@"; do :; done
case "\$last" in *-feedback.md) exit 1 ;; esac
exec "$REALMV" "\$@"
EOF
cat > "$FAKEBIN_R/cp" <<EOF
#!/usr/bin/env bash
for last in "\$@"; do :; done
case "\$last" in *.tmp.*|*.bak.*) exec "$REALCP" "\$@" ;; esac
exit 1
EOF
chmod +x "$FAKEBIN_R/mv" "$FAKEBIN_R/cp"
_reset; printf 'OLD\n' > "$R/T1-C-report.md"
RUN_PATH="$FAKEBIN_R:$PATH" _run "$(_block T1 C NEEDS_FIX 'NEW')" false
baks=$(ls -A "$R" | grep -E '^\.T1-C-report\.md\.bak\.' || true)
nbak=$(printf '%s' "$baks" | grep -c . || true)
if [ "$RC" -eq 0 ] && [ -z "$ERR" ] && [ -z "$OUT" ] && [ "$nbak" = "1" ] && [ "$(cat "$R/$baks" 2>/dev/null)" = "OLD" ]; then
  ok "T1.r AC-9 복원 cp 실패 → 백업(.<name>.bak.<pid>) 보존 · 내용 OLD · exit 0 · stderr·stdout 없음"
else nope "T1.r AC-9" "rc=$RC err=$ERR out=$OUT nbak=$nbak $(ls -A "$R" | tr '\n' ' ')"; fi

# ── T2.a AC-6 hooks.json SubagentStop 배선 ──
HJ="$PLUGIN/hooks/hooks.json"
m=$(jq -r '.hooks.SubagentStop[0].matcher // empty' "$HJ")
c=$(jq -r '.hooks.SubagentStop[0].hooks[0].command // empty' "$HJ")
a=$(jq -r '.hooks.SubagentStop[0].hooks[0].async' "$HJ")
if [ "$m" = "specops-ko:spec-reviewer-ko|specops-ko:code-reviewer-ko" ]; then ok "T2.a AC-6 matcher = 네임스페이스 포함 두 리뷰어"
else nope "T2.a AC-6 matcher" "'$m'"; fi
if printf '%s' "$c" | grep -qF '${CLAUDE_PLUGIN_ROOT}/hooks/save-review-report.sh'; then ok "T2.b AC-6 command 경로"
else nope "T2.b AC-6 command" "'$c'"; fi
if [ "$a" = "false" ]; then ok "T2.c AC-6 async=false (stderr 가 서브에이전트에 닿아야 한다)"
else nope "T2.c AC-6 async" "'$a'"; fi
if [ "$(jq -r '.hooks.SubagentStop | length' "$HJ")" = "1" ]; then ok "T2.d AC-6 SubagentStop 항목 1개"
else nope "T2.d AC-6 항목 수"; fi

# ── T3 AC-1 계약 판정 6종 — exit 1 + 구별되는 사유(stderr 첫 줄) · stdout 공백 ──
# AC-1 은 "stderr 첫 줄"을 요구하므로 head -1 로 위치를 고정한다 — 위치 무관 매치는 계약보다 느슨하다.
# stdout 공백은 전 케이스에서 함께 단언한다(FR-3).
_c() {
  if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | head -1 | grep -qF "$2"; then ok "$1"
  else nope "$1" "rc=$RC out=$OUT err=$ERR"; fi
}

_reset; _run "그냥 보고서 텍스트" false
_c "T3.a AC-1 블록 0건 → exit 1 + 사유" 'save-review-report: REVIEW 블록 없음 또는 열림·닫힘 짝 불일치 — 저장 건너뜀'

_reset; _run "$(printf '<<<REVIEW fid=%s tid=T1 phase=C verdict=OK>>>\n본문\n<<<END>>>' "$FID")" false
_c "T3.b AC-1 meta 형식 불일치 → exit 1 + 사유" 'save-review-report: meta 형식 불일치(fid·tid·phase·verdict 필요) — 저장 건너뜀'

_reset; _run "$(_block T1 C READY_TO_MERGE 'A')
$(printf '<<<REVIEW fid=20260101-other tid=T2 phase=C verdict=PASS>>>\nB\n<<<END>>>')" false
_c "T3.c AC-1 FID 불일치 → exit 1 + 사유" 'save-review-report: 블록 간 FID 불일치 — 저장 건너뜀'

_reset; _run "$(_block T1 C READY_TO_MERGE '첫째')
$(_block T1 C READY_TO_MERGE '둘째')" false
_c "T3.d AC-1 tid-phase 중복 → exit 1 + 사유" 'save-review-report: tid-phase 중복 — 저장 건너뜀'

_reset; _run "$(_block T1 C READY_TO_MERGE '   ')" false
_c "T3.e AC-1 빈 본문 → exit 1 + 사유" 'save-review-report: 본문이 비어 있음 — 저장 건너뜀'

_reset; _run "$(printf '<<<REVIEW fid=20260101-nope tid=T1 phase=C verdict=PASS>>>\n본문\n<<<END>>>')" false
_c "T3.f AC-1 FID 디렉터리 부재 → exit 1 + 사유" 'save-review-report: FID 디렉터리 없음(cwd 확인) — 저장 건너뜀'

# ── T3.f2 AC-1 사유 6종이 서로 구별된다 — 구현 리터럴을 직접 잠근다 ──
#   위 T3.a~f 는 각 케이스가 "기대 문자열을 내는지" 만 본다. 구현과 테스트를 **함께** 고쳐
#   두 사유를 같게 만들면 그 단언들은 통과한다(같은 출처 공유). 구현 파일에서 _bail 인자를
#   직접 뽑아 중복 0 을 단언해 그 경로를 닫는다.
_reasons=$(grep -oE '_bail "[^"]+"' "$HOOK" | sed 's/^_bail "//; s/"$//')
_rn=$(printf '%s\n' "$_reasons" | grep -c .)
_rdup=$(printf '%s\n' "$_reasons" | LC_ALL=C sort | uniq -d)
if [ "$_rn" -eq 6 ] && [ -z "$_rdup" ]; then ok "T3.f2 AC-1 _bail 사유 6종 · 중복 0"
else nope "T3.f2 AC-1 사유 구별" "n=$_rn dup=[$_rdup]"; fi

# ── T3.g AC-6 음성 대조 — 정상 경로에는 사유 접두가 없다 · stdout 공백 · rc=2 ──
_reset; _run "$(_block T1 B PASS 'B 본문')" false
if [ "$RC" -eq 2 ] && [ -z "$OUT" ] && ! printf '%s' "$ERR" | grep -qF 'save-review-report:'; then
  ok "T3.g AC-6 정상 경로 → 사유 접두 미출현 · stdout 공백"
else nope "T3.g AC-6" "rc=$RC out=$OUT err=$ERR"; fi

# ── T3.h AC-3 인프라 경로는 침묵 — rc=0 · stdout·stderr 모두 공백 ──
_reset; _run "$(_block T1 B PASS 'B')" true
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
  ok "T3.h AC-3 stop_hook_active → rc=0 · stdout·stderr 공백"
else nope "T3.h AC-3" "rc=$RC out=$OUT err=$ERR"; fi

# ── T3.i~T3.o AC-3 인프라·파일 조작 경로 7건 — rc=0 · stdout·stderr 공백 ──
# AC-3 Given 이 나열한 경로 중 종전 스위트가 단언하지 않던 몫이다(커버 완료분: jq=T1.f3 · stop_hook_active=T3.h ·
#   대상 검사=T1.p · 이동=T1.n1·n2·r). cwd 와 msg 는 같은 줄의 다른 조건이라 케이스를 나누고,
#   백업 실패는 복원 cp 실패(T1.r)와 다른 절이라 따로 둔다 — 둘 다 AC-3 Given 문안이 열거한 경로다.
# ⚠️ 음성 단언(rc=0 · 공백)은 그 경로에 **도달하지 못해도** 통과한다. 그래서 케이스마다 도달 증거를 함께 건다:
#   (a) 가짜·래퍼 바이너리의 호출 로그를 **내용으로** 단언 (mktemp·mkdir·cp) — 비어있지 않음만 보면 앞 케이스의
#       잔여 줄로 무음 통과하므로 실행 직전 truncate 하고 정확히 무엇이 불렸는지 비교한다
#   (b) 게이트만 없앤 같은 입력의 대조 실행이 rc=2 로 저장까지 간다 (훅 비활성·cwd·msg)
# 가짜 bin 과 로그는 $FAKEBIN 하위에 둔다 — $TD·$TDROOT 안에 두면 _files()·T1.g 트리 비교가 오탐한다.
INFRA="$FAKEBIN/infra"; mkdir -p "$INFRA"; LOG="$INFRA/log"; CPREAL=$(command -v cp); MDREAL=$(command -v mkdir)

# _run 의 형제 — cwd 를 지정하고 추가 env 를 주입할 수 있다(_run 은 SPECOPS_GOVERNANCE_PROFILE 을 env -u 로 지운다).
#   _run 을 고치지 않는다 — 기존 24개 케이스가 그 시그니처에 걸려 있다.
# $1=message $2=stop_hook_active $3=cwd $4.. = VAR=값(선택) → RC, ERR, OUT
_run_env() {
  local msg=$1 active=$2 cwd=$3; shift 3
  local json so
  json=$(jq -n --arg cwd "$cwd" --arg m "$msg" --argjson a "$active" \
    '{hook_event_name:"SubagentStop",agent_type:"specops-ko:code-reviewer-ko",cwd:$cwd,stop_hook_active:$a,last_assistant_message:$m}')
  so=$(mktemp)
  ERR=$(printf '%s' "$json" | env -u SPECOPS_GOVERNANCE_PROFILE PATH="${RUN_PATH:-$PATH}" \
    SPECOPS_CONFIG="$TD/none.yaml" "$@" bash "$HOOK" 2>&1 >"$so")
  RC=$?
  OUT=$(cat "$so"); rm -f "$so"
}
_silent() { [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; }
BODY=$(_block T1 C NEEDS_FIX 'NEW')

# T3.i 훅 비활성 — is-hook-enabled 가 rc=1. 프로파일 env 로 유도한다: config yaml 경로는 pyyaml 없는 머신에서
#   default enabled 로 떨어져 rc=2 오FAIL 이 된다(그 경로는 수동 프로브로 따로 확인했다).
_reset; _run_env "$BODY" false "$TD" SPECOPS_GOVERNANCE_PROFILE=standard
off_rc=$RC; off_out=$OUT; off_err=$ERR; off_saved=$(ls -A "$R" | tr '\n' ' ')
_reset; _run_env "$BODY" false "$TD"
if [ "$off_rc" -eq 0 ] && [ -z "$off_out" ] && [ -z "$off_err" ] && [ -z "$off_saved" ] \
   && [ "$RC" -eq 2 ] && [ -f "$R/T1-C-report.md" ]; then
  ok "T3.i AC-3 훅 비활성 → rc=0 · stdout·stderr 공백 · 무저장 (대조: 활성이면 rc=2 저장)"
else nope "T3.i AC-3" "off(rc=$off_rc out=$off_out err=$off_err saved=$off_saved) on(rc=$RC)"; fi

# T3.j cwd 빈값
_reset; _run_env "$BODY" false ""
e_rc=$RC; e_out=$OUT; e_err=$ERR; e_saved=$(ls -A "$R" | tr '\n' ' ')
_reset; _run_env "$BODY" false "$TD"
if [ "$e_rc" -eq 0 ] && [ -z "$e_out" ] && [ -z "$e_err" ] && [ -z "$e_saved" ] \
   && [ "$RC" -eq 2 ] && [ -f "$R/T1-C-report.md" ]; then
  ok "T3.j AC-3 cwd 빈값 → rc=0 · stdout·stderr 공백 · 무저장 (대조: cwd 있으면 rc=2 저장)"
else nope "T3.j AC-3" "empty(rc=$e_rc out=$e_out err=$e_err saved=$e_saved) on(rc=$RC)"; fi

# T3.k last_assistant_message 빈값
_reset; _run_env "" false "$TD"
m_rc=$RC; m_out=$OUT; m_err=$ERR; m_saved=$(ls -A "$R" | tr '\n' ' ')
_reset; _run_env "$BODY" false "$TD"
if [ "$m_rc" -eq 0 ] && [ -z "$m_out" ] && [ -z "$m_err" ] && [ -z "$m_saved" ] \
   && [ "$RC" -eq 2 ] && [ -f "$R/T1-C-report.md" ]; then
  ok "T3.k AC-3 msg 빈값 → rc=0 · stdout·stderr 공백 · 무저장 (대조: msg 있으면 rc=2 저장)"
else nope "T3.k AC-3" "empty(rc=$m_rc out=$m_out err=$m_err saved=$m_saved) on(rc=$RC)"; fi

# T3.l mktemp 실패 — PATH 앞 가짜 mktemp(호출을 로그에 남기고 무음 실패)
FB_MK="$INFRA/mktemp-fail"; mkdir -p "$FB_MK"
cat > "$FB_MK/mktemp" <<EOF
#!/usr/bin/env bash
echo "mktemp \$*" >> "$LOG"
exit 1
EOF
chmod +x "$FB_MK/mktemp"
_reset; printf 'OLD\n' > "$R/T1-C-report.md"; pre=$(_files); : > "$LOG"
RUN_PATH="$FB_MK:$PATH" _run_env "$BODY" false "$TD"
if _silent && [ "$(cat "$LOG")" = "mktemp -d" ] && [ "$(cat "$R/T1-C-report.md")" = "OLD" ] \
   && [ "$(_files)" = "$pre" ] && [ -z "$(_leftover)" ]; then
  ok "T3.l AC-3 mktemp 실패 → rc=0 · 공백 · 호출 로그 'mktemp -d' · 기존 파일 보존"
else nope "T3.l AC-3" "rc=$RC out=$OUT err=$ERR log=[$(cat "$LOG")] $(ls -A "$R" | tr '\n' ' ')"; fi

# T3.m mkdir 실패 — reviews 자리에 일반 파일을 두어 실제로 실패시키고, 래퍼가 호출 도달을 로그로 남긴다.
#   $R 이 디렉토리가 아니므로 이 케이스에서는 _reset·_leftover 를 쓸 수 없다.
FB_MD="$INFRA/mkdir-log"; mkdir -p "$FB_MD"
cat > "$FB_MD/mkdir" <<EOF
#!/usr/bin/env bash
echo "mkdir \$*" >> "$LOG"
exec "$MDREAL" "\$@"
EOF
chmod +x "$FB_MD/mkdir"
rm -rf "$TD/.specops"; mkdir -p "$TD/.specops/$FID"; printf 'blocker\n' > "$R"; pre=$(_files); : > "$LOG"
RUN_PATH="$FB_MD:$PATH" _run_env "$BODY" false "$TD"
if _silent && [ "$(cat "$LOG")" = "mkdir -p $R" ] && [ -f "$R" ] \
   && [ "$(cat "$R")" = "blocker" ] && [ "$(_files)" = "$pre" ]; then
  ok "T3.m AC-3 mkdir 실패 → rc=0 · 공백 · 호출 로그 'mkdir -p <reviews>' · 트리 무변경"
else nope "T3.m AC-3" "rc=$RC out=$OUT err=$ERR log=[$(cat "$LOG")] files=$(_files | tr '\n' ' ')"; fi

# T3.n 임시 쓰기 실패 — 가짜 cp(목적지가 *.tmp.* 일 때만 실패)로 1단계에서 좌초시킨다.
#   기존 대상을 미리 둔다: 백업 cp 가 뒤따르는 절이라 로그의 **.bak. 부재**가 "임시 쓰기에서 멈췄다"의 증거다.
FB_TW="$INFRA/tmpwrite-fail"; mkdir -p "$FB_TW"
cat > "$FB_TW/cp" <<EOF
#!/usr/bin/env bash
for last in "\$@"; do :; done
echo "cp -> \$last" >> "$LOG"
case "\$last" in *.tmp.*) exit 1 ;; esac
exec "$CPREAL" "\$@"
EOF
chmod +x "$FB_TW/cp"
_reset; printf 'OLD\n' > "$R/T1-C-report.md"; pre=$(_files); : > "$LOG"
RUN_PATH="$FB_TW:$PATH" _run_env "$BODY" false "$TD"
if _silent && [ "$(grep -c '\.tmp\.' "$LOG")" -eq 1 ] && [ "$(grep -c '\.bak\.' "$LOG")" -eq 0 ] \
   && [ "$(cat "$R/T1-C-report.md")" = "OLD" ] && [ "$(_files)" = "$pre" ] && [ -z "$(_leftover)" ]; then
  ok "T3.n AC-3 임시 쓰기 실패 → rc=0 · 공백 · .tmp. 시도 1회·.bak. 미도달 · 기존 파일 보존 · 잔존 0"
else nope "T3.n AC-3" "rc=$RC out=$OUT err=$ERR log=[$(cat "$LOG")] $(ls -A "$R" | tr '\n' ' ')"; fi

# T3.o 백업 실패 — 가짜 cp(목적지가 *.bak.* 일 때만 실패). 임시 쓰기는 성공하므로 로그에 **둘 다** 남는다 —
#   이 비대칭이 T3.n 과 이 케이스를 구별한다(같은 로그면 둘 중 하나는 다른 절을 재검사하는 중복이다).
FB_BK="$INFRA/backup-fail"; mkdir -p "$FB_BK"
cat > "$FB_BK/cp" <<EOF
#!/usr/bin/env bash
for last in "\$@"; do :; done
echo "cp -> \$last" >> "$LOG"
case "\$last" in *.bak.*) exit 1 ;; esac
exec "$CPREAL" "\$@"
EOF
chmod +x "$FB_BK/cp"
_reset; printf 'OLD\n' > "$R/T1-C-report.md"; pre=$(_files); : > "$LOG"
RUN_PATH="$FB_BK:$PATH" _run_env "$BODY" false "$TD"
if _silent && [ "$(grep -c '\.tmp\.' "$LOG")" -eq 1 ] && [ "$(grep -c '\.bak\.' "$LOG")" -eq 1 ] \
   && [ "$(cat "$R/T1-C-report.md")" = "OLD" ] && [ "$(_files)" = "$pre" ] && [ -z "$(_leftover)" ]; then
  ok "T3.o AC-3 백업 실패 → rc=0 · 공백 · .tmp. 성공 후 .bak. 실패 · 기존 파일 보존 · 잔존 0"
else nope "T3.o AC-3" "rc=$RC out=$OUT err=$ERR log=[$(cat "$LOG")] $(ls -A "$R" | tr '\n' ' ')"; fi

# ── T6 두 SubagentStop 동시 종료 (20261006-review-bc-parallel) — 최초 B/C 병렬 dispatch ──
#   B·C 가 같은 FID 에서 동시에 끝나도 두 report 가 모두 저장되고 서로의 파일·백업을 건드리지 않는다.
_reset
_msgB="$(_block T1 B PASS '# B 통과')"
_msgC="$(_block T1 C READY_TO_MERGE '# C 통과')"
_jb=$(jq -n --arg cwd "$TD" --arg m "$_msgB" '{hook_event_name:"SubagentStop",agent_type:"specops-ko:spec-reviewer-ko",cwd:$cwd,stop_hook_active:false,last_assistant_message:$m}')
_jc=$(jq -n --arg cwd "$TD" --arg m "$_msgC" '{hook_event_name:"SubagentStop",agent_type:"specops-ko:code-reviewer-ko",cwd:$cwd,stop_hook_active:false,last_assistant_message:$m}')
_rb=$(mktemp); _rc=$(mktemp)
for _i in 1 2 3 4 5; do
  _reset
  (printf '%s' "$_jb" | env -u SPECOPS_GOVERNANCE_PROFILE SPECOPS_CONFIG="$TD/none.yaml" bash "$HOOK" >/dev/null 2>"$_rb"; echo $? > "$_rb.rc") &
  (printf '%s' "$_jc" | env -u SPECOPS_GOVERNANCE_PROFILE SPECOPS_CONFIG="$TD/none.yaml" bash "$HOOK" >/dev/null 2>"$_rc"; echo $? > "$_rc.rc") &
  wait
  if ! { [ -f "$R/T1-B-report.md" ] && [ -f "$R/T1-C-report.md" ] && [ -z "$(_leftover)" ] \
         && grep -qF '# B 통과' "$R/T1-B-report.md" && grep -qF '# C 통과' "$R/T1-C-report.md" \
         && [ "$(cat "$_rb.rc")" -eq 2 ] && [ "$(cat "$_rc.rc")" -eq 2 ]; }; then
    _bad="round=$_i rb=$(cat "$_rb.rc") rc=$(cat "$_rc.rc") files=$(ls -A "$R" | tr '\n' ' ')"; break
  fi
done
rm -f "$_rb" "$_rc" "$_rb.rc" "$_rc.rc"
if [ -z "${_bad:-}" ]; then ok "T6.a B·C 동시 종료 5회 — 두 report 모두 저장·교차 오염 0·백업 잔존 0 (rc 2/2)"
else nope "T6.a 동시 종료" "$_bad"; fi

finish
