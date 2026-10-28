#!/usr/bin/env bash
# 공통부 FR foundation-scope SKIP + hybrid 금지 — 20260812
#
# 결함: [공통] FR 이 /start-all PENDING 에 들어가면 §유형=신규+§batch 로 구현되어
#   foundation 경로(manifest·Step 5.6)와 어긋난다. hybrid(§유형=foundation+§batch)는
#   Argus FR-28 실측 — 생산 배타 계약을 모델이 깨면 halt/verify/reuse 가 충돌한다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-fr-table.sh"
LBL="$PLUGIN/scripts/_internal/check-spec-label-compat.sh"

_req() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

# T1: Argus형 — [공통] FR-4 + 기능 FR-5 → foundation-scope / ELIGIBLE
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
<!-- seed-fr: FR-1,FR-2,FR-3 -->
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | M1 시드 전체 | M1 | must | (TBD) |
| FR-4 | **[공통]** 프로젝트 스캐폴딩 — Poetry·app 트리 | M1 | must | (TBD) |
| FR-5 | 종목 마스터 동기화 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" --classify 2>&1); rc=$?
printf '%s' "$out" | grep -qE '^SKIP\|FR-4\|foundation-scope\|M1$' \
  && printf '%s' "$out" | grep -qE '^ELIGIBLE\|FR-5\|' \
  && printf '%s' "$out" | grep -qE 'foundation_skip=1' \
  && [ "$rc" -eq 0 ] \
  && ok "T1 [공통] → foundation-scope, FR-5 ELIGIBLE" \
  || nope "T1" "rc=$rc out=$out"
rm -rf "$TD"

# T2: HTML foundation-fr 목록만
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
<!-- foundation-fr: FR-27, FR-28 -->
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-27 | 백엔드 공통 코어 | M1 | must | (TBD) |
| FR-28 | 프론트 공통 기반 | M1 | must | (TBD) |
| FR-10 | 기술적 지표 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" --classify 2>&1); rc=$?
printf '%s' "$out" | grep -qE '^SKIP\|FR-27\|foundation-scope\|' \
  && printf '%s' "$out" | grep -qE '^SKIP\|FR-28\|foundation-scope\|' \
  && printf '%s' "$out" | grep -qE '^ELIGIBLE\|FR-10\|' \
  && printf '%s' "$out" | grep -qE 'foundation_skip=2' \
  && [ "$rc" -eq 0 ] \
  && ok "T2 HTML foundation-fr → SKIP" \
  || nope "T2" "rc=$rc out=$out"
rm -rf "$TD"

# T3: 미표기 — 설명 중간에만 '공통' → ELIGIBLE (오탐 방지)
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-9 | 배치 스케줄러 — 공통 로그 포맷 사용 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" --classify 2>&1); rc=$?
printf '%s' "$out" | grep -qE '^ELIGIBLE\|FR-9\|' \
  && ! printf '%s' "$out" | grep -q 'foundation-scope' \
  && [ "$rc" -eq 0 ] \
  && ok "T3 중간 '공통' 산문 → ELIGIBLE" \
  || nope "T3" "rc=$rc out=$out"
rm -rf "$TD"

# T4: start-all 배선
grep -q 'foundation-scope' "$PLUGIN/commands/start-all.md" \
  && grep -q 'check-spec-label-compat\|hybrid' "$PLUGIN/commands/start-all.md" \
  && ok "T4 start-all foundation-scope·hybrid 배선" \
  || nope "T4" "start-all 누락"

# T5: start-all-auto 승계
grep -q 'foundation-scope' "$PLUGIN/commands/start-all-auto.md" \
  && ok "T5 start-all-auto 승계" \
  || nope "T5" "auto 누락"

# T6 mutation: foundation-scope 분기 제거하면 T1이 ELIGIBLE 로 붕괴
TD=$(mktemp -d)
mut=$(mktemp)
sed '/_is_foundation_scope/,/^}/d; /if _is_foundation_scope/,/continue$/d' "$CHK" > "$mut" 2>/dev/null \
  || sed '/foundation-scope/d' "$CHK" > "$mut"
# 더 안전한 mutation: _is_foundation_scope 본문을 항상 return 1
awk '
  /^_is_foundation_scope\(\)/ { print; print "  return 1"; skip=1; next }
  skip && /^}/ { skip=0; print; next }
  skip { next }
  { print }
