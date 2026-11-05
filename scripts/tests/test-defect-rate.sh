#!/usr/bin/env bash
# defect-rate.sh — FID 별 "머지 후 N일 안 결함 fix" 집계 회귀 (임시 git 저장소 fixture 만 사용 — 실저장소를 읽지도 쓰지도 않는다, 토큰 0)
# fixture 시각은 모두 2024-01-01 기준 고정 epoch(+0000) — 벽시계·로컬 타임존에 의존하지 않는다.
# shellcheck disable=SC1091,SC2012,SC2015,SC2034,SC2046
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
DR="$PLUGIN/scripts/defect-rate.sh"
BASH_BIN=$(command -v bash)
REAL_GIT=$(command -v git)
SB=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/tmp" "$SB/home" "$SB/shim"
# 사용자 git 설정(서명·기본 브랜치·merge 옵션)이 fixture 에 새지 않게 한다
export HOME="$SB/home" XDG_CONFIG_HOME="$SB/home" GIT_CONFIG_NOSYSTEM=1 GIT_MERGE_AUTOEDIT=no
export GIT_CEILING_DIRECTORIES="$SB"   # 비 git 폴더 case 가 상위(임시 폴더 위쪽) 저장소를 찾아 올라가지 못하게
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid

ck() { if [ "$2" = "$3" ]; then ok "$1"; else nope "$1" "exp '$3' got '$2'"; fi; }

# ── fixture 헬퍼 ─────────────────────────────────────────────────────────────
# 모든 커밋은 cm/mg 로만 만든다 — 둘 다 작성·커밋 시각을 고정 epoch 로 박는다(빠뜨리면 벽시계가 들어와 기간 단언이 우연히 맞거나 틀린다).
E0=1704067200; DAY=86400                       # 2024-01-01T00:00:00Z
t() { echo $(( E0 + $1 * DAY + ${2:-0} )); }   # t <일> [초] → epoch
_dt() { GIT_AUTHOR_DATE="@$1 +0000"; GIT_COMMITTER_DATE="@$1 +0000"; export GIT_AUTHOR_DATE GIT_COMMITTER_DATE; }
g() { git -C "$R" "$@"; }
mkrepo() { R="$SB/$1"; rm -rf "$R"; mkdir -p "$R"; git -C "$R" init -q 2>/dev/null; git -C "$R" symbolic-ref HEAD "refs/heads/${2:-main}"; }
put() { local f="$R/$1"; shift; mkdir -p "$(dirname "$f")"; printf '%s\n' "$@" > "$f"; }   # put <경로> <줄>… (파일 전체 교체)
cm() { _dt "$1"; g add -A; g commit -q -m "$2"; }                                            # cm <epoch> <제목>
brn() { g checkout -q -b "$1" "${2:-main}"; }                                                # brn <새 브랜치> [시작점]
mg() { g checkout -q main; _dt "$1"; g merge -q --no-ff "$2" -m "$3"; }                      # mg <epoch> <브랜치> <제목>
PR() { echo "Merge pull request #$1 from o/$2"; }                                            # PR <번호> <브랜치> → GitHub 머지 제목

# 실행: dr <인자…> → OUT RC ERR (cwd=$SB · TMPDIR 은 전용 빈 폴더 — 누출 검사용 · 시각 env 제거)
dr() {
  OUT=$(cd "$SB" && unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE && TZ="${TZV:-UTC}" TMPDIR="$SB/tmp" "$BASH_BIN" "$DR" "$@" 2>"$SB/err"); RC=$?
  ERR=$(cat "$SB/err")
}
has()  { printf '%s\n' "$OUT" | grep -Fxq -- "$1"; }                                            # 출력에 이 줄이 통째로 있다
row()  { printf '%s\n' "$OUT" | awk -v f="$1" '$1 == f { print $2, $3, $4 }'; }                 # 표의 한 행 → "머지일 상태 결함수"
fids() { printf '%s\n' "$OUT" | awk '/^FID /{t=1; next} /^---$/{t=0} t && NF { print $1 }' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; }
L1() { printf '완료 FID %s · 결함 있는 FID %s (%s%%) · FID 당 평균 %s' "$1" "$2" "$3" "$4"; }
L2() { printf '관찰중 %s · 코드변경없음 %s · 인식 못 한 머지 %s · 귀속 못 한 fix %s · blame 실패 %s' "$1" "$2" "$3" "$4" "$5"; }
HDR() { printf 'defect-rate: base=%s@%s 기간=%s일 기준시각=%s' "$1" "$(git -C "$2" rev-parse "$1" | cut -c1-8)" "$3" "$4"; }
NOTE='※ 근사치: 줄 추가만 하는 fix 와 fix 규약을 안 지킨 수정은 세지 않는다.'
fp() { (cd "$1" && find .git -type f -exec cksum {} + | LC_ALL=C sort); }                       # 저장소 지문(.git 전 파일 cksum)
leaks() { ls -A "$SB/tmp" | wc -l | tr -d ' '; }                                                 # 전용 TMPDIR 에 남은 항목 수
nlines() { if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi; }

# 오류 경로 공통 단언: rc 2 · stdout 비어 있음(부분 표 금지) · stderr 정확히 1줄이고 "defect-rate:" 로 시작
err_case() {
  local d="$1"; shift
  dr "$@"
  if [ "$RC" = 2 ] && [ -z "$OUT" ] && [ "$(nlines "$ERR")" = 1 ] && [ "${ERR#defect-rate: }" != "$ERR" ]; then ok "$d"
  else nope "$d" "rc=$RC out='$OUT' err='$ERR'"; fi
}

