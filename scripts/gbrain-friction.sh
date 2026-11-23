#!/usr/bin/env bash
# gbrain-friction.sh — 마찰 로그 집계 (20260807, 학습 루프 observe→distill 1단계)
# Usage: bash scripts/gbrain-friction.sh [--json]
# Exit: 0 항상 (조회 도구 — 실패로 상위 흐름을 막지 않는다)
# 환경: SPECOPS_ROOT(기본 .specops) · GBRAIN_FRICTION_MIN(증류 후보 임계, 기본 3)
#
# 왜 필요한가:
#   `friction-log.jsonl` 은 `.specops/<FID>/` 마다 따로 쌓인다. 그래서 **아무도 안 읽는다**.
#   실측 20260807: 25개 파일 130행 — 그중 **R-1(commit 전 verify) 89행 = 68%**.
#   한 규칙이 25개 FID 에 걸쳐 89번 울렸는데 그 신호로 바뀐 것이 0이었다.
#   이건 데이터가 없어서가 아니라 **있는데 집계가 없어서**다.
#
# 학습 루프에서의 위치 (observe→distill→reuse→refine 대조):
#   specops 는 observe 만 강했다(learnings 167건 · friction 130행 · freelog).
#   본 스크립트가 distill 의 **첫 단계** — 흩어진 관찰을 반복 패턴으로 묶어 제시한다.
#   임계값 3 은 "3회 이상 반복 → 증류" 기준이다.
#
# 하지 않는 것 (의도적):
#   - 게이트 **자동 생성** — 클래스 B 정적 메타 규칙이 후보 4건 전부 오탐(4/4)으로
#     철회된 전례가 있다. "이게 진짜 결함 패턴인가" 는 의미론이라 정적 판별이 안 된다.
#     증류와 게이트 사이에는 **사람 승인**이 들어간다. 본 도구는 후보 제시까지다.
#   - 로그 수정·삭제 — 읽기 전용 (5원칙 4 주권).
# 미계측 구간 (unmeasured — 20260912-trigger-prefix-unquoted-space):
#   2026-09-11~12 의 `gh pr create` 5건은 R-1/R-2 trigger prefilter 가 **인용 없는 대입값의 공백**
#   (`GH_TOKEN=$(gh auth token --user x) …`)을 불매칭해 차단·감사 **양쪽에서 침묵**했다. 따라서 그
#   5건은 아래 집계에 **행 자체가 없다** — 규칙별 합산표라 "0 으로 보고" 되는 것이 아니라 **부재**다.
#   부재는 무위반이 아니라 **미계측**이다. (주의: 해당 FID 들에 R-2 기록이 아예 없다는 뜻은 아니다 —
#   예컨대 20260912-pretool-src-capture-flaky 에는 머지 후의 라이브 deny 2건이 따로 있다.)
#   대상 FID: 20260911-run-all-parallel · 20260911-posttool-matcher-narrow ·
#            20260911-meta-skill-progressive-disclosure · 20260912-verify-stale-docs-scope ·
#            20260912-pretool-src-capture-flaky
#   소급 friction 기록은 **생성하지 않는다** — 그 시점에 게이트가 발화했다는 거짓 진술이 되기 때문이다
#   (clarify Q1 = ③ 통계에 주석만).
set -u

SPECOPS="${SPECOPS_ROOT:-.specops}"
MIN="${GBRAIN_FRICTION_MIN:-3}"
case "$MIN" in ''|*[!0-9]*) MIN=3 ;; esac
JSON=0
[ "${1:-}" = "--json" ] && JSON=1

# 파일 수집 — 깨진 경로·부재는 조용히 건너뛴다
files=$(find "$SPECOPS" -name 'friction-log.jsonl' -type f 2>/dev/null | sort || true)
# receipt: implement 창 정직 탈출구 사용량 (BYPASS 관성과 대조)
receipt_n=$(find "$SPECOPS" -path '*/receipts/*.json' -type f 2>/dev/null | grep -c . || true)
: "${receipt_n:=0}"

if [ -z "$files" ]; then
  if [ "$JSON" -eq 1 ]; then
    echo '{"total_rows":0,"total_files":0,"rules":[],"candidates":[],"min":'"$MIN"',"bypass_env":{"rows":0,"fids":0},"receipts":{"files":'"$receipt_n"'}}'
  else
    echo "마찰 기록 없음 (friction-log.jsonl 0개)"
    echo ""
    echo "### BYPASS vs receipt"
    echo ""
    echo "| 지표 | 값 |"
    echo "|---|---:|"
    echo "| BYPASS-ENV 행수 | 0 |"
    echo "| BYPASS-ENV FID수 | 0 |"
    echo "| receipt 파일수 | $receipt_n |"
    echo ""
    echo "> BYPASS-ENV ≫ receipt 이면 우회 관성 · receipt ≥ BYPASS 이면 정직 중간커밋 경로 사용 중."
  fi
  exit 0
