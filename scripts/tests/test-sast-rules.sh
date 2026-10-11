#!/usr/bin/env bash
# SAST 로컬 룰셋 검증 (FID 20260917-sast-offline-ruleset)
#   AC-1 룰 2개 로드 · AC-5 양성(행 번호까지) · AC-6 프로덕션 오탐 0
#   semgrep 호출에는 반드시 SEMGREP_ENABLE_VERSION_CHECK=0 — 없으면 semgrep.dev 로 ~99s 매달린다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
P=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$P/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
RULES="$P/scripts/_internal/semgrep-rules/bash-injection.yml"
FIX="$P/scripts/tests/fixtures/sast/vulnerable.sh"
FIX_SAFE="$P/scripts/tests/fixtures/sast/safe.sh"

# T1.a AC-1 룰 파일 존재
[ -f "$RULES" ] && ok "T1.a AC-1 룰 파일 존재" || nope "T1.a AC-1 룰 파일" "$RULES 부재"

# T1.b AC-1 룰 2개 이상
# `grep -c` 는 0건에 "0" 출력 + rc=1 이라 `|| true` 로 rc 만 흡수한다
#   (`|| echo 0` 은 stdout 이 "0\n0" 이 되어 이어지는 `-ge 2` 가 integer error 를 낸다 — run-all:205 와 같은 idiom).
n=$(grep -c '^  - id:' "$RULES" 2>/dev/null || true); n=${n:-0}
[ "$n" -ge 2 ] && ok "T1.b AC-1 룰 $n 개 (2 이상)" || nope "T1.b AC-1 룰 개수" "n=$n"

# T1.c 픽스처 존재·실행권한
{ [ -f "$FIX" ] && [ -x "$FIX" ]; } && ok "T1.c 픽스처 존재·exec" || nope "T1.c 픽스처" "$FIX"

