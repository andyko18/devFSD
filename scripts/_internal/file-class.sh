#!/usr/bin/env bash
# library-only
# 파일 1건 분류 단일 SoT (20260912-verify-stale-docs-scope).
#
# 왜 한 곳인가: verify **면제** 판정(`_files_all_docs`)과 verify **무효화** 판정(지문·편집 이벤트)이
#   "변경" 을 서로 다르게 정의해, 문서 한 줄이 커밋을 막고 전체 스위트 재실행을 강요했다.
#   면제 경로의 분류 규칙은 20260813-r1-docs-only-scope 계열로 세 번 정밀해졌는데
#   무효화 경로는 그 개선을 한 번도 받지 못했다 — 그 비대칭을 없애는 것이 이 파일의 목적이다.
#
# 두 계열을 함께 제공한다:
#   - bash `case` (`fc::is_doc`)        : 지문 계산용. 파일 수만큼 도는 루프라 프로세스 스폰이 없다.
#   - jq/grep 정규식 (`FC_*_RE`)        : transcript 판정용. jq 는 bash 함수를 부를 수 없어 `--arg` 로 넘긴다.
#   두 계열의 동치는 `scripts/tests/test-file-class.sh` 가 강제한다 — 갈라지면 면제와 무효화가 어긋난다.
#   (`_RUNNER_ANCHOR_PAT` ↔ T70 이 같은 이유로 쓰는 구조다.)
#
# ★ jq 정규식은 `[^/]+` 가 아니라 `.*` 다: bash 의 `*` 는 `/` 를 넘는다.
#   실측 — `skills/*/SKILL.md` 는 `skills/a/b/SKILL.md` 를, `commands/*.md` 는 `commands/x/y.md` 를 매치한다.
#   `[^/]+` 로 쓰면 중첩 경로에서 런타임 파일이 "문서" 로 오분류돼 R-1 면제가 넓어진다.

# 플러그인 런타임 경로 — 확장자와 무관하게 **코드**다 (20260828-md-runtime-scope).
#   이 플러그인의 실행 로직은 산문이다: skills/*/SKILL.md 한 줄이 chain 동작을 바꾼다.
# shellcheck disable=SC2034  # 외부 소비 변수 — jq --arg 로 governance-lib 3경로가 주입해 쓴다
#   skills/ 아래는 SKILL.md 만이 아니다 — implementing-ko 가 wave 직전에 Read 하는 dev-autonomy.md · planning-ko 전문가 patterns/*.md ·
#   리뷰어 프롬프트 같은 보조 md 도 모델이 읽고 따르는 행동 규칙이다(11회차 E-1: 이 파일들이 "문서" 로 면제돼 검증 없이 커밋됐다).
#   단 `skills/<이름>/README.md` 는 배포 런타임이 아니라 사람이 읽는 문서라 면제 유지(T-plug.h) — 음의 전방탐색이라 FC_RUNTIME_RE 도
#   jq 전용이다(grep -E 로 쓰지 말 것: quick-scope 는 jq 로 판정한다).
FC_RUNTIME_RE='^(skills/(?![^/]+/README\.md$).*\.md|commands/.*\.md|agents/.*\.md|templates/.*\.md|hooks/.*|\.claude-plugin/.*)$'

# 문서·아티팩트 — 실행 코드가 살 수 없는 경로.
#   screens/*.html 은 저장소 루트 한정(design-first 미리보기), .specops/ 는 lifecycle 아티팩트 도메인.
# ★ screens 는 `.*` 다 — bash `screens/*.html` 이 `/` 를 넘으므로 `[^/]*` 로 쓰면 중첩 경로에서
#   두 계열이 갈라진다(실측: `screens/a/b.html` → bash=doc · jq=code). 위 런타임 패턴이 같은 이유로
#   `.*` 를 쓰는데 이 줄만 함정을 밟고 있었다 — Phase C I-2.
#   .txt 는 문서지만 **빌드·의존성 목록**은 코드다(11회차 E-6) — requirements*.txt · constraints*.txt · CMakeLists.txt 와
#   requirements/·constraints/ 폴더 아래 txt. 의존성 한 줄이 테스트 결과를 바꾸는데 "문서" 로 면제돼 verify 없이 열렸다.
#   이 예외는 플러그인 repo 한정이 아니다 — 하류 앱의 requirements.txt 도 코드다. 예외는 Oniguruma 의 음의 전방탐색이라
#   FC_DOC_RE 는 jq 전용이다(grep -E 로 쓰지 말 것 — bash 계열은 아래 fc::is_doc 의 case 가 같은 집합을 낸다).
FC_DOC_RE='(\.md|\.rst)$|^(?!(?:.*/)?(?:CMakeLists|[^/]*requirements[^/]*|[^/]*constraints[^/]*)\.txt$)(?!(?:.*/)?(?:requirements|constraints)/).*\.txt$|^screens/.*\.html$|^\.specops/'

# 이 저장소에서 `.md` 가 런타임인가 — Claude Code 플러그인 저장소 판정.
#   루프 **밖에서 1회만** 부른다(파일마다 부르면 변경 파일 수만큼 프로세스를 스폰한다 — 훅은 hot path).
fc::is_plugin_repo() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -f "$root/.claude-plugin/plugin.json" ]
}

# $1=경로(저장소 상대) · $2=플러그인repo 판정 rc(0=맞음). $2 생략 시 매 호출 판정하므로 루프에선 넘길 것.
# rc: 0=문서(면제) · 1=코드(비면제)
fc::is_doc() {
  local f="$1" plugin_rc="${2:-}"
  [ -n "$f" ] || return 1
  if [ -z "$plugin_rc" ]; then
    if fc::is_plugin_repo; then plugin_rc=0; else plugin_rc=1; fi
  fi
  # 플러그인 저장소에서만 런타임 예외를 건다 — 이 경로들은 Claude Code 플러그인 규약이지 앱 규약이 아니다.
  #   무조건 걸면 하류 앱의 templates/email.md 가 문서 커밋에서 막히고, false-deny 가 BYPASS 관성을 만든다.
  if [ "$plugin_rc" -eq 0 ] && ! [[ "$f" =~ ^skills/[^/]+/README\.md$ ]]; then
    case "$f" in
      skills/*.md|commands/*.md|agents/*.md|templates/*.md|hooks/*|.claude-plugin/*) return 1 ;;
    esac
  fi
  # .specops/ 는 lifecycle 아티팩트 도메인이라 어떤 이름이든 문서 — jq 계열은 `|^\.specops/` 가 독립 대안이라 그렇게 낸다(리뷰 I-1 발산).
  case "$f" in .specops/*) return 0 ;; esac
  # 빌드·의존성 목록 txt 는 코드 — FC_DOC_RE 의 전방탐색 예외와 같은 집합이다(basename 글로브 + 폴더 이름).
  case "${f##*/}" in
    CMakeLists.txt|*requirements*.txt|*constraints*.txt) return 1 ;;
  esac
  case "$f" in
    requirements/*.txt|*/requirements/*.txt|constraints/*.txt|*/constraints/*.txt) return 1 ;;
  esac
  case "$f" in
    *.md|*.txt|*.rst) return 0 ;;
    screens/*.html|.specops/*) return 0 ;;
    *) return 1 ;;
  esac
}
