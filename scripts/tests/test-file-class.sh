#!/usr/bin/env bash
# 파일 분류 단일 SoT — bash case ↔ jq 정규식 동치 + 면제 클래스 일치
# 왜 필요한가: 면제 판정(_files_all_docs)과 무효화 판정(지문·편집이벤트)이 같은 기준을 써야 한다.
#   두 벌이 되면 문서 한 줄이 커밋을 막는 결함이 재발한다(20260912 실측: 문서 4종 STALE 오탐).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
FC="$PLUGIN/scripts/_internal/file-class.sh"

[ -f "$FC" ] || { echo "FATAL: file-class.sh 부재" >&2; exit 1; }
# shellcheck source=/dev/null
. "$FC"
type fc::is_doc >/dev/null 2>&1 || { echo "FATAL: fc::is_doc 미정의" >&2; exit 1; }

# 코퍼스: 문서 · screens · .specops · 런타임(중첩 포함) · 코드
# 형식: {경로}|{플러그인repo에서 기대: doc 또는 code}
# ★ 중첩 경로(skills/a/b/SKILL.md · commands/x/y.md)가 필수다 — bash 의 `*` 는 `/` 를 넘지만
#   jq 의 `[^/]+` 는 넘지 않아, 중첩이 없으면 두 계열이 갈라져도 이 테스트가 못 잡는다(실측).
CORPUS='CHANGELOG.md|doc
README.md|doc
CLAUDE.md|doc
docs/guide.md|doc
notes.txt|doc
spec.rst|doc
screens/login.html|doc
screens/a/b.html|doc
screens/sub/dir/x.html|doc
.specops/a/b.json|doc
skills/foo/SKILL.md|code
skills/a/b/SKILL.md|code
commands/bar.md|code
commands/x/y.md|code
agents/z.md|code
templates/t.md|code
hooks/h.sh|code
.claude-plugin/plugin.json|code
code.sh|code
src/app.ts|code'

# T1.a bash case 계열이 면제 클래스와 일치
_mis=0
while IFS='|' read -r p want; do
  [ -z "$p" ] && continue
  if fc::is_doc "$p" 0; then got=doc; else got=code; fi
  [ "$got" = "$want" ] || { _mis=$((_mis+1)); echo "  MISMATCH(bash) $p want=$want got=$got"; }
done <<EOF
$CORPUS
EOF
[ "$_mis" -eq 0 ] && ok "T1.a bash case 분류가 면제 클래스와 일치" || nope "T1.a bash case 분류" "불일치 $_mis 건"

# T1.b jq 정규식 계열이 **bash 계열과 동치** (중첩 경로 포함)
# ★ 기대값(want)이 아니라 bash 결과와 **직접 대조**한다 — want 비교만 하면 두 계열이 같은 방향으로
#   함께 틀어질 때 둘 다 조용히 통과한다(실측: case 제거 변이에서 bash 만 FAIL, jq 는 PASS 로 남았다).
#   동치를 주장하려면 두 계열의 출력을 맞대야 한다.
_mis=0
while IFS='|' read -r p want; do
  [ -z "$p" ] && continue
  if fc::is_doc "$p" 0; then b=doc; else b=code; fi
  j=$(jq -rn --arg p "$p" --arg doc "$FC_DOC_RE" --arg rt "$FC_RUNTIME_RE" \
    'if ($p | test($rt)) then "code" elif ($p | test($doc)) then "doc" else "code" end')
  [ "$b" = "$j" ] || { _mis=$((_mis+1)); echo "  DIVERGE $p bash=$b jq=$j"; }
done <<EOF
$CORPUS
EOF
[ "$_mis" -eq 0 ] && ok "T1.b jq 정규식이 bash case 와 동치 (중첩 경로 포함)" || nope "T1.b jq 동치" "발산 $_mis 건"

# T1.c 비플러그인 저장소에서는 런타임 예외가 없다 — *.md 전부 문서
if fc::is_doc "skills/foo/SKILL.md" 1; then
  ok "T1.c 비플러그인 저장소는 런타임 예외 없음"
else
  nope "T1.c 비플러그인 저장소는 런타임 예외 없음"
fi

# T1.d 패턴 리터럴이 governance-lib.sh 에 복제되지 않았다 (AC-6)
# ★ 두 벌이 되면 한쪽만 조여져 면제와 무효화가 어긋난다 — 그게 이 FID 가 고치는 병이다.
if grep -qE '\*\.md\|\*\.txt\|\*\.rst' "$PLUGIN/hooks/governance-lib.sh"; then
  nope "T1.d 패턴 리터럴 복제 0건" "governance-lib.sh 에 잔존"
else
  ok "T1.d 패턴 리터럴 복제 0건"
fi

finish
