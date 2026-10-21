#!/usr/bin/env bash
# security-scan.sh 검증 (self-check 레이어 — FID 20260620-security-selfcheck)
#   + 외부 스캐너 상한·강등 (FID 20260828-sast-timeout)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
P=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$P/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SC="$P/scripts/security-scan.sh"
[ -f "$SC" ] && [ -x "$SC" ] || nope "존재" "security-scan.sh 부재/비실행"

# self-check 레이어 검증에서는 외부 스캐너를 **기본** 차단한다 (20260828-sast-timeout).
#   왜: 종전엔 5개 케이스가 각각 실제 semgrep 을 종전 배선(레지스트리 자동 룰셋)으로 불렀고,
#   그건 **네트워크 호출**이라 run-all 이 여기서 무한 정지했다(실측 8분+ 무출력).
#   아래 self-check 레이어 케이스에는 외부 스캐너가 관심사가 아니므로 기본값을 0 으로 둔다.
# 원인 정정 (PR #58): 그 대기의 실체는 룰 수신이 아니라 semgrep.dev version-check 였다
#   (`--version` 만으로도 98.5s · `SEMGREP_ENABLE_VERSION_CHECK=0` 이면 1.8s — PR #58 실측).
# ★ 한계 고백 철회 (f313f8d): "실 semgrep 이 specops 자체 코드에 오탐을 내지 않는가" 는 더 이상
#   포기된 커버리지가 아니다 — 파일 하단 AC-5-sg·AC-6-sg·AC-3-sg 가 이 기본값을 =1 로 되돌려
#   **실 semgrep** 을 부른다. 로컬 룰셋 + version-check 차단이라 네트워크를 쓰지 않으므로
#   종전의 포기 사유(네트워크 의존)가 소멸했다(2026-09-24 실측: 1파일 스캔 1.9s).
export SPECOPS_SAST_EXTERNAL=0

# AC-R-1: 깨끗한 디렉토리 → self-check 통과 (crit=0 exit 0, 도구 미설치여도 SKIP 아닌 crit=0)
T=$(mktemp -d); printf 'def f():\n    return 1\n' > "$T/clean.py"
out=$(bash "$SC" "$T" 2>&1); ec=$?
{ printf '%s' "$out" | grep -qE 'SECURITY: (crit=0 high=0|SKIP)' && [ "$ec" -eq 0 ]; } \
  && ok "AC-R-1 깨끗 디렉토리 통과 (exit 0)" || nope "AC-R-1" "out=$out ec=$ec"; rm -rf "$T"

# AC-2: secret 탐지 → crit, exit 1. ※ fixture 키는 런타임 조립 — 이 소스에 완전체 미노출(self-check 자기오탐 방지, C-1)
T=$(mktemp -d); printf 'aws=%s\n' "AKIA""IOSFODNN7EXAMPLE" > "$T/leak.py"
out=$(bash "$SC" "$T" 2>&1); ec=$?
{ printf '%s' "$out" | grep -qE 'crit=[1-9]' && [ "$ec" -ne 0 ]; } \
  && ok "AC-2 secret 탐지 차단" || nope "AC-2" "out=$out ec=$ec"; rm -rf "$T"

# AC-3a: 위험함수 비-bash(.py) 탐지 → high
T=$(mktemp -d); printf 'subprocess.run(cmd, shell=True)\n' > "$T/danger.py"
out=$(bash "$SC" "$T" 2>&1)
printf '%s' "$out" | grep -qE 'high=[1-9]' && ok "AC-3a 위험함수 비-bash 탐지" || nope "AC-3a" "out=$out"; rm -rf "$T"

# AC-3b: bash eval 오탐 0 (specops 자체 보호 핵심)
T=$(mktemp -d); printf '#!/usr/bin/env bash\neval "$cmd"\n' > "$T/script.sh"
out=$(bash "$SC" "$T" 2>&1); ec=$?
{ printf '%s' "$out" | grep -qE 'crit=0 high=0|SECURITY: SKIP' && [ "$ec" -eq 0 ]; } \
  && ok "AC-3b bash eval 오탐 0" || nope "AC-3b" "out=$out ec=$ec"; rm -rf "$T"

# AC-R-2: specops 자체 scripts/ 스캔 오탐 0 (tests 제외로 fixture·테스트소스 미스캔)
out=$(bash "$SC" "$P/scripts" 2>&1); ec=$?
{ printf '%s' "$out" | grep -qE 'crit=0 high=0|SECURITY: SKIP' && [ "$ec" -eq 0 ]; } \
  && ok "AC-R-2 specops scripts/ 오탐 0" || nope "AC-R-2" "자기코드 오탐 out=$out ec=$ec"


