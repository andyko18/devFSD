#!/usr/bin/env bash
# /quick-fix 경로 (FID 20261010-quick-fix-path) — 명세 없는 1-태스크 FID 의 범위 상한·리뷰·영수증.
#
# 왜 필요한가: "태스크 문서는 있고 명세는 없는 FID" 는 영수증만 유효하면 커밋이 열렸다 — 문서도 리뷰도 크기 상한도 없이.
#   실사용 0건이라 드러나지 않았을 뿐인 통로다. 그 통로를 quick 경로로 정식화하면서 범위·리뷰를 커밋 시점에 강제한다.
#   판정은 판정기 한 곳(quick-scope.sh)이 하고, 훅이 부르는 영수증 검사기와 봉인 스크립트가 같이 쓴다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE   # 훅 환경에서 돌아도 픽스처가 실 저장소를 건드리지 않게

QS="$PLUGIN/scripts/_internal/quick-scope.sh"
F=20261010-q1
_SBS=""

# 격리 저장소 — 구현 1파일·테스트 1파일이 커밋돼 있고 .specops 가 있다(specops 관할)
_mk() {
  local sb; sb=$(mktemp -d) || return 1
  ( cd "$sb" && git init -q && git checkout -q -b work && mkdir -p src tests .specops \
      && printf 'echo v1\n' > src/a.sh \
      && printf '#!/usr/bin/env bash\ngrep -q v2 src/a.sh\n' > tests/t.sh \
      && git add src tests && git -c user.name=t -c user.email=t@e.com commit -qm init ) >/dev/null 2>&1 || return 1
  printf '%s' "$sb"
}
# 리뷰 보고서 — 저장 훅(save-review-report.sh)의 파일 규약 그대로: 통과가 아니면 feedback 을 함께 쓴다
_review() {  # <sb> <PASS|FAIL>
  mkdir -p "$1/.specops/$F/reviews"
  printf '# 코드 품질 리뷰\n' > "$1/.specops/$F/reviews/T1-C-report.md"
  [ "$2" = PASS ] || cp "$1/.specops/$F/reviews/T1-C-report.md" "$1/.specops/$F/reviews/T1-C-feedback.md"
}
_scope() { ( cd "$1" && bash "$QS" "$F" T1 2>&1 ); }                       # <sb> → 판정 줄 · rc
_n() { local i=0; while [ "$i" -lt "$1" ]; do echo "echo line$i"; i=$((i+1)); done; }   # <N> → N줄
# ── Q1 범위 안 — 판정기 ──────────────────────────────────────────────────────
sb=$(_mk); _SBS="$_SBS $sb"; mkdir -p "$sb/.specops/$F"
( cd "$sb" && printf 'echo v2\n' > src/a.sh && git add src/a.sh ); _review "$sb" PASS
out=$(_scope "$sb"); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^QUICK-SCOPE: OK 구현 파일 1개 · 2줄' \
  && ok "Q1.a 구현 1파일·2줄 + 통과 리뷰 → OK" || nope "Q1.a" "rc=$rc out=$out"

# ── Q2 경계값 — 파일 수·줄 수, 테스트·문서 제외 (AC-2) ──────────────────────
( cd "$sb" && _n 10 > src/b.sh && git add src/b.sh ); _review "$sb" PASS      # 구현 2파일 · 2+10=12줄
out=$(_scope "$sb"); rc=$?
[ "$rc" = 0 ] && ok "Q2.a 구현 파일 2개(상한) → OK" || nope "Q2.a" "rc=$rc out=$out"
( cd "$sb" && _n 1 > src/inspect.sh && git add src/inspect.sh )                # 이름에 spec 이 든 **구현** 파일
out=$(_scope "$sb"); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'OVER 구현 파일 3개 (상한 2개)' \
  && ok "Q2.b 구현 파일 3개 → OVER (inspect.sh 는 테스트가 아니다)" || nope "Q2.b" "rc=$rc out=$out"
( cd "$sb" && git rm -q --cached src/inspect.sh && rm -f src/inspect.sh && _n 18 > src/b.sh && git add src/b.sh ); _review "$sb" PASS   # 2+18=20줄
out=$(_scope "$sb"); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '· 20줄' && ok "Q2.c 변경 20줄(상한) → OK" || nope "Q2.c" "rc=$rc out=$out"
( cd "$sb" && _n 19 > src/b.sh && git add src/b.sh )                           # 2+19=21줄
out=$(_scope "$sb"); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'OVER 변경 21줄 (상한 20줄' \
  && ok "Q2.d 변경 21줄 → OVER" || nope "Q2.d" "rc=$rc out=$out"
( cd "$sb" && _n 18 > src/b.sh && _n 200 > tests/t_big.sh && _n 300 > NOTES.md && _n 50 > src/util_test.go \
    && git add src/b.sh tests/t_big.sh NOTES.md src/util_test.go ); _review "$sb" PASS
out=$(_scope "$sb"); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '구현 파일 2개 · 20줄' \
  && ok "Q2.e 테스트(tests/ · *_test.go)·문서는 파일 수·줄 수에 넣지 않는다" || nope "Q2.e" "rc=$rc out=$out"

