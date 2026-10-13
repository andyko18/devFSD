#!/usr/bin/env bash
# test-constitution-rules.sh — 헌법 「구조 규칙」 표 읽기(scripts/_internal/check-constitution-rules.sh) 계약 (FID 20261013-constitution-structure-rules)
# 방식: mktemp 아래 fixture 헌법 파일로 판정한다 — 실 트리 쓰기 0.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CK="$PLUGIN/scripts/_internal/check-constitution-rules.sh"
TPL="$PLUGIN/templates/constitution.md"
[ -f "$CK" ] || nope "존재" "scripts/_internal/check-constitution-rules.sh 부재"

ROOT=$(mktemp -d) || exit 1
trap 'rm -rf "$ROOT"' EXIT
unset SPECOPS_ROOT

HDR='| ID | 규칙 | 적용 경로 | 판정 | 판정 명령 |'
SEP='|---|---|---|---|---|'
EX='| (예시) S-1 | 예시 규칙 | `src/` | 리뷰 | - |'
R1='| S-1 | 외부 API 는 어댑터에서만 부른다 | `src/adapters/` | 리뷰 | - |'
R2='| S-2 | 시각은 clock 으로만 얻는다 | `app/` | 명령 | `ruff check --select DTZ` |'
# 헌법 파일 만들기 — $1=경로, 나머지=표지 사이에 넣을 행(순서대로). 머리·구분 행은 자동.
mk() {
  local f="$1"; shift
  { printf '# 헌법\n\n## 원칙\n\n### 원칙 1: 가\n\n## 구조 규칙\n\n<!-- structure-rules:start -->\n%s\n%s\n' "$HDR" "$SEP"
    local r; for r in "$@"; do printf '%s\n' "$r"; done
    printf '<!-- structure-rules:end -->\n\n## 거버넌스\n'; } > "$f"
}
# 실행 — 표준 출력은 $out, 표준 오류는 $err, 종료 코드는 $rc
run() { out=$(bash "$CK" "$@" 2>"$ROOT/err"); rc=$?; err=$(cat "$ROOT/err"); }

# ── C1: 템플릿 (AC-1) ──
ls_=$(grep -n '^## 원칙$' "$TPL" | head -1 | cut -d: -f1); lr=$(grep -n '^## 구조 규칙$' "$TPL" | head -1 | cut -d: -f1); lg=$(grep -n '^## 거버넌스$' "$TPL" | head -1 | cut -d: -f1)
lst=$(grep -n 'structure-rules:start' "$TPL" | head -1 | cut -d: -f1); len=$(grep -n 'structure-rules:end' "$TPL" | head -1 | cut -d: -f1)
{ [ -n "$ls_" ] && [ -n "$lr" ] && [ -n "$lg" ] && [ -n "$lst" ] && [ -n "$len" ] && [ "$ls_" -lt "$lr" ] && [ "$lr" -lt "$lst" ] && [ "$lst" -lt "$len" ] && [ "$len" -lt "$lg" ] \
  && sed -n "${lst},${len}p" "$TPL" | grep -qF "$HDR" && [ "$(sed -n "${lst},${len}p" "$TPL" | grep -c '^| (예시)')" -ge 1 ]; } \
  && ok "C1.a 템플릿: 원칙 < 구조 규칙 < 표지(시작 < 끝) < 거버넌스 순 · 머리 행 · 예시 행 1개 이상" || nope "C1.a" "원칙=$ls_ 구조=$lr 시작=$lst 끝=$len 거버넌스=$lg"