# ── 외부 스캐너 상한 (FID 20260828-sast-timeout) ──
# 느린 stub 으로 "네트워크에 걸린 semgrep" 을 재현한다. 실 semgrep 을 쓰면 이 테스트 자체가
# 고치려는 병에 걸린다 — 재현은 stub, 상한은 프로덕션 코드가 건다.
STUB=$(mktemp -d)
printf '#!/usr/bin/env bash\nsleep 99\n' > "$STUB/semgrep"; chmod +x "$STUB/semgrep"
printf '#!/usr/bin/env bash\nsleep 99\n' > "$STUB/gitleaks"; chmod +x "$STUB/gitleaks"
T=$(mktemp -d); printf 'def f():\n    return 1\n' > "$T/clean.py"

# AC-4: 느린 외부 스캐너가 스크립트를 정지시키지 못한다
s=$(date +%s)
out=$(PATH="$STUB:$PATH" SPECOPS_SAST_EXTERNAL=1 SPECOPS_SAST_TIMEOUT=2 bash "$SC" "$T" 2>&1); ec=$?
el=$(( $(date +%s) - s ))
[ "$el" -lt 20 ] && ok "AC-4 느린 스캐너 상한 작동 (${el}s < 20s)" \
  || nope "AC-4 상한" "${el}s 소요 — 상한 미작동(stub sleep 99 완주 의심)"

# AC-5: 시간초과가 crit=0 을 '깨끗한 SAST 통과' 로 위장하지 않는다
# 왜 별건인가: 상한만 걸고 표기를 안 하면 정지가 **조용한 오탐 통과**로 바뀐다 — 더 나쁘다.
printf '%s' "$out" | grep -q '시간초과' \
  && ok "AC-5 시간초과 명시 표기 (무음 통과 차단)" \
  || nope "AC-5 강등 표기" "out=$out ec=$ec"

