#!/usr/bin/env bash
# check-screens-overview.sh — 화면 목록 마스터 ↔ 실제 screens/ 대조·동기화
# 사용: bash scripts/_internal/check-screens-overview.sh <list|designed|diff|sync>
#   designed — 목적 칸이 `init 설계 완료` 로 시작하는 화면 이름만 낸다(20261112).
#     /init-project Phase 11 이 M1 범위 화면을 설계·리뷰까지 끝냈다는 표지다 —
#     /start-all Phase 2.5-A 가 이 이름을 다시 설계·리뷰하지 않는다. 표지가 없으면 빈 출력(종전 동작).
#
# 왜: /init-project Phase 7 이 만든 .specops/memory/screens-overview.md 를
#   /start-all Phase 2.5-A 가 읽지도 쓰지도 않아, 사용자가 정의한 화면이
#   어느 FR spec 에도 없으면 조용히 누락됐다(PR #32 가 한계로 기록).
#
# ★ 비차단이 계약이다 — 전 모드 rc=0. 마스터↔실제 불일치는 정당한 경우가
#   많고(다음 마일스톤 선등재·/design-screen 개별 생성분·낡은 마스터),
#   차단하면 false-deny → BYPASS 관성 경로다(CLAUDE.md).
set -u

# ★ 기본 경로는 **cwd 상대**다 — 형제 판정기와 동일 규약
#   (check-foundation-shell-baseline.sh:15 · check-screen-quality.sh:111 · check-fr-table.sh:35).
#   플러그인 설치 루트를 기준으로 잡으면 하류 프로젝트에서 **영구 no-op** 이 된다 —
#   배선이 "${CLAUDE_PLUGIN_ROOT}"/scripts/... 로 부르므로 스크립트 위치는 캐시 디렉터리다(실측).
OVERVIEW="${SPECOPS_SCREENS_OVERVIEW:-.specops/memory/screens-overview.md}"
SCREENS_DIR="${SPECOPS_SCREENS_DIR:-screens}"
MODE="${1:-diff}"

# fence 안 name 컬럼만 — design-screen.sh:142-147 과 동일 관용구.
#   fence 밖 예시 행·name 헤더를 실데이터로 세면 유령 화면이 된다(07ef42e).
# fence 가 **양쪽 다** 성립해야 표로 인정한다 (Phase C I1).
#   end 만 검사하면 두 방향으로 깨진다 —
#   ① start 부재: awk 가 이름을 0개 뽑아 `list` 는 비는데, sync 는 그 빈 목록을
#      기준으로 차집합을 내므로 **매 실행마다 같은 행을 다시 추가**한다(실측: 3회 → 3행).
#      start-all.md 가 약속한 "멱등" 이 거짓이 되고, 그 행들은 `list` 가 못 읽어
#      Step 1 합류에도 안 들어간다 — 쓰기는 되는데 아무도 못 보는 상태.
#   ② end 부재: fence 가 파일 끝까지 열려 무관한 표를 흡수한다(07ef42e 클래스).
#   `2>/dev/null` — 마스터가 읽기 불가일 때 stderr 노이즈 없이 "fence 불성립" 으로
#   일관 처리한다. 비차단 계약이라 어느 쪽이든 rc=0 이다.
_fence_ok() {
  [ -f "$OVERVIEW" ] || return 1
  grep -q '^<!-- screens-table:start -->' "$OVERVIEW" 2>/dev/null || return 1
  grep -q '^<!-- screens-table:end -->'   "$OVERVIEW" 2>/dev/null || return 1
}