# ══ fixture 1: attr — AC-1 줄 단위 귀속 ═══════════════════════════════════════
#   A 가 app.txt 에 A-line 추가·머지(2일) → B 가 같은 파일에 B-line, b.txt 추가·머지(4일)
#   12일: A-line 수정 fix  ·  13일: 줄만 추가하는 fix(b.txt 중간·app.txt 끝 = B-line 바로 뒤)  ·  100일: 현재(base 끝)
mkrepo attr
put app.txt base1 base2; put note.txt n1; cm "$(t 0)" "chore: init"
brn feat/20240102-aaa; put app.txt base1 base2 A-line; cm "$(t 1)" "feat: A line"
mg "$(t 2)" feat/20240102-aaa "$(PR 1 feat/20240102-aaa)"
brn feat/20240104-bbb; put app.txt base1 base2 A-line B-line; put b.txt b1 b2 b3; cm "$(t 3)" "feat: B"
mg "$(t 4)" feat/20240104-bbb "$(PR 2 feat/20240104-bbb)"
put app.txt base1 base2 A-line-fixed B-line; cm "$(t 12)" "fix: correct A line"
put b.txt b1 b2 guard b3; put app.txt base1 base2 A-line-fixed B-line tail; cm "$(t 13)" "fix: add guard"
put note.txt n1 n2; cm "$(t 100)" "chore: tip"
ATTR="$R"
ck "DR-fx.1 fixture 점검: attr 머지 2개(first-parent)·fix 2개·끝 커밋 시각" "$(g log --merges --first-parent --format=%s main | wc -l | tr -d ' ')|$(g log --no-merges --format=%s main | grep -c '^fix')|$(g log -1 --format=%ct main)" "2|2|$(t 100)"

BEFORE=$(fp "$ATTR")
dr --repo "$ATTR"
ck "DR-1.a ★ A(수정된 줄 L 의 작성 FID) 결함 1" "$(row 20240102-aaa)" "2024-01-03 완료 1"
ck "DR-1.b ★ B(같은 파일의 다른 줄·다른 파일 — 줄만 추가한 fix 는 귀속 안 됨) 결함 0" "$(row 20240104-bbb)" "2024-01-05 완료 0"
ck "DR-1.c 표에 FID 두 행뿐(머지 아닌 커밋·기준 커밋은 행이 아니다)" "$(fids)" "20240102-aaa 20240104-bbb"
ck "DR-1.d 요약: 줄 추가 fix 는 '귀속 못 한' 으로도 안 센다 · blame 실패 0" "$(has "$(L1 2 1 50 0.5)" && echo y)|$(has "$(L2 0 0 0 0 0)" && echo y)" "y|y"
ck "DR-1.e rc 0 · stderr 비어 있음 · 한계 고지 줄" "$RC|$ERR|$(has "$NOTE" && echo y)" "0||y"
ck "DR-3.h 머리줄: base 이름·SHA 8자리·기간·기준시각(= base 끝 커밋 시각, 벽시계 아님)" "$(printf '%s\n' "$OUT" | head -1)" "$(HDR main "$ATTR" 30 2024-04-10)"
ck "DR-nfr.a 읽기 전용(NFR-3): 집계가 성공(rc 0)했고 실행 전후 .git 전 파일 지문 동일" "$RC|$([ "$(fp "$ATTR")" = "$BEFORE" ] && echo same)" "0|same"
ck "DR-nfr.b 임시 폴더 정리: 집계가 성공(rc 0)했고 전용 TMPDIR 에 남은 것 0" "$RC|$(leaks)" "0|0"
# 부재 단언의 양성 대조 — 같은 검사가 변화를 실제로 잡는다
cp -R "$ATTR" "$SB/attr-ctl"; git -C "$SB/attr-ctl" tag zz-ctl
[ "$(fp "$SB/attr-ctl")" != "$BEFORE" ] && ok "DR-nfr.c 양성 대조: 태그 1개만 만들어도 저장소 지문이 달라진다" || nope "DR-nfr.c 지문이 변화를 못 잡는다"
touch "$SB/tmp/ctl"; [ "$(leaks)" = 1 ] && ok "DR-nfr.d 양성 대조: 임시 폴더에 파일 1개면 누출 수 1" || nope "DR-nfr.d 누출 검사가 변화를 못 잡는다"; rm -f "$SB/tmp/ctl"
dr --repo "$ATTR"; first="$OUT"; dr --repo "$ATTR"
ck "DR-3.i 같은 base 면 다시 돌려도 출력 동일(빈 출력끼리의 일치는 통과가 아니다)" "$RC|$([ -n "$first" ] && [ "$OUT" = "$first" ] && echo same)" "0|same"
TZV=Asia/Seoul dr --repo "$ATTR"; ck "DR-3.j 타임존(Asia/Seoul)이 달라도 출력 동일" "$RC|$([ -n "$first" ] && [ "$OUT" = "$first" ] && echo same)" "0|same"
TZV=America/Los_Angeles dr --repo "$ATTR"; ck "DR-3.k 타임존(America/Los_Angeles)이 달라도 출력 동일" "$RC|$([ -n "$first" ] && [ "$OUT" = "$first" ] && echo same)" "0|same"
( cd "$ATTR" && unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE && TMPDIR="$SB/tmp" "$BASH_BIN" "$DR" ) > "$SB/dot.out" 2>&1
ck "DR-1.f --repo 생략 시 현재 폴더가 대상" "$(cat "$SB/dot.out")" "$first"

