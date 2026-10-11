#!/usr/bin/env bash
# 결정 원장 확정값 판정 — 20260806 /start-foundation 후속
#
# 결함: `decisions.md` 소비 규칙(HARD)은 "확정값이 있는 주제는 BLOCKING 재질문 금지" 인데,
#   판정이 모델 눈대중이었다. 그런데 `/init-project` Phase 10 이 만드는 **골격에는
#   예시 행이 들어 있다**:
#     | D-001 | (예시) UI 유무 | 있음 | init Phase11.5 | YYYY-MM-DD |
#   빈 원장이 "행이 있는 원장" 처럼 보이므로, foundation BLOCKING 면제(스택 확정)가
#   근거 없이 열릴 수 있다. 소비처가 6곳(clarifying·specifying·start-all(-auto)·
#   start-foundation·init-project)이라 공유 판정기가 필요하다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-decisions-ledger.sh"

_ledger() {  # $1=dir  (stdin = 표 행들)
  mkdir -p "$1/.specops/memory"
  { printf '# 결정 원장\n\n| DECISION-ID | 주제 | 확정값 | 출처 | 갱신일 |\n|---|---|---|---|---|\n'
    printf '<!-- decisions-table:start -->\n'
    cat
    printf '<!-- decisions-table:end -->\n'
  } > "$1/.specops/memory/decisions.md"
}

# T1: ★ 골격 그대로(예시 행만) → 미확정 (핵심 — 눈대중이면 "확정됨" 으로 오독)
TD=$(mktemp -d)
_ledger "$TD" <<'EOF'
| D-001 | (예시) UI 유무 | 있음 | init Phase11.5 | YYYY-MM-DD |
EOF
(cd "$TD" && bash "$CHK" '프론트' >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T1 골격(예시 행만) → 미확정" || nope "T1" "rc=$rc"
rm -rf "$TD"

# T2: 예시 행 자체를 주제로 물어도 미확정 ((예시) 접두는 실결정 아님)
TD=$(mktemp -d)
_ledger "$TD" <<'EOF'
| D-001 | (예시) UI 유무 | 있음 | init Phase11.5 | YYYY-MM-DD |
EOF
(cd "$TD" && bash "$CHK" 'UI 유무' >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T2 (예시) 접두 행 → 미확정" || nope "T2" "rc=$rc"
rm -rf "$TD"

# T3: 실제 확정 행 → 확정
TD=$(mktemp -d)
_ledger "$TD" <<'EOF'
| D-001 | 프론트엔드 스택 | React 19 + Vite | clarify 20260806-x | 2026-08-06 |
EOF
(cd "$TD" && bash "$CHK" '프론트' >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T3 실제 확정 행 → 확정" || nope "T3" "rc=$rc"
rm -rf "$TD"

# T4: 확정값이 placeholder → 미확정
TD=$(mktemp -d)
_ledger "$TD" <<'EOF'
| D-001 | 백엔드 스택 | <미확정 — 근거 필요> | init Phase11.5 | 2026-08-06 |
EOF
(cd "$TD" && bash "$CHK" '백엔드' >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T4 placeholder 확정값 → 미확정" || nope "T4" "rc=$rc"
rm -rf "$TD"

# T5: 확정값이 빈칸 → 미확정
TD=$(mktemp -d)
_ledger "$TD" <<'EOF'
| D-001 | 백엔드 스택 |  | init Phase11.5 | 2026-08-06 |
EOF
(cd "$TD" && bash "$CHK" '백엔드' >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T5 빈 확정값 → 미확정" || nope "T5" "rc=$rc"
rm -rf "$TD"

# T6: 무정보 값(TBD·미정) → 미확정
TD=$(mktemp -d)
_ledger "$TD" <<'EOF'
| D-001 | 배포 | TBD | init Phase11.5 | 2026-08-06 |
| D-002 | 인증 | (미정) | init Phase11.5 | 2026-08-06 |
EOF
(cd "$TD" && bash "$CHK" '배포' >/dev/null 2>&1); rc1=$?
(cd "$TD" && bash "$CHK" '인증' >/dev/null 2>&1); rc2=$?
[ "$rc1" -eq 1 ] && [ "$rc2" -eq 1 ] && ok "T6 TBD·(미정) → 미확정" || nope "T6" "rc=$rc1/$rc2"
rm -rf "$TD"

# T7: 원장 파일 부재 → 미확정(1) — 없으면 물어야 한다
TD=$(mktemp -d); mkdir -p "$TD/.specops/memory"
(cd "$TD" && bash "$CHK" '프론트' >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T7 원장 부재 → 미확정" || nope "T7" "rc=$rc"
rm -rf "$TD"

# T8: 예시 행 + 실결정 혼재 → 실결정만 인정
TD=$(mktemp -d)
_ledger "$TD" <<'EOF'
| D-001 | (예시) UI 유무 | 있음 | init Phase11.5 | YYYY-MM-DD |
| D-002 | 프론트엔드 스택 | React 19 | clarify 20260806-x | 2026-08-06 |
EOF
(cd "$TD" && bash "$CHK" '프론트' >/dev/null 2>&1); rc1=$?
(cd "$TD" && bash "$CHK" 'UI 유무' >/dev/null 2>&1); rc2=$?
[ "$rc1" -eq 0 ] && [ "$rc2" -eq 1 ] && ok "T8 혼재 — 실결정만 인정" || nope "T8" "rc=$rc1/$rc2"
rm -rf "$TD"

# T9: --list — 확정 주제만 출력 (예시·미확정 제외)
TD=$(mktemp -d)
_ledger "$TD" <<'EOF'
| D-001 | (예시) UI 유무 | 있음 | init Phase11.5 | YYYY-MM-DD |
| D-002 | 프론트엔드 스택 | React 19 | clarify x | 2026-08-06 |
| D-003 | 배포 | TBD | init | 2026-08-06 |
EOF
out=$(cd "$TD" && bash "$CHK" --list 2>/dev/null)
[ "$(printf '%s\n' "$out" | grep -c .)" -eq 1 ] && printf '%s' "$out" | grep -q '프론트엔드 스택' \
  && ok "T9 --list 확정 주제만" || nope "T9" "out=$out"
rm -rf "$TD"

# T10: clarifying-ko 가 판정기를 SoT 로 지목 (눈대중 금지)
grep -q 'check-decisions-ledger.sh' "$PLUGIN/skills/clarifying-ko/SKILL.md" \
  && ok "T10 clarifying-ko 스크립트 지목" || nope "T10" "스킬 본문 미갱신"

# T11: 템플릿 예시 행이 판정에서 제외됨을 템플릿 자신도 명시
grep -qE '예시 행은.*삭제' "$PLUGIN/templates/decisions.md" \
  && ok "T11 템플릿 예시 행 삭제 지침 존재" || nope "T11" "템플릿 지침 부재"

finish
