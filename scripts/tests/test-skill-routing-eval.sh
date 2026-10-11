#!/usr/bin/env bash
# test-skill-routing-eval.sh — 결정론 skill 라우팅 eval 잠금 (FID 20261004-skill-routing-eval · AC-1~6)
# 토큰 0 · 모델/네트워크 호출 0 — fixture skills 와 mktemp 만 쓴다(실 repo smoke 는 T2 구간).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
EVAL="$PLUGIN/scripts/skill-routing-eval.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq 필요"; exit 0; }
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# ── fixture: 유사 쌍(alpha·beta) + 상이 4개 — gamma·delta·eps·zeta 는 commonword(df 4), gamma·delta·eps 는 tripleword(df 3 = 6×0.5 — 경계 포함 제외)만 공유한다(df 상한 확인용) ──
mkskill() {  # <루트> <이름> <description>
  mkdir -p "$1/skills/$2"; printf -- '---\nname: %s\ndescription: %s\n---\n# 본문\n' "$2" "$3" > "$1/skills/$2/SKILL.md"
}
FX="$TMP/fx"
mkskill "$FX" alpha-ko "계약 데이터를 검증하고 스키마 위반을 보고하는 도구 API 계약을 점검한다 alphaonly"
mkskill "$FX" beta-ko  "계약 데이터가 스키마를 위반하는지 검증하고 위반을 보고하는 도구 API 계약 점검을 수행한다"
mkskill "$FX" gamma-ko "이미지 파일을 압축하고 썸네일을 생성한다 resize cache commonword tripleword"
mkskill "$FX" delta-ko "사용자 로그인 세션을 관리하고 토큰을 갱신한다 oauth commonword tripleword"
mkskill "$FX" eps-ko   "배포 파이프라인 단계를 순서대로 실행하고 롤백한다 deploy commonword tripleword"
mkskill "$FX" zeta-ko  "고객 주문 결제 내역을 집계해 월간 보고서를 만든다 billing commonword"
NOQ="$TMP/noq"; mkdir -p "$NOQ"
run() { bash "$EVAL" --skills-dir "$FX/skills" --queries-dir "$NOQ" "$@" 2>&1; }

# T1.a 스크립트 존재·실행 가능
if [ -x "$EVAL" ]; then ok "T1.a scripts/skill-routing-eval.sh 존재·실행 가능"; else nope "T1.a" "$EVAL 부재 또는 실행권한 없음"; fi

# T1.b (AC-2) 한글 조사 제거·글자 bigram — 바이트가 아니라 글자 단위(awk 는 length 9)
_t1=$(bash "$EVAL" --dump-tokens "계약을 검증하는 API-gateway" 2>&1); _t2=$(bash "$EVAL" --dump-tokens "스키마를" 2>&1)
if [ "$_t1" = "계약 검증 api-gateway" ] && [ "$_t2" = "스키 키마" ]; then ok "T1.b 토큰화 — 조사 제거(계약을→계약·검증하는→검증)·글자 bigram(스키마를→스키 키마)·라틴 소문자(하이픈 유지)"
else nope "T1.b" "'$_t1' | '$_t2'"; fi

# T1.b2 (AC-2) 조사 제거 경계 — 2글자 어절은 말미 조사를 떼지 않음(이도) · 1글자는 그대로(시) · 말미 1개만(점검시→점검) · 최장 일치(에서는→서버 · 으로→처음)
_t3=$(bash "$EVAL" --dump-tokens "이도 점검시 배포등 서버에서는 서버에서 처음으로 시 사용및" 2>&1)
if [ "$_t3" = "이도 점검 배포 서버 서버 처음 시 사용" ]; then ok "T1.b2 조사 제거 경계 — 이도(2글자 보존)·점검시→점검·배포등→배포·서버에서는/서버에서→서버·처음으로→처음·시(1글자 보존)·사용및→사용"
else nope "T1.b2" "'$_t3'"; fi