# AC-6: SPECOPS_SAST_EXTERNAL=0 → 외부 스캐너 미실행 (느린 stub 이 PATH 에 있어도 즉시 종료)
s=$(date +%s)
out=$(PATH="$STUB:$PATH" SPECOPS_SAST_EXTERNAL=0 bash "$SC" "$T" 2>&1); ec=$?
el=$(( $(date +%s) - s ))
{ [ "$el" -lt 20 ] && [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -qE 'crit=0 high=0'; } \
  && ok "AC-6 EXTERNAL=0 외부 스캐너 미실행 (${el}s)" \
  || nope "AC-6 EXTERNAL=0" "el=${el}s ec=$ec out=$out"

# AC-8: 외부 스캐너 하드 실패(rc≥2)도 강등 표기 — 무음 통과 차단
# 왜 별건인가: 시간초과만 표기하면, 네트워크 두절·설정 거부로 semgrep 이 **즉시 에러**를 낼 때
#   crit=0 이 그대로 나가 "스캔 안 함" 과 "통과" 가 구분되지 않는다. 실측 계기:
#   `--metrics=off` 를 붙였더니 semgrep 이 "Cannot create auto config…" 로 거부해 스캐너가
#   통째로 no-op 이 됐는데 출력은 `SECURITY: crit=0 high=0` 이었다.
FSTUB=$(mktemp -d)
printf '#!/usr/bin/env bash\necho "boom" >&2\nexit 2\n' > "$FSTUB/semgrep"; chmod +x "$FSTUB/semgrep"
out=$(PATH="$FSTUB:$PATH" SPECOPS_SAST_EXTERNAL=1 bash "$SC" "$T" 2>&1); ec=$?
{ printf '%s' "$out" | grep -q '실행실패' && [ "$ec" -eq 0 ] \
  && ! printf '%s' "$out" | grep -qF '(룰셋:'; } \
  && ok "AC-8 하드 실패 강등 표기 + 룰셋 표기 부재 (실행 receipt)" \
  || nope "AC-8 하드 실패" "out=$out ec=$ec"
rm -rf "$FSTUB"

# AC-7: 외부 미실행 시에도 self-check 판정은 살아 있다 (강등이지 무력화가 아니다)
printf 'aws=%s\n' "AKIA""IOSFODNN7EXAMPLE" > "$T/leak.py"
out=$(PATH="$STUB:$PATH" SPECOPS_SAST_EXTERNAL=0 bash "$SC" "$T" 2>&1); ec=$?
{ printf '%s' "$out" | grep -qE 'crit=[1-9]' && [ "$ec" -ne 0 ]; } \
  && ok "AC-7 외부 미실행에도 self-check secret 차단 유지" || nope "AC-7" "out=$out ec=$ec"
rm -rf "$T" "$STUB"

# ── 실 semgrep 스캔 (FID 20260917-sast-offline-ruleset) ──
#   라벨 접두 AC-*-sg = 이 스위트가 실 semgrep 으로 검증하는 spec AC. 기존 AC-3a/3b 와 충돌 없음.
if command -v semgrep >/dev/null 2>&1; then
  # AC-5-sg 양성 — 취약 픽스처에서 룰 2개가 정확히 2건 검출
  out=$(SPECOPS_SAST_EXTERNAL=1 bash "$SC" "$P/scripts/tests/fixtures/sast/vulnerable.sh" 2>&1); ec=$?
  #   `crit=2 ` 뒤 공백까지 요구한다 — `crit=2` 만이면 `crit=20` 도 만족하는 접두 일치다.
  { printf '%s' "$out" | grep -qE 'crit=2 ' && [ "$ec" = 1 ]; } \
    && ok "AC-5-sg 실 semgrep 취약 픽스처 crit=2 차단" || nope "AC-5-sg 양성" "out=$out ec=$ec"

  # AC-6-sg 음성 — 프로덕션 코드 오탐 0 + semgrep 이 실제로 돌았음
  #   :16-17 주석이 "네트워크 의존이라 신뢰할 수 없어 포기했다" 고 적은 커버리지를 되살린다.
  #   crit=0 high=0 만 보면 semgrep 미실행도 통과하므로 강등 부재를 함께 요구한다.
  #   검사 문자열을 semgrep( 로 좁힌다 — 외부 SAST 미반영 은 gitleaks 강등도 포함하는 공용 표기다.
  #   ⚠️ security-scan.sh 는 `TARGET="${1:-.}"` 로 **인자를 1개만** 받는다. `"$P/hooks" "$P/scripts"`
  #   처럼 두 경로를 넘기면 둘째가 조용히 버려져 "범위를 넓힌 척" 이 된다 — 실측(2026-09-24):
  #   hooks + 취약픽스처를 함께 넘겨도 `crit=0`, 픽스처 단독은 `crit=2`. 그래서 코퍼스마다 **호출을 분리**한다.
  #   T1.e 의 음성 코퍼스(hooks+scripts 102파일)와 범위를 맞춘다.
  out_hooks=""
  for corpus in hooks scripts; do
    o=$(SPECOPS_SAST_EXTERNAL=1 bash "$SC" "$P/$corpus" 2>&1); e=$?
    [ "$corpus" = hooks ] && out_hooks="$o"
    { printf '%s' "$o" | grep -qE 'crit=0 high=0' && [ "$e" = 0 ] \
      && ! printf '%s' "$o" | grep -q 'semgrep('; } \
      && ok "AC-6-sg 실 semgrep $corpus/ 오탐 0 (실행 확인 포함)" \
      || nope "AC-6-sg 오탐 ($corpus)" "out=$o ec=$e"
  done

  # AC-3-sg 룰셋 출처 표기 = 실행 receipt.
  #   대상을 hooks 출력으로 **고정**한다 — 루프의 마지막 $o 를 쓰면 코퍼스를 추가·재배치할 때
  #   검사 대상이 조용히 옮겨간다(무음 이동).
  printf '%s' "$out_hooks" | grep -qF '(룰셋: 로컬 bash-injection)' \
    && ok "AC-3-sg 룰셋 출처 표기" || nope "AC-3-sg 출처 표기" "out=$out_hooks"
else
  skip "AC-5-sg·AC-6-sg·AC-3-sg semgrep 미설치 — 실 스캔 미실행 (PASS 집계 제외)"
fi

# ── 다중 인자·존재 검증 (FID 20261003-ops-debt) ─────────────────────────────
# ※ 외부 스캐너는 위에서 SPECOPS_SAST_EXTERNAL=0 으로 기본 차단 — self-check 레이어만 본다.
T=$(mktemp -d); printf 'def f():\n    return 1\n' > "$T/clean.py"
printf 'aws=%s\n' "AKIA""IOSFODNN7EXAMPLE" > "$T/leak.py"; mkdir -p "$T/d"; cp "$T/leak.py" "$T/d/leak2.py"
o_single=$(bash "$SC" "$T/leak.py" 2>&1)
o1=$(bash "$SC" "$T/clean.py" "$T/leak.py" 2>&1); e1=$?
o2=$(bash "$SC" "$T/leak.py" "$T/clean.py" 2>&1); e2=$?
o3=$(bash "$SC" "$T/clean.py" "$T/d" 2>&1); e3=$?
o4=$(bash "$SC" "$T/d" "$T/clean.py" 2>&1); e4=$?
oc=$(bash "$SC" "$T/clean.py" 2>&1); ec=$?
{ [ "$e1" = 1 ] && [ "$e2" = 1 ] && [ "$e3" = 1 ] && [ "$e4" = 1 ] && printf '%s%s%s%s' "$o1" "$o2" "$o3" "$o4" | grep -qE 'crit=[1-9]' && [ "$ec" = 0 ] && printf '%s' "$oc" | grep -q 'crit=0 high=0'; } \
  && ok "AC-2-ma 다중 인자: 순서·파일/디렉터리 혼합과 무관하게 위험한 인자를 놓치지 않는다(둘째만 위험해도 차단)" \
  || nope "AC-2-ma" "e=$e1/$e2/$e3/$e4 o1=$o1 oc=$oc ec=$ec"
for bad in "$T/none" "" "$T/clean.py $T/leak.py"; do
  ob=$(bash "$SC" "$bad" 2>"$T/err"); eb=$?
  { [ "$eb" = 2 ] && [ -z "$ob" ] && grep -qF "SECURITY: 대상 없음 — $bad" "$T/err" && ! grep -q 'syntax error' "$T/err"; } \
    && ok "AC-3-ne 존재하지 않는 인자 → rc 2·stdout 없음·'대상 없음' (인자='${bad:0:20}')" || nope "AC-3-ne" "bad='$bad' eb=$eb ob=$ob err=$(cat "$T/err")"
done
ob=$(bash "$SC" "$T/leak.py" "$T/none" 2>"$T/err"); eb=$?
{ [ "$eb" = 2 ] && [ -z "$ob" ]; } && ok "AC-3-ne2 실존+미존재 혼합 → rc 2·부분 스캔 없음(stdout 없음)" || nope "AC-3-ne2" "eb=$eb ob=$ob"
ob=$(bash "$SC" "$(printf '%s\n%s' "$T/clean.py" "$T/leak.py")" 2>"$T/err"); eb=$?
{ [ "$eb" = 2 ] && grep -q '대상 없음' "$T/err"; } && ok "AC-3-nl 개행 이은 목록 문자열 → rc 2" || nope "AC-3-nl" "eb=$eb"
od=$(bash "$SC" "$T/leak.py" "$T/leak.py" 2>&1); ed=$?
od2=$(bash "$SC" "$T/leak.py" "$T/clean.py" "$T/leak.py" 2>&1); ed2=$?
{ [ "$od" = "$o_single" ] && [ "$ed" = 1 ] && [ "$od2" = "$o_single" ] && [ "$ed2" = 1 ]; } \
  && ok "AC-5-dup 문자열 완전 일치 중복 인자는 1회만 스캔(단독과 같은 출력·건수)" || nope "AC-5-dup" "od=$od single=$o_single od2=$od2"
oe=$(bash "$SC" "$T/clean.py" "" 2>"$T/err"); ee=$?
{ [ "$ee" = 2 ] && [ -z "$oe" ] && grep -q '대상 없음' "$T/err"; } && ok "AC-5-empty 빈 문자열 인자 → rc 2·부분 스캔 없음" || nope "AC-5-empty" "ee=$ee"
o_dot=$( cd "$T" && bash "$SC" 2>&1 ); e_dot=$?; o_dot2=$( cd "$T" && bash "$SC" . 2>&1 ); e_dot2=$?
{ [ "$o_dot" = "$o_dot2" ] && [ "$e_dot" = "$e_dot2" ] && [ "$e_dot" = 1 ]; } \
  && ok "AC-R-1-noarg 인자 없음 = '.' (출력·rc 동일)" || nope "AC-R-1-noarg" "o_dot=$o_dot o_dot2=$o_dot2"
rm -rf "$T"

# 외부 스캐너 계약 — 다중 인자에서도 gitleaks 인자별 호출·합산, 시간 상한·강등 표기 유지 (PATH stub — 설치 여부 무관)
T=$(mktemp -d); mkdir -p "$T/bin"
printf 'def f():\n    return 1\n' > "$T/a.py"; printf 'x=1\n' > "$T/b.py"
cat > "$T/bin/gitleaks" <<'STUB'
#!/usr/bin/env bash
# source/report-path 를 기록하고 report 에 1건짜리 JSON 배열을 쓴다
src=""; rep=""
while [ "$#" -gt 0 ]; do case "$1" in --source) src="$2"; shift 2;; --report-path) rep="$2"; shift 2;; *) shift;; esac; done
printf '%s\n' "$src" >> "$STUB_LOG"; printf '[{"RuleID":"x"}]\n' > "$rep"; exit 0
STUB
chmod +x "$T/bin/gitleaks"
out=$(STUB_LOG="$T/log" PATH="$T/bin:$PATH" SPECOPS_SAST_EXTERNAL=1 SPECOPS_SAST_TIMEOUT=0 bash "$SC" "$T/a.py" "$T/b.py" 2>&1); ec=$?
calls=$(wc -l < "$T/log" | tr -d ' ')
{ [ "$calls" = 2 ] && printf '%s' "$out" | grep -qE 'crit=2 ' && [ "$ec" = 1 ]; } \
  && ok "AC-4-gl 다중 인자 gitleaks 인자별 2회 호출·건수 합산(crit=2)" || nope "AC-4-gl" "calls=$calls out=$out ec=$ec"
