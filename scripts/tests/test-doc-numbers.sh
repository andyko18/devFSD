#!/usr/bin/env bash
# doc-lock 검사 스위트 — 마커 대조·미마커 금지·경로 allowlist·비-git 트리 판정
# run-all: 이 스위트는 sandbox 트리(mktemp)만 쓴다 — 실 트리 쓰기 0
#
# ★ 자기 충돌 회피: 이 파일은 "수치 + 한글 단위어" 리터럴을 쓰지 않는다 — 한글 토큰을
#   printf 로 조립한다. 리터럴을 두면 tracked 되는 순간 자기 스캔에 걸려
#   검사가 자기 자신 때문에 FAIL 한다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
# ★★ 훅 환경 격리 — 반드시 sandbox git 호출보다 앞에 온다.
#   git 은 pre-push 훅에 GIT_DIR 를 export 하고 run-all 은 그 훅에서 돈다. 떼지 않으면
#   아래 sandbox 의 `git init`·`git add -A` 가 **실 저장소 인덱스**에 기록해 실 트리 파일
#   전체가 스테이징 삭제로 뒤집힌다(실측: 구현 중 이 사고를 실제로 냈다 — 작업 트리는
#   무손상이나 인덱스가 오염됐다). 검사 본체에도 같은 unset 이 있으나 그것만으로는
#   이 스위트 자신의 git 호출을 막지 못한다.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
# 로케일 고정 — 검사 본체(:21) 와 대칭. 미고정이면 아래 grep -E "$RE" 의 한글 바이트 패턴이
#   조용히 매치를 멈추고, "0건이어야 함" 단언인 T2.c 가 공허하게 통과한다.
export LC_ALL=C.UTF-8
PASS=0; FAIL=0; SKIP=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

# ── temp 정리 + 실 인덱스 감시 ────────────────────────────────
# trap: set -u 조기 종료·중단(Ctrl-C) 경로에서 sandbox 디렉터리가 남는 누수를 막는다.
_tmps=()
_reg() { [ -n "${1:-}" ] && _tmps+=("$1"); return 0; }
_cleanup() { local t; for t in "${_tmps[@]:-}"; do [ -n "$t" ] && rm -rf "$t"; done; }
trap _cleanup EXIT
# 실 저장소 인덱스 지문 — 이 스위트의 git 호출이 실 인덱스에 닿았는지 T5.a 가 판정한다.
#   ★ 이것은 **사후 탐지**다. 예방은 위 env unset 과 아래 sb 가드·헬퍼 가드가 한다.
#     손상을 막지는 못하지만, 손상이 무음으로 지나가지는 못하게 한다.
_idx_sig() { printf '%s/%s' \
  "$(git -C "$PLUGIN" ls-files 2>/dev/null | wc -l | tr -d ' ')" \
  "$(git -C "$PLUGIN" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')"; }
_idx_before=$(_idx_sig)

CHK="$PLUGIN/scripts/_internal/check-doc-numbers.sh"
WORD=$(printf '\xec\x8a\xa4\xec\x9c\x84\xed\x8a\xb8')
RE="[0-9]{2,4}[[:space:]]*$WORD"
# 픽스처 기대 실측: validate-structure 무조건 1 + test 파일 9 = 10.
#   ★ 두 자리여야 한다 — 검사 정규식이 [0-9]{2,4} 라 한 자리 픽스처는 아예 스캔되지 않아
#   T1.b~T1.d 가 공허하게 통과한다(초안의 결함 — 구현 중 실측으로 정정).
EXP=10

