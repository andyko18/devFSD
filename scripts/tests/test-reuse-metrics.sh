#!/usr/bin/env bash
# test-reuse-metrics.sh — 재사용·복제 관측(scripts/reuse-metrics.sh) 계약 (FID 20261013-reuse-dup-metrics)
# 방식: mktemp 아래 fixture git 저장소를 만들어 측정한다 — 실 트리 쓰기 0.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
RM="$PLUGIN/scripts/reuse-metrics.sh"
RUN="$PLUGIN/scripts/_internal/run-verification.sh"
[ -f "$RM" ] || nope "존재" "scripts/reuse-metrics.sh 부재"

ROOT=$(mktemp -d) || exit 1
trap 'rm -rf "$ROOT"' EXIT
FID=20260101-demo
unset SPECOPS_ROOT SPECOPS_REUSE_DUP_WINDOW SPECOPS_REUSE_MAX_FILES SPECOPS_REUSE_MAX_CORPUS_LINES

# 8줄 블록 — 태그가 같으면 같은 블록이다(창 6줄보다 길어야 복제로 잡힌다)
blk() { local i; for i in 1 2 3 4 5 6 7 8; do echo "    step_$1_$i = compute(value_$i, $1)"; done; }
# 기준 커밋(main)만 있는 fixture 저장소 → 경로. 이후 호출자가 feat 브랜치에서 변경을 얹는다.
mk_repo() {
  local r; r=$(mktemp -d "$ROOT/repo.XXXXXX") || return 1
  ( cd "$r" && git init -q -b main && git config user.email t@t && git config user.name t \
    && mkdir -p src lib tests && { echo "def existing():"; blk old; } > src/old.py \
    && echo "export function formatDate(d) { return d.toISOString() }" > lib/dates.js \
    && git add -A && git commit -qm base && git checkout -qb "feat/$FID" && mkdir -p ".specops/$FID" ) >/dev/null 2>&1 || return 1
  printf '%s\n' "$r"
}
commit_all() { ( cd "$1" && git add -A && git commit -qm work ) >/dev/null 2>&1; }
J() { jq -r "$2" "$1/.specops/$FID/reuse-metrics.json" 2>/dev/null; }   # $1=저장소 $2=jq 식

if ! command -v jq >/dev/null 2>&1; then
  skip "jq 미설치 — 기록 내용 대조 케이스 전체 미실행 (PASS 집계 제외)"
  finish; exit $?
fi

# ── R1: 변경 규모를 구현·테스트·문서로 나눠 센다 (AC-1) ──
R=$(mk_repo)
printf 'a = 1\nb = 2\nc = 3\n' > "$R/src/impl.py"                 # 구현 +3
printf 'def t():\n    assert True\n' > "$R/tests/test_impl.py"     # 테스트 +2
printf '# 제목\n한 줄\n둘째 줄\n넷째\n' > "$R/README.md"            # 문서 +4
( cd "$R" && git rm -q lib/dates.js ) >/dev/null 2>&1              # 파일 삭제 — 구현 -1
{ echo "def existing():"; blk old | sed -n '1,5p'; } > "$R/src/old.py"   # 기존 파일에서 3줄 삭제 — 구현 -3
printf '{"lockfileVersion": 3}\n' > "$R/package-lock.json"          # 생성물 — 규모에 넣지 않는다
commit_all "$R"
out=$( cd "$R" && bash "$RM" measure "$FID" 2>&1 ); rc=$?
{ [ "$rc" = 0 ] && [ "$(J "$R" '.size.status')" = measured ] && [ "$(J "$R" '[.size.impl.added,.size.test.added,.size.doc.added]|join(",")')" = "3,2,4" ] \
  && [ "$(J "$R" '.size.impl.deleted')" = 4 ] && [ "$(J "$R" '.size.generated_skipped')" = 1 ] \
  && [ "$(J "$R" '.size.files')" = 5 ] && [ -n "$(J "$R" '.base // empty')" ] && [ -n "$(J "$R" '.head // empty')" ] && [ -n "$(J "$R" '.ts // empty')" ]; } \
  && ok "R1 변경 규모: 구현 +3/-4(파일 삭제 1 + 줄 삭제 3) · 테스트 +2 · 문서 +4 · 생성물 1개 제외 · 분기점·HEAD·시각 기록" || nope "R1" "rc=$rc out=$out json=$(cat "$R/.specops/$FID/reuse-metrics.json" 2>/dev/null)"