rm -rf "$T"

# 첫 호출만 1건을 쓰고 이후 호출은 리포트 없이 rc 3 으로 실패 — stale 리포트 이중 계상 방지(: > 리포트)와 강등 표기 1회를 잠근다
T=$(mktemp -d); mkdir -p "$T/bin"
printf 'x=1\n' > "$T/a.py"; printf 'x=2\n' > "$T/b.py"; printf 'x=3\n' > "$T/c.py"
cat > "$T/bin/gitleaks" <<'STUB'
#!/usr/bin/env bash
rep=""
while [ "$#" -gt 0 ]; do case "$1" in --report-path) rep="$2"; shift 2;; *) shift;; esac; done
n=$(cat "$STUB_N" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$STUB_N"
if [ "$n" = 1 ]; then printf '[{"RuleID":"x"}]\n' > "$rep"; exit 0; fi
exit 3
STUB
chmod +x "$T/bin/gitleaks"
out=$(STUB_N="$T/n" PATH="$T/bin:$PATH" SPECOPS_SAST_EXTERNAL=1 SPECOPS_SAST_TIMEOUT=0 bash "$SC" "$T/a.py" "$T/b.py" "$T/c.py" 2>&1); ec=$?
notes=$(printf '%s' "$out" | grep -o 'gitleaks(실행실패 rc=3)' | wc -l | tr -d ' ')
{ printf '%s' "$out" | grep -qE 'crit=1 ' && [ "$notes" = 1 ] && [ "$ec" = 1 ]; } \
  && ok "AC-4-fail 일부 인자 gitleaks 실패: stale 리포트 이중 계상 없음(crit=1)·강등 표기 1회·rc 1" || nope "AC-4-fail" "notes=$notes out=$out ec=$ec"
# 리포트가 JSON 이 아니어도 산술 구문 오류 없이 0 건으로 집계
cat > "$T/bin/gitleaks" <<'STUB'
#!/usr/bin/env bash
rep=""
while [ "$#" -gt 0 ]; do case "$1" in --report-path) rep="$2"; shift 2;; *) shift;; esac; done
printf 'not json at all\n' > "$rep"; exit 0
STUB
out=$(PATH="$T/bin:$PATH" SPECOPS_SAST_EXTERNAL=1 SPECOPS_SAST_TIMEOUT=0 bash "$SC" "$T/a.py" "$T/b.py" 2>&1); ec=$?
{ ! printf '%s' "$out" | grep -q 'syntax error' && printf '%s' "$out" | grep -qE 'crit=0 ' && [ "$ec" = 0 ]; } \
  && ok "AC-4-garbage 비 JSON 리포트 → 산술 오류 없이 crit=0" || nope "AC-4-garbage" "out=$out ec=$ec"