# ── sandbox 구축 ─────────────────────────────────────────────
# git add -A 가 필수다 — add 없이는 git ls-files 가 0건이라
# 검사가 아무것도 스캔하지 않고 공허 통과한다.
_mksandbox() {
  local d
  d=$(mktemp -d "${TMPDIR:-/tmp}/docnum.XXXXXX") || return 1
  mkdir -p "$d/scripts/_internal" "$d/docs" \
           "$d/scripts/tests/dag" "$d/scripts/tests/governance" \
           "$d/scripts/tests/llm-eval" "$d/scripts/tests/test-convention" \
           "$d/scripts/tests/freecomment" "$d/scripts/tests/promote"
  : > "$d/scripts/_internal/validate-structure.sh"
  # 7개 수집 디렉터리를 모두 덮는다 — 검사의 수집 목록에서 한 줄이 빠지면
  #   실측이 줄어 T1.a 가 잡는다(디렉터리 누락 실패 모드 검출).
  : > "$d/scripts/tests/test-a.sh"
  : > "$d/scripts/tests/test-b.sh"
  : > "$d/scripts/tests/test-c.sh"
  : > "$d/scripts/tests/dag/test-d.sh"
  : > "$d/scripts/tests/governance/test-e.sh"
  : > "$d/scripts/tests/llm-eval/test-f.sh"
  : > "$d/scripts/tests/test-convention/test-g.sh"
  : > "$d/scripts/tests/freecomment/test-h.sh"
  : > "$d/scripts/tests/promote/test-i.sh"
  ( cd "$d" && git init -q && git add -A ) >/dev/null 2>&1 || return 1
  printf '%s' "$d"
}
# ★★ 헬퍼 자신이 빈 sandbox 인자를 거부한다 — 방어를 호출부에만 두면 다음에 어서션을
#   추가하는 사람이 같은 문을 다시 연다. `cd ""` 는 bash 에서 **rc=0 no-op** 이라
#   가드가 없으면 `git add -A` 가 **cwd = 실 트리**에서 돌아 실 인덱스를 오염시킨다
#   (실측: 사본에서 인덱스 571→573 · untracked 캐너리가 스테이징됨).
_addfile() { # <sandbox> <상대경로> <내용>
  [ -n "${1:-}" ] || return 1
  mkdir -p "$(dirname "$1/$2")"; printf '%s\n' "$3" > "$1/$2"
  ( cd "$1" && git add -A ) >/dev/null 2>&1
}
_rmfile() { # <sandbox> <상대경로>
  [ -n "${1:-}" ] || return 1
  rm -f "$1/$2"; ( cd "$1" && git add -A ) >/dev/null 2>&1
}
# _run·_rc 도 빈 루트를 거부한다 — DOC_NUMBERS_ROOT="" 는 검사에서 show-toplevel 로 폴백해
#   **실 트리**를 판정 대상으로 삼는다(읽기 전용이지만 어서션이 조용히 대상을 갈아탄다).
#   _rc 는 rc 자리에 97(=호출 오류)을 내 어서션이 요란하게 실패하도록 한다.
_run() { [ -n "${1:-}" ] || { printf 'FATAL: _run 에 빈 루트'; return 1; }; DOC_NUMBERS_ROOT="$1" bash "$CHK" 2>&1; }
_rc()  { [ -n "${1:-}" ] || { printf '%s' 97; return 0; }; DOC_NUMBERS_ROOT="$1" bash "$CHK" >/dev/null 2>&1; printf '%s' "$?"; }

# ── T1.a 실측 계산: 픽스처를 정확히 센다 ──
sb=$(_mksandbox) || nope "T1.a" "sandbox 생성 실패"
# ★★ sandbox 가 없으면 **즉시 종료한다**. nope 는 FAIL 을 세고 그대로 진행하므로, 이 가드가
#   없으면 아래 _addfile "$sb" … 가 sb="" 로 호출되고 `cd ""`(rc=0 no-op) 때문에
#   `git add -A` 가 실 트리에서 반복 실행된다. 실측 트리거는 TMPDIR 불가(mktemp 실패)이며,
#   그때 스위트 출력은 이 부작용을 한 줄도 말하지 않았다 — 조용한 인덱스 오염이었다.
[ -n "${sb:-}" ] || { nope "T1.a-guard" "sandbox 없이는 진행하지 않는다 — 실 인덱스 보호를 위해 즉시 종료"; finish; exit 1; }
_reg "$sb"
out=$(_run "$sb")
case "$out" in
  *"suite-count=$EXP"*) ok "T1.a 실측 계산 = $EXP (validate-structure 1 + 수집 파일 9)" ;;
  *) nope "T1.a" "실측 $EXP 이 아니다 — 실제: $out" ;;
esac

