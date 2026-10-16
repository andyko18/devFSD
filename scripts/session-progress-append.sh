#!/usr/bin/env bash
# session-progress.md FID 섹션 자동 append helper (v0.4-pre P1 신설)
# Usage: scripts/session-progress-append.sh <FID> <command> <status> [memo] [feature-name]
# - FID:     20260426-epoch-iso-cli 형식
# - command: /specify, /clarify, /plan, /tasks, /implement, /verify, /request-review, /receive-review 등
# - status:  완료 | 진행 | BLOCK | DONE | PASS | FAIL 등
# - memo:    선택 — 산출 파일·결과 요약 (예: "spec.md, AC.md")
# - feature-name: 선택 — FID 섹션 생성 시 헤더에 추가 (예: "한국어 URL Slug 변환 CLI")
#
# 동작:
#   1. .specops/session-progress.md 부재 시 templates에서 자동 생성 (ensure-session-progress.sh 호출)
#   2. FID 섹션 (## <FID>) 없으면 파일 상단 (## <FID-1> 자리) 에 신규 섹션 prepend
#   3. 있으면 해당 섹션 첫 줄에 "- <ts> <command> <status> (<memo>)" prepend
#
# 멱등 안전:
#   - 같은 (FID, command, status, memo) 한 줄이 이미 섹션 첫 줄이면 중복 추가 안 함
#
# 참조: templates/session-progress.md (포맷 정의), 마스터 plan v0.4-pre P1

set -u

if [ "$#" -lt 3 ]; then
  cat <<EOF >&2
usage: $0 <FID> <command> <status> [memo] [feature-name]
  FID 형식: YYYYMMDD-kebab-slug (예: 20260426-epoch-iso-cli)
  command:  /specify, /clarify, /plan, /tasks, /implement, /verify 등
  status:   완료 | 진행 | BLOCK | DONE | PASS | FAIL
  memo:     선택, 산출 파일·결과 요약
  feature-name: 선택, FID 섹션 헤더 부속 (신규 섹션 생성 시만)
EOF
  exit 2
fi

# worktree 에서 불려도 메인 worktree 의 .specops 에 쓴다 (20261016-hook-worktree-target — specops-root.sh 머리 참조)
#   자기 경로는 이동 전에 절대경로로 잡는다(상대경로 호출이면 이동 뒤 뜻이 바뀐다).
_SPA_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
. "$_SPA_DIR/_internal/specops-root.sh" 2>/dev/null && specops_root_enter || true

# .specops 가 symlink 면 거부 — 악성 repo clone 시 외부 dir write-through(path-escape) 차단
if [ -L ".specops" ]; then
  echo "ERROR: .specops 가 symlink — 쓰기 거부(path-escape 차단)" >&2
  exit 1
fi

FID=$1
COMMAND=$2
STATUS=$3
MEMO=${4:-}
FEATURE=${5:-}

# FID 포맷 검증
if ! printf '%s' "$FID" | grep -Eq '^[0-9]{8}-[a-z0-9-]+$'; then
  echo "error: invalid FID format '$FID' (expected YYYYMMDD-kebab-slug)" >&2
  exit 1
fi

TARGET=".specops/session-progress.md"

