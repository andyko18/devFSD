#!/usr/bin/env bash
# specops-ko · session-progress-append.sh 검증
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCRIPT="$PLUGIN/scripts/session-progress-append.sh"


# ── fixture helpers ─────────────────────────────────────────────────────

EXISTING_FID="20260101-existing-fid"

make_progress() {
  local f="$1"
  cat > "$f" <<EOF
# Session Progress

---

## ${EXISTING_FID} · 기존 기능

- 2026-01-01 10:00 /specify 완료 (spec.md)

---

## 활용 방법
EOF
}

# ── T1: usage / exit code ──────────────────────────────────────────────

# T1.a: 스크립트 존재
[ -f "$SCRIPT" ] && ok "T1.a script 존재" || fail "T1.a script 존재"

# T1.b: exec-bit
[ -x "$SCRIPT" ] && ok "T1.b exec-bit" || fail "T1.b exec-bit"

# T1.c: 인자 없음 → exit 2 + usage 출력
T1_c_out=$(bash "$SCRIPT" 2>&1)
T1_c_rc=$?
[ $T1_c_rc -eq 2 ] && echo "$T1_c_out" | grep -qi "usage\|FID" \
  && ok "T1.c 인자 없음 → exit 2" || fail "T1.c 인자 없음 → exit 2"

# T1.d: 잘못된 FID 포맷 → exit 1
bash "$SCRIPT" "bad-fid" "/specify" "완료" >/dev/null 2>&1
[ $? -eq 1 ] && ok "T1.d FID 포맷 오류 → exit 1" || fail "T1.d FID 포맷 오류 → exit 1"

# ── T2: 신규 섹션 생성 ────────────────────────────────────────────────

# T2.a: 신규 FID → 섹션 생성
T2_a() {
  local tmp dir fid
  tmp=$(mktemp -d)
  fid="20260101-new-fid"
  mkdir -p "$tmp/.specops"
  make_progress "$tmp/.specops/session-progress.md"
  (cd "$tmp" && bash "$PLUGIN/scripts/session-progress-append.sh" "$fid" "/specify" "완료" "spec.md") >/dev/null 2>&1
  grep -q "## $fid" "$tmp/.specops/session-progress.md" || { rm -rf "$tmp"; return 1; }
  grep -q "/specify 완료" "$tmp/.specops/session-progress.md" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}
T2_a && ok "T2.a 신규 FID 섹션 생성" || fail "T2.a 신규 FID 섹션 생성"

# T2.b: feature-name 인자 → 섹션 헤더에 포함
T2_b() {
  local tmp fid
  tmp=$(mktemp -d)
  fid="20260101-feat-b"
  mkdir -p "$tmp/.specops"
  make_progress "$tmp/.specops/session-progress.md"
  (cd "$tmp" && bash "$PLUGIN/scripts/session-progress-append.sh" "$fid" "/specify" "완료" "" "테스트기능") >/dev/null 2>&1
  grep -q "## $fid · 테스트기능" "$tmp/.specops/session-progress.md" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}
T2_b && ok "T2.b feature-name 헤더 포함" || fail "T2.b feature-name 헤더 포함"

# ── T3: 기존 섹션 append ──────────────────────────────────────────────

# T3.a: 기존 FID → 기존 섹션에 줄 추가
T3_a() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.specops"
  make_progress "$tmp/.specops/session-progress.md"
  (cd "$tmp" && bash "$PLUGIN/scripts/session-progress-append.sh" "$EXISTING_FID" "/clarify" "완료" "clarifications.md") >/dev/null 2>&1
  grep -q "/clarify 완료" "$tmp/.specops/session-progress.md" || { rm -rf "$tmp"; return 1; }
  grep -q "/specify 완료" "$tmp/.specops/session-progress.md" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}
T3_a && ok "T3.a 기존 섹션 줄 추가" || fail "T3.a 기존 섹션 줄 추가"

