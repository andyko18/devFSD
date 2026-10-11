#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

# T1.a: gbrain-append.sh 존재
run "T1.a gbrain-append.sh 존재" \
  test -f "$PLUGIN/scripts/gbrain-append.sh"

# T1.b: usage 출력 (인자 없음 → exit 1)
T1_b() {
  bash "$PLUGIN/scripts/gbrain-append.sh" 2>&1 | grep -qi "usage\|insight" && \
  ! bash "$PLUGIN/scripts/gbrain-append.sh" >/dev/null 2>&1
}
run "T1.b usage 출력 exit 1" T1_b

# T2.a: JSONL 레코드 추가 (ts·fid·insight·tags 포함)
T2_a() {
  local tmp
  tmp=$(mktemp)
  GBRAIN_FILE="$tmp" bash "$PLUGIN/scripts/gbrain-append.sh" "테스트 인사이트" 2>/dev/null
  local result
  result=$(cat "$tmp")
  rm -f "$tmp"
  echo "$result" | grep -q '"insight"' && \
  echo "$result" | grep -q '"ts"' && \
  echo "$result" | grep -q '"tags"'
}
run "T2.a JSONL 레코드 추가" T2_a

# T2.b: insight 값 round-trip
run "T2.b JSONL insight 값 round-trip" bash -c '
  tmp=$(mktemp)
  GBRAIN_FILE="$tmp" bash "'"$PLUGIN"'"/scripts/gbrain-append.sh "라운드트립인사이트"
  if grep -q "\"insight\":\"라운드트립인사이트\"" "$tmp"; then rc=0; else rc=1; fi
  rm -f "$tmp"
  exit $rc
'

# T2.c: 큰따옴표 포함 insight JSONL 유효 (C-1 검증)
run "T2.c insight 큰따옴표 포함 JSONL 유효" bash -c '
  tmp=$(mktemp)
  GBRAIN_FILE="$tmp" bash "'"$PLUGIN"'"/scripts/gbrain-append.sh '"'"'he said \"hello\"'"'"'
  line=$(tail -1 "$tmp")
  if echo "$line" | grep -q '"'"'"insight"'"'"'; then rc=0; else rc=1; fi
  rm -f "$tmp"
  exit $rc
'

# T2.d: 큰따옴표 포함 insight python3 json 파싱 round-trip
T2_d() {
  command -v python3 >/dev/null 2>&1 || return 0  # python3 없으면 SKIP (pass)
  local tmp line ts insight result
  tmp=$(mktemp)
  GBRAIN_FILE="$tmp" bash "$PLUGIN/scripts/gbrain-append.sh" 'he said "hello world"' 2>/dev/null
  line=$(tail -1 "$tmp")
  # python3로 파싱
  result=$(python3 - "$line" <<'PYEOF'
import sys, json
obj = json.loads(sys.argv[1])
print(obj.get("insight", ""))
PYEOF
)
  rm -f "$tmp"
  [ "$result" = 'he said "hello world"' ]
}
run "T2.d 큰따옴표 포함 insight python3 round-trip" T2_d

# T2.f: 제어문자(개행·탭) 포함 insight JSONL 유효 (H1 escape fix — control chars U+0000~U+001F)
T2_f() {
  command -v jq >/dev/null 2>&1 || return 0  # jq 없으면 SKIP (pass)
  local tmp line
  tmp=$(mktemp) || return 1
  GBRAIN_FILE="$tmp" bash "$PLUGIN/scripts/gbrain-append.sh" "$(printf 'multi\nline\ttab')" 2>/dev/null
  line=$(cat "$tmp")
  rm -f "$tmp"
  # fix 전: literal 개행/탭 → 무효 JSON(여러 줄) → jq 실패. fix 후: \n·\t 이스케이프된 단일 유효 JSON.
  printf '%s\n' "$line" | jq -e . >/dev/null 2>&1
}
run "T2.f 제어문자 포함 insight JSONL 유효" T2_f