# ── Q3 고위험 신호 — 작아도 quick 이 아니다 (AC-2) ──────────────────────────
_sig() {  # <라벨> <기대 신호> <준비를 마친 샌드박스> — 준비는 호출부가 한다(명령 문자열을 받아 실행하지 않는다)
  local s="$3" o r; _review "$s" PASS
  o=$(_scope "$s"); r=$?
  [ "$r" = 3 ] && printf '%s' "$o" | grep -q "OVER 고위험 신호:.*$2" && ok "$1" || nope "$1" "rc=$r out=$o"
}
s=$(_mk); _SBS="$_SBS $s"; mkdir -p "$s/.specops/$F"
( cd "$s" && printf "echo x\n" > src/auth.sh && git add src/auth.sh ) >/dev/null 2>&1
_sig "Q3.a 경로에 auth → 고위험(auth)" 'auth' "$s"
s=$(_mk); _SBS="$_SBS $s"; mkdir -p "$s/.specops/$F"
( cd "$s" && printf "echo \"ALTER TABLE t ADD c int\"\n" > src/a.sh && git add src/a.sh ) >/dev/null 2>&1
_sig "Q3.b 변경 줄에 ALTER TABLE → 고위험(db_migration)" 'db_migration' "$s"
s=$(_mk); _SBS="$_SBS $s"; mkdir -p "$s/.specops/$F"
( cd "$s" && mkdir -p screens && printf "<p>x</p>\n" > screens/list.html && printf "echo v2\n" > src/a.sh && git add screens src/a.sh ) >/dev/null 2>&1
_sig "Q3.c 화면 문서를 함께 고침 → 고위험(ui_if)" 'ui_if' "$s"
s=$(_mk); _SBS="$_SBS $s"; mkdir -p "$s/.specops/$F"
( cd "$s" && mkdir -p .claude-plugin hooks && printf "{}\n" > .claude-plugin/plugin.json && git add .claude-plugin && git -c user.name=t -c user.email=t@e.com commit -qm p && printf "echo h\n" > hooks/x.sh && git add hooks/x.sh ) >/dev/null 2>&1
_sig "Q3.d 플러그인 저장소의 훅 수정 → 고위험(plugin_runtime)" 'plugin_runtime' "$s"
s=$(_mk); _SBS="$_SBS $s"; mkdir -p "$s/.specops/$F"
( cd "$s" && mkdir -p prisma && printf "model U {\n  id Int\n}\n" > prisma/schema.prisma && git add prisma ) >/dev/null 2>&1
_sig "Q3.g 스키마 정의 파일(schema.prisma)에 필드 한 줄 → 고위험(schema)" 'schema' "$s"
s=$(_mk); _SBS="$_SBS $s"; mkdir -p "$s/.specops/$F"
( cd "$s" && mkdir -p db && printf "ADD COLUMN email text;\n" > db/001.sql && git add db ) >/dev/null 2>&1
_sig "Q3.h .sql 의 ADD COLUMN(TABLE 키워드 없음) → 고위험(schema)" 'schema' "$s"
s=$(_mk); _SBS="$_SBS $s"; mkdir -p "$s/.specops/$F"
( cd "$s" && printf "echo \"ALTER TABLE t ADD c int\"\n" > src/한글.sh && git add src/한글.sh ) >/dev/null 2>&1
_sig "Q3.i 한글 경로의 변경 줄에 ALTER TABLE → 고위험(db_migration) — 비ASCII 경로도 내용을 본다" 'db_migration' "$s"
# 대조 — 변경하지 않은 줄(문맥)의 낱말은 신호가 아니다
sb2=$(_mk); _SBS="$_SBS $sb2"; mkdir -p "$sb2/.specops/$F"
( cd "$sb2" && printf '# permission 검사는 다른 곳에서 한다\necho v1\n' > src/a.sh && git add src/a.sh \
    && git -c user.name=t -c user.email=t@e.com commit -qm c && printf '# permission 검사는 다른 곳에서 한다\necho v2\n' > src/a.sh && git add src/a.sh ) >/dev/null 2>&1
_review "$sb2" PASS; out=$(_scope "$sb2"); rc=$?
[ "$rc" = 0 ] && ok "Q3.e 바뀌지 않은 줄의 낱말은 신호가 아니다(변경 줄만 본다)" || nope "Q3.e" "rc=$rc out=$out"
# 바이너리
sb3=$(_mk); _SBS="$_SBS $sb3"; mkdir -p "$sb3/.specops/$F"
( cd "$sb3" && printf '\000\001\002\003' > src/blob.bin && git add src/blob.bin ); _review "$sb3" PASS
out=$(_scope "$sb3"); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'OVER 바이너리 파일 변경' && ok "Q3.f 바이너리 변경 → OVER (줄 수를 셀 수 없다)" || nope "Q3.f" "rc=$rc out=$out"

# ── Q4 리뷰 — 없음 · 불통과 · 수정보다 오래됨 (AC-3) ────────────────────────
sb=$(_mk); _SBS="$_SBS $sb"; mkdir -p "$sb/.specops/$F"
( cd "$sb" && printf 'echo v2\n' > src/a.sh && git add src/a.sh )
out=$(_scope "$sb"); rc=$?
[ "$rc" = 4 ] && printf '%s' "$out" | grep -q 'NOREVIEW 리뷰 보고서가 없다' && ok "Q4.a 리뷰 보고서 없음 → NOREVIEW(4)" || nope "Q4.a" "rc=$rc out=$out"
_review "$sb" FAIL; out=$(_scope "$sb"); rc=$?
[ "$rc" = 4 ] && printf '%s' "$out" | grep -q 'NOREVIEW 마지막 리뷰 판정이 통과가 아니다' && ok "Q4.b 통과가 아닌 판정 → NOREVIEW(4)" || nope "Q4.b" "rc=$rc out=$out"
touch -t 202001010000 "$sb/.specops/$F/reviews/T1-C-feedback.md"; _review "$sb" PASS   # 옛 불통과 뒤에 통과 판정이 새로 왔다
out=$(_scope "$sb"); rc=$?
[ "$rc" = 0 ] && ok "Q4.c 옛 feedback 이 남아 있어도 마지막 판정이 통과면 OK" || nope "Q4.c" "rc=$rc out=$out"
touch -t 201901010000 "$sb/.specops/$F/reviews/T1-C-feedback.md"                      # (feedback 은 report 보다 더 오래된 채로 둔다)
touch -t 202001010000 "$sb/.specops/$F/reviews/T1-C-report.md"                        # 리뷰가 수정보다 오래됐다
out=$(_scope "$sb"); rc=$?
[ "$rc" = 4 ] && printf '%s' "$out" | grep -q 'NOREVIEW 리뷰 뒤에 src/a.sh 가 다시 수정됐다' \
  && ok "Q4.d 리뷰 뒤에 코드를 다시 고침 → NOREVIEW(4)" || nope "Q4.d" "rc=$rc out=$out"
# 한글 경로도 신선도를 본다 — git 의 경로 이스케이프 때문에 파일을 못 찾아 비교를 건너뛰면 안 된다
sbk=$(_mk); _SBS="$_SBS $sbk"; mkdir -p "$sbk/.specops/$F"
( cd "$sbk" && printf 'echo k\n' > src/한글.sh && git add src/한글.sh ); _review "$sbk" PASS
touch -t 202001010000 "$sbk/.specops/$F/reviews/T1-C-report.md"
out=$(_scope "$sbk"); rc=$?
[ "$rc" = 4 ] && printf '%s' "$out" | grep -q 'NOREVIEW 리뷰 뒤에 src/한글.sh 가 다시 수정됐다' \
  && ok "Q4.g 한글 경로 — 리뷰 뒤 수정을 놓치지 않는다" || nope "Q4.g" "rc=$rc out=$out"