# T3.b: 멱등 — 동일 줄 중복 추가 안 함
T3_b() {
  local tmp count
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.specops"
  make_progress "$tmp/.specops/session-progress.md"
  (cd "$tmp" && bash "$PLUGIN/scripts/session-progress-append.sh" "$EXISTING_FID" "/clarify" "완료" "memo") >/dev/null 2>&1
  (cd "$tmp" && bash "$PLUGIN/scripts/session-progress-append.sh" "$EXISTING_FID" "/clarify" "완료" "memo") >/dev/null 2>&1
  # 동일 내용 줄이 2개 이상이면 중복
  count=$(grep -Fc "/clarify 완료 (memo)" "$tmp/.specops/session-progress.md" 2>/dev/null)
  rm -rf "$tmp"
  [ "${count:-0}" -le 1 ]
}
T3_b && ok "T3.b 멱등 — 중복 추가 안 함" || fail "T3.b 멱등 — 중복 추가 안 함"

# ── T4: 파일 미존재 시 자동 생성 ─────────────────────────────────────

# T4.a: .specops/session-progress.md 없음 → hooks/ensure-session-progress.sh 호출·생성
# (ensure 스크립트가 templates에서 생성하므로 plugin_root 에서 동작 필요)
T4_a() {
  local tmp fid
  tmp=$(mktemp -d)
  fid="20260101-auto-create"
  mkdir -p "$tmp/.specops"
  # progress 파일 없이 시작
  (cd "$tmp" && bash "$PLUGIN/scripts/session-progress-append.sh" "$fid" "/specify" "완료") >/dev/null 2>&1
  local ret=0
  [ -f "$tmp/.specops/session-progress.md" ] || ret=1
  rm -rf "$tmp"
  return $ret
}
T4_a && ok "T4.a 파일 미존재 시 자동 생성" || fail "T4.a 파일 미존재 시 자동 생성"

# T4.b: .specops/ 디렉토리째 없음 → 기록기가 만든다.
#   진행 기록 쓰기는 lifecycle 의 명시적 행위라 관할을 여는 쪽이다. Stop 훅(ensure-session-progress)은
#   .specops 부재 시 아무것도 만들지 않으므로, 디렉토리 생성은 기록기 몫이다.
T4_b() {
  local tmp ret=0
  tmp=$(mktemp -d)
  (cd "$tmp" && bash "$PLUGIN/scripts/session-progress-append.sh" "20260101-first-write" "/specify" "완료") >/dev/null 2>&1 || ret=1
  grep -q '^## 20260101-first-write' "$tmp/.specops/session-progress.md" 2>/dev/null || ret=1
  rm -rf "$tmp"
  return $ret
}
T4_b && ok "T4.b .specops 부재 → 기록기가 디렉토리·파일 생성" || fail "T4.b .specops 부재 시 기록 실패"

# T4.c: 진행 기록 훅을 끈 프로파일(standard·minimal)에서도 **명시적 기록**은 된다.
#   끄는 것은 Stop 훅의 자동 생성이다. 기록까지 막히면 `/verify PASS` 줄이 없어 R-1 이 모든 코드 커밋을 막는다
#   (그 프로파일들은 차단 훅을 켠 채 둔다).
T4_c() {
  local tmp ret=0 p
  for p in standard minimal; do
    tmp=$(mktemp -d); mkdir -p "$tmp/.specops"
    (cd "$tmp" && SPECOPS_GOVERNANCE_PROFILE=$p bash "$PLUGIN/scripts/session-progress-append.sh" "20260101-prof" "/verify" "PASS" "x") >/dev/null 2>&1 || ret=1
    grep -q '/verify PASS' "$tmp/.specops/session-progress.md" 2>/dev/null || ret=1
    rm -rf "$tmp"
  done
  return $ret
}
T4_c && ok "T4.c 프로파일 standard·minimal → 명시적 기록은 파일을 만들고 줄을 쓴다" || fail "T4.c 진행 기록 훅이 꺼진 프로파일에서 기록 실패"
# T4.d: 대조 — Stop 훅으로 도는 자동 생성(환경변수 없음)은 그 프로파일에서 여전히 꺼져 있다
T4_d() {
  local tmp ret=0
  tmp=$(mktemp -d); mkdir -p "$tmp/.specops"
  (cd "$tmp" && SPECOPS_GOVERNANCE_PROFILE=standard bash "$PLUGIN/hooks/ensure-session-progress.sh") >/dev/null 2>&1
  [ ! -e "$tmp/.specops/session-progress.md" ] || ret=1
  rm -rf "$tmp"
  return $ret
}
T4_d && ok "T4.d 대조 — 자동 생성(Stop 훅)은 standard 에서 꺼진 채" || fail "T4.d 킬스위치가 자동 생성까지 풀렸다"

