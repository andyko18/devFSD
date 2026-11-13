#!/usr/bin/env bash
# 기준 약화 후보 스캐너(scan-dod-weakening.sh) — 6클래스 추출 · 종료 코드 0/1/2 · 조이는 변경은 무시 · 값 비출력 (20261113-dod-weakening-scan)
# run-all: sandbox 트리(mktemp)만 쓴다 — 실 트리 쓰기 0
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCAN="$PLUGIN/scripts/_internal/scan-dod-weakening.sh"
AG="$PLUGIN/agents/code-reviewer-ko.md"
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT

# 기준 커밋 하나를 가진 저장소 — base 는 브랜치 `base`
mkrepo() {
  local d="$SB/$1"; mkdir -p "$d/src" "$d/tests" "$d/.github/workflows"
  git -C "$d" init -q; git -C "$d" config user.email t@t; git -C "$d" config user.name t
  printf 'export function add(a, b) {\n  return a + b;\n}\n' > "$d/src/add.ts"
  printf 'it("adds", () => {\n  expect(add(1, 2)).toBe(3);\n  expect(add(0, 0)).toBe(0);\n  expect(add(-1, 1)).toBe(0);\n});\n' > "$d/tests/add.test.ts"
  printf 'it("old", () => {\n  expect(1).toBe(1);\n});\n' > "$d/tests/old.test.ts"
  printf 'module.exports = {\n  coverageThreshold: { global: { lines: 80 } },\n  testTimeout: 5000,\n};\n' > "$d/jest.config.js"
  printf 'jobs:\n  t:\n    steps:\n      - run: npm test\n' > "$d/.github/workflows/ci.yml"
  printf '# 안내\n' > "$d/README.md"
  git -C "$d" add -A; git -C "$d" commit -q -m base; git -C "$d" branch -q base
  echo "$d"
}
scan() { ( cd "$1" && shift && bash "$SCAN" "$@" ) 2>&1; }
has() { printf '%s\n' "$1" | grep -qE -- "$2"; }

# T1 클래스별 약화 → 후보 행 · 요약 · rc 1
d=$(mkrepo r1)
printf 'export function add(a, b) {\n  // @ts-ignore\n  return a + b;\n}\nexport function sub() {\n  throw new Error("Not implemented");\n}\n' > "$d/src/add.ts"
printf 'it.skip("adds", () => {\n  expect(add(1, 2)).toBe(3);\n});\n' > "$d/tests/add.test.ts"
git -C "$d" rm -q tests/old.test.ts
printf 'module.exports = {\n  coverageThreshold: { global: { lines: 70 } },\n  testTimeout: 9000,\n};\n' > "$d/jest.config.js"
printf 'jobs:\n  t:\n    steps:\n      - run: npm test || true\n' > "$d/.github/workflows/ci.yml"
out=$(scan "$d" --base base); rc=$?
[ "$rc" -eq 1 ] && ok "T1.rc 후보가 있으면 rc 1" || nope "T1.rc" "rc=$rc out=$out"
has "$out" '^suppress	src/add\.ts:2	@ts-ignore$' && ok "T1.a 억제 주석 신규 — 파일:줄·패턴" || nope "T1.a" "$out"
has "$out" '^skip	tests/add\.test\.ts:1	' && ok "T1.b skip 추가" || nope "T1.b" "$out"
has "$out" '^skip	tests/old\.test\.ts:-	deleted-test-file$' && ok "T1.c 테스트 파일 삭제" || nope "T1.c" "$out"
has "$out" '^assert	tests/add\.test\.ts:-	assertions -2 \+0$' && ok "T1.d 단언 순감소 — 삭제 2 · 추가 0" || nope "T1.d" "$out"
has "$out" '^threshold	jest\.config\.js:2	80 -> 70$' && ok "T1.e 임계값 하향" || nope "T1.e" "$out"
has "$out" '^threshold	jest\.config\.js:3	5000 -> 9000$' && ok "T1.f 타임아웃 상향" || nope "T1.f" "$out"
has "$out" '^disable	\.github/workflows/ci\.yml:4	\|\| true$' && ok "T1.g 검증 무력화" || nope "T1.g" "$out"
has "$out" '^stub	src/add\.ts:6	Not implemented$' && ok "T1.h 미구현 표식" || nope "T1.h" "$out"
has "$out" '^DOD-WEAKENING: candidates=8 suppress=1 skip=2 assert=1 threshold=2 disable=1 stub=1 ' && ok "T1.i 요약 줄 — 클래스별 건수" || nope "T1.i" "$(printf '%s\n' "$out" | tail -1)"