# ── active-fid 마커 upsert (FID 20260809-active-fid-marker-producer) ──
# 왜 필요한가: hooks/governance-lib.sh 의 detect_fid() 가 이 마커를 **1순위**로 읽는데
#   (주석의 U8 — 다중 FID 환경 first-only 회피) 갱신하는 층이 **0곳**이었다. 소비자만
#   있고 생산자가 없어 한 번 기록된 값이 영원히 고착된다. 실사용 관측(20260809):
#   R-1 게이트가 직전 FID 의 verify 증거를 요구해 `git commit` 이 2회 막혔고 사람이
#   수동 sed 로 풀었다.
# 왜 2순위로 못 때우나: 섹션은 **prepend** 되므로 첫 h2 헤더는 "가장 최근 **생성**된
#   FID" 이지 활성 FID 가 아니다 — 재개 시 둘이 갈린다(마커가 도입된 이유가 그것).
# 왜 replace 단독이 아닌가: 마커가 **없는** 파일(신규 프로젝트·구 파일)에서 치환은
#   조용히 no-op 이 된다. 삽입 경로가 없으면 그 파일은 영원히 2순위에 머문다.
# 왜 sed -i 가 아닌가: GNU/BSD 인자 분기(`sed -i ''`)를 피해 awk + mv 로 통일한다.
# 실패해도 스크립트를 죽이지 않는다 — 섹션 기록이 1차 목적이고 이미 끝난 뒤 호출된다.
_upsert_active_fid() {
  local fid="$1" target="$2" tmp
  # ★ 테스트 fixture 는 활성 FID 로 승격하지 않는다 (20260829-fixture-fid-hijack).
  #   /e2e-test 는 12스텝 내내 이 스크립트를 부르므로 마커가 fixture 로 덮이고, 그 뒤
  #   **모든 커밋이 fixture 의 verify 상태를 대신 answer** 해야 한다(R-1 ②앵커). 게다가
  #   fixture 테스트는 `.specops/<FID>/*.sh` 라 run-verification 실행 whitelist 밖이어서
  #   구조적으로 PASS 를 낼 수 없다 — 정직한 탈출구가 없어 BYPASS 만 남는다(실측 3회).
  #   섹션 기록 자체는 그대로 남긴다(증거 보존) — 막는 것은 **활성 지목**뿐이다.
  #   사람이 마커를 손으로 써서 fixture 를 지목하는 것은 여전히 존중된다(소비자 1순위 불변).
  if [ -f ".specops/$fid/.fixture" ]; then
    return 0
  fi
  tmp=$(mktemp) || { echo "warn: active-fid 마커 갱신 skip (mktemp 실패)" >&2; return 0; }
  # ★ 생산자 앵커는 소비자와 **대칭**이어야 한다 — detect_fid 의 grep 은 무앵커(행 내
  #   아무 위치)라, 생산자만 `^<!--` 로 조이면 **선행 공백이 붙은 마커**(수동 편집 흔적:
  #   이 결함의 기원이 바로 수동 sed 다)를 못 보고 아래에 새 마커를 추가한다. 그러면
  #   소비자의 `grep -m1` 이 위쪽 stale 을 먼저 집어 **재실행해도 자기치유되지 않는다**
  #   (Phase C 프로브 P2 실증: 두 번 돌려도 detect_fid=20260101-stale 고착).
  #   또 이미 오염된 파일의 **후속 중복 마커는 청소**한다 — 하나만 남기는 것이 계약이다.
  if FID="$fid" awk '
    BEGIN { done = 0 }
    /^[[:space:]]*<!--[[:space:]]*active-fid:/ {
      if (!done) { printf "<!-- active-fid: %s -->\n", ENVIRON["FID"]; done = 1 }
      next
    }
    !done && /^#/ {
      printf "<!-- active-fid: %s -->\n\n", ENVIRON["FID"]; done = 1; print; next
    }
    { print }
    END { if (!done) printf "<!-- active-fid: %s -->\n", ENVIRON["FID"] }
  ' "$target" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$target"
  else
    # 무음 실패는 마커 고착 재발을 흔적 없이 숨긴다 — 1줄이라도 남긴다(원칙 5).
    rm -f "$tmp"
    echo "warn: active-fid 마커 갱신 skip (섹션 기록은 완료)" >&2
  fi
  return 0
}