# ── T5: 멱등성·빈섹션 회귀 ─────────────────────────────────────────────

# T5.a AC-2/5: 신규섹션 동일 라인 재append → 1회 (멱등 섹션 전체 스캔)
T5_a() {
  local tmp; tmp=$(mktemp -d)
  ( cd "$tmp" && mkdir -p .specops && bash "$PLUGIN/hooks/ensure-session-progress.sh" >/dev/null 2>&1
    bash "$SCRIPT" 20260615-i /specify 완료 "m" "F" >/dev/null 2>&1
    bash "$SCRIPT" 20260615-i /specify 완료 "m" >/dev/null 2>&1 )
  local cnt; cnt=$(grep -c "specify 완료 (m)" "$tmp/.specops/session-progress.md" 2>/dev/null || echo 99)
  rm -rf "$tmp"
  [ "$cnt" = "1" ]
}
T5_a && ok "T5.a 멱등 재append 1회 (AC-2/5)" || fail "T5.a 멱등 재append 1회 (AC-2/5)"

# T5.b AC-R-1: 다른 라인 → prepend (섹션 첫 줄 앞), 기존 라인 보존
T5_b() {
  local tmp; tmp=$(mktemp -d)
  ( cd "$tmp" && mkdir -p .specops && bash "$PLUGIN/hooks/ensure-session-progress.sh" >/dev/null 2>&1
    bash "$SCRIPT" 20260615-p /specify 완료 "a" "F" >/dev/null 2>&1
    bash "$SCRIPT" 20260615-p /clarify 완료 "b" >/dev/null 2>&1 )
  local f; f="$tmp/.specops/session-progress.md"
  local ret=0
  grep -q "clarify 완료 (b)" "$f" && grep -q "specify 완료 (a)" "$f" || ret=1
  rm -rf "$tmp"
  return $ret
}
T5_b && ok "T5.b 다른 라인 prepend 무손상 (AC-R-1)" || fail "T5.b 다른 라인 prepend 무손상 (AC-R-1)"

# T5.c AC-6: 빈섹션(항목0)에 첫 항목 추가 보존
T5_c() {
  local tmp; tmp=$(mktemp -d); mkdir -p "$tmp/.specops"
  printf -- '---\n\n## 20260615-e · F\n\n## 20260101-old · O\n\n- old line\n' > "$tmp/.specops/session-progress.md"
  ( cd "$tmp" && bash "$SCRIPT" 20260615-e /specify 완료 "x" >/dev/null 2>&1 )
  local ret=0
  grep -q "specify 완료 (x)" "$tmp/.specops/session-progress.md" || ret=1
  rm -rf "$tmp"
  return $ret
}
T5_c && ok "T5.c 빈섹션 첫 항목 추가 (AC-6)" || fail "T5.c 빈섹션 첫 항목 추가 (AC-6)"

# ── T6: escape 회귀 케이스 (AC-5/6/3) ───────────────────────────────────