' "$CHK" > "$mut"
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-4 | [공통] 스캐폴딩 | M1 | must | (TBD) |
| FR-5 | 기능 A | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$mut" --classify 2>&1); rc=$?
if printf '%s' "$out" | grep -q 'foundation-scope'; then
  nope "T6 mutation" "분기 무력화했는데도 foundation-scope — mutation 무효 out=$out"
else
  printf '%s' "$out" | grep -qE '^ELIGIBLE\|FR-4\|' \
    && ok "T6 mutation: 무력화 → FR-4 ELIGIBLE (비-vacuous)" \
    || nope "T6 mutation" "rc=$rc out=$out"
fi
rm -rf "$TD" "$mut"

# T7: eligible=0 중단 지시 (공통만)
grep -qE 'eligible=0' "$PLUGIN/commands/start-all.md" \
  && grep -qE '공통|/start-foundation' "$PLUGIN/commands/start-all.md" \
  && ok "T7 eligible=0·공통 중단 안내" \
  || nope "T7" "eligible=0 안내 부족"

# H1: hybrid FAIL
TD=$(mktemp -d)
mkdir -p "$TD/.specops/x"
printf '%s\n' '**§유형**: foundation' '**§batch**: batch-1' > "$TD/.specops/x/spec.md"
out=$(cd "$TD" && bash "$LBL" x 2>&1); rc=$?
printf '%s' "$out" | grep -q 'SPEC-LABEL: FAIL' \
  && [ "$rc" -eq 1 ] \
  && ok "H1 hybrid → FAIL" \
  || nope "H1" "rc=$rc out=$out"
rm -rf "$TD"

# H2: foundation alone / batch+신규 PASS
TD=$(mktemp -d)
mkdir -p "$TD/.specops/a" "$TD/.specops/b"
printf '%s\n' '**§유형**: foundation' > "$TD/.specops/a/spec.md"
printf '%s\n' '**§유형**: 신규' '**§batch**: batch-1' > "$TD/.specops/b/spec.md"
outa=$(cd "$TD" && bash "$LBL" a 2>&1); rca=$?
outb=$(cd "$TD" && bash "$LBL" b 2>&1); rcb=$?
[ "$rca" -eq 0 ] && [ "$rcb" -eq 0 ] \
  && printf '%s' "$outa" | grep -q 'PASS' \
  && printf '%s' "$outb" | grep -q 'PASS' \
  && ok "H2 foundation alone / batch+신규 PASS" \
  || nope "H2" "rca=$rca rcb=$rcb outa=$outa outb=$outb"
rm -rf "$TD"

# H3: specifying-ko 금지 문구
grep -q 'hybrid' "$PLUGIN/skills/specifying-ko/SKILL.md" \
  && grep -q 'check-spec-label-compat' "$PLUGIN/skills/specifying-ko/SKILL.md" \
  && ok "H3 specifying-ko hybrid 금지" \
  || nope "H3" "skill 누락"

# H4: emit-context · run-verification 배선
grep -q 'check-spec-label-compat' "$PLUGIN/scripts/dag/emit-context.sh" \
  && grep -q 'check-spec-label-compat' "$PLUGIN/scripts/_internal/run-verification.sh" \
  && ok "H4 emit/verify 배선" \
  || nope "H4" "배선 누락"

