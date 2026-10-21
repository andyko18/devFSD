#!/usr/bin/env bash
# check-ac-format.sh — AC 필드 게이트 (20260807, OpenSpec 대비 갭분석 G1)
# Usage: check-ac-format.sh <FID>
# Exit: 0 = PASS(WARN 포함) · 1 = FAIL · 2 = acceptance-criteria.md 부재
#
# 왜 필요한가 — **게이트를 끄는 스위치가 무검증이었다**:
#   `emit-context.sh` 의 must AC 역방향 커버리지 검사는 `**우선순위**: must` 가 있는
#   AC 만 대상으로 삼는다. 코드 주석이 그 성질을 직접 적어 뒀다 —
#     "우선순위 필드가 아예 없는 구식/픽스처 AC 문서는 자연히 대상 0건(하위호환 fail-open)"
#   즉 모델이 `**우선순위**` 줄을 빠뜨리면 `must_ids = []` 가 되어 **검사가 통째로
#   무음으로 꺼진다**. 그리고 그 필드의 존재를 강제하는 층은 0곳이었다
#   (실측 20260807: AC 픽스처 7개 중 6개가 우선순위 0건 — 그 문서들에선 검사가 죽어 있었다).
#   결과는 "must AC 가 어느 태스크에도 매핑되지 않아 영영 구현되지 않는" 무음 사고다.
#
# 판정 (HARD = exit 1):
#   H1. 헤더형 일반 AC(`^#{2,3} AC-<n>`) ≥ 1건        — 불릿 전용 문서는 must 판정 영구 0건
#   H2. 블록마다 `**우선순위**: must|should|nice-to-have`  ← 스위치 잠금 (템플릿 §우선순위 규약)
#   H3. 블록마다 `**Given**`·`**When**`·`**Then**` 각 1건 이상
#   H4. 헤더·G/W/T 의 템플릿 골격 잔존(`<...>` · 값이 `...` 뿐) 없음
# 판정 (WARN = stdout, exit 0):
#   W1. `**검증 방법**` 부재  — tasks.md `test_command` 가 이미 hard 로 잡는다(중복)
#   W2. `**관련 FR**` 부재    — 대조 SoT 미결(spec §4 FR 표 vs .specops/memory/requirements.md).
#                               batch 경로에서 check-fr-table.sh 와 어긋날 위험이 있어 warn-first.
#   → 전환점: FR SoT 확정 시 W2 를 hard 로. W1 은 test_command 와 통합 판정으로.
#
# 대상 밖: `AC-R-*`(회귀 AC) — SoT 는 `check-regression-ac.sh`. 템플릿이 AC-R 을
#   대괄호 placeholder 로 배포하므로 신규 FID 가 그대로 두는 것이 정상이고,
#   여기서 함께 FAIL 내면 **모든 신규 FID 가 막힌다**.
set -u

FID="${1:?usage: $0 <FID>}"
SPECOPS="${SPECOPS_ROOT:-.specops}"
AC="$SPECOPS/$FID/acceptance-criteria.md"

[ -f "$AC" ] || { echo "AC-FORMAT: MISSING (acceptance-criteria.md 부재)"; exit 2; }