rm -rf "$T"

# semgrep PATH stub — 다중 경로가 **한 번의** 호출 argv 에 모두 들어가는지(CI 러너에 semgrep 이 없어도 회귀를 잠근다)
if command -v jq >/dev/null 2>&1; then
  T=$(mktemp -d); mkdir -p "$T/bin"; printf 'x=1\n' > "$T/a.py"; printf 'x=2\n' > "$T/b.py"
  cat > "$T/bin/semgrep" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"; printf '{"results":[]}\n'; exit 0
STUB
  chmod +x "$T/bin/semgrep"
  out=$(STUB_LOG="$T/log" PATH="$T/bin:$PATH" SPECOPS_SAST_EXTERNAL=1 SPECOPS_SAST_TIMEOUT=0 bash "$SC" "$T/a.py" "$T/b.py" 2>&1); ec=$?
  calls=$(wc -l < "$T/log" | tr -d ' ')
  { [ "$calls" = 1 ] && grep -qF "$T/a.py $T/b.py" "$T/log" && [ "$ec" = 0 ] && printf '%s' "$out" | grep -qF '(룰셋: 로컬 bash-injection)'; } \
    && ok "AC-4-sgstub semgrep 1회 호출에 모든 경로(a.py b.py 순서대로)가 들어간다 · 룰셋 receipt" || nope "AC-4-sgstub" "calls=$calls log=$(cat "$T/log") out=$out ec=$ec"
  rm -rf "$T"
else
  skip "AC-4-sgstub jq 미설치 — 외부 집계 skip 경로라 semgrep 호출 없음 (PASS 집계 제외)"
fi