# T6.a AC-2/6: memo \n → 리터럴 1줄 (멀티라인 오염 0)
T6_a() {
  local tmp; tmp=$(mktemp -d)
  ( cd "$tmp" && mkdir -p .specops && bash "$PLUGIN/hooks/ensure-session-progress.sh" >/dev/null 2>&1
    bash "$SCRIPT" 20260615-ea /specify 완료 'a\nb' "F" >/dev/null 2>&1 )
  local f; f="$tmp/.specops/session-progress.md"
  local lit; lit=$(grep -cF 'a\nb' "$f" 2>/dev/null || echo 0)
  local sec; sec=$(awk '/^## /{x=($0 ~ "^## 20260615-ea")} x&&/^- /{c++} END{print c+0}' "$f")
  rm -rf "$tmp"
  [ "$lit" = "1" ] && [ "$sec" = "1" ]
}
T6_a && ok "T6.a memo \\n 리터럴 1줄·오염0 (AC-2/6)" || fail "T6.a memo \\n 리터럴 1줄·오염0 (AC-2/6)"

# T6.b AC-6: memo \t → 리터럴 보존
T6_b() {
  local tmp; tmp=$(mktemp -d)
  ( cd "$tmp" && mkdir -p .specops && bash "$PLUGIN/hooks/ensure-session-progress.sh" >/dev/null 2>&1
    bash "$SCRIPT" 20260615-eb /specify 완료 'x\ty' "F" >/dev/null 2>&1 )
  local ret=0; grep -qF 'x\ty' "$tmp/.specops/session-progress.md" || ret=1
  rm -rf "$tmp"
  return $ret
}
T6_b && ok "T6.b memo \\t 리터럴 보존 (AC-6)" || fail "T6.b memo \\t 리터럴 보존 (AC-6)"

# T6.c AC-6: memo \\ → 리터럴 보존
T6_c() {
  local tmp; tmp=$(mktemp -d)
  ( cd "$tmp" && mkdir -p .specops && bash "$PLUGIN/hooks/ensure-session-progress.sh" >/dev/null 2>&1
    bash "$SCRIPT" 20260615-ec /specify 완료 'p\\q' "F" >/dev/null 2>&1 )
  local ret=0; grep -qF 'p\\q' "$tmp/.specops/session-progress.md" || ret=1
  rm -rf "$tmp"
  return $ret
}
T6_c && ok "T6.c memo \\\\ 리터럴 보존 (AC-6)" || fail "T6.c memo \\\\ 리터럴 보존 (AC-6)"

# T6.d AC-3: escape 포함 동일 라인 재append → 1회 (멱등)
T6_d() {
  local tmp; tmp=$(mktemp -d)
  ( cd "$tmp" && mkdir -p .specops && bash "$PLUGIN/hooks/ensure-session-progress.sh" >/dev/null 2>&1
    bash "$SCRIPT" 20260615-ed /specify 완료 'a\nb' "F" >/dev/null 2>&1
    bash "$SCRIPT" 20260615-ed /specify 완료 'a\nb' >/dev/null 2>&1 )
  local cnt; cnt=$(grep -cF 'a\nb' "$tmp/.specops/session-progress.md" 2>/dev/null || echo 99)
  rm -rf "$tmp"
  [ "$cnt" = "1" ]
}
T6_d && ok "T6.d escape 동일 라인 멱등 1회 (AC-3)" || fail "T6.d escape 동일 라인 멱등 1회 (AC-3)"

# ── M1~M8: active-fid 마커 생산자 (FID 20260809-active-fid-marker-producer) ──
#   결함: detect_fid() 가 마커를 1순위로 읽는데 갱신하는 층이 0곳이라 값이 고착됐다.
#   실사용 관측: R-1 게이트가 직전 FID 의 verify 증거를 요구해 git commit 2회 차단.

_mk_progress() {   # $1=루트 디렉터리, $2=마커 FID(빈 문자열이면 마커 없음)
  mkdir -p "$1/.specops"
  {
    echo '<!-- OWNER_COMMAND: 모든 커맨드가 append -->'
    echo '<!-- layer: Harness-Foundation-Artifact -->'
    [ -n "$2" ] && echo "<!-- active-fid: $2 -->"
    echo ''
    echo '# Session Progress — fixture'
    echo ''
    echo '---'
    echo ''
    echo '## 20260101-existing-fid · 기존'
    echo ''
    echo '- 2026-01-01 00:00 /specify 완료 "기존 행"'
    echo ''
  } > "$1/.specops/session-progress.md"
}
_detect() {   # $1=루트 — governance-lib 의 detect_fid 를 그 cwd 에서 실행
  ( cd "$1" && . "$PLUGIN/hooks/governance-lib.sh" >/dev/null 2>&1 && detect_fid ) 2>/dev/null
}

