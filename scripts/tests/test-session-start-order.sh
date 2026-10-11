#!/usr/bin/env bash
# SessionStart additionalContext 조립 순서·오프셋 계약 (FID 20260814-sessionstart-payload-order)
# 계약: 행동 지시 블록(anchor·pending·reconcile)이 harness 프리뷰(2048B) 안에서 시작하고,
#       rehydrate 는 메타 본문 뒤 최후미에 온다 (clarify Q1 / AC-6).
#       총량은 인라인 한도(UTF-16 단위 10,000) 아래 — 예산 9,500 가드 (FID 20260911-meta-skill-progressive-disclosure, T-bud.*).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$PLUGIN/hooks/session-start.sh"
LIMIT=1536
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "PASS $1"; }
ng(){ FAIL=$((FAIL+1)); echo "FAIL $1 — $2"; }

# 블록 시작 바이트 오프셋 (없으면 빈 문자열)
offset_of(){ # $1=ctx file  $2=block name
  local ln; ln=$(grep -n "^<$2>" "$1" | head -1 | cut -d: -f1)
  [ -n "$ln" ] || { printf ''; return; }
  if [ "$ln" -eq 1 ]; then printf '0'; else head -n $((ln-1)) "$1" | wc -c | tr -d ' '; fi
}

# 전 블록 발생 샌드박스 구성 후 훅 실행 → ctx 추출
make_ctx(){ # $1=sandbox dir  $2=with_optional(1|0)
  local sb="$1"
  mkdir -p "$sb/.specops"
  if [ "$2" = "1" ]; then
    mkdir -p "$sb/.specops/20260101-probe"
    printf '## 20260101-probe\n- 2026-01-01 00:00 /specify 완료 (spec.md)\n' > "$sb/.specops/session-progress.md"
    printf '{"ts":"x","files":["a.sh"],"prompt":"","type":"fix","fid":""}\n' > "$sb/.specops/pending-capture.jsonl"
    local f
    for f in spec.md acceptance-criteria.md plan.md tasks.md; do echo x > "$sb/.specops/20260101-probe/$f"; done
  fi
  ( cd "$sb" && bash "$HOOK" 2>/dev/null ) > "$sb/out.json"
  jq -r '.hookSpecificOutput.additionalContext' "$sb/out.json" > "$sb/ctx.txt" 2>/dev/null
}

# 오프셋은 **decode 된 additionalContext** 기준으로 잰다. harness 절단이 인코딩 원문
# 기준일 수 있으나, 인코딩 기준 실측(436B)도 상한 대비 여유가 커서 어느 기준이든 계약이 선다.
SB=$(mktemp -d); SB2=""; SB3=""; SB4=""; SB5=""; SB6=""; SB7=""
trap 'rm -rf "$SB" "$SB2" "$SB3" "$SB4" "$SB5" "$SB6" "$SB7"' EXIT
make_ctx "$SB" 1
CTX="$SB/ctx.txt"

o_anchor=$(offset_of "$CTX" specops-ko-anchor)
o_pend=$(offset_of "$CTX" freecomment-pending)
o_recon=$(offset_of "$CTX" session-progress-reconcile)
o_rehy=$(offset_of "$CTX" session-progress-rehydrate)
o_meta=$(offset_of "$CTX" EXTREMELY_IMPORTANT)

# T-ord.a pending 오프셋 상한
if [ -n "$o_pend" ] && [ "$o_pend" -le "$LIMIT" ]; then ok "T-ord.a pending 오프셋 ${o_pend}B <= ${LIMIT}B"
else ng "T-ord.a pending 오프셋 상한" "got='${o_pend:-없음}' limit=$LIMIT"; fi

# T-ord.b reconcile 오프셋 상한
if [ -n "$o_recon" ] && [ "$o_recon" -le "$LIMIT" ]; then ok "T-ord.b reconcile 오프셋 ${o_recon}B <= ${LIMIT}B"
else ng "T-ord.b reconcile 오프셋 상한" "got='${o_recon:-없음}' limit=$LIMIT"; fi