# ══ fixture 2: sql — 줄 단위 귀속의 파싱 함정 ═════════════════════════════════
#   sql.txt: A 가 '-- header'·'select 1;', B 가 'select 2;' · gone.sh: C · 'sp ace.txt': A
#   14일: '-- header' 줄 삭제 + 같은 파일 3행 수정(한 fix 에 hunk 2개 — 앞 hunk 의 삭제 줄이 '--- ' 로 보인다)
#   15일: 파일 삭제 fix · 16일: 이름에 공백이 있는 파일 수정 fix
mkrepo sql
put app.txt base; cm "$(t 0)" "chore: init"
brn feat/20240102-aaa; put sql.txt '-- header' 'select 1;'; put 'sp ace.txt' s1 s2; cm "$(t 1)" "feat: A"
mg "$(t 2)" feat/20240102-aaa "$(PR 1 feat/20240102-aaa)"
brn feat/20240103-bbb; put sql.txt '-- header' 'select 1;' 'select 2;'; cm "$(t 3)" "feat: B"
mg "$(t 4)" feat/20240103-bbb "$(PR 2 feat/20240103-bbb)"
brn feat/20240104-ccc; put gone.sh g1 g2; cm "$(t 5)" "feat: C"
mg "$(t 6)" feat/20240104-ccc "$(PR 3 feat/20240104-ccc)"
put sql.txt 'select 1;' 'select 2 ;'; cm "$(t 14)" "fix: sql"
rm -f "$R/gone.sh"; cm "$(t 15)" "fix: drop gone"
put 'sp ace.txt' s1x s2; cm "$(t 16)" "fix: spaced name"
put app.txt base tip; cm "$(t 100)" "chore: tip"
SQL="$R"
dr --repo "$SQL"
ck "DR-1.g ★ 한 fix 의 두 hunk(앞이 '-- ' 로 시작하는 줄 삭제) → 앞 hunk 는 A, 뒤 hunk 는 B 에 각각 귀속" "$(row 20240102-aaa)|$(row 20240103-bbb)" "2024-01-03 완료 2|2024-01-05 완료 1"
ck "DR-1.h ★ 파일을 통째로 지운 fix 도 그 파일을 쓴 FID 에 귀속" "$(row 20240104-ccc)" "2024-01-07 완료 1"
ck "DR-1.i 이 fixture 는 blame 실패 0 · 귀속 못 한 fix 0 (공백 이름 파일도 blame 된다)" "$(has "$(L2 0 0 0 0 0)" && echo y)" "y"
# 외부 호출 실패 — git blame 이 이 파일에서만 실패하게 하는 git 대역(계약: rc 128 + stderr 1줄, 나머지 호출은 진짜 git 으로 위임)
cat > "$SB/shim/git" <<EOF
#!/bin/sh
if [ -n "\${GITLOG:-}" ]; then printf '%s\n' "\$*" >> "\$GITLOG"; fi
if [ -n "\${FAIL_BLAME_FILE:-}" ]; then
  for a in "\$@"; do last=\$a; done
  case " \$* " in *" blame "*) if [ "\$last" = "\$FAIL_BLAME_FILE" ]; then echo "fatal: simulated blame failure" >&2; exit 128; fi ;; esac
fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$SB/shim/git"
OUT=$(cd "$SB" && PATH="$SB/shim:$PATH" FAIL_BLAME_FILE='sp ace.txt' TMPDIR="$SB/tmp" "$BASH_BIN" "$DR" --repo "$SQL" 2>"$SB/err"); RC=$?; ERR=$(cat "$SB/err")
ck "DR-1.j ★ blame 이 한 파일에서 실패 → 그 파일만 건너뛰고 집계 계속(rc 0) · 'blame 실패 1' · 다른 파일 결과는 그대로" "$RC|$(row 20240102-aaa)|$(row 20240103-bbb)|$(row 20240104-ccc)|$(has "$(L2 0 0 0 0 1)" && echo y)" "0|2024-01-03 완료 1|2024-01-05 완료 1|2024-01-07 완료 1|y"
ck "DR-1.k blame 실패는 stderr 로 새지 않는다(집계 일부일 뿐)" "$ERR" ""

# ══ fixture 3: win — AC-2 기간 · 자기 커밋 · 제외 경로 · 제목 ══════════════════
#   FID 'win' 은 src/w.sh(w1~w4)·tests/w_test.sh(t1,t2) 를 5일에 쓰고, 8일에 자기 fix(w1), 10일 머지
#   (b) 8일 FID 자신의 fix(…)  (c) 12일 테스트 파일만 고친 fix  (d) 13일 chore: 로 w3 수정  (a) 50일(머지+40일) w2 를 고친 fix
mkrepo win
put core.txt c1; cm "$(t 0)" "chore: init"
brn feat/20240102-win; put src/w.sh w1 w2 w3 w4; put tests/w_test.sh t1 t2; cm "$(t 5)" "feat: win"
put src/w.sh w1b w2 w3 w4; cm "$(t 8)" "fix(win): own fix before merge"
mg "$(t 10)" feat/20240102-win "$(PR 1 feat/20240102-win)"
put tests/w_test.sh t1b t2; cm "$(t 12)" "fix: test tweak"
put src/w.sh w1b w2 w3x w4; cm "$(t 13)" "chore: tweak w3"
put src/w.sh w1b w2late w3x w4; cm "$(t 50)" "fix: late"
put note.txt n; cm "$(t 200)" "chore: tip"
WIN="$R"
dr --repo "$WIN"
ck "DR-2.a ★ 기본 30일: (a) 머지+40일 (b) 머지 전 자기 fix (c) 테스트만 고친 fix (d) chore: — 넷 다 안 센다" "$(row 20240102-win)" "2024-01-11 완료 0"
ck "DR-2.b 안 센 fix 는 '귀속 못 한' 으로도 안 센다(귀속은 됐고 기간·제외·제목에서 걸러졌다)" "$(has "$(L2 0 0 0 0 0)" && echo y)" "y"
dr --repo "$WIN" --window-days 60
ck "DR-2.c ★ --window-days 60 이면 (a) 하나만 센다 — (b)(c)(d) 는 여전히 0" "$(row 20240102-win)|$(printf '%s\n' "$OUT" | head -1 | sed 's/ 기준시각.*//')" "2024-01-11 완료 1|defect-rate: base=main@$(git -C "$WIN" rev-parse main | cut -c1-8) 기간=60일"
dr --repo "$WIN" --window-days 40; ck "DR-2.d 경계: 머지+정확히 40일 = 센다(이하)" "$(row 20240102-win)" "2024-01-11 완료 1"
dr --repo "$WIN" --window-days 39; ck "DR-2.e 경계: 머지+40일은 39일 기간 밖" "$(row 20240102-win)" "2024-01-11 완료 0"