# 1순위(마커) ↔ 2순위(첫 h2 헤더)가 **갈리는** 픽스처 — 판별력 확보용.
#   섹션이 2개이고 대상 FID 는 **두 번째**다. 마커 없이 대상에 append 하면
#   2순위는 첫 섹션(20260505-decoy)을 내놓으므로, detect_fid 가 대상을 반환하면
#   그것은 **마커를 읽었다는 뜻**이다. 섹션 1개짜리 픽스처는 새 섹션이 맨 위에
#   prepend 돼 두 경로가 같은 답을 내므로 구조적으로 공허하다(구현 중 실증).
_mk_progress2() {   # $1=루트, $2=마커 FID(빈 문자열이면 마커 없음)
  mkdir -p "$1/.specops"
  {
    echo '<!-- OWNER_COMMAND: 모든 커맨드가 append -->'
    [ -n "$2" ] && echo "<!-- active-fid: $2 -->"
    echo ''
    echo '# Session Progress — fixture2'
    echo ''
    echo '---'
    echo ''
    echo '## 20260505-decoy · 첫 섹션(2순위가 집는 값)'
    echo ''
    echo '- 2026-05-05 00:00 /specify 완료 "decoy"'
    echo ''
    echo '## 20260101-existing-fid · 대상'
    echo ''
    echo '- 2026-01-01 00:00 /specify 완료 "기존 행"'
    echo ''
  } > "$1/.specops/session-progress.md"
}

_m1=$(mktemp -d); _mk_progress "$_m1" "20260101-old"
( cd "$_m1" && bash "$SCRIPT" 20260202-new /specify 완료 "m1" ) >/dev/null 2>&1
_n=$(grep -c 'active-fid' "$_m1/.specops/session-progress.md")
_v=$(grep -c 'active-fid: 20260202-new' "$_m1/.specops/session-progress.md")
[ "$_n" = "1" ] && [ "$_v" = "1" ] \
  && ok "M1 마커 치환 (중복 0) (AC-1)" || fail "M1 마커 치환 — active-fid 줄=$_n 신값=$_v (기대 1·1)"

# M2 — 마커가 없으면 삽입. 치환 단독이면 여기서 조용히 no-op 된다 (AC-2)
_m2=$(mktemp -d); _mk_progress "$_m2" ""
( cd "$_m2" && bash "$SCRIPT" 20260303-ins /specify 완료 "m2" ) >/dev/null 2>&1
_n2=$(grep -c 'active-fid' "$_m2/.specops/session-progress.md")
#   ★ 배치까지 본다 — 값 존재만 보면 END fallback 이 **파일 끝**에 붙여도 통과해,
#     삽입 경로를 지우는 변이가 격추되지 않는다(구현 중 실제 확인). 상단 주석 블록,
#     즉 첫 `#` 제목보다 **앞**에 와야 기존 파일 관례와 일치한다.
_lm=$(grep -n 'active-fid' "$_m2/.specops/session-progress.md" | head -1 | cut -d: -f1)
_lh=$(grep -n '^#' "$_m2/.specops/session-progress.md" | head -1 | cut -d: -f1)
[ "$_n2" = "1" ] && grep -q 'active-fid: 20260303-ins' "$_m2/.specops/session-progress.md" \
  && [ -n "$_lm" ] && [ -n "$_lh" ] && [ "$_lm" -lt "$_lh" ] \
  && ok "M2 마커 부재 시 상단 삽입 (AC-2)" || fail "M2 마커 삽입 — 줄수=$_n2 마커행=$_lm 제목행=$_lh (기대 1·마커<제목)"