run "$TPL"
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'SKIP (규칙 0건'; } && ok "C1.b 템플릿 자체는 규칙 0건의 해당 없음 · rc 0" || nope "C1.b" "rc=$rc out=$out err=$err"
# /init-project 가 하는 것과 같은 치환(프로젝트명·날짜·원칙 이름)을 거친 헌법도 같다 (FR-6)
sed -e 's/<PROJECT_NAME>/demo/g' -e 's/<YYYY-MM-DD>/2026-01-01/g' -e 's/<PRINCIPLE_\([1-5]\)_NAME>/원칙\1/g' "$TPL" > "$ROOT/init.md"
run "$ROOT/init.md"
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'SKIP (규칙 0건'; } && ok "C1.c 초기화 치환을 거친 헌법도 해당 없음 · rc 0" || nope "C1.c" "rc=$rc out=$out err=$err"
if [ -f "$PLUGIN/scripts/_internal/scan-enrich-placeholders.sh" ]; then
  awk -v a="$lr" -v b="$lg" 'NR >= a && NR < b' "$ROOT/init.md" > "$ROOT/sec.md"
  scan_out=$(bash "$PLUGIN/scripts/_internal/scan-enrich-placeholders.sh" "$ROOT/sec.md" 2>&1); scan_rc=$?      # 0=검출 없음 · 1=검출 · 2=오류
  { [ -s "$ROOT/sec.md" ] && grep -q 'structure-rules:start' "$ROOT/sec.md" && [ "$scan_rc" = 0 ]; } && ok "C1.d 구조 규칙 절은 미채움 스캔에 걸리는 자리표시자를 더하지 않는다(절만 떼어 스캔 rc 0)" || nope "C1.d" "스캐너 rc=$scan_rc out=$scan_out"
else
  skip "C1.d scan-enrich-placeholders.sh 부재 — 미채움 스캔 대조 미실행"
fi