# T2 기준을 건드리지 않는 변경 → 후보 0 · rc 0 · files 가 0 이 아니다(빈 diff 와 구별)
d=$(mkrepo r2)
printf 'export function add(a, b) {\n  return b + a;\n}\n' > "$d/src/add.ts"
out=$(scan "$d" --base base); rc=$?
[ "$rc" -eq 0 ] && has "$out" '^DOD-WEAKENING: candidates=0 .* files=1$' && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] \
  && ok "T2 약화 없는 변경 → rc 0 · 요약 1줄 · files=1" || nope "T2" "rc=$rc out=$out"

# T3 조이는 방향(억제 제거 · skip 해제 · 임계 상향 · 타임아웃 하향 · 단언 추가)은 후보가 아니다
d=$(mkrepo r3)
printf 'export function add(a, b) {\n  // @ts-ignore\n  return a + b;\n}\n' > "$d/src/add.ts"
printf 'it.skip("adds", () => {\n  expect(add(1, 2)).toBe(3);\n});\n' > "$d/tests/add.test.ts"
printf 'jobs:\n  t:\n    steps:\n      - run: npm test || true\n' > "$d/.github/workflows/ci.yml"
git -C "$d" add -A; git -C "$d" commit -q -m loose; git -C "$d" branch -q -f base
printf 'export function add(a, b) {\n  return a + b;\n}\n' > "$d/src/add.ts"
printf 'it("adds", () => {\n  expect(add(1, 2)).toBe(3);\n  expect(add(0, 0)).toBe(0);\n});\n' > "$d/tests/add.test.ts"
printf 'module.exports = {\n  coverageThreshold: { global: { lines: 90 } },\n  testTimeout: 3000,\n};\n' > "$d/jest.config.js"
printf 'jobs:\n  t:\n    steps:\n      - run: npm test\n' > "$d/.github/workflows/ci.yml"
out=$(scan "$d" --base base); rc=$?
[ "$rc" -eq 0 ] && has "$out" '^DOD-WEAKENING: candidates=0 ' && ok "T3 조이는 변경은 조용하다 → rc 0" || nope "T3" "rc=$rc out=$out"

# T4 실행할 수 없으면 rc 2 — 통과(0)로 읽히지 않는다
nd="$SB/nogit"; mkdir -p "$nd"
out=$(scan "$nd" --base base); rc=$?
[ "$rc" -eq 2 ] && has "$out" '^DOD-WEAKENING: ERROR ' && ok "T4.a git 저장소 아님 → rc 2 · ERROR 줄" || nope "T4.a" "rc=$rc out=$out"
d=$(mkrepo r4)
out=$(scan "$d" --base no-such-ref); rc=$?
[ "$rc" -eq 2 ] && has "$out" '^DOD-WEAKENING: ERROR ' && ok "T4.b 없는 base → rc 2" || nope "T4.b" "rc=$rc out=$out"
out=$(scan "$d" --base); rc=$?
[ "$rc" -eq 2 ] && ok "T4.c --base 값 누락 → rc 2" || nope "T4.c" "rc=$rc out=$out"
out=$(scan "$d" --bogus); rc=$?
[ "$rc" -eq 2 ] && ok "T4.d 모르는 옵션 → rc 2" || nope "T4.d" "rc=$rc out=$out"

# T5 추적하지 않는 새 파일도 본다 · 문서(*.md)와 .specops 는 보지 않는다
d=$(mkrepo r5)
printf 'def f():\n    x = 1  # noqa\n    raise NotImplementedError\n' > "$d/src/new.py"
printf '설명: `eslint-disable` 와 `@ts-ignore` 는 억제 주석이다\n' > "$d/README.md"
mkdir -p "$d/.specops/x"; printf '// @ts-ignore\n' > "$d/.specops/x/note.ts"
out=$(scan "$d" --base base); rc=$?
[ "$rc" -eq 1 ] && has "$out" '^suppress	src/new\.py:2	# noqa$' && has "$out" '^stub	src/new\.py:3	NotImplementedError$' \
  && ok "T5.a 추적하지 않는 새 파일의 후보" || nope "T5.a" "rc=$rc out=$out"
! has "$out" 'README\.md|\.specops/' && ok "T5.b 문서·.specops 제외" || nope "T5.b" "$out"

# T6 값은 출력하지 않는다 — 후보 줄에 비밀값이 있어도 패턴 이름만
d=$(mkrepo r6)
printf 'jobs:\n  t:\n    steps:\n      - run: TOKEN=sk-live-SECRETVALUE123 npm test || true\n' > "$d/.github/workflows/ci.yml"
out=$(scan "$d" --base base); rc=$?
[ "$rc" -eq 1 ] && has "$out" '^disable	' && ! has "$out" 'SECRETVALUE123' && ok "T6 줄 원문을 출력하지 않는다(값 비출력)" || nope "T6" "rc=$rc out=$out"