# ── R2: 복제 두 방향 + 방식 기록 (AC-2) ──
R=$(mk_repo); { echo "def a():"; blk new; echo "def b():"; blk new; } > "$R/src/new.py"; commit_all "$R"
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.dup.status')" = measured ] && [ "$(J "$R" '.dup.dup_within_new')" = 16 ] && [ "$(J "$R" '.dup.existing.dup_of_existing')" = 0 ] && [ "$(J "$R" '.dup.method')" = builtin ]; } \
  && ok "R2.a 새 코드끼리 복제: 8줄 블록 2회 → 16줄 · 기존 코드 복제 0 · method=builtin" || nope "R2.a" "$(J "$R" '.dup')"
R=$(mk_repo); { echo "def c():"; blk old; } > "$R/src/copy.py"; commit_all "$R"
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.dup.existing.status')" = measured ] && [ "$(J "$R" '.dup.existing.dup_of_existing')" = 8 ] && [ "$(J "$R" '.dup.dup_within_new')" = 0 ]; } \
  && ok "R2.b 기존 코드 복제: 저장소에 있던 8줄 블록을 복사 → 8줄 · 새 코드끼리 0" || nope "R2.b" "$(J "$R" '.dup')"
R=$(mk_repo); { echo "def d():"; blk uniq1; echo "def e():"; blk uniq2; } > "$R/src/clean.py"; commit_all "$R"
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.dup.status')" = measured ] && [ "$(J "$R" '.dup.dup_within_new')" = 0 ] && [ "$(J "$R" '.dup.existing.dup_of_existing')" = 0 ] && [ "$(J "$R" '.dup.new_lines')" = 18 ]; } \
  && ok "R2.c 복제 없음: 둘 다 0 이 measured 로(미측정과 구분) · 새 코드 18줄" || nope "R2.c" "$(J "$R" '.dup')"
{ [ "$(J "$R" '.jscpd.status')" = not_applicable ] || command -v jscpd >/dev/null 2>&1; } \
  && ok "R2.d jscpd 가 없으면 jscpd 칸은 not_applicable(숫자 아님)" || nope "R2.d" "$(J "$R" '.jscpd')"
R=$(mk_repo); ( cd "$R" && git mv src/old.py src/renamed.py ) >/dev/null 2>&1; commit_all "$R"
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.dup.existing.status')" = measured ] && [ "$(J "$R" '.dup.existing.dup_of_existing')" = 0 ] && [ "$(J "$R" '.dup.new_lines')" = 9 ] && [ "$(J "$R" '[.size.impl.added,.size.impl.deleted]|join("/")')" = "9/9" ]; } \
  && ok "R2.g 파일 이름만 바꾼 것은 기존 코드 복제가 아니다(0) — 같은 diff 에서 지운 줄과 같은 창은 뺀다 · 규모는 +9/-9" || nope "R2.g" "$(J "$R" '.dup') $(J "$R" '.size')"
R=$(mk_repo); { echo "def existing():"; echo "    if flag:"; blk old | sed 's/^/    /'; } > "$R/src/old.py"; commit_all "$R"
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.dup.existing.dup_of_existing')" = 0 ] && [ "$(J "$R" '.dup.new_lines')" = 9 ]; } \
  && ok "R2.h 기존 블록을 if 로 감싸 들여쓰기만 바뀐 것은 복제가 아니다(0)" || nope "R2.h" "$(J "$R" '.dup')"
# 분기점 커밋에 export-ignore 가 걸린 파일도 기존 코드다 — 코퍼스에서 조용히 빠지면 실제 복사가 0 으로 나온다.
R=$(mk_repo)
( cd "$R" && git checkout -q main && echo "src/old.py export-ignore" > .gitattributes && git add -A && git commit -qm attrs && git checkout -q -B "feat/$FID" ) >/dev/null 2>&1
{ echo "def c():"; blk old; } > "$R/src/copy.py"; commit_all "$R"
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.dup.existing.status')" = measured ] && [ "$(J "$R" '.dup.existing.dup_of_existing')" = 8 ] && [ "$(J "$R" '.dup.existing.corpus_files')" -ge 1 ] 2>/dev/null; } \
  && ok "R2.i export-ignore 가 걸린 기존 파일의 8줄 블록을 복사 → 8줄(코퍼스에서 빠지지 않는다)" || nope "R2.i" "$(J "$R" '.dup')"