# T1.c (AC-2) 유사 쌍만 PAIR-WARN · df 상한 — 4/6 문서 공통 어휘(commonword)만 공유하는 쌍은 0.000
_o=$(run)
_w=$(printf '%s\n' "$_o" | sed -n 's/^PAIR-WARN: alpha-ko ~ beta-ko cos=\(.*\)$/\1/p')
_cnt=$(printf '%s\n' "$_o" | grep -c '^PAIR-WARN:')
if [ -n "$_w" ] && [ "$_cnt" = 1 ] && printf '%s\n' "$_o" | grep -q '^SKILL-ROUTING: skills=6 pairs=15 '; then ok "T1.c 유사 쌍(alpha~beta cos=$_w)만 PAIR-WARN · 6 skill 15 쌍 요약"
else nope "T1.c" "w='$_w' cnt=$_cnt out=$_o"; fi
_all=$(run --warn-pair 0)
if printf '%s\n' "$_all" | grep -q '^PAIR-WARN: delta-ko ~ gamma-ko cos=0.000$'; then ok "T1.d df 상한 — 4/6 문서 공통 어휘(commonword)만 공유하는 쌍은 cos=0.000"
else nope "T1.d" "$(printf '%s\n' "$_all" | grep 'delta-ko ~ gamma-ko')"; fi
if printf '%s\n' "$_all" | grep -q '^PAIR-WARN: eps-ko ~ gamma-ko cos=0.000$'; then ok "T1.d2 df 경계 — 정확히 50%(3/6) 문서 공통 어휘(tripleword)도 제외(df ≥ N/2)"
else nope "T1.d2" "$(printf '%s\n' "$_all" | grep 'eps-ko ~ gamma-ko')"; fi

# T1.e (AC-1) 결정론·토큰 0 — 두 번 실행 cksum 동일 · curl/claude 가 호출되지 않음 · 로케일 독립
SHIM="$TMP/shim"; mkdir -p "$SHIM"
for _c in curl claude wget; do printf '#!/bin/sh\necho called > "%s/called.%s"\nexit 1\n' "$TMP" "$_c" > "$SHIM/$_c"; chmod +x "$SHIM/$_c"; done
_loc=$(locale -a 2>/dev/null | grep -i 'utf-\{0,1\}8' | sed -n 1p); [ -n "$_loc" ] || _loc=C   # 실재하는 UTF-8 로케일(없으면 C) — 없는 로케일을 쓰면 bash 가 stderr 경고를 낸다
_a=$(run | cksum); _b=$(PATH="$SHIM:$PATH" run | cksum); _c=$(LANG="$_loc" LC_ALL="$_loc" run | cksum)
if [ "$(run | sed -n 1p | cut -c1-14)" = "SKILL-ROUTING:" ] && [ "$_a" = "$_b" ] && [ "$_a" = "$_c" ] && [ ! -e "$TMP/called.curl" ] && [ ! -e "$TMP/called.claude" ] && [ ! -e "$TMP/called.wget" ]; then ok "T1.e 두 번·shim PATH·UTF-8 로케일 출력 동일 · curl/claude/wget 호출 0"
else nope "T1.e" "$_a|$_b|$_c called=$(ls "$TMP"/called.* 2>/dev/null | tr '\n' ' ')"; fi

# T1.f (AC-3) 기준선 드리프트 — 점수 +0.10(드리프트)·+0.04(경계 아래)·동일(드리프트 아님)·새 쌍(기준선에 없음)·기준선 부재(생략)
mkbase() { jq -n --argjson s "$1" '{version:1,pairs:{"alpha-ko~beta-ko":$s}}' > "$TMP/base.json"; }
_lo=$(jq -n --argjson s "$_w" '$s - 0.10'); _mid=$(jq -n --argjson s "$_w" '$s - 0.04')
mkbase "$_lo";  _d1=$(run --baseline "$TMP/base.json"); _r1=$?
mkbase "$_mid"; _d2=$(run --baseline "$TMP/base.json")
mkbase "$_w";   _d3=$(run --baseline "$TMP/base.json")
_hi=$(jq -n --argjson s "$_w" '$s + 0.10'); mkbase "$_hi"; _d7=$(run --baseline "$TMP/base.json")
_edge=$(jq -n --argjson s "$_w" '$s - 0.05'); mkbase "$_edge"; _d6=$(run --baseline "$TMP/base.json")
echo '{"version":1,"pairs":{}}' > "$TMP/base-empty.json"; _d4=$(run --baseline "$TMP/base-empty.json")
_d5=$(run --baseline "$TMP/nonexistent.json"); _r5=$?
if printf '%s\n' "$_d1" | grep -q '^PAIR-DRIFT: alpha-ko ~ beta-ko cos='"$_w"' baseline=' && printf '%s\n' "$_d1" | grep -q '^DRIFT: 1$' \
   && printf '%s\n' "$_d2" | grep -q '^DRIFT: 0$' && printf '%s\n' "$_d3" | grep -q '^DRIFT: 0$' && printf '%s\n' "$_d6" | grep -q '^DRIFT: 1$' && printf '%s\n' "$_d7" | grep -q '^DRIFT: 0$' \
   && printf '%s\n' "$_d4" | grep -q '^PAIR-DRIFT: alpha-ko ~ beta-ko cos='"$_w"' baseline=없음$' \
   && printf '%s\n' "$_d5" | grep -q '^BASELINE: 없음' && ! printf '%s\n' "$_d5" | grep -q '^DRIFT:' && [ "$_r1" = 0 ] && [ "$_r5" = 0 ]; then
  ok "T1.f 드리프트 — +0.10·정확히 +0.05(경계 포함) 경고 · +0.04·동일·하락(-0.10) 무경고 · 기준선에 없는 새 쌍 '없음' 병기 · 기준선 부재 BASELINE: 없음 · 모두 rc 0(warn-first)"