# ── T1.b 마커 대조 PASS: 값이 실측과 같으면 통과 ──
_addfile "$sb" docs/lock.md "게이트는 $EXP $WORD 를 돈다 <!-- doc-lock: suite-count -->"
[ "$(_rc "$sb")" = 0 ] \
  && ok "T1.b 마커 값이 실측과 일치 → rc=0" \
  || nope "T1.b" "일치하는데 FAIL — $(_run "$sb")"

# ── T1.c 마커 대조 FAIL: 값이 다르면 4요소 리포트 + rc=1 (AC-1) ──
_addfile "$sb" docs/lock.md "게이트는 $((EXP+1)) $WORD 를 돈다 <!-- doc-lock: suite-count -->"
out=$(_run "$sb"); rc=$(_rc "$sb")
if [ "$rc" = 1 ] \
   && printf '%s' "$out" | grep -q 'docs/lock.md' \
   && printf '%s' "$out" | grep -q ":1 " \
   && printf '%s' "$out" | grep -q "기대=$EXP" \
   && printf '%s' "$out" | grep -q "실제=$((EXP+1))"; then
  ok "T1.c 마커 불일치 → rc=1 + 경로·줄·기대·실제 리포트 (AC-1)"
else
  nope "T1.c" "rc=$rc · 출력: $out"
fi

# ── T1.d 미마커 금지: 마커·allowlist 없으면 rc=1 + 조치 2종 (AC-2) ──
# lock.md 를 실측값으로 원복해 둔다 — 그래야 이 케이스의 rc=1 이 bare.md 때문임이 확정된다
# (원복 자체가 rc 를 0 으로 되돌린다는 실증은 T4 되돌려-관찰이 담당한다).
_addfile "$sb" docs/lock.md "게이트는 $EXP $WORD 를 돈다 <!-- doc-lock: suite-count -->"
_addfile "$sb" docs/bare.md "예전엔 99 $WORD 였다"
out=$(_run "$sb"); rc=$(_rc "$sb")
if [ "$rc" = 1 ] \
   && printf '%s' "$out" | grep -q 'docs/bare.md' \
   && printf '%s' "$out" | grep -q 'doc-lock: suite-count' \
   && printf '%s' "$out" | grep -q 'doc-lock: historical'; then
  ok "T1.d 미마커 → rc=1 + 조치 2종 안내 (AC-2)"
else
  nope "T1.d" "rc=$rc · 출력: $out"
fi

# ── T1.e 숨김 디렉터리도 스캔한다 (FR-6) ──
_rmfile "$sb" docs/bare.md
_addfile "$sb" .githooks/pre-push "echo '99 $WORD'"
[ "$(_rc "$sb")" = 1 ] \
  && ok "T1.e 숨김 디렉터리(.githooks/) 도 스캔 (FR-6)" \
  || nope "T1.e" "숨김 디렉터리를 놓쳤다"

# ── T1.f allowlist 경로 3종은 통과 (AC-3 sandbox 판) ──
_rmfile "$sb" .githooks/pre-push
_addfile "$sb" CHANGELOG.md "v1: 99 $WORD"
_addfile "$sb" docs/audit/2026-01-01-x.md "당시 88 $WORD"
_addfile "$sb" docs/2026-02-02-y.md "당시 77 $WORD"
[ "$(_rc "$sb")" = 0 ] \
  && ok "T1.f allowlist 경로 3종 통과 — 오탐 0 (AC-3)" \
  || nope "T1.f" "allowlist 오탐 — $(_run "$sb")"

# ── T1.g historical 마커도 통과 ──
_addfile "$sb" docs/old.md "당시 66 $WORD <!-- doc-lock: historical -->"
[ "$(_rc "$sb")" = 0 ] \
  && ok "T1.g doc-lock: historical 마커 통과" \
  || nope "T1.g" "historical 마커를 인정하지 않는다"

# ── T1.h 반공허 가드: 스캔 파일·줄 수가 출력된다 (AC-3) ──
out=$(_run "$sb")
if printf '%s' "$out" | grep -qE "스캔 [1-9][0-9]*파일" \
   && printf '%s' "$out" | grep -qE "/[1-9][0-9]*줄"; then
  ok "T1.h 스캔 파일·줄 수 ≥ 1 출력 — 반공허 가드 (AC-3)"