# T7 hunk 안의 `+++`·`---` 로 시작하는 내용 줄을 파일 머리로 읽지 않는다 → 뒤 줄 번호가 밀리지 않는다
d=$(mkrepo r7)
printf 'x = 1\ny = 2\n' > "$d/src/m.py"; git -C "$d" add -A; git -C "$d" commit -q -m m; git -C "$d" branch -q -f base
printf 'x = 1\n++ header-like\n-- another\nz = 3  # type: ignore\ny = 2\n' > "$d/src/m.py"
out=$(scan "$d" --base base); rc=$?
has "$out" '^suppress	src/m\.py:4	# type: ignore$' && ok "T7 머리처럼 보이는 내용 줄 뒤에도 줄 번호가 맞다" || nope "T7" "rc=$rc out=$out"

# T8 검증 명령이 없는 줄의 `|| true` 는 후보가 아니다(무력화 = 테스트·린트·빌드 명령 뒤)
d=$(mkrepo r8)
printf '#!/bin/sh\nn=$(grep -c x f || true)\nmkdir -p out || true\n' > "$d/src/run.sh"
out=$(scan "$d" --base base); rc=$?
[ "$rc" -eq 0 ] && ok "T8 검증 명령 없는 || true → 후보 아님" || nope "T8" "rc=$rc out=$out"

# T9 하위 폴더에서 실행해도 저장소 전체를 본다
d=$(mkrepo r9)
printf 'export function add(a, b) {\n  // eslint-disable-next-line\n  return a + b;\n}\n' > "$d/src/add.ts"
out=$(scan "$d/tests" --base base); rc=$?
[ "$rc" -eq 1 ] && has "$out" '^suppress	src/add\.ts:2	eslint-disable$' && ok "T9 하위 폴더 실행 → 저장소 기준 경로" || nope "T9" "rc=$rc out=$out"

# T11 오탐 경계 — 실제 저장소 이력(v3.1.0..)에서 나온 3종
d=$(mkrepo r11)
printf '{"skill":"a","bytes":15213,"lines":366}\n' > "$d/src/size.jsonl"
git -C "$d" add -A; git -C "$d" commit -q -m s; git -C "$d" branch -q -f base
printf '{"skill":"a","bytes":15209,"lines":366}\n' > "$d/src/size.jsonl"
printf '#!/bin/sh\n_o=$(grep -c x "$P/templates/test-strategy.md" || true)\nprintf "%%s" "$E" | grep -q -- "--no-verify" && echo y\n' > "$d/src/a.sh"
out=$(scan "$d" --base base); rc=$?
[ "$rc" -eq 0 ] && ok "T11.a 뒤쪽 낱말(lines)이 앞 숫자를 임계로 만들지 않는다 · 경로 조각 test-x · 문자열 속 --no-verify → 후보 아님" || nope "T11.a" "rc=$rc out=$out"
printf '#!/bin/sh\nbash scripts/tests/run-all.sh || true\ngit push --no-verify origin x\n./gradlew test || exit 0\n' > "$d/src/a.sh"
out=$(scan "$d" --base base); rc=$?
has "$out" '^disable	src/a\.sh:2	\|\| true$' && has "$out" '^disable	src/a\.sh:3	--no-verify$' && has "$out" '^disable	src/a\.sh:4	\|\| true$' \
  && ok "T11.b run-all || true · git push --no-verify · gradlew test || exit 0 → 후보" || nope "T11.b" "rc=$rc out=$out"

# T12 스캐너 자신과 그 테스트는 정확한 두 경로만 뺀다 — 이름이 비슷한 파일은 본다
d=$(mkrepo r12)
mkdir -p "$d/scripts/_internal" "$d/scripts/tests"
printf '# @ts-ignore\n' > "$d/scripts/_internal/scan-dod-weakening.sh"
printf '# @ts-ignore\n' > "$d/scripts/tests/test-scan-dod-weakening.sh"
printf '# @ts-ignore\n' > "$d/scripts/_internal/scan-dod-weakening.sh.bak"
out=$(scan "$d" --base base); rc=$?
has "$out" '^DOD-WEAKENING: candidates=1 ' && has "$out" '^suppress	scripts/_internal/scan-dod-weakening\.sh\.bak:1	' \
  && ok "T12 자기 제외는 정확한 경로 2개뿐" || nope "T12" "rc=$rc out=$out"

