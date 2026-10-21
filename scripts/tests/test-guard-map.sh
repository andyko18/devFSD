#!/usr/bin/env bash
# run-all: serial — T7.a·T9.b 가 실 repo 실행 시간 상한(20초·10초)을 잰다(CPU 경합 시 초과 가능 — 실측 0.66초)
# test-guard-map.sh — guard-map.sh(가드 생존 맵) 계약 스위트 (FID 20261003-guard-survival-map · AC-1~AC-8)
# fixture repo 는 mktemp 안에만 만든다 — 실제 repo 는 읽기만 하고(T7 스모크) 어떤 파일도 쓰지 않는다.
# ★ 이 파일은 scripts/tests/ 아래라 guard-map 이 "테스트 언급(T 참조)" 으로 읽는다. 그래서 실제 가드명·규칙 id·구조 라벨은
#   쓰지 않는다 — fixture 전용 이름(alpha·R-X1·lbl_a …)만 쓴다. (실 repo 의 T 칸이 이 파일 때문에 부풀지 않게.)
# 시각·세션 독립: 이 스위트는 시각·CLAUDE_CODE_SESSION_ID·실 ~/.claude 를 읽지 않는다(T6 이 date shim·세션 변수로 실증).
#   SPECOPS_GM_REAL_ROOT 는 T7 스모크 대상 root 를 바꾼다(변이 하네스가 사본 트리에서 돌릴 때 쓴다 — 기본은 이 스위트가 속한 repo).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
GM="$PLUGIN/scripts/guard-map.sh"
REAL_ROOT="${SPECOPS_GM_REAL_ROOT:-$PLUGIN}"
BASH_BIN=$(command -v bash)
SB=$(mktemp -d)
NEWH_LINE0='증거 약함 (적용 증거 2종 이상 가드(check) 중 판정 가능한 증거에서 있음 1종 이하 — 미측정 칸은 판정에서 제외): 0개
  (없음)'
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/tmp" "$SB/home"

ck() { if [ "$2" = "$3" ]; then echo "PASS $1"; PASS=$((PASS+1)); else echo "FAIL $1 — exp '${3//$'\n'/⏎}' got '${2//$'\n'/⏎}'"; FAIL=$((FAIL+1)); fi; }  # 줄바꿈은 ⏎ 로 한 줄에 — run-all --quiet 는 FAIL 줄만 보여 준다
ckn() { if [ "$2" != "$3" ]; then echo "PASS $1"; PASS=$((PASS+1)); else echo "FAIL $1 — 같으면 안 된다: '$2'"; FAIL=$((FAIL+1)); fi; }