# T-ord.c 상대 순서 anchor < pending < reconcile < meta < rehydrate
if [ -n "$o_anchor" ] && [ -n "$o_pend" ] && [ -n "$o_recon" ] && [ -n "$o_meta" ] && [ -n "$o_rehy" ] \
   && [ "$o_anchor" -lt "$o_pend" ] && [ "$o_pend" -lt "$o_recon" ] \
   && [ "$o_recon" -lt "$o_meta" ] && [ "$o_meta" -lt "$o_rehy" ]; then
  ok "T-ord.c 상대 순서 anchor<pending<reconcile<meta<rehydrate"
else
  ng "T-ord.c 상대 순서" "anchor=$o_anchor pend=$o_pend recon=$o_recon meta=$o_meta rehy=$o_rehy"
fi

# T-ord.d anchor 가 byte 0
if [ "${o_anchor:-x}" = "0" ]; then ok "T-ord.d anchor byte 0"
else ng "T-ord.d anchor byte 0" "got='${o_anchor:-없음}'"; fi

# T-ord.e 조건부 블록 0개 경로 — anchor+meta 만, JSON 유효
SB2=$(mktemp -d); make_ctx "$SB2" 0
c2="$SB2/ctx.txt"
a2=$(offset_of "$c2" specops-ko-anchor); m2=$(offset_of "$c2" EXTREMELY_IMPORTANT)
p2=$(offset_of "$c2" freecomment-pending)
# 조건부 3종 전부 부재여야 한다 — pending 만 보면 reconcile·rehydrate 누출을 놓친다.
r2=$(offset_of "$c2" session-progress-reconcile); h2=$(offset_of "$c2" session-progress-rehydrate)
if jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' "$SB2/out.json" >/dev/null 2>&1 \
   && [ "${a2:-x}" = "0" ] && [ -n "$m2" ] && [ -z "$p2" ] && [ -z "$r2" ] && [ -z "$h2" ]; then
  ok "T-ord.e 조건부 0개 경로 — anchor+meta 만 출력, JSON 유효"
else
  ng "T-ord.e 조건부 0개 경로" "anchor=$a2 meta=$m2 pending=${p2:-없음} recon=${r2:-없음} rehy=${h2:-없음}"
fi


# --- 인라인 예산 계약 (FID 20260911-meta-skill-progressive-disclosure) ----------
# Claude Code 는 훅 출력 1건이 **UTF-16 단위 10,000**(JS length — 바이트·코드포인트 아님)을 넘으면 파일로 빼고
# 선두 2KB 프리뷰만 인라인한다(실측: ASCII 9,990 인라인·10,010 파일행 · 한글 5,000자 인라인 ·
# 이모지 5,100개(코드포인트 5,115 / UTF-16 10,215) 파일행). 넘으면 메타 skill 대부분이 모델에 닿지 않는다
# (실측: specops 주입 235건 전부 파일행). 여기서는 **jq explode** 로 UTF-16 단위를 센다 — 훅의 tr 계산기와
# 다른 경로로 재야 계산기 결함이 같이 숨지 않는다(code-reviewer-ko Suggestion).
u16_of(){ jq '[.hookSpecificOutput.additionalContext | explode[] | if . > 65535 then 2 else 1 end] | add // 0' "$1" 2>/dev/null; }
chars_of(){ LC_ALL=C tr -d '\200-\277' < "$1" | wc -c | tr -d ' '; }   # 원문 파일 크기 가드용(코드포인트)
ctx_j(){ # $1=sandbox — 이미 구성된 샌드박스에서 훅 재실행 → $1/ctxj.txt (jq -j: 끝 개행 없음)
  ( cd "$1" && bash "$HOOK" 2>/dev/null ) > "$1/outj.json"
  jq -j '.hookSpecificOutput.additionalContext' "$1/outj.json" > "$1/ctxj.txt" 2>/dev/null
}

# T-bud.a 조건부 블록 0개 경로는 8,000자 이하 + 메타 SKILL.md 본문 전 행 포함 (AC-1)
#   8,000 은 래칫이다 — 조건부 블록·rehydrate 몫(~1,500자)을 남겨 둔다. 메타가 다시 커지면 여기서 멈춘다.
ctx_j "$SB2"
n_a=$(u16_of "$SB2/outj.json"); miss_a=0
while IFS= read -r l; do
  [ -z "$l" ] && continue
  grep -qF -- "$l" "$SB2/ctxj.txt" || miss_a=$((miss_a+1))
