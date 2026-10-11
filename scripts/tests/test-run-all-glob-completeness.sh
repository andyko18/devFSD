#!/usr/bin/env bash
# test-run-all-glob-completeness.sh — run-all glob 완결성 계약 (FID 20260712-runall-glob-completeness)
# 실제 test 보유 subdir ⊆ run-all for-루프 커버. SoT = run-all.sh for 루프(L4 주석 아님, Q5)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0
RA="$PLUGIN/scripts/tests/run-all.sh"

# subdir 정규화: 루트 상대 → 루트는 ".", 서브는 dirname. $1=트리 루트(기본 PLUGIN)
_actual() {
  local r="${1:-$PLUGIN}"
  find "$r/scripts/tests" -name 'test-*.sh' -not -path '*/fixtures/*' 2>/dev/null \
    | sed -E "s#^$r/scripts/tests##; s#/test-[^/]*\$##; s#^/##; s#^\$#.#" | sort -u
}
# run-all for-루프 glob 라인만 파싱 (L4 주석 brace 형태는 미매치 — SoT 단일)
_cover() {
  grep -oE '"\$PLUGIN"/scripts/tests/[a-z0-9-]*/?test-\*\.sh' "$RA" \
    | sed -E 's#"\$PLUGIN"/scripts/tests##; s#/?test-\*\.sh##; s#^/##; s#^$#.#' | sort -u
}

# ── T1: 실제 ⊆ 커버 (AC-1) ──
missing=$(comm -23 <(_actual) <(_cover))
[ -z "$missing" ] && ok "T1.a 실제 test subdir ⊆ run-all 커버 (완결)" \
  || nope "T1.a 완결성" "run-all 미커버 subdir: $(echo $missing)"

# ── T2: SoT 단일 — 커버가 for 루프에서 도출(하드코딩 배열 복제 없음) (AC-3) ──
# 계약 테스트 자신에 subdir 리터럴 배열이 없음을 자기검증(grep -oE 도출만)
if grep -qE 'COVER=\(|SUBDIRS=\(|cover=\(' "$0"; then
  nope "T2.a SoT" "커버 목록 하드코딩 배열 발견(SoT 복제)"
else
  ok "T2.a SoT 단일 (run-all grep 도출)"
fi

# ── T3: reverse-observe — 미등록 subdir 적발 (AC-2) ──
#   ★ canary 는 사본 트리에 만든다 (20260911-run-all-parallel): 실 트리에 만들면 병렬로 도는
#     스위트(find scripts/tests · cp -R scripts)가 canary 를 보고, SIGKILL 이면 잔존해 마커 지문을 바꾼다.
#     _actual 은 파일 **이름**만 보므로 test-*.sh 목록을 빈 파일로 복제한 트리면 충분하다.
F=$(mktemp -d) || { nope "T3.a reverse-observe" "사본 생성 실패"; finish; exit 1; }
trap 'rm -rf "$F"' EXIT
( cd "$PLUGIN" && find scripts/tests -name 'test-*.sh' -not -path '*/fixtures/*' ) \
  | while IFS= read -r f; do mkdir -p "$F/$(dirname "$f")" && : > "$F/$f"; done
# 공허 가드: 사본이 실 트리와 같은 subdir 집합이어야 canary 차이가 의미를 갖는다
if [ -z "$(_actual "$F")" ] || [ "$(_actual "$F")" != "$(_actual)" ]; then
  nope "T3.a reverse-observe" "사본 subdir 집합이 실 트리와 다르다 (사본=[$(_actual "$F" | tr '\n' ' ')])"
else
  mkdir -p "$F/scripts/tests/extract-test-commands"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$F/scripts/tests/extract-test-commands/test-glob-canary.sh"
  miss_after=$(comm -23 <(_actual "$F") <(_cover))
  echo "$miss_after" | grep -q 'extract-test-commands' \
    && ok "T3.a reverse-observe — 미등록 subdir FAIL 적발 (사본 canary)" \
    || nope "T3.a reverse-observe" "dummy 넣어도 미검출(계약 무력)"
fi

# ── T4: 주석 배제 — 커버 ⊆ 실제 (주석에만 있는 가짜 dir 오포획 없음) (AC-4) ──
# count 하드코딩 대신 역방향 부분집합: for-루프 형태를 주석에 써도 실제에 없으면 FAIL (plan-reviewer M-1)
extra=$(comm -13 <(_actual) <(_cover))
[ -z "$extra" ] && ok "T4.a 커버 ⊆ 실제 (주석 오포획 없음)" \
  || nope "T4.a 주석배제" "실제에 없는 커버 dir: $(echo $extra)"

echo ""
finish