# ── fixture 헬퍼 ───────────────────────────────────────────────────────────
mkfx() {  # <name> — 빈 골격(rules·conf·원장 모두 빈 파일)
  local d="$SB/$1"
  mkdir -p "$d/hooks" "$d/scripts/_internal" "$d/scripts/tests" "$d/commands"
  : > "$d/hooks/rules.jsonl"; : > "$d/scripts/tests/mutation-targets.conf"; : > "$d/scripts/_internal/propagation-matrix.jsonl"
  printf '#!/usr/bin/env bash\nemit() { RESULTS+=("$1|$2|${3:-}"); }\n' > "$d/scripts/_internal/validate-structure.sh"
}
rule() { printf '%s\n' "$2" >> "$SB/$1/hooks/rules.jsonl"; }                           # <fx> <json 한 줄>
chk() { local fx="$1" n; shift; for n in "$@"; do printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/$fx/scripts/_internal/check-$n.sh"; done; }
lbl() { local fx="$1" l; shift; for l in "$@"; do printf '[ -z "$x" ] && emit %s OK || emit %s FAIL "m"\n' "$l" "$l" >> "$SB/$fx/scripts/_internal/validate-structure.sh"; done; }
file() { mkdir -p "$(dirname "$SB/$1/$2")"; cat > "$SB/$1/$2"; }                         # <fx> <relpath> (본문 stdin)
conf() { printf '%s\n' "$2" >> "$SB/$1/scripts/tests/mutation-targets.conf"; }          # <fx> <line>
led() { cat >> "$SB/$1/scripts/_internal/propagation-matrix.jsonl"; }                  # <fx> (JSON 줄 stdin)
cpfx() { rm -rf "${SB:?}/$2"; cp -R "$SB/$1" "$SB/$2"; }

# 실행: gm <fx> [옵션...] → OUT·ERR·RC. env -i + 최소 환경(GMX 로 변수 추가, GMPATH 로 PATH 교체).
gm() {
  local fx="$1"; shift
  # shellcheck disable=SC2086
  OUT=$(env -i ${GMX:-} PATH="${GMPATH:-$PATH}" HOME="$SB/home" TMPDIR="$SB/tmp" "$BASH_BIN" "$GM" --repo "$SB/$fx" "$@" 2>"$SB/err"); RC=$?
  ERR=$(cat "$SB/err")
}
# 표의 칸: cell <종류> <가드> <T|M|P>  (열은 공백 2칸+ 로 구분 — 값 안의 공백은 1칸)
cell() { printf '%s\n' "$OUT" | awk -F'  +' -v k="$1" -v n="$2" -v c="$3" '$1 == k && $2 == n { i = (c == "T") ? 3 : (c == "M") ? 4 : 5; print $i; exit }'; }
rows() { printf '%s\n' "$OUT" | awk -F'  +' -v k="$1" -v n="$2" '$1 == k && $2 == n { c++ } END { print c + 0 }'; }
head1() { printf '%s\n' "$OUT" | grep -m1 '^인벤토리:'; }
sumline() { printf '%s\n' "$OUT" | grep -m1 "^- $1 "; }                                  # 요약의 종류별 줄
weakblock() { printf '%s\n' "$OUT" | awk '/^증거 약함/ { on = 1; print; next } /^한계/ { on = 0 } on && NF { print }'; }
hasline() { printf '%s\n' "$OUT" | grep -cxF -- "$1"; }

# ═════ T1 (AC-1): 인벤토리 3종을 repo 파일에서 기계 추출한다 ═════
mkfx f1
rule f1 '{"id": "R-X1", "enabled": true, "note": "a"}'
rule f1 '{"id": "R-X2", "enabled": true}'
rule f1 '{"id": "R-X3", "enabled": false}'
printf '\n   \n' >> "$SB/f1/hooks/rules.jsonl"
chk f1 delta beta alpha gamma
printf '# emit nope_comment OK\nreemit nope_two OK\necho "emit nope_three plain text"\n' >> "$SB/f1/scripts/_internal/validate-structure.sh"
lbl f1 lbl_a lbl_b lbl_c lbl_d lbl_e
lbl f1 lbl_a
gm f1
ck "T1.a rc=0 · 머리에 인벤토리 숫자(rules 3 · check 4 · structure 5) — emit 라벨은 중복·주석·함수 정의를 세지 않는다" "$RC|$(head1)" "0|인벤토리: rules 3 · check 4 · structure 5"
ck "T1.b 가드마다 표에 정확히 1행: rule 3 · check 4 · structure 5(emit 중복 라벨 1행)" "$(rows rule R-X1)$(rows rule R-X2)$(rows rule R-X3)|$(rows check alpha)$(rows check beta)$(rows check gamma)$(rows check delta)|$(rows structure lbl_a)$(rows structure lbl_b)$(rows structure lbl_c)$(rows structure lbl_d)$(rows structure lbl_e)" "111|1111|11111"
ck "T1.c 비활성 규칙(enabled:false)은 T 칸이 비활성 이고 M·P 는 - · 주석 안의 emit 라벨은 행이 없다" "$(cell rule R-X3 T)|$(cell rule R-X3 M)|$(cell rule R-X3 P)|$(rows structure nope_comment)$(rows structure nope_two)$(rows structure nope_three)" "비활성|-|-|000"
ck "T1.d 표 행 순서: check 는 가드명 정렬(alpha beta delta gamma) — 파일 생성 순서(delta beta alpha gamma)와 무관" "$(printf '%s\n' "$OUT" | awk -F'  +' '$1 == "check" { printf "%s,", $2 }')" "alpha,beta,delta,gamma,"
cpfx f1 f1x
chk f1x epsilon; rm "$SB/f1x/scripts/_internal/check-beta.sh"; rule f1x '{"id": "R-X4"}'; lbl f1x lbl_f
gm f1x
ck "T1.e 가드를 추가·제거하면 숫자가 따라 바뀐다(check +1 −1 · rule +1 · structure +1) — 하드코딩 아님" "$(head1)" "인벤토리: rules 4 · check 4 · structure 6"
ck "T1.f enabled 키가 없는 규칙은 활성으로 읽는다(R-X4 T 칸이 비활성 이 아니다)" "$(cell rule R-X4 T)" "없음"

# ═════ T2 (AC-2): 증거 조인이 정확하다 ═════
mkfx f2
rule f2 '{"id": "R-X1", "enabled": true}'
rule f2 '{"id": "R-X2", "enabled": true}'
lbl f2 lbl_a lbl_b
chk f2 named subdir refonly mutreg incmd commented byname byvar selfonly bare genvar crossfile nonguardvar testedge docedge hostA guestB ac ac-format
chk f2 plaindot expvar locvar nosh helperonly readmeonly trail lead nosuffix selfmention dual dotpath docsedge jsonedge bothnv twovars guestV hookonly hookguard dotconf spaceconf txtonly
printf '#!/usr/bin/env bash\n# usage: check-selfmention.sh\n' > "$SB/f2/scripts/_internal/check-selfmention.sh"
file f2 scripts/tests/test-named.sh <<'EOF'
# no mentions here
EOF
file f2 scripts/tests/sub/test-subdir.sh <<'EOF'
# nested named test
EOF
file f2 scripts/tests/test-other.sh <<'EOF'
bash "$P/scripts/_internal/check-refonly.sh"
x=check-ac-format.sh
echo R-X10 R-X2: xlbl_b lbl_b2 lbl_a
see check-trail.sh. and bash --check-lead.sh then check-nosuffix
EOF
file f2 scripts/tests/lib-helper.sh <<'EOF'
# helper (test-*.sh 가 아님): check-helperonly.sh
EOF
file f2 scripts/README.md <<'EOF'
docs mention check-readmeonly.sh
EOF
file f2 scripts/notes.txt <<'EOF'
check-txtonly.sh (txt 는 호출처 후보가 아니다)
EOF
file f2 .githooks/pre-commit <<'EOF'
bash scripts/_internal/check-hookonly.sh
bash scripts/_internal/check-hookguard.sh
EOF
conf f2 '# scripts/_internal/check-commented.sh|bash scripts/tests/test-commented.sh'
conf f2 'scripts/_internal/check-mutreg.sh|bash scripts/tests/test-mutreg.sh >/dev/null 2>&1'
conf f2 'scripts/dag/parse.sh|bash scripts/tests/test-x.sh --target scripts/_internal/check-incmd.sh'
conf f2 './scripts/_internal/check-dotconf.sh|bash scripts/tests/test-d.sh'
conf f2 '  scripts/_internal/check-spaceconf.sh  |bash scripts/tests/test-s.sh'
file f2 scripts/run-it.sh <<'EOF'
bash scripts/_internal/check-byname.sh "$1"
bash scripts/_internal/check-dual.sh
EOF
file f2 scripts/run-dot.sh <<'EOF'
bash scripts/_internal/check-dotpath.sh
EOF
file f2 scripts/nv.sh <<'EOF'
NV_SH="$P/scripts/_internal/check-bothnv.sh"
bash "$NV_SH"
EOF
file f2 scripts/exp.sh <<'EOF'
export EXP_SH="$P/scripts/_internal/check-expvar.sh"
f() {
  local LOC_SH="$P/scripts/_internal/check-locvar.sh"
}
NOSH_SH="check-nosh"
EOF
file f2 scripts/tv1.sh <<'EOF'
ZV_SH="$P/scripts/_internal/check-twovars.sh"
EOF
file f2 scripts/tv2.sh <<'EOF'
AV_SH="$P/scripts/_internal/check-twovars.sh"
EOF
file f2 scripts/run-v.sh <<'EOF'
BYVAR_SH="$PLUGIN/scripts/_internal/check-byvar.sh"
bash "$BYVAR_SH"
EOF
file f2 scripts/uses.sh <<'EOF'
# callers: check-selfonly.sh check-bare.sh check-incmd.sh check-commented.sh check-testedge.sh check-docedge.sh check-docsedge.sh check-jsonedge.sh
EOF
file f2 scripts/run-g.sh <<'EOF'
CHK="$PLUGIN/scripts/_internal/check-genvar.sh"
bash "$CHK"
EOF
file f2 scripts/a.sh <<'EOF'
X_SH="$P/scripts/_internal/check-crossfile.sh"
EOF
file f2 scripts/b.sh <<'EOF'
bash "$X_SH"
EOF
file f2 scripts/n.sh <<'EOF'
# check-nonguardvar.sh
N_SH="$P/scripts/other.sh"
bash "$N_SH"
EOF
file f2 scripts/ac.sh <<'EOF'
bash scripts/_internal/check-ac-format.sh
EOF
printf 'GUESTB_SH="$H/check-guestB.sh"\nGUESTV_SH="$H/check-guestV.sh"\nHOSTA_SH="$H/check-hostA.sh"\nbash "$GUESTB_SH"\n' > "$SB/f2/scripts/_internal/check-hostA.sh"
led f2 <<'EOF'
{"id":"t-byname","edges":[{"path":"scripts/run-it.sh","must_match":"check-byname\\.sh"}]}
{"id":"t-byvar","edges":[{"path":"scripts/run-v.sh","must_match":"bash \"\\$BYVAR_SH\""}]}
{"id":"t-self","edges":[{"path":"scripts/_internal/check-selfonly.sh","must_match":"exit"}]}
{"id":"t-gen","edges":[{"path":"scripts/run-g.sh","must_match":"bash \"\\$CHK\""}]}
{"id":"t-cross","edges":[{"path":"scripts/b.sh","must_match":"bash \"\\$X_SH\""}]}
{"id":"t-nonguard","edges":[{"path":"scripts/n.sh","must_match":"\\$N_SH"}]}
{"id":"t-testedge","edges":[{"path":"scripts/tests/test-named.sh","must_match":"check-testedge"}]}
{"id":"t-doc","edges":[{"path":"scripts/README.md","must_match":"check-docedge\\.sh"}]}
{"id":"t-host","edges":[{"path":"scripts/_internal/check-hostA.sh","must_match":"check-guestB\\.sh"}]}
{"id":"t-ac","edges":[{"path":"scripts/ac.sh","must_match":"check-ac-format\\.sh"}]}
{"id":"t-hostv","edges":[{"path":"scripts/_internal/check-hostA.sh","must_match":"\\$GUESTV_SH"},{"path":"scripts/_internal/check-hostA.sh","must_match":"check-hostA\\.sh"},{"path":"scripts/_internal/check-hostA.sh","must_match":"\\$HOSTA_SH"}]}
{"id":"t-dual","edges":[{"path":"scripts/_internal/check-dual.sh","must_match":"exit"},{"path":"scripts/run-it.sh","must_match":"check-dual\\.sh"}]}
{"id":"t-dot","edges":[{"path":"./scripts/run-dot.sh","must_match":"check-dotpath\\.sh"}]}
{"id":"t-docs","edges":[{"path":"docs/guide.md","must_match":"check-docsedge\\.sh"},{"path":"scripts/data.jsonl","must_match":"check-jsonedge\\.sh"}]}
{"id":"t-nv","edges":[{"path":"scripts/nv.sh","must_match":"\\$NV_SH"},{"path":"scripts/nv.sh","must_match":"check-bothnv\\.sh"}]}
{"id":"t-tv2","edges":[{"path":"scripts/tv2.sh","must_match":"\\$AV_SH"}]}
{"id":"t-tv1","edges":[{"path":"scripts/tv1.sh","must_match":"\\$ZV_SH"}]}
{"id":"t-plain","edges":[{"path":"scripts/run-it.sh","must_match":"check-plaindot.sh"}]}
{"id":"t-hook","edges":[{"path":".githooks/pre-commit","must_match":"check-hookguard\\.sh"}]}
{"id":"t-exp","edges":[{"path":"scripts/exp.sh","must_match":"\\$EXP_SH"},{"path":"scripts/exp.sh","must_match":"\\$LOC_SH"},{"path":"scripts/exp.sh","must_match":"\\$NOSH_SH"}]}
EOF
gm f2
ck "T2.pre rc=0 · 인벤토리 rules 2 · check 41 · structure 2" "$RC|$(head1)" "0|인벤토리: rules 2 · check 41 · structure 2"
c3() { echo "$(cell check "$1" T)|$(cell check "$1" M)|$(cell check "$1" P)"; }
ck "T2.a (a) test-<이름>.sh 명명 일치 → T 있음(명명), M·P 는 증거 없음 형상(P 는 호출처 코드 없음 → 미측정)" "$(c3 named)" "있음(명명)|없음|미측정(호출처 코드 없음)"
ck "T2.b 하위 디렉터리의 test-<이름>.sh 도 명명 일치" "$(cell check subdir T)" "있음(명명)"
ck "T2.c (b) 다른 테스트가 스크립트 이름만 언급 → T 있음(참조) · 테스트 파일은 호출처가 아니다(P 미측정) · 접미 마침표·--접두·.sh 없는 이름도 언급" "$(cell check refonly T)|$(cell check refonly P)|$(cell check trail T)|$(cell check lead T)|$(cell check nosuffix T)" "있음(참조)|미측정(호출처 코드 없음)|있음(참조)|있음(참조)|있음(참조)"
ck "T2.d (c) mutation-targets.conf 대상 열에 있음 → M 있음 · 주석 줄의 경로와 명령 열 안의 경로는 대상이 아니다(없음)" "$(cell check mutreg M)|$(cell check commented M)|$(cell check incmd M)" "있음(conf)|없음|없음"
ck "T2.e (d) 원장 호출처 edge 가 가드명을 담음 → P 있음(이름)" "$(cell check byname P)" "있음(이름)"
ck "T2.f (e) 원장 호출처 edge 가 *_SH 변수명을 담고 그 호출처에서 가드 경로를 할당 → P 있음(변수 BYVAR_SH)" "$(cell check byvar P)" "있음(변수 BYVAR_SH)"
ck "T2.g (f) 가드 스크립트 자기 자신만 잠그는 edge → 자기잠금(있음으로 세지 않는다)" "$(cell check selfonly P)" "자기잠금"
ck "T2.h (g) 증거 없음 형상: 호출처는 있으나 테스트·conf·edge 없음 → 없음·없음·없음" "$(c3 bare)" "없음|없음|없음"
ck "T2.i 음성: 일반 변수(CHK) 호출·다른 파일에서 할당한 *_SH·가드 경로가 아닌 값의 *_SH → P 없음(호출처는 있다)" "$(cell check genvar P)|$(cell check crossfile P)|$(cell check nonguardvar P)" "없음|없음|없음"
ck "T2.j 음성: 테스트 파일·README 를 가리키는 edge 는 호출처 배선이 아니다 → P 없음" "$(cell check testedge P)|$(cell check docedge P)" "없음|없음"
ck "T2.k 가드 스크립트 A 를 가리키는 edge 가 가드 B 를 가리키면 B 는 있음(이름), A 는 자기잠금(B 의 P 를 자기잠금 분기가 삼키지 않는다)" "$(cell check guestB P)|$(cell check hostA P)" "있음(이름)|자기잠금"
ck "T2.l 이름 경계: 가드 ac-format 의 언급이 가드 ac 로 새지 않는다(ac: T 없음 · P 미측정, ac-format: T 참조 · P 이름)" "$(cell check ac T)|$(cell check ac P)|$(cell check ac-format T)|$(cell check ac-format P)" "없음|미측정(호출처 코드 없음)|있음(참조)|있음(이름)"
ck "T2.m rule T: id 경계(R-X10 은 R-X1 이 아니다 → 없음) · 언급(R-X2:) → 있음(참조)" "$(cell rule R-X1 T)|$(cell rule R-X2 T)" "없음|있음(참조)"
ck "T2.n structure T: 라벨 언급 → 있음(참조) · 접두·접미가 붙은 단어(xlbl_b·lbl_b2)는 언급이 아니다 → 없음" "$(cell structure lbl_a T)|$(cell structure lbl_b T)" "있음(참조)|없음"
ck "T2.o rule·structure 행의 M·P 는 해당 없음(-)" "$(cell rule R-X1 M)$(cell rule R-X1 P)$(cell structure lbl_a M)$(cell structure lbl_a P)" "----"

ck "T2.q 테스트 디렉터리의 test-*.sh 가 아닌 파일(lib-helper.sh)은 테스트가 아니다 → T 없음 · README·.txt 는 호출처가 아니다 → P 미측정" "$(cell check helperonly T)|$(cell check readmeonly P)|$(cell check txtonly P)" "없음|미측정(호출처 코드 없음)|미측정(호출처 코드 없음)"
ck "T2.r 가드 스크립트가 자기 이름을 적은 것은 호출처가 아니다(selfmention P 미측정) · .githooks 호출처: edge 있으면 있음(이름), 없으면 없음" "$(cell check selfmention P)|$(cell check hookguard P)|$(cell check hookonly P)" "미측정(호출처 코드 없음)|있음(이름)|없음"
ck "T2.s 자기 edge 와 호출처 edge 가 둘 다 있으면 있음이 이긴다(dual) · edge path 의 ./ 접두는 정규화(dotpath) · docs/·.jsonl edge 는 호출처 배선이 아니다" "$(cell check dual P)|$(cell check dotpath P)|$(cell check docsedge P)|$(cell check jsonedge P)" "있음(이름)|있음(이름)|없음|없음"
ck "T2.t 근거 선택은 결정적: 이름 edge 가 변수 edge 보다 먼저(bothnv) · 같은 순위면 경로 사전순 최소(twovars: 원장 순서와 무관하게 tv1.sh 의 ZV_SH) · A 의 변수 edge 가 B 를 가리키면 B 는 변수 근거(guestV) · A 자신의 이름 edge 는 A 를 있음으로 만들지 않는다" "$(cell check bothnv P)|$(cell check twovars P)|$(cell check guestV P)|$(cell check hostA P)" "있음(이름)|있음(변수 ZV_SH)|있음(변수 GUESTV_SH)|자기잠금"
ck "T2.u0 must_match 가 이스케이프 없는 평문(check-X.sh — 점이 정규식 메타문자 그대로)이어도 이름으로 읽는다" "$(cell check plaindot P)" "있음(이름)"
ck "T2.u1 export·local 접두가 붙은 *_SH 할당도 푼다 · 값에 .sh 경로가 없는 *_SH(NOSH_SH=check-nosh)는 풀지 않는다 → 없음(호출처는 있다)" "$(cell check expvar P)|$(cell check locvar P)|$(cell check nosh P)" "있음(변수 EXP_SH)|있음(변수 LOC_SH)|없음"
ck "T2.u conf 대상 경로 정리: ./ 접두와 앞뒤 공백을 떼고 비교한다" "$(cell check dotconf M)|$(cell check spaceconf M)" "있음(conf)|있음(conf)"
ck "T2.v 요약(f2): P 칸 합이 일관하고 자기잠금은 없음에 포함해 따로 보인다" "$(sumline check | grep -o '| P 있음 [0-9]* 없음 [0-9]* 미측정 [0-9]* - [0-9]*')|$(sumline check | grep -o '자기잠금 [0-9]*(없음에 포함)')" "| P 있음 13 없음 14 미측정 14 - 0|자기잠금 2(없음에 포함)"

# 호출처 후보 디렉터리 전수(hooks·scripts·.githooks·skills·commands·agents·templates · 확장자 sh·md·json)
mkfx dirs
chk dirs hooksonly skillonly agentonly tmplonly cmdonly jsononly scriptsonly jsonedge2
file dirs hooks/h.sh <<'EOF'
bash scripts/_internal/check-hooksonly.sh
EOF
file dirs skills/s/SKILL.md <<'EOF'
run check-skillonly.sh
EOF
file dirs agents/a.md <<'EOF'
run check-agentonly.sh
EOF
file dirs templates/t.md <<'EOF'
run check-tmplonly.sh
EOF
file dirs commands/c.md <<'EOF'
run check-cmdonly.sh
EOF
file dirs hooks/hooks.json <<'EOF'
{"cmd": "bash scripts/_internal/check-jsononly.sh"}
EOF
file dirs scripts/other.sh <<'EOF'
bash scripts/_internal/check-scriptsonly.sh
EOF
file dirs hooks/more.json <<'EOF'
{"cmd": "bash scripts/_internal/check-jsonedge2.sh"}
EOF
led dirs <<'EOF'
{"id":"d","edges":[{"path":"hooks/more.json","must_match":"check-jsonedge2\\.sh"}]}
EOF
gm dirs
ck "T2.w 호출처 후보 디렉터리 전수(hooks·skills·agents·templates·commands·scripts · 확장자 sh·md·json): 어디에 있든 호출처가 있으면 edge 없을 때 없음(미측정 아님) · .json 호출처의 edge 는 호출 배선이다" "$(for g in hooksonly skillonly agentonly tmplonly cmdonly jsononly scriptsonly; do cell check $g P; done | grep -cx '없음')|$(cell check jsonedge2 P)" "7|있음(이름)"

# 골든: 작은 fixture 의 전체 출력(정렬·한글 표시 폭 정렬·요약·약함·푸터) — gawk·mawk·BSD awk 가 모두 같아야 한다(T6.c)
mkfx g1
rule g1 '{"id": "R-X1", "enabled": true}'
rule g1 '{"id": "R-X2", "enabled": false}'
chk g1 alpha beta-longer-name
lbl g1 lbl_a
file g1 scripts/tests/test-alpha.sh <<'EOF'
echo R-X1
EOF
conf g1 'scripts/_internal/check-alpha.sh|bash scripts/tests/test-alpha.sh'
file g1 scripts/run.sh <<'EOF'
bash scripts/_internal/check-alpha.sh
bash scripts/_internal/check-beta-longer-name.sh
EOF
led g1 <<'EOF'
{"id":"g","edges":[{"path":"scripts/run.sh","must_match":"check-alpha\\.sh"}]}
EOF
GOLDEN_G1='인벤토리: rules 2 · check 2 · structure 1
범례: T=테스트 M=변이 대상 등록 P=propagation 호출 배선 · 값 = 있음(근거) / 없음 / 미측정(사유) / - 해당 없음

종류       가드              T           M           P
rule       R-X1              있음(참조)  -           -
rule       R-X2              비활성      -           -
check      alpha             있음(명명)  있음(conf)  있음(이름)
check      beta-longer-name  없음        없음        없음
structure  lbl_a             없음        -           -

요약
- rule      2개 | T 있음 1 없음 0 미측정 0 - 1 | 비활성 1(-에 포함) | 판정 제외(적용 증거 1종)
- check     2개 | T 있음 1 없음 1 미측정 0 - 0 | M 있음 1 없음 1 미측정 0 - 0 | P 있음 1 없음 1 미측정 0 - 0
- structure 1개 | T 있음 0 없음 1 미측정 0 - 0 | 판정 제외(적용 증거 1종)
- 가드 5개 중 증거 2종 이상 1개 · 증거 약함 1개

증거 약함 (적용 증거 2종 이상 가드(check) 중 판정 가능한 증거에서 있음 1종 이하 — 미측정 칸은 판정에서 제외): 1개
  check beta-longer-name — 있음 0/3 (-) 미측정 0

한계
 ① 명명 규약 밖 게이트(release-ready.sh·reconcile-check.sh·batch-state.sh --gate 등)와 훅 deny 분기는 인벤토리에 없다.
 ② 테스트 `참조` 는 가드를 단언한다는 뜻이 아니다 — 증거 있음 ≠ 가드 작동.
 ③ 변이 점수는 직접 재계산하지 않는다 — M 은 mutation-targets.conf 등록 여부만 본다.
 ④ propagation edge 는 must_match 를 단어 단위로만 읽고 문자열 존재만 본다 — 교대(|)·glob·부정 정규식은 오탐·미탐이 날 수 있다.'
gm g1
ck "T2.p 골든: 전체 출력(표 정렬 — 한글 칸 폭·요약·약함·푸터)이 바이트 단위로 일치한다" "$OUT" "$GOLDEN_G1"

# ═════ T3 (AC-3): 측정하지 못한 칸은 미측정(사유) — 없음 으로 위장하지 않는다 ═════
mkfx b3
rule b3 '{"id": "R-X1", "enabled": true}'
chk b3 alpha beta gamma
lbl b3 lbl_a
file b3 scripts/tests/test-alpha.sh <<'EOF'
echo placeholder
EOF
conf b3 'scripts/_internal/check-alpha.sh|bash scripts/tests/test-alpha.sh'
file b3 scripts/run.sh <<'EOF'
bash scripts/_internal/check-alpha.sh
bash scripts/_internal/check-beta.sh
EOF
led b3 <<'EOF'
{"id":"b","edges":[{"path":"scripts/run.sh","must_match":"check-alpha\\.sh"}]}
{"id":"badword","edges":[{"path":"scripts/run.sh","must_match":"BAD"}]}
EOF
col() { printf '%s,%s,%s' "$(cell check alpha "$1")" "$(cell check beta "$1")" "$(cell check gamma "$1")"; }
nozero() { printf '%s\n' "$OUT" | awk -F'  +' -v c="$1" '$1 == "check" { i = (c == "T") ? 3 : (c == "M") ? 4 : 5; if ($i == "없음") n++ } END { print n + 0 }'; }
gm b3
ck "T3.0 대조: 입력이 다 있는 b3 — P 는 있음(이름)·없음(호출처 있음)·미측정(호출처 없음)" "$RC|$(col P)" "0|있음(이름),없음,미측정(호출처 코드 없음)"
cpfx b3 b3a; rm "$SB/b3a/scripts/_internal/propagation-matrix.jsonl"
gm b3a
ck "T3.a (a) 원장 부재 → P 칸 전부 미측정(원장 부재) · 없음 0건 · rc 0 · 입력 안내 줄" "$RC|$(col P)|$(nozero P)|$(printf '%s\n' "$OUT" | grep -c '^미측정 입력:.*propagation-matrix.jsonl')" "0|미측정(원장 부재),미측정(원장 부재),미측정(원장 부재)|0|1"
ck "T3.a2 P 미측정은 약함 판정에서 제외: alpha(T·M 있음)는 약하지 않고 gamma(T·M 없음 · P 미측정)는 있음 0/2 · 미측정 1" "$(weakblock | grep -c ' check alpha ')|$(weakblock | grep -F ' check gamma ')" "0|  check gamma — 있음 0/2 (-) 미측정 1"
ck "T3.a3 요약의 P 줄: 있음 0 없음 0 미측정 3" "$(sumline check | grep -o '| P 있음 [0-9]* 없음 [0-9]* 미측정 [0-9]* - [0-9]*')" "| P 있음 0 없음 0 미측정 3 - 0"
cpfx b3 b3b; rm "$SB/b3b/scripts/tests/mutation-targets.conf"
gm b3b
ck "T3.b (b) mutation-targets.conf 부재 → M 칸 전부 미측정(변이 conf 부재) · 없음 0건 · rc 0" "$RC|$(col M)|$(nozero M)" "0|미측정(변이 conf 부재),미측정(변이 conf 부재),미측정(변이 conf 부재)|0"
ck "T3.b1 입력 안내 줄에 mutation-targets.conf 가 오른다" "$(printf '%s\n' "$OUT" | grep -c '^미측정 입력:.*mutation-targets.conf')" "1"
ck "T3.b2 M 미측정은 약함 판정에서 제외: beta(T 없음·P 없음·M 미측정)는 있음 0/2 · 미측정 1 로 약하고, alpha(T·P 있음)는 약하지 않다" "$(weakblock | grep -F ' check beta ')|$(weakblock | grep -c ' check alpha ')" "  check beta — 있음 0/2 (-) 미측정 1|0"
cpfx b3 b3c; printf '{broken\n{"id": "R-X3", "enabled": true}\n' >> "$SB/b3c/hooks/rules.jsonl"
gm b3c
ck "T3.c (c) rules.jsonl 파싱 불가 줄 → 그 행의 T 가 미측정(파싱 불가) · 멀쩡한 규칙은 그대로 · rc 0 · 머리 rules 3" "$RC|$(head1 | grep -o 'rules [0-9]*')|$(cell rule 줄2 T)|$(cell rule R-X1 T)|$(cell rule R-X3 T)" "0|rules 3|미측정(파싱 불가)|없음|없음"
ck "T3.c2 파싱 불가 규칙 행은 약함 목록에 없다(판정 불가)" "$(weakblock | grep -c ' rule 줄2 ')" "0"
# jq 부재: 필요한 도구만 심볼릭 링크한 bin 디렉터리(PATH 에서 디렉터리를 빼면 jq 와 함께 다른 도구도 사라진다)
NJ="$SB/nojq-bin"; mkdir -p "$NJ"
for t in awk grep find sort cat mktemp rm dirname mkdir; do p=$(command -v "$t") && ln -s "$p" "$NJ/$t"; done
ck "T3.d.pre 선행: nojq PATH 에서 jq 는 없고 필요한 도구는 있다" "$(env -i PATH="$NJ" "$BASH_BIN" -c 'command -v jq >/dev/null 2>&1 && echo jq; command -v awk >/dev/null 2>&1 && echo awk')" "awk"
GMPATH="$NJ" gm b3
ck "T3.d (d) jq 부재 → rules 칸 미측정(jq 부재) · P 칸 전부 미측정(jq 부재)(없음 0건) · rc 0 · T·M 은 그대로 측정" "$RC|$(cell rule R-X1 T)|$(col P)|$(nozero P)|$(col T)|$(col M)" "0|미측정(jq 부재)|미측정(jq 부재),미측정(jq 부재),미측정(jq 부재)|0|있음(명명),없음,없음|있음(conf),없음,없음"
ck "T3.d1 입력 안내 줄에 jq 가 오른다" "$(printf '%s\n' "$OUT" | grep -c '^미측정 입력:.* jq')" "1"
ck "T3.d2 jq 부재의 rules 행은 약함 목록에 없다(칸이 미측정뿐)" "$(weakblock | grep -c ' rule ')" "0"
unset GMPATH
gm b3
ck "T3.e (e) 호출처가 어디에도 없는 가드는 P 미측정(호출처 코드 없음) — 없음 이 아니다(b3 gamma)" "$(cell check gamma P)" "미측정(호출처 코드 없음)"
cpfx b3 b3f; rm -rf "$SB/b3f/scripts/tests"
gm b3f
ck "T3.f scripts/tests 부재 → T 칸 전부 미측정(테스트 디렉터리 부재)(rule·check·structure) · M 은 conf 가 같이 사라져 미측정" "$RC|$(col T)|$(cell rule R-X1 T)|$(cell structure lbl_a T)|$(col M)" "0|미측정(테스트 디렉터리 부재),미측정(테스트 디렉터리 부재),미측정(테스트 디렉터리 부재)|미측정(테스트 디렉터리 부재)|미측정(테스트 디렉터리 부재)|미측정(변이 conf 부재),미측정(변이 conf 부재),미측정(변이 conf 부재)"
ck "T3.f1 입력 안내 줄에 scripts/tests 가 오른다" "$(printf '%s\n' "$OUT" | grep -c '^미측정 입력:.*scripts/tests')" "1"
cpfx b3 b3g; printf '{broken\n' >> "$SB/b3g/scripts/_internal/propagation-matrix.jsonl"
gm b3g
ck "T3.g 원장 일부 파싱 불가: 읽힌 edge 는 유효(alpha 있음) · 근거 못 읽은 칸(beta 없음 판정 불가)은 미측정(원장 일부 파싱 불가) · 안내 줄" "$RC|$(col P)|$(printf '%s\n' "$OUT" | grep -c '^미측정 입력:.*일부 파싱 불가')" "0|있음(이름),미측정(원장 일부 파싱 불가),미측정(원장 일부 파싱 불가)|1"
cpfx b3 b3g2; printf '[1]\n' >> "$SB/b3g2/scripts/_internal/propagation-matrix.jsonl"
gm b3g2
ck "T3.g2 원장의 객체가 아닌 JSON 줄([1])도 파싱 불가로 센다(beta 는 미측정(원장 일부 파싱 불가))" "$(cell check beta P)" "미측정(원장 일부 파싱 불가)"
cpfx b3 b3h; rm "$SB/b3h/scripts/_internal/propagation-matrix.jsonl" "$SB/b3h/scripts/tests/mutation-targets.conf"; rm -rf "$SB/b3h/scripts/tests"
GMPATH="$NJ" gm b3h
ck "T3.h 판정 가능한 칸이 하나도 없는 가드(전부 미측정)는 약함 목록에서 제외 → (없음) · 0개" "$RC|$(weakblock)" "0|증거 약함 (적용 증거 2종 이상 가드(check) 중 판정 가능한 증거에서 있음 1종 이하 — 미측정 칸은 판정에서 제외): 0개
  (없음)"
unset GMPATH

cpfx b3 b3i; rm "$SB/b3i/hooks/rules.jsonl" "$SB/b3i/scripts/_internal/validate-structure.sh"
gm b3i
ck "T3.i rules.jsonl·validate-structure.sh 부재 → rules 0 · structure 0 · rc 0 · 입력 안내 줄에 둘 다" "$RC|$(head1)|$(printf '%s\n' "$OUT" | grep -c '^미측정 입력: hooks/rules.jsonl validate-structure.sh')" "0|인벤토리: rules 0 · check 3 · structure 0|1"
ck "T3.i2 입력 부재는 stderr 에 아무것도 내지 않는다" "$ERR" ""
cpfx b3 b3d; printf '\n{"enabled": true}\n' >> "$SB/b3d/hooks/rules.jsonl"
gm b3d; JQ_ROW="$(cell rule '?' T)"
GMPATH="$NJ" gm b3d; unset GMPATH
ck "T3.j id 없는 규칙: jq 경로는 행 이름 ? · jq 부재 경로는 줄N(빈 줄 포함 3번째 줄)·T 미측정(jq 부재) — 둘 다 행이 사라지지 않고 빈 줄은 규칙이 아니다" "$JQ_ROW|$(cell rule 줄3 T)|$(head1)" "없음|미측정(jq 부재)|인벤토리: rules 2 · check 3 · structure 1"
cpfx b3 b3m; rm "$SB/b3m/hooks/rules.jsonl"
GMPATH="$NJ" gm b3m; unset GMPATH
ck "T3.l rules.jsonl 부재 + jq 부재: rules 0 · rc 0 · stderr 비어 있음(없는 파일을 awk 가 열려다 내는 오류 문구가 새지 않는다)" "$RC|$(head1 | grep -o 'rules [0-9]*')|$ERR" "0|rules 0|"
cpfx b3 b3k; printf '[1]\n{"id": "R-X9", "enabled": false}\n' >> "$SB/b3k/hooks/rules.jsonl"
gm b3k
ck "T3.k 객체가 아닌 JSON 줄([1])도 파싱 불가 행(줄2)이고 이어지는 규칙은 정상(R-X9 비활성)" "$(cell rule 줄2 T)|$(cell rule R-X9 T)" "미측정(파싱 불가)|비활성"

# ═════ T4 (AC-4): 요약 · 증거 약함 목록 · --weak-only ═════
mkfx f4
rule f4 '{"id": "R-X1", "enabled": true}'
rule f4 '{"id": "R-X2", "enabled": false}'
rule f4 '{"id": "R-X3", "enabled": true}'
chk f4 full two one zero unkfull unkweak
lbl f4 lbl_a lbl_b
for n in full two one unkfull; do printf 'echo %s\n' "$n" > "$SB/f4/scripts/tests/test-$n.sh"; done
printf 'echo R-X1 lbl_a\n' > "$SB/f4/scripts/tests/test-misc.sh"
conf f4 'scripts/_internal/check-full.sh|bash scripts/tests/test-full.sh'
conf f4 'scripts/_internal/check-unkfull.sh|bash scripts/tests/test-unkfull.sh'
file f4 scripts/run.sh <<'EOF'
bash scripts/_internal/check-full.sh
bash scripts/_internal/check-two.sh
bash scripts/_internal/check-one.sh
bash scripts/_internal/check-zero.sh
EOF
led f4 <<'EOF'
{"id":"f","edges":[{"path":"scripts/run.sh","must_match":"check-full\\.sh"},{"path":"scripts/run.sh","must_match":"check-two\\.sh"}]}
EOF
gm f4
ck "T4.a rc=0(약함이 있어도 관측 도구라 0) · 종류별 줄 3개 + 총괄 줄" "$RC|$(printf '%s\n' "$OUT" | grep -c '^- ')" "0|4"
ck "T4.b rule 요약: 3개 · T 있음 1 없음 1 미측정 0 - 1(비활성 1 은 -에 포함)" "$(sumline rule)" "- rule      3개 | T 있음 1 없음 1 미측정 0 - 1 | 비활성 1(-에 포함) | 판정 제외(적용 증거 1종)"
ck "T4.c check 요약: 6개 · T 4/2/0/0 · M 2/4/0/0 · P 2/2/2/0 (증거 종류별 있음 수)" "$(sumline check)" "- check     6개 | T 있음 4 없음 2 미측정 0 - 0 | M 있음 2 없음 4 미측정 0 - 0 | P 있음 2 없음 2 미측정 2 - 0"
ck "T4.d structure 요약: 2개 · T 있음 1 없음 1" "$(sumline structure)" "- structure 2개 | T 있음 1 없음 1 미측정 0 - 0 | 판정 제외(적용 증거 1종)"
ck "T4.e 총괄: 가드 11개 중 증거 2종 이상 3개(full·two·unkfull) · 증거 약함 3개(check 만 — one·zero·unkweak)" "$(printf '%s\n' "$OUT" | grep -m1 '^- 가드')" "- 가드 11개 중 증거 2종 이상 3개 · 증거 약함 3개"
EXPECT_WEAK='증거 약함 (적용 증거 2종 이상 가드(check) 중 판정 가능한 증거에서 있음 1종 이하 — 미측정 칸은 판정에서 제외): 3개
  check one — 있음 1/3 (T) 미측정 0
  check unkweak — 있음 0/2 (-) 미측정 1
  check zero — 있음 0/3 (-) 미측정 0'
ck "T4.f 약함 목록: check 중 있음 ≤ 1 인 3개만(one·zero·unkweak) — full·two·unkfull(미측정 P 가 있어도 있음 2종)은 없고 rule·structure(R-X1 있음 1/1 · R-X3 없음 · lbl_a·lbl_b)는 약함이어도 목록에 없다" "$(weakblock)" "$EXPECT_WEAK"
FULL_WEAK=$(weakblock)
gm f4 --weak-only
ck "T4.g --weak-only: 약함 목록만(rc 0) — 인벤토리·표·요약·한계가 없고 목록이 기본 실행의 약함 블록과 같다" "$RC|$OUT" "0|$FULL_WEAK"
ck "T4.h --weak-only 출력에 표 머리·한계 푸터가 없다" "$(printf '%s\n' "$OUT" | grep -c -e '^인벤토리' -e '^요약' -e '^한계' -e '^범례' -e '^종류 ')" "0"
gm f4 --weak-only --repo "$SB/f4"
ck "T4.i 옵션 순서·--repo 중복 지정에도 같다" "$RC|$OUT" "0|$FULL_WEAK"
cpfx f4 f4n; rm -f "$SB/f4n/scripts/tests"/test-*.sh; rm "$SB/f4n/scripts/_internal"/check-*.sh; printf '' > "$SB/f4n/hooks/rules.jsonl"; printf '#!/bin/sh\n' > "$SB/f4n/scripts/_internal/validate-structure.sh"; printf '' > "$SB/f4n/scripts/tests/mutation-targets.conf"
gm f4n --weak-only
ck "T4.j 가드가 하나도 없으면 약함 0개 · (없음) · rc 0" "$RC|$OUT" "0|증거 약함 (적용 증거 2종 이상 가드(check) 중 판정 가능한 증거에서 있음 1종 이하 — 미측정 칸은 판정에서 제외): 0개
  (없음)"
gm f4n
ck "T4.k 가드 0개의 머리·표: 인벤토리 숫자가 0 이다" "$(head1)" "인벤토리: rules 0 · check 0 · structure 0"

# ═════ T4b (AC-9): 약함 판정은 적용 증거가 2종 이상인 가드(check)에 한정한다 ═════
gm f4
ck "T4b.a 기본 실행: 약함 목록에 rule·structure 행이 하나도 없다(f4 의 R-X1 있음 1/1·R-X3 없음 0/1·lbl_a·lbl_b 는 예전 문면이면 약함이었다) · 표에는 T 칸이 그대로 있다" "$(weakblock | grep -cE '^  (rule|structure) ')|$(cell rule R-X3 T)|$(cell structure lbl_b T)" "0|없음|없음"
ck "T4b.b 요약: rule·structure 줄에 판정 제외(적용 증거 1종) 표기와 개수(T 있음/없음)가 함께 보이고 check 줄에는 표기가 없다" "$(sumline rule | grep -c '판정 제외(적용 증거 1종)')$(sumline structure | grep -c '판정 제외(적용 증거 1종)')$(sumline check | grep -c '판정 제외')|$(sumline structure | grep -o 'T 있음 [0-9]* 없음 [0-9]*')" "110|T 있음 1 없음 1"
SUMW=$(printf '%s\n' "$OUT" | grep -m1 '^- 가드' | grep -o '증거 약함 [0-9]*개' | grep -o '[0-9]*'); HEADW=$(weakblock | head -1 | sed 's/개$//; s/^.*: //'); LISTW=$(weakblock | grep -cE '^  (rule|check|structure) ')
gm f4 --weak-only; WOW=$(printf '%s\n' "$OUT" | grep -cE '^  (rule|check|structure) ')
ck "T4b.c 항목 수 일치: 요약의 증거 약함 수 = 목록 머리의 N = 목록 줄 수 = --weak-only 항목 수 (f4: 3)" "$SUMW/$HEADW/$LISTW/$WOW" "3/3/3/3"
mkfx w9
rule w9 '{"id": "R-X1", "enabled": true}'
rule w9 '{"id": "R-X2", "enabled": true}'
lbl w9 lbl_a lbl_b
printf 'echo R-X2\n' > "$SB/w9/scripts/tests/test-misc.sh"
gm w9
ck "T4b.d rules·structure 만 있고 증거가 없거나 1종뿐인 fixture → 약함 0 (R-X1 없음·lbl_a 없음도 약함이 아니다) · 요약 총괄 증거 약함 0개 · 목록 (없음)" "$RC|$(printf '%s\n' "$OUT" | grep -m1 '^- 가드' | grep -o '증거 약함 [0-9]*개')|$(weakblock | tail -1)|$(weakblock | grep -c '개$')" "0|증거 약함 0개|  (없음)|1"
gm w9 --weak-only
ck "T4b.e 같은 fixture 의 --weak-only: 0개 · (없음) · rc 0" "$RC|$OUT" "0|$NEWH_LINE0"
chk w9 solo
gm w9
ck "T4b.f 음성 대조: 같은 fixture 에 증거 없는 check(solo)를 더하면 약함 1(check solo 만 · rule R-X1 은 여전히 목록에 없다)" "$(weakblock | grep -cE '^  check solo ')|$(weakblock | grep -cE '^  (rule|structure) ')|$(printf '%s\n' "$OUT" | grep -m1 '^- 가드' | grep -o '증거 약함 [0-9]*개')" "1|0|증거 약함 1개"

# ═════ T5 (AC-5): 푸터 한계 고지 · 읽기 전용 · 종료 코드 ═════
gm f4
ck "T5.a 푸터 한계 4종(고정 문구 — ① 명명 규약 밖·훅 deny 분기 ② 참조≠단언 ③ 변이 점수 미재계산 ④ edge 문자열 존재만)" "$(hasline ' ① 명명 규약 밖 게이트(release-ready.sh·reconcile-check.sh·batch-state.sh --gate 등)와 훅 deny 분기는 인벤토리에 없다.')$(hasline ' ② 테스트 `참조` 는 가드를 단언한다는 뜻이 아니다 — 증거 있음 ≠ 가드 작동.')$(hasline ' ③ 변이 점수는 직접 재계산하지 않는다 — M 은 mutation-targets.conf 등록 여부만 본다.')$(hasline ' ④ propagation edge 는 must_match 를 단어 단위로만 읽고 문자열 존재만 본다 — 교대(|)·glob·부정 정규식은 오탐·미탐이 날 수 있다.')|$(hasline '한계')" "1111|1"
snap() { (cd "$SB/$1" && find . -type f -print0 | sort -z | xargs -0 cksum; find . -type f -exec ls -l {} + | awk '{print $1, $NF}' | sort; find . | sort) | cksum; }
SNAP1=$(snap f2); gm f2; SNAP2=$(snap f2)
ck "T5.b 읽기 전용: 실행 전후 fixture 트리 해시(내용·모드·파일 목록)가 같다" "$SNAP2" "$SNAP1"
ck "T5.c 임시 파일 잔존 0 (TMPDIR 전용 디렉터리) · 출력에 임시 경로·fixture 경로가 새지 않는다" "$(ls -A "$SB/tmp" | wc -l | tr -d ' ')|$(printf '%s\n%s\n' "$OUT" "$ERR" | grep -c -e "$SB" -e 'guard-map\.')" "0|0"
gm nonexistent-dir
ck "T5.d --repo 가 없는 디렉터리 → rc 2 · stdout 비어 있음 · stderr 에 사용법" "$RC|$OUT|$(printf '%s\n' "$ERR" | grep -c '^사용: guard-map.sh')" "2||1"
gm f2 --json
ck "T5.e 알 수 없는 옵션(--json) → rc 2 · stdout 비어 있음 · 사용법" "$RC|$OUT|$(printf '%s\n' "$ERR" | grep -c '^사용: guard-map.sh')" "2||1"
env -i PATH="$PATH" TMPDIR="$SB/tmp" "$BASH_BIN" "$GM" --repo >/dev/null 2>"$SB/err"; RCV=$?
ck "T5.f --repo 값 누락 → rc 2" "$RCV" "2"
env -i PATH="$PATH" TMPDIR="$SB/tmp" "$BASH_BIN" "$GM" stray >/dev/null 2>"$SB/err"; RCP=$?
ck "T5.g 위치 인자(옵션 아님) → rc 2" "$RCP" "2"
env -i PATH="$PATH" TMPDIR="$SB/tmp" "$BASH_BIN" "$GM" -h >"$SB/out" 2>"$SB/err"; RCH=$?
ck "T5.h -h → rc 0 · stdout 에 사용법" "$RCH|$(grep -c '^사용: guard-map.sh' "$SB/out")" "0|1"
env -i PATH="$PATH" TMPDIR="$SB/tmp" "$BASH_BIN" "$GM" --repo "" >"$SB/out" 2>"$SB/err"; RCE=$?
env -i PATH="$PATH" TMPDIR="$SB/tmp" "$BASH_BIN" "$GM" --weak-only --repo "" >"$SB/out2" 2>"$SB/err2"; RCE2=$?
ck "T5.j --repo \"\"(빈 값) → rc 2 · stdout 비어 있음 · stderr 에 사유와 사용법 (단독·--weak-only 함께)" "$RCE|$(wc -c < "$SB/out" | tr -d ' ')|$(grep -c '^guard-map: --repo 값이 비어 있다' "$SB/err")|$(grep -c '^사용: guard-map.sh' "$SB/err")|$RCE2|$(wc -c < "$SB/out2" | tr -d ' ')" "2|0|1|1|2|0"
if [ "$(id -u)" -eq 0 ]; then  # root 는 a-w 트리에도 쓴다 — repo 안 임시 파일이 생겨도 실패하지 않아 단언이 공허하다
  echo "SKIP T5.ro 읽기 전용 root(chmod a-w) — root 로 실행 중(권한 검사 무의미)"
else
  cpfx f1 f1ro; gm f1; RO_BASE="$OUT"; chmod -R a-w "$SB/f1ro"; gm f1ro; RO_RC=$RC; RO_OUT="$OUT"; chmod -R u+w "$SB/f1ro"
  ck "T5.ro 읽기 전용 root(chmod a-w)에서도 rc 0 · 같은 출력 — 임시 파일을 대상 repo 안에 만들지 않는다" "$RO_RC|$([ "$RO_OUT" = "$RO_BASE" ] && echo same)" "0|same"
fi
ck "T5.i 오류 실행 뒤에도 임시 파일 잔존 0" "$(ls -A "$SB/tmp" | wc -l | tr -d ' ')" "0"
# --repo 생략 시 기본: 이 스크립트 위치 기준 repo — 사본 트리 안의 스크립트를 돌리면 그 트리의 가드를 센다
mkfx dflt; mkdir -p "$SB/dflt/scripts"; cp "$GM" "$SB/dflt/scripts/guard-map.sh"; chk dflt only1
OUTD=$(env -i PATH="$PATH" TMPDIR="$SB/tmp" "$BASH_BIN" "$SB/dflt/scripts/guard-map.sh" 2>/dev/null)
ck "T5.j --repo 생략 → 스크립트 위치 기준 repo(사본 트리의 check 1개)" "$(printf '%s\n' "$OUTD" | grep -m1 '^인벤토리:')" "인벤토리: rules 0 · check 1 · structure 0"

# ═════ T6 (AC-6): 시각·세션 환경 독립 + awk 3종 ═════
gm f4; BASE_OUT="$OUT"
mkdir -p "$SB/dshim"; printf '#!/bin/sh\necho "Sat Jan  1 00:00:00 UTC 2000"\n' > "$SB/dshim/date"; chmod +x "$SB/dshim/date"
same=0; tot=0
for v in "CLAUDE_CODE_SESSION_ID=sess-2026-10-03T15" "CLAUDE_CODE_SESSION_ID=" "TZ=UTC" "TZ=Pacific/Kiritimati" "TZ=America/Los_Angeles CLAUDE_CODE_SESSION_ID=s-T15" "LC_ALL=C LANG=C" "LC_ALL=en_US.UTF-8"; do
  GMX="$v" GMPATH="$SB/dshim:$PATH" gm f4; tot=$((tot+1))
  [ "$OUT" = "$BASE_OUT" ] && same=$((same+1))
done
unset GMX GMPATH
ck "T6.a 시각 shim(date 가 2000-01-01 만 답함)·세션 변수 설정/빈값·TZ 3종·로케일 변이 7종 모두 기본 실행과 출력이 같다" "$same/$tot" "7/7"
gm f4 --weak-only; BASE_W="$OUT"
GMX="CLAUDE_CODE_SESSION_ID=s-T15 TZ=Pacific/Kiritimati" GMPATH="$SB/dshim:$PATH" gm f4 --weak-only; unset GMX GMPATH
ck "T6.b --weak-only 도 같다" "$OUT" "$BASE_W"
asame=0; atot=0; anames=""
for cand in gawk mawk original-awk nawk /usr/bin/awk; do
  ap=$(command -v "$cand" 2>/dev/null) || continue
  [ -x "$ap" ] || continue
  d="$SB/awk-$atot"; mkdir -p "$d"; ln -s "$ap" "$d/awk"
  GMPATH="$d:$PATH" gm g1; atot=$((atot+1))
  if [ "$OUT" = "$GOLDEN_G1" ]; then asame=$((asame+1)); else anames="$anames $cand"; fi
  GMX="LC_ALL=en_US.UTF-8" GMPATH="$d:$PATH" gm g1; unset GMX; atot=$((atot+1))
  if [ "$OUT" = "$GOLDEN_G1" ]; then asame=$((asame+1)); else anames="$anames $cand(UTF-8)"; fi
done
unset GMPATH
ck "T6.c 설치된 awk 전부(gawk·mawk·BSD awk·nawk — 있는 것만)에서 골든 출력과 같다 (불일치:${anames:- 없음}) · 최소 1종" "$([ "$atot" -ge 1 ] && echo "$asame/$atot" || echo none)" "$atot/$atot"
GM_CODE="$SB/gm-code.txt"; grep -vE '^[[:space:]]*#' "$GM" > "$GM_CODE"
ck "T6.d 정적: 코드에 date 호출·mktime·세션 변수·~/.claude·\$HOME 이 없다" "$(grep -cE '(^|[^A-Za-z_-])date([[:space:]]|$)|mktime|CLAUDE_CODE_SESSION_ID|\.claude|\$HOME|\$\{HOME' "$GM_CODE")" "0"
ck "T6.e 정적: awk interval expression({n}·{n,m})이 없다" "$(grep -cE '(^|[^$])[{][0-9]+(,[0-9]*)?[}]' "$GM_CODE")" "0"
ck "T6.f 정적: shebang · 실행권한 · 네임스페이스(최상위 함수는 전부 gm:: · 전역 변수는 GM_ 접두)" "$(head -1 "$GM")|$([ -x "$GM" ] && echo x)|$(grep -E '^[a-zA-Z_][A-Za-z0-9_:]*\(\)' "$GM_CODE" | grep -vcE '^gm::')|$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$GM_CODE" | grep -vcE '^GM_')" "#!/usr/bin/env bash|x|0|0"