# 시각 경계(초 단위): 머지 시각 M 에 대해 M(제외) · M+1초(포함) · M+30일(포함) · M+30일+1초(제외)
mkrepo edge
put core.txt c1; cm "$(t 0)" "chore: init"
brn feat/20240102-edge; put src/e.sh e1 e2 e3 e4; cm "$(t 5)" "feat: edge"
mg "$(t 10)" feat/20240102-edge "$(PR 1 feat/20240102-edge)"
put src/e.sh e1x e2 e3 e4;   cm "$(t 10)" "fix: at merge time"
put src/e.sh e1x e2x e3 e4;  cm "$(t 10 1)" "fix: merge plus 1s"
put src/e.sh e1x e2x e3x e4; cm "$(t 40)" "fix: merge plus 30d"
put src/e.sh e1x e2x e3x e4x; cm "$(t 40 1)" "fix: merge plus 30d 1s"
put note.txt n; cm "$(t 200)" "chore: tip"
dr --repo "$R"
ck "DR-2.f ★ 시각 경계: 머지 시각 초과 ~ +30일 이하만 센다(= M+1초·M+30일 두 건)" "$(row 20240102-edge)" "2024-01-11 완료 2"

# 제외 경로: 경로 규칙 하나하나 + 닮았지만 코드인 경로(양성 대조)
EXCLUDED="tests/a.sh test/b.sh pkg/__tests__/c.js scripts/test-d.sh lib/test_e.py lib/f.test.js lib/g.spec.ts CHANGELOG.md docs/CHANGELOG-ko.md .specops/h.md"
COUNTED="src/latest/i.sh contest.sh docs/.specops/j.md testing/k.sh lib/l.tests.js src/test-ish/m.sh"
mkrepo excl
put core.txt c; cm "$(t 0)" "chore: init"
brn feat/20240102-xx; for f in $EXCLUDED $COUNTED; do put "$f" orig; done; cm "$(t 1)" "feat: xx"
mg "$(t 2)" feat/20240102-xx "$(PR 1 feat/20240102-xx)"
brn feat/20240103-docs; put tests/y.sh y1; put docs/CHANGELOG-y.md c1; put .specops/y.md y; cm "$(t 2 60)" "feat: docs only"
mg "$(t 3)" feat/20240103-docs "$(PR 2 feat/20240103-docs)"
brn feat/20240104-lk; put tests/z.sh z1; put src/latest/z.sh z1; cm "$(t 3 60)" "feat: lookalike"
mg "$(t 4)" feat/20240104-lk "$(PR 3 feat/20240104-lk)"
i=0; for f in $EXCLUDED $COUNTED; do i=$((i+1)); put "$f" changed; cm "$(t $((10+i)))" "fix: change $f"; done
put tests/y.sh y2; cm "$(t 40)" "fix: y tests"
put note.txt n; cm "$(t 100)" "chore: tip"
dr --repo "$R"
ck "DR-2.g ★ 제외 경로 10종(tests/ test/ __tests__/ test-* test_* *.test.* *.spec.* CHANGELOG* .specops/)은 안 세고, 닮았지만 코드인 6종은 센다 → 6" "$(row 20240102-xx)" "2024-01-03 완료 6"
ck "DR-2.h ★ 제외 경로만 바꾼 FID(tests·CHANGELOG*·.specops)는 '코드변경없음' — 값 칸 '-'" "$(row 20240103-docs)" "2024-01-04 코드변경없음 -"
ck "DR-2.i 제외 경로 + 닮은 코드 경로를 함께 바꾼 FID 는 코드 변경이 있다(완료)" "$(row 20240104-lk)" "2024-01-05 완료 0"
ck "DR-2.j 요약: 완료 2(xx·lk) · 결함 1 (50%) · 평균 3.0 · 코드변경없음 1 · 제외 경로만 고친 fix 는 귀속 못 한 에도 안 센다" "$(has "$(L1 2 1 50 3.0)" && echo y)|$(has "$(L2 0 1 0 0 0)" && echo y)" "y|y"

# 제목 문법: fix: · fix(…) · fix! 만 센다
mkrepo ttl
put core.txt c; cm "$(t 0)" "chore: init"
brn feat/20240107-ttl; put t.sh t1 t2 t3 t4 t5 t6 t7 t8 t9 t10; cm "$(t 1)" "feat: ttl"
mg "$(t 2)" feat/20240107-ttl "$(PR 1 feat/20240107-ttl)"
i=0
for title in "fix: a" "fix(scope): b" "fix!: c" "fixup: d" "Fix: e" "chore: fix f" "refix: g" "fixes: h" "docs(fix): i" "chore: fix(x): j"; do
  i=$((i+1)); put t.sh $(seq 1 10 | awk -v n="$i" '{ if ($1 <= n) print "t" $1 "x"; else print "t" $1 }'); cm "$(t $((3+i)))" "$title"
done
put note.txt n; cm "$(t 100)" "chore: tip"
dr --repo "$R"
ck "DR-2.k ★ 제목이 fix: · fix(…): · fix!: 인 3건만 센다(fixup:·Fix:·chore: fix·refix:·fixes:·docs(fix):·chore: fix(x): 7건은 안 센다)" "$(row 20240107-ttl)" "2024-01-03 완료 3"

