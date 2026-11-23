#!/usr/bin/env bash
# test-board-mode.sh — scripts/_internal/board-mode.sh (관제판의 명령별 구성 자료 · 읽기 전용)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않는다
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BM="$PLUGIN/scripts/_internal/board-mode.sh"
ok() { PASS=$((PASS+1)); echo "PASS $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL $1 — ${2:-}"; }
has() { printf '%s\n' "$1" | grep -qxF -- "$2"; }   # 줄 전체 일치
TAB="$(printf '\t')"

T=$(mktemp -d) || exit 1; T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
# 실제 하류 구조: <프로젝트>/.specops/{session-progress.md,<FID>/…,batch-*/queue.md,.init-timing}
P="$T/proj"; S="$P/.specops"; mkdir -p "$S"
_bm() { (cd "$P" && bash "$BM" "$@" 2>&1); }
_fid() { mkdir -p "$S/$1"; }
_led() { cat > "$S/session-progress.md"; }

# ── B1 초기화 — 표시 파일(.init-timing)이 있으면 작업이 없어도 흐름·소요·시각을 낸다 ──
NOW=$(date +%s); T0=$((NOW - 600))   # 10분 전에 시작한 초기화
printf '%s\tphase0\n%s\tanswers\n%s\tbash-start\n%s\tbash-end\n%s\tinterview\n' "$T0" $((T0 + 180)) $((T0 + 190)) $((T0 + 240)) $((T0 + 480)) > "$S/.init-timing"
out=$(_bm)
has "$out" "MODE${TAB}init${TAB}프로젝트 초기화" && ok "B1.a 작업 인자 없이도 초기화를 알린다" || no "B1.a" "$out"
[ "$(printf '%s\n' "$out" | grep -c "^STEP${TAB}done")" = 4 ] && has "$out" "STEP${TAB}cur${TAB}보강" && [ "$(printf '%s\n' "$out" | grep -c "^STEP${TAB}todo")" = 3 ] \
  && ok "B1.b 준비·답변·골격·인터뷰 끝 → 지금 보강 · 남은 3" || no "B1.b" "$out"
has "$out" "ROW${TAB}{d|답변 3분 · 골격 1분 · 인터뷰 4분}${TAB}" && ok "B1.c 단계별 소요(앞 표시부터 그 표시까지)" || no "B1.c" "$out"
has "$out" "SINCE${TAB}$((T0 + 480))" && ok "B1.d 지금 단계가 시작된 시각 = 마지막 표시" || no "B1.d" "$out"
# 초기화가 도는 동안 앞선 작업이 활성으로 남아 있어도 초기화를 보인다 — 그 작업의 최근 기록이 표시보다 앞선다
_fid 20200101-old; printf '# s\n\n**§유형**: 신규\n' > "$S/20200101-old/spec.md"
_led <<EOF
## 20200101-old · x
- 2020-01-01 10:00 /implement 진행 (x)
EOF
has "$(_bm 20200101-old | head -1)" "MODE${TAB}init${TAB}프로젝트 초기화" && ok "B1.h 앞선 작업이 활성이어도 도는 초기화를 보인다(기록이 표시보다 앞선다)" || no "B1.h" "$(_bm 20200101-old)"
_led <<EOF
## 20200101-old · x
- $(date -r $((NOW + 120)) '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$((NOW + 120))" '+%Y-%m-%d %H:%M') /implement 진행 (x)
EOF
has "$(_bm 20200101-old | head -1)" "MODE${TAB}start${TAB}신규 기능" && ok "B1.i 표시보다 뒤에 기록된 작업은 그 작업으로 보인다" || no "B1.i" "$(_bm 20200101-old)"
# B1.k ★ 기록 시각(분 단위)을 읽을 때 초를 :00 으로 못 박는다 — macOS date -j 는 초가 형식에 없으면 지금의 초로 채워 같은 입력이 호출마다 달랐다(20261123).
#   가짜 date 로 -j 호출의 인자를 받아 본다(어느 OS 에서든 -j 가 먼저 불린다).
mkdir -p "$T/fakedate"; : > "$T/fakedate/log"
cat > "$T/fakedate/date" <<FD
#!/usr/bin/env bash
case "\$1" in -j) echo "\$*" >> "$T/fakedate/log"; echo 1 ;; *) exec $(command -v date) "\$@" ;; esac
FD
chmod +x "$T/fakedate/date"
_led <<EOF
## 20200101-old · x
- 2020-01-01 10:00 /implement 진행 (x)
EOF
( cd "$P" && PATH="$T/fakedate:$PATH" bash "$BM" 20200101-old >/dev/null 2>&1 )
has "$(cat "$T/fakedate/log")" "-j -f %Y-%m-%d %H:%M:%S 2020-01-01 10:00:00 +%s" && ok "B1.k ★ 기록 시각은 초까지(:00) 읽는다 — 호출마다 값이 흔들리지 않는다" || no "B1.k" "$(cat "$T/fakedate/log")"
printf '%s\tphase0\n' $((NOW - 30000)) > "$S/.init-timing"
[ -z "$(_bm)" ] && ok "B1.j 6시간 넘게 멈춘 표시 파일은 '돌고 있다'로 보지 않는다(중단돼 남은 것)" || no "B1.j" "$(_bm)"
rm -rf "$S/20200101-old"; rm -f "$S/session-progress.md"
printf 'garbage\n\tx\n' > "$S/.init-timing"
[ -z "$(_bm)" ] && ok "B1.e 표시 파일이 깨졌으면 아무것도 내지 않는다" || no "B1.e" "$(_bm)"
rm -f "$S/.init-timing"
[ -z "$(_bm)" ] && ok "B1.f 표시 파일도 작업도 없으면 빈 출력" || no "B1.f" "$(_bm)"
_fid 20261116-init-project
out=$(_bm 20261116-init-project)
[ "$(printf '%s\n' "$out" | grep -c "^STEP${TAB}done")" = 8 ] && ok "B1.g 끝난 초기화 작업은 여덟 단계가 모두 끝남이다" || no "B1.g" "$out"