# ── C2: 형식이 맞는 표 (AC-2) ──
mkdir -p "$ROOT/p/.specops/memory"; mk "$ROOT/p/.specops/memory/constitution.md" "$EX" "$R1" "$R2"
run "$ROOT/p/.specops/memory/constitution.md"
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'OK (규칙 2건' && [ -z "$err" ]; } && ok "C2.a 경로 인자: 규칙 2건 통과 · 예시 행은 세지 않는다 · 표준 오류 없음" || nope "C2.a" "rc=$rc out=$out err=$err"
out=$( cd "$ROOT/p" && bash "$CK" 2>/dev/null ); rc=$?
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'OK (규칙 2건'; } && ok "C2.b 인자 없음: 기본 경로(.specops/memory/constitution.md)를 읽는다" || nope "C2.b" "rc=$rc out=$out"
mkdir -p "$ROOT/q/alt/memory"; cp "$ROOT/p/.specops/memory/constitution.md" "$ROOT/q/alt/memory/constitution.md"
out=$( cd "$ROOT/q" && SPECOPS_ROOT=alt bash "$CK" 2>/dev/null ); rc=$?
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'OK (규칙 2건'; } && ok "C2.c SPECOPS_ROOT 를 따른다" || nope "C2.c" "rc=$rc out=$out"
printf '%s\r\n' '<!-- structure-rules:start -->' "$HDR" "$SEP" "$R1" "$R2" '<!-- structure-rules:end -->' > "$ROOT/crlf.md"
run --list "$ROOT/crlf.md"
{ [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c .)" = 2 ] && ! printf '%s' "$out" | grep -q $'\r'; } && ok "C2.d CRLF 파일도 같은 결과(규칙 2줄 · 출력에 CR 없음)" || nope "C2.d" "rc=$rc out=$out err=$err"

# ── C3: 형식 위반 (AC-3) — 표지 시작이 9행, 머리 10, 구분 11, 첫 규칙 행 12 ──
badfile() {   # $1=케이스 이름 $2=파일 $3=기대 줄 번호 $4=사유에 들어갈 낱말 — 두 방식(기본·--list) 모두 rc 1, --list 표준 출력은 빈다
  local name="$1" f="$2" ln="$3" why="$4"
  run "$f"; local rc1=$rc err1=$err out1=$out
  run --list "$f"
  { [ "$rc1" = 1 ] && [ -z "$out1" ] && printf '%s\n' "$err1" | grep -qF "$f:${ln}: " && printf '%s\n' "$err1" | grep -F ":${ln}: " | grep -qF "$why" \
    && [ "$rc" = 1 ] && [ -z "$out" ]; } && ok "$name" || nope "$name" "rc=$rc1/$rc err=$err1 out=$out1 list_out=$out"
}
bad() {   # $1=케이스 이름 $2=기대 줄 번호 $3=사유에 들어갈 낱말, 나머지=행
  local name="$1" ln="$2" why="$3"; shift 3
  mk "$ROOT/bad.md" "$@"; badfile "$name" "$ROOT/bad.md" "$ln" "$why"
}
bad "C3.a 칸이 4개 → 줄 번호·사유 · --list 는 rc 1·출력 없음" 12 "칸이 5개가 아님(4개)" '| S-1 | 규칙 | `src/` | 리뷰 |'
bad "C3.b 칸 안의 세로줄(6칸)" 13 "칸이 5개가 아님(6개)" "$R1" '| S-2 | 규칙 | `src/` | 명령 | grep a | wc -l |'
bad "C3.c ID 가 S-숫자 꼴이 아님" 12 "ID 가 S-숫자 꼴이 아님" '| R-1 | 규칙 | `src/` | 리뷰 | - |'
bad "C3.d ID 중복 — 뒤 행을 가리킨다" 13 "ID 중복: S-1" "$R1" '| S-1 | 다른 규칙 | `lib/` | 리뷰 | - |'
bad "C3.e 규칙 칸이 빔" 12 "규칙 칸이 비었거나" '| S-1 |  | `src/` | 리뷰 | - |'
bad "C3.f 적용 경로가 꺾쇠 자리표시자(백틱 포함)" 12 "적용 경로 칸이 비었거나" '| S-1 | 규칙 | `<경로>` | 리뷰 | - |'
bad "C3.g 판정이 리뷰·명령이 아님" 12 "판정은 리뷰 또는 명령" '| S-1 | 규칙 | `src/` | 검사 | - |'
bad "C3.h 판정이 명령인데 판정 명령이 빔" 12 "판정 명령이 비었음" '| S-1 | 규칙 | `src/` | 명령 |  |'
bad "C3.i 판정이 명령인데 판정 명령이 -" 12 "판정 명령이 비었음" '| S-1 | 규칙 | `src/` | 명령 | - |'
bad "C3.j 위반이 있으면 맞는 행도 내지 않는다(뒤 행 위반)" 13 "판정은 리뷰 또는 명령" "$R1" '| S-2 | 규칙 | `src/` | 자동 | - |'
printf '# 헌법\n\n<!-- structure-rules:start -->\n%s\n%s\n%s\n' "$HDR" "$SEP" "$R1" > "$ROOT/open.md"
badfile "C3.k 시작 표지만 있고 끝 표지 없음 → 위반(시작 표지 줄)" "$ROOT/open.md" 3 "끝 표지 없음"
printf '# 헌법\n\n%s\n%s\n%s\n<!-- structure-rules:end -->\n' "$HDR" "$SEP" "$R1" > "$ROOT/close.md"
badfile "C3.l 끝 표지만 있음 → 위반" "$ROOT/close.md" 6 "시작 표지 없이"
{ mk "$ROOT/two.md" "$R1"; printf '\n<!-- structure-rules:start -->\n%s\n%s\n%s\n<!-- structure-rules:end -->\n' "$HDR" "$SEP" "$R2" >> "$ROOT/two.md"; }
badfile "C3.m 표지 쌍이 둘 이상 → 위반(어느 쪽이 진짜인지 정할 수 없다)" "$ROOT/two.md" 17 "표지 쌍이 둘 이상"
mk "$ROOT/multi.md" '| X | 규칙 | `src/` | 리뷰 | - |' '| S-2 |  | `src/` | 명령 |  |'
run "$ROOT/multi.md"; rc1=$rc; err1=$err; run --list "$ROOT/multi.md"
{ [ "$rc1" = 1 ] && [ "$(printf '%s\n' "$err1" | grep -c "^$ROOT/multi.md:1[23]: ")" = 3 ] && printf '%s\n' "$err1" | grep -q 'FAIL (형식 위반 3건' && [ "$rc" = 1 ] && [ -z "$out" ]; } \
  && ok "C3.n 위반 여러 건을 전부 낸다(3건 · 요약 줄에 건수) · --list 는 rc 1·출력 없음" || nope "C3.n" "rc=$rc1/$rc err=$err1 out=$out"
# 표지 사이에서 조용히 버려지는 줄이 없어야 한다 — 규칙이 신호 없이 빠지면 --list 를 쓰는 쪽이 모른다
bad "C3.o 표지 사이의 | 로 시작하지 않는 행(맞는 행과 섞임) → 위반 · 맞는 행도 내지 않는다" 13 "표 행이 아닌 줄" "$R1" 'S-2 | 둘째 규칙 | `lib/` | 명령 |  |'
bad "C3.p 표지 사이의 인용(>) 안 표 행 → 위반" 12 "표 행이 아닌 줄" '> | S-1 | 규칙 | `src/` | 리뷰 | - |'
printf '# 헌법\n\n<!-- structure-rules:start --> 메모\n%s\n%s\n| S-1 | 규칙 | `src/` | 검사 | - |\n<!-- structure-rules:end --> 메모\n' "$HDR" "$SEP" > "$ROOT/mark.md"
badfile "C3.q 표지 줄에 다른 글자가 붙음 → 절 없음(rc 0)이 아니라 위반" "$ROOT/mark.md" 3 "표지 꼴이 틀림"
printf '# 헌법\n\n<!-- structure-rules: start -->\n%s\n%s\n%s\n<!-- structure-rules:end -->\n' "$HDR" "$SEP" "$R1" > "$ROOT/mark2.md"
badfile "C3.r 표지 콜론 뒤 공백(structure-rules: start) → 위반" "$ROOT/mark2.md" 3 "표지 꼴이 틀림"
printf '# 헌법\n\n<!-- structure-rules:start -->\n| ID | 규칙 |\n%s\n%s\n<!-- structure-rules:end -->\n' "$SEP" "$R1" > "$ROOT/hdr.md"
badfile "C3.s 첫 행이 정해진 머리 행이 아님(2칸) → 위반" "$ROOT/hdr.md" 4 "머리 행이 아님"
printf '# 헌법\n\n<!-- structure-rules:start -->\n| ID | 적용 경로 | 규칙 | 판정 | 판정 명령 |\n%s\n%s\n<!-- structure-rules:end -->\n' "$SEP" "$R1" > "$ROOT/hdr2.md"
badfile "C3.t 머리 행의 칸 순서가 바뀜 → 위반(칸 이름·순서가 계약)" "$ROOT/hdr2.md" 4 "머리 행이 아님"
printf '# 헌법\n\n<!-- structure-rules:start -->\n%s\n%s\n<!-- structure-rules:end -->\n' "$HDR" "$R1" > "$ROOT/sep.md"
badfile "C3.u 구분 행 없이 규칙 행이 바로 옴 → 위반" "$ROOT/sep.md" 5 "구분 행이 아님"
bad "C3.v 머리 행처럼 ID 칸이 ID 인 뒤쪽 행은 건너뛰지 않는다(4칸 위반으로 잡힌다)" 12 "칸이 5개가 아님(4개)" '| ID | 규칙 | `src/` | 검사 |'
bad "C3.w 구분 행처럼 생긴 뒤쪽 행도 건너뛰지 않는다" 12 "ID 가 S-숫자 꼴이 아님" '| - | - | - | - | - |'

# ── C4: 해당 없음 (AC-4) ──
run "$ROOT/nope/constitution.md"; rc1=$rc; out1=$out; run --list "$ROOT/nope/constitution.md"
{ [ "$rc1" = 0 ] && printf '%s' "$out1" | grep -q 'SKIP (헌법 없음' && [ "$rc" = 0 ] && [ -z "$out" ] && printf '%s' "$err" | grep -q 'SKIP (헌법 없음'; } \
  && ok "C4.a 헌법 파일 없음 → rc 0 · 한 줄 · --list 표준 출력은 비고 안내는 표준 오류로" || nope "C4.a" "rc=$rc1/$rc out1=$out1 out=$out err=$err"
printf '# 헌법\n\n## 원칙\n\n### 원칙 1: 가\n\n| 표 | 다른 것 |\n|---|---|\n| a | b |\n\n## 거버넌스\n' > "$ROOT/old.md"
run "$ROOT/old.md"; rc1=$rc; out1=$out; run --list "$ROOT/old.md"
{ [ "$rc1" = 0 ] && printf '%s' "$out1" | grep -q 'SKIP (구조 규칙 절 없음' && [ "$rc" = 0 ] && [ -z "$out" ]; } && ok "C4.b 절이 없는 기존 헌법(다른 표가 있어도) → 해당 없음 · rc 0" || nope "C4.b" "rc=$rc1/$rc out1=$out1 out=$out"
mk "$ROOT/ex.md" "$EX" '| (예시) 칸 수가 틀린 예시 행 |'
run "$ROOT/ex.md"; rc1=$rc; out1=$out; run --list "$ROOT/ex.md"
{ [ "$rc1" = 0 ] && printf '%s' "$out1" | grep -q 'SKIP (규칙 0건' && [ "$rc" = 0 ] && [ -z "$out" ]; } && ok "C4.c 예시 행만 있는 표(형식이 틀린 예시 행 포함) → 규칙 0건 · rc 0" || nope "C4.c" "rc=$rc1/$rc out1=$out1 out=$out err=$err"
printf '<!-- structure-rules:start -->\n<!-- structure-rules:end -->\n' > "$ROOT/empty.md"
run "$ROOT/empty.md"
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'SKIP (규칙 0건'; } && ok "C4.d 표지만 있고 표가 없음 → 규칙 0건 · rc 0" || nope "C4.d" "rc=$rc out=$out"
{ mk "$ROOT/outside.md" "$R1"; printf '\n%s\n%s\n| S-9 | 표지 밖 | `x/` | 리뷰 | - |\n' "$HDR" "$SEP" >> "$ROOT/outside.md"; }
run --list "$ROOT/outside.md"
{ [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c .)" = 1 ] && ! printf '%s' "$out" | grep -q 'S-9'; } && ok "C4.e 표지 밖의 표는 읽지 않는다" || nope "C4.e" "rc=$rc out=$out"

# ── C5: --list 출력 (AC-5) ──
run --list "$ROOT/p/.specops/memory/constitution.md"
want='S-1|외부 API 는 어댑터에서만 부른다|`src/adapters/`|리뷰|
S-2|시각은 clock 으로만 얻는다|`app/`|명령|`ruff check --select DTZ`'
{ [ "$rc" = 0 ] && [ "$out" = "$want" ] && printf '%s' "$err" | grep -q 'OK (규칙 2건'; } \
  && ok "C5.a --list: 정확히 2줄 · 칸 앞뒤 공백 없음 · 리뷰 행의 끝 칸은 빈 칸 · 예시 행 없음 · 요약 줄은 표준 오류로" || nope "C5.a" "rc=$rc out=[$out] err=$err"
mk "$ROOT/sp.md" '|   S-7   |   공백이   많은 규칙   |   `a/`, `b/`   |   리뷰   |      |'
run --list "$ROOT/sp.md"
[ "$out" = 'S-7|공백이   많은 규칙|`a/`, `b/`|리뷰|' ] && ok "C5.b 칸 앞뒤 공백만 뗀다(안쪽 공백·쉼표는 그대로) · 빈 명령 칸은 빈 칸" || nope "C5.b" "out=[$out] err=$err"

# ── C6: 판정 불가 · 읽기 전용 (AC-6) ──
mkdir -p "$ROOT/dir.md"
run "$ROOT/dir.md"; rc1=$rc; err1=$err; run --list "$ROOT/dir.md"
{ [ "$rc1" = 2 ] && printf '%s' "$err1" | grep -q '판정 불가' && [ "$rc" = 2 ] && [ -z "$out" ]; } && ok "C6.a 읽을 수 없는 입력(디렉터리) → rc 2·사유 — 통과(0)가 아니다" || nope "C6.a" "rc=$rc1/$rc err=$err1"
mkdir -p "$ROOT/stub"; printf '#!/usr/bin/env bash\nexit 3\n' > "$ROOT/stub/awk"; chmod +x "$ROOT/stub/awk"
out=$(PATH="$ROOT/stub:$PATH" bash "$CK" "$ROOT/p/.specops/memory/constitution.md" 2>"$ROOT/err"); rc=$?; err=$(cat "$ROOT/err")
{ [ "$rc" = 2 ] && printf '%s' "$err" | grep -q '판정 불가' && ! printf '%s' "$out" | grep -q 'OK\|SKIP'; } && ok "C6.b 표를 읽는 도구가 실패하면 rc 2 — 규칙 0건·통과로 답하지 않는다" || nope "C6.b" "rc=$rc out=$out err=$err"
printf '#!/usr/bin/env bash\nexit 0\n' > "$ROOT/stub/awk"
out=$(PATH="$ROOT/stub:$PATH" bash "$CK" "$ROOT/p/.specops/memory/constitution.md" 2>"$ROOT/err"); rc=$?; err=$(cat "$ROOT/err")
{ [ "$rc" = 2 ] && printf '%s' "$err" | grep -q '판정 불가'; } && ok "C6.c 도구가 rc 0 인데 아무것도 안 내도(끝 표시 없음) rc 2" || nope "C6.c" "rc=$rc out=$out err=$err"
run --bogus; r1=$rc; run "$ROOT/old.md" "$ROOT/ex.md"; r2=$rc; run ""; r3=$rc
{ [ "$r1" = 2 ] && [ "$r2" = 2 ] && [ "$r3" = 2 ]; } && ok "C6.d 모르는 옵션·파일 인자 2개·빈 문자열 인자 → rc 2(사용 오류 — 기본 경로로 떨어지지 않는다)" || nope "C6.d" "r1=$r1 r2=$r2 r3=$r3"
ln -s "$ROOT/no-such-target.md" "$ROOT/dangling.md"
run "$ROOT/dangling.md"; rc1=$rc; err1=$err; run --list "$ROOT/dangling.md"
{ [ "$rc1" = 2 ] && printf '%s' "$err1" | grep -q '판정 불가' && [ "$rc" = 2 ] && [ -z "$out" ]; } && ok "C6.f 끊어진 심볼릭 링크 → rc 2 — 헌법 없음(0)으로 답하지 않는다" || nope "C6.f" "rc=$rc1/$rc err=$err1"
printf '<!-- structure-rules:start -->\n%s\n%s\n| S-1 | 규\000칙 | `src/` | 검사 | - |\n<!-- structure-rules:end -->\n' "$HDR" "$SEP" > "$ROOT/nul.md"
run "$ROOT/nul.md"
{ [ "$rc" = 2 ] && printf '%s' "$err" | grep -q 'NUL'; } && ok "C6.g NUL 바이트가 든 파일(UTF-16 등) → rc 2 — 절 없음(0)으로 답하지 않는다" || nope "C6.g" "rc=$rc out=$out err=$err"
ln -s "$ROOT/nowhere-dir" "$ROOT/dirlink"
run "$ROOT/dirlink/constitution.md"; rc1=$rc; err1=$err; out1=$out; run --list "$ROOT/dirlink/constitution.md"
{ [ "$rc1" = 2 ] && [ -z "$out1" ] && printf '%s' "$err1" | grep -q '판정 불가' && [ "$rc" = 2 ] && [ -z "$out" ]; } && ok "C6.i 상위 경로가 끊어진 심볼릭 링크 → rc 2 — 링크를 지나쳐 올라가 헌법 없음(0)으로 답하지 않는다" || nope "C6.i" "rc=$rc1/$rc out=$out1 err=$err1"
mkdir -p "$ROOT/okdir"; ln -s "$ROOT/okdir" "$ROOT/oklink"
run "$ROOT/oklink/constitution.md"
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'SKIP (헌법 없음'; } && ok "C6.j 따라갈 수 있는 링크 아래에 파일이 없으면 종전대로 헌법 없음 · rc 0" || nope "C6.j" "rc=$rc out=$out err=$err"
if [ "$(id -u)" = 0 ]; then
  skip "C6.k 링크 대상이 들어갈 수 없는 디렉터리 — root 는 권한을 무시하므로 미실행"