# ══ fixture 4: sum — AC-3 관찰중 · 요약 · 인식 못 한 머지 · 귀속 못 한 fix · --since ══
#   현재(base 끝)=100일(2024-04-10), 기간 30일. old1(5일)·old2(6일)·docs(15일, 테스트·CHANGELOG 만)·hotfix(25일, FID 형식 아님)
#   edge(정확히 70일 = 현재-30일 → 완료) · obs(70일+1초 → 관찰중)
mkrepo sum
put core.txt k1 k2; cm "$(t 0)" "chore: init"
brn feat/20240102-old1; put src/o1.sh o1a o1b o1c; cm "$(t 4)" "feat: old1"
mg "$(t 5)" feat/20240102-old1 "$(PR 1 feat/20240102-old1)"
brn feat/20240103-old2; put src/o2.sh o2a o2b; cm "$(t 5 60)" "feat: old2"
mg "$(t 6)" feat/20240103-old2 "$(PR 2 feat/20240103-old2)"
put src/o1.sh o1ax o1b o1c; cm "$(t 10)" "fix: o1 bug"
put src/o2.sh o2ax o2b; cm "$(t 12)" "fix(o2): o2 bug"
brn feat/20240108-docs; put tests/n.sh n1 n2; put CHANGELOG.md c1; cm "$(t 14)" "docs: tests only"
mg "$(t 15)" feat/20240108-docs "$(PR 3 feat/20240108-docs)"
put tests/n.sh n1x n2; cm "$(t 17)" "fix: docs test"
brn hotfix; put src/hot.sh h1 h2; cm "$(t 24)" "hotfix: direct"
mg "$(t 25)" hotfix "Merge branch 'hotfix'"
put src/hot.sh h1x h2; cm "$(t 30)" "fix: hot"
put src/o1.sh o1ax o1b o1c o1d; cm "$(t 31)" "fix: add-only"
brn feat/20240106-edge; put src/edge.sh e1; cm "$(t 69)" "feat: edge"
mg "$(t 70)" feat/20240106-edge "$(PR 4 feat/20240106-edge)"
brn feat/20240105-obs; put src/obs.sh ob1; cm "$(t 69 60)" "feat: obs"
mg "$(t 70 1)" feat/20240105-obs "$(PR 5 feat/20240105-obs)"
put note.txt n; cm "$(t 100)" "chore: tip"
SUM="$R"
ck "DR-fx.2 fixture 점검: sum 의 first-parent 머지 6개(FID 5 + hotfix 1)·끝 커밋 시각" "$(g log --merges --first-parent --format=%s main | wc -l | tr -d ' ')|$(g log -1 --format=%ct main)" "6|$(t 100)"
BEFORE=$(fp "$SUM")
dr --repo "$SUM"
ck "DR-3.a ★ FID 표 5행뿐 — hotfix(FID 형식 아님)는 행이 아니다" "$(fids)" "20240102-old1 20240103-old2 20240105-obs 20240106-edge 20240108-docs"
ck "DR-3.b 머지 30일 미경과(70일+1초)는 '관찰중' — 값 '-'" "$(row 20240105-obs)" "2024-03-11 관찰중 -"
ck "DR-3.c ★ 경계: 정확히 30일 지난 머지는 완료(관찰중 아님)" "$(row 20240106-edge)" "2024-03-11 완료 0"
ck "DR-3.d 테스트·CHANGELOG 만 바꾼 FID 는 '코드변경없음'" "$(row 20240108-docs)" "2024-01-16 코드변경없음 -"
ck "DR-3.e 일반 FID 결함 수(줄 추가만 한 fix 는 old1 에 안 붙는다)" "$(row 20240102-old1)|$(row 20240103-old2)" "2024-01-06 완료 1|2024-01-07 완료 1"
ck "DR-3.f ★ 요약 1줄: 분모는 완료 3 만 — 완료 3 · 결함 2 (67%) · 평균 0.7" "$(has "$(L1 3 2 67 0.7)" && echo y)" "y"
ck "DR-3.g ★ 요약 2줄: 관찰중 1 · 코드변경없음 1 · 인식 못 한 머지 1 · 귀속 못 한 fix 1 · blame 실패 0" "$(has "$(L2 1 1 1 1 0)" && echo y)" "y"
ck "DR-3.h2 머리줄(base·SHA 8자리·기간·기준시각)·한계 고지·rc 0·stderr 비어 있음" "$(printf '%s\n' "$OUT" | head -1)|$(has "$NOTE" && echo y)|$RC|$ERR" "$(HDR main "$SUM" 30 2024-04-10)|y|0|"
ck "DR-3.l 읽기 전용: 집계 성공(rc 0) · 실행 전후 지문 동일 · 임시 폴더 누출 0" "$RC|$([ "$(fp "$SUM")" = "$BEFORE" ] && echo same)|$(leaks)" "0|same|0"
dr --repo "$SUM" --since 20240107
ck "DR-3.m ★ --since 20240107(머지일 이상): old1(01-06) 만 빠진다 · 분모 완료 2(old2·edge) · 인식 못 한 머지·귀속 못 한 fix 는 거르지 않는다" "$(fids)|$(has "$(L1 2 1 50 0.5)" && echo y)|$(has "$(L2 1 1 1 1 0)" && echo y)" "20240103-old2 20240105-obs 20240106-edge 20240108-docs|y|y"
dr --repo "$SUM" --since 20240106
ck "DR-3.n 경계: --since 가 머지일과 같은 날이면 포함(이상)" "$(fids)" "20240102-old1 20240103-old2 20240105-obs 20240106-edge 20240108-docs"
dr --repo "$SUM" --since 20240311
ck "DR-3.o ★ --since 20240311: edge·obs 만 · 완료 1 · 결함 0 (0%) · 평균 0.0" "$(fids)|$(has "$(L1 1 0 0 0.0)" && echo y)|$(has "$(L2 1 0 1 1 0)" && echo y)" "20240105-obs 20240106-edge|y|y"
dr --repo "$SUM" --since 20240312
ck "DR-3.p ★ --since 로 전부 제외 → rc 0 + 원인 줄('--since 로 전부 제외') · 다른 원인('FID 머지 0건')으로 위장하지 않는다 · 표 없음" "$RC|$(printf '%s\n' "$OUT" | grep -c -- '--since 로 전부 제외')|$(printf '%s\n' "$OUT" | grep -c 'FID 머지 0건')|$(printf '%s\n' "$OUT" | grep -c '^FID ')" "0|1|0|0"
dr --repo "$SUM" --window-days 6
ck "DR-3.q 기간 인자가 관찰중 판정에 쓰인다: --window-days 6 이면 obs 는 완료 · 머리줄 6일 · old1(5일)·old2(6일 정확히) 둘 다 센다 → 완료 4 · 결함 2 (50%) · 평균 0.5" "$(row 20240105-obs)|$(printf '%s\n' "$OUT" | head -1 | grep -c '기간=6일')|$(has "$(L1 4 2 50 0.5)" && echo y)|$(has "$(L2 0 1 1 1 0)" && echo y)" "2024-03-11 완료 0|1|y|y"

