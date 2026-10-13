#!/usr/bin/env bash
# reuse-metrics.sh — FID 별 변경 규모·복제·재사용 선언 이행을 재서 기록한다 (관측 전용 — 차단·경고 없음)
# Usage: reuse-metrics.sh measure <FID>     # .specops/<FID>/reuse-metrics.json 을 쓴다(재측정 시 덮어씀)
#        reuse-metrics.sh report [경로]      # <경로>/*/reuse-metrics.json 을 FID 별 표로 (기본 .specops)
# rc: 0 = 실행됨(재지 못한 항목은 status 로 말한다 — 0 으로 위장하지 않는다) · 2 = 사용 오류
#
# 항목마다 status 를 갖는다: measured · not_measured(사유) · not_applicable(사유). 값은 measured 일 때만 숫자다.
#   size  — 분기점…작업 트리의 추가·삭제 줄 수를 구현·테스트·문서로 나눠 센다(문서 분류: file-class.sh). 삭제된 파일의 줄도 센다.
#   dup   — 자체 방식(항상 같은 방식이라 FID 간 비교가 된다): 추가된 코드에서 연속 N줄(앞뒤 공백 제거 후 완전 일치)이
#           (a) 추가분 안에서 반복된 줄 수 (b) 분기점 시점의 저장소에 이미 있던 줄 수. (b) 는 같은 diff 에서 **삭제된 줄과 일치하는 창을 뺀다**
#           — 파일 이름 변경·블록 이동·들여쓰기 변경은 복제가 아니다(모듈 추출을 복제로 세면 신호가 거꾸로 나온다).
#   jscpd — jscpd 가 PATH 에 있을 때만 그 수치를 추가로 기록한다(파일 전체·토큰 기반 — dup 과 서로 비교하지 않는다).
#   reuse — check-foundation-reuse.sh --declarations 의 `재사용 foundation` 선언에 적힌 경로·심볼이 추가된 코드에 나오는 건수 / 선언 건수.
# 분기점: .specops/<FID>/review-base.sha 가 있으면 그것(/start-all batch 는 한 브랜치에 FR 여럿 — FR 의 시작점), 없으면 기본 브랜치와의 merge-base.
# 한계: 자체 방식은 이름만 바꾼 복제를 못 잡는다. reuse 는 "선언한 이름이 코드에 나오는가" 라 근사치다(간접 사용은 못 본다).
#       추적하지 않는 새 파일은 대상이 아니다. 임계값 판정은 하지 않는다.
set -u

SPECOPS="${SPECOPS_ROOT:-.specops}"
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FC_SH="$SELF_DIR/_internal/file-class.sh"
REUSE_SH="$SELF_DIR/_internal/check-foundation-reuse.sh"
WINDOW="${SPECOPS_REUSE_DUP_WINDOW:-6}"                        # 연속 줄 수
MAX_FILES="${SPECOPS_REUSE_MAX_FILES:-200}"                    # 변경된 비문서 파일 수 상한 — 넘으면 dup·jscpd·reuse 는 not_measured
MAX_TREE_FILES="${SPECOPS_REUSE_MAX_TREE_FILES:-10000}"        # 분기점 트리의 파일 수 상한 — 넘으면 읽지 않고 (b) 만 not_measured
MAX_TREE_BYTES="${SPECOPS_REUSE_MAX_TREE_BYTES:-209715200}"    # 분기점 트리의 바이트 합 상한(200MB) — 넘으면 읽지 않고 (b) 만 not_measured
MAX_CORPUS_LINES="${SPECOPS_REUSE_MAX_CORPUS_LINES:-150000}"   # 대조 코퍼스 줄 수 상한 — 넘으면 (b) 만 not_measured
case "$WINDOW" in ''|*[!0-9]*|0) WINDOW=6 ;; esac
case "$MAX_FILES" in ''|*[!0-9]*) MAX_FILES=200 ;; esac
case "$MAX_TREE_FILES" in ''|*[!0-9]*) MAX_TREE_FILES=10000 ;; esac
case "$MAX_TREE_BYTES" in ''|*[!0-9]*) MAX_TREE_BYTES=209715200 ;; esac
case "$MAX_CORPUS_LINES" in ''|*[!0-9]*) MAX_CORPUS_LINES=150000 ;; esac