# T2.g: 제어문자 포함 insight round-trip 보존 (python3)
T2_g() {
  command -v python3 >/dev/null 2>&1 || return 0  # python3 없으면 SKIP (pass)
  local tmp line result expected
  expected=$(printf 'multi\nline\ttab')
  tmp=$(mktemp) || return 1
  GBRAIN_FILE="$tmp" bash "$PLUGIN/scripts/gbrain-append.sh" "$expected" 2>/dev/null
  line=$(cat "$tmp")
  rm -f "$tmp"
  result=$(printf '%s' "$line" | python3 -c 'import sys,json; print(json.load(sys.stdin)["insight"])')
  [ "$result" = "$expected" ]
}
run "T2.g 제어문자 포함 insight round-trip" T2_g

# T2.e: SKILL.md parse_line 코드 블록에 python3 분기 존재
run "T2.e SKILL.md python3 파싱 분기 존재" \
  grep -q 'python3' "$PLUGIN/skills/gbrain-ko/SKILL.md"

# T3.a: 파일 미존재 시 자동 생성
T3_a() {
  local tmpdir tmp
  tmpdir=$(mktemp -d)
  tmp="$tmpdir/learnings.jsonl"
  GBRAIN_FILE="$tmp" bash "$PLUGIN/scripts/gbrain-append.sh" "첫 인사이트" 2>/dev/null
  local ret=0
  test -f "$tmp" || ret=1
  rm -rf "$tmpdir"
  return $ret
}
run "T3.a 파일 미존재 시 자동 생성" T3_a

# T4.a: SKILL.md 존재 + frontmatter 6 필드
T4_a() {
  local count
  count=$(grep -c "^name:\|^description:\|^layer:\|^reference_upstream:\|^specops_version:\|^used_by:" \
    "$PLUGIN/skills/gbrain-ko/SKILL.md" 2>/dev/null || echo 0)
  [ "$count" -ge 6 ]
}
run "T4.a SKILL.md frontmatter 6 필드" T4_a

# T5.a: SKILL.md 조회 프로세스 언급
run "T5.a SKILL.md 조회 프로세스 언급" \
  grep -q "learnings.jsonl\|tail\|최신" "$PLUGIN/skills/gbrain-ko/SKILL.md" 2>/dev/null

# T6.a: commands/gbrain.md 존재
run "T6.a commands/gbrain.md 존재" \
  test -f "$PLUGIN/commands/gbrain.md"

# T6.b: gbrain-ko 언급
run "T6.b commands/gbrain.md gbrain-ko 언급" \
  grep -q "gbrain-ko" "$PLUGIN/commands/gbrain.md" 2>/dev/null

# T7.a: --fid 레코드 기록 (should)
T7_a() {
  local tmp
  tmp=$(mktemp)
  # (20260806) FID 형식 검증 도입 — 픽스처를 규약 형식(YYYYMMDD-kebab)으로 갱신.
  GBRAIN_FILE="$tmp" bash "$PLUGIN/scripts/gbrain-append.sh" "인사이트A" --fid "20260806-fid-a" 2>/dev/null
  GBRAIN_FILE="$tmp" bash "$PLUGIN/scripts/gbrain-append.sh" "인사이트B" --fid "20260806-fid-b" 2>/dev/null
  local ret=0
  grep -q '"20260806-fid-a"' "$tmp" && grep -q '"20260806-fid-b"' "$tmp" || ret=1
  rm -f "$tmp"
  return $ret
}
run "T7.a --fid 레코드 기록" T7_a