# 결함이 한 건도 없는 저장소 — 'FID 머지 0건' 으로 오진하지 않고 FID 행을 보여 준다 (hits 가 비면 awk NR==FNR 이 병합 파일까지 삼킨다)
mkrepo nohit
put core.txt c; cm "$(t 0)" "chore: init"
brn feat/20240102-calm; put src/c.sh c1 c2; cm "$(t 1)" "feat: calm"
mg "$(t 2)" feat/20240102-calm "$(PR 1 feat/20240102-calm)"
put note.txt n; cm "$(t 100)" "chore: tip"
dr --repo "$R"
ck "DR-3.s ★ fix 가 전혀 없어도 FID 행(완료 0)과 요약을 낸다 — 'FID 머지 0건' 오진 금지" "$(row 20240102-calm)|$(printf '%s\n' "$OUT" | grep -c 'FID 머지 0건')|$(has "$(L1 1 0 0 0.0)" && echo y)" "2024-01-03 완료 0|0|y"
# 전부 관찰중(spec §2 '대상 0건' 원인 3종 중 하나 — AC 에는 없다): 기간 365일이면 sum 의 FID 5개가 모두 미경과. 일반 실행에는 이 줄이 없다(양성 대조)
dr --repo "$SUM" --window-days 365
ck "DR-3.r (spec) 전부 관찰중 → 원인 줄 1개 · 일반 실행(DR-3.g 의 출력)엔 없다" "$(printf '%s\n' "$OUT" | grep -c '전부 관찰중')|$(dr --repo "$SUM"; printf '%s\n' "$OUT" | grep -c '전부 관찰중')" "1|0"