# M2b — 삽입된 마커를 detect_fid 가 **실제로 읽는가** (AC-2 Then 후반부)
#   ★ grep substring 만 보면 삽입 분기 printf 의 `-->` 가 빠지는 변이가 통과한다
#     (구현 중 실증: 24/0 그대로). detect_fid 정규식은 `-->` 를 요구하므로 그런 마커는
#     조용히 2순위로 떨어진다 — 이 FID 가 고치려는 결함 클래스 그 자체다.
#     치환 분기(M4)와 삽입 분기는 **별개 printf** 라 한쪽만 깨질 수 있어 둘 다 잠근다.
_m2b=$(mktemp -d); _mk_progress2 "$_m2b" ""
( cd "$_m2b" && bash "$SCRIPT" 20260101-existing-fid /verify PASS "m2b" ) >/dev/null 2>&1
_ins=$(_detect "$_m2b")
[ "$_ins" = "20260101-existing-fid" ] \
  && ok "M2b 삽입 마커를 detect_fid 가 인식 (AC-2)" \
  || fail "M2b detect_fid='$_ins' (기대 20260101-existing-fid — 2순위면 20260505-decoy 가 나온다)"

# M3 — 기존 섹션 append 경로에서도 갱신 (AC-3)
_m3=$(mktemp -d); _mk_progress "$_m3" "20260101-old"
( cd "$_m3" && bash "$SCRIPT" 20260101-existing-fid /verify PASS "m3" ) >/dev/null 2>&1
grep -q 'active-fid: 20260101-existing-fid' "$_m3/.specops/session-progress.md" \
  && ok "M3 기존 섹션 경로에서도 마커 갱신 (AC-3)" || fail "M3 기존 섹션 append 시 마커 미갱신"

# M4 — detect_fid 가 최신 FID 를 반환 (AC-4, 결함의 직접 해소)
_m4=$(mktemp -d); _mk_progress2 "$_m4" "20260505-decoy"
( cd "$_m4" && bash "$SCRIPT" 20260101-existing-fid /verify PASS "m4" ) >/dev/null 2>&1
_got=$(_detect "$_m4")
[ "$_got" = "20260101-existing-fid" ] \
  && ok "M4 detect_fid 최신 FID 반환 (AC-4)" \
  || fail "M4 detect_fid='$_got' (기대 20260101-existing-fid — 마커 미갱신이면 20260505-decoy)"

# M5 — 기존 섹션 헤더·행 무손상 (AC-5, append-only 계약)
grep -q '^## 20260101-existing-fid · 기존' "$_m1/.specops/session-progress.md" \
  && grep -q '기존 행' "$_m1/.specops/session-progress.md" \
  && ok "M5 기존 섹션 헤더·행 보존 (AC-5)" || fail "M5 기존 섹션 손상"

# M6 — sed -i 미사용(GNU/BSD 분기 회피) + mktemp 원자 교체 (AC-6)
#   ★ 주석을 제외하고 본다 — whole-file grep 은 "왜 sed -i 가 아닌가" 같은 **설명 주석**에
#     매치해 오탐한다(구현 중 실제 발생). 실행되는 줄만 검사한다.
_code_only=$(grep -v '^[[:space:]]*#' "$SCRIPT")
if printf '%s' "$_code_only" | grep -q 'sed -i'; then
  fail "M6 sed -i 사용 — GNU/BSD 인자 분기 위험"
elif printf '%s' "$_code_only" | grep -q 'mktemp'; then
  ok "M6 원자 교체 (sed -i 미사용) (AC-6)"
else
  fail "M6 mktemp 미사용"
fi

# M7 — AC-R-1: 마커 부재 파일에서 2순위 fallback 보존 (detect_fid 무수정)
_m7=$(mktemp -d); _mk_progress "$_m7" ""
_fb=$(_detect "$_m7")
[ "$_fb" = "20260101-existing-fid" ] \
  && ok "M7 마커 부재 시 2순위 fallback 보존 (AC-R-1)" || fail "M7 fallback='$_fb' (기대 20260101-existing-fid)"

