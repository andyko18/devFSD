#!/usr/bin/env bash
# /init-project 오케스트레이터 — 10 Phase 구현 (T13b~T13f 가 각 phase 함수 추가)
# 한국 SI 표준 14종 산출물 자동 부트스트랩
set -u

PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# 14종 산출물 (root 4개 + .specops/memory 10개 — process-design.md 는 20261008 정본 편입)
ARTIFACTS_ROOT=("PRD.md" "CLAUDE.md" "README.md" "DESIGN.md")
ARTIFACTS_MEMORY=(
  ".specops/memory/constitution.md"
  ".specops/memory/requirements.md"
  ".specops/memory/test-strategy.md"
  ".specops/memory/architecture.md"
  ".specops/memory/frontend-architecture.md"
  ".specops/memory/backend-architecture.md"
  ".specops/memory/api-spec.md"
  ".specops/memory/data-model.md"
  ".specops/memory/screens-overview.md"
  ".specops/memory/process-design.md"
)
PROJECT_KIND=""           # 1=UI 2=BE 3=CLI 4=Full 5=Mobile 6=Other
CONFLICT_POLICY="skip"    # skip|overwrite|merge
PROJECT_NAME=""           # phase_1 에서 인자/basename 으로 설정
PRD_ONELINE=""            # PRD §1 한 줄 — phase_5 에서 CLAUDE/README 인용
BM_REF="n"               # brainstorming 메모 참조 여부 (y|n)
RESUME_MODE=${RESUME_MODE:-0}  # 1=resume 모드 (기존 파일 보존·누락만 생성)

# ── 분할 모듈 source (BASH_SOURCE 기준 — 임의 cwd 안전) ──
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/init-project/lib.sh"
source "$_DIR/init-project/phases-early.sh"
source "$_DIR/init-project/phases-design.sh"
source "$_DIR/init-project/phases-artifacts.sh"

_usage() {
  cat <<EOF
Usage: $0 [--resume] [--answers <파일>] [<project-name>]
       $0 --answers-template

devFSD 한국어 자율 Lifecycle 부트스트랩 — 한국 SI 표준 14종 산출물 자동 생성

Options:
  --resume              기존 파일 보존, 누락 파일만 생성 (부분 부트스트랩 재개)
  --answers <파일>      질문의 답을 키=값 파일로 준다 (순서 무관 · 비대화 호출의 권장 방식).
                        빠진 키·잘못된 값이 있으면 아무것도 쓰지 않고 rc=2 로 전부 알린다.
  --answers-template    답변 파일의 키 목록과 설명을 출력한다 (아무것도 쓰지 않는다)

입력: --answers 가 없으면 질문을 stdin 에서 순서대로 읽는다(터미널용). 터미널이 아닌데 입력이 모자라거나
      선택지가 아닌 값이 들어오면 기본값으로 이어 가지 않고 rc=2 로 멈춘다.

Phase:
  1  사전검사 (git/memory/ + 14종 파일별 표)
  2  종류 분류 (Web/UI · BE/API · CLI/lib · 풀스택 · 모바일 · 기타)
  3  헌법 입력
  4  PRD 입력 (numbered list 6 필드)
  5  CLAUDE.md 자동 생성
  6  DESIGN.md (UI/풀스택/모바일만)
  7  초기 화면 목록
  8  종류별 산출물 매트릭스 (8a~8i)
  9  README.md 자동 생성
  10 .specops/.gitignore + 스테이징 (커밋은 Phase 11 뒤 init-finalize.sh)
EOF
}

main() {
  local project_name="" want_template=0
  # 옵션은 위치와 무관하게 받는다. 모르는 `--*` 는 프로젝트 이름으로 삼지 않는다 —
  #   종전엔 `--enrich` 를 넘기면 README 제목이 `# --enrich` 가 됐다(20261009 재현).
  while [ $# -gt 0 ]; do
    case "$1" in
      --resume) RESUME_MODE=1 ;;
      --help|-h) _usage; exit 0 ;;
      --answers)
        [ $# -ge 2 ] || { echo "[init] --answers 뒤에 파일 경로가 필요합니다" >&2; exit 2; }
        ANSWERS_FILE="$2"; shift
        [ -n "$ANSWERS_FILE" ] || { echo "[init] --answers 의 파일 경로가 비어 있습니다" >&2; exit 2; } ;;
      --answers=*)
        ANSWERS_FILE="${1#--answers=}"
        [ -n "$ANSWERS_FILE" ] || { echo "[init] --answers 의 파일 경로가 비어 있습니다" >&2; exit 2; } ;;
      --answers-template) want_template=1 ;;
      --enrich)
        echo "[init] --enrich 는 이 스크립트의 옵션이 아닙니다 — bash 단계 없이 Phase 11(보강)만 하는 /init-project 의 모드입니다." >&2
        exit 2 ;;
      --*)
        echo "[init] 모르는 옵션: $1 (--help 참고)" >&2
        exit 2 ;;
      *)
        if [ -n "$1" ]; then
          [ -z "$project_name" ] || { echo "[init] 인자가 너무 많습니다: '$1' (프로젝트 이름은 하나)" >&2; exit 2; }
          project_name="$1"
        fi ;;
    esac
    shift
  done
  if [ "$want_template" = "1" ]; then
    _answers_template
    exit 0
  fi
  [ "$RESUME_MODE" = "1" ] && echo "[resume 모드] 기존 파일 보존, 누락 파일만 생성합니다." >&2
  # 답변 파일 경로는 repo 루트로 이동하기 **전에** 절대경로로 바꾼다
  if [ -n "$ANSWERS_FILE" ]; then
    case "$ANSWERS_FILE" in /*) ;; *) ANSWERS_FILE="$PWD/$ANSWERS_FILE" ;; esac
  fi
  _cd_repo_root
  _check_case_collision
  if [ -n "$ANSWERS_FILE" ]; then
    _check_git
    _answers_preflight
  fi
  phase_1_precheck "${project_name}"
  phase_2_classify
  phase_3_constitution
  phase_4_prd
  phase_5_claude
  phase_6_design
  phase_7_screens
  phase_8_artifacts
  phase_9_readme
  phase_10_commit
}

# source 가드 — sourced 시 함수만 로드 (테스트가 _replace_line_prefix 등 단위 호출 가능)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