# ══ fixture 5: misc — 머지 여러 번 · first-parent · 한 fix 가 여러 FID/줄 · 도달성 ════
#   pp(3일) qq(4일) multi(5일, 24일에 같은 제목으로 한 번 더) outer(7일, 안에 중첩 머지 inner) ttl 없음 · FID 형식 아닌 머지 1
#   10일 fix 하나가 pp 의 두 줄 + qq 한 줄 → pp 1·qq 1(줄 수가 아니라 FID 당 1건) · 11일 qq 한 줄 더 → qq 2
mkrepo misc
put core.txt k1 k2; cm "$(t 0)" "chore: init"
brn feat/20240103-pp; put p.sh p1 p2 p3; cm "$(t 2)" "feat: pp"
mg "$(t 3)" feat/20240103-pp "$(PR 1 feat/20240103-pp)"
brn feat/20240104-qq; put q.sh q1 q2; cm "$(t 3 60)" "feat: qq"
mg "$(t 4)" feat/20240104-qq "$(PR 2 feat/20240104-qq)"
brn feat/20240102-multi; put m1.sh m1a m1b m1c; cm "$(t 4 60)" "feat: multi 1"
mg "$(t 5)" feat/20240102-multi "$(PR 3 feat/20240102-multi)"
brn feat/20240105-outer; put o.sh o1; cm "$(t 5 60)" "feat: outer"
brn fix/20240106-inner feat/20240105-outer; put i.sh i1; cm "$(t 6)" "feat: inner"
g checkout -q feat/20240105-outer; _dt "$(t 6 60)"; g merge -q --no-ff fix/20240106-inner -m "$(PR 9 fix/20240106-inner)"
mg "$(t 7)" feat/20240105-outer "$(PR 4 feat/20240105-outer)"
brn feat/20240107-ttl; put t.sh t1 t2 t3; cm "$(t 7 60)" "feat: ttl"
mg "$(t 8)" feat/20240107-ttl "$(PR 5 feat/20240107-ttl)"
brn feat/no-date-slug; put u.sh u1; cm "$(t 8 60)" "feat: no date"
mg "$(t 9)" feat/no-date-slug "$(PR 6 feat/no-date-slug)"
put p.sh p1x p2x p3; put q.sh q1x q2; cm "$(t 10)" "fix: cross"
put q.sh q1x q2x; cm "$(t 11)" "fix: second"
put t.sh t1x t2 t3; cm "$(t 12)" "fix: t1"
put t.sh t1x t2x t3; cm "$(t 13)" "fix: t2"
put t.sh t1x t2x t3x; cm "$(t 14)" "fix: t3"
put core.txt k1x k2; cm "$(t 21)" "fix: core"
put i.sh i1x; cm "$(t 22)" "fix: inner line"
brn fix/dangling main; put p.sh p1x p2x p3y; cm "$(t 23)" "fix: dangling (never merged)"; g checkout -q main
g checkout -q feat/20240102-multi; put m2.sh m2a m2b m2c; cm "$(t 23 60)" "feat: multi 2"
mg "$(t 24)" feat/20240102-multi "$(PR 7 feat/20240102-multi)"
put m1.sh m1ax m1b m1c; put m2.sh m2ax m2b m2c; cm "$(t 30)" "fix: multi both"
put m2.sh m2ax m2bx m2c; cm "$(t 36)" "fix: multi m2 only"
put m1.sh m1ax m1bx m1c; cm "$(t 37)" "fix: multi m1 only"
put note.txt n; cm "$(t 120)" "chore: tip"
MISC="$R"
ck "DR-fx.3 fixture 점검: misc first-parent 머지 7개 · 도달 불가 fix 브랜치 존재" "$(g log --merges --first-parent --format=%s main | wc -l | tr -d ' ')|$(g branch --list 'fix/dangling' | grep -c dangling)|$(g log main --format=%s | grep -c dangling)" "7|1|0"
dr --repo "$MISC"
ck "DR-5.a ★ 표 5행 — 중첩 머지(inner)는 행이 아니고 FID 하나가 한 행(multi 두 번 머지)" "$(fids)" "20240102-multi 20240103-pp 20240104-qq 20240105-outer 20240107-ttl"
ck "DR-5.b ★ 한 fix 가 같은 FID 의 두 줄 + 다른 FID 의 한 줄을 고쳐도 FID 당 1건: pp 1 · qq 1+1(다른 fix) = 2" "$(row 20240103-pp)|$(row 20240104-qq)" "2024-01-04 완료 1|2024-01-05 완료 2"
ck "DR-5.c ★ 같은 FID 두 번 머지: 행은 1개·머지일은 첫 머지 · 기간은 줄을 쓴 커밋이 든 머지 시각부터 — 동시에 두 머지의 줄을 고친 fix 1건 + 둘째 머지의 줄만 고친 fix(첫 머지+31일) 1건, 첫 머지의 줄만 고친 fix(첫 머지+32일) 는 0 → 2" "$(row 20240102-multi)|$(printf '%s\n' "$OUT" | awk '$1 == "20240102-multi"' | wc -l | tr -d ' ')" "2024-01-06 완료 2|1"
ck "DR-5.d first-parent 만 따라간다: 중첩 머지 안의 줄은 바깥 FID 에 귀속(outer 1) · 도달 불가 브랜치의 fix 는 안 센다(pp 는 1 그대로)" "$(row 20240105-outer)|$(row 20240103-pp)" "2024-01-08 완료 1|2024-01-04 완료 1"
ck "DR-5.e 제목 문법 fix: 3건 (ttl t1·t2·t3) → ttl 3" "$(row 20240107-ttl)" "2024-01-09 완료 3"
ck "DR-5.f ★ 요약: 완료 5 · 결함 5 (100%) · 평균 1.8 / 인식 못 한 머지 1(날짜 없는 FID 제목) · 귀속 못 한 fix 1(core.txt — 이전 역사) · 기간 밖 fix·도달 불가 fix 는 귀속 못 한 에 안 센다" "$(has "$(L1 5 5 100 1.8)" && echo y)|$(has "$(L2 0 0 1 1 0)" && echo y)" "y|y"
ck "DR-5.g 머리줄 base=main" "$(printf '%s\n' "$OUT" | head -1)" "$(HDR main "$MISC" 30 2024-04-30)"

# ══ fixture 6: perf — 외부 프로세스 수가 줄 수에 비례하지 않는다 (NFR-1) ══════════
#   한 fix 가 big.txt 의 떨어진 20곳(= hunk 20개)을 고치고, 다른 fix 가 파일 둘(big.txt 1곳 + small.txt)을 고친다 → git blame 은 (파일 수) = 1 + 2 = 3 번
mkrepo perf
put core.txt c; cm "$(t 0)" "chore: init"
brn feat/20240102-big; put big.txt $(seq 1 60 | sed 's/^/L/'); put small.txt s1; cm "$(t 1)" "feat: big"
mg "$(t 2)" feat/20240102-big "$(PR 1 feat/20240102-big)"
put big.txt $(seq 1 60 | awk '{ if (($1 - 1) % 3 == 0 && $1 <= 58) print "L" $1 "x"; else print "L" $1 }'); cm "$(t 5)" "fix: twenty hunks"
put big.txt $(seq 1 60 | awk '{ if (($1 - 1) % 3 == 0 && $1 <= 58) print "L" $1 "x"; else if ($1 == 2) print "L2y"; else print "L" $1 }'); put small.txt s1x; cm "$(t 6)" "fix: two files"
put note.txt n; cm "$(t 100)" "chore: tip"
: > "$SB/gitcalls"
OUT=$(cd "$SB" && PATH="$SB/shim:$PATH" GITLOG="$SB/gitcalls" TMPDIR="$SB/tmp" "$BASH_BIN" "$DR" --repo "$R" 2>"$SB/err"); RC=$?
ck "DR-6.a 집계 값: big 은 fix 2건" "$RC|$(row 20240102-big)" "0|2024-01-03 완료 2"
ck "DR-6.b ★ git blame 호출 수 = 고친 (fix, 파일) 쌍 수 3 — hunk 20개를 한 번의 blame(-L 여러 개)으로 (hunk 마다 부르면 22)" "$(grep -c ' blame ' "$SB/gitcalls")" "3"