# 실 semgrep — 다중 경로를 한 번에 넘겨도 둘째 파일의 위험(eval 변수 전개)을 놓치지 않고 룰셋 receipt 가 남는다
if command -v semgrep >/dev/null 2>&1; then
  T=$(mktemp -d); printf 'echo ok\n' > "$T/a.sh"; printf '#!/usr/bin/env bash\neval "$1"\n' > "$T/b.sh"
  oa=$(SPECOPS_SAST_EXTERNAL=1 bash "$SC" "$T/a.sh" 2>&1); ea=$?
  o1=$(SPECOPS_SAST_EXTERNAL=1 bash "$SC" "$T/a.sh" "$T/b.sh" 2>&1); e1=$?
  o2=$(SPECOPS_SAST_EXTERNAL=1 bash "$SC" "$T/b.sh" "$T/a.sh" 2>&1); e2=$?
  { printf '%s' "$oa" | grep -qE 'crit=0 ' && [ "$ea" = 0 ] \
    && printf '%s%s' "$o1" "$o2" | grep -qE 'crit=1 ' && [ "$e1" = 1 ] && [ "$e2" = 1 ] \
    && printf '%s' "$o1" | grep -qF '(룰셋: 로컬 bash-injection)' && ! printf '%s' "$o1" | grep -q 'semgrep('; } \
    && ok "AC-4-sg 실 semgrep 다중 경로: 둘째만 위험해도 순서 무관 crit=1·룰셋 receipt·강등 없음" || nope "AC-4-sg" "oa=$oa o1=$o1 e1=$e1 o2=$o2 e2=$e2"
  rm -rf "$T"
else
  skip "AC-4-sg semgrep 미설치 — 실 다중 경로 스캔 미실행 (PASS 집계 제외)"
fi

# semgrep 경로 하나가 실패해도 나머지 경로의 탐지는 살아남는다 (Phase C 보정) — PATH stub: argv 에 bad.py 가 있으면 rc 2
T=$(mktemp -d); mkdir -p "$T/bin"; printf 'x=1\n' > "$T/evil.py"; printf 'x=2\n' > "$T/bad.py"; printf 'x=3\n' > "$T/ok.py"
cat > "$T/bin/semgrep" <<'STUB'
#!/usr/bin/env bash
case " $* " in *"/bad.py "*) exit 2;; esac
case "$*" in *evil.py*) printf '{"results":[{"extra":{"severity":"ERROR"}}]}\n';; *) printf '{"results":[]}\n';; esac; exit 0
STUB
chmod +x "$T/bin/semgrep"
if command -v jq >/dev/null 2>&1; then
  o1=$(PATH="$T/bin:$PATH" SPECOPS_SAST_EXTERNAL=1 SPECOPS_SAST_TIMEOUT=0 bash "$SC" "$T/evil.py" "$T/bad.py" "$T/ok.py" 2>&1); e1=$?
  o2=$(PATH="$T/bin:$PATH" SPECOPS_SAST_EXTERNAL=1 SPECOPS_SAST_TIMEOUT=0 bash "$SC" "$T/bad.py" "$T/ok.py" "$T/evil.py" 2>&1); e2=$?
  o3=$(PATH="$T/bin:$PATH" SPECOPS_SAST_EXTERNAL=1 SPECOPS_SAST_TIMEOUT=0 bash "$SC" "$T/ok.py" "$T/evil.py" 2>&1); e3=$?
  { printf '%s%s' "$o1" "$o2" | grep -qE 'crit=1 ' && [ "$e1" = 1 ] && [ "$e2" = 1 ] \
    && printf '%s' "$o1" | grep -qF 'semgrep(실행실패 rc=2)' && ! printf '%s' "$o1" | grep -qF '(룰셋:' \
    && printf '%s' "$o3" | grep -qF '(룰셋: 로컬 bash-injection)' && printf '%s' "$o3" | grep -qE 'crit=1 ' && [ "$e3" = 1 ]; } \
    && ok "AC-4-fallback 한 경로 semgrep 실패 → 경로별 재시도로 성한 경로 탐지 보존·강등 표기·receipt 없음 (전부 성공이면 receipt)" \
    || nope "AC-4-fallback" "o1=$o1 e1=$e1 o2=$o2 e2=$e2 o3=$o3 e3=$e3"
else
  skip "AC-4-fallback jq 미설치 — 외부 집계 skip 경로 (PASS 집계 제외)"
fi
rm -rf "$T"
if command -v semgrep >/dev/null 2>&1; then
  T=$(mktemp -d); printf 'echo ok\n' > "$T/a.sh"; printf '#!/usr/bin/env bash\neval "$1"\n' > "$T/evil.sh"; ln -s a.sh "$T/link.sh"
  o=$(SPECOPS_SAST_EXTERNAL=1 bash "$SC" "$T/evil.sh" "$T/link.sh" 2>&1); e=$?
  { printf '%s' "$o" | grep -qE 'crit=1 ' && [ "$e" = 1 ] && printf '%s' "$o" | grep -qF 'semgrep(실행실패'; } \
    && ok "AC-4-sglink 실 semgrep: 심볼릭 링크 인자가 섞여도 evil.sh 탐지 보존(crit=1)·강등 표기" || nope "AC-4-sglink" "o=$o e=$e"
  rm -rf "$T"
