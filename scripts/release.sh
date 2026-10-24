#!/usr/bin/env bash
# Requires: git 2.23+ (rollback 이 `git restore` 사용), jq, bash 3.2+
set -euo pipefail

PLUGIN_ROOT="${RELEASE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PREFLIGHT_CMD="${RELEASE_PREFLIGHT_CMD:-}"
VERSION="${1:-}"
DRY_RUN=false
[ "${2:-}" = "--dry-run" ] && DRY_RUN=true

_sed_i() {
  if [[ "$(uname)" == "Darwin" ]]; then sed -i '' "$@"; else sed -i "$@"; fi
}

# FR-1: semver X.Y.Z 검증
if ! grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<< "$VERSION"; then
  echo "Error: semver X.Y.Z 형식이 아닙니다: '${VERSION}'" >&2
  exit 1
fi

# FR-2: git 워킹트리 클린 확인 — 추적 파일 변경(수정·삭제·스테이징)만 차단한다.
#   untracked 는 경고만: 릴리즈 커밋은 CHANGED_FILES 명시 목록만 add 하므로 untracked 가 섞이지 않는다
#   (v1.106.0 때 사용자 소유 untracked 폴더 때문에 GIT_CONFIG_* 우회가 필요했다 — FID 20261003-ops-debt).
if [ -n "$(git -C "$PLUGIN_ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
  echo "Error: git 워킹트리가 클린하지 않습니다. 커밋 또는 stash 후 재시도하세요." >&2
  exit 1
fi
_untracked=$(git -C "$PLUGIN_ROOT" status --porcelain 2>/dev/null | sed -n 's/^?? //p' || true)
if [ -n "$_untracked" ]; then
  _un_n=$(printf '%s\n' "$_untracked" | awk 'END { print NR }')
  _un_names=$(printf '%s\n' "$_untracked" | awk 'NR <= 5 { printf "%s%s", (NR > 1 ? ", " : ""), $0 }')
  _un_more=""; [ "$_un_n" -gt 5 ] && _un_more=" 외 $((_un_n - 5))개"
  echo "Warning: untracked ${_un_n}개 — ${_un_names}${_un_more} (릴리즈 커밋에는 포함되지 않습니다 — CHANGED_FILES 만 add)" >&2
fi

# FR-11: 이미 태그된 버전 확인
if grep -q "^v${VERSION}$" <<< "$(git -C "$PLUGIN_ROOT" tag -l "v${VERSION}" 2>/dev/null)"; then
  echo "Error: v${VERSION} already tagged" >&2
  exit 1
fi

# B#1: 버전 단조성 — 현재 plugin.json 버전보다 높아야 (회귀/중복 버전 발행 차단).
# 미태그 회귀버전(release 1.5.0)·동일버전 재발행을 사전 차단 — partial-failure 후
# 잔류 commit(plugin.json 이미 bump) 재실행도 여기서 명확히 거부된다.
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
if [ -f "$PLUGIN_JSON" ]; then
  CUR_VER=$(grep -oE '"version": *"[0-9]+\.[0-9]+\.[0-9]+"' "$PLUGIN_JSON" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  if [ -n "$CUR_VER" ]; then
    higher=$(printf '%s\n%s\n' "$CUR_VER" "$VERSION" | sort -V | tail -1)
    if [ "$VERSION" = "$CUR_VER" ] || [ "$higher" != "$VERSION" ]; then
      echo "Error: v${VERSION} 는 현재 버전 v${CUR_VER} 이하입니다 — 회귀/중복 발행 차단 (단조 증가 필요)" >&2
      exit 1
    fi
  fi
fi

_run_check() {
  local label="$1"
  if [ -n "$PREFLIGHT_CMD" ]; then
    # 테스트 전용 override (RELEASE_PREFLIGHT_CMD=true/false) — 프로덕션 미설정
    if ! eval "$PREFLIGHT_CMD" > /dev/null 2>&1; then
      echo "Error: pre-flight 검증 실패 ($label)" >&2
      exit 1
    fi
  else
    if ! bash "$PLUGIN_ROOT/$label" > /dev/null 2>&1; then
      echo "Error: pre-flight 검증 실패 ($label)" >&2
      exit 1
    fi
  fi
}

# run-all.sh 내부에서 호출된 경우 (test-release T10.b) pre-flight 재실행 시 무한 재귀 — skip
if [ "${SPECOPS_RUN_ALL:-}" = "1" ] && [ -z "$PREFLIGHT_CMD" ]; then
  echo "-> pre-flight skip (run-all 내부 — 재귀 방지)"
else
  # 같은 비문서 트리가 이미 전체 스위트를 통과했으면(다른 worktree 의 통과 기록 포함) 재실행하지 않는다 —
  #   판정은 full-suite-fresh.sh 하나(생략 방향 오판 경로 없음 계약) · 헬퍼 부재·STALE·판정 불가는 지금처럼 전체 실행
  #   (20261024-speed-release-fresh-task-record). 테스트 오버라이드(RELEASE_PREFLIGHT_CMD)보다 앞에서 본다 — 마커 없는 픽스처는 STALE 이다.
  _fresh=""
  _fresh_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_internal/full-suite-fresh.sh"
  if [ -f "$_fresh_sh" ]; then
    _fresh=$(cd "$PLUGIN_ROOT" && bash "$_fresh_sh" --any-worktree 2>/dev/null) || _fresh=""
  fi
  if [ -n "$_fresh" ]; then
    echo "-> pre-flight skip ($_fresh — 같은 비문서 트리가 이미 전체 스위트를 통과했다)"
    # 지문은 비문서 기준이라 문서만 바뀐 트리도 생략된다 — 문서 수치·구조 검사(수 초)는 그래도 돌린다(release 는 main 에 직접 push 한다)
    for _cheap in scripts/_internal/check-doc-numbers.sh scripts/_internal/validate-structure.sh; do
      [ -f "$PLUGIN_ROOT/$_cheap" ] || continue
      ( cd "$PLUGIN_ROOT" && bash "$_cheap" ) > /dev/null 2>&1 || { echo "Error: pre-flight 검증 실패 ($_cheap)" >&2; exit 1; }
    done
  else
    echo "-> pre-flight 검증 시작 (전체 테스트 aggregator)..."
    _run_check "scripts/tests/run-all.sh"
    echo "-> pre-flight PASS"
  fi
fi

# B층: llm-eval staleness soft 경고 (비차단 — LLM chain 은 run-all 밖이라 별도 신호)
# stat: GNU(-c) 우선, Darwin(-f) fallback — 역순이면 GNU 에서 -f 가 fs 덤프 출력 (hard fail 원인)
STAMP="$PLUGIN_ROOT/.specops-cache/llm-eval-last-run"
if [ ! -f "$STAMP" ]; then
  echo "⚠️  llm-eval 실행 기록 없음 — 릴리즈 전 bash scripts/tests/llm-eval/run-evals.sh 권장 (soft)" >&2
else
  stamp_epoch=$(stat -c %Y "$STAMP" 2>/dev/null || stat -f %m "$STAMP" 2>/dev/null || echo 0)
  age_days=$(( ( $(date +%s) - stamp_epoch ) / 86400 ))
  if [ "$stamp_epoch" -eq 0 ]; then
    echo "⚠️  llm-eval 스탬프 시각 판독 불가 — 재실행 권장 (soft)" >&2
  elif [ "$age_days" -gt 7 ]; then
    echo "⚠️  llm-eval 마지막 실행 ${age_days}일 경과 — 재실행 권장 (soft)" >&2
  fi
fi

# M1: specops_version 부패 soft 경고 (비차단 — 20260806 커맨드 전수 분석)
# FR-7 은 footer↔frontmatter **동기**만 한다. "본문이 substantive 하게 바뀌었는데 버전이
# 직전 태그와 동일" 은 아무도 안 봐서 CLAUDE.md 규약("마지막 substantive 변경 버전")이
# 조용히 썩는다. 실측: start.md 가 d1af18d 에서 end-loaded 절을 얻고도 1.0.0 잔존.
# footer 스탬프 줄만 바뀐 diff 는 substantive 가 아니다 — FR-7 이 매 릴리즈 건드리므로 제외.
# 태그 부재(최초 릴리즈)·git 실패는 fail-open.
_last_tag=$(git -C "$PLUGIN_ROOT" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
if [ -n "$_last_tag" ]; then
  _stale=""
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    [ -f "$PLUGIN_ROOT/$_f" ] || continue
    # footer 스탬프 줄을 제외한 실질 변경이 있는가
    # grep 무매치는 rc=1 — set -e·pipefail 하에서 스크립트를 죽인다.
    #   `{ …; } || echo 0` 은 wc 가 이미 "0" 을 낸 뒤 echo 가 **한 번 더** 붙어
    #   "0\n0" 이 되고, `[ "0\n0" -gt 0 ]` 가 integer 오류 → 그 파일이 조용히 누락된다.
    #   파이프라인 끝에 `|| true` 만 붙여 stdout(정상 "0")은 그대로 쓰고 exit 만 흡수한다.
    _subst=$(git -C "$PLUGIN_ROOT" diff -U0 "$_last_tag" -- "$_f" 2>/dev/null \
      | grep -E '^[+-]' | grep -Ev '^[+-][+-]' | grep -Ev '^[+-]\*specops-ko ' \
      | wc -l | tr -d ' ' || true)
    [ "${_subst:-0}" -gt 0 ] || continue
    _cur=$( { awk 'BEGIN{n=0} /^---/{n++; if(n==2)exit} /^specops_version:/{print $2; exit}' \
      "$PLUGIN_ROOT/$_f" 2>/dev/null; } || true)
    # `git show <tag>:<newfile>` 은 태그 시점에 없던 파일이면 **exit 128** 이다.
    #   set -euo pipefail 하에서 그대로 두면 스크립트가 통째로 중단된다(실측 rc=128) —
    #   신규 커맨드가 추가된 릴리즈는 항상 이 경로를 탄다. 빈 문자열로 흡수하면
    #   아래 `[ -n "$_old" ]` 가 자연히 걸러 "신규 파일은 부패 판정 대상 아님" 이 된다.
    _old=$( { git -C "$PLUGIN_ROOT" show "$_last_tag:$_f" 2>/dev/null \
      | awk 'BEGIN{n=0} /^---/{n++; if(n==2)exit} /^specops_version:/{print $2; exit}'; } || true)
    [ -n "$_cur" ] && [ -n "$_old" ] && [ "$_cur" = "$_old" ] && _stale="${_stale} $_f"
  done <<EOF
$(git -C "$PLUGIN_ROOT" diff --name-only "$_last_tag" -- 'commands/*.md' 'skills/*/SKILL.md' 'agents/*.md' 2>/dev/null)
EOF
  if [ -n "$_stale" ]; then
    echo "⚠️  specops_version 미갱신 (${_last_tag} 이후 본문 변경, soft):" >&2
    for _f in $_stale; do echo "      - $_f" >&2; done
    echo "    CLAUDE.md 규약: specops_version = 본문이 마지막으로 substantive 변경된 버전" >&2
  fi
fi

CHANGELOG="$PLUGIN_ROOT/CHANGELOG.md"
README="$PLUGIN_ROOT/README.md"
DATE=$(date +%Y-%m-%d)
CHANGED_FILES=()

# trap EXIT: best-effort 롤백
_do_rollback() {
  if [ ${#CHANGED_FILES[@]} -gt 0 ]; then
    echo "Error: 중간 실패 — best-effort 롤백 중..." >&2
    git -C "$PLUGIN_ROOT" restore -- "${CHANGED_FILES[@]}" 2>/dev/null || true
  fi
}
trap '_do_rollback' EXIT

# dry-run 분기
if $DRY_RUN; then
  echo "--- DRY-RUN 예정 작업 ---"
  echo "1. CHANGELOG: [Unreleased] -> [${VERSION}] — ${DATE} 변환"
  echo "2. README: 버전 배지 갱신"
  echo "3. commands/*.md: footer 스탬프 불일치 수정"
  echo "4. .claude-plugin/plugin.json + marketplace.json: 버전 bump"
  echo "5. git commit: chore: release v${VERSION}"
  echo "6. git tag: v${VERSION}"
  echo "7. git push (origin 존재 시): main + v${VERSION} 태그"
  echo "8. gh release create v${VERSION} (gh 설치 시): CHANGELOG [${VERSION}] 노트 + --latest"
  echo "--- DRY-RUN 완료 (변경 없음) ---"
  trap - EXIT
  exit 0
fi

# FR-4+FR-5: CHANGELOG 변환 (awk — cross-platform)
# B#2: 멱등 가드 — [VERSION] 섹션이 이미 존재하면 변환 skip (부분 실패 재실행 시
#   [Unreleased] 잔존으로 인한 [VERSION] heading 이중삽입 방지). 단조성 게이트(B#1)와 중첩 방어.
if grep -qE "^## \[${VERSION//./\\.}\]( |$)" "$CHANGELOG"; then
  echo "Warning: CHANGELOG 에 [${VERSION}] 섹션 이미 존재 — CHANGELOG 변환 skip (멱등)" >&2
elif grep -q '^## \[Unreleased\]$' "$CHANGELOG"; then
  CHANGED_FILES+=("$CHANGELOG")
  PREV=$(grep '^\[Unreleased\]:' "$CHANGELOG" | sed 's|.*compare/\([^.]*\.[^.]*\.[^.]*\)\.\.\.HEAD|\1|')
  BASE_URL=$(grep '^\[Unreleased\]:' "$CHANGELOG" | sed 's|\[Unreleased\]: \(.*\)/compare/.*|\1|')
  [ -z "$PREV" ] && echo "Warning: CHANGELOG.md에 [Unreleased]: compare 링크 없음 — 링크 갱신 skip" >&2

  # [Unreleased] 헤딩 아래 새 버전 헤딩 삽입
  awk -v ver="$VERSION" -v date="$DATE" '
    /^## \[Unreleased\]$/ { print; print ""; print "## [" ver "] — " date; next }
    { print }
  ' "$CHANGELOG" > "${CHANGELOG}.tmp" && mv "${CHANGELOG}.tmp" "$CHANGELOG"

  # compare 링크 갱신
  awk -v ver="$VERSION" -v prev="$PREV" -v base="$BASE_URL" '
    /^\[Unreleased\]:.*HEAD$/ {
      print "[Unreleased]: " base "/compare/v" ver "...HEAD"
      print "[" ver "]: " base "/compare/" prev "...v" ver
      next
    }
    { print }
  ' "$CHANGELOG" > "${CHANGELOG}.tmp" && mv "${CHANGELOG}.tmp" "$CHANGELOG"
else
  echo "Warning: CHANGELOG.md에 '## [Unreleased]' 섹션 없음 — CHANGELOG 갱신 skip" >&2
fi

# FR-6: README 버전 배지 갱신
CHANGED_FILES+=("$README")
OLD_VER=$(grep -oE '\(v[0-9]+\.[0-9]+\.[0-9]+\)' "$README" | head -1 | tr -d '()')
if [ -n "$OLD_VER" ]; then
  _sed_i "s|(${OLD_VER})|(v${VERSION})|g" "$README"
fi

# FR-6b: README footer 최신 버전 스탬프 갱신 (**최신: vX.Y.Z (날짜)**)
if grep -qE '최신: v[0-9]+\.[0-9]+\.[0-9]+' "$README"; then
  _sed_i "s|최신: v[0-9][0-9.]* ([0-9-]*)|최신: v${VERSION} (${DATE})|" "$README"
fi

# FR-7: commands/*.md footer 스탬프 불일치 수정
for cmd_file in "$PLUGIN_ROOT/commands/"*.md; do
  [ -f "$cmd_file" ] || continue
  # 추적되지 않는 파일은 릴리즈 대상이 아니다 — 클린 검사가 untracked 를 허용하면서 이 glob 이 파일시스템을 그대로 훑으면
  #   사용자 WIP 가 stamp 수정·릴리즈 커밋에 섞이고, 롤백의 git restore 가 pathspec 오류로 통째로 무력화된다(Phase C 실측).
  git -C "$PLUGIN_ROOT" ls-files --error-unmatch -- "commands/$(basename "$cmd_file")" >/dev/null 2>&1 || continue
  fm_ver=$(awk 'BEGIN{n=0} /^---/{n++; if(n==2)exit} /^specops_version:/{print $2}' "$cmd_file")
  [ -z "$fm_ver" ] && continue
  if grep -qE '^\*specops-ko v[0-9]' "$cmd_file"; then
    footer_ver=$(grep '^\*specops-ko' "$cmd_file" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d 'v')
    if [ -n "$footer_ver" ] && [ "$footer_ver" != "$fm_ver" ]; then
      CHANGED_FILES+=("$cmd_file")
      _sed_i "s|^\(\*specops-ko v\)[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*|\1${fm_ver}|" "$cmd_file"
    fi
  fi
done

# FR-7b: plugin.json/marketplace.json 버전 bump
for manifest in "$PLUGIN_ROOT/.claude-plugin/plugin.json" \
                "$PLUGIN_ROOT/.claude-plugin/marketplace.json"; do
  [ -f "$manifest" ] || continue
  _sed_i "s/\"version\": \"[0-9][^\"]*\"/\"version\": \"${VERSION}\"/" "$manifest"
  CHANGED_FILES+=("$manifest")
done

# FR-7c: marketplace metadata.description 내 (vX.Y.Z — 토큰 갱신
MARKET="$PLUGIN_ROOT/.claude-plugin/marketplace.json"
if [ -f "$MARKET" ] && grep -qE '\(v[0-9]+\.[0-9]+\.[0-9]+ —' "$MARKET"; then
  _sed_i "s|(v[0-9][0-9.]* —|(v${VERSION} —|" "$MARKET"
fi

echo "-> 파일 변환 완료"

# FR-8: post-flight
echo "-> post-flight 검증 시작..."
_run_check "scripts/_internal/validate-structure.sh"
echo "-> post-flight PASS"

# FR-9~FR-10: git commit + annotated tag
echo "-> git 커밋 및 태그 생성..."
git -C "$PLUGIN_ROOT" add "${CHANGED_FILES[@]}"
git -C "$PLUGIN_ROOT" commit -m "chore: release v${VERSION}"
git -C "$PLUGIN_ROOT" tag -a "v${VERSION}" -m "Release v${VERSION}"

trap - EXIT

echo ""
echo "로컬 릴리즈 완료 (v${VERSION})"

# FR-12: 원격 push + GitHub Release 발행
# origin 부재 시(테스트 임시 repo 등) push/release skip — fail-safe, 테스트 무손상
if ! git -C "$PLUGIN_ROOT" remote get-url origin > /dev/null 2>&1; then
  echo "원격 origin 없음 — push/release skip. 수동: git push && git push --tags"
  exit 0
fi

# origin main CI 가 red 면 경고한다 (경고 전용 — 차단 없음).
# 아래 push 는 SPECOPS_RUN_ALL=1 로 pre-push 재귀 가드를 켜므로, 훅 안의 check-ci-status
# 호출부(.githooks/pre-push 의 CI_CHECK 블록)에 도달하지 않는다 — 그 신호를 여기서 직접 복원한다.
# cwd 의존: check-ci-status.sh 는 `git remote get-url origin` 을 cwd 기준으로 본다 → 서브셸 cd 필수.
CI_CHECK="$PLUGIN_ROOT/scripts/_internal/check-ci-status.sh"
[ -f "$CI_CHECK" ] && (cd "$PLUGIN_ROOT" && bash "$CI_CHECK") || true

# 원격 단계 일부만 성공하면(20261021 실측: 클라우드 세션에서 main push 는 됐는데 태그 push 가 HTTP 403)
#   set -e 로 끝나 무엇이 이미 올라갔는지 알 수 없었다 — 어디까지 됐는지와 마무리 방법을 적고 실패로 끝낸다.
_partial_release() {  # <실패 단계>
  local sha; sha=$(git -C "$PLUGIN_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')
  echo "" >&2
  echo "Error: 부분 릴리즈 — '$1' 단계에서 실패했다 (로컬 커밋 ${sha} · 로컬 태그 v${VERSION} 는 있다)." >&2
  case "$1" in
    "main push")
      echo "  원격에는 아무것도 올라가지 않았다. 수동: git push && git push origin v${VERSION}" >&2 ;;
    "태그 push")
      echo "  main 은 이미 push 됐다(${sha}). 태그만 원격에 없다. 수동 중 하나:" >&2
      echo "    git push origin v${VERSION}" >&2
      echo "    또는 GitHub 웹 Releases → Draft a new release → 태그 v${VERSION} 새로 만들기(target ${sha}) → 노트는 CHANGELOG [${VERSION}] 절" >&2 ;;
    "GitHub Release")
      echo "  main·태그는 push 됐다. Release 만 없다. 수동: gh release create v${VERSION} --verify-tag --latest --generate-notes 또는 GitHub 웹에서 태그 v${VERSION} 로 Release 생성" >&2 ;;
  esac
  exit 1
}

echo "-> 원격 push..."
# pre-flight 가 방금 동일한 run-all.sh 전체를 통과했다(또는 같은 비문서 트리의 통과 기록으로 생략했다). SPECOPS_RUN_ALL=1 은 pre-push
# 재귀 가드(.githooks/pre-push 의 SPECOPS_RUN_ALL 분기)를 켜 같은 스위트의 중복 실행을 막는다.
# ★ 반드시 명령 prefix 로 둘 것 — 스크립트 전역으로 export 하면 release.sh:65 가
#   pre-flight 자체를 skip 해 게이트가 전면 상실된다 (T20.b 가 잠그는 유일 teeth —
#   T11.a 는 RELEASE_PREFLIGHT_CMD=true 로 도는 탓에 이 회귀에 발화하지 않는다).
SPECOPS_RUN_ALL=1 git -C "$PLUGIN_ROOT" push || _partial_release "main push"
SPECOPS_RUN_ALL=1 git -C "$PLUGIN_ROOT" push origin "v${VERSION}" || _partial_release "태그 push"

# gh CLI 미설치 시 release 만 graceful skip (push 는 이미 성공)
if ! command -v gh > /dev/null 2>&1; then
  echo "Warning: gh CLI 미설치 — GitHub Release 생성 skip." >&2
  echo "  수동: gh release create v${VERSION} --verify-tag --latest --generate-notes" >&2
  exit 0
fi

echo "-> GitHub Release 생성..."
# CHANGELOG 의 [VERSION] 섹션 본문을 release 노트로 추출 (헤더 제외)
NOTES_FILE=$(mktemp)
awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" { f=1; next }
  f && /^## \[/ { exit }
  f { print }
' "$CHANGELOG" > "$NOTES_FILE"

# compare 링크 추가 (PREV/BASE_URL 은 CHANGELOG 변환 단계에서 산출됨)
if [ -n "${PREV:-}" ] && [ -n "${BASE_URL:-}" ]; then
  printf '\n**Full Changelog**: %s/compare/%s...v%s\n' "$BASE_URL" "$PREV" "$VERSION" >> "$NOTES_FILE"
fi

# 노트 본문이 비면 gh 자동 생성으로 fallback
if [ -s "$NOTES_FILE" ]; then
  gh release create "v${VERSION}" \
    --repo "$(git -C "$PLUGIN_ROOT" remote get-url origin)" \
    --title "v${VERSION}" \
    --notes-file "$NOTES_FILE" \
    --verify-tag --latest || { rm -f "$NOTES_FILE"; _partial_release "GitHub Release"; }
else
  gh release create "v${VERSION}" \
    --repo "$(git -C "$PLUGIN_ROOT" remote get-url origin)" \
    --title "v${VERSION}" \
    --verify-tag --latest --generate-notes || { rm -f "$NOTES_FILE"; _partial_release "GitHub Release"; }
fi
rm -f "$NOTES_FILE"

echo ""
echo "릴리즈 발행 완료 (v${VERSION})"