# M8 — AC-R-2: stdout 문구 보존 (호출 규약 무변경)
_m8=$(mktemp -d); _mk_progress "$_m8" "20260101-old"
_o1=$( ( cd "$_m8" && bash "$SCRIPT" 20260101-existing-fid /verify PASS "m8" ) 2>&1 )
_o2=$( ( cd "$_m8" && bash "$SCRIPT" 20260404-brand /specify 완료 "m8b" ) 2>&1 )
printf '%s' "$_o1" | grep -q 'appended to existing section' \
  && printf '%s' "$_o2" | grep -q 'created new section' \
  && ok "M8 stdout 문구 보존 (AC-R-2)" || fail "M8 stdout 규약 변경 — [$_o1] [$_o2]"

# M9 — 선행 공백 마커도 치환·중복 청소 (Phase C 프로브 P2)
#   ★ 생산자 앵커가 `^<!--` 로 조여 있으면 들여쓴 마커를 못 보고 아래에 새로 추가한다.
#     소비자(detect_fid)의 grep 은 **무앵커**라 위쪽 stale 을 먼저 집어 **재실행해도
#     자기치유되지 않는다**(실증: 두 번 돌려도 stale 고착). 앵커 대칭이 계약이다.
_m9=$(mktemp -d); mkdir -p "$_m9/.specops"
{
  echo '<!-- OWNER_COMMAND: x -->'
  echo '  <!-- active-fid: 20260101-stale -->'
  echo ''
  echo '# Session Progress — fixture9'
  echo ''
  echo '---'
  echo ''
  echo '## 20260707-other · 첫 섹션'
  echo ''
  echo '- 2026-07-07 00:00 /specify 완료 "x"'
  echo ''
} > "$_m9/.specops/session-progress.md"
( cd "$_m9" && bash "$SCRIPT" 20260808-new /verify PASS "m9" ) >/dev/null 2>&1
_n9=$(grep -c 'active-fid' "$_m9/.specops/session-progress.md")
_d9=$(_detect "$_m9")
[ "$_n9" = "1" ] && [ "$_d9" = "20260808-new" ] \
  && ok "M9 선행 공백 마커 치환 + 중복 청소 (Phase C P2)" \
  || fail "M9 마커수=$_n9 detect='$_d9' (기대 1·20260808-new — stale 이면 고착 재발)"

# M10 — END fallback: `#` 제목도 마커도 없는 퇴화 파일에서도 마커가 생긴다
#   Phase B 가 "생존 변이"로 고백한 미검증 경로를 잠근다.
#   ★ `#` 이 하나라도 있으면 그 분기가 먼저 잡아 END 에 도달하지 않는다(구현 중 실증:
#     `## FID` 헤더 픽스처로는 END 변이가 격추되지 않았다). `#` 도 `---` 도 없어야 한다.
_m10=$(mktemp -d); mkdir -p "$_m10/.specops"
printf -- 'plain text only\nno heading, no separator\n' > "$_m10/.specops/session-progress.md"
( cd "$_m10" && bash "$SCRIPT" 20260606-only /verify PASS "m10" ) >/dev/null 2>&1
grep -q 'active-fid: 20260606-only' "$_m10/.specops/session-progress.md" \
  && ok "M10 퇴화 파일 END fallback 마커 생성" \
  || fail "M10 END fallback 미동작 — 마커 부재"

rm -rf "$_m1" "$_m2" "$_m2b" "$_m3" "$_m4" "$_m7" "$_m8" "$_m9" "$_m10"