# T13 테스트 파일의 미구현 표식(가짜 구현)은 stub 후보가 아니다 — 같은 줄이 소스에 있으면 후보다
d=$(mkrepo r13)
printf 'const fake = { save() { throw new Error("Not implemented"); } };\n' > "$d/tests/fake.test.ts"
out=$(scan "$d" --base base); rc=$?
[ "$rc" -eq 0 ] && ok "T13.a 테스트 파일의 Not implemented → 후보 아님" || nope "T13.a" "rc=$rc out=$out"
printf 'const fake = { save() { throw new Error("Not implemented"); } };\n' > "$d/src/fake.ts"
out=$(scan "$d" --base base); rc=$?
has "$out" '^stub	src/fake\.ts:1	Not implemented$' && ok "T13.b 소스 파일의 같은 줄 → stub 후보" || nope "T13.b" "rc=$rc out=$out"

# T14 공백 든 경로 — git 이 경로 뒤에 붙이는 탭이 출력·제외 판정에 남지 않는다
d=$(mkrepo r14)
printf 'it("x", () => {\n  expect(1).toBe(1);\n});\n' > "$d/tests/my case.test.ts"
git -C "$d" add -A; git -C "$d" commit -q -m sp; git -C "$d" branch -q -f base
git -C "$d" rm -q "tests/my case.test.ts"
printf '// @ts-ignore 설명\n' > "$d/my doc.md"
printf 'const a = 1; // @ts-ignore\n' > "$d/src/my file.ts"
out=$(scan "$d" --base base); rc=$?
has "$out" '^skip	tests/my case\.test\.ts:-	deleted-test-file$' && has "$out" '^suppress	src/my file\.ts:1	@ts-ignore$' && ! has "$out" 'my doc\.md' \
  && has "$out" '^DOD-WEAKENING: candidates=2 ' && ok "T14 공백 든 경로 — 탭 없이 출력 · .md 제외 유지 · 삭제 테스트 파일" || nope "T14" "rc=$rc out=$(printf '%s' "$out" | od -c | head -8)"

# T15 사용자 git 설정(diff.mnemonicPrefix · diff.noprefix)이 경로를 바꾸지 않는다
for cfg in diff.mnemonicPrefix diff.noprefix; do
  d=$(mkrepo "r15-$cfg"); git -C "$d" config "$cfg" true
  mkdir -p "$d/a" "$d/b"; printf 'x = 1  # noqa\n' > "$d/a/in_a.py"
  printf 'export function add(a, b) {\n  // @ts-ignore\n  return a + b;\n}\n' > "$d/src/add.ts"
  git -C "$d" add a/in_a.py
  out=$(scan "$d" --base base); rc=$?
  has "$out" '^suppress	src/add\.ts:2	@ts-ignore$' && has "$out" '^suppress	a/in_a\.py:1	# noqa$' \
    && ok "T15 $cfg=true 에서도 경로가 그대로다" || nope "T15 $cfg" "rc=$rc out=$out"
done

# T16 상한(max…)을 낮추거나 임계 낱말 없는 줄의 숫자를 낮춘 것은 threshold 후보가 아니다
d=$(mkrepo r16)
printf 'rules:\n  max-lines: 100\n  min-height: 20\n  max-statements: 30\n' > "$d/src/c.yml"
git -C "$d" add -A; git -C "$d" commit -q -m c; git -C "$d" branch -q -f base
printf 'rules:\n  max-lines: 50\n  min-height: 10\n  max-statements: 10\n' > "$d/src/c.yml"
out=$(scan "$d" --base base); rc=$?
[ "$rc" -eq 0 ] && ok "T16 max-lines·min-height·max-statements 하향 → 후보 아님" || nope "T16" "rc=$rc out=$out"

# T17 같은 골격의 줄이 여럿이면 나온 순서대로 짝짓는다 — 내려간 줄만 후보다
d=$(mkrepo r17)
printf 'cov:\n  lines: 80\n  lines: 60\n  lines: 40\n' > "$d/src/t.yml"
git -C "$d" add -A; git -C "$d" commit -q -m t; git -C "$d" branch -q -f base
printf 'cov:\n  lines: 80\n  lines: 50\n  lines: 45\n' > "$d/src/t.yml"
out=$(scan "$d" --base base); rc=$?
has "$out" '^threshold	src/t\.yml:3	60 -> 50$' && has "$out" '^DOD-WEAKENING: candidates=1 ' \
  && ok "T17 순서대로 짝짓기 — 60→50 만 후보(40→45 는 조이는 방향)" || nope "T17" "rc=$rc out=$out"

# T10 리뷰어 문서가 스캐너를 가리키고 rc 2 를 통과로 읽지 않는다고 적는다
sec=$(awk 'index($0, "## 기준 약화 탐지") == 1 { on = 1; print; next } /^## / { on = 0 } on' "$AG")
has "$sec" 'scripts/_internal/scan-dod-weakening\.sh' && has "$sec" 'rc 2' && has "$sec" '판정이 아니다' \
  && ok "T10 code-reviewer-ko 가 스캐너 · rc 2 · 후보는 판정이 아님을 적는다" || nope "T10" "문구 누락"

finish