# 파일 부재 시 ensure-session-progress.sh 호출하여 생성
if [ ! -f "$TARGET" ]; then
  script_dir=$_SPA_DIR
  plugin_root=$(dirname "$script_dir")
  # 진행 기록 쓰기는 lifecycle 의 명시적 행위라 관할을 여는 쪽이다 — 디렉토리는 여기서 만든다.
  #   (ensure-session-progress 는 Stop 훅으로도 돌아 `.specops/` 부재 시 아무것도 만들지 않는다.)
  [ -L ".specops" ] || mkdir -p ".specops" 2>/dev/null || true
  # 훅의 킬스위치(설정·프로파일)는 Stop 훅의 자동 생성을 끄는 것이다 — 여기는 명시적 기록이라 그와 무관하게 만든다.
  SPECOPS_ENSURE_EXPLICIT=1 bash "$plugin_root/hooks/ensure-session-progress.sh" >/dev/null 2>&1
  if [ ! -f "$TARGET" ]; then
    echo "error: failed to create $TARGET" >&2
    exit 1
  fi
fi

# 이중화 — prepend 직전 현 상태를 .bak 1세대로 백업 (best-effort, 실패해도 prepend 계속 — AC-2)
[ -f "$TARGET" ] && cp "$TARGET" "$TARGET.bak" 2>/dev/null || true

TS=$(date +"%Y-%m-%d %H:%M")
LINE="- $TS $COMMAND $STATUS"
if [ -n "$MEMO" ]; then
  LINE="$LINE ($MEMO)"
fi

# FID 섹션 존재 여부 확인
SECTION_HEADER="## $FID"
if grep -qF "$SECTION_HEADER" "$TARGET"; then
  # 섹션 존재 — 섹션 직후 첫 빈 줄 다음에 LINE prepend (멱등 체크 후)
  # 멱등 — 섹션 전체 스캔 (AC-5): FID 섹션 내 동일 line 존재 시 추가 skip
  already=$(LINE="$LINE" FID="$FID" awk '
    /^## / { in_s = ($0 == "## " ENVIRON["FID"] || index($0, "## " ENVIRON["FID"] " ") == 1) ? 1 : 0 }
    in_s && $0 == ENVIRON["LINE"] { found = 1 }
    END { print (found ? "1" : "0") }
  ' "$TARGET")
  if [ "$already" = "1" ]; then
    echo "already present (idempotent): $FID"
    exit 0
  fi
  # awk로 처리: ## <FID> 이후 첫 빈 줄 만나면 LINE 추가, 그 다음 기존 줄들
  TMP=$(mktemp) || exit 1
  LINE="$LINE" FID="$FID" awk '
    BEGIN { added = 0; in_section = 0 }
    /^## / {
      if (in_section && !added) { print ENVIRON["LINE"]; added = 1 }
      if ($0 == "## " ENVIRON["FID"] || index($0, "## " ENVIRON["FID"] " ") == 1) {
        in_section = 1
        print
        next
      } else {
        in_section = 0
      }
    }
    in_section && !added && /^- / {
      if ($0 != ENVIRON["LINE"]) { print ENVIRON["LINE"] }
      added = 1
      print
      next
    }
    { print }
    END {
      if (in_section && !added) print ENVIRON["LINE"]
    }
  ' "$TARGET" > "$TMP" && mv "$TMP" "$TARGET"
  _upsert_active_fid "$FID" "$TARGET"
  echo "appended to existing section: $FID"
else
  # 섹션 없음 — 파일 상단 (구분선 --- 다음 첫 ## 자리) 에 신규 섹션 prepend
  HEADER="## $FID"
  if [ -n "$FEATURE" ]; then
    HEADER="$HEADER · $FEATURE"
  fi
  TMP=$(mktemp) || exit 1
  HEADER="$HEADER" LINE="$LINE" awk '
    BEGIN { added = 0 }
    /^---$/ && !added {
      print
      print ""
      print ENVIRON["HEADER"]
      print ""
      print ENVIRON["LINE"]
      print ""
      added = 1
      next
    }
    { print }
  ' "$TARGET" > "$TMP" && mv "$TMP" "$TARGET"
  _upsert_active_fid "$FID" "$TARGET"
  echo "created new section: $HEADER"
fi