_js() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\t' '  '; }   # JSON 문자열 이스케이프(한 줄)
_num_or_null() { case "${1:-}" in ''|*[!0-9]*) printf 'null' ;; *) printf '%s' "$1" ;; esac; }
_count() { local n; n=$(grep -c "$1" "$2" 2>/dev/null || true); printf '%s' "${n:-0}"; }
# 테스트 경로 판정 — quick-scope.sh 의 qs::is_test 와 같은 규칙이다(그 파일은 source 할 수 없는 구조라 옮겨 적었다 — 바꿀 때 함께 본다).
_is_test_path() {
  case "$1" in tests/*|test/*|__tests__/*|*/tests/*|*/test/*|*/__tests__/*) return 0 ;; esac
  case "${1##*/}" in test_*.py|*_test.*|*.test.*|*.spec.*|test-*.sh) return 0 ;; esac
  return 1
}
# 생성물 — 사람이 쓴 코드가 아니라 변경 규모·복제 계산에서 뺀다(건수는 따로 남긴다).
_is_generated() {
  case "${1##*/}" in package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.lock|poetry.lock|Pipfile.lock|composer.lock|Gemfile.lock|go.sum|*.min.js|*.min.css) return 0 ;; esac
  return 1
}

cmd_measure() {
  local fid="${1:-}"
  printf '%s' "$fid" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || { echo "reuse-metrics: FID 형식 오류: '$fid'" >&2; return 2; }
  [ -d "$SPECOPS/$fid" ] || { echo "reuse-metrics: FID 디렉터리 없음: $SPECOPS/$fid" >&2; return 2; }
  local out="$SPECOPS/$fid/reuse-metrics.json" tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/specops-reuse.XXXXXX") || { echo "reuse-metrics: 임시 디렉터리 생성 실패" >&2; return 0; }
  # shellcheck disable=SC2064   # $tmp 는 지역 변수라 **지금** 확장돼야 한다 (함수가 끝나면 trap 실행 시점에는 값이 없다)
  trap "rm -rf '$tmp'" EXIT
  trap 'exit 143' TERM INT HUP      # 시간 상한(run-bounded.sh 의 TERM)에 끊겨도 위 EXIT 정리가 돌게 한다

  # ── 분기점 ── git 명령은 전부 저장소 루트 기준·경로 인용 없이 돈다(하위 디렉터리에서 불러도, 비ASCII·따옴표 경로여도 같은 결과).
  local ts head="" base="" base_reason="" top="" base_src="" base_out=""
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  top=$(git rev-parse --show-toplevel 2>/dev/null || true)
  _git() { git -C "$top" -c core.quotePath=false "$@"; }
  if [ -n "$top" ]; then
    head=$(_git rev-parse HEAD 2>/dev/null || true)
    local rb="$SPECOPS/$fid/review-base.sha" cand=""
    if [ -s "$rb" ]; then cand=$(tr -d ' \n\r' < "$rb"); _git cat-file -e "${cand}^{commit}" 2>/dev/null && { base="$cand"; base_src="review-base.sha"; }; fi
    if [ -z "$base" ]; then
      local b
      b=$(_git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
      [ -n "$b" ] || { _git show-ref -q --verify refs/heads/main && b=main; }
      [ -n "$b" ] || { _git show-ref -q --verify refs/heads/master && b=master; }
      if [ -n "$b" ]; then base=$(_git merge-base HEAD "$b" 2>/dev/null || true); [ -n "$base" ] && base_src="merge-base($b)"; fi
    fi
    [ -n "$base" ] || base_reason="분기점을 구할 수 없음(review-base.sha·기본 브랜치 origin/HEAD·main·master 부재 또는 공통 조상 없음)"
  else
    base_reason="git 저장소가 아님"
  fi

  # ── size ── numstat -z: 경로를 인용하지 않는다. 삭제된 파일의 줄도 센다(코드 경로 목록에는 지금 있는 파일만 넣는다).
  local size_status=not_measured size_reason="$base_reason" ia="" id_="" ta="" td="" da="" dd="" nfiles="" ngen=""
  : > "$tmp/code.paths"
  if [ -n "$base" ]; then
    local plugin_rc=1
    if [ -f "$FC_SH" ]; then
      # shellcheck source=/dev/null
      . "$FC_SH"
      fc::is_plugin_repo; plugin_rc=$?
    fi
    ia=0; id_=0; ta=0; td=0; da=0; dd=0; nfiles=0; ngen=0
    local a d p expa=0     # expa = 코드 경로 목록에 넣은 파일들의 추가 줄 합(아래 자기 점검의 기대값)
    while IFS=$'\t' read -r -d '' a d p; do
      [ -n "$p" ] || continue
      if _is_generated "$p"; then ngen=$((ngen + 1)); continue; fi
      nfiles=$((nfiles + 1))
      case "$a" in ''|*[!0-9]*) a=0 ;; esac      # 바이너리는 numstat 이 "-" 를 낸다 — 줄 수에 넣지 않는다
      case "$d" in ''|*[!0-9]*) d=0 ;; esac
      if command -v fc::is_doc >/dev/null 2>&1 && fc::is_doc "$p" "$plugin_rc"; then da=$((da + a)); dd=$((dd + d)); continue; fi
      if _is_test_path "$p"; then ta=$((ta + a)); td=$((td + d)); else ia=$((ia + a)); id_=$((id_ + d)); fi
      [ -f "$top/$p" ] && { printf '%s\n' "$p" >> "$tmp/code.paths"; expa=$((expa + a)); }
    done < <(_git diff --no-ext-diff --no-textconv --numstat -z --no-renames "$base" 2>/dev/null)
    size_status=measured; size_reason=""
    # 빈 범위 — 분기점과 HEAD 가 같고 작업 트리 변경도 없으면 "변경 0" 이 아니라 볼 범위가 없는 것이다(기본 브랜치 위·이미 합쳐진 뒤). 0 으로 쓰지 않는다.
    if [ "$base" = "$head" ] && [ "$((nfiles + ngen))" -eq 0 ]; then
      size_status=not_measured; size_reason="변경 범위가 비었음(분기점과 HEAD 가 같고 작업 트리 변경 없음 — 기본 브랜치 위이거나 이미 합쳐진 뒤)"
      base_reason="$size_reason"; base_out="$base"; base=""; ia=""; id_=""; ta=""; td=""; da=""; dd=""; nfiles=""; ngen=""
    fi
  fi

  # ── 추가·삭제된 줄 뽑기 (dup·reuse 공용) ── F=파일 시작 · R=연속 구간 시작 · L<TAB>줄. 추가분은 코드 경로만, 삭제분은 전부.
  local ncode added_ok=0 added_reason="$base_reason"
  ncode=$(_count . "$tmp/code.paths")
  : > "$tmp/added.txt"; : > "$tmp/removed.txt"
  if [ -n "$base" ]; then
    if [ "$ncode" -gt "$MAX_FILES" ]; then
      added_reason="변경된 비문서 파일 ${ncode}개 > 상한 ${MAX_FILES}"
    else
      _git diff --no-ext-diff --no-textconv -U0 --no-color --no-renames --src-prefix=a/ --dst-prefix=b/ "$base" 2>/dev/null | awk -v OUTA="$tmp/added.txt" -v OUTD="$tmp/removed.txt" -v LIST="$tmp/code.paths" '
        BEGIN { while ((getline q < LIST) > 0) want[q] = 1 }
        /^diff --git /  { on = 0; hdr = 1; next }
        hdr && /^\+\+\+ / { f = substr($0, 5); sub(/^b\//, "", f); sub(/\t$/, "", f); on = (f in want); if (on) print "F" > OUTA; print "F" > OUTD; hdr = 0; next }
        hdr             { next }
        /^@@/           { if (on) print "R" > OUTA; print "R" > OUTD; next }
        /^\+/           { if (on) print "L\t" substr($0, 2) > OUTA; next }
        /^-/            { print "L\t" substr($0, 2) > OUTD; next }
      '
      # 자기 점검 — 읽은 추가 줄 수가 변경 규모(numstat)와 다르면 뽑기가 틀린 것이다(예: git 이 인용한 경로). 일부만 읽은 값을 보고하지 않는다.
      local got; got=$(_count '^L' "$tmp/added.txt")
      if [ "$got" -ne "$expa" ]; then
        added_reason="추가된 줄을 다 읽지 못함(변경 규모는 +${expa} 인데 diff 에서 ${got}줄 — 경로 해석 불일치)"
      else
        added_ok=1; added_reason=""
      fi
    fi
  fi

  # ── dup (자체 방식) ──
  local dup_status=not_measured dup_reason="$added_reason" new_lines="" dup_new="" dup_exist="" exist_status=not_measured exist_reason="$added_reason" corpus_files=""
  if [ "$added_ok" = 1 ]; then
    : > "$tmp/corpus.txt"; corpus_files=0
    if [ "$ncode" -eq 0 ]; then
      exist_status=measured; exist_reason=""
    else
      # 분기점 코퍼스 — 변경 파일과 같은 확장자 분류의 추적 파일만. 트리를 디스크에 풀지 않고 blob 을 직접 읽는다
      #   (git archive 는 export-ignore 경로를 조용히 빼고, checkout 계열은 smudge 필터를 돌린다).
      #   ls-tree 한 번으로 상한 판정(파일 수·바이트 합)과 대상 고르기를 함께 한다 — 읽기 **전에** 세어 큰 저장소에서 시간을 쓰지 않는다.
      #   대상: 일반 blob(심볼릭 링크 120000·하위 모듈 제외) · 1MiB 미만 · 확장자 분류(cls)가 변경된 코드 파일의 분류 집합에 드는 것.
      local tree_n tree_b tree_s tree_rc nsel
      _git ls-tree -r -l "$base" > "$tmp/tree.txt" 2>/dev/null; tree_rc=$?
      : > "$tmp/sel.shas"
      tree_s=$(awk -v LIST="$tmp/code.paths" -v SEL="$tmp/sel.shas" '
        function cls(p,   b, n, a) { b = p; sub(/.*\//, "", b); n = split(b, a, "."); return (n < 2 || a[n] == "" || b ~ /^\.[^.]*$/) ? "." : a[n] }
        BEGIN { while ((getline q < LIST) > 0) want[cls(q)] = 1 }
        { n++; if ($4 ~ /^[0-9]+$/) b += $4 }
        $1 != "120000" && $2 == "blob" && $4 ~ /^[0-9]+$/ && $4 + 0 < 1048576 {
          p = substr($0, index($0, "\t") + 1)
          if (p ~ /^".*"$/) p = substr(p, 2, length(p) - 2)      # ls-tree 는 따옴표가 든 경로를 따옴표로 감싼다
          if (cls(p) in want) { print $3 > SEL; s++ }
        }
        END { printf "%d %.0f %d", n, b, s }' "$tmp/tree.txt" 2>/dev/null)
      tree_n=${tree_s%% *}; tree_b=${tree_s#* }; nsel=${tree_b#* }; tree_b=${tree_b%% *}
      case "$tree_n" in ''|*[!0-9]*) tree_n=0 ;; esac; case "$tree_b" in ''|*[!0-9]*) tree_b=0 ;; esac
      case "$nsel" in ''|*[!0-9]*) tree_rc=1 ;; esac      # 집계 awk 가 답을 못 냈다 — 트리를 못 읽은 것과 같이 다룬다
      if [ "$tree_rc" -ne 0 ]; then
        exist_reason="분기점 트리를 읽을 수 없음(git ls-tree 실패)"
      elif [ "$tree_n" -gt "$MAX_TREE_FILES" ]; then
        exist_reason="분기점 트리 ${tree_n}개 파일 > 상한 ${MAX_TREE_FILES}"
      elif [ "$tree_b" -gt "$MAX_TREE_BYTES" ]; then
        exist_reason="분기점 트리 ${tree_b}바이트 > 상한 ${MAX_TREE_BYTES}"
      else
        # 머리표지는 실행마다 다른 값 — 내용 줄과 겹치지 않게. 파이프로 잇지 않고 종료 코드를 따로 받는다.
        local clines mark got_f crc=0
        mark="SPECOPS-REUSE-BLOB-$$-$RANDOM"
        if [ "$nsel" -gt 0 ]; then
          _git cat-file --batch="$mark %(objectname)" < "$tmp/sel.shas" > "$tmp/blobs.raw" 2>/dev/null; crc=$?
          # cat-file --batch 는 blob 마다 내용 뒤에 LF 를 하나 더 붙인다 — 그 빈 줄 하나(머리표지·끝 바로 앞)는 내용이 아니라 버린다.
          #   빈 줄은 잡아 두었다가 뒤에 내용 줄이 오면 그때 낸다(줄 수 상한이 파일의 실제 줄 수를 세게).
          awk -v M="$mark " '
            index($0, M) == 1 { pend = 0; print "F"; next }
            $0 == ""          { if (pend) print "L\t"; pend = 1; next }
                              { if (pend) { print "L\t"; pend = 0 } print "L\t" $0 }' "$tmp/blobs.raw" > "$tmp/corpus.txt" 2>/dev/null
        fi
        # 자기 점검 — 읽은 blob 수가 요청한 수와 다르면 코퍼스가 빈 것·일부인 것이다. 그 위에서 센 0 을 보고하지 않는다.
        got_f=$(_count '^F$' "$tmp/corpus.txt")
        if [ "$crc" -ne 0 ] || [ "$got_f" -ne "$nsel" ]; then
          exist_reason="분기점 코퍼스를 다 읽지 못함(요청 ${nsel}개 중 ${got_f}개 — git cat-file rc=${crc})"; : > "$tmp/corpus.txt"
        else
          corpus_files=$got_f
          clines=$(_count '^L' "$tmp/corpus.txt")
          if [ "$clines" -gt "$MAX_CORPUS_LINES" ]; then exist_reason="대조 코퍼스 ${clines}줄 > 상한 ${MAX_CORPUS_LINES}"; : > "$tmp/corpus.txt"
          else exist_status=measured; exist_reason=""; fi
        fi
      fi
    fi
    # 정규화: 앞뒤 공백 제거, 빈 줄과 2자 이하 줄(괄호·fi 등)은 버린다. 창은 같은 파일·같은 연속 구간 안에서만 만든다.
    local res
    res=$(awk -v N="$WINDOW" -v USE_CORPUS="$([ "$exist_status" = measured ] && echo 1 || echo 0)" -v FC="$tmp/corpus.txt" -v FR="$tmp/removed.txt" '
      function norm(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
      function windows(file, set,   line, s, n, buf, k, j) {      # file 의 모든 N줄 창을 set 에 넣는다
        n = 0
        while ((getline line < file) > 0) {
          if (line == "F" || line == "R") { n = 0; continue }
          s = norm(substr(line, 3)); if (length(s) < 3) continue
          buf[++n] = s
          if (n >= N) { k = buf[n - N + 1]; for (j = n - N + 2; j <= n; j++) k = k "\n" buf[j]; set[k] = 1 }
        }
        close(file)
      }
      BEGIN { windows(FC, corpus); windows(FR, removed) }
      {
        if ($0 == "F" || $0 == "R") { run++; next }
        s = norm(substr($0, 3)); if (length(s) < 3) next
        nl[++n] = s; rid[n] = run
      }
      END {
        for (i = 1; i + N - 1 <= n; i++) {
          if (rid[i] != rid[i + N - 1]) continue
          k = nl[i]; for (j = 1; j < N; j++) k = k "\n" nl[i + j]
          wk[i] = k; cnt[k]++
        }
        for (i = 1; i + N - 1 <= n; i++) {
          if (!(i in wk)) continue
          if (cnt[wk[i]] >= 2) for (j = 0; j < N; j++) mw[i + j] = 1
          # 기존 코드 복제 — 단, 같은 diff 에서 지운 줄과 같은 창은 이동·이름 변경·들여쓰기 변경이라 뺀다
          if (USE_CORPUS == 1 && (wk[i] in corpus) && !(wk[i] in removed)) for (j = 0; j < N; j++) me[i + j] = 1
        }
        a = 0; b = 0; for (i = 1; i <= n; i++) { if (i in mw) a++; if (i in me) b++ }
        printf "%d %d %d\n", n, a, b
      }' "$tmp/added.txt" 2>/dev/null)
    if [ -n "$res" ]; then
      new_lines=${res%% *}; res=${res#* }; dup_new=${res%% *}; dup_exist=${res#* }
      dup_status=measured; dup_reason=""
      [ "$exist_status" = measured ] || dup_exist=""
    else
      dup_reason="복제 계산 실패(awk)"; exist_status=not_measured; exist_reason="$dup_reason"
    fi
  fi

  # ── jscpd (있을 때만, 추가 기록) ──
  local j_status=not_applicable j_reason="jscpd 미설치" j_lines="" j_dup=""
  if command -v jscpd >/dev/null 2>&1; then
    j_status=not_measured
    if [ "$added_ok" != 1 ]; then j_reason="$added_reason"
    elif [ "$ncode" -eq 0 ]; then j_status=measured; j_reason=""; j_lines=0; j_dup=0
    elif ! command -v jq >/dev/null 2>&1; then j_reason="jq 미설치 — jscpd 리포트를 읽을 수 없음"
    else
      local jp=() jq_
      while IFS= read -r jq_; do jp+=("$top/$jq_"); done < "$tmp/code.paths"
      mkdir -p "$tmp/jscpd"
      if jscpd --silent --reporters json --output "$tmp/jscpd" --min-lines "$WINDOW" "${jp[@]}" >/dev/null 2>&1 && [ -f "$tmp/jscpd/jscpd-report.json" ]; then
        j_lines=$(jq -r '.statistics.total.lines // empty' "$tmp/jscpd/jscpd-report.json" 2>/dev/null)
        j_dup=$(jq -r '.statistics.total.duplicatedLines // empty' "$tmp/jscpd/jscpd-report.json" 2>/dev/null)
        case "$j_lines" in ''|*[!0-9]*) j_lines="" ;; esac
        case "$j_dup" in ''|*[!0-9]*) j_dup="" ;; esac
        if [ -n "$j_lines" ] && [ -n "$j_dup" ]; then j_status=measured; j_reason=""; else j_reason="jscpd 리포트에 통계 필드가 없음"; j_lines=""; j_dup=""; fi
      else
        j_reason="jscpd 실행 실패 또는 리포트 부재"
      fi
    fi
  fi

  # ── reuse (선언 대비 실제 등장) ──
  local r_status=not_applicable r_reason="" declared="" fulfilled=""
  local manifest="$SPECOPS/memory/foundation-manifest.md"
  if [ ! -f "$manifest" ]; then r_reason="foundation-manifest 없음(공통부가 없는 프로젝트)"
  elif [ ! -f "$REUSE_SH" ]; then r_status=not_measured; r_reason="check-foundation-reuse.sh 없음"
  else
    local decl
    decl=$(bash "$REUSE_SH" --declarations "$fid" 2>/dev/null || true)
    if [ -z "$decl" ]; then r_reason="재사용 게이트 비발동(§유형=foundation 또는 산출물 부재)"
    elif printf '%s\n' "$decl" | grep -q '^NOMAP|'; then r_status=not_measured; r_reason="태스크 절 번호와 task id 가 어긋나 선언을 대응시킬 수 없음"
    elif [ "$added_ok" != 1 ]; then r_status=not_measured; r_reason="$added_reason"
    else
      declared=0; fulfilled=0
      grep '^L' "$tmp/added.txt" 2>/dev/null | cut -f2- > "$tmp/added.plain"
      local line val tok hit
      while IFS= read -r line; do
        case "$line" in *"|재사용 foundation|"*) ;; *) continue ;; esac
        declared=$((declared + 1)); val=${line#*|재사용 foundation|}; hit=0
        # 근거 토큰: 선언의 백틱 표기 → 없으면 manifest 표에서 선언에 모듈 이름이 나온 행의 백틱 표기
        printf '%s\n' "$val" | grep -oE '`[^`]+`' | tr -d '`' > "$tmp/tok" 2>/dev/null
        if [ ! -s "$tmp/tok" ]; then
          awk -F'|' -v V="$val" 'NF >= 3 { m = $2; gsub(/^[ \t]+|[ \t]+$/, "", m); if (m != "" && m !~ /^-+$/ && index(V, m) > 0) print }' "$manifest" \
            | grep -oE '`[^`]+`' | tr -d '`' > "$tmp/tok" 2>/dev/null
        fi
        # 바늘: 토큰 그대로 · 확장자를 뗀 경로(import 는 확장자를 안 쓴다) · 파일 이름(4자 이상).
        #   **식별자 경계**에서만 맞춘다 — `index` 가 `indexOf` 에, `dates` 가 `updates` 에 맞으면 안 된다.
        while IFS= read -r tok; do
          [ "${#tok}" -ge 3 ] || continue
          if awk -v T="$tok" '
              function isw(c) { return c ~ /[A-Za-z0-9_]/ }
              function has(s, nd,   i, st, b, a, L) {
                L = length(nd); st = 1
                while ((i = index(substr(s, st), nd)) > 0) {
                  i = st + i - 1; b = (i > 1) ? substr(s, i - 1, 1) : ""; a = substr(s, i + L, 1)
                  if (!(b != "" && isw(b) && isw(substr(nd, 1, 1))) && !(a != "" && isw(a) && isw(substr(nd, L, 1)))) return 1
                  st = i + 1
                }
                return 0
              }
              BEGIN {
                n = 0; nd[++n] = T
                p = T; sub(/\.[A-Za-z0-9]+$/, "", p); if (p != T && length(p) >= 3) nd[++n] = p
                b = p; sub(/.*\//, "", b); if (b != p && length(b) >= 4) nd[++n] = b
              }
              { for (k = 1; k <= n; k++) if (has($0, nd[k])) { found = 1; exit } }
              END { exit(found ? 0 : 1) }' "$tmp/added.plain" 2>/dev/null; then hit=1; break; fi
        done < "$tmp/tok"
        fulfilled=$((fulfilled + hit))
      done <<EOF_DECL
$decl
EOF_DECL
      r_status=measured; r_reason=""
    fi
  fi

  # ── 기록 ──
  [ "$exist_status" = measured ] || corpus_files=""      # 재지 못했으면 부가 칸도 숫자로 내지 않는다
  {
    printf '{"schema_version":1,"fid":"%s","ts":"%s","base":%s,"base_source":"%s","head":%s,\n' "$fid" "$ts" \
      "$([ -n "${base_out:-$base}" ] && printf '"%s"' "${base_out:-$base}" || printf null)" "$(_js "$base_src")" "$([ -n "$head" ] && printf '"%s"' "$head" || printf null)"
    printf ' "size":{"status":"%s","reason":"%s","files":%s,"generated_skipped":%s,"impl":{"added":%s,"deleted":%s},"test":{"added":%s,"deleted":%s},"doc":{"added":%s,"deleted":%s}},\n' \
      "$size_status" "$(_js "$size_reason")" "$(_num_or_null "$nfiles")" "$(_num_or_null "$ngen")" "$(_num_or_null "$ia")" "$(_num_or_null "$id_")" \
      "$(_num_or_null "$ta")" "$(_num_or_null "$td")" "$(_num_or_null "$da")" "$(_num_or_null "$dd")"
    printf ' "dup":{"status":"%s","reason":"%s","method":"builtin","window":%s,"new_lines":%s,"dup_within_new":%s,"existing":{"status":"%s","reason":"%s","dup_of_existing":%s,"corpus_files":%s}},\n' \
      "$dup_status" "$(_js "$dup_reason")" "$WINDOW" "$(_num_or_null "$new_lines")" "$(_num_or_null "$dup_new")" \
      "$exist_status" "$(_js "$exist_reason")" "$(_num_or_null "$dup_exist")" "$(_num_or_null "$corpus_files")"
    printf ' "jscpd":{"status":"%s","reason":"%s","lines":%s,"duplicated_lines":%s},\n' "$j_status" "$(_js "$j_reason")" "$(_num_or_null "$j_lines")" "$(_num_or_null "$j_dup")"
    printf ' "reuse":{"status":"%s","reason":"%s","declared":%s,"fulfilled":%s}}\n' "$r_status" "$(_js "$r_reason")" "$(_num_or_null "$declared")" "$(_num_or_null "$fulfilled")"
  } > "$tmp/out.json"
  # cp 가 아니라 리다이렉트로 쓴다 — 대상이 디렉터리면 cp 는 그 안에 복사해 성공으로 끝난다(기록 실패를 못 본다).
  if [ ! -d "$out" ] && cat "$tmp/out.json" > "$out" 2>/dev/null; then echo "REUSE-METRICS: $out"
  else echo "reuse-metrics: 기록 실패 — $out 에 쓸 수 없음" >&2; fi
  return 0
}

cmd_report() {
  local root="${1:-$SPECOPS}"
  command -v jq >/dev/null 2>&1 || { echo "reuse-metrics: jq 미설치 — 표를 만들 수 없음"; return 0; }
  local n=0 miss=0 d f
  for d in "$root"/*/; do
    [ -d "$d" ] || continue
    case "$(basename "$d")" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*) ;; *) continue ;; esac
    if [ -f "$d/reuse-metrics.json" ]; then n=$((n + 1)); else miss=$((miss + 1)); fi
  done
  if [ "$n" -eq 0 ]; then echo "reuse-metrics: 기록 없음 (reuse-metrics.json 0건 · 기록 없는 FID ${miss}개)"; return 0; fi
  printf '%s\n' "FID | 구현 +/- | 테스트 +/- | 새 코드 줄 | 복제(새 코드끼리) | 복제(기존 코드) | jscpd | 재사용 이행"
  printf '%s\n' "--- | --- | --- | --- | --- | --- | --- | ---"
  for f in "$root"/*/reuse-metrics.json; do
    [ -f "$f" ] || continue
    jq -r '
      def st(s; v): if s.status == "measured" then v elif s.status == "not_applicable" then "해당없음" else "미측정(" + (s.reason // "") + ")" end;
      [ .fid,
        st(.size; "+\(.size.impl.added)/-\(.size.impl.deleted)"),
        st(.size; "+\(.size.test.added)/-\(.size.test.deleted)"),
        st(.dup; "\(.dup.new_lines)"),
        st(.dup; "\(.dup.dup_within_new) [builtin]"),
        st(.dup.existing; "\(.dup.existing.dup_of_existing) [builtin]"),
        st(.jscpd; "\(.jscpd.duplicated_lines)/\(.jscpd.lines) [jscpd]"),
        st(.reuse; "\(.reuse.fulfilled)/\(.reuse.declared)")
      ] | join(" | ")' "$f" 2>/dev/null || echo "$(basename "$(dirname "$f")") | (읽을 수 없는 기록)"
  done
  [ "$miss" -eq 0 ] || echo "(기록 없는 FID ${miss}개는 표에 없다)"
  return 0
}

case "${1:-}" in
  measure) shift; cmd_measure "$@"; exit $? ;;
  report)  shift; cmd_report "$@"; exit $? ;;
  *) echo "usage: reuse-metrics.sh measure <FID> | report [.specops 경로]" >&2; exit 2 ;;
esac