if command -v semgrep >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  TD=$(mktemp -d)
  # T1.d AC-5 양성 — 정확히 2건 + 행 번호 5·7 (픽스처 앞 3줄이 shebang·주석·directive)
  SEMGREP_ENABLE_VERSION_CHECK=0 semgrep --config "$RULES" --json "$FIX" > "$TD/pos.json" 2>/dev/null
  got=$(python3 -c "
import json
d=json.load(open('$TD/pos.json'))
print(sorted((r['check_id'].split('.')[-1], r['start']['line']) for r in d['results']))
" 2>/dev/null)
  want="[('bash-eval-var', 5), ('bash-rm-rf-var', 7)]"
  [ "$got" = "$want" ] && ok "T1.d AC-5 양성 2건 · 행 5·7" || nope "T1.d AC-5 양성" "got=$got want=$want"

  # T1.e AC-6 음성 — 프로덕션 코드 매치 0
  SEMGREP_ENABLE_VERSION_CHECK=0 semgrep --config "$RULES" --json "$P/hooks" "$P/scripts" \
    > "$TD/neg.json" 2>/dev/null
  m=$(python3 -c "import json;print(len(json.load(open('$TD/neg.json'))['results']))" 2>/dev/null)
  [ "$m" = 0 ] && ok "T1.e AC-6 프로덕션 오탐 0" || nope "T1.e AC-6 오탐" "매치=$m — 픽스처가 아니라 룰을 고칠 것"

  # T1.f AC-6 파싱 커버리지 floor — 2026-09-24 실측 48/102 → 2026-09-28 47/101 로 하향.
  #   하향 사유: 외부 디자인 플러그인 의존 제거 FID(20260928-uiux-promax-removal-design-master)가
  #   파싱 성공 파일 1건(자산 어댑터)을 삭제했다. 파서 퇴행이 아니라 파일 제거이며 사람 판정으로 floor 를 옮겼다.
  #   T1.e 의 "매치 0" 은 파싱된 범위에서만 유효하다 → 파서 퇴행을 무음으로 흘리면
  #   이 FID 가 고치려는 병(미실행이 PASS 로 보이는 것)이 음성 대조 안으로 이동한다.
  read -r parsed total <<<"$(python3 -c "
import json
d=json.load(open('$TD/neg.json'))
sc=len(d['paths']['scanned']); bad=len({e.get('path') for e in d.get('errors',[]) if e.get('path')})
print(sc-bad, sc)
" 2>/dev/null)"
  if [ -z "${parsed:-}" ]; then
    nope "T1.f AC-6 파싱 커버리지" "산출 실패 (python3/JSON)"
  elif [ "$parsed" -ge 47 ]; then
    ok "T1.f AC-6 파싱 커버리지 $parsed/$total (floor 47)"
  else
    nope "T1.f AC-6 파싱 커버리지" "$parsed/$total — floor 47 미달 (파서 퇴행 또는 파일 제거 — 사람 판정)"
  fi
  # T1.g AC-6 음성 대조 픽스처 — 안전한 관용구에 매치 0 (룰 **정밀도**를 잠근다)
  #   왜 별건인가: 프로덕션 102파일에는 파싱 가능한 `rm -rf`·`eval` 문이 없어 느슨한 룰도 0건을 낸다
  #   → T1.e 만으로는 정밀도를 판별하지 못한다. 판별력 실측(2026-09-24, 이 픽스처 기준):
  #   현행 0건 / M1 변이(`rm -rf $...X` 원복) 단독 **4건** / M5 변이(`eval $...X`) 단독 **2건**.
  #   (종전 주석은 M5 를 6건으로 적었으나 그것은 M1+M5 **동시 적용값**이다 — 부모가 M1 변이본을
  #    다시 고쳐 M5 를 만든 탓에 두 변이가 겹친 측정치를 M5 단독으로 라벨했다. Phase C 재판정 적발.)
  #   ⚠️ 반드시 **명시 경로**로 스캔한다. hooks+scripts 코퍼스 스캔에 얹으면 `scripts/tests/` 가
  #   semgrep dir 스캔에서 제외되어(실측: scripts 스캔 91파일, fixtures 미포함) 파일이 스캔되지
  #   않은 채 "매치 0" 이 공허하게 참이 된다. 그래서 scanned≥1 · errors=0 · 매치 0 을 **동시에**
  #   요구한다 — 하나라도 빠지면 이 FID 가 고치려는 병(미실행이 PASS 로 보이는 것)이 음성 대조 안에서 재발한다.
  SEMGREP_ENABLE_VERSION_CHECK=0 semgrep --config "$RULES" --json "$FIX_SAFE" \
    > "$TD/safe.json" 2>/dev/null
  read -r sc_n er_n hit_n hits <<<"$(python3 -c "
import json
d=json.load(open('$TD/safe.json'))
r=d['results']
print(len(d['paths']['scanned']),
      len({e.get('path') for e in d.get('errors',[]) if e.get('path')}),
      len(r),
      sorted((x['check_id'].split('.')[-1], x['start']['line']) for x in r))
" 2>/dev/null)"
  if [ -z "${sc_n:-}" ] || [ -z "${hit_n:-}" ]; then
    nope "T1.g AC-6 음성 대조" "산출 실패 (python3/JSON)"
  elif [ "$sc_n" -lt 1 ] || [ "$er_n" -ne 0 ]; then
    nope "T1.g AC-6 음성 대조" "스캔 미성립 scanned=$sc_n errors=$er_n — '매치 0' 이 공허하게 참일 수 있다"
  elif [ "$hit_n" -ne 0 ]; then
    nope "T1.g AC-6 음성 대조" "안전 관용구 오탐 $hit_n 건 hits=$hits — 픽스처가 아니라 룰을 고칠 것"
  else
    ok "T1.g AC-6 음성 대조 픽스처 오탐 0 (scanned=$sc_n)"
  fi
  rm -rf "$TD"
else
  skip "T1.d~g semgrep 또는 python3 미설치 — 실 스캔 미실행 (PASS 집계 제외)"
fi

# SKIP 을 요약에 드러낸다 — green 이 곧 전량 실행은 아니다(도구 부재로 축소 실행 가능).
#   SKIP=0 이면 종전 출력과 바이트 동일하다.
sk=""; [ "${SKIP:-0}" -gt 0 ] && sk=" SKIP=$SKIP"
echo "── test-sast-rules: PASS=$PASS FAIL=$FAIL$sk ──"
[ "$FAIL" -eq 0 ]