fi

# 집계 — jq 로 유효 객체만 통과(깨진 행은 fromjson? 로 탈락), awk 로 규칙별 누적.
#   행수와 **FID 수를 분리**한다: 한 FID 에서만 시끄러운 규칙과 전역 패턴은 다른 문제다.
agg=$(
  printf '%s\n' "$files" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    jq -Rr 'fromjson? | objects
      | select(.rule_id != null)
      | [ .rule_id, (.fid // "?"), (.severity // "?"), (.ts // "?"), (.scope_class // "unknown") ] | @tsv' "$f" 2>/dev/null || true
  done | awk -F'\t' '
    {
      r = $1
      rows[r]++
      if (!seen[r SUBSEP $2]++) fids[r]++
      sev[r SUBSEP $3]++
      # `$4 != "?"` 가드: ts 누락 자리채움("?")이 max 를 이기면 안 된다.
      #   awk 문자열 비교는 **로케일 의존**이다 — LC_ALL=C(바이트순)에서 "?"(0x3F) >
      #   "2"(0x32) 라 누락 행이 이겨 `최근` 이 "?" 로 붕괴한다(실측). UTF-8 로케일은
      #   strcoll 이라 구두점이 앞서 붕괴가 **가려진다** — 그래서 로컬에선 안 보이고
      #   C 로케일 환경(CI·훅)에서만 터지는 종류의 결함이다. 자리채움과 max 는 분리한다.
      if ($4 != "?" && $4 > last[r]) last[r] = $4
      sc[r SUBSEP $5]++
      total++
    }
    END {
      for (r in rows) {
        # severity 분포 문자열 (block 우선 표기 — 우선순위 판단의 핵심 축)
        s = ""; b = 0
        for (k in sev) {
          split(k, p, SUBSEP)
          if (p[1] == r) { s = s (s == "" ? "" : " ") p[2] ":" sev[k]; if (p[2] == "block") b = sev[k] }
        }
        # ts 가 비면 **중간 필드 붕괴**가 난다 — bash read 의 IFS 탭은 whitespace 라
        #   빈 필드가 사라져 blocks 가 last 로 밀린다(표에 block 0 오표시).
        #   종전엔 last_ts 가 말단이라 무해했으나 blocks 컬럼 추가로 새로 생긴 경로다.
        #   여기서 "?" 로 채우면 붕괴 자체가 성립하지 않는다.
        lt = (last[r] == "" ? "?" : last[r])
        # 커밋 범위 분류 4버킷. **`unknown` 은 `empty` 와 다른 축**이다(AC-4) —
        #   전자는 분류 불가(구 레코드·git 실패), 후자는 "커밋 범위가 실제로 비었다".
        #   jq 의 `// "unknown"` 이 그 경계를 만들고 여기서 별도 카운터로 유지한다.
        d = sc[r SUBSEP "docs-only"] + 0; c = sc[r SUBSEP "code"] + 0
        e = sc[r SUBSEP "empty"] + 0;     u = sc[r SUBSEP "unknown"] + 0
        # 신규 4열은 **뒤에 붙인다** — 앞 6필드 인덱스가 밀리면 기존 소비부가 전부 깨진다.
        printf "%s\t%d\t%d\t%s\t%s\t%d\t%d\t%d\t%d\t%d\n", r, rows[r], fids[r], s, lt, b, d, c, e, u
      }
      printf "TOTAL\t%d\n", total
    }
  ' | sort -t"$(printf '\t')" -k2,2nr -k1,1
)

total_rows=$(printf '%s\n' "$agg" | awk -F'\t' '$1=="TOTAL"{print $2}')
: "${total_rows:=0}"
rows_only=$(printf '%s\n' "$agg" | grep -v '^TOTAL' || true)
n_files=$(printf '%s\n' "$files" | grep -c . || true)

# BYPASS-ENV 집계 (규칙 표에 없어도 0으로 보고 — 생략 금지)
bypass_rows=$(printf '%s\n' "$rows_only" | awk -F'\t' '$1=="BYPASS-ENV"{print $2; found=1} END{if(!found) print 0}')
bypass_fids=$(printf '%s\n' "$rows_only" | awk -F'\t' '$1=="BYPASS-ENV"{print $3; found=1} END{if(!found) print 0}')
: "${bypass_rows:=0}"; : "${bypass_fids:=0}"

if [ "$JSON" -eq 1 ]; then
  printf '%s\n' "$rows_only" | jq -Rs --argjson min "$MIN" --argjson tr "${total_rows:-0}" --argjson tf "${n_files:-0}" \
    --argjson br "${bypass_rows:-0}" --argjson bf "${bypass_fids:-0}" --argjson rn "${receipt_n:-0}" '
    [ split("\n")[] | select(length > 0) | split("\t")
      | {rule_id: .[0], rows: (.[1]|tonumber), fids: (.[2]|tonumber),
         severity: .[3], last_ts: .[4], blocks: (.[5]|tonumber),
         scope: {"docs-only": (.[6]|tonumber), code: (.[7]|tonumber),
                 empty: (.[8]|tonumber), unknown: (.[9]|tonumber)}} ]
    | {total_rows: $tr, total_files: $tf, min: $min,
       rules: ., candidates: [ .[] | select(.blocks >= $min) ],
       bypass_env: {rows: $br, fids: $bf},
       receipts: {files: $rn}}'
  exit 0
fi

echo "### 마찰 집계 (${total_rows}행 / ${n_files}개 FID 로그)"
echo ""
echo "| 규칙 | 행수 | FID수 | block | docs-only | code | empty | 판정불가 | severity | 최근 |"
echo "|---|---:|---:|---:|---:|---:|---:|---:|---|---|"
# block 을 4번째에 둔다 — 후보 판정의 **직접 근거**라 눈에 먼저 들어와야 하고,
#   앞 3열(규칙·행수·FID수)이 그대로라 기존 어서션(T2·T3)의 그렙이 보존된다.
#   분류 4열은 block 뒤·severity 앞에 넣는다 — 기존 어서션은 전부 4열까지의
#   **접두 그렙**이라 보존되고, 분류는 block 옆에 있어야 함께 읽힌다.
printf '%s\n' "$rows_only" | while IFS=$'\t' read -r r rows fids sev last blocks d c e u; do
  [ -n "$r" ] || continue
  printf '| %s | %5d | %5d | %5d | %5d | %5d | %5d | %5d | %s | %s |\n' \
    "$r" "$rows" "$fids" "${blocks:-0}" "${d:-0}" "${c:-0}" "${e:-0}" "${u:-0}" "$sev" "${last%T*}"
done

# 후보 판정은 **block(차단) 건수**만 본다 — warn 은 posttool 감사 기록이라 성공한
#   커밋에도 붙는다(실측: R-1 warn 66행이 전부 통과한 커밋). 합산하면 설계상 warn 인
#   규칙(R-3·R-4·R-5 — rules.jsonl severity: warn)에게 "게이트를 더 세게 걸까?" 를 묻게 된다.
cand=$(printf '%s\n' "$rows_only" | awk -F'\t' -v m="$MIN" '$6 + 0 >= m')
echo ""
echo "### 증류 후보 (block ${MIN}회 이상)"
echo ""
if [ -z "$cand" ]; then
  echo "- 없음 — **block(차단) ${MIN}회 이상**인 규칙이 없다. warn 은 posttool 감사 기록이라 후보 판정에 세지 않는다(표에는 남는다)."
else
  # 읽기 변수만 늘린다(출력 불변) — 안 늘리면 말단 변수 blocks 에 남은 4필드가
  #   탭 결합돼 들어와 printf %d 가 깨진다.
  printf '%s\n' "$cand" | while IFS=$'\t' read -r r rows fids sev last blocks d c e u; do
    [ -n "$r" ] || continue
    # 판정의 직접 근거인 block 건수를 함께 낸다 — 행수만 보이면 왜 후보인지 알 수 없다.
    printf -- '- **%s** — block %d회 (%d행 / %d FID). ' "$r" "${blocks:-0}" "$rows" "$fids"
    if [ "${fids:-0}" -ge 3 ]; then
      echo "여러 FID 에 걸친 **전역 패턴** — 규칙을 더 세게 걸 문제인지, 워크플로 설계를 바꿀 문제인지 판단 필요."
    else
      echo "특정 FID 편중 — 국소 사정일 수 있다. 원문 확인 후 판단."
    fi
  done
  echo ""
  echo "> 후보는 **제시일 뿐** 자동 조치하지 않는다. 게이트화 여부는 사람이 정한다"
  echo "> (정적 패턴 자동 판별은 클래스 B 메타 규칙에서 4/4 오탐으로 철회된 전례)."
fi

echo ""
echo "### BYPASS vs receipt"
echo ""
echo "| 지표 | 값 |"
echo "|---|---:|"
echo "| BYPASS-ENV 행수 | $bypass_rows |"
echo "| BYPASS-ENV FID수 | $bypass_fids |"
echo "| receipt 파일수 | $receipt_n |"
echo ""
if [ "$bypass_rows" -gt "$receipt_n" ] && [ "$bypass_rows" -ge 3 ]; then
  echo "> **해석:** BYPASS-ENV ≫ receipt — 우회 관성 가능. implement 중간 커밋은 \`record-task-receipt\` 경로를 우선하세요."
elif [ "$receipt_n" -ge "$bypass_rows" ] && [ "$receipt_n" -gt 0 ]; then
  echo "> **해석:** receipt ≥ BYPASS — 정직 중간커밋 경로가 쓰이는 중."
else
  echo "> **해석:** BYPASS-ENV ≫ receipt 이면 우회 관성 · receipt ≥ BYPASS 이면 정직 중간커밋 경로 사용 중."
fi
exit 0