# H5 mutation: hybrid 검사 무력화(항상 PASS) 시 H1이 통과해 버림
mut=$(mktemp)
cat > "$mut" <<'EOF'
#!/usr/bin/env bash
echo "SPEC-LABEL: PASS"
exit 0
EOF
TD=$(mktemp -d)
mkdir -p "$TD/.specops/x"
printf '%s\n' '**§유형**: foundation' '**§batch**: batch-1' > "$TD/.specops/x/spec.md"
out=$(cd "$TD" && bash "$mut" x 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q PASS; then
  # 원본은 FAIL 이어야 함 — mutation 이 PASS 로 바뀌었으니 비-vacuous
  out_real=$(cd "$TD" && bash "$LBL" x 2>&1); rc_real=$?
  [ "$rc_real" -eq 1 ] \
    && ok "H5 mutation: stub PASS vs real FAIL (비-vacuous)" \
    || nope "H5" "원본이 FAIL 아님 rc_real=$rc_real"
else
  nope "H5" "stub 실패"
fi
rm -rf "$TD" "$mut"

# T8: FR-4 vs FR-40 id 경계 (HTML)
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
<!-- foundation-fr: FR-4 -->
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-4 | 스캐폴딩 | M1 | must | (TBD) |
| FR-40 | 다른 기능 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" --classify 2>&1)
printf '%s' "$out" | grep -qE '^SKIP\|FR-4\|foundation-scope\|' \
  && printf '%s' "$out" | grep -qE '^ELIGIBLE\|FR-40\|' \
  && ok "T8 FR-4 목록이 FR-40 을 오탐하지 않음" \
  || nope "T8" "out=$out"
rm -rf "$TD"

# ── T9: 공통부 FR 완료 기록 (20261009 /start-foundation 점검 묶음 C) ─────────────
# 결함: 공통부 FR 은 queue 에서 SKIP 이라 FID 칸이 없고, 요구사항 표의 `관련 spec` 칸도 아무도 채우지 않았다
#   (실기록: foundation 완료 한 달 뒤에도 공통 FR 8건 전부 `(TBD)`). fr-set-fid.sh 가 그 칸을 채운다.
SET="$PLUGIN/scripts/_internal/fr-set-fid.sh"
_req9() {
  _req "$1/.specops/memory/requirements.md" <<'EOF'
# 요구사항

> 설명 문단 | 표가 아닌 줄

<!-- foundation-fr: FR-20 -->

| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | M1 시드 | M1 | must | (마일스톤 시드 — 세부 FR 로 분해) |
| FR-4 | **[공통]** 스캐폴딩 — `pnpm` 워크스페이스 | M1 | must | (TBD) |
| **FR-5** | [공통] 인증 | M1 | must | 20260801-earlier |
| FR-6 | 주문 목록 | M1 | must | (TBD) |
| FR-20 | DB 베이스 스키마 | M1 | must | — |
| FR-40 | 다른 기능 | M2 | should | (TBD)   |

## NFR

| ID | 요구사항 | 기준 |
|---|---|---|
| FR-99 | 칸이 모자란 행 | x |
EOF
}
TD=$(mktemp -d); _req9 "$TD"; R="$TD/.specops/memory/requirements.md"; cp "$R" "$TD/before.md"
out=$(cd "$TD" && bash "$SET" 20260806-fnd FR-4 FR-20 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -qxF '| FR-4 | **[공통]** 스캐폴딩 — `pnpm` 워크스페이스 | M1 | must | 20260806-fnd |' "$R" \
  && grep -qxF '| FR-20 | DB 베이스 스키마 | M1 | must | 20260806-fnd |' "$R" \
  && ok "T9.a 빈 칸((TBD)·—)에 FID 를 적는다" || nope "T9.a" "rc=$rc out=$out $(grep -E 'FR-4 |FR-20' "$R")"
# 지정하지 않은 행·표 밖의 줄은 한 글자도 바뀌지 않는다
[ "$(diff "$TD/before.md" "$R" | grep -c '^[<>]')" -eq 4 ] && grep -qxF '| FR-40 | 다른 기능 | M2 | should | (TBD)   |' "$R" \
  && grep -qxF '> 설명 문단 | 표가 아닌 줄' "$R" \
  && ok "T9.b 지정한 두 행만 바뀐다(FR-4 가 FR-40 을 건드리지 않는다)" || nope "T9.b" "$(diff "$TD/before.md" "$R")"
# 이미 다른 FID 가 있으면 덧붙인다 · 굵은 ID 도 읽는다
out=$(cd "$TD" && bash "$SET" 20260806-fnd FR-5 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -qxF '| **FR-5** | [공통] 인증 | M1 | must | 20260801-earlier · 20260806-fnd |' "$R" \
  && ok "T9.c 다른 FID 가 있으면 뒤에 덧붙인다(굵은 ID 행)" || nope "T9.c" "rc=$rc out=$out $(grep 'FR-5' "$R")"
# 다시 돌려도 중복되지 않는다
cp "$R" "$TD/once.md"; (cd "$TD" && bash "$SET" 20260806-fnd FR-4 FR-5 FR-20 >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && cmp -s "$TD/once.md" "$R" && ok "T9.d 재실행해도 그대로(중복 없음)" || nope "T9.d" "rc=$rc $(diff "$TD/once.md" "$R")"
# 없는 FR · 칸이 모자란 행 → rc 1, 파일 불변
cp "$R" "$TD/pre.md"; out=$(cd "$TD" && bash "$SET" 20260806-fnd FR-77 FR-99 2>&1); rc=$?
[ "$rc" -eq 1 ] && cmp -s "$TD/pre.md" "$R" && printf '%s' "$out" | grep -q 'FR-77' && printf '%s' "$out" | grep -q '칸이' \
  && ok "T9.e 없는 FR·칸 모자란 행 → rc 1 · 파일 불변 · 사유" || nope "T9.e" "rc=$rc out=$out"
# FID 꼴이 아니면 쓰지 않는다
out=$(cd "$TD" && bash "$SET" 'x | y' FR-6 2>&1); rc=$?
[ "$rc" -eq 2 ] && cmp -s "$TD/pre.md" "$R" && ok "T9.f FID 꼴이 아니면 rc 2 · 파일 불변" || nope "T9.f" "rc=$rc out=$out"
rm -rf "$TD"

# T9.g --pending-foundation: 공통부 FR([공통]·foundation-fr) 중 칸이 빈 것만
TD=$(mktemp -d); _req9 "$TD"
out=$(cd "$TD" && bash "$SET" --pending-foundation 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | tr '\n' ' ')" = "FR-4 FR-20 " ] \
  && ok "T9.g 빈 공통 FR 만 나열(FR-4·FR-20 — 적힌 FR-5·기능 FR-6 제외)" || nope "T9.g" "rc=$rc out=$out"
rm -rf "$TD"

# T9.h CRLF 표에서도 그 행만 바꾸고 줄 끝을 보존한다
TD=$(mktemp -d); mkdir -p "$TD/.specops/memory"; R="$TD/.specops/memory/requirements.md"
printf '| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |\r\n|---|---|---|---|---|\r\n| FR-4 | [공통] 스캐폴딩 | M1 | must | (TBD) |\r\n| FR-6 | 주문 | M1 | must | (TBD) |\r\n' > "$R"
(cd "$TD" && bash "$SET" 20260806-fnd FR-4 >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(grep -c $'\r$' "$R")" -eq 4 ] && grep -q '| FR-4 | \[공통\] 스캐폴딩 | M1 | must | 20260806-fnd |' "$R" \
  && ok "T9.h CRLF 보존" || nope "T9.h" "rc=$rc $(od -c "$R" | tail -4)"
rm -rf "$TD"

# T9.j 앞머리가 같은 ID(FR-40 이 FR-4 보다 먼저 오는 표)에서도 정확한 행만 고친다
TD=$(mktemp -d); mkdir -p "$TD/.specops/memory"; R="$TD/.specops/memory/requirements.md"
printf '| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |\n|---|---|---|---|---|\n| FR-40 | 다른 기능 | M2 | should | (TBD) |\n| FR-4 | [공통] 스캐폴딩 | M1 | must | (TBD) |\n' > "$R"
(cd "$TD" && bash "$SET" 20260806-fnd FR-4 >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -qxF '| FR-40 | 다른 기능 | M2 | should | (TBD) |' "$R" && grep -qxF '| FR-4 | [공통] 스캐폴딩 | M1 | must | 20260806-fnd |' "$R" \
  && ok "T9.j FR-4 지정이 앞선 FR-40 행을 건드리지 않는다" || nope "T9.j" "rc=$rc $(cat "$R")"
rm -rf "$TD"

# ── T9.k~: 독립 리뷰 반영 — 사용자 문서를 고치는 스크립트라 좁게 잠근다 ─────────────
_hdr5='| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |\n|---|---|---|---|---|\n'
# T9.k 쓰기에 실패하면 성공이라 하지 않는다
TD=$(mktemp -d); mkdir -p "$TD/.specops/memory"; R="$TD/.specops/memory/requirements.md"
printf "${_hdr5}| FR-4 | [공통] a | M1 | must | (TBD) |\n" > "$R"; cp "$R" "$TD/pre.md"; chmod 444 "$R"
out=$(cd "$TD" && bash "$SET" 20260806-fnd FR-4 2>&1); rc=$?
if [ -w "$R" ]; then skip "T9.k 읽기 전용 → rc 1 — 이 환경은 읽기 전용 파일에도 쓸 수 있다(root 등)"
else [ "$rc" -eq 1 ] && cmp -s "$TD/pre.md" "$R" && ! printf '%s' "$out" | grep -q '←' \
  && ok "T9.k 읽기 전용 → rc 1 · 성공 메시지 없음 · 파일 불변" || nope "T9.k" "rc=$rc out=$out"; fi
chmod 644 "$R"; rm -rf "$TD"
# T9.l 파일 끝에 개행이 없으면 없는 채로 둔다 — 지정한 행 밖은 한 바이트도 안 바뀐다
TD=$(mktemp -d); mkdir -p "$TD/.specops/memory"; R="$TD/.specops/memory/requirements.md"
printf "${_hdr5}| FR-4 | [공통] a | M1 | must | (TBD) |\n| FR-6 | 주문 | M1 | must | (TBD) |" > "$R"
printf "${_hdr5}| FR-4 | [공통] a | M1 | must | 20260806-fnd |\n| FR-6 | 주문 | M1 | must | (TBD) |" > "$TD/want.md"
(cd "$TD" && bash "$SET" 20260806-fnd FR-4 >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && cmp -s "$TD/want.md" "$R" && ok "T9.l 끝 개행 없는 파일 → 바이트 단위로 그 행만" || nope "T9.l" "rc=$rc $(cmp "$TD/want.md" "$R" 2>&1)"
rm -rf "$TD"
# T9.m 코드펜스 안의 예시 행은 표가 아니다 — 실제 행을 고친다
TD=$(mktemp -d); mkdir -p "$TD/.specops/memory"; R="$TD/.specops/memory/requirements.md"
printf '예시:\n\n```markdown\n| FR-4 | [공통] 예시 행 | M1 | must | (TBD) |\n```\n\n'"${_hdr5}"'| FR-4 | [공통] 실제 행 | M1 | must | (TBD) |\n' > "$R"
(cd "$TD" && bash "$SET" 20260806-fnd FR-4 >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -qxF '| FR-4 | [공통] 예시 행 | M1 | must | (TBD) |' "$R" && grep -qxF '| FR-4 | [공통] 실제 행 | M1 | must | 20260806-fnd |' "$R" \
  && ok "T9.m 펜스 안 예시 행은 그대로 · 실제 행만 고친다" || nope "T9.m" "rc=$rc $(cat "$R")"
rm -rf "$TD"
# T9.n 칸 안의 `|` 는 구분자가 아니다 — 이스케이프·백틱 안
TD=$(mktemp -d); mkdir -p "$TD/.specops/memory"; R="$TD/.specops/memory/requirements.md"
printf '%s\n' '| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |' '|---|---|---|---|---|' \
  '| FR-4 | [공통] `a|b` 를 받고 x \| y 를 낸다 | M1 | must | (TBD) |' \
  '| FR-5 | [공통] 인증 | M1 | must | `spec|v1` |' \
  '| FR-7 | 칸이 넷 x \| y | M1 | must |' > "$R"
(cd "$TD" && bash "$SET" 20260806-fnd FR-4 FR-5 >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -qxF '| FR-4 | [공통] `a|b` 를 받고 x \| y 를 낸다 | M1 | must | 20260806-fnd |' "$R" \
  && grep -qxF '| FR-5 | [공통] 인증 | M1 | must | `spec|v1` · 20260806-fnd |' "$R" \
  && ok "T9.n 칸 안의 | 가 있어도 마지막 칸만 정확히 고친다" || nope "T9.n" "rc=$rc $(cat "$R")"
cp "$R" "$TD/pre.md"; out=$(cd "$TD" && bash "$SET" 20260806-fnd FR-7 2>&1); rc=$?
[ "$rc" -eq 1 ] && cmp -s "$TD/pre.md" "$R" && ok "T9.o 이스케이프한 | 를 칸으로 세지 않는다(칸 넷 → 거부 · 불변)" || nope "T9.o" "rc=$rc out=$out $(diff "$TD/pre.md" "$R")"
rm -rf "$TD"

# T9.i 문서 배선 — /start-foundation 이 범위 출처(공통 FR)와 완료 기록을 지시한다
SF="$PLUGIN/commands/start-foundation.md"
grep -q 'fr-set-fid.sh' "$SF" && grep -q 'check-fr-table.sh --classify' "$SF" \
  && ok "T9.i start-foundation.md 가 공통 FR 범위·완료 기록을 지시" || nope "T9.i" "명령 문서 미배선"

finish