# === --confidence (AC-1/4/R-1) ===
T_conf_high() {
  local gf gd; gd=$(mktemp -d) || return 1; gf="$gd/learnings.jsonl"
  GBRAIN_FILE="$gf" bash "$PLUGIN/scripts/gbrain-append.sh" "테스트" --confidence high >/dev/null 2>&1
  local ok=1; [ "$(tail -1 "$gf" | jq -r '.confidence // "none"')" = "high" ] || ok=0
  rm -rf "$(dirname "$gf")"; [ "$ok" = 1 ]
}
run "AC-1 --confidence high 필드" T_conf_high
T_conf_none() {
  local gf gd; gd=$(mktemp -d) || return 1; gf="$gd/learnings.jsonl"
  GBRAIN_FILE="$gf" bash "$PLUGIN/scripts/gbrain-append.sh" "노confidence" >/dev/null 2>&1
  local ok=1; [ "$(tail -1 "$gf" | jq 'has("confidence")')" = "false" ] || ok=0
  rm -rf "$(dirname "$gf")"; [ "$ok" = 1 ]
}
run "AC-R-1 미지정 필드 없음" T_conf_none
T_conf_bogus() {
  local gf gd; gd=$(mktemp -d) || return 1; gf="$gd/learnings.jsonl"
  ! GBRAIN_FILE="$gf" bash "$PLUGIN/scripts/gbrain-append.sh" "x" --confidence bogus >/dev/null 2>&1
  local r=$?; rm -rf "$(dirname "$gf")"; return $r
}
run "AC-4 bogus 거부(exit 1)" T_conf_bogus
# low/medium 값도 대칭 동작 (high 외 enum 값 회귀 가드)
T_conf_lowmed() {
  local gf gd; gd=$(mktemp -d) || return 1; gf="$gd/learnings.jsonl"
  local ok=1
  GBRAIN_FILE="$gf" bash "$PLUGIN/scripts/gbrain-append.sh" "낮음" --confidence low >/dev/null 2>&1
  [ "$(tail -1 "$gf" | jq -r '.confidence // "none"')" = "low" ] || ok=0
  GBRAIN_FILE="$gf" bash "$PLUGIN/scripts/gbrain-append.sh" "중간" --confidence medium >/dev/null 2>&1
  [ "$(tail -1 "$gf" | jq -r '.confidence // "none"')" = "medium" ] || ok=0
  rm -rf "$gd"; [ "$ok" = 1 ]
}
run "AC-1 --confidence low/medium 필드" T_conf_lowmed
# --confidence 뒤 값 누락 → usage 오류 + exit 1 (case ${2:-} 빈값 미매칭)
T_conf_missing() {
  local gf gd; gd=$(mktemp -d) || return 1; gf="$gd/learnings.jsonl"
  ! GBRAIN_FILE="$gf" bash "$PLUGIN/scripts/gbrain-append.sh" "x" --confidence >/dev/null 2>&1
  local r=$?; rm -rf "$gd"; return $r
}
run "AC-4 --confidence 값 누락 거부(exit 1)" T_conf_missing

# ── T5: --fid 형식 검증 (20260806 유틸 스캔) ─────────────────────────────────
# 결함: repo 전 스크립트가 FID 를 `^[0-9]{8}-[a-z0-9-]+$` 로 검증하는데
#   (session-progress-append·show-fid-status·record-metric·record-task-receipt·
#    promote-validate) gbrain-append·gbrain-recall 만 무검증이었다.
#   실측: 실 learnings.jsonl 에 형식 위배 **5건**(`audit-20260710` 등) 적재됨 →
#   `/gbrain --fid <FID>` 필터·FID별 환류 조회가 조용히 어긋난다.
T5_a() {  # 형식 위배 FID 거부
  local tmp; tmp=$(mktemp)
  ! GBRAIN_FILE="$tmp" bash "$PLUGIN/scripts/gbrain-append.sh" "x" --fid "audit-20260710" >/dev/null 2>&1
}
run "T5.a 형식 위배 --fid 거부 (exit≠0)" T5_a