else nope "T1.f" "d1='$_d1' d2='$(printf '%s' "$_d2" | grep DRIFT)' d4='$(printf '%s' "$_d4" | grep DRIFT)' d5='$(printf '%s' "$_d5" | head -3)' r1=$_r1 r5=$_r5"; fi

# T1.g (AC-3) --strict — 드리프트 있으면 rc 1, 없으면 rc 0
mkbase "$_lo"; run --baseline "$TMP/base.json" --strict >/dev/null; _s1=$?
mkbase "$_w";  run --baseline "$TMP/base.json" --strict >/dev/null; _s2=$?
run --baseline "$TMP/nonexistent.json" --strict >/dev/null; _s3=$?
if [ "$_s1" = 1 ] && [ "$_s2" = 0 ] && [ "$_s3" = 0 ]; then ok "T1.g --strict: 드리프트 rc 1 · 무드리프트 rc 0 · 기준선 부재(판정 없음) rc 0"; else nope "T1.g" "s1=$_s1 s2=$_s2 s3=$_s3"; fi

# T1.h (AC-4) 입력 오류 rc 2 + stderr 사유 — skills 없음·description 누락·기준선 손상·질의 손상·미지 옵션·잘못된 숫자·block scalar description
_err() { { bash "$EVAL" "$@" >/dev/null; } 2>&1; }
mkdir -p "$TMP/nodesc/skills/x-ko" "$TMP/nodesc/skills/y-ko"; printf -- '---\nname: x-ko\n---\n' > "$TMP/nodesc/skills/x-ko/SKILL.md"; cp "$FX/skills/alpha-ko/SKILL.md" "$TMP/nodesc/skills/y-ko/SKILL.md"
echo '{broken' > "$TMP/base-bad.json"
mkdir -p "$TMP/qbad/alpha-ko"; echo '{broken' > "$TMP/qbad/alpha-ko/trigger-queries.json"
_bad=""
mkdir -p "$TMP/blk/skills/blk-ko" "$TMP/blk/skills/ok-ko"   # description 이 YAML block scalar(`>`) — 한 줄만 지원이라 조용히 빠지면 안 된다
printf -- '---\nname: blk-ko\ndescription: >\n  여러 줄 설명\n  둘째 줄\n---\n' > "$TMP/blk/skills/blk-ko/SKILL.md"; cp "$FX/skills/alpha-ko/SKILL.md" "$TMP/blk/skills/ok-ko/SKILL.md"
mkdir -p "$TMP/qfmt/alpha-ko"; echo '{"skill":"alpha-ko","should_trigger":[{"id":"p","query":5}]}' > "$TMP/qfmt/alpha-ko/trigger-queries.json"
for _spec in "skills 디렉터리 없음|--skills-dir $TMP/none" "description 누락|--skills-dir $TMP/nodesc/skills" "기준선 손상|--skills-dir $FX/skills --baseline $TMP/base-bad.json" "trigger-queries 손상|--skills-dir $FX/skills --queries-dir $TMP/qbad" "형식 오류|--skills-dir $FX/skills --queries-dir $TMP/qfmt" "알 수 없는 인자|--bogus" "--warn-pair|--skills-dir $FX/skills --warn-pair abc" "block scalar|--skills-dir $TMP/blk/skills"; do
  _want=${_spec%%|*}; _case=${_spec#*|}
  # shellcheck disable=SC2086
  _e=$(_err $_case); _rc=$(bash "$EVAL" $_case >/dev/null 2>&1; echo $?)
  { [ "$_rc" = 2 ] && printf '%s' "$_e" | grep -q "^ERROR: .*$_want"; } || _bad="$_bad [$_case → rc=$_rc '$_e' (기대 '$_want')]"
done
if [ -z "$_bad" ]; then ok "T1.h 입력 오류 8종(skills 없음·description 누락·기준선 손상·질의 손상·질의 형식·미지 옵션·잘못된 숫자·block scalar) → stderr ERROR+고유 사유 + rc 2"; else nope "T1.h" "$_bad"; fi

# T1.i (AC-4) jq 부재 — SKIP 한 줄 · rc 0 (오류를 경고로 위장하지 않음: jq 없이는 계산 자체가 불가)
NOJQ="$TMP/nojq"; mkdir -p "$NOJQ"; ln -s "$(command -v dirname)" "$NOJQ/dirname"
_nj=$(PATH="$NOJQ" "$BASH" "$EVAL" --skills-dir "$FX/skills" 2>&1); _njrc=$?
if [ "$_njrc" = 0 ] && [ "$_nj" = "SKILL-ROUTING: SKIP (jq 필요)" ]; then ok "T1.i jq 부재 → 'SKILL-ROUTING: SKIP (jq 필요)' rc 0"; else nope "T1.i" "rc=$_njrc out='$_nj'"; fi

# T1.i2 jq 부재 + --emit-baseline — 기준선 파일에 SKIP 문구가 들어가지 않게 stdout 비움 · stderr ERROR · rc 2
_nj2=$(PATH="$NOJQ" "$BASH" "$EVAL" --skills-dir "$FX/skills" --emit-baseline 2>"$TMP/nj2.err"); _nj2rc=$?
if [ "$_nj2rc" = 2 ] && [ -z "$_nj2" ] && grep -q '^ERROR: jq 필요' "$TMP/nj2.err"; then ok "T1.i2 jq 부재 + --emit-baseline → stdout 비움 · stderr ERROR · rc 2"; else nope "T1.i2" "rc=$_nj2rc out='$_nj2'"; fi

# T1.j (AC-5) 질의 라우팅 참고 지표 — 요약·QUERY-WARN(owner 순위 top_k=5 밖)·rc 0
mkdir -p "$TMP/q/alpha-ko"
cat > "$TMP/q/alpha-ko/trigger-queries.json" <<'JSON'
{"skill":"alpha-ko",
 "should_trigger":[{"id":"pos-1","query":"alphaonly API 계약 데이터를 검증해줘"},{"id":"pos-2","query":"오늘 점심 메뉴 추천해줘"},{"id":"pos-3","query":"이미지 파일 압축 썸네일"}],
 "should_not_trigger":[{"id":"neg-1","query":"썸네일 이미지 파일을 압축해줘"}]}
JSON
_q=$(bash "$EVAL" --skills-dir "$FX/skills" --queries-dir "$TMP/q" 2>&1); _qrc=$?
if [ "$_qrc" = 0 ] && printf '%s\n' "$_q" | grep -q '^QUERY-ROUTING: pos=3 owner-rank1=1 owner-top3=1 · neg=1 owner-rank1=0$' \
   && printf '%s\n' "$_q" | grep -q '^QUERY-WARN: alpha-ko pos-2 owner-rank=6 top1=-$' && printf '%s\n' "$_q" | grep -q '^QUERY-WARN: alpha-ko pos-3 owner-rank=6 top1=gamma-ko$' \
   && [ "$(printf '%s\n' "$_q" | grep '^QUERY-WARN:' | sed 's/^QUERY-WARN: alpha-ko \(pos-[0-9]\).*/\1/' | tr '\n' ' ')" = 'pos-2 pos-3 ' ] && ! printf '%s\n' "$_q" | grep -q '^QUERY-WARN: alpha-ko pos-1'; then
  ok "T1.j 질의 라우팅 — 요약(pos=3 owner-rank1=1 owner-top3=1 · neg owner-rank1=0) · owner 순위 밖 긍정 질의만 QUERY-WARN(pos-2 top1=- · pos-3 top1=gamma-ko, pos 순 정렬) · rc 0"
else nope "T1.j" "rc=$_qrc out=$(printf '%s\n' "$_q" | grep QUERY)"; fi

# T1.j2 (AC-5) 부정 질의 owner-rank1 카운터 구동 — owner 가 1위인 부정 질의(neg-1)만 센다(neg-2 는 owner 순위 밖)
mkdir -p "$TMP/q2/alpha-ko"
cat > "$TMP/q2/alpha-ko/trigger-queries.json" <<'JSON'
{"skill":"alpha-ko",
 "should_trigger":[{"id":"pos-1","query":"alphaonly API 계약 데이터를 검증해줘"}],
 "should_not_trigger":[{"id":"neg-1","query":"alphaonly API 계약 데이터를 검증해줘"},{"id":"neg-2","query":"이미지 파일 압축 썸네일"}]}
JSON
_q2=$(bash "$EVAL" --skills-dir "$FX/skills" --queries-dir "$TMP/q2" 2>&1); _q2rc=$?
if [ "$_q2rc" = 0 ] && printf '%s\n' "$_q2" | grep -q '^QUERY-ROUTING: pos=1 owner-rank1=1 owner-top3=1 · neg=2 owner-rank1=1$'; then
  ok "T1.j2 부정 질의 카운터 — owner 가 1위인 부정 질의만 센다(neg=2 owner-rank1=1)"
else nope "T1.j2" "rc=$_q2rc out=$(printf '%s\n' "$_q2" | grep QUERY)"; fi

# T1.k (AC-6) --emit-baseline — stdout 에만 JSON(임계 0.15 이상 쌍) · 결정론 · 파일 무변경 · 형식이 기준선으로 쓰임(drift 0)
_e1=$(bash "$EVAL" --skills-dir "$FX/skills" --queries-dir "$NOQ" --baseline "$TMP/never-written.json" --emit-baseline 2>"$TMP/emit.err"); _e2=$(bash "$EVAL" --skills-dir "$FX/skills" --queries-dir "$NOQ" --emit-baseline 2>/dev/null)
printf '%s\n' "$_e1" > "$TMP/emitted.json"
if [ "$_e1" = "$_e2" ] && [ ! -e "$TMP/never-written.json" ] && [ ! -s "$TMP/emit.err" ] && [ "$(jq -r '.version' "$TMP/emitted.json")" = 1 ] \
   && [ "$(jq -r '.pairs | keys | join(",")' "$TMP/emitted.json")" = "alpha-ko~beta-ko" ] && run --baseline "$TMP/emitted.json" | grep -q '^DRIFT: 0$'; then
  ok "T1.k --emit-baseline — stdout JSON(임계 0.15 이상 쌍만) · 두 번 동일 · 파일 미생성 · 출력을 기준선으로 쓰면 DRIFT: 0"
else nope "T1.k" "e1='$_e1'"; fi

# T1.l (AC-2) FR-1 수치 골든 — 손으로 계산 가능한 fixture 로 tf(1+ln)·idf(ln(N/df))·코사인 분모·df 계수를 점수로 잠근다
#   a-ko "aa bb cc" · b-ko "aa bb dd" → 0.429 / c-ko "xx xx yy zz"(xx 두 번 — tf=1+ln2) · d-ko "xx yy ww" → 0.488 (N=6, 독립 계산: 파이썬으로 같은 공식)
GX="$TMP/gx"
mkskill "$GX" a-ko "aa bb cc"; mkskill "$GX" b-ko "aa bb dd"; mkskill "$GX" c-ko "xx xx yy zz"; mkskill "$GX" d-ko "xx yy ww"; mkskill "$GX" e-ko "ff gg"; mkskill "$GX" f-ko "hh ii"
_g=$(bash "$EVAL" --skills-dir "$GX/skills" --queries-dir "$NOQ" --warn-pair 0.01 2>&1)
if printf '%s\n' "$_g" | grep -q '^PAIR-WARN: c-ko ~ d-ko cos=0.488$' && printf '%s\n' "$_g" | grep -q '^PAIR-WARN: a-ko ~ b-ko cos=0.429$' \
   && printf '%s\n' "$_g" | grep -q '^SKILL-ROUTING: skills=6 pairs=15 max=0.488 (c-ko~d-ko) ' && [ "$(printf '%s\n' "$_g" | grep -c '^PAIR-WARN:')" = 2 ]; then
  ok "T1.l 골든 점수 — a~b 0.429 · c~d 0.488(tf 로그·idf·코사인 분모·df 계수) · max=0.488(c-ko~d-ko) · 그 밖의 쌍 0"
else nope "T1.l" "$(printf '%s\n' "$_g" | head -4)"; fi

# T1.m (AC-3·AC-6) 임계 사이 쌍 — g1~g2 cos=0.129(N=8): 기준선 floor 0.15 아래라 --emit-baseline 에 들어가지 않고, 경고 임계 0.20 아래라 기준선에 없는 새 쌍이어도 drift 가 아니다
GY="$TMP/gy"
mkskill "$GY" g1-ko "p1 u1 u2 u3"; mkskill "$GY" g2-ko "p1 v1 v2 v3"
for _i in 1 2 3 4 5 6; do mkskill "$GY" "f${_i}-ko" "fill${_i}a fill${_i}b"; done
_gy=$(bash "$EVAL" --skills-dir "$GY/skills" --queries-dir "$NOQ" --warn-pair 0.01 2>&1)
_gye=$(bash "$EVAL" --skills-dir "$GY/skills" --queries-dir "$NOQ" --emit-baseline 2>/dev/null)
_gyd=$(bash "$EVAL" --skills-dir "$GY/skills" --queries-dir "$NOQ" --baseline "$TMP/base-empty.json" 2>&1)
if printf '%s\n' "$_gy" | grep -q '^PAIR-WARN: g1-ko ~ g2-ko cos=0.129$' && [ "$(printf '%s' "$_gye" | jq -c '.pairs')" = '{}' ] && printf '%s\n' "$_gyd" | grep -q '^DRIFT: 0$'; then
  ok "T1.m 임계 사이 쌍(0.129) — floor 0.15 아래라 기준선 미포함 · 경고 임계 0.20 아래라 새 쌍도 drift 아님"
else nope "T1.m" "gy='$(printf '%s\n' "$_gy" | head -3)' emit='$_gye' drift='$(printf '%s\n' "$_gyd" | grep DRIFT)'"; fi

# T1.n (AC-3) 코퍼스 변화 안정성 — 무관한 skill 이 하나 늘어도 기준선 대비 drift 가 없다(idf 가 N·df 에 의존하나 변동은 +0.05 임계 안)
mkdir -p "$TMP/fx7"; cp -R "$FX/skills" "$TMP/fx7/skills"; mkskill "$TMP/fx7" eta-ko "서버 인증서 갱신 일정을 달력에 등록하고 만료 알림을 보낸다"
bash "$EVAL" --skills-dir "$FX/skills" --queries-dir "$NOQ" --emit-baseline > "$TMP/base-fx.json" 2>/dev/null
_n7=$(bash "$EVAL" --skills-dir "$TMP/fx7/skills" --queries-dir "$NOQ" --baseline "$TMP/base-fx.json" 2>&1)
if printf '%s\n' "$_n7" | grep -q '^SKILL-ROUTING: skills=7 ' && printf '%s\n' "$_n7" | grep -q '^DRIFT: 0$'; then ok "T1.n 무관한 skill 추가(6→7)에도 기준선 대비 DRIFT: 0 — N 변화 안정성"
else nope "T1.n" "$(printf '%s\n' "$_n7" | grep -E 'SKILL-ROUTING|DRIFT')"; fi

# ══ T2: 실 repo (AC-R-1) — warn-first: description 드리프트는 경고만, 기준선 형식·참조 손상과 문서 등재는 실패 ══
BASEF="$PLUGIN/scripts/tests/llm-eval/skill-routing-baseline.json"
nskills=$(ls "$PLUGIN"/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
# T2.a 기준선 계약 — 유효 JSON · version 1 · pairs 값 전부 수 · 키 'a~b'(a<b) 의 두 skill 이 모두 실재(이름 변경·삭제로 낡은 기준선은 실패)
_bad=""
if jq -e '.version == 1 and (.pairs | type) == "object" and all(.pairs[]; type == "number")' "$BASEF" >/dev/null 2>&1; then
  for _k in $(jq -r '.pairs | keys[]' "$BASEF"); do
    _a=${_k%%~*}; _b=${_k##*~}
    { [ "$_a" \< "$_b" ] && [ -f "$PLUGIN/skills/$_a/SKILL.md" ] && [ -f "$PLUGIN/skills/$_b/SKILL.md" ]; } || _bad="$_bad $_k"
  done
else _bad=" (JSON 형식)"; fi
if [ -z "$_bad" ]; then ok "T2.a 커밋된 기준선 계약 — version 1 · pairs 수 · 키 a~b(a<b) 두 skill 실재"; else nope "T2.a" "손상:$_bad"; fi
# T2.b 실 repo 실행 — rc 0 · skills 수 일치 · 질의 라우팅 소비(trigger-queries 6종 — QUERY-ROUTING: pos=N) · DRIFT 판정(warn-first: 드리프트는 경고로만 알린다)
_r=$(bash "$EVAL" 2>&1); _rrc=$?; _dn=$(printf '%s\n' "$_r" | sed -n 's/^DRIFT: \([0-9][0-9]*\)$/\1/p')
if [ "$_rrc" = 0 ] && printf '%s\n' "$_r" | grep -q "^SKILL-ROUTING: skills=$nskills " && [ -n "$_dn" ] && printf '%s\n' "$_r" | grep -qE '^QUERY-ROUTING: pos=[0-9]+ '; then
  if [ "$_dn" = 0 ]; then ok "T2.b 실 repo 실행 — rc 0 · skills=$nskills · DRIFT: 0 (기준선 일치)"
  else ok "T2.b 실 repo 실행 — rc 0 · skills=$nskills · ⚠️ DRIFT: $_dn (warn-first — 기준선 갱신 검토: bash scripts/skill-routing-eval.sh --emit-baseline)"; printf '%s\n' "$_r" | grep '^PAIR-DRIFT' | sed 's/^/    /'; fi
else nope "T2.b" "rc=$_rrc skills=$nskills out=$(printf '%s\n' "$_r" | head -3)"; fi
# T2.c --emit-baseline 출력이 두 번 같고 유효 JSON(결정론) — 커밋된 기준선과 다르면 갱신 권장 경고(warn-first)
_em1=$(bash "$EVAL" --emit-baseline 2>/dev/null); _em2=$(bash "$EVAL" --emit-baseline 2>/dev/null)
if [ -n "$_em1" ] && [ "$_em1" = "$_em2" ] && printf '%s' "$_em1" | jq -e '.version == 1' >/dev/null 2>&1; then
  if [ "$(printf '%s' "$_em1" | jq -S -c .)" = "$(jq -S -c . "$BASEF")" ]; then ok "T2.c --emit-baseline 결정론 · 커밋된 기준선과 동일"
  else ok "T2.c --emit-baseline 결정론 · ⚠️ 커밋된 기준선과 다름(warn-first — 갱신 권장)"; fi
else nope "T2.c" "emit 출력 비결정 또는 형식 오류"; fi
# T2.d 기준선 하한 경계 — 점수가 정확히 하한(0.15)인 planning-ko~specifying-ko 쌍이 emit·커밋된 기준선에 모두 포함(하한 비교 >= 를 > 로 바꾸면 이 쌍이 빠져 실패)
if [ "$(printf '%s' "$_em1" | jq -r '.pairs["planning-ko~specifying-ko"] // "없음"')" = "0.15" ] && [ "$(jq -r '.pairs["planning-ko~specifying-ko"] // "없음"' "$BASEF")" = "0.15" ]; then
  ok "T2.d 기준선 하한 경계 — 점수 정확히 0.15 인 planning-ko~specifying-ko 가 emit·커밋된 기준선에 포함"
else nope "T2.d" "emit='$(printf '%s' "$_em1" | jq -c '.pairs["planning-ko~specifying-ko"]')' base='$(jq -c '.pairs["planning-ko~specifying-ko"]' "$BASEF")'"; fi

finish