else
  skip "AC-4-sglink semgrep 미설치 — 실 심볼릭 링크 인자 스캔 미실행 (PASS 집계 제외)"
fi

# ── 문서 확장자 파일 인자 (FID 20261012-security-scan-md-fp) ─────────────────
# 서술문 속 위험함수 낱말은 코드가 아니다. 파일 인자일 때만 high 가 나던 비대칭(디렉토리 분기는 코드 확장자만 순회)을 잠근다.
# 해제 범위는 위험함수·SQL 룰뿐이다 — 문서의 secret 과 코드 파일·.html·확장자 없는 스크립트는 계속 잡혀야 한다(양성 대조군).
T=$(mktemp -d)
DOC_PROSE='이 함수에서 eval(x) 나 exec(y), os.system, el.innerHTML = z 를 쓰지 말라는 서술이다.'
DOC_SQL='나쁜 예: f"SELECT * FROM t WHERE id={uid}" 같은 문자열 조립.'
for ext in md markdown txt rst adoc MD; do
  printf '%s\n%s\n' "$DOC_PROSE" "$DOC_SQL" > "$T/note.$ext"
  o=$(bash "$SC" "$T/note.$ext" 2>&1); e=$?
  { [ "$e" = 0 ] && printf '%s' "$o" | grep -q 'crit=0 high=0'; } \
    && ok "DOC-1 .$ext 서술은 위험함수·SQL high 를 내지 않는다" || nope "DOC-1 .$ext" "o=$o e=$e"
done
# 계약: 문서 확장자면 shebang 이 있어도 문서다(확장자가 이긴다) — 문서 확장자 파일을 직접 실행하는 경로가 이 플러그인에 없다(spec §7).
printf '#!/usr/bin/env python3\n%s\n%s\n' "$DOC_PROSE" "$DOC_SQL" > "$T/shebang.md"
o=$(bash "$SC" "$T/shebang.md" 2>&1); e=$?
{ [ "$e" = 0 ] && printf '%s' "$o" | grep -q 'crit=0 high=0'; } \
  && ok "DOC-1b 문서 확장자는 shebang 이 있어도 문서다(확장자 우선 계약)" || nope "DOC-1b" "o=$o e=$e"
printf '%s\n%s\n' "$DOC_PROSE" "$DOC_SQL" > "$T/code.py"
printf '%s\n%s\n' "$DOC_PROSE" "$DOC_SQL" > "$T/page.html"
printf '#!/usr/bin/env python3\n%s\n%s\n' "$DOC_PROSE" "$DOC_SQL" > "$T/script"
# 경계 번짐 대조군 — 문서 확장자와 닮았지만 문서가 아닌 것: .mdx(JSX 를 담을 수 있다 — clarifications 결정) · .md.py(끝 확장자가 py)
printf '%s\n%s\n' "$DOC_PROSE" "$DOC_SQL" > "$T/note.mdx"
printf '%s\n%s\n' "$DOC_PROSE" "$DOC_SQL" > "$T/note.md.py"
for f in code.py page.html script note.mdx note.md.py; do
  o=$(bash "$SC" "$T/$f" 2>&1); e=$?
  { [ "$e" = 1 ] && printf '%s' "$o" | grep -qE 'high=[1-9]'; } \
    && ok "DOC-2 양성 대조군: 같은 문장이 $f 에서는 여전히 high" || nope "DOC-2 $f" "o=$o e=$e"
done
for f in note.md note.markdown; do
  printf 'aws=%s\n' "AKIA""IOSFODNN7EXAMPLE" > "$T/sec.$f"
  o=$(bash "$SC" "$T/sec.$f" 2>&1); e=$?
  { [ "$e" = 1 ] && printf '%s' "$o" | grep -qE 'crit=[1-9]'; } \
    && ok "DOC-3 문서 확장자(sec.$f)의 secret 은 여전히 crit" || nope "DOC-3 sec.$f" "o=$o e=$e"
done
oc=$(bash "$SC" "$T/code.py" 2>&1)
o1=$(bash "$SC" "$T/note.md" "$T/code.py" 2>&1); e1=$?
o2=$(bash "$SC" "$T/code.py" "$T/note.md" 2>&1); e2=$?
hc=$(printf '%s' "$oc" | grep -oE 'high=[0-9]+' | head -1)
{ [ "$e1" = 1 ] && [ "$e2" = 1 ] && [ -n "$hc" ] && [ "$hc" != "high=0" ] \
  && [ "$(printf '%s' "$o1" | grep -oE 'high=[0-9]+' | head -1)" = "$hc" ] && [ "$(printf '%s' "$o2" | grep -oE 'high=[0-9]+' | head -1)" = "$hc" ]; } \
  && ok "DOC-4 문서와 코드 파일을 함께 주면 순서 무관하게 차단되고 high 는 코드 파일 단독($hc)과 같다(문서 기여 0)" || nope "DOC-4" "e1=$e1 e2=$e2 hc=$hc o1=$o1 o2=$o2"