# ═════ T7 (AC-7): 실 repo 구조 스모크 — 정확한 수치가 아니라 일관성만 ═════
if [ -f "$REAL_ROOT/hooks/rules.jsonl" ] && [ -d "$REAL_ROOT/scripts/_internal" ]; then
  T0=$SECONDS
  OUT=$(env -i PATH="$PATH" HOME="$SB/home" TMPDIR="$SB/tmp" "$BASH_BIN" "$GM" --repo "$REAL_ROOT" 2>"$SB/err"); RC=$?
  T1=$SECONDS
  ck "T7.a 실 repo 에서 rc 0 · 20초 이내(CPU 경합 여유 — 실측 1초 안팎, 목표 ~10초) · stderr 비어 있음" "$RC|$([ $((T1 - T0)) -le 20 ] && echo fast)|$(cat "$SB/err")" "0|fast|"
  RN=$(grep -c '[^[:space:]]' "$REAL_ROOT/hooks/rules.jsonl")
  CN=$(ls "$REAL_ROOT"/scripts/_internal/check-*.sh | wc -l | tr -d ' ')
  SN=$(grep -vE '^[[:space:]]*#' "$REAL_ROOT/scripts/_internal/validate-structure.sh" | grep -oE '(^|[^A-Za-z0-9_])emit [a-z_]+ [A-Z]+' | awk '{ print $(NF-1) }' | sort -u | wc -l | tr -d ' ')
  ck "T7.b 인벤토리 숫자가 ls·grep 직접 집계(rules.jsonl 비공백 줄 · check-*.sh 파일 수 · emit 라벨 고유 수)와 일치한다" "$(head1)" "인벤토리: rules $RN · check $CN · structure $SN"
  ck "T7.c 표 행 수가 종류별 인벤토리 수와 같다(가드 1행씩)" "$(printf '%s\n' "$OUT" | awk -F'  +' '$1 == "rule" { r++ } $1 == "check" { c++ } $1 == "structure" { s++ } END { print r + 0, c + 0, s + 0 }')" "$RN $CN $SN"
  # 종류별 합계 일관성: 칸마다 있음+없음+미측정+- = 가드 수
  SUMOK=$(printf '%s\n' "$OUT" | awk '
    /^- (rule|check|structure) / {
      n = $3; sub(/개$/, "", n); bad = 0
      m = split($0, seg, " \\| ")
      for (i = 2; i <= m; i++) {
        if (seg[i] ~ /^[TMP] 있음/) { split(seg[i], f, " "); if (f[3] + f[5] + f[7] + f[9] != n) bad = 1; cols++ }
      }
      if (cols == 0) bad = 1
      tot++; if (bad) nb++
    }
    END { print (tot == 3 && nb == 0) ? "ok" : "bad:" tot "/" nb }')
  ck "T7.d 종류별 요약의 칸마다 있음+없음+미측정+- = 가드 수" "$SUMOK" "ok"
  VOCAB=$(printf '%s\n' "$OUT" | awk -F'  +' '($1 == "rule" || $1 == "check" || $1 == "structure") { for (i = 3; i <= 5; i++) if ($i !~ /^(있음\(.+\)|없음|미측정\(.+\)|-|비활성|자기잠금)$/) bad++ } END { print bad + 0 }')
  ck "T7.e 표의 모든 칸이 허용 어휘(있음(근거)·없음·미측정(사유)·-·비활성·자기잠금)다" "$VOCAB" "0"
  ck "T7.f 증거 약함: 요약의 수 = 머리의 N = 목록 줄 수 · 목록은 check 행뿐(rule·structure 제외) · 푸터 4종" "$(printf '%s\n' "$OUT" | awk '/^- 가드/ { s = $0; sub(/^.*증거 약함 /, "", s); sub(/개$/, "", s) } /^증거 약함/ { n = $0; sub(/개$/, "", n); sub(/^.*: /, "", n); on = 1; next } /^한계/ { on = 0 } on && /^  check / { c++ } on && /^  (rule|structure) / { o++ } END { print (s + 0 == n + 0 && n + 0 == c + 0 && o + 0 == 0) ? "ok" : "bad " s " " n " " c + 0 " " o + 0 }')|$(printf '%s\n' "$OUT" | grep -c -e '^ ① ' -e '^ ② ' -e '^ ③ ' -e '^ ④ ')" "ok|4"
else
  ck "T7.pre 실 repo 구조(hooks/rules.jsonl · scripts/_internal)를 찾을 수 있다" "none" "found"
fi

# ═════ T8 (AC-8): 산문(.md) 호출 배선 edge 도 P 로 세고 근거에 산문을 표시한다 ═════
mkfx f8
chk f8 proseonly nowhere codeonly proseno both procvar
file f8 commands/go.md <<'EOF'
run scripts/_internal/check-proseonly.sh then check-proseno.sh and check-both.sh
EOF
file f8 skills/k/SKILL.md <<'EOF'
PROCVAR_SH="$X/scripts/_internal/check-procvar.sh"
EOF
file f8 scripts/x.sh <<'EOF'
bash scripts/_internal/check-codeonly.sh
bash scripts/_internal/check-both.sh
EOF
led f8 <<'EOF'
{"id":"p1","edges":[{"path":"commands/go.md","must_match":"check-proseonly\\.sh"},{"path":"commands/go.md","must_match":"check-both"}]}
{"id":"p2","edges":[{"path":"scripts/x.sh","must_match":"check-codeonly\\.sh"},{"path":"scripts/x.sh","must_match":"check-both\\.sh"}]}
{"id":"p3","edges":[{"path":"skills/k/SKILL.md","must_match":"\\$PROCVAR_SH"}]}
EOF
gm f8
ck "T8.a (a) 호출처가 .md 뿐 · .md edge 가 가드명을 담음 → P 있음(이름·산문)" "$RC|$(cell check proseonly P)" "0|있음(이름·산문)"
ck "T8.b (b) 호출처가 코드·산문 어디에도 없는 가드 → P 미측정(호출처 코드 없음)" "$(cell check nowhere P)" "미측정(호출처 코드 없음)"
ck "T8.c (c) 코드 호출처 edge → 있음(이름) · 코드·산문 edge 가 둘 다 있으면 코드 근거가 먼저(산문 표시 없음)" "$(cell check codeonly P)|$(cell check both P)" "있음(이름)|있음(이름)"
ck "T8.d 음성: 산문 호출처는 있으나 원장 edge 가 없으면 없음(산문 edge 부재 시 미측정이 아니라 없음 — 호출처가 있다)" "$(cell check proseno P)" "없음"
ck "T8.e 산문의 *_SH 변수 할당 + 산문 edge → 있음(변수 PROCVAR_SH·산문) · 자기잠금이 아니다" "$(cell check procvar P)" "있음(변수 PROCVAR_SH·산문)"
ck "T8.f 산문 edge 는 증거 약함 판정에서 P 있음으로 센다: proseonly 에 T 만 더하면 있음 2종 → 약하지 않다" "$(cpfx f8 f8w; printf 'echo\n' > "$SB/f8w/scripts/tests/test-proseonly.sh"; gm f8w; weakblock | grep -c ' check proseonly ')|$(gm f8; weakblock | grep -c ' check proseonly ')" "0|1"
gm f8 --tsv; RC_TSV="$RC|$OUT"; gm f8
ck "T8.g --tsv 도 알 수 없는 옵션 → rc 2·stdout 없음 · 기본 출력은 사람용 표(탭 구분 TSV·JSON 아님: 탭 0 · 첫 줄 인벤토리)" "$RC_TSV|$(printf '%s\n' "$OUT" | grep -c "$(printf '\t')")|$(printf '%s\n' "$OUT" | head -1 | grep -c '^인벤토리')" "2||0|1"

# ═════ T9: source 가능 · 성능 · 결정성 ═════
mkfx s1; chk s1 only1
SRC=$("$BASH_BIN" -c '
  before_f=$(declare -F | sed "s/^declare -f //" | sort); before_v=$(compgen -v | sort)
  # shellcheck disable=SC1090
  source "$1" || exit 9
  after_f=$(declare -F | sed "s/^declare -f //" | sort); after_v=$(compgen -v | sort)
  trap "echo CALLER-TRAP-FIRED" EXIT
  nf=$(comm -13 <(printf "%s\n" "$before_f") <(printf "%s\n" "$after_f") | grep -vc "^gm::")
  nv=$(comm -13 <(printf "%s\n" "$before_v") <(printf "%s\n" "$after_v") | grep -v -e "^GM_" -e "^BASH_" -e "^_$" -e "^before_" -e "^after_" -e "^nf$" -e "^nv$" | wc -l | tr -d " ")
  echo "newfn=$nf newvar=$nv"
  echo "$(gm::main --repo "$2" | sed -n 1p)"   # head -1 은 SIGPIPE 가 무시되는 환경(CI 러너)에서 cat 의 Broken pipe 를 stderr 로 흘린다
  echo "after-main"' _ "$GM" "$SB/s1" 2>&1)
ck "T9.a source 만으로는 아무것도 출력·실행하지 않고(main 미실행) 새 함수는 전부 gm:: · 새 변수는 GM_ 접두 · gm::main 호출 뒤에도 호출자의 EXIT trap 이 살아 있다" "$SRC" "newfn=0 newvar=0
인벤토리: rules 0 · check 1 · structure 0
after-main
CALLER-TRAP-FIRED"
mkfx big
for i in $(seq 1 60); do chk big "g$i"; done
for i in $(seq 1 250); do
  { for j in 1 2 3 4 5 6 7 8 9 10; do echo "word$i foo_bar baz-qux check-g$((i % 70)).sh R-$j lbl_$j some more filler words here and there to make lines non trivial $i $j"; done; } > "$SB/big/scripts/tests/test-t$i.sh"
done
for i in $(seq 1 120); do printf 'echo check-g%s.sh\n' "$i" > "$SB/big/scripts/s$i.sh"; done
printf '{"id":"b","edges":[{"path":"scripts/s1.sh","must_match":"check-g1\\\\.sh"}]}\n' > "$SB/big/scripts/_internal/propagation-matrix.jsonl"
T0=$SECONDS; gm big; T1=$SECONDS
ck "T9.b 합성 대형 입력(check 60 · 테스트 250 · 호출처 120)이 rc 0 · 10초 이내(반복 프로세스 생성 없이 한 번에 조인 — 실측 1초 안팎)" "$RC|$(head1)|$([ $((T1 - T0)) -le 10 ] && echo fast)" "0|인벤토리: rules 0 · check 60 · structure 0|fast"
mkfx o1; chk o1 zz aa mm Bb; mkfx o2; chk o2 mm Bb zz aa
gm o1; O1="$OUT"; gm o2; O2="$OUT"
ck "T9.c 결정성: 같은 내용의 fixture 는 파일 생성 순서와 무관하게 같은 출력" "$O1" "$O2"
GMX="LC_ALL=en_US.UTF-8" gm o1; unset GMX
ck "T9.d 로케일 독립: UTF-8 로케일에서도 같은 출력 — 대문자 이름(Bb)은 C 순서대로 aa 앞(정렬을 로케일에 맡기지 않는다)" "$OUT" "$O1"
ck "T9.e 대문자 이름 정렬: Bb < aa < mm < zz (C 순서)" "$(printf '%s\n' "$O1" | awk -F'  +' '$1 == "check" { printf "%s,", $2 }')" "Bb,aa,mm,zz,"

SRCO=$("$BASH_BIN" -c '
  source "$1" || exit 9
  a=$(set -o | grep -E "^(nounset|pipefail)" | tr -s " \t" " " | tr "\n" ,)
  gm::main --repo "$2" >/dev/null
  b=$(set -o | grep -E "^(nounset|pipefail)" | tr -s " \t" " " | tr "\n" ,)
  echo "$a|$b"' _ "$GM" "$SB/s1" 2>&1)
ck "T9.f source 해도 호출자 셸의 nounset·pipefail 이 켜지지 않는다(source 직후·gm::main 호출 뒤 모두 off)" "$SRCO" "nounset off,pipefail off,|nounset off,pipefail off,"
ck "T9.g 엄격 모드는 gm::main 서브셸 첫 줄에서 켜고 최상위에는 없다(정적 잠금 — 서브셸 안 옵션은 블랙박스로 못 본다)" "$(awk '/^gm::main\(\) \($/ { getline; print; exit }' "$GM")|$(grep -c '^set -uo pipefail' "$GM")" "  set -uo pipefail|0"

# ═════ T10: 문서(scripts/README.md 의 guard-map 절) ═════
SECF="$SB/readme-sec.txt"
awk '/^## guard-map.sh/ { on = 1; next } /^## / { on = 0 } on' "$PLUGIN/scripts/README.md" > "$SECF"
kw() { if grep -qF -- "$1" "$SECF"; then printf y; else printf n; fi; }
ck "T10.a README 에 guard-map 절: 사용법(--weak-only·--repo)·증거 종류(T·M·P 호출 배선)·미측정·해석 주의(증거 있음 ≠ 가드 작동)·한계(명명 규약 밖 게이트·참조·변이 점수·edge 문자열)·읽기 전용" "$(kw 'bash scripts/guard-map.sh')$(kw '--weak-only')$(kw '--repo')$(kw '미측정')$(kw '자기잠금')$(kw '산문')$(kw '증거 있음 ≠ 가드 작동')$(kw '명명 규약 밖')$(kw '변이 점수')$(kw '문자열 존재')$(kw '읽기 전용')" "yyyyyyyyyyy"
ck "T10.b README 절은 --json·--tsv 를 지원 옵션으로 소개하지 않는다(YAGNI — 후속 FID)" "$(grep -cE '^[[:space:]]*(bash scripts/guard-map.sh .*--(json|tsv)|- `--(json|tsv)`)' "$SECF")" "0"
ck "T10.c README 해석 주의에 P 판정 한계(must_match 단어 단위·교대·glob·부정 정규식 오탐·미탐)가 있다" "$(kw 'must_match` 를 단어 단위로만 읽는다')$(kw '교대')$(kw 'glob')$(kw '오탐·미탐')" "yyyy"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