else
  nope "T1.h" "도달 증거 미출력 — $out"
fi

# ── T1.i 지표는 suite-count·historical 뿐 (AC-6①) ──
if [ ! -f "$CHK" ]; then
  nope "T1.i" "검사 본체가 없다 — 지표 목록을 판정할 수 없다"
elif grep -q 'harness-suite-count' "$CHK"; then
  nope "T1.i" "기각된 harness-suite-count 가 구현에 남아 있다"
else
  ok "T1.i 지표 1종(suite-count) + historical — harness 지표 미지원 (AC-6①)"
fi

# ── T1.j 대상 트리가 git 아니면 rc=2 ──
nd=$(mktemp -d "${TMPDIR:-/tmp}/docnum-nogit.XXXXXX") || nd=""
_reg "$nd"
[ "$(_rc "$nd")" = 2 ] \
  && ok "T1.j 비-git 트리 → rc=2 (판정 불가를 통과로 위장하지 않는다)" \
  || nope "T1.j" "비-git 트리에서 rc=2 가 아니다 (nd='${nd:-}')"
# 정리는 trap _cleanup 이 맡는다 — 실패 경로에서도 누수되지 않게 한 곳으로 모았다.

# ── T1.k 잠금 마커 0건 → rc=2 (판정 불가를 통과로 위장하지 않는다) ──
# 왜 필요한가: 마커가 하나도 없으면 검사는 아무것도 대조하지 않았다. 그걸 OK 로 내면
#   누출·빈 트리 같은 실패 모드가 전부 "스캔 0파일/0줄" + rc=0 으로 조용히 통과한다.
#   스위트는 T2.b 가 실 트리 도달을 보지만, CLAUDE.md 가 문서화한 **단독 실행**은 무방어였다.
sb0=$(_mksandbox) || sb0=""
_reg "$sb0"
if [ -z "$sb0" ]; then
  nope "T1.k" "sandbox 생성 실패 — 판정 불가"
else
  k_rc=$(_rc "$sb0")
  [ "$k_rc" = 2 ] \
    && ok "T1.k 잠금 마커 0건 → rc=2 — 판정 불가를 OK 로 내지 않는다" \
    || nope "T1.k" "locked=0 인데 rc=$k_rc — $(_run "$sb0")"
fi

# ── T4 가드의 이빨: env 누출 차단 가드를 지우면 검사가 불일치를 놓치는가 ──
# 왜 변이 사본인가: 가드 줄의 **존재만** grep 하면 "있다" 를 "작동한다" 로 착각한다.
#   사본에서 그 줄을 지우고 누출 env 를 주입해 실제로 놓치는지 본다(되돌려-관찰).
# ★ 누출 env 는 **다른 sandbox** 만 가리킨다 — 실 트리 .git 은 읽기 전용으로도 넣지 않는다.
#   훗날 이 경로에 쓰기가 생기면 지금 닫은 문이 그대로 다시 열리기 때문이다.
# ★ 누출원(sbL)에는 문서를 심지 않는다 — 심으면 누출된 ls-files 가 대상 트리에도 존재하는
#   경로를 내놓아 mutant 도 불일치를 잡고, 이 어서션이 조용히 판별력을 잃는다.
sbT=$(_mksandbox) || sbT=""; _reg "$sbT"
sbL=$(_mksandbox) || sbL=""; _reg "$sbL"
mut=""
if [ -n "$sbT" ] && [ -n "$sbL" ]; then
  _addfile "$sbT" docs/lock.md "게이트는 $((EXP+7)) $WORD 를 돈다 <!-- doc-lock: suite-count -->"
  mut=$(mktemp "${TMPDIR:-/tmp}/docnum-mut.XXXXXX") || mut=""
  _reg "$mut"
  [ -n "$mut" ] && sed '/^unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE$/d' "$CHK" > "$mut"