out=$(awk '
function flush() {
  if (cur == "") return
  n_blocks++
  if (prio == "")            err[++e] = cur ": **우선순위** 필드 부재 — must 커버리지 검사가 이 AC 를 보지 못한다"
  else if (prio !~ /^(must|should|nice-to-have)$/) \
                             err[++e] = cur ": **우선순위** 값 규약 위반 (\"" prio "\") — must·should·nice-to-have 중 하나"
  if (!g) err[++e] = cur ": **Given** 부재"
  if (!w) err[++e] = cur ": **When** 부재"
  if (!t) err[++e] = cur ": **Then** 부재"
  if (ph) err[++e] = cur ": 템플릿 골격 잔존 (미채움 — 실제 시나리오로 채우세요)"
  if (!vm) warn[++v] = cur ": **검증 방법** 부재"
  if (!fr) warn[++v] = cur ": **관련 FR** 부재"
  cur = ""
}
# 골격 판정: 값 **전체**가 `<...>` placeholder 이거나 점(...)뿐일 때.
#   ⚠️ 부분 매칭 금지 — 실사용 검증 1호 결함(20260807, FID 20260807-specops-doctor AC-3):
#      "…api-spec.md 에 `<placeholder>` 가 남아 있을 때" 라는 **정상 문장**이 골격으로
#      오판돼 dispatch 가 막혔다. 템플릿 골격은 값 전체가 placeholder 인 형태
#      (`**Given** <전제 조건·초기 상태>`)이므로 앵커드 매칭이 맞다.
#      클래스 B 교훈과 동일 — 과탐지는 정상 문서를 막아 게이트 신뢰를 깎는다.
#      대가: 부분 채움(`<전제> 이고 <조건>`)은 통과한다. 오탐보다 미탐을 택한다.
function skeleton(s) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
  gsub(/^`|`$/, "", s)                 # 백틱 코드스팬 감싸기 제거 후 판정
  # mawk 호환: 구간 반복({n,m})을 쓰지 않는다 — mawk 1.3.4(Ubuntu 24.04 기본)는 지원하지 않아 매칭이 0건이 된다.
  #   길이 상한은 length() 로 본다(gawk·UTF-8 은 문자, mawk·BWK 는 바이트 — 한글 자리표시자는 mawk 에서 더 짧게 끊긴다).
  if (s ~ /^<[^<>]+>$/ && length(s) <= 62) return 1
  if (s ~ /^\.\.+$/) return 1
  return 0
}
/^(##|###)[[:space:]]+AC-/ {
  flush()
  # 헤더 규칙은 next 로 끝나므로 말미의 토큰 스캔 규칙이 헤더 줄을 보지 못한다.
  #   여기서 직접 세지 않으면 **AC-R 만 있는 유지보수 문서**가 has_token=0 이 되어
  #   "AC 0건 — 계약이 비어 있다" 로 오판된다 (AC-R-1 이 눈앞에 있는데도).
  #   T8/T8b 가 미채운 AC-1..3 골격을 hard 로 막으므로, 유지보수 FID 에서 템플릿
  #   골격을 지우는 것이 **정상 대응**이고 그때 정확히 이 경로에 닿는다.
  has_token = 1
  hdr = $0
  sub(/^#+[[:space:]]+/, "", hdr)
  id = hdr; sub(/[:[:space:]].*$/, "", id)
  # AC-R 배제는 아래 두 줄이 **각각 단독으로** 성립한다(의도된 이중 방어).
  #   변이 검증 20260807: 한 줄만 지우면 T10 이 통과한다 — 둘 다 지워야 실패한다.
  if (id ~ /^AC-R-/) { cur = ""; next }        # 회귀 AC 는 SoT 분리(check-regression-ac)
  if (id !~ /^AC-[0-9]+$/) { cur = ""; next }  # AC-1, AC-2 … 만 일반 AC
  n_general++
  cur = id; prio = ""; g = 0; w = 0; t = 0; vm = 0; fr = 0; ph = 0
  rest = hdr; sub(/^[^:]*:?[[:space:]]*/, "", rest)
  if (skeleton(rest)) ph = 1
  next
}
/^(##|###)[[:space:]]/ { flush(); next }
cur != "" {
  line = $0
  # 존재 판정은 **행 어디서든** — `**Given** 입력 / **When** 실행 / **Then** 정상` 처럼
  #   한 줄에 몰아 쓰는 실사용 형태가 흔하다(픽스처 missing-tc·bad-ac). 목적은 세 절의
  #   존재이지 배치가 아니다. 골격(placeholder) 판정만 행두 형태에서 값을 떼어 본다.
  if (line ~ /\*\*Given\*\*/) { g = 1; if (line ~ /^\*\*Given\*\*/) { val = line; sub(/^\*\*Given\*\*[[:space:]]*/, "", val); if (skeleton(val)) ph = 1 } }
  if (line ~ /\*\*When\*\*/)  { w = 1; if (line ~ /^\*\*When\*\*/)  { val = line; sub(/^\*\*When\*\*[[:space:]]*/,  "", val); if (skeleton(val)) ph = 1 } }
  if (line ~ /\*\*Then\*\*/)  { t = 1; if (line ~ /^\*\*Then\*\*/)  { val = line; sub(/^\*\*Then\*\*[[:space:]]*/,  "", val); if (skeleton(val)) ph = 1 } }
  if (line ~ /^\*\*검증 방법\*\*/) vm = 1
  if (line ~ /^\*\*관련 FR\*\*/)   fr = 1
  if (line ~ /^\*\*우선순위\*\*/) {
    prio = line
    sub(/^\*\*우선순위\*\*:?[[:space:]]*/, "", prio)
    gsub(/[[:space:]]+$/, "", prio)
  }
}
END {
  flush()
  if (n_general == 0) {
    # 토큰조차 없다 = 계약이 비어 있다 → HARD.
    # 토큰은 있는데 헤더형이 0건(불릿·표·산문) → WARN. emit-context 는 요약 추출에서
    #   불릿/표 형식을 의도적으로 구제한다(#209 · 20260716 dogfood). 그 계약을 여기서
    #   일방적으로 깨지 않는다. 다만 **must 커버리지는 그 문서에서 영구히 0건**이므로
    #   침묵시키지 않고 드러낸다 — 완전 봉합은 "불릿 형식 지원 폐기" 결정이 선행돼야 한다.
    if (has_token) print "WARN\t헤더형 일반 AC 0건 — 이 문서에서는 must 커버리지 검사가 동작하지 않는다 (`### AC-1: <제목>` 헤더 권장)"
    else           print "FAIL\tAC 0건 — 계약 항목이 비어 있다 (`### AC-1: <제목>` 형식으로 작성)"
  }
  for (i = 1; i <= e; i++) print "FAIL\t" err[i]
  for (i = 1; i <= v; i++) print "WARN\t" warn[i]
}
{ if ($0 ~ /AC-[0-9]/) has_token = 1 }
' "$AC")

fails=$(printf '%s\n' "$out" | grep -c '^FAIL' || true)
warns=$(printf '%s\n' "$out" | grep -c '^WARN' || true)

printf '%s\n' "$out" | grep '^WARN' | sed 's/^WARN\t/AC-FORMAT: WARN — /' || true

if [ "${fails:-0}" -gt 0 ]; then
  printf '%s\n' "$out" | grep '^FAIL' | sed 's/^FAIL\t/AC-FORMAT: FAIL — /'
  cat <<'EOF'
  왜 막는가: emit-context 의 **must AC 역방향 커버리지** 검사는 `**우선순위**: must` 가
  있는 AC 만 본다. 필드가 없으면 그 검사가 무음으로 꺼지고, must AC 가 어느 태스크에도
  매핑되지 않은 채 구현이 진행된다(= 그 기능은 영영 구현되지 않는다).
  해법: templates/acceptance-criteria.md 형식대로 AC 블록마다
        **Given** / **When** / **Then** / **우선순위** 를 채우세요.
EOF
  exit 1
fi

if [ "${warns:-0}" -gt 0 ]; then
  echo "AC-FORMAT: PASS (경고 ${warns}건)"
else
  echo "AC-FORMAT: PASS"
fi
exit 0