# ══ 기본 base: origin/main 우선, --base 로 덮어쓴다 ═══════════════════════════════
mkrepo bs
put app.txt a1; cm "$(t 0)" "chore: init"
brn feat/20240102-bb; put b.sh b1; cm "$(t 1)" "feat: bb"
mg "$(t 2)" feat/20240102-bb "$(PR 1 feat/20240102-bb)"
put b.sh b1x; cm "$(t 5)" "fix: bb"
put app.txt a1 a2; cm "$(t 40)" "chore: tip"
BS="$R"
git clone -q "file://$BS" "$SB/bs-clone" 2>/dev/null
R="$SB/bs-clone"; brn feat/20240111-dd; put d.sh d1; cm "$(t 49)" "feat: dd"; mg "$(t 50)" feat/20240111-dd "$(PR 2 feat/20240111-dd)"   # 로컬에만 있는 머지(origin/main 에 없음)
dr --repo "$SB/bs-clone"
ck "DR-b.a ★ --base 생략: origin/main 이 main 보다 우선 — 로컬에만 있는 dd 는 안 보이고 머리줄이 origin/main" "$(fids)|$(printf '%s\n' "$OUT" | head -1 | cut -d' ' -f1-2)" "20240102-bb|defect-rate: base=origin/main@$(git -C "$SB/bs-clone" rev-parse origin/main | cut -c1-8)"
dr --repo "$SB/bs-clone" --base main
ck "DR-b.b ★ --base main 이면 로컬 main 기준 — dd 가 보인다(관찰중)" "$(fids)|$(row 20240111-dd)|$(printf '%s\n' "$OUT" | head -1 | cut -d' ' -f1-2)" "20240102-bb 20240111-dd|2024-02-20 관찰중 -|defect-rate: base=main@$(git -C "$SB/bs-clone" rev-parse main | cut -c1-8)"
mkrepo onlymaster master
put app.txt a1; cm "$(t 0)" "chore: init"
OM="$R"
err_case "DR-b.c main·origin/main 이 없고 --base 도 없으면 rc 2" --repo "$OM"
dr --repo "$OM" --base master; ck "DR-b.d --base master 로 지정하면 같은 저장소가 rc 0 (FID 머지 0건)" "$RC" "0"

# ══ AC-4: 오류·인자 — rc 2 · stdout 비어 있음 · stderr 1줄 ═══════════════════════
mkdir -p "$SB/nogit"; err_case "DR-4.a ★ git 저장소가 아닌 폴더 → rc 2" --repo "$SB/nogit"
err_case "DR-4.a2 없는 경로 → rc 2" --repo "$SB/does-not-exist"
err_case "DR-4.b ★ 없는 --base → rc 2" --repo "$ATTR" --base no-such-ref
err_case "DR-4.b2 커밋이 하나도 없는 저장소 → rc 2" --repo "$(mkrepo empty; echo "$R")"
git clone -q --depth 1 "file://$SUM" "$SB/shallow" 2>/dev/null
ck "DR-fx.4 fixture 점검: shallow 복제가 실제로 shallow 다" "$(git -C "$SB/shallow" rev-parse --is-shallow-repository)" "true"
err_case "DR-4.c ★ 얕은 복제 → rc 2" --repo "$SB/shallow"
git clone -q "file://$SUM" "$SB/fullclone" 2>/dev/null
dr --repo "$SB/fullclone"; ck "DR-4.c2 양성 대조: 같은 저장소의 전체 복제는 rc 0 (origin/main 기준)" "$RC|$(row 20240106-edge)" "0|2024-03-11 완료 0"
for v in 0 366 abc -5 1.5 30x 1000 ""; do err_case "DR-4.d ★ --window-days '$v' → rc 2" --repo "$ATTR" --window-days "$v"; done
err_case "DR-4.d2 --window-days 값 없음 → rc 2" --repo "$ATTR" --window-days
dr --repo "$ATTR" --window-days 1;   ck "DR-4.e 경계 --window-days 1 → rc 0 · 머리줄 1일" "$RC|$(printf '%s\n' "$OUT" | head -1 | grep -c '기간=1일')" "0|1"
dr --repo "$ATTR" --window-days 365; ck "DR-4.f 경계 --window-days 365 → rc 0 · 머리줄 365일" "$RC|$(printf '%s\n' "$OUT" | head -1 | grep -c '기간=365일')" "0|1"
for v in 2024011 abcdefgh 202401011 2024-01-01 ""; do err_case "DR-4.g ★ --since '$v' → rc 2" --repo "$ATTR" --since "$v"; done
err_case "DR-4.g2 --since 값 없음 → rc 2" --repo "$ATTR" --since
dr --repo "$ATTR" --since 20240101; ck "DR-4.h --since 20240101 → rc 0" "$RC" "0"
err_case "DR-4.i 알 수 없는 옵션 → rc 2" --repo "$ATTR" --bogus
err_case "DR-4.j 위치 인자 → rc 2" "$ATTR"
err_case "DR-4.k --repo 값 없음 → rc 2" --repo
err_case "DR-4.l --base 값 없음 → rc 2" --repo "$ATTR" --base

# FID 머지 0건인 정상 저장소 → rc 0 + 원인 줄 (squash 머지는 머지 커밋이 아니라 인식하지 못함)
mkrepo zero
put app.txt a1 a2; cm "$(t 0)" "chore: init"
put app.txt a1x a2; cm "$(t 3)" "feat: squashed thing (#12)"
put app.txt a1y a2; cm "$(t 5)" "fix: direct"
Z="$R"
dr --repo "$Z"
ck "DR-4.m ★ FID 머지 0건 → rc 0 · 원인 1줄 · 표 없음 · 머리줄 있음" "$RC|$(has '대상 없음: FID 머지 0건 (squash·rebase 머지는 인식하지 못함)' && echo y)|$(printf '%s\n' "$OUT" | grep -c '^FID ')|$(printf '%s\n' "$OUT" | head -1 | cut -d' ' -f1-2)|$ERR" "0|y|0|defect-rate: base=main@$(git -C "$Z" rev-parse main | cut -c1-8)|"

finish