# DOC-5: 외부 스캐너를 켠 채에도 문서 서술은 high 를 내지 않는다 (semgrep 룰은 bash 전용 — 설치된 환경에서만)
if command -v semgrep >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  o=$(SPECOPS_SAST_EXTERNAL=1 bash "$SC" "$T/note.md" "$T/note.rst" 2>&1); e=$?
  { [ "$e" = 0 ] && printf '%s' "$o" | grep -q 'crit=0 high=0' && printf '%s' "$o" | grep -qF '(룰셋: 로컬 bash-injection)'; } \
    && ok "DOC-5 외부 스캐너를 켠 채에도 문서 서술은 high 를 내지 않는다(룰셋 receipt 유지)" || nope "DOC-5" "o=$o e=$e"
else
  skip "DOC-5 semgrep·jq 미설치 — 외부 스캐너를 켠 문서 스캔 미실행 (PASS 집계 제외)"
fi
rm -rf "$T"

# ── JSON 데이터 파일 인자 (llm-eval evals.json SQL 오탐 — FID 20261021-api-designer-agent 에서 분류·이연) ──
# .json 은 실행되지 않는 데이터다. 한 줄 수천 자짜리 문자열에 `execute(` … 산문 `+` … `params` 가 놓이면 SQL 룰이 high 를 냈다.
# 해제는 확장자로만 한다 — 같은 줄이 .py 에 있으면, 그리고 진짜 문자열 조립 SQL 은 계속 high 다(양성 대조군).
T=$(mktemp -d)
pad=$(printf '%0900d' 0 | tr 0 x)
JSON_LINE="{\"prompt\": \"plan: session.execute(select(User)) ${pad} 산문 a + b ${pad} params = inspect.signature(fn) 그리고 eval(x) 서술\"}"
printf '%s\n' "$JSON_LINE" > "$T/evals.json"
printf '%s\n' "$JSON_LINE" > "$T/EVALS.JSON"
for f in evals.json EVALS.JSON; do
  o=$(bash "$SC" "$T/$f" 2>&1); e=$?
  { [ "$e" = 0 ] && printf '%s' "$o" | grep -q 'crit=0 high=0'; } \
    && ok "JSON-1 $f 데이터 줄은 위험함수·SQL high 를 내지 않는다" || nope "JSON-1 $f" "o=$o e=$e"
done
# 실제 오탐 원본 — 저장소의 evals.json (읽기만 한다)
REAL_EVALS="$P/scripts/tests/llm-eval/skills/specifying-ko/evals.json"
if [ -f "$REAL_EVALS" ]; then
  o=$(bash "$SC" "$REAL_EVALS" 2>&1); e=$?
  { [ "$e" = 0 ] && printf '%s' "$o" | grep -q 'crit=0 high=0'; } \
    && ok "JSON-1b 실제 specifying-ko/evals.json 은 high=0" || nope "JSON-1b" "o=$o e=$e"
else
  skip "JSON-1b specifying-ko/evals.json 부재 — 실파일 대조 미실행 (PASS 집계 제외)"
fi
printf '%s\n' "$JSON_LINE" > "$T/same.py"
printf '%s\n' "$JSON_LINE" > "$T/evals.json.py"
printf 'cursor.execute("SELECT * FROM users WHERE name = \x27" + request.args["q"] + "\x27")\n' > "$T/real.py"
for f in same.py evals.json.py real.py; do
  o=$(bash "$SC" "$T/$f" 2>&1); e=$?
  { [ "$e" = 1 ] && printf '%s' "$o" | grep -qE 'high=[1-9]'; } \
    && ok "JSON-2 양성 대조군: $f 는 여전히 high" || nope "JSON-2 $f" "o=$o e=$e"
done
printf '{"aws": "%s"}\n' "AKIA""IOSFODNN7EXAMPLE" > "$T/sec.json"
o=$(bash "$SC" "$T/sec.json" 2>&1); e=$?
{ [ "$e" = 1 ] && printf '%s' "$o" | grep -qE 'crit=[1-9]'; } \
  && ok "JSON-3 .json 의 secret 은 여전히 crit" || nope "JSON-3" "o=$o e=$e"
rm -rf "$T"

# SKIP 을 요약에 드러낸다 — green 이 곧 전량 실행은 아니다(도구 부재로 축소 실행 가능).
#   SKIP=0 이면 종전 출력과 바이트 동일하다.
sk=""; [ "${SKIP:-0}" -gt 0 ] && sk=" SKIP=$SKIP"
echo "── test-security-scan: PASS=$PASS FAIL=$FAIL$sk ──"
[ "$FAIL" -eq 0 ]