else
  mkdir -p "$ROOT/vault/memory"; cp "$ROOT/p/.specops/memory/constitution.md" "$ROOT/vault/memory/constitution.md"; ln -s "$ROOT/vault/memory" "$ROOT/memlink"; chmod 000 "$ROOT/vault"
  run "$ROOT/memlink/constitution.md"; rc1=$rc; err1=$err; out1=$out; run --list "$ROOT/memlink/constitution.md"; chmod 700 "$ROOT/vault"
  { [ "$rc1" = 2 ] && [ -z "$out1" ] && printf '%s' "$err1" | grep -q '판정 불가' && [ "$rc" = 2 ] && [ -z "$out" ]; } \
    && ok "C6.k 상위 경로가 막힌 대상을 가리키는 링크(헌법은 실재) → rc 2 — 헌법 없음(0)으로 답하지 않는다" || nope "C6.k" "rc=$rc1/$rc out=$out1 err=$err1"
fi
if [ "$(id -u)" = 0 ]; then
  skip "C6.h 들어갈 수 없는 상위 디렉터리 — root 는 권한을 무시하므로 미실행"
else
  mkdir -p "$ROOT/locked/memory"; cp "$ROOT/p/.specops/memory/constitution.md" "$ROOT/locked/memory/constitution.md"; chmod 000 "$ROOT/locked/memory"
  run "$ROOT/locked/memory/constitution.md"; rc1=$rc; err1=$err; out1=$out; run --list "$ROOT/locked/memory/constitution.md"; chmod 700 "$ROOT/locked/memory"
  { [ "$rc1" = 2 ] && [ -z "$out1" ] && printf '%s' "$err1" | grep -q '판정 불가' && [ "$rc" = 2 ] && [ -z "$out" ]; } \
    && ok "C6.h 들어갈 수 없는 상위 디렉터리 아래의 헌법 → rc 2 — 헌법 없음(0)으로 답하지 않는다" || nope "C6.h" "rc=$rc1/$rc out=$out1 err=$err1"
fi
before=$(cd "$ROOT/p" && find . -type f -exec cksum {} + | sort); ( cd "$ROOT/p" && bash "$CK" >/dev/null 2>&1; bash "$CK" --list >/dev/null 2>&1 ); after=$(cd "$ROOT/p" && find . -type f -exec cksum {} + | sort)
[ "$before" = "$after" ] && ok "C6.e 읽기 전용 — 실행 전후 파일 목록·내용이 같다" || nope "C6.e" "파일이 바뀜"

finish