T5_b() {  # 경로 문자 주입 거부
  local tmp; tmp=$(mktemp)
  ! GBRAIN_FILE="$tmp" bash "$PLUGIN/scripts/gbrain-append.sh" "x" --fid "../../etc/passwd" >/dev/null 2>&1
}
run "T5.b 경로 문자 --fid 거부" T5_b

T5_c() {  # 정상 FID 통과 + 기록
  local tmp; tmp=$(mktemp)
  GBRAIN_FILE="$tmp" bash "$PLUGIN/scripts/gbrain-append.sh" "정상" --fid "20260806-valid-fid" >/dev/null 2>&1 \
    && jq -e '.fid == "20260806-valid-fid"' "$tmp" >/dev/null 2>&1
}
run "T5.c 정상 FID 통과" T5_c

T5_d() {  # --fid 미지정(빈값)은 정상 — 자유작업 인사이트
  local tmp; tmp=$(mktemp)
  GBRAIN_FILE="$tmp" bash "$PLUGIN/scripts/gbrain-append.sh" "자유" >/dev/null 2>&1 \
    && jq -e '.fid == ""' "$tmp" >/dev/null 2>&1
}
run "T5.d --fid 생략 → 빈값 허용" T5_d

# ── redact 관문 적용 (FID 20261001-redact-capture · AC-5 · AC-6) ──
# 가짜 키는 실행 중 조각 조립 — 저장소에 실제 형태 리터럴을 두지 않는다
T9_a() {
  local tmp k; tmp=$(mktemp); k="AK""IA$(printf 'A%.0s' $(seq 16))"
  GBRAIN_FILE="$tmp" bash "$PLUGIN/scripts/gbrain-append.sh" "키 $k 를 붙여넣음" --fid 20261001-redact-capture >/dev/null 2>&1 \
    && ! grep -q "$k" "$tmp" && grep -q 'REDACTED:aws' "$tmp" \
    && [ "$(jq -c 'keys' "$tmp")" = '["fid","insight","tags","ts"]' ]
}
run "T9.a insight 의 가짜 키 마스킹·필드 불변" T9_a
T9_b() {
  local tmp ins; tmp=$(mktemp); ins=$(printf '가%.0s' $(seq 3000))
  GBRAIN_FILE="$tmp" bash "$PLUGIN/scripts/gbrain-append.sh" "$ins" >/dev/null 2>&1 \
    && [ "$(jq -r '.insight' "$tmp")" = "$ins" ]
}
run "T9.b 3000자 정상 insight 는 절단 없이 보존" T9_b
T9_c() {
  local d rc=0 before=0 after=0; d=$(mktemp -d)
  mkdir -p "$d/p/scripts/_internal" "$d/w/.specops/memory"
  cp "$PLUGIN/scripts/gbrain-append.sh" "$d/p/scripts/"
  cp "$PLUGIN/scripts/_internal/redact.sh" "$d/p/scripts/_internal/" 2>/dev/null   # 패턴 파일은 일부러 복사하지 않는다
  [ -e "$PLUGIN/.specops/redact-failures.log" ] && before=1
  (cd "$d/w" && GBRAIN_FILE="$d/w/.specops/memory/learnings.jsonl" bash "$d/p/scripts/gbrain-append.sh" "비밀 insight 텍스트" 2>"$d/err") || rc=$?
  [ -e "$PLUGIN/.specops/redact-failures.log" ] && after=1
  [ "$rc" -eq 1 ] && [ ! -s "$d/w/.specops/memory/learnings.jsonl" ] && grep -q '마스킹 불가' "$d/err" \
    && [ "$(wc -l < "$d/w/.specops/redact-failures.log" | tr -d ' ')" = "1" ] \
    && ! grep -q '비밀 insight' "$d/w/.specops/redact-failures.log" && [ "$before" = "$after" ]
  local r=$?; rm -rf "$d"; return $r
}
run "T9.c 마스킹 불가 → 미기록·exit 1·로그 1줄·실트리 무쓰기" T9_c

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