# ── B2 /start — 갈래(기본·풀·승격)와 판정 기록 ──
A=20261117-alpha; _fid $A; printf '# s\n\n**§유형**: 신규\n' > "$S/$A/spec.md"; printf 'tasks=2\nsignals=\nexperts=\n' > "$S/$A/steps.txt"
_led <<EOF
## $A · x
- 2026-11-17 10:00 /basic 시작 (x)
EOF
out=$(_bm $A)
has "$out" "MODE${TAB}start${TAB}신규 기능" && has "$out" "ROW${TAB}{d|갈래} 기본 {d|· 위험 신호 없음 · 태스크 2}${TAB}" && ok "B2.a 기본 경로 — 판정 기록의 태스크 수 · 신호 없음" || no "B2.a" "$out"
! printf '%s\n' "$out" | grep -q "^STEP" && ok "B2.b /start 는 흐름을 내지 않는다(관제판이 작업의 단계 막대를 쓴다)" || no "B2.b" "$out"
printf 'tasks=1\nsignals=auth db_schema\nexperts=x\n' > "$S/$A/steps.txt"
out=$(_bm $A)
has "$out" "ROW${TAB}{d|갈래} 기본 {d|· 신호 있음 · 태스크 1}${TAB}" && ! printf '%s' "$out" | grep -q 'auth' && ok "B2.c 가벼운 신호가 있으면 '신호 있음'(신호 이름은 싣지 않는다)" || no "B2.c" "$out"
echo x > "$S/$A/intent.md"
has "$(_bm $A)" "ROW${TAB}{d|갈래} 풀${TAB}" && ok "B2.d intent 가 있으면 풀 경로" || no "B2.d" "$(_bm $A)"
mkdir "$S/$A/basic-draft"
has "$(_bm $A)" "ROW${TAB}{d|갈래} 기본→풀 승격${TAB}" && ok "B2.e basic-draft 가 있으면 승격" || no "B2.e" "$(_bm $A)"

# ── B3 계획 안쪽 단계 — 계획이 도는 동안만 ──
_led <<EOF
## $A · x
- 2026-11-17 10:20 /plan-expert 진행 (x)
- 2026-11-17 10:10 /plan-draft 완료 (x)
- 2026-11-17 10:00 /specify 완료 (x)
EOF
has "$(_bm $A)" "ROW${TAB}{d|계획 │} 초안{k|✓} {k|전문가●} {d|리뷰○} {d|확정○}${TAB}" && ok "B3.a 초안 끝 · 전문가 진행 · 리뷰·확정 남음" || no "B3.a" "$(_bm $A)"
_led <<EOF
## $A · x
- 2026-11-17 10:40 /tasks 완료 (x)
- 2026-11-17 10:20 /plan-expert 완료 (x)
- 2026-11-17 10:10 /plan-draft 완료 (x)
EOF
! _bm $A | grep -q '계획 │' && ok "B3.b 분해까지 갔으면 계획 줄을 내리지 않는다" || no "B3.b" "$(_bm $A)"