fi
_teeth_pair() { # $1=누출시킬 env 이름 → "<control rc> <mutant rc>"
  local crc mrc
  case "$1" in
    GIT_DIR)
      DOC_NUMBERS_ROOT="$sbT" GIT_DIR="$sbL/.git" GIT_WORK_TREE="$sbL" bash "$CHK" >/dev/null 2>&1; crc=$?
      DOC_NUMBERS_ROOT="$sbT" GIT_DIR="$sbL/.git" GIT_WORK_TREE="$sbL" bash "$mut" >/dev/null 2>&1; mrc=$?
      ;;
    *)
      DOC_NUMBERS_ROOT="$sbT" GIT_INDEX_FILE="$sbL/.git/index" bash "$CHK" >/dev/null 2>&1; crc=$?
      DOC_NUMBERS_ROOT="$sbT" GIT_INDEX_FILE="$sbL/.git/index" bash "$mut" >/dev/null 2>&1; mrc=$?
      ;;
  esac
  printf '%s %s' "$crc" "$mrc"
}
for _v in GIT_DIR GIT_INDEX_FILE; do
  case "$_v" in GIT_DIR) _id="T4.a" ;; *) _id="T4.b" ;; esac
  if [ -z "$mut" ] || [ ! -s "$mut" ] \
     || [ "$(( $(wc -l < "$CHK") - $(wc -l < "$mut") ))" -ne 1 ] \
     || grep -q '^unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE$' "$mut" 2>/dev/null; then
    # 변이가 실제로 적용됐는지 먼저 확인한다 — 미적용이면 이 어서션은 공허하다.
    #   빈 사본(sed 실패·$CHK 미읽기)은 가드 줄 grep 이 미매치라 "적용됨" 으로 오판되고 rc=0 으로
    #   통과했다(리뷰 실측). 그래서 비어 있지 않음 + 원본 대비 정확히 1줄 삭제를 함께 요구한다.
    nope "$_id" "변이 사본 준비 실패(비었거나 · 가드 1줄 삭제가 아니다) — 이빨을 판정할 수 없다"
    continue
  fi
  read -r crc mrc <<< "$(_teeth_pair "$_v")"
  # mutant 기대값은 ≠1 이 아니라 정확히 2(locked=0 가드 도달) — ≠1 이면 문법 오류(127)·빈 파일(0)
  #   처럼 가드와 무관하게 죽은 사본도 "이빨 있음" 으로 통과한다.
  if [ "${crc:-}" = 1 ] && [ "${mrc:-}" = 2 ]; then
    ok "$_id $_v 누출 — 가드 있음: 불일치 적발(rc=1) · 가드 지움: 판정 불가로 떨어짐(rc=2). 가드에 이빨이 있다"
  else
    nope "$_id" "$_v 누출 — control rc=${crc:-?}(기대 1) · mutant rc=${mrc:-?}(기대 2)"
  fi
done

# ── T2: 실 트리 어서션 (정정 후에만 GREEN) ─────────────────────
# ★ DOC_NUMBERS_ROOT 는 **이 호출에만** 붙는 prefix 다 — 본문에 bare 대입/export 로 두면
#   위 _run·_rc 의 sandbox 루트를 덮어써 T1.a~T1.j 10건이 조용히 실 트리를 보게 된다.
#   prefix 로 고정하는 이유: cwd 가 어디든(중첩 트리·훅 경유) 판정 대상이 실 트리로 확정된다.
real_out=$(DOC_NUMBERS_ROOT="$PLUGIN" bash "$CHK" 2>&1); real_rc=$?

# T2.a 실 트리에서 검사가 통과한다 (AC-4)
[ "$real_rc" = 0 ] \
  && ok "T2.a 실 트리 검사 rc=0 — 정정 완료 (AC-4)" \
  || nope "T2.a" "실 트리 FAIL — $real_out"

# T2.b 실 트리 반공허: 스캔 파일·줄 수가 1 이상 (AC-3)
if printf '%s' "$real_out" | grep -qE "스캔 [1-9][0-9]*파일/[1-9][0-9]*줄"; then
  ok "T2.b 실 트리 도달 증거 — 스캔 파일·줄 ≥ 1 (AC-3)"
else
  nope "T2.b" "도달 증거 없음 — $real_out"
fi

# T2.c harness 계열에 수치 서술이 0건 (AC-6②)
if grep -qE "$RE" "$PLUGIN/scripts/tests/harness.sh" \
                 "$PLUGIN/scripts/tests/test-harness-skip.sh" 2>/dev/null; then
  nope "T2.c" "harness 계열에 수치 서술이 남아 있다"