# ── T-fx.a~c: fixture FID 는 active-fid 마커로 승격하지 않는다 (20260829-fixture-fid-hijack) ──
# 왜: /e2e-test 가 12스텝 내내 이 스크립트를 부르므로 마커가 fixture 로 덮이고, 이후 모든
#   커밋이 fixture 의 verify 상태를 대신 answer 해야 한다(R-1 ②앵커). fixture 테스트는
#   run-verification 실행 whitelist 밖이라 PASS 불가 → BYPASS 외 탈출구가 없다(실측 3회).
_fxm() {  # $1 = fixture 마커 생성 여부(0/1) → 결과 active-fid 를 stdout
  local sb; sb=$(mktemp -d)
  ( cd "$sb" || exit
    mkdir -p .specops/20260101-real .specops/20260102-e2e
    printf '<!-- active-fid: 20260101-real -->\n\n## 20260101-real\n\n- x\n' > .specops/session-progress.md
    [ "$1" = 1 ] && : > .specops/20260102-e2e/.fixture
    bash "$SCRIPT" 20260102-e2e /verify PASS m f >/dev/null 2>&1
    grep -m1 -oE 'active-fid: [0-9]{8}-[a-z0-9-]+' .specops/session-progress.md | sed 's/active-fid: //' )
  rm -rf "$sb"
}
_got=$(_fxm 0)
[ "$_got" = 20260102-e2e ] && ok "T-fx.a 일반 FID 는 종전대로 마커 승격 ($_got)" \
  || nope "T-fx.a" "got=$_got 기대=20260102-e2e"
_got=$(_fxm 1)
[ "$_got" = 20260101-real ] && ok "T-fx.b ★ fixture FID 는 마커 미승격 (직전 실작업 유지: $_got)" \
  || nope "T-fx.b 점거" "got=$_got 기대=20260101-real"

# 섹션 기록 자체는 남아야 한다 — 막는 것은 활성 지목뿐(증거 보존)
_sb=$(mktemp -d)
( cd "$_sb" || exit
  mkdir -p .specops/20260102-e2e && : > .specops/20260102-e2e/.fixture
  # `---` 앵커 필수 — append 의 섹션 삽입 지점이다(없으면 조용히 드롭된다: 이 스크립트의
  #   기존 동작이며 실제 파일은 ensure-session-progress 가 템플릿으로 보장한다)
  printf '# sp\n\n---\n' > .specops/session-progress.md
  bash "$SCRIPT" 20260102-e2e /verify PASS m f >/dev/null 2>&1
  grep -q '^## 20260102-e2e' .specops/session-progress.md )
[ $? -eq 0 ] && ok "T-fx.c fixture 도 섹션 기록은 남는다 (증거 보존)" || nope "T-fx.c" "섹션 미기록"
rm -rf "$_sb"

# R-1 앵커 형식 잠금 (20260911-stage-timing-derive AC-R-1)
#   governance-lib.sh:122-126 이 `^- YYYY-MM-DD HH:MM /command` 를 하드코딩한다.
#   초를 붙이면 `:SS` 가 ` /` 자리에 와서 매칭이 0 이 되고 R-1 앵커가 무음으로 죽는다
#   (false-deny). 그 계약을 여기서 잠근다 — 실제 append 결과를 그 정규식으로 단언한다.
# ★ `SPECOPS_ROOT` 로는 격리되지 않는다 — session-progress-append.sh:52 가
#   `TARGET=".specops/session-progress.md"` 를 **하드코딩**해 cwd 기준으로 쓴다.
#   run-all.sh:124 (작업자)가 `cd "$plugin"` 을 하므로 그대로 두면 (a) 항상 FAIL 이고
#   (b) **실 repo 원장에 `## 20260911-lock` 섹션이 prepend 되고 `active-fid` 마커가
#   탈취된다**(20260829-fixture-fid-hijack 재발). 반드시 `cd` 로 격리한다.
#   `---` 앵커도 필수다 — 없으면 섹션이 조용히 드롭된다(이 파일 T-fx.c 와 동일 관행).
_sp_lock=$(mktemp -d)
mkdir -p "$_sp_lock/.specops"
printf '# sp\n\n---\n' > "$_sp_lock/.specops/session-progress.md"
( cd "$_sp_lock" && bash "$SCRIPT" 20260911-lock /verify PASS "x" >/dev/null 2>&1 )
if grep -qE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} /verify PASS' \
     "$_sp_lock/.specops/session-progress.md"; then
  ok "T-lock R-1 앵커 형식(분 해상도) 유지"
else
  nope "T-lock" "R-1 앵커 형식 이탈 — governance-lib.sh:122-126 매칭이 죽는다"
fi
rm -rf "$_sp_lock"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