# ── B4 /start-foundation — spec 의 §유형 과 진행 기록 제목의 FR 번호 ──
F=20261116-sso-login; _fid $F; printf '# s\n\n**§유형**: foundation\n' > "$S/$F/spec.md"
_led <<EOF
## $F · 사내 SSO 로그인(FR-5)
- 2026-11-16 10:00 /specify 완료 (x)
EOF
has "$(_bm $F)" "MODE${TAB}foundation${TAB}공통부 FR-5" && ok "B4.a 공통부 + FR 번호" || no "B4.a" "$(_bm $F)"
_led <<EOF
## $F · 제목에 번호 없음
- 2026-11-16 10:00 /specify 완료 (x)
EOF
has "$(_bm $F)" "MODE${TAB}foundation${TAB}공통부" && ok "B4.b FR 번호가 없으면 '공통부' 만" || no "B4.b" "$(_bm $F)"

# ── B5 /maintain — §유형 또는 분석 기록 · 회귀 기준 ──
M=20261117-fix-token; _fid $M
printf '# s\n\n**§유형**: 유지보수\n\n### AC-R-1: 기존 동작\n' > "$S/$M/spec.md"; printf '### AC-R-1: 기존 동작\n### AC-R-2: 데이터\n### AC-1: 새 동작\n' > "$S/$M/acceptance-criteria.md"
_led <<EOF
## $M · x
- 2026-11-17 10:00 /implement 진행 (x)
EOF
out=$(_bm $M)
has "$out" "MODE${TAB}maintain${TAB}유지보수" && has "$out" "ROW${TAB}{d|기존 동작 보존} 회귀 기준 2건${TAB}{d|○ 검증 전}" && ok "B5.a 유지보수 · 회귀 기준 2건(중복은 한 번) · 검증 전" || no "B5.a" "$out"
_led <<EOF
## $M · x
- 2026-11-17 10:30 /verify PASS (x)
- 2026-11-17 10:00 /implement 완료 (x)
EOF
has "$(_bm $M)" "ROW${TAB}{d|기존 동작 보존} 회귀 기준 2건${TAB}{g|✓ 검증됨}" && ok "B5.b 검증 PASS 뒤에는 '검증됨'" || no "B5.b" "$(_bm $M)"
printf '# s\n\n**§유형**: trivial\n' > "$S/$M/spec.md"
_led <<EOF
## $M · x
- 2026-11-17 10:00 /analyze 완료 (x)
EOF
has "$(_bm $M)" "MODE${TAB}maintain${TAB}유지보수" && ok "B5.c §유형 이 달라도 분석 기록이 있으면 유지보수" || no "B5.c" "$(_bm $M)"

# ── B6 /start-all — 큐에서 묶음 흐름과 FR 목록 ──
R=20261116-room-list; V=20261116-reservation; _fid $R; _fid $V
for f in $R $V; do printf '# s\n\n**§유형**: 신규\n**§batch**: batch-20261116-2014\n' > "$S/$f/spec.md"; done
Q="$S/batch-20261116-2014"; mkdir -p "$Q"; : > "$Q/ACTIVE"
_queue() { cat > "$Q/queue.md"; }
_queue <<EOF
# 큐

| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | — | (시드) | SKIP |
| \`FR-7\` | $R | 회의실 {목록} 조회 — 활성 회의실의 이름 | **IMPL_DONE** |
| FR-8 | $V | 날짜별 예약 현황 조회 — 슬롯 | PLAN_DONE |
| FR-9 | 20261116-x | 예약 생성 | PLAN_DONE |
| FR-11 | 20261116-y | 알림 발송 | HELD |
EOF
: > "$Q/plan-review.md"; : > "$Q/design-review.md"
_led <<EOF
## $V · x
- 2026-11-16 21:00 /implement 진행 (x)
EOF
out=$(_bm $V)
has "$out" "MODE${TAB}batch${TAB}일괄 묶음 1/4" && ok "B6.a 끝난 FR 1 / 전체 4 (SKIP 제외 · 굵게·백틱 표기 흡수)" || no "B6.a" "$out"
[ "$(printf '%s\n' "$out" | grep "^STEP" | cut -f2 | tr '\n' ' ')" = "done done done done cur todo todo " ] && has "$out" "STEP${TAB}cur${TAB}구현" && ok "B6.b 묶음 흐름 — 지금 구현" || no "B6.b" "$out"
has "$out" "FR${TAB}done${TAB}FR-7${TAB}회의실 목록 조회${TAB}" && has "$out" "FR${TAB}cur${TAB}FR-8${TAB}날짜별 예약 현황 조회${TAB}" && has "$out" "FR${TAB}todo${TAB}FR-9${TAB}예약 생성${TAB}" && has "$out" "FR${TAB}hold${TAB}FR-11${TAB}알림 발송${TAB}보류" \
  && ok "B6.c FR 줄 — 끝남·지금·남음·보류 · 설명은 ' — ' 앞까지" || no "B6.c" "$out"
! printf '%s\n' "$out" | grep -q 'FR-1'"$TAB" && ok "B6.d SKIP 인 FR 은 목록에 없다" || no "B6.d" "$out"
[ "$(printf '%s\n' "$out" | awk -F'\t' '{ print NF }' | sort -u | tr '\n' ' ')" = "3 5 " ] && ! printf '%s' "$out" | grep -q '[{}|]' && ok "B6.e 설명의 탭·중괄호·세로줄을 지워 줄 형식을 지킨다" || no "B6.e" "$out"
rm -f "$Q/plan-review.md" "$Q/design-review.md"
has "$(_bm $V | grep "${TAB}cur${TAB}" | head -1)" "STEP${TAB}cur${TAB}계획 리뷰" && ok "B6.f 계획 리뷰 파일이 없으면 지금 계획 리뷰" || no "B6.f" "$(_bm $V)"
sed -i.bak 's/| PLAN_DONE |$/| PENDING |/' "$Q/queue.md"
has "$(_bm $V | grep "${TAB}cur${TAB}" | head -1)" "STEP${TAB}cur${TAB}FR 명세" && ok "B6.g PENDING 이 남았으면 지금 FR 명세" || no "B6.g" "$(_bm $V)"
: > "$Q/plan-review.md"; sed -i.bak 's/| PENDING |$/| IMPL_DONE |/; s/| HELD |$/| MERGED |/' "$Q/queue.md"
out=$(_bm $V)
has "$out" "STEP${TAB}skip${TAB}통합 설계" && has "$out" "STEP${TAB}cur${TAB}통합" && ok "B6.h 전부 끝났으면 지금 통합 · 설계 리뷰가 없었으면 생략 표시" || no "B6.h" "$out"
rm -f "$Q/ACTIVE"
has "$(_bm $V)" "MODE${TAB}start${TAB}신규 기능" && ok "B6.i 묶음이 끝났으면(ACTIVE 없음) 일괄로 그리지 않는다" || no "B6.i" "$(_bm $V)"

# ── B7 /quick-fix — 명세 없이 태스크 문서만 ──
K=20261117-quick; _fid $K; echo "# tasks" > "$S/$K/tasks.md"
cat > "$T/mk.sh" <<'MK'
cd "$1" && git init -q -b main . && printf '.specops/\n' > .gitignore && echo a > a.txt && git add -A && git -c user.name=t -c user.email=t@t commit -q -m init
MK
bash "$T/mk.sh" "$P"
_led <<EOF
## $K · x
- 2026-11-17 10:00 /quick-fix 시작 (x)
EOF
out=$(_bm $K)
has "$out" "MODE${TAB}quick${TAB}몇 줄 수정" && has "$out" "STEP${TAB}cur${TAB}수정" && ok "B7.a 시작 직후(변경 없음) — 지금 수정" || no "B7.a" "$out"
echo b >> "$P/a.txt"
has "$(_bm $K)" "STEP${TAB}cur${TAB}테스트" && ok "B7.b 변경이 생기면 지금 테스트" || no "B7.b" "$(_bm $K)"
mkdir -p "$S/$K/receipts"; echo '{}' > "$S/$K/receipts/T1.json"
has "$(_bm $K)" "STEP${TAB}cur${TAB}리뷰" && ok "B7.c 영수증이 있으면 지금 리뷰" || no "B7.c" "$(_bm $K)"
mkdir -p "$S/$K/reviews"; echo x > "$S/$K/reviews/T1-C-report.md"
out=$(_bm $K)
has "$out" "STEP${TAB}cur${TAB}커밋" && ok "B7.d 리뷰 보고서가 있으면 지금 커밋" || no "B7.d" "$out"
mf=$(sed -n 's/^QUICK_MAX_IMPL_FILES=//p' "$PLUGIN/scripts/_internal/quick-scope.sh"); ml=$(sed -n 's/^QUICK_MAX_LINES=//p' "$PLUGIN/scripts/_internal/quick-scope.sh")
has "$out" "ROW${TAB}{d|범위 상한} 파일 $mf · 줄 $ml${TAB}" && ok "B7.g ★ 스테이징 전에는 판정을 붙이지 않는다(판정기의 '판정 불가'를 범위 초과로 그리지 않는다)" || no "B7.g" "$out"
cat > "$T/add.sh" <<'AD'
cd "$1" && git add a.txt
AD
bash "$T/add.sh" "$P"; out=$(_bm $K)
printf '%s\n' "$out" | grep -qE "^ROW${TAB}\{d\|범위 상한\} 파일 $mf · 줄 $ml${TAB}\{(g\|범위 안|w\|범위 초과)\}$" && ok "B7.h 스테이징 뒤에는 판정기의 판정을 붙인다" || no "B7.h" "$out"
printf '%s\n' "$out" | grep -q "^ROW${TAB}{d|범위 상한} 파일 $mf · 줄 $ml${TAB}" && ok "B7.e 범위 상한은 판정기의 상수 그대로(파일 $mf · 줄 $ml)" || no "B7.e" "$out"
_led <<EOF
## $K · x
- 2026-11-17 10:30 /lifecycle DONE (quick-fix)
- 2026-11-17 10:00 /quick-fix 시작 (x)
EOF
out=$(_bm $K)
[ "$(printf '%s\n' "$out" | grep -c "^STEP${TAB}done")" = 5 ] && ! printf '%s\n' "$out" | grep -q '범위 상한' && ok "B7.f 끝난 작업 — 다섯 단계 끝남 · 범위 줄 없음" || no "B7.f" "$out"

# ── B8 판정할 수 없으면 조용히 ──
[ -z "$(_bm 20991231-nothing)" ] && ok "B8.a 없는 작업 → 빈 출력" || no "B8.a" "$(_bm 20991231-nothing)"
[ -z "$(_bm '../../etc')" ] && [ -z "$(_bm 'BAD FID')" ] && ok "B8.b 작업 이름 꼴이 아니면 빈 출력(초기화도 아님)" || no "B8.b"
E="$T/empty"; mkdir -p "$E"
[ -z "$(cd "$E" && bash "$BM" $A 2>&1)" ] && ok "B8.c .specops 가 없으면 빈 출력" || no "B8.c"
L="$T/linked"; mkdir -p "$L"; ln -s "$S" "$L/.specops"
[ -z "$(cd "$L" && bash "$BM" $A 2>&1)" ] && ok "B8.d .specops 가 링크면 읽지 않는다" || no "B8.d"
(cd "$P" && bash "$BM" $A >/dev/null 2>&1); rc=$?
(cd "$E" && bash "$BM" >/dev/null 2>&1); rc2=$?
[ "$rc" = 0 ] && [ "$rc2" = 0 ] && ok "B8.e 종료 코드는 항상 0" || no "B8.e" "$rc $rc2"

# ── B9 관찰만 한다 — 아무것도 쓰지 않는다 ──
touch "$P/a.txt"   # stat 만 바뀐 파일 — git 이 index 를 다시 쓰려 드는 상태
idx_before=$(cksum < "$P/.git/index")
before=$(cd "$P" && find .specops -type f | sort | xargs cksum 2>/dev/null | cksum)
for f in "" $A $F $M $V $K 20261116-init-project; do _bm $f >/dev/null; done
after=$(cd "$P" && find .specops -type f | sort | xargs cksum 2>/dev/null | cksum)
[ "$before" = "$after" ] && ok "B9.a 여섯 명령을 다 불러도 .specops 가 그대로다" || no "B9.a"
[ "$idx_before" = "$(cksum < "$P/.git/index")" ] && ok "B9.b ★ git index 도 다시 쓰지 않는다(GIT_OPTIONAL_LOCKS=0 — 주 세션의 git 과 겹치지 않는다)" || no "B9.b"

# ── B10 관제판 코드와의 계약 ──
grep -q "scripts/_internal/board-mode.sh" "$PLUGIN/hooks/progress-pane.tsx" && ok "B10.a 관제판이 이 스크립트를 부른다" || no "B10.a"
kinds=$(grep -oE "MODE\\\\t[a-z]+" "$BM" | sed 's/^MODE..//' | sort -u | tr '\n' ' ')
[ "$kinds" = "batch foundation init maintain quick start " ] && ok "B10.b 내는 종류는 여섯 — init·foundation·batch·start·maintain·quick" || no "B10.b" "$kinds"
for k in init foundation batch start maintain quick; do grep -q "'$k'" "$PLUGIN/hooks/progress-pane.tsx" || { no "B10.c" "관제판이 '$k' 를 모른다"; k=""; break; }; done
[ -n "$k" ] && ok "B10.c 관제판이 여섯 종류를 모두 안다"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