else
  ok "T2.c harness·test-harness-skip 수치 서술 0건 (AC-6②)"
fi

# T2.d test-harness-skip 자신이 통과한다 (AC-6④)
# 판정은 :49 의 [ "$fout" = "PASS=3 FAIL=0" ] 이므로 :50 메시지 변경은 로직 무영향이어야 한다.
if bash "$PLUGIN/scripts/tests/test-harness-skip.sh" >/dev/null 2>&1; then
  ok "T2.d test-harness-skip PASS — 판정 로직 무영향 (AC-6④)"
else
  nope "T2.d" "수치 제거가 test-harness-skip 을 깨뜨렸다"
fi

# T2.e 드리프트: run-all 과 검사의 수집 디렉터리 집합이 같다
# ★ 한계: 추출 정규식이 **소문자+하이픈** 디렉터리만 잡는다 — 숫자·대문자·밑줄이 든
#   디렉터리(`tests/e2e2/`·`tests/E2E/`)가 한쪽에 추가되면 양쪽 집합에서 똑같이 누락돼
#   이 비교를 **무음 통과**한다. 그 경우 실측값이 과소계산되고 잠금이 틀린 값을 강제한다.
#   넓히려면 검사·run-all 양쪽의 실제 glob 어휘를 먼저 재측정해야 한다(이 FID 범위 밖).
_dirs_from() {
  grep -oE 'scripts/tests(/[a-z-]+)?/test-' "$1" | sed 's|/test-$||' | sort -u
}
if diff -q <(_dirs_from "$PLUGIN/scripts/tests/run-all.sh") \
           <(_dirs_from "$CHK") >/dev/null 2>&1; then
  ok "T2.e 수집 디렉터리 집합 일치 — 드리프트 없음"
else
  nope "T2.e" "run-all 과 검사의 수집 목록이 다르다 — 실측값이 거짓이 된다"
fi

# T2.f CLAUDE.md 가 suite-count 마커로 잠겼다 (AC-7③)
if grep -q 'doc-lock: suite-count' "$PLUGIN/CLAUDE.md" 2>/dev/null; then
  ok "T2.f CLAUDE.md 가 suite-count 마커로 잠겼다 (AC-7③)"
else
  nope "T2.f" "CLAUDE.md 에 마커가 없다 — 검사가 자기 저장소에서 FAIL 한다"
fi

# ── T3: 등재 ──────────────────────────────────────────────
# T3.a propagation 레코드가 있고 edge 가 3건이다 (AC-7①)
# jq 부재는 skip 으로 센다 — ok 로 세면 도구 부재 시 이 커버리지가 조용히 사라진다.
if command -v jq >/dev/null 2>&1; then
  n=$(jq -s '[.[]|select(.id=="doc-number-lock")|.edges|length]|add // 0' \
        "$PLUGIN/scripts/_internal/propagation-matrix.jsonl")
  [ "$n" = 3 ] \
    && ok "T3.a doc-number-lock 레코드 edge 3건 (AC-7①)" \
    || nope "T3.a" "edge 수가 3이 아니다 — 실제 $n"
else
  skip "T3.a jq 미설치"
fi

# T3.b 검사가 README·CLAUDE 에 등재됐다
grep -q 'check-doc-numbers' "$PLUGIN/scripts/README.md" \
  && grep -q 'check-doc-numbers' "$PLUGIN/CLAUDE.md" \
  && ok "T3.b scripts/README·CLAUDE.md 등재" \
  || nope "T3.b" "등재 누락"

# ── T5.a 실 인덱스 무접촉 — 이 스위트의 git 호출이 실 저장소에 닿지 않았다 ──
# 사후 탐지다(예방은 상단 env unset · sb 가드 · 헬퍼 빈인자 가드). 조용한 오염만은 막는다.
_idx_after=$(_idx_sig)
[ "$_idx_before" = "$_idx_after" ] \
  && ok "T5.a 실 인덱스 지문 불변 ($_idx_before) — 스위트가 실 저장소를 건드리지 않았다" \
  || nope "T5.a" "실 인덱스가 변했다 ($_idx_before → $_idx_after) — sandbox 가드 또는 env 격리가 깨졌다"

finish