_master_names() {
  _fence_ok || return 0
  awk '
    /^<!-- screens-table:start -->/ { inside=1; next }
    /^<!-- screens-table:end -->/   { inside=0; next }
    inside && /^\|/ {
      split($0, f, "|"); gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[2])
      if (f[2] != "name" && f[2] != "") print f[2]
    }
  ' "$OVERVIEW"
}
# 목적 칸(셋째 칸)이 `init 설계 완료` 로 **시작**하는 행만 — 초안 표지 `init 보강 (미확정 N)` 과
#   손으로 쓴 목적 문장 속의 같은 낱말(칸 중간)은 세지 않는다.
_designed_names() {
  _fence_ok || return 0
  awk '
    /^<!-- screens-table:start -->/ { inside=1; next }
    /^<!-- screens-table:end -->/   { inside=0; next }
    inside && /^\|/ {
      split($0, f, "|")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[2]); gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[4])
      if (f[2] != "name" && f[2] != "" && index(f[4], "init 설계 완료") == 1) print f[2]
    }
  ' "$OVERVIEW"
}
_screen_names() {
  [ -d "$SCREENS_DIR" ] || return 0
  for f in "$SCREENS_DIR"/*.md; do [ -f "$f" ] || continue; basename "$f" .md; done
}

case "$MODE" in
  list) _master_names; exit 0 ;;
  designed) _designed_names; exit 0 ;;
  diff|sync)
    if [ ! -f "$OVERVIEW" ]; then
      echo "SCREENS-OVERVIEW: SKIP (마스터 부재 — $OVERVIEW)"; exit 0
    fi
    m=$(_master_names | sort); s=$(_screen_names | sort)
    only_m=$(comm -23 <(printf '%s\n' "$m") <(printf '%s\n' "$s") | grep -v '^$' || true)
    only_s=$(comm -13 <(printf '%s\n' "$m") <(printf '%s\n' "$s") | grep -v '^$' || true)
    if [ "$MODE" = "sync" ]; then
      added=0
      if [ -n "$only_s" ]; then
        # ★ awk -v 로 다중행을 넘기지 않는다 — BSD awk 가 "newline in string" 으로 죽는데
        #   호출부는 그걸 모르고 added 를 그대로 보고한다(실측: 보고 1, 실제 기록 0).
        # ★ end 줄번호만 보지 않는다 — start 가 없으면 위 _master_names 가 빈 목록을
        #   내므로 차집합이 매번 전량이 되어 중복이 쌓인다(Phase C I1).
        _fence_ok || { echo "SCREENS-OVERVIEW: SKIP (fence 없음)"; exit 0; }
        end_ln=$(grep -n '^<!-- screens-table:end -->' "$OVERVIEW" | head -1 | cut -d: -f1)
        [ -n "$end_ln" ] || { echo "SCREENS-OVERVIEW: SKIP (fence 없음)"; exit 0; }
        # ★ mktemp 를 쓰지 않는다 — 기본 모드 0600 이 mv 로 넘어가 마스터 퍼미션이 바뀌고,
        #   /tmp 가 다른 파일시스템이면 mv 가 원자 rename 이 아니다. design-screen.sh:167 선례.
        tmp="${OVERVIEW}.tmp"
        head -n $((end_ln-1)) "$OVERVIEW" > "$tmp" || { rm -f "$tmp"; echo "SCREENS-OVERVIEW: SKIP (임시파일 쓰기 실패)"; exit 0; }
        while IFS= read -r n; do
          [ -z "$n" ] && continue
          printf '| %s | %s | TODO | [screens/%s.md](../../screens/%s.md) | [screens/%s.html](../../screens/%s.html) |\n' \
            "$n" "$n" "$n" "$n" "$n" "$n" >> "$tmp"
          added=$((added+1))
        done <<< "$only_s"
        tail -n +"$end_ln" "$OVERVIEW" >> "$tmp" && mv "$tmp" "$OVERVIEW" || { rm -f "$tmp"; echo "SCREENS-OVERVIEW: SKIP (갱신 실패 — 원본 보존)"; exit 0; }
      fi
      echo "SCREENS-OVERVIEW: SYNC added=$added"; exit 0
    fi
    [ -n "$only_m" ] && while IFS= read -r n; do [ -n "$n" ] && printf 'MASTER-ONLY: %s\n' "$n"; done <<< "$only_m"
    [ -n "$only_s" ] && while IFS= read -r n; do [ -n "$n" ] && printf 'SCREENS-ONLY: %s\n' "$n"; done <<< "$only_s"
    if [ -z "$only_m" ] && [ -z "$only_s" ]; then echo "SCREENS-OVERVIEW: OK"; else echo "SCREENS-OVERVIEW: DIFF"; fi
    exit 0 ;;
  *) echo "SCREENS-OVERVIEW: SKIP (알 수 없는 모드: $MODE)" >&2; exit 0 ;;
esac