# 범위와 리뷰가 둘 다 걸리면 범위를 먼저 말한다(리뷰를 받아도 소용없으므로)
( cd "$sb" && _n 30 > src/a.sh && git add src/a.sh ); out=$(_scope "$sb"); rc=$?
[ "$rc" = 3 ] && ok "Q4.e 범위 초과 + 리뷰 미충족 → 범위 초과(3)를 먼저 말한다" || nope "Q4.e" "rc=$rc out=$out"
exp=$(cd "$sb" && bash "$QS" "$F" T1 --explain 2>/dev/null)
[ "$exp" = "변경 31줄 (상한 20줄 · 테스트·문서 제외)" ] && ok "Q4.f --explain 은 접두 없이 사유만 낸다" || nope "Q4.f" "out=$exp"

# ── Q5 판정 불가는 막는 쪽이다 (NFR-3) ──────────────────────────────────────
sbn=$(_mk); _SBS="$_SBS $sbn"; mkdir -p "$sbn/.specops/$F"; _review "$sbn" PASS
out=$(_scope "$sbn"); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'OVER 판정 불가 — 스테이징된 변경이 없다' \
  && ok "Q5.a 스테이징된 변경이 없으면 판정 불가 → 3 (통과가 아니다)" || nope "Q5.a" "rc=$rc out=$out"
nog=$(mktemp -d); _SBS="$_SBS $nog"            # 임시 폴더가 어떤 저장소 안에 있어도 위로 올라가 찾지 않게 한다
out=$(cd "$nog" && GIT_CEILING_DIRECTORIES="$(dirname "$nog")" bash "$QS" "$F" T1 2>&1); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'OVER 판정 불가 — git 저장소가 아니다' \
  && ok "Q5.b git 저장소 밖 → 판정 불가 → 3" || nope "Q5.b" "rc=$rc out=$out"