done < "$PLUGIN/skills/using-specops-ko/SKILL.md"
if [ "${n_a:-99999}" -le 8000 ] && [ "$miss_a" -eq 0 ]; then ok "T-bud.a 조건부 0개 ${n_a}자 <= 8000 · 메타 본문 전 행 포함"
else ng "T-bud.a 조건부 0개 총량/메타 전량" "chars=${n_a:-없음} limit=8000 누락행=$miss_a"; fi

# T-pend.a pending 블록이 실재하는 절차 파일 절대경로를 가리킨다 (AC-4 ①)
#   절차 본문은 메타 skill 밖(freework-pending.md)이라, 블록의 경로가 틀리면 자유작업 기록 경로가 끊긴다.
fw_path=$(sed -n 's/^절차: \(.*\) 를 Read 해 따른다\..*/\1/p' "$CTX" | head -1)
case "$fw_path" in
  /*/skills/using-specops-ko/freework-pending.md)
    if [ -f "$fw_path" ]; then ok "T-pend.a pending 블록 → 절차 파일 절대경로 실재"
    else ng "T-pend.a pending 절차 경로" "파일 부재: $fw_path"; fi ;;
  *) ng "T-pend.a pending 절차 경로" "절대경로 아님/미발견: '${fw_path}'" ;;
esac

# T-pend.b pending 블록이 플러그인 루트 절대경로와 치환 지시를 준다 (AC-7)
#   Read 로 읽는 파일은 ${CLAUDE_PLUGIN_ROOT} 가 치환되지 않고, Bash 도구 환경에도 이 변수가 없다(실측 unset).
root_path=$(sed -n 's/.*CLAUDE_PLUGIN_ROOT} 는 \(.*\) 로 바꿔 실행한다\..*/\1/p' "$CTX" | head -1)
case "$root_path" in
  /*) if [ -f "$root_path/scripts/freework-resolve-fid.sh" ]; then ok "T-pend.b pending 블록 → 플러그인 루트 치환 지시 + scripts 실재"
      else ng "T-pend.b 플러그인 루트" "scripts/freework-resolve-fid.sh 부재: $root_path"; fi ;;
  *) ng "T-pend.b 플러그인 루트" "치환 지시/절대경로 미발견: '${root_path}'" ;;
esac

# 전 조건부 블록 샌드박스 — make_ctx(…, 1) 에 미완 batch 1건을 더하고, $2=1 이면 최상단 FID 블록을
#   20,000자 이상으로 부풀린다. 채움 줄에는 단계 표기(/specify 등)를 넣지 않는다 — reconcile 판정을
#   바꾸지 않아야 두 샌드박스의 앞 블록이 같아진다.
mk_full(){ # $1=sandbox  $2=giant(0|1)
  make_ctx "$1" 1
  mkdir -p "$1/.specops/batch-20260828-0900"
  printf '| FR-ID | FID | 설명 | Status |\n|---|---|---|---|\n| FR-1 | 20260101-d1 | d | IMPL_DONE |\n| FR-p1 | TBD | p | PENDING |\n' \
    > "$1/.specops/batch-20260828-0900/queue.md"
  : > "$1/.specops/batch-20260828-0900/ACTIVE"
  if [ "$2" = "1" ]; then
    local i
    for i in $(seq 1 450); do
      printf '  메모 %03d: 가나다라마바사아자차카타파하 세션 기록 누적 확인용 한글 채움 문장입니다\n' "$i"
    done >> "$1/.specops/session-progress.md"
  fi
  ctx_j "$1"
}
SB3=$(mktemp -d); mk_full "$SB3" 1
SB4=$(mktemp -d); mk_full "$SB4" 0
reh_of(){ sed -n '/^<session-progress-rehydrate>/,/^<\/session-progress-rehydrate>/p' "$1"; }
pre_of(){ awk '/^<session-progress-rehydrate>/{ exit } { print }' "$1"; }
OMIT='(이하 생략 — 전체: .specops/session-progress.md)'

# T-bud.b 전 조건부 블록 + 거대 rehydrate 에서도 9,500자 이하 (AC-2)
#   ★ 공허 가드: 픽스처가 정말 전 블록을 냈는지·원문이 20,000자를 넘는지 먼저 확인한다.
n_b=$(u16_of "$SB3/outj.json"); src_b=$(chars_of "$SB3/.specops/session-progress.md")
blocks_b=$(grep -cE '^<(freecomment-pending|session-progress-reconcile|batch-resume|session-progress-rehydrate)>' "$SB3/ctxj.txt")
if [ "$blocks_b" -eq 4 ] && [ "$src_b" -ge 20000 ] && [ "${n_b:-99999}" -le 9500 ] \
   && jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' "$SB3/outj.json" >/dev/null 2>&1; then
  ok "T-bud.b 전 블록+거대 rehydrate(원문 ${src_b}자) → ${n_b}자 <= 9500, JSON 유효"
else
  ng "T-bud.b 거대 rehydrate 예산" "chars=${n_b:-없음} limit=9500 원문=$src_b 블록=$blocks_b/4"
fi

# T-bud.c 절단 시 rehydrate 태그 안 끝에 생략 포인터 + 앞 블록은 절단 없는 경우와 문자 단위 동일 (AC-2 ②③)
if reh_of "$SB3/ctxj.txt" | tail -2 | head -1 | grep -qF -- "$OMIT" \
   && [ "$(pre_of "$SB3/ctxj.txt")" = "$(pre_of "$SB4/ctxj.txt")" ]; then
  ok "T-bud.c 생략 포인터가 rehydrate 끝 + 앞 블록 불변"
else
  ng "T-bud.c 절단 형태" "끝줄='$(reh_of "$SB3/ctxj.txt" | tail -2 | head -1)' 앞블록동일=$([ "$(pre_of "$SB3/ctxj.txt")" = "$(pre_of "$SB4/ctxj.txt")" ] && echo y || echo n)"
fi

# T-bud.d 예산 이내면 rehydrate 무절단 — 포인터 없음 + 최상단 블록 끝 줄 포함 (AC-3)
n_d=$(u16_of "$SB4/outj.json")
if [ "${n_d:-99999}" -le 9500 ] && ! grep -qF -- "$OMIT" "$SB4/ctxj.txt" \
   && reh_of "$SB4/ctxj.txt" | grep -qF -- '/specify 완료 (spec.md)'; then
  ok "T-bud.d 예산 이내(${n_d}자) → rehydrate 무절단"
else
  ng "T-bud.d 무절단" "chars=${n_d:-없음} 포인터=$(grep -cF -- "$OMIT" "$SB4/ctxj.txt")"
fi

# T-bud.e 문자 계산은 locale 무관 — UTF-8 locale 과 C locale 에서 거대 픽스처 출력이 바이트 동일 (AC-3)
#   ${#var} 같은 locale 의존 계산이면 C 에서 바이트로 세어 한글 픽스처의 절단점이 달라진다.
u8=$(locale -a 2>/dev/null | grep -iE '^(en_US|C)\.(utf-?8)$' | head -1)
( cd "$SB3" && LC_ALL=C LANG=C bash "$HOOK" 2>/dev/null ) > "$SB3/out_c.json"
if [ ! -s "$SB3/out_c.json" ]; then
  ng "T-bud.e locale 비교" "C locale 출력이 비었다 — 둘 다 비면 cmp 가 공허 PASS 한다"
elif [ -n "$u8" ]; then
  ( cd "$SB3" && LC_ALL="$u8" LANG="$u8" bash "$HOOK" 2>/dev/null ) > "$SB3/out_u.json"
  if cmp -s "$SB3/out_c.json" "$SB3/out_u.json"; then ok "T-bud.e locale 무관 ($u8 == C)"
  else ng "T-bud.e locale 의존" "$u8 과 C 출력이 다름"; fi
else
  cmp -s "$SB3/out_c.json" "$SB3/outj.json" && ok "T-bud.e locale 무관 (UTF-8 locale 부재 — 기본 == C 비교)" \
    || ng "T-bud.e locale 의존" "기본과 C 출력이 다름"
fi

# T-bud.f progress_block 을 조기 종료 소비자(head·grep -q)로 파이프하지 않는다 (plan-reviewer C-1 — 정적 잠금)
#   set -euo pipefail 하에서 블록이 파이프 버퍼보다 크면 printf 가 SIGPIPE(rc 141)로 죽고 set -e 가 훅을
#   **무출력 종료**시킨다(실측: 병렬 24회 중 2회 JSON 0바이트). 레이스라 동적 테스트로는 결정적으로 못 잡는다.
#   주석 행은 제외한다(설명문의 `progress_block … | head` 오탐 방지 — plan-reviewer 2회차 Minor).
early_pipe=$(grep -nE 'progress_block"?[^|]*\|[[:space:]]*(head|grep[[:space:]]+-[a-zA-Z]*q)' "$HOOK" | grep -vE '^[0-9]+:[[:space:]]*#' || true)
if [ -n "$early_pipe" ]; then
  ng "T-bud.f progress_block 조기 종료 파이프" "$(printf '%s\n' "$early_pipe" | head -1)"
else
  ok "T-bud.f progress_block 조기 종료 파이프 없음 (SIGPIPE 무출력 경로 차단)"
fi

# T-bud.g astral 문자(이모지 — UTF-16 2단위)로 채운 거대 rehydrate 도 UTF-16 9,500 이하 (AC-2 · code-reviewer-ko Important)
#   코드포인트로 세면 이모지 1개를 1로 쳐 예산을 통과시키고 실제 UTF-16 길이는 한도를 넘긴다(리뷰어 프로브:
#   코드포인트 9,463 / UTF-16 10,724). 한글·ASCII 픽스처(T-bud.b)는 전부 BMP 라 두 단위를 가르지 못한다.
SB5=$(mktemp -d); make_ctx "$SB5" 1
e30=$(printf '😀%.0s' $(seq 1 30))
for i in $(seq 1 150); do printf '  %03d %s\n' "$i" "$e30"; done >> "$SB5/.specops/session-progress.md"
ctx_j "$SB5"
n_g=$(u16_of "$SB5/outj.json")
if [ -n "$n_g" ] && [ "$n_g" -le 9500 ] && grep -qF -- "$OMIT" "$SB5/ctxj.txt"; then
  ok "T-bud.g astral rehydrate → UTF-16 ${n_g} <= 9500 + 생략 포인터"
else
  ng "T-bud.g astral rehydrate 예산" "utf16=${n_g:-없음} limit=9500 포인터=$(grep -cF -- "$OMIT" "$SB5/ctxj.txt")"
fi

# T-bud.h 훅 계산기 단독 — astral·CJK Ext-B·국기·JSON 이스케이프 혼합 문자열에서 jq UTF-16 계수와 일치 (Phase C 2/2 Important)
#   T-bud.g 는 astral 이 rehydrate 본문에만 있어 awk 줄 계수 경로만 잠근다. 계산기(_json_decoded_chars)의 4바이트 가산을
#   지워도 head_context 에 astral 이 없으면 T-bud.g 가 통과한다(변이 mutD1 실측) — 계산기를 떼어 직접 단정한다.
fn_h=$(sed -n '/^_json_decoded_chars() {/,/^}/p' "$HOOK")
probe_h=$(printf 'a"b\\c\t😀한𠀀🇰🇷 끝')
esc_h=$(jq -rn --arg s "$probe_h" '$s | tojson | .[1:-1]')
want_h=$(jq -rn --arg s "$probe_h" '[$s | explode[] | if . > 65535 then 2 else 1 end] | add')
got_h=$(bash -c "$fn_h"$'\n''_json_decoded_chars "$1"' _ "$esc_h" 2>/dev/null)
if [ -n "$fn_h" ] && [ -n "$want_h" ] && [ "$got_h" = "$want_h" ]; then
  ok "T-bud.h _json_decoded_chars = jq UTF-16 ($got_h) — astral·이스케이프 혼합"
else
  ng "T-bud.h 계산기 UTF-16 불일치" "hook=${got_h:-없음} jq=${want_h:-없음} 함수추출=$([ -n "$fn_h" ] && echo y || echo n)"
fi

# --- 문서 계약 (AC-5) ---------------------------------------------------------
# 조립 순서는 코드에만 있으면 다음 편집자가 모른다. 순서를 서술하는 문서 3곳이
# 계약을 담고 있는지 함께 잠근다 — 실측 결함의 구조적 원인이 "각 PR 이 자기 블록만
# 보고 누적 순서를 아무도 안 봤다" 였으므로, 순서 계약은 문서에도 남아야 한다.
doc_has(){ # $1=파일  $2=grep 패턴  $3=TEST ID  $4=설명
  if [ -f "$PLUGIN/$1" ] && grep -q "$2" "$PLUGIN/$1"; then ok "$3 $4"
  else ng "$3 $4" "$1 에 '$2' 없음"; fi
}
doc_has CLAUDE.md 'specops-ko-anchor' "T-ord.f" "CLAUDE.md 조립 순서 계약 기재"
doc_has README.md '조립 순서' "T-ord.g" "README.md 조립 순서 요약 기재"
doc_has skills/context-resets-ko/SKILL.md '최후미' "T-ord.h" "context-resets-ko rehydrate 최후미 서술"
doc_has CLAUDE.md '문자 10,000' "T-ord.i" "CLAUDE.md 인라인 한도(문자 10,000) 서술"
doc_has CLAUDE.md 'UTF-16 단위' "T-ord.j" "CLAUDE.md 한도 단위 한정어(UTF-16) — 코드포인트 오해 방지"

# T-bud.i 앞 블록 폭주 — 미완 batch 14개여도 batch-resume 은 상세 3개 + 건수 1줄로 접혀 총량이 9,500 이하다 (20261002-batch-resume-hook-cap)
#   ★ 공허 가드(실행 단언): 같은 픽스처의 직접 실행(상한 없음) 블록이 훅 블록의 2배 이상이어야 한다 — 상한이 실제로 접고 있다는 증거.
SB6=$(mktemp -d); make_ctx "$SB6" 1
for i in $(seq 1 14); do
  b="$SB6/.specops/batch-2026082$((i % 10))-09$(printf %02d "$i")"; mkdir -p "$b"
  printf '| FR-ID | FID | 설명 | Status |\n|---|---|---|---|\n| FR-1 | 20260101-d%s | d | IMPL_DONE |\n| FR-p1 | TBD | p | PENDING |\n' "$i" > "$b/queue.md"
  : > "$b/ACTIVE"
done
for i in $(seq 1 450); do printf '  메모 %03d: 가나다라마바사아자차카타파하 세션 기록 누적 확인용 한글 채움 문장입니다\n' "$i"; done >> "$SB6/.specops/session-progress.md"
ctx_j "$SB6"
n_i=$(u16_of "$SB6/outj.json")
bres_of(){ sed -n '/^<batch-resume>/,/^<\/batch-resume>/p' "$1" | sed '1d;$d'; }   # 블록 본문(태그 제외)
direct_bytes(){ ( cd "$1" && SPECOPS_ROOT="$1/.specops" bash "$PLUGIN/scripts/_internal/batch-resume-check.sh" 2>/dev/null ) | LC_ALL=C wc -c | tr -d ' '; }
hb_i=$(bres_of "$SB6/ctxj.txt" | LC_ALL=C wc -c | tr -d ' '); db_i=$(direct_bytes "$SB6")
if [ "${n_i:-99999}" -le 9500 ] && [ "$(grep -c '미완 batch — batch-' "$SB6/ctxj.txt")" -eq 3 ] && grep -q '외 미완 batch 11개' "$SB6/ctxj.txt" \
   && [ "${hb_i:-0}" -gt 0 ] && [ "${db_i:-0}" -ge $((hb_i * 2)) ]; then
  ok "T-bud.i 미완 batch 14개 → 상세 3 + '외 11개' · ${n_i}자 <= 9500 (공허 가드: 직접 ${db_i}B >= 2×훅 ${hb_i}B)"
else
  ng "T-bud.i batch 폭주 상한" "chars=${n_i:-없음} 상세=$(grep -c '미완 batch — batch-' "$SB6/ctxj.txt")/3 건수줄=$(grep -c '외 미완 batch 11개' "$SB6/ctxj.txt") 직접=${db_i:-없음}B 훅=${hb_i:-없음}B"
fi
rm -rf "$SB6"

# T-bud.j 완료형 batch 3개(전 FR IMPL_DONE + evidence.md 존재 + 게이트 헤더 없음) — 개수(3) 안이어도 총량이 예산 안 (Phase C Critical)
#   완료형 상세는 3줄 + 절대경로 2회(SPECOPS_ROOT="$(pwd)/.specops")라 cwd 깊이에 비례한다. 개수 상한만으로는 실 repo 경로에서
#   총 10,411 / head 10,196 이었다 → 바이트 예산이 2번째부터 접는다. mktemp 기본 경로와 cwd 150자 두 변형을 잰다.
#   ★ 공허 가드(실행 단언): 직접 실행(상한 없음) 블록이 훅 블록의 2배 이상 — 예산이 실제로 접고 있다는 증거.
mk_done3(){ # $1=sandbox — make_ctx(…,1) + 거대 rehydrate + 완료형 batch 3개
  local i b
  make_ctx "$1" 1
  for i in 1 2 3; do
    b="$1/.specops/batch-20260828-090$i"; mkdir -p "$b" "$1/.specops/20260101-e$i"
    printf '| FR-ID | FID | 설명 | Status |\n|---|---|---|---|\n| FR-1 | 20260101-e%s | d | IMPL_DONE |\n' "$i" > "$b/queue.md"
    : > "$b/ACTIVE"; : > "$1/.specops/20260101-e$i/evidence.md"
  done
  for i in $(seq 1 450); do printf '  메모 %03d: 가나다라마바사아자차카타파하 세션 기록 누적 확인용 한글 채움 문장입니다\n' "$i"; done >> "$1/.specops/session-progress.md"
  ctx_j "$1"
}
SB7=$(mktemp -d)
pad_j=$((150 - ${#SB7} - 1)); [ "$pad_j" -ge 1 ] || pad_j=1
deep_j="$SB7/$(printf 'p%.0s' $(seq 1 "$pad_j"))"
# 얕은 변형은 session-start 내부 가드(CTX_BUDGET 9,500)로, 깊은 변형은 실제 harness 한도(UTF-16 10,000)로 단언한다 —
#   깊은 변형은 pending 블록의 플러그인 루트 경로 길이(1자당 +2)에 민감해 9,500 은 clone 위치에 따라 흔들린다(134자 실측 9,650).
for sb_j in "$SB7/s" "$deep_j"; do
  if [ "$sb_j" = "$deep_j" ]; then lim_j=10000; else lim_j=9500; fi
  mkdir -p "$sb_j"; mk_done3 "$sb_j"
  n_j=$(u16_of "$sb_j/outj.json")
  hd_j=$(jq '.hookSpecificOutput.additionalContext | split("\n\n<session-progress-rehydrate>")[0] | [explode[] | if . > 65535 then 2 else 1 end] | add' "$sb_j/outj.json" 2>/dev/null)
  d_j=$(grep -c '미완 batch — batch-' "$sb_j/ctxj.txt")
  hb_j=$(bres_of "$sb_j/ctxj.txt" | LC_ALL=C wc -c | tr -d ' '); db_j=$(direct_bytes "$sb_j")
  if [ "${n_j:-99999}" -le "$lim_j" ] && [ "${hd_j:-99999}" -le "$lim_j" ] && jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' "$sb_j/outj.json" >/dev/null 2>&1 \
     && [ "$d_j" -ge 1 ] && [ "$d_j" -le 2 ] && [ "$(grep -c "외 미완 batch $((3 - d_j))개" "$sb_j/ctxj.txt")" -eq 1 ] \
     && [ "${hb_j:-0}" -gt 0 ] && [ "${db_j:-0}" -ge $((hb_j * 2)) ]; then
    ok "T-bud.j 완료형 3개 cwd ${#sb_j}자 → 상세 ${d_j} + '외 $((3 - d_j))개' · 총 ${n_j} / head ${hd_j} <= ${lim_j} (직접 ${db_j}B >= 2×훅 ${hb_j}B)"
  else
    ng "T-bud.j 완료형 batch 예산 (cwd ${#sb_j}자)" "chars=${n_j:-없음} head=${hd_j:-없음} limit=$lim_j 상세=$d_j 건수줄=$(grep -c '외 미완 batch' "$sb_j/ctxj.txt") 직접=${db_j:-없음}B 훅=${hb_j:-없음}B"
  fi
done
rm -rf "$SB7"

echo "==== Results: PASS=$PASS FAIL=$FAIL ===="
[ "$FAIL" -eq 0 ]