# jscpd 스텁 — 리포트를 쓰는 것 / 실패하는 것
STUB="$ROOT/stub"; mkdir -p "$STUB/ok" "$STUB/bad"
cat > "$STUB/ok/jscpd" <<'EOS'
#!/usr/bin/env bash
out=""; while [ "$#" -gt 0 ]; do case "$1" in --output) out="$2"; shift 2 ;; *) shift ;; esac; done
mkdir -p "$out"; printf '{"statistics":{"total":{"lines":40,"duplicatedLines":12}}}\n' > "$out/jscpd-report.json"
EOS
printf '#!/usr/bin/env bash\nexit 3\n' > "$STUB/bad/jscpd"; chmod +x "$STUB/ok/jscpd" "$STUB/bad/jscpd"
( cd "$R" && PATH="$STUB/ok:$PATH" bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.jscpd.status')" = measured ] && [ "$(J "$R" '[.jscpd.lines,.jscpd.duplicated_lines]|join(",")')" = "40,12" ] && [ "$(J "$R" '.dup.status')" = measured ]; } \
  && ok "R2.e jscpd 가 있으면 그 수치를 추가로 기록(40줄 중 12) · 자체 수치도 그대로" || nope "R2.e" "$(J "$R" '.jscpd')"
( cd "$R" && PATH="$STUB/bad:$PATH" bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.jscpd.status')" = not_measured ] && [ "$(J "$R" '.jscpd.duplicated_lines')" = null ] && [ "$(J "$R" '.dup.status')" = measured ]; } \
  && ok "R2.f jscpd 가 실패하면 jscpd 칸만 not_measured(null) · 자체 수치는 유지" || nope "R2.f" "$(J "$R" '.jscpd')"

# ── R3: 재사용 이행률 (AC-3) ──
mk_manifest() {
  mkdir -p "$1/.specops/memory"
  printf '# Foundation Manifest\n\n## 제공 모듈\n\n| 모듈 | 경로 | 역할 | 재사용 방법 |\n|---|---|---|---|\n| 날짜 유틸 | `lib/dates.js` | 날짜 | `formatDate` |\n| 로깅 | `lib/logger.js` | 로그 | `logInfo` |\n| 인증 | `lib/auth.js` | 인증 | `requireUser` |\n| 설정 | `lib/config.js` | 설정 | `loadConfig` |\n| 캐시 | `lib/cache.js` | 캐시 | `cacheGet` |\n' > "$1/.specops/memory/foundation-manifest.md"
}
R=$(mk_repo); mk_manifest "$R"
printf '**§유형**: 신규\n' > "$R/.specops/$FID/spec.md"
{ printf '# tasks\n'
  printf '\n## Task 1: a\n\n**재사용 foundation**: `lib/dates.js`\n'      # 이행 — 경로의 파일 이름(dates)이 import 에 나온다
  printf '\n## Task 2: b\n\n**재사용 foundation**: 로깅\n'                # 미이행 — logger 를 쓰지 않는다
  printf '\n## Task 3: c\n\n**재사용 foundation**: `requireUser`\n'       # 이행 — 심볼
  printf '\n## Task 4: d\n\n**재사용 foundation**: 설정\n'                # 이행 — manifest 행의 loadConfig 가 코드에 나온다
  printf '\n## Task 5: e\n\n**재사용 foundation**: `lib/cache.js`\n'      # 미이행
  printf '\n## Task 6: f\n\n**미재사용 근거**: 공통부 범위 밖\n'            # 선언 건수에 넣지 않는다
} > "$R/.specops/$FID/tasks.md"
printf "import { formatDate } from '../lib/dates'\nconst u = requireUser(req)\nconst c = loadConfig()\n" > "$R/src/use.js"; commit_all "$R"
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.reuse.status')" = measured ] && [ "$(J "$R" '[.reuse.fulfilled,.reuse.declared]|join("/")')" = "3/5" ]; } \
  && ok "R3.a 재사용 이행률: 선언 5건 중 3건이 코드에 나온다 → 3/5 (미재사용 근거는 세지 않는다)" || nope "R3.a" "$(J "$R" '.reuse')"
R=$(mk_repo); echo "x = 1" > "$R/src/x.py"; commit_all "$R"
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.reuse.status')" = not_applicable ] && [ "$(J "$R" '.reuse.declared')" = null ] && [ -n "$(J "$R" '.reuse.reason')" ]; } \
  && ok "R3.b manifest 가 없으면 not_applicable 과 사유(0/0 이 아니다)" || nope "R3.b" "$(J "$R" '.reuse')"

R=$(mk_repo); mkdir -p "$R/.specops/memory"
printf '# Foundation Manifest\n\n| 모듈 | 경로 | 역할 | 재사용 방법 |\n|---|---|---|---|\n| 인덱스 | `lib/index.js` | a | - |\n| 날짜 | `lib/dates.js` | b | - |\n| API | `lib/api.js` | c | - |\n' > "$R/.specops/memory/foundation-manifest.md"
printf '**§유형**: 신규\n' > "$R/.specops/$FID/spec.md"
printf '# tasks\n\n## Task 1: a\n\n**재사용 foundation**: `lib/index.js`\n\n## Task 2: b\n\n**재사용 foundation**: `lib/dates.js`\n\n## Task 3: c\n\n**재사용 foundation**: `lib/api.js`\n' > "$R/.specops/$FID/tasks.md"
printf "const i = arr.indexOf(x)\nconst updates = []\nimport { get } from '../lib/api'\n" > "$R/src/use.js"; commit_all "$R"
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
[ "$(J "$R" '[.reuse.fulfilled,.reuse.declared]|join("/")')" = "1/3" ] \
  && ok "R3.c 식별자 경계: index 는 indexOf 에, dates 는 updates 에 맞지 않는다 · 확장자 없는 import(lib/api)는 맞는다 → 1/3" || nope "R3.c" "$(J "$R" '.reuse')"
( cd "$R" && SPECOPS_REUSE_MAX_FILES=0 bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.reuse.status')" = not_measured ] && [ "$(J "$R" '.reuse.fulfilled')" = null ] && [ "$(J "$R" '.reuse.declared')" = null ]; } \
  && ok "R3.d 파일 수 상한 초과: 이행률도 not_measured·null (0/N 으로 쓰지 않는다)" || nope "R3.d" "$(J "$R" '.reuse')"

# ── R4: 재지 못한 것을 0 으로 쓰지 않는다 (AC-4) ──
NG="$ROOT/nogit"; mkdir -p "$NG/.specops/$FID"
out=$( cd "$NG" && bash "$RM" measure "$FID" 2>&1 ); rc=$?
{ [ "$rc" = 0 ] && [ "$(J "$NG" '.size.status')" = not_measured ] && [ "$(J "$NG" '.size.impl.added')" = null ] && [ "$(J "$NG" '.dup.status')" = not_measured ] \
  && [ "$(J "$NG" '.dup.dup_within_new')" = null ] && [ -n "$(J "$NG" '.size.reason')" ]; } \
  && ok "R4.a 분기점을 구할 수 없으면 size·dup 이 not_measured·null·사유 · rc 0" || nope "R4.a" "rc=$rc $(cat "$NG/.specops/$FID/reuse-metrics.json" 2>/dev/null)"
R=$(mk_repo); echo "a = 1" > "$R/src/a.py"; echo "b = 2" > "$R/src/b.py"; commit_all "$R"
( cd "$R" && SPECOPS_REUSE_MAX_FILES=1 bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.dup.status')" = not_measured ] && [ "$(J "$R" '.dup.dup_within_new')" = null ] && [ "$(J "$R" '.size.status')" = measured ] && [ "$(J "$R" '.size.impl.added')" = 2 ]; } \
  && ok "R4.b 파일 수 상한 초과: dup 만 not_measured(null) · size 는 계속 측정" || nope "R4.b" "$(cat "$R/.specops/$FID/reuse-metrics.json")"
( cd "$R" && bash "$RM" measure "not-a-fid" ) >/dev/null 2>&1; r1=$?; ( cd "$R" && bash "$RM" ) >/dev/null 2>&1; r2=$?
{ [ "$r1" = 2 ] && [ "$r2" = 2 ]; } && ok "R4.c 잘못된 FID·인자 없음 → rc 2(사용 오류)" || nope "R4.c" "r1=$r1 r2=$r2"

R=$(mk_repo); { echo "def a():"; blk new; echo "def b():"; blk new; } > "$R/src/한글 모듈.py"; printf '설계\n둘째\n셋째\n' > "$R/docs설계.md"; commit_all "$R"
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.dup.status')" = measured ] && [ "$(J "$R" '.dup.new_lines')" = 18 ] && [ "$(J "$R" '.dup.dup_within_new')" = 16 ] && [ "$(J "$R" '[.size.impl.added,.size.doc.added]|join(",")')" = "18,3" ]; } \
  && ok "R4.d 비ASCII·공백 경로: 경로 인용에 빗나가지 않는다(새 코드 18줄 중 16 복제 · 문서 +3)" || nope "R4.d" "$(cat "$R/.specops/$FID/reuse-metrics.json")"
R=$(mk_repo); mkdir -p "$R/proj/src" "$R/proj/.specops/$FID"; { echo "def a():"; blk new; echo "def b():"; blk new; } > "$R/proj/src/new.py"; commit_all "$R"
( cd "$R/proj" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(jq -r '.dup.new_lines' "$R/proj/.specops/$FID/reuse-metrics.json" 2>/dev/null)" = 18 ] && [ "$(jq -r '.size.impl.added' "$R/proj/.specops/$FID/reuse-metrics.json" 2>/dev/null)" = 18 ]; } \
  && ok "R4.e 저장소 하위 디렉터리에서 불러도 같은 결과(규모 +18 · 새 코드 18줄)" || nope "R4.e" "$(cat "$R/proj/.specops/$FID/reuse-metrics.json" 2>/dev/null)"
R=$(mk_repo); { echo "def a():"; blk new; } > "$R/src/a\"b.py"; commit_all "$R"
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.size.impl.added')" = 9 ] && { [ "$(J "$R" '.dup.new_lines')" = 9 ] || { [ "$(J "$R" '.dup.status')" = not_measured ] && [ "$(J "$R" '.dup.new_lines')" = null ]; }; }; } \
  && ok "R4.f 따옴표 든 경로: 줄을 읽었으면 9, 못 읽었으면 not_measured·null — 어느 쪽이든 measured 0 은 아니다($(J "$R" '.dup.status'))" || nope "R4.f" "$(cat "$R/.specops/$FID/reuse-metrics.json")"
echo "z = 1" > "$R/src/ok.py"; commit_all "$R"      # 읽히는 파일이 섞여도 일부만 읽은 값을 measured 로 내지 않는다
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.size.impl.added')" = 10 ] && { [ "$(J "$R" '.dup.new_lines')" = 10 ] || { [ "$(J "$R" '.dup.status')" = not_measured ] && [ "$(J "$R" '.dup.new_lines')" = null ] && [ "$(J "$R" '.reuse.status')" != measured ]; }; }; } \
  && ok "R4.g 따옴표 든 경로 + 읽히는 파일 혼합: 전부 읽었으면 10, 아니면 not_measured·null — 일부(1줄)만 읽고 measured 로 내지 않는다($(J "$R" '.dup.status'))" || nope "R4.g" "$(cat "$R/.specops/$FID/reuse-metrics.json")"
R=$(mk_repo); { echo "def c():"; blk old; } > "$R/src/copy.py"; commit_all "$R"
( cd "$R" && SPECOPS_REUSE_MAX_TREE_BYTES=10 bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.dup.existing.status')" = not_measured ] && [ "$(J "$R" '.dup.existing.dup_of_existing')" = null ] && [ "$(J "$R" '.dup.existing.corpus_files')" = null ] && J "$R" '.dup.existing.reason' | grep -q '바이트' && [ "$(J "$R" '.dup.status')" = measured ] && [ "$(J "$R" '.size.impl.added')" = 9 ]; } \
  && ok "R4.h 분기점 트리 바이트 상한 초과: 코퍼스를 읽지 않고 기존 코드 복제만 not_measured(null)·사유 · 새 코드끼리·size 는 계속 측정" || nope "R4.h" "$(cat "$R/.specops/$FID/reuse-metrics.json")"
R=$(mk_repo)      # 분기 직후 — 변경 없음
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.size.status')" = not_measured ] && [ "$(J "$R" '.size.impl.added')" = null ] && [ "$(J "$R" '.dup.status')" = not_measured ] && [ "$(J "$R" '.dup.new_lines')" = null ] \
  && J "$R" '.size.reason' | grep -q '변경 범위가 비었음' && [ -n "$(J "$R" '.base // empty')" ]; } \
  && ok "R4.i 빈 범위(분기점 = HEAD · 작업 트리 변경 없음): measured 0 이 아니라 not_measured·null·사유 · 분기점은 기록" || nope "R4.i" "$(cat "$R/.specops/$FID/reuse-metrics.json")"
echo "w = 1" > "$R/src/wip.py"; ( cd "$R" && git add -A ) >/dev/null 2>&1      # 커밋 전 변경은 범위에 든다
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.size.status')" = measured ] && [ "$(J "$R" '.size.impl.added')" = 1 ]; } \
  && ok "R4.j 분기점 = HEAD 여도 커밋 전 변경이 있으면 측정한다(+1)" || nope "R4.j" "$(cat "$R/.specops/$FID/reuse-metrics.json")"
# git 래퍼 — cat-file 만 다르게 굴고 나머지는 진짜 git 으로 넘긴다(스크립트는 `git -C <루트> -c … cat-file` 로 부르므로 인자 전체를 훑는다).
REAL_GIT=$(command -v git)
mk_git_wrap() {   # $1=디렉터리 $2=cat-file 을 만났을 때 할 일
  mkdir -p "$1"
  { printf '#!/usr/bin/env bash\n'
    printf 'for a in "$@"; do if [ "$a" = cat-file ]; then %s; fi; done\n' "$2"
    printf 'exec "%s" "$@"\n' "$REAL_GIT"; } > "$1/git"
  chmod +x "$1/git"
}
mk_git_wrap "$ROOT/gfail" 'exit 1'
R=$(mk_repo); { echo "def c():"; blk old; } > "$R/src/copy.py"; commit_all "$R"      # review-base.sha 없음 — cat-file 은 코퍼스 읽기에서만 불린다
( cd "$R" && PATH="$ROOT/gfail:$PATH" bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.dup.existing.status')" = not_measured ] && [ "$(J "$R" '.dup.existing.dup_of_existing')" = null ] && [ "$(J "$R" '.dup.existing.corpus_files')" = null ] \
  && [ -n "$(J "$R" '.dup.existing.reason')" ] && [ "$(J "$R" '.dup.status')" = measured ] && [ "$(J "$R" '.dup.dup_within_new')" = 0 ] && [ "$(J "$R" '.size.status')" = measured ]; } \
  && ok "R4.k 분기점 코퍼스를 읽지 못하면(cat-file 실패) 기존 코드 복제만 not_measured·null·사유 — measured 0 이 아니다 · 새 코드끼리·size 는 유지" || nope "R4.k" "$(cat "$R/.specops/$FID/reuse-metrics.json")"
( cd "$R" && SPECOPS_REUSE_MAX_CORPUS_LINES=9 bash "$RM" measure "$FID" ) >/dev/null 2>&1      # 코퍼스 = src/old.py 9줄
c9=$(J "$R" '[.dup.existing.status,.dup.existing.dup_of_existing]|join(",")')
( cd "$R" && SPECOPS_REUSE_MAX_CORPUS_LINES=8 bash "$RM" measure "$FID" ) >/dev/null 2>&1
c8=$(J "$R" '[.dup.existing.status,.dup.existing.dup_of_existing,.dup.existing.corpus_files]|map(tostring)|join(",")')
{ [ "$c9" = "measured,8" ] && [ "$c8" = "not_measured,null,null" ] && J "$R" '.dup.existing.reason' | grep -q '대조 코퍼스 9줄'; } \
  && ok "R4.m 코퍼스 줄 수 상한 경계: 9줄 코퍼스는 상한 9 에서 측정(8) · 상한 8 에서 not_measured·null — 줄 수는 파일의 실제 줄 수다" || nope "R4.m" "상한9=$c9 상한8=$c8 사유=$(J "$R" '.dup.existing.reason')"
R=$(mk_repo); { echo "def a():"; blk new; echo "def b():"; blk new; } > "$R/src/new.py"; commit_all "$R"
( cd "$R" && git config diff.mnemonicPrefix true && bash "$RM" measure "$FID" ) >/dev/null 2>&1
m1=$(J "$R" '[.dup.status,.dup.new_lines,.dup.dup_within_new]|join(",")')
( cd "$R" && git config --unset diff.mnemonicPrefix && git config diff.noprefix true && bash "$RM" measure "$FID" ) >/dev/null 2>&1
m2=$(J "$R" '[.dup.status,.dup.new_lines,.dup.dup_within_new]|join(",")')
{ [ "$m1" = "measured,18,16" ] && [ "$m2" = "measured,18,16" ]; } \
  && ok "R4.l 사용자 git 설정(diff.mnemonicPrefix · diff.noprefix)과 무관하게 같은 값(새 코드 18줄 중 16 복제)" || nope "R4.l" "mnemonicPrefix=$m1 noprefix=$m2"

# ── R7: batch — review-base.sha 가 있으면 그 FR 의 시작점부터만 센다 ──
R=$(mk_repo); printf 'a = 1\nb = 2\nc = 3\n' > "$R/src/first.py"; commit_all "$R"
( cd "$R" && git rev-parse HEAD > ".specops/$FID/review-base.sha" ); printf 'd = 4\ne = 5\n' > "$R/src/second.py"; commit_all "$R"
( cd "$R" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
{ [ "$(J "$R" '.size.impl.added')" = 2 ] && [ "$(J "$R" '.base_source')" = "review-base.sha" ]; } \
  && ok "R7 review-base.sha 가 있으면 그 지점부터만(+2) — 한 브랜치의 앞 FR 변경(+3)을 누적하지 않는다" || nope "R7" "$(J "$R" '.size') src=$(J "$R" '.base_source')"

# ── R5: report (AC-5) ──
T="$ROOT/tree"; mkdir -p "$T/20260101-aaa" "$T/20260102-bbb" "$T/20260103-ccc" "$T/20260104-norecord" "$T/memory"
cp "$R/.specops/$FID/reuse-metrics.json" "$T/20260101-aaa/reuse-metrics.json"
cp "$NG/.specops/$FID/reuse-metrics.json" "$T/20260102-bbb/reuse-metrics.json"
R3=$(mk_repo); { echo "def a():"; blk new; echo "def b():"; blk new; } > "$R3/src/new.py"; commit_all "$R3"; ( cd "$R3" && bash "$RM" measure "$FID" ) >/dev/null 2>&1
cp "$R3/.specops/$FID/reuse-metrics.json" "$T/20260103-ccc/reuse-metrics.json"
rep=$(bash "$RM" report "$T" 2>&1); rrc=$?
{ [ "$rrc" = 0 ] && [ "$(printf '%s\n' "$rep" | grep -c '^2026')" = 3 ] && printf '%s\n' "$rep" | grep -q '미측정(' && printf '%s\n' "$rep" | grep -q '해당없음' \
  && printf '%s\n' "$rep" | grep -q '16 \[builtin\]' && printf '%s\n' "$rep" | grep -q '기록 없는 FID 1개' && ! printf '%s\n' "$rep" | grep -q 'norecord |'; } \
  && ok "R5.a report: 기록 있는 3개가 한 줄씩 · 미측정·해당없음이 숫자와 구별 · 방식 표기 · 기록 없는 FID 는 건수만" || nope "R5.a" "rc=$rrc rep=$rep"
E="$ROOT/empty"; mkdir -p "$E/20260101-zzz"
rep=$(bash "$RM" report "$E" 2>&1); rrc=$?
{ [ "$rrc" = 0 ] && printf '%s\n' "$rep" | grep -q '기록 없음'; } && ok "R5.b 기록이 하나도 없으면 그 사실을 한 줄로 · rc 0" || nope "R5.b" "rc=$rrc rep=$rep"

# ── R6: verify 판정이 바뀌지 않는다 (AC-6) ──
mk_verify() {   # $1=저장소 $2=pass|fail
  mkdir -p "$1/scripts/tests"
  printf -- '- [ ] **스텝 4**: 실행: `bash scripts/tests/dummy.sh`\n' > "$1/.specops/$FID/tasks.md"
  if [ "$2" = pass ]; then printf '#!/usr/bin/env bash\nexit 0\n' > "$1/scripts/tests/dummy.sh"; else printf '#!/usr/bin/env bash\nexit 1\n' > "$1/scripts/tests/dummy.sh"; fi
  chmod +x "$1/scripts/tests/dummy.sh"
}
R=$(mk_repo); echo "x = 1" > "$R/src/x.py"; mk_verify "$R" pass; commit_all "$R"
out=$( cd "$R" && bash "$RUN" "$FID" 2>&1 ); rc=$?
{ [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] && [ -f "$R/.specops/$FID/reuse-metrics.json" ] && [ "$(J "$R" '.size.status')" = measured ]; } \
  && ok "R6.a verify PASS → 마지막 줄 VERIFY: PASS · rc 0 · reuse-metrics.json 자동 기록" || nope "R6.a" "rc=$rc out=$out"
R=$(mk_repo); echo "x = 1" > "$R/src/x.py"; mk_verify "$R" pass; mkdir -p "$R/.specops/$FID/reuse-metrics.json"; commit_all "$R"   # 기록 경로가 디렉터리 → 측정 기록 실패
out=$( cd "$R" && bash "$RUN" "$FID" 2>&1 ); rc=$?
{ [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] \
  && [ ! -f "$R/.specops/$FID/reuse-metrics.json/out.json" ] && [ -z "$(ls -A "$R/.specops/$FID/reuse-metrics.json")" ]; } \
  && ok "R6.b 측정 기록이 실패해도(기록 경로가 디렉터리 — 안에 아무것도 쓰지 않는다) verify 는 그대로 VERIFY: PASS · rc 0" || nope "R6.b" "rc=$rc out=$out"
R=$(mk_repo); echo "x = 1" > "$R/src/x.py"; mk_verify "$R" fail; commit_all "$R"
out=$( cd "$R" && bash "$RUN" "$FID" 2>&1 ); rc=$?
{ [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'VERIFY: FAIL' && [ ! -e "$R/.specops/$FID/reuse-metrics.json" ]; } \
  && ok "R6.c verify FAIL → 판정·rc 그대로 · 측정하지 않는다(파일 없음)" || nope "R6.c" "rc=$rc out=$out"
# 측정 스크립트 자체가 실패하고 판정처럼 보이는 줄을 내도 verify 의 판정·rc·마지막 줄은 그대로다.
#   실 플러그인을 건드리지 않도록 scripts·hooks 를 사본으로 복사해 그 사본의 reuse-metrics.sh 만 스텁으로 바꾼다.
PL="$ROOT/pl"; mkdir -p "$PL"; cp -R "$PLUGIN/scripts" "$PLUGIN/hooks" "$PL/"
printf '#!/usr/bin/env bash\necho "VERIFY: FAIL stub"\necho "VERIFY: FAIL stub" >&2\nexit 1\n' > "$PL/scripts/reuse-metrics.sh"
R=$(mk_repo); echo "x = 1" > "$R/src/x.py"; mk_verify "$R" pass; commit_all "$R"
out=$( cd "$R" && bash "$PL/scripts/_internal/run-verification.sh" "$FID" 2>&1 ); rc=$?
{ [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] && ! printf '%s\n' "$out" | grep -q 'VERIFY: FAIL'; } \
  && ok "R6.d 측정 스크립트가 rc 1·가짜 판정 줄을 내도 verify 는 VERIFY: PASS · rc 0 · 측정 출력은 새지 않는다" || nope "R6.d" "rc=$rc out=$out"
rm -f "$PL/scripts/reuse-metrics.sh"
R=$(mk_repo); echo "x = 1" > "$R/src/x.py"; mk_verify "$R" pass; commit_all "$R"
out=$( cd "$R" && bash "$PL/scripts/_internal/run-verification.sh" "$FID" 2>&1 ); rc=$?
{ [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] && [ ! -e "$R/.specops/$FID/reuse-metrics.json" ]; } \
  && ok "R6.e 측정 스크립트가 없어도 verify 는 VERIFY: PASS · rc 0" || nope "R6.e" "rc=$rc out=$out"
# 측정이 매달려도 verify 는 상한에서 끊고 끝난다. 사본의 상한 숫자만 30→2 로 줄여 60초 자는 스텁을 붙인다(한도 20초 — 부하 여유).
RV="$PL/scripts/_internal/run-verification.sh"
sed 's/bounded_run 30 bash/bounded_run 2 bash/' "$RV" > "$RV.new" && mv "$RV.new" "$RV"
printf '#!/usr/bin/env bash\nsleep 60\n' > "$PL/scripts/reuse-metrics.sh"
if [ "$(grep -c 'bounded_run 2 bash "$PLUGIN/scripts/reuse-metrics.sh" measure' "$RV")" = 1 ]; then
  R=$(mk_repo); echo "x = 1" > "$R/src/x.py"; mk_verify "$R" pass; commit_all "$R"
  t0=$SECONDS; out=$( cd "$R" && bash "$RV" "$FID" 2>&1 ); rc=$?; el=$((SECONDS - t0))
  { [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] && [ "$el" -lt 20 ]; } \
    && ok "R6.f 측정이 매달려도(60초 스텁) verify 는 시간 상한에서 끊고 VERIFY: PASS · rc 0 (사본 상한 2초 · 한도 20초 안)" || nope "R6.f" "rc=$rc el=${el}s out=$out"
else
  nope "R6.f" "run-verification.sh 의 측정 호출에 시간 상한(bounded_run 30)이 없다 — 실행 생략"
fi
# 측정이 끝나든 TERM 으로 끊기든 임시 디렉터리를 남기지 않는다. 끊는 방식은 run-bounded.sh 와 같다(프로세스 그룹째 TERM).
TD="$ROOT/tmpd"; mkdir -p "$TD"
mk_git_wrap "$ROOT/gslow" ": > '$ROOT/gslow.reached'; sleep 30; exit 1"
R=$(mk_repo); { echo "def c():"; blk old; } > "$R/src/copy.py"; commit_all "$R"
( cd "$R" && TMPDIR="$TD" bash "$RM" measure "$FID" ) >/dev/null 2>&1
left_ok=$(find "$TD" -maxdepth 1 -name 'specops-reuse.*' | wc -l | tr -d ' ')
gres=$(
  set -m
  ( cd "$R" && TMPDIR="$TD" PATH="$ROOT/gslow:$PATH" exec bash "$RM" measure "$FID" ) >/dev/null 2>&1 &
  gp=$!
  set +m
  i=0; while [ ! -e "$ROOT/gslow.reached" ] && [ "$i" -lt 100 ]; do sleep 0.2; i=$((i + 1)); done
  mid=$(find "$TD" -maxdepth 1 -name 'specops-reuse.*' | wc -l | tr -d ' ')
  kill -TERM -- "-$gp" 2>/dev/null; kill -TERM "$gp" 2>/dev/null
  wait "$gp" 2>/dev/null
  echo "$([ -e "$ROOT/gslow.reached" ] && echo 1 || echo 0) $mid $(find "$TD" -maxdepth 1 -name 'specops-reuse.*' | wc -l | tr -d ' ')"
) 2>/dev/null
{ [ "$left_ok" = 0 ] && [ "$gres" = "1 1 0" ] && grep -q "^  trap 'exit 143' TERM" "$RM"; } \
  && ok "R6.g 임시 디렉터리를 남기지 않는다 — 정상 종료 뒤 0개 · 측정 도중(코퍼스 읽기) TERM 으로 끊겨도 1개→0개" || nope "R6.g" "정상 종료 뒤=${left_ok} 끊김(도달 중간 끝)=${gres}"

finish