# ── 훅 종단용 헬퍼 (B 절 이후가 쓴다) ────────────────────────────────────────
HOOK="$PLUGIN/hooks/pretool-governance.sh"
TR="$PLUGIN/scripts/tests/governance/fixtures/transcripts/pretool-no-verify.jsonl"   # 러너 실행 기록이 없는 transcript
[ -f "$TR" ] || { echo "FATAL: transcript 픽스처 부재 $TR" >&2; exit 1; }
MSG='git commit -m "fix: a (Task: T1)"'
_hook() {  # <sb> <커밋 명령> → ALLOW | DENY: <사유 전문>
  jq -nc --arg c "$2" --arg t "$TR" '{tool_name:"Bash", tool_input:{command:$c}, transcript_path:$t}' \
    | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>/dev/null \
    | jq -r 'if .hookSpecificOutput.permissionDecision == "deny" then "DENY: " + .hookSpecificOutput.permissionDecisionReason else "ALLOW" end'
}
_open_fid() {  # <sb> — FID 폴더와 진행 기록을 손으로 연다(훅이 활성 FID 를 찾는다)
  mkdir -p "$1/.specops/$F"
  printf '<!-- active-fid: %s -->\n## %s\n- 2026-10-10 10:00 /quick-fix 시작\n' "$F" "$F" > "$1/.specops/session-progress.md"
}
# 손으로 만든 영수증 — 봉인 스크립트를 거치지 않아도 커밋에서 걸리는지 보려고 태스크 문서를 직접 쓴다
_hand_receipt() {  # <sb> <outputs — 쉼표 구분>
  printf '# tasks\n\n## 의존 그래프\n\n```yaml\nreview_mode: end-loaded\ntasks:\n  - id: T1\n    depends_on: []\n    inputs: []\n    outputs: [%s]\n    ac: []\n    test_command: "bash tests/t.sh"\n```\n' \
    "$2" > "$1/.specops/$F/tasks.md"
  ( cd "$1" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/record-task-receipt.sh" "$F" T1 ) >/dev/null 2>&1
}

# ── H1 범위 초과 — 영수증이 유효해도 커밋 차단, 사유가 걸린 기준을 말한다 (AC-2) ──
_h_over() {  # <라벨> <기대 사유 조각> <outputs> <준비를 마친 샌드박스>
  local s="$4" v; _review "$s" PASS; _hand_receipt "$s" "$3"
  [ -f "$s/.specops/$F/receipts/T1.json" ] || { nope "$1" "픽스처 — 영수증이 만들어지지 않았다"; return; }
  v=$(_hook "$s" "$MSG")
  printf '%s' "$v" | grep -q '^DENY' && printf '%s' "$v" | grep -qF "quick 범위 초과 — $2" && printf '%s' "$v" | grep -q '/maintain-lite' \
    && ! printf '%s' "$v" | grep -q '기록된 receipt 가 유효하지 않습니다' \
    && ok "$1" || nope "$1" "$(printf '%s' "$v" | tail -6)"
}
s=$(_mk); _SBS="$_SBS $s"; _open_fid "$s"
( cd "$s" && printf "echo v2\n" > src/a.sh && _n 3 > src/b.sh && _n 3 > src/c.sh && git add src ) >/dev/null 2>&1
_h_over "H1.a ★ 구현 파일 3개 → 차단 · 사유에 기준과 /maintain-lite ('영수증 무효' 라고 말하지 않는다)" '구현 파일 3개 (상한 2개)' 'src/a.sh, src/b.sh, src/c.sh' "$s"
s=$(_mk); _SBS="$_SBS $s"; _open_fid "$s"
( cd "$s" && { echo "echo v2"; _n 29; } > src/a.sh && git add src/a.sh ) >/dev/null 2>&1
_h_over "H1.b 변경 31줄 → 차단" '변경 31줄 (상한 20줄' 'src/a.sh' "$s"
s=$(_mk); _SBS="$_SBS $s"; _open_fid "$s"
( cd "$s" && printf "echo v2\n" > src/a.sh && mkdir -p db && printf "ADD COLUMN x int;\n" > db/001.sql && git add src db ) >/dev/null 2>&1
_h_over "H1.c 고위험 신호(스키마 파일) → 차단" '고위험 신호: schema' 'src/a.sh, db/001.sql' "$s"

# ── H2 리뷰 미충족 — 커밋 차단, 사유는 범위 초과와 다르다 (AC-3) ────────────
sb=$(_mk); _SBS="$_SBS $sb"; _open_fid "$sb"
( cd "$sb" && printf 'echo v2\n' > src/a.sh && git add src/a.sh )
_hand_receipt "$sb" "src/a.sh"; v=$(_hook "$sb" "$MSG")
printf '%s' "$v" | grep -q '^DENY' && printf '%s' "$v" | grep -q 'quick 리뷰 미충족 — 리뷰 보고서가 없다' \
  && ! printf '%s' "$v" | grep -q '범위 초과' \
  && ok "H2.a ★ 리뷰 없이 영수증만 만든 커밋 → 차단, 사유는 리뷰(범위 초과가 아니다)" || nope "H2.a" "$(printf '%s' "$v" | tail -5)"
_review "$sb" FAIL; v=$(_hook "$sb" "$MSG")
printf '%s' "$v" | grep -q '^DENY' && printf '%s' "$v" | grep -q 'quick 리뷰 미충족 — 마지막 리뷰 판정이 통과가 아니다' \
  && ok "H2.b 통과가 아닌 판정 → 차단" || nope "H2.b" "$(printf '%s' "$v" | tail -4)"
touch -t 201901010000 "$sb/.specops/$F/reviews/T1-C-feedback.md"; _review "$sb" PASS; v=$(_hook "$sb" "$MSG")
[ "$v" = "ALLOW" ] && ok "H2.c ★ 같은 영수증에 통과 리뷰가 오면 열린다 (범위 안 + 리뷰 + 영수증 = 통과 · AC-1)" || nope "H2.c" "$(printf '%s' "$v" | tail -4)"
touch -t 202001010000 "$sb/.specops/$F/reviews/T1-C-report.md"; v=$(_hook "$sb" "$MSG")
printf '%s' "$v" | grep -q '^DENY' && printf '%s' "$v" | grep -q 'quick 리뷰 미충족 — 리뷰 뒤에 src/a.sh 가 다시 수정됐다' \
  && ok "H2.d 리뷰가 수정보다 오래됨 → 차단" || nope "H2.d" "$(printf '%s' "$v" | tail -4)"

# ── H3 기존 흐름 불변 (AC-R-1) ──────────────────────────────────────────────
# 명세가 있는 FID(정식 경로) — 범위가 크고 리뷰 보고서가 없어도 영수증만으로 종전처럼 열린다
sb=$(_mk); _SBS="$_SBS $sb"; _open_fid "$sb"; printf '# spec\n' > "$sb/.specops/$F/spec.md"
( cd "$sb" && printf 'echo v2\n' > src/a.sh && _n 30 > src/b.sh && _n 30 > src/c.sh && git add src )
_hand_receipt "$sb" "src/a.sh, src/b.sh, src/c.sh"; v=$(_hook "$sb" "$MSG")
[ "$v" = "ALLOW" ] && ok "H3.a ★ 명세가 있는 FID 는 범위·리뷰 판정을 받지 않는다(정식 영수증 경로 불변)" || nope "H3.a" "$(printf '%s' "$v" | tail -4)"
# 태스크 문서가 없는 FID(자유작업) — quick 문안이 나오지 않는다
sb=$(_mk); _SBS="$_SBS $sb"; _open_fid "$sb"
( cd "$sb" && printf 'echo v2\n' > src/a.sh && _n 30 > src/b.sh && _n 30 > src/c.sh && git add src ); v=$(_hook "$sb" "$MSG")
printf '%s' "$v" | grep -q '^DENY' && ! printf '%s' "$v" | grep -qE 'quick (범위 초과|리뷰 미충족|경로)' \
  && ok "H3.b 태스크 문서가 없는 FID 는 종전 판정 그대로다(quick 문안 없음)" || nope "H3.b" "$(printf '%s' "$v" | head -2)"

# ── H4 원인 매핑 — 영수증 검사기의 종료 코드가 사유 코드로 ──────────────────
c3=$(. "$PLUGIN/hooks/governance-lib.sh" >/dev/null 2>&1; _receipt_cause 3 "$MSG" T1 "$F")
c4=$(. "$PLUGIN/hooks/governance-lib.sh" >/dev/null 2>&1; _receipt_cause 4 "$MSG" T1 "$F")
c1=$(. "$PLUGIN/hooks/governance-lib.sh" >/dev/null 2>&1; _receipt_cause 1 "$MSG" T1 "$F")
[ "$c3" = "quick-over" ] && [ "$c4" = "quick-noreview" ] && [ "$c1" = "open-invalid" ] \
  && ok "H4.a 종료 코드 3 → quick-over · 4 → quick-noreview · 1 → open-invalid(종전)" || nope "H4.a" "c3=$c3 c4=$c4 c1=$c1"
# 판정 불가(스테이징된 변경 없음)는 "범위 초과" 가 아니다 — 문안이 원인을 그대로 말하고 /maintain-lite 로 보내지 않는다
sb=$(_mk); _SBS="$_SBS $sb"; mkdir -p "$sb/.specops/$F"
h=$(cd "$sb" && . "$PLUGIN/hooks/governance-lib.sh" >/dev/null 2>&1; _receipt_hint_extra quick-over "$MSG" "$F")
printf '%s' "$h" | grep -q 'quick 판정 불가 — 스테이징된 변경이 없다' && ! printf '%s' "$h" | grep -qE '범위 초과|/maintain-lite' \
  && ok "H4.b 판정 불가는 범위 초과로 말하지 않는다(원인 그대로 · /maintain-lite 안내 없음)" || nope "H4.b" "$(printf '%s' "$h" | head -3)"

# ── S1 start 의 가드 ────────────────────────────────────────────────────────
QF="$PLUGIN/scripts/quick-fix.sh"
sb=$(mktemp -d); _SBS="$_SBS $sb"; ( cd "$sb" && git init -q ) >/dev/null 2>&1
out=$(cd "$sb" && bash "$QF" start "$F" "x" 2>&1); rc=$?
[ "$rc" = 1 ] && [ ! -e "$sb/.specops" ] && ok "S1.a .specops 가 없는 저장소 → 거부, .specops 를 만들지 않는다(관할 편입 금지)" || nope "S1.a" "rc=$rc out=$out"
sb=$(_mk); _SBS="$_SBS $sb"; mkdir -p "$sb/.specops/$F"; printf '# spec\n' > "$sb/.specops/$F/spec.md"
out=$(cd "$sb" && bash "$QF" seal "$F" "bash tests/t.sh" 2>&1); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '명세(spec.md)가 있다' && ok "S1.b 명세가 있는 FID → 거부(정식 경로의 FID 를 덮어쓰지 않는다)" || nope "S1.b" "rc=$rc out=$out"
sb=$(_mk); _SBS="$_SBS $sb"; ( cd "$sb" && git checkout -q -b main ) >/dev/null 2>&1
( cd "$sb" && bash "$QF" start "$F" "기본 브랜치에서" ) >/dev/null 2>&1
[ "$(cd "$sb" && git symbolic-ref --short HEAD)" = "feat/$F" ] && ok "S1.c 기본 브랜치(main) 위에서 start → 브랜치 feat/<FID> 생성" \
  || nope "S1.c" "branch=$(cd "$sb" && git symbolic-ref --short HEAD)"
out=$(cd "$sb" && bash "$QF" seal "$F" 'bash tests/t.sh "x"' 2>&1); rc=$?
[ "$rc" = 1 ] && ok "S1.d test_command 의 따옴표 → 거부(태스크 문서의 YAML 을 깨뜨린다)" || nope "S1.d" "rc=$rc out=$out"

# ── S2 종단 — start → 수정 → 리뷰 → seal → 커밋 → done (AC-1 · AC-6) ────────
sb=$(_mk); _SBS="$_SBS $sb"
out=$(cd "$sb" && bash "$QF" start "$F" "a.sh 값 수정" 2>&1); rc=$?
[ "$rc" = 0 ] && [ -d "$sb/.specops/$F" ] && grep -q "## $F" "$sb/.specops/session-progress.md" \
  && [ "$(cd "$sb" && git symbolic-ref --short HEAD)" = "work" ] \
  && ok "S2.a start — FID 폴더·진행 기록 생성, 작업 브랜치 위면 브랜치를 바꾸지 않는다" || nope "S2.a" "rc=$rc out=$out"
( cd "$sb" && printf 'echo v2\n' > src/a.sh && git add src/a.sh ); _review "$sb" PASS
out=$(cd "$sb" && bash "$QF" seal "$F" "bash tests/t.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && [ -f "$sb/.specops/$F/tasks.md" ] && [ -f "$sb/.specops/$F/receipts/T1.json" ] \
  && printf '%s' "$out" | grep -q 'QUICK-FIX: SEALED' \
  && ok "S2.b seal — 태스크 문서·영수증 생성(테스트 실제 실행)" || nope "S2.b" "rc=$rc out=$out"
v=$(_hook "$sb" "$MSG")
[ "$v" = "ALLOW" ] && ok "S2.c ★ 봉인 뒤 'Task: T1' 커밋 → 훅 통과" || nope "S2.c" "$(printf '%s' "$v" | head -3)"
n=$(cd "$sb/.specops/$F" && find . -type f | wc -l | tr -d ' ')
docs=$(cd "$sb/.specops/$F" && ls spec.md acceptance-criteria.md plan.md evidence.md intent.md 2>/dev/null | wc -l | tr -d ' ')
[ "$n" -le 3 ] && [ "$docs" = 0 ] && ok "S2.d FID 폴더의 파일 ${n}개(태스크 문서·영수증·리뷰 보고서) — 명세·수용 기준·계획·증거 문서 없음" \
  || nope "S2.d" "files=$n docs=$docs: $(cd "$sb/.specops/$F" && find . -type f | tr '\n' ' ')"
( cd "$sb" && git -c user.name=t -c user.email=t@e.com commit -qm "fix: a (Task: T1)" ) >/dev/null 2>&1
out=$(cd "$sb" && bash "$QF" done "$F" "a.sh 값 v2 로" 2>&1); rc=$?
rec=$(cd "$sb" && SPECOPS_ROOT="$sb/.specops" bash "$PLUGIN/scripts/_internal/reconcile-check.sh" "$F" --hook 2>&1)
[ "$rc" = 0 ] && grep -q '/lifecycle DONE' "$sb/.specops/session-progress.md" \
  && grep -qE "^- [0-9]{2}:[0-9]{2} \[fix\] \($F\) src/a.sh — a.sh 값 v2 로$" "$sb/.specops/freelog.md" && [ -z "$rec" ] \
  && ok "S2.e done — 종결 줄 + 자유작업 로그 1줄, 진행 대조에 DESYNC 없음 (AC-6)" || nope "S2.e" "rc=$rc out=$out rec=$rec"

# 한글 파일명도 봉인 → 커밋이 열린다 (태스크 문서의 outputs 와 훅이 보는 스테이징 목록이 같은 표기여야 한다)
sb=$(_mk); _SBS="$_SBS $sb"; ( cd "$sb" && bash "$QF" start "$F" "한글 파일" ) >/dev/null 2>&1
( cd "$sb" && printf 'echo v2\n' > src/a.sh && printf 'echo k\n' > src/한글.sh && git add src ); _review "$sb" PASS
out=$(cd "$sb" && bash "$QF" seal "$F" "bash tests/t.sh" 2>&1); rc=$?; v=$(_hook "$sb" "$MSG")
[ "$rc" = 0 ] && [ "$v" = "ALLOW" ] && ok "S2.f 한글 파일명 — 봉인 뒤 커밋 통과" || nope "S2.f" "rc=$rc out=$out v=$(printf '%s' "$v" | tail -3)"

# ── S3 봉인 거부 — 범위 초과 · 리뷰 없음 · 테스트 실패 (AC-2 · AC-3 · AC-4) ──
sb=$(_mk); _SBS="$_SBS $sb"; ( cd "$sb" && bash "$QF" start "$F" "큰 수정" ) >/dev/null 2>&1
( cd "$sb" && printf 'echo v2\n' > src/a.sh && _n 3 > src/b.sh && _n 3 > src/c.sh && git add src ); _review "$sb" PASS
out=$(cd "$sb" && bash "$QF" seal "$F" "bash tests/t.sh" 2>&1); rc=$?
[ "$rc" = 3 ] && [ ! -f "$sb/.specops/$F/tasks.md" ] && [ ! -d "$sb/.specops/$F/receipts" ] \
  && printf '%s' "$out" | grep -q '/maintain-lite' \
  && ok "S3.a seal — 범위 초과면 rc 3, 아무것도 쓰지 않고 /maintain-lite 를 안내" || nope "S3.a" "rc=$rc out=$out"
sb=$(_mk); _SBS="$_SBS $sb"; ( cd "$sb" && bash "$QF" start "$F" "리뷰 없이" ) >/dev/null 2>&1
( cd "$sb" && printf 'echo v2\n' > src/a.sh && git add src/a.sh )
out=$(cd "$sb" && bash "$QF" seal "$F" "bash tests/t.sh" 2>&1); rc=$?
[ "$rc" = 4 ] && [ ! -f "$sb/.specops/$F/tasks.md" ] && ok "S3.b seal — 리뷰 없으면 rc 4, 아무것도 쓰지 않는다" || nope "S3.b" "rc=$rc out=$out"
sb=$(_mk); _SBS="$_SBS $sb"; ( cd "$sb" && bash "$QF" start "$F" "테스트 실패" ) >/dev/null 2>&1
( cd "$sb" && printf 'echo v3\n' > src/a.sh && git add src/a.sh ); _review "$sb" PASS      # tests/t.sh 는 v2 를 찾는다 → 실패
out=$(cd "$sb" && bash "$QF" seal "$F" "bash tests/t.sh" 2>&1); rc=$?
v=$(_hook "$sb" "$MSG")
[ "$rc" = 1 ] && [ ! -f "$sb/.specops/$F/receipts/T1.json" ] && printf '%s' "$v" | grep -q '^DENY' \
  && ok "S3.c 테스트 실패 → 봉인 실패(rc 1), 영수증 없음, 커밋 차단 (AC-4)" || nope "S3.c" "rc=$rc out=$out v=$(printf '%s' "$v" | head -1)"

# ── D 진입·계약 — 리뷰어의 quick 입력 · 자연어 추론 금지 (AC-5) ─────────────
CR="$PLUGIN/agents/code-reviewer-ko.md"; META="$PLUGIN/skills/using-specops-ko/SKILL.md"
grep -qF 'quick 경로: yes' "$CR" && grep -qF '`quick 경로: yes` 표시가 있으면 SKIP 하지 않는다' "$CR" \
  && grep -qF 'N/A(quick 경로 — 명세 없음)' "$CR" \
  && ok "D2.a code-reviewer-ko — quick 표시를 받는 컨텍스트로 받고 SKIP 하지 않는다" || nope "D2.a" "계약에 quick 입력이 없다"
grep -qF '경로도 병렬 표시도 없으면 SKIP 반환' "$CR" \
  && ok "D2.b 종전 자격 게이트(경로·병렬 표시 둘 다 없으면 SKIP)는 그대로다" || nope "D2.b" "SKIP 문구가 사라졌다"
grep -qF '`/maintain-lite`·`/quick-fix`를 **추론하지 않는다**' "$META" \
  && ok "D3.a 메타 스킬 — 자연어로 /quick-fix 를 추론하지 않는다(lite 와 같은 줄)" || nope "D3.a" "메타 스킬에 문구 없음"

# ── D1 진입 커맨드 — 슬래시 전용 · 절차 · 상한 표 (AC-5) ────────────────────
CMD="$PLUGIN/commands/quick-fix.md"
[ -f "$CMD" ] && grep -q '^disable-model-invocation: true$' "$CMD" \
  && ok "D1.a /quick-fix 커맨드는 모델 호출 금지(슬래시 전용)" || nope "D1.a" "커맨드 부재 또는 표지 없음"
grep -qF 'quick-fix.sh start' "$CMD" 2>/dev/null && grep -qF 'quick-fix.sh seal' "$CMD" && grep -qF 'quick-fix.sh done' "$CMD" \
  && grep -qF 'Task: T1' "$CMD" && grep -qF 'quick 경로: yes' "$CMD" && grep -qF '/maintain-lite' "$CMD" \
  && ok "D1.b 커맨드 본문 — start·seal·done · Task: T1 · 리뷰어 quick 표시 · 초과 시 /maintain-lite" || nope "D1.b" "본문에 빠진 절차가 있다"
# 상한 수치는 판정기의 상수가 유일한 정의다 — 커맨드 문서의 표가 그 값과 같아야 한다(상수를 바꾸고 문서를 안 고치면 여기서 걸린다)
_mf=$(sed -n 's/^QUICK_MAX_IMPL_FILES=//p' "$QS"); _ml=$(sed -n 's/^QUICK_MAX_LINES=//p' "$QS")
[ -n "$_mf" ] && [ -n "$_ml" ] && grep -qF "| ${_mf}개 |" "$CMD" 2>/dev/null && grep -qF "| ${_ml}줄 |" "$CMD" \
  && ok "D1.d 커맨드 문서의 상한(${_mf}개 · ${_ml}줄) = 판정기 상수" || nope "D1.d" "상수 files=$_mf lines=$_ml 가 커맨드 문서의 표와 다르다"
[ ! -f "$PLUGIN/commands/quick-fix-auto.md" ] && ok "D1.c 무인 변형을 두지 않는다" || nope "D1.c" "quick-fix-auto.md 가 있다"

# ── R 코드 리뷰 반영 (20261010) — 우회 경로 · 해석할 수 없는 경로 · 빠져 있던 단언 ─────
# 왜: 1회차 코드 리뷰가 실측으로 보인 것 — (1) quick FID 도 검증 러너를 통과시키면 영수증 창이 닫혀 범위·리뷰 판정 없이
#   자기보고 면제로 열렸다 (2) `git commit -a`·경로 인자는 스테이징 밖의 변경을 함께 커밋하는데 판정은 스테이징만 본다
#   (3) 따옴표가 든 경로는 git 이 이스케이프해 내서 신선도·내용 신호가 조용히 빠졌다.
# shellcheck source=/dev/null
. "$PLUGIN/scripts/tests/lib/exec-transcript.sh"
FIXT="$PLUGIN/scripts/tests/governance/fixtures/transcripts"
_hook_tr() { local TR="$3"; _hook "$1" "$2"; }   # <sb> <커밋 명령> <transcript> — _hook 이 읽는 TR 만 바꾼다
MSG_A='git commit -a -m "fix: a (Task: T1)"'
MSG_P='git commit -m "fix: a (Task: T1)" -- src/c.sh'

# R1 검증 러너를 통과시켜도 quick 판정은 그대로다
sb=$(_mk); _SBS="$_SBS $sb"; _open_fid "$sb"
( cd "$sb" && { echo 'echo v2'; _n 40; } > src/a.sh && git add src/a.sh ); _hand_receipt "$sb" "src/a.sh"   # 42줄(추가 41 · 삭제 1) · 리뷰 없음 · 영수증 유효
v=$(_hook "$sb" "$MSG")
printf '%s' "$v" | grep -q '^DENY' && printf '%s' "$v" | grep -q 'quick 범위 초과 — 변경 42줄' \
  && ! printf '%s' "$v" | grep -qE '실행 증거|진행 기록 앵커' && printf '%s' "$v" | grep -q '검증 러너.*통과로는 열리지 않습니다' \
  && ok "R1.a quick 거부 문안은 검증 러너 안내(①②)를 붙이지 않는다 — 그 길은 quick FID 를 열지 않는다" || nope "R1.a" "$(printf '%s' "$v" | head -4)"
vp=$(cd "$sb" && bash "$PLUGIN/scripts/_internal/run-verification.sh" "$F" </dev/null 2>&1 | grep -c '^VERIFY: PASS')
v=$(_hook_tr "$sb" "$MSG" "$(_tr_for "$sb" "$FIXT/pretool-with-verify-exec.jsonl")")
[ "$vp" = 1 ] && printf '%s' "$v" | grep -q '^DENY' && printf '%s' "$v" | grep -q 'quick 범위 초과 — 변경 42줄' \
  && ok "R1.b ★ 러너가 VERIFY: PASS 를 낸 뒤(실행 증거 있음)에도 범위 초과 커밋은 막힌다" || nope "R1.b" "vp=$vp $(printf '%s' "$v" | head -3)"

# R2 스테이징된 것만 커밋하는 명령이어야 한다
sb=$(_mk); _SBS="$_SBS $sb"; _open_fid "$sb"
( cd "$sb" && _n 3 > src/c.sh && git add src/c.sh && git -c user.name=t -c user.email=t@e.com commit -qm c \
    && printf 'echo v2\n' > src/a.sh && git add src/a.sh && _n 40 > src/c.sh ) >/dev/null 2>&1   # 스테이징 = a.sh 2줄 · 비스테이징 = c.sh 40줄
_review "$sb" PASS; _hand_receipt "$sb" "src/a.sh"
v=$(_hook "$sb" "$MSG"); [ "$v" = "ALLOW" ] && ok "R2.a 대조 — 스테이징된 것만 커밋하는 명령은 통과" || nope "R2.a" "$(printf '%s' "$v" | tail -4)"
v=$(_hook "$sb" "$MSG_A")
printf '%s' "$v" | grep -q '^DENY' && printf '%s' "$v" | grep -q 'quick 커밋 범위' && ! printf '%s' "$v" | grep -q '범위 초과' \
  && ok "R2.b ★ git commit -a → 차단(스테이징 밖의 변경까지 커밋한다)" || nope "R2.b" "$(printf '%s' "$v" | tail -4)"
v=$(_hook "$sb" "$MSG_P")
printf '%s' "$v" | grep -q '^DENY' && printf '%s' "$v" | grep -q 'quick 커밋 범위' \
  && ok "R2.c ★ git commit -- <경로> → 차단" || nope "R2.c" "$(printf '%s' "$v" | tail -4)"
# 여러 줄 메시지 — 명령 치환(`-m "$(cat <<EOF …)"`)은 스테이징 전용인지 확인할 수 없어 막히고, 문안이 그 형태와 대안을 말한다
MSG_S=$(printf 'git commit -m "$(cat <<%sEOF%s\nfix: a (Task: T1)\nEOF\n)"' "'" "'")
MSG_F=$(printf 'git commit -q -F - <<%sEOF%s\nfix: a\n\nTask: T1\nEOF' "'" "'")
v=$(_hook "$sb" "$MSG_S")
printf '%s' "$v" | grep -q '^DENY' && printf '%s' "$v" | grep -q 'quick 커밋 범위' && printf '%s' "$v" | grep -q '명령 치환' \
  && printf '%s' "$v" | grep -qF 'git commit -F - <<' \
  && ok "R2.e 명령 치환으로 메시지를 넣은 커밋 → 차단, 문안이 그 형태와 대안(-F - heredoc)을 말한다" || nope "R2.e" "$(printf '%s' "$v" | tail -5)"
v=$(_hook "$sb" "$MSG_F"); [ "$v" = "ALLOW" ] \
  && ok "R2.f 대조 — heredoc 으로 메시지를 넣은 커밋(-F -)은 통과" || nope "R2.f" "$(printf '%s' "$v" | tail -4)"
printf '# spec\n' > "$sb/.specops/$F/spec.md"                                  # 명세가 생기면 정식 FID 다
v=$(_hook "$sb" "$MSG_A"); [ "$v" = "ALLOW" ] \
  && ok "R2.d 정식 FID(명세 있음)의 commit -a 는 종전 그대로다(영수증 경로 불변 · AC-R-1)" || nope "R2.d" "$(printf '%s' "$v" | tail -4)"

# R3 원인 매핑 · 사유 조회 실패
c5=$(. "$PLUGIN/hooks/governance-lib.sh" >/dev/null 2>&1; _receipt_cause 5 "$MSG_A" T1 "$F")
[ "$c5" = "quick-unstaged" ] && ok "R3.a 종료 코드 5 → quick-unstaged" || nope "R3.a" "c5=$c5"
h=$(cd "$sb" && . "$PLUGIN/hooks/governance-lib.sh" >/dev/null 2>&1; _QUICK_SCOPE_SH=/nonexistent/quick-scope.sh; _receipt_hint_extra quick-over "$MSG" "$F")
printf '%s' "$h" | grep -q 'quick 범위 초과 — 사유 조회 실패' \
  && ok "R3.b 판정기를 부를 수 없어 사유를 못 얻으면 그렇다고 말한다(빈 사유를 내지 않는다)" || nope "R3.b" "$(printf '%s' "$h" | head -3)"

# R4 판정기 — 빠져 있던 신호 단언 · 테스트 파일 이름 · 해석할 수 없는 경로
s=$(_mk); _SBS="$_SBS $s"; mkdir -p "$s/.specops/$F"
( cd "$s" && printf "curl http://x/api/v1/list\n" > src/a.sh && git add src/a.sh ) >/dev/null 2>&1
_sig "R4.a 변경 줄의 외부 API 경로 → 고위험(public_api)" 'public_api' "$s"
s=$(_mk); _SBS="$_SBS $s"; mkdir -p "$s/.specops/$F"
( cd "$s" && mkdir -p docs && printf "x\n" > docs/api-spec.md && printf "echo v2\n" > src/a.sh && git add docs src/a.sh ) >/dev/null 2>&1
_sig "R4.b 인터페이스 설계 문서(api-spec.md)를 함께 고침 → 고위험(ui_if)" 'ui_if' "$s"
s=$(_mk); _SBS="$_SBS $s"; mkdir -p "$s/.specops/$F"
( cd "$s" && mkdir -p docs && printf "x\n" > docs/data-model.md && printf "echo v2\n" > src/a.sh && git add docs src/a.sh ) >/dev/null 2>&1
_sig "R4.c 테이블 설계 문서(data-model.md)를 함께 고침 → 고위험(ui_if)" 'ui_if' "$s"
sb=$(_mk); _SBS="$_SBS $sb"; mkdir -p "$sb/.specops/$F"
( cd "$sb" && printf 'echo v2\n' > src/a.sh && _n 30 > src/test-helper.sh && git add src ); _review "$sb" PASS
out=$(_scope "$sb"); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'OK 구현 파일 1개 · 2줄' \
  && ok "R4.d test-*.sh 는 폴더와 무관하게 테스트 파일이다(파일 수·줄 수에 넣지 않는다)" || nope "R4.d" "rc=$rc out=$out"
sb=$(_mk); _SBS="$_SBS $sb"; mkdir -p "$sb/.specops/$F"
( cd "$sb" && printf 'echo "ALTER TABLE t ADD c int"\n' > 'src/a"b.sh' && git add src ); _review "$sb" PASS
touch -t 202001010000 "$sb/.specops/$F/reviews/T1-C-report.md"                 # 리뷰가 수정보다 오래됐고 변경 줄에 고위험 신호가 있다
out=$(_scope "$sb"); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'OVER 판정 불가 — 경로를 해석할 수 없다' \
  && ok "R4.e ★ 따옴표가 든 경로 → 판정 불가(막는다) — 신선도·내용 신호를 건너뛰고 통과하지 않는다" || nope "R4.e" "rc=$rc out=$out"

# 플러그인 런타임 신호는 플러그인 저장소에서만이다 — 앱 저장소의 hooks/ 는 그 프로젝트의 코드일 뿐이다(판정기 변이 측정에서 생존)
sb=$(_mk); _SBS="$_SBS $sb"; mkdir -p "$sb/.specops/$F"
( cd "$sb" && mkdir -p hooks && printf 'echo h\n' > hooks/pre.sh && git add hooks ); _review "$sb" PASS
out=$(_scope "$sb"); rc=$?
[ "$rc" = 0 ] && ok "R4.f 플러그인이 아닌 저장소의 hooks/ 변경은 plugin_runtime 신호가 아니다" || nope "R4.f" "rc=$rc out=$out"
sb=$(_mk); _SBS="$_SBS $sb"; mkdir -p "$sb/.specops/$F"
( cd "$sb" && mkdir -p .claude-plugin && printf '{}\n' > .claude-plugin/plugin.json && git add .claude-plugin \
    && git -c user.name=t -c user.email=t@e.com commit -qm p && printf 'echo v2\n' > src/a.sh && git add src/a.sh ) >/dev/null 2>&1; _review "$sb" PASS
out=$(_scope "$sb"); rc=$?
[ "$rc" = 0 ] && ok "R4.g 플러그인 저장소라도 런타임 경로 밖의 변경은 신호가 아니다" || nope "R4.g" "rc=$rc out=$out"
# 리뷰 신선도는 스테이징된 파일만 본다 — 저장소 최상위 폴더의 수정 시각(스테이징 밖의 파일 생성)은 무관하다(같은 측정에서 생존)
sb=$(_mk); _SBS="$_SBS $sb"; mkdir -p "$sb/.specops/$F"
( cd "$sb" && printf 'echo v2\n' > src/a.sh && git add src/a.sh ); _review "$sb" PASS
touch -t 202001010000 "$sb/src/a.sh"; touch -t 202101010000 "$sb/.specops/$F/reviews/T1-C-report.md"; : > "$sb/NOTE.tmp"
out=$(_scope "$sb"); rc=$?
[ "$rc" = 0 ] && ok "R4.h 스테이징 밖의 변화(최상위 폴더의 수정 시각)는 리뷰 신선도와 무관하다" || nope "R4.h" "rc=$rc out=$out"

# R5 봉인 스크립트의 입력 가드 — 가드만 재도록 다른 가드에 먼저 걸리지 않는 입력으로
sb=$(_mk); _SBS="$_SBS $sb"; mkdir -p "$sb/.specops/$F"
out=$(cd "$sb" && bash "$QF" seal "$F" 'bash tests/t.sh "x"' 2>&1); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '따옴표' && ok "R5.a test_command 의 따옴표 → 그 사유로 거부" || nope "R5.a" "rc=$rc out=$out"
out=$(cd "$sb" && bash "$QF" seal "$F" "$(printf 'bash tests/t.sh\necho x')" 2>&1); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '한 줄' && ok "R5.b 여러 줄 명령 → 거부" || nope "R5.b" "rc=$rc out=$out"
sb=$(_mk); _SBS="$_SBS $sb"; mkdir -p "$sb/real"; ln -s "$sb/real" "$sb/.specops/$F"
out=$(cd "$sb" && bash "$QF" start "$F" "x" 2>&1); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'symlink' && ok "R5.c FID 폴더가 symlink → 거부" || nope "R5.c" "rc=$rc out=$out"

# 샌드박스 정리 — 경로를 하나씩 따옴표로 넘긴다(_SBS 는 mktemp 경로를 공백으로 이은 목록이다)
for _d in $_SBS; do rm -rf "$_d"; done
echo ""
finish
