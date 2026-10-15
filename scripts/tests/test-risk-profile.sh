#!/usr/bin/env bash
# P1 위험 프로파일 limited-live 분류기 (Wave B)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
RP="$PLUGIN/scripts/_internal/risk-profile.sh"

_setup() {  # $1=dir $2=fid
  mkdir -p "$1/.specops/$2" "$1/src" "$1/docs"
  (cd "$1" && git init -q && printf 'base\n' > README.md && git add README.md \
    && git -c user.name=t -c user.email=t@e.com commit -qm init)
}

# T1: docs-only → lite (mode=live + batch-review-skip allowlist)
TD=$(mktemp -d); FID=20260803-rp-lite
_setup "$TD" "$FID"
printf '# note\n' > "$TD/docs/note.md"
(cd "$TD" && git add docs/note.md)
printf '**§유형**: 신규\n' > "$TD/.specops/$FID/spec.md"
out=$(cd "$TD" && bash "$RP" compute "$FID" 2>/dev/null | tail -1)
[ "$out" = "lite" ] && jq -e '.mode=="live" and .reductions_applied==[] and (.reductions_allowed|index("batch-review-skip"))' \
  "$TD/.specops/$FID/risk-profile.json" >/dev/null \
  && ok "T1 docs-only → lite(live+allowlist)" || nope "T1" "out=$out"
rm -rf "$TD"

# T2: 코드 2파일 → standard (live, allowlist 빈 배열)
TD=$(mktemp -d); FID=20260803-rp-std
_setup "$TD" "$FID"
printf 'x\n' > "$TD/src/a.sh"; printf 'y\n' > "$TD/src/b.sh"
(cd "$TD" && git add src)
printf '**§유형**: 신규\n일반 기능\n' > "$TD/.specops/$FID/spec.md"
out=$(cd "$TD" && bash "$RP" compute "$FID" 2>/dev/null | tail -1)
[ "$out" = "standard" ] && jq -e '.mode=="live" and .reductions_allowed==[]' \
  "$TD/.specops/$FID/risk-profile.json" >/dev/null \
  && ok "T2 코드 2파일 → standard(live·빈 allowlist)" || nope "T2" "out=$out"
rm -rf "$TD"

# T3: auth 키워드 1줄 → strict
TD=$(mktemp -d); FID=20260803-rp-auth
_setup "$TD" "$FID"
printf 'x\n' > "$TD/src/rbac.sh"
(cd "$TD" && git add src)
printf '**§유형**: 신규\n인증 RBAC 조건 1줄 변경\n' > "$TD/.specops/$FID/spec.md"
out=$(cd "$TD" && bash "$RP" compute "$FID" 2>/dev/null | tail -1)
[ "$out" = "strict" ] && jq -e '.mode=="live" and .reductions_allowed==[] and (.signals.strict|index("auth"))' \
  "$TD/.specops/$FID/risk-profile.json" >/dev/null \
  && ok "T3 auth → strict(live·빈 allowlist)" || nope "T3" "out=$out"
rm -rf "$TD"

# T4: migration → strict
TD=$(mktemp -d); FID=20260803-rp-mig
_setup "$TD" "$FID"
mkdir -p "$TD/db/migrations"
printf 'ALTER TABLE t ADD c int;\n' > "$TD/db/migrations/001.sql"
(cd "$TD" && git add db)
printf 'migration 적용\n' > "$TD/.specops/$FID/spec.md"
out=$(cd "$TD" && bash "$RP" compute "$FID" 2>/dev/null | tail -1)
[ "$out" = "strict" ] && ok "T4 migration → strict" || nope "T4" "out=$out"
rm -rf "$TD"

# T5: irreversible → strict
TD=$(mktemp -d); FID=20260803-rp-irr
_setup "$TD" "$FID"
printf 'x\n' > "$TD/src/a.sh"; (cd "$TD" && git add src)
cat > "$TD/.specops/$FID/tasks.md" <<'EOF'
# tasks
## 의존 그래프
```yaml
tasks:
  - id: T1
    irreversible: true
    depends_on: []
    outputs: [src/a.sh]
```
EOF
out=$(cd "$TD" && bash "$RP" compute "$FID" 2>/dev/null | tail -1)
[ "$out" = "strict" ] && ok "T5 irreversible → strict" || nope "T5" "out=$out"
rm -rf "$TD"

# T6: parallel batch → strict 아님 (병렬 가능성은 위험이 아니다 — 필드 기록만 유지)
TD=$(mktemp -d); FID=20260803-rp-par
_setup "$TD" "$FID"
printf 'a\n' > "$TD/src/a.sh"; printf 'b\n' > "$TD/src/b.sh"
(cd "$TD" && git add src)
cat > "$TD/.specops/$FID/tasks.md" <<'EOF'
# tasks
## 의존 그래프
```yaml
tasks:
  - id: T1
    depends_on: []
    outputs: [src/a.sh]
  - id: T2
    depends_on: []
    outputs: [src/b.sh]
```
EOF
out=$(cd "$TD" && bash "$RP" compute "$FID" 2>/dev/null | tail -1)
[ "$out" != "strict" ] && jq -e '.signals.parallel_batch==true and (.signals.strict|index("parallel_batch")|not)' \
  "$TD/.specops/$FID/risk-profile.json" >/dev/null \
  && ok "T6 parallel → strict 아님(parallel_batch 기록 유지)" || nope "T6" "out=$out"
rm -rf "$TD"

# T7: floor 상향
TD=$(mktemp -d); FID=20260803-rp-floor
_setup "$TD" "$FID"
printf '# d\n' > "$TD/docs/x.md"; (cd "$TD" && git add docs)
printf 'docs\n' > "$TD/.specops/$FID/spec.md"
out=$(cd "$TD" && bash "$RP" compute "$FID" --floor strict 2>/dev/null | tail -1)
[ "$out" = "strict" ] && jq -e '.computed=="lite" and .effective=="strict"' \
  "$TD/.specops/$FID/risk-profile.json" >/dev/null \
  && ok "T7 floor 상향" || nope "T7" "out=$out"
rm -rf "$TD"

# T8: floor 하향 거부
TD=$(mktemp -d); FID=20260803-rp-down
_setup "$TD" "$FID"
if (cd "$TD" && bash "$RP" compute "$FID" --floor lite >/dev/null 2>&1); then
  nope "T8" "하향 허용됨"
else
  ok "T8 floor 하향 거부"
fi
rm -rf "$TD"

# T9: code→md rename 위장 금지 (--no-renames 정합: delete+add로 코드 삭제 감지)
TD=$(mktemp -d); FID=20260803-rp-rename
_setup "$TD" "$FID"
printf 'code\n' > "$TD/src/tool.sh"
(cd "$TD" && git add src/tool.sh && git -c user.name=t -c user.email=t@e.com commit -qm add)
(cd "$TD" && git mv src/tool.sh docs/tool.md)
printf 'x\n' > "$TD/.specops/$FID/spec.md"
out=$(cd "$TD" && bash "$RP" compute "$FID" 2>/dev/null | tail -1)
# rename decomposes to delete .sh + add .md → not docs-only → standard or strict
[ "$out" != "lite" ] && ok "T9 rename 위장 ≠ lite" || nope "T9" "out=$out"
rm -rf "$TD"

# T10: mixed docs+code → 비-lite
TD=$(mktemp -d); FID=20260803-rp-mix
_setup "$TD" "$FID"
printf 'd\n' > "$TD/docs/a.md"; printf 'c\n' > "$TD/src/a.sh"
(cd "$TD" && git add docs src)
out=$(cd "$TD" && bash "$RP" compute "$FID" 2>/dev/null | tail -1)
[ "$out" != "lite" ] && ok "T10 mixed ≠ lite" || nope "T10" "out=$out"
rm -rf "$TD"

# T11: metrics append
TD=$(mktemp -d); FID=20260803-rp-met
_setup "$TD" "$FID"
printf '# d\n' > "$TD/docs/x.md"; (cd "$TD" && git add docs)
(cd "$TD" && bash "$RP" compute "$FID" >/dev/null)
jq -e '.phase=="risk-profile"' "$TD/.specops/$FID/metrics.jsonl" >/dev/null \
  && ok "T11 metrics phase=risk-profile" || nope "T11" "missing metric"
rm -rf "$TD"

# T12: bad FID
if bash "$RP" compute bad-id >/dev/null 2>&1; then
  nope "T12" "bad fid accepted"
else
  ok "T12 invalid FID 거부"
fi

# T13: §유형=trivial 단독 ≠ lite 강제
TD=$(mktemp -d); FID=20260803-rp-triv
_setup "$TD" "$FID"
printf 'a\n' > "$TD/src/a.sh"; printf 'b\n' > "$TD/src/b.sh"
(cd "$TD" && git add src)
printf '**§유형**: trivial\n' > "$TD/.specops/$FID/spec.md"
out=$(cd "$TD" && bash "$RP" compute "$FID" 2>/dev/null | tail -1)
[ "$out" = "standard" ] && ok "T13 trivial ≠ lite 강제" || nope "T13" "out=$out"
rm -rf "$TD"

# ── §lite × strict 승격 가드 (H1, 20260806) ──────────────────────────────────
# specifying-ko:122·131 의 `★ strict 승격 가드` 는 산문(모델의 키워드 판단)뿐이었다.
# lite 는 clarify·plan 을 이미 건너뛴 뒤라, strict 가 뒤늦게 드러나도 되돌릴 게이트가 없었다.
# compute 가 spec.md 의 `**§lite**: true` 를 **스스로 감지**해 strict 면 rc=3 을 낸다
# (모델이 플래그를 넘겨야 하는 설계면 플래그 생략으로 우회 가능 — self-detect 여야 한다).
# plan.md 가 생기면(승격 완료) 자동 해제 — 영구 차단 방지.
_setup_lite() {  # $1=dir $2=fid $3=spec 본문 추가줄
  _setup "$1" "$2"
  printf 'a\n' > "$1/src/a.sh"; (cd "$1" && git add src)
  { printf '**§유형**: trivial\n'; printf '**§lite**: true\n'; printf '%s\n' "$3"; } \
    > "$1/.specops/$2/spec.md"
}

# T14: §lite + strict 신호 → rc=3 (프로파일은 기록됨 — 판정 자체는 남긴다)
TD=$(mktemp -d); FID=20260806-rp-lite-strict
_setup_lite "$TD" "$FID" '사용자 로그인 jwt 인증을 추가한다.'
(cd "$TD" && bash "$RP" compute "$FID" >/dev/null 2>&1); rc=$?
eff=$(jq -r .effective "$TD/.specops/$FID/risk-profile.json" 2>/dev/null)
[ "$rc" -eq 3 ] && [ "$eff" = "strict" ] \
  && ok "T14 §lite + strict → rc=3 (가드 발화)" || nope "T14" "rc=$rc eff=$eff"
rm -rf "$TD"

# T15: §lite + 비-strict → rc=0 (정상 lite 흐름 무영향 — false-block 없음)
TD=$(mktemp -d); FID=20260806-rp-lite-ok
_setup_lite "$TD" "$FID" 'CSV 줄 수를 세는 CLI 를 만든다.'
(cd "$TD" && bash "$RP" compute "$FID" >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T15 §lite + 비-strict → rc=0" || nope "T15" "rc=$rc"
rm -rf "$TD"

# T16: §lite 아님 + strict → rc=0 (범위 한정 — 일반 strict 는 정상 흐름)
TD=$(mktemp -d); FID=20260806-rp-nolite-strict
_setup "$TD" "$FID"
printf 'a\n' > "$TD/src/a.sh"; (cd "$TD" && git add src)
printf '**§유형**: 신규\n사용자 로그인 jwt 인증을 추가한다.\n' > "$TD/.specops/$FID/spec.md"
(cd "$TD" && bash "$RP" compute "$FID" >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T16 비-lite strict → rc=0 (범위 한정)" || nope "T16" "rc=$rc"
rm -rf "$TD"

# T17: 승격 완료(plan.md 존재) → 가드 자동 해제 (영구 차단 방지)
TD=$(mktemp -d); FID=20260806-rp-lite-promoted
_setup_lite "$TD" "$FID" '사용자 로그인 jwt 인증을 추가한다.'
printf '# plan\n' > "$TD/.specops/$FID/plan.md"
(cd "$TD" && bash "$RP" compute "$FID" >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T17 plan.md 존재 → 가드 해제" || nope "T17" "rc=$rc"
rm -rf "$TD"

# T18: 사용자 주권 override — env + 사유 병기 (모델이 쓸 수 있는 마커 파일 아님)
TD=$(mktemp -d); FID=20260806-rp-lite-override
_setup_lite "$TD" "$FID" '사용자 로그인 jwt 인증을 추가한다.'
(cd "$TD" && SPECOPS_LITE_STRICT_OVERRIDE=1 SPECOPS_LITE_STRICT_REASON='내부 PoC — 인증 목업' \
  bash "$RP" compute "$FID" >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T18 override(env+사유) → rc=0" || nope "T18" "rc=$rc"
rm -rf "$TD"

# T18b: override 인데 사유 없음 → 무효 (무사유 우회 거부 — BYPASS 규약 동형)
TD=$(mktemp -d); FID=20260806-rp-lite-noreason
_setup_lite "$TD" "$FID" '사용자 로그인 jwt 인증을 추가한다.'
(cd "$TD" && SPECOPS_LITE_STRICT_OVERRIDE=1 bash "$RP" compute "$FID" >/dev/null 2>&1); rc=$?
[ "$rc" -eq 3 ] && ok "T18b override 무사유 → 여전히 rc=3" || nope "T18b" "rc=$rc"
rm -rf "$TD"

# T19: --floor strict 로 사용자가 명시 상향한 lite FID → 가드 발화 (의도적 상향 = 승격 강제)
TD=$(mktemp -d); FID=20260806-rp-lite-floor
_setup_lite "$TD" "$FID" 'CSV 줄 수를 세는 CLI 를 만든다.'
(cd "$TD" && bash "$RP" compute "$FID" --floor strict >/dev/null 2>&1); rc=$?
[ "$rc" -eq 3 ] && ok "T19 --floor strict + §lite → rc=3" || nope "T19" "rc=$rc"
rm -rf "$TD"

# T20: spec.md 부재 → fail-open (판정 불가로 차단하지 않는다)
TD=$(mktemp -d); FID=20260806-rp-nospec
_setup "$TD" "$FID"
printf 'a\n' > "$TD/src/a.sh"; (cd "$TD" && git add src)
(cd "$TD" && bash "$RP" compute "$FID" >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T20 spec.md 부재 → fail-open rc=0" || nope "T20" "rc=$rc"
rm -rf "$TD"

# ── 문맥 필터 (20260914-risk-profile-negation-blind) ─────────────────────────
# 신호 판정은 "무엇을 하는가"를 봐야 한다. 부정문·괄호 나열·표 셀·격리 정리는 언급일 뿐이다.
# 하류 105건 중 88건 strict · 가드 발화 8 FID 중 5건 오탐(override·리터럴 삭제로 해소)이 계기.
_rp_case() {  # $1=fid $2=tasks.md 본문 $3=staged 경로(선택) → stdout "<effective> <signals.strict json>"
  local td; td=$(mktemp -d)
  _setup "$td" "$1"
  printf '**§유형**: 신규\n' > "$td/.specops/$1/spec.md"
  printf '%s\n' "$2" > "$td/.specops/$1/tasks.md"
  if [ -n "${3:-}" ]; then
    mkdir -p "$td/$(dirname "$3")"; printf 'x\n' > "$td/$3"; (cd "$td" && git add "$3")
  fi
  (cd "$td" && bash "$RP" compute "$1" >/dev/null 2>&1)
  printf '%s %s\n' "$(jq -r .effective "$td/.specops/$1/risk-profile.json" 2>/dev/null)" \
    "$(jq -c .signals.strict "$td/.specops/$1/risk-profile.json" 2>/dev/null)"
  rm -rf "$td"
}
_has()  { case "$1" in *"\"$2\""*) return 0 ;; *) return 1 ;; esac; }   # $1=_rp_case 결과 $2=신호명
_eff()  { printf '%s' "${1%% *}"; }

# 오탐 — strict 가 아니어야 한다
r=$(_rp_case 20260914-rp-neg-irr '- irreversible: true 대상이 없다')
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" destructive_fs \
  && ok "T21 부정문 irreversible → strict 아님" || nope "T21" "$r"
r=$(_rp_case 20260914-rp-neg-schema '스키마 변경 없음 — ALTER TABLE·DROP TABLE·data-model.md 무관')
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" db_migration \
  && ok "T22 스키마 부재 선언 → strict 아님" || nope "T22" "$r"
r=$(_rp_case 20260914-rp-list '조건부 섹션(RBAC·반응형·접근성)')
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" auth \
  && ok "T23 괄호 나열 → strict 아님" || nope "T23" "$r"
r=$(_rp_case 20260914-rp-trap "trap 'rm -rf \"\$TD\"' EXIT")
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" destructive_fs \
  && ok "T24 격리 정리 rm -rf → strict 아님" || nope "T24" "$r"

# 정탐 대조군 — strict 를 유지해야 한다 (필터가 신호를 통째로 죽이지 않았다는 증거)
r=$(_rp_case 20260914-rp-jwt 'JWT 검증 미들웨어를 추가한다')
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T25 정탐 JWT → strict(auth)" || nope "T25" "$r"
r=$(_rp_case 20260914-rp-rmrf 'rm -rf /var/data')
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T26 정탐 비격리 rm -rf → strict(destructive_fs)" || nope "T26" "$r"
r=$(_rp_case 20260914-rp-mixed 'JWT 검증을 추가한다. 레거시 세션은 없음')
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T27 혼합 문장 → 긍정 문장 신호 유지" || nope "T27" "$r"
r=$(_rp_case 20260914-rp-migpath '' db/migrations/001.sql)
[ "$(_eff "$r")" = "strict" ] && _has "$r" db_migration \
  && ok "T28 migration 경로 → strict(db_migration)" || nope "T28" "$r"

# 표 셀 (clarify Q1) — 셀마다 판정
r=$(_rp_case 20260914-rp-cell-pos '| T1 | JWT 검증 미들웨어 추가 | 레거시 세션 없음 |')
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T29 표 행 — 긍정 셀 신호 유지" || nope "T29" "$r"
#   T30 은 실제 키워드(JWT)를 부정 셀에 둔다 — `인증` 은 원래 키워드가 아니라 필터 없이도 통과했다(판별력 0)
r=$(_rp_case 20260914-rp-cell-neg '| NFR-3 | 보안 | JWT 없음 |')
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" auth \
  && ok "T30 표 행 — 부정 셀 신호 없음" || nope "T30" "$r"

# 부정 표지 과확장 방지 (plan-reviewer 1회차) — 숫자 뒤 `0건`·옵션 `--no-*` 는 부정이 아니다
r=$(_rp_case 20260914-rp-10gun '마이그레이션 10건 적용 ALTER TABLE')
[ "$(_eff "$r")" = "strict" ] && _has "$r" db_migration \
  && ok "T32 '10건' 은 부정 아님 → db_migration 유지" || nope "T32" "$r"
r=$(_rp_case 20260914-rp-noopt 'git diff --no-renames 로 rm -rf 대상 계산')
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T33 '--no-renames' 는 부정 아님 → destructive_fs 유지" || nope "T33" "$r"

# T31: 필터 실패 → 원 코퍼스 + stderr 경고 (clarify Q2 — 조용히 약해지지 않는다)
#   shim 은 필터 awk 프로그램의 `# rp-filter` 마커가 있을 때만 실패한다(그 밖의 awk 는 실물로 위임).
TD=$(mktemp -d); FID=20260914-rp-fallback; SHIM=$(mktemp -d)
_setup "$TD" "$FID"
printf '**§유형**: 신규\n' > "$TD/.specops/$FID/spec.md"
printf '%s\n' '- irreversible: true 대상이 없다' > "$TD/.specops/$FID/tasks.md"
printf '#!/bin/sh\ncase "$*" in *rp-filter*) exit 2 ;; esac\nexec %s "$@"\n' "$(command -v awk)" > "$SHIM/awk"
chmod +x "$SHIM/awk"
out=$(cd "$TD" && PATH="$SHIM:$PATH" bash "$RP" compute "$FID" 2>"$TD/err"); rc=$?
[ "$rc" -eq 0 ] && grep -q 'corpus filter unavailable' "$TD/err" \
  && [ "$(printf '%s\n' "$out" | tail -1)" = "strict" ] \
  && [ "$(printf '%s\n' "$out" | head -1)" = "RISK_PROFILE: computed=strict effective=strict mode=live" ] \
  && ok "T31 필터 실패 → 원 코퍼스 판정 + stderr 경고" || nope "T31" "rc=$rc out=$out"
rm -rf "$TD" "$SHIM"

# ── 문맥 필터 Phase C 수정 (C-1·I-1~I-4) ─────────────────────────────────────
# 구조화 필드 `irreversible: true` 는 주석에 부정 표지가 있어도 파괴 선언이다 (C-1)
r=$(_rp_case 20260914-rp-yaml-cmt "$(printf '```yaml\ntasks:\n  - id: 1\n    irreversible: true   # 되돌릴 수 없음\n    depends_on: []\n```')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T34 YAML irreversible 필드 + 부정 주석 → strict 유지" || nope "T34" "$r"
r=$(_rp_case 20260914-rp-yaml-bare "$(printf 'tasks:\n  - id: 1\n    irreversible: true\n')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T35 YAML irreversible 필드(주석 없음) → strict · T21 산문형과 구분" || nope "T35" "$r"

# SQL `not null` 은 대소문자 무관하게 부정이 아니다 (I-1)
r=$(_rp_case 20260914-rp-notnull 'create table orders (id int not null)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" db_migration \
  && ok "T36 소문자 not null → db_migration 유지" || nope "T36" "$r"

# 격리 변수 면제는 변수명 전체 일치만 — 접두 일치(TD_ROOT·TMPDIR_BACKUP)는 면제 아님 (I-2)
r=$(_rp_case 20260914-rp-tdroot 'rm -rf ${TD_ROOT}/../var/lib/data')
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T37a \${TD_ROOT} 접두 → destructive_fs" || nope "T37a" "$r"
r=$(_rp_case 20260914-rp-tmpbak 'rm -rf "$TMPDIR_BACKUP/prod"')
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T37b \$TMPDIR_BACKUP 접두 → destructive_fs" || nope "T37b" "$r"
r=$(_rp_case 20260914-rp-tdsub 'rm -rf ${TD}/sub')
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" destructive_fs \
  && ok "T37c \${TD}/sub → 격리 면제 유지" || nope "T37c" "$r"

# 마침표 없는 bullet 끝 부정 괄호구는 괄호만 지운다 — 긍정 본문 신호 유지 (I-3)
r=$(_rp_case 20260914-rp-paren-neg '- JWT 인증 미들웨어 추가 (기존 세션 제거 없음)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T38 부정 괄호구 제거 → 본문 auth 유지" || nope "T38" "$r"

# 괄호 제거가 호출 표기 신호를 죽이지 않는다 (split 에 () 금지 — exec\( 무음 사망 방지)
#   입력을 신호 1개씩 분리한다 — 이 단언들을 쓸 때는 signals.strict 에 첫 신호만 남았다(20261008 수정 · T54 가 잠금).
#   아래 주석의 "첫 신호만 기록" 은 그 시절 사정이다. 단독 입력은 그대로 둔다 — 단언이 신호 하나씩을 겨눈다.
r=$(_rp_case 20260914-rp-callexec 'exec(cmd) 로 실행')
[ "$(_eff "$r")" = "strict" ] && _has "$r" external_exec \
  && ok "T39a exec( 신호 보존" || nope "T39a" "$r"
r=$(_rp_case 20260914-rp-callunlink 'fs.unlink(path) 로 정리')
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T39b fs.unlink( 신호 보존" || nope "T39b" "$r"

# 필터가 신호를 전부 지우면 stderr 1줄 (I-4 — 조용히 약해지지 않는다) · strict 면 경고 없음
_rp_err() {  # $1=fid $2=tasks.md 본문 → stdout = compute stderr
  local td; td=$(mktemp -d)
  _setup "$td" "$1"
  printf '**§유형**: 신규\n' > "$td/.specops/$1/spec.md"
  printf '%s\n' "$2" > "$td/.specops/$1/tasks.md"
  (cd "$td" && bash "$RP" compute "$1" 2>&1 >/dev/null)
  rm -rf "$td"
}
e=$(_rp_err 20260914-rp-allgone "$(printf -- '- irreversible: true 대상이 없다\n- DROP TABLE sessions 금지 해제\n')")
[ "$(printf '%s\n' "$e" | grep -c '문맥 필터가 strict 신호를 모두 제외')" -eq 1 ] \
  && ok "T40 전량 제외 → stderr 경고 1줄" || nope "T40" "stderr=$e"
e=$(_rp_err 20260914-rp-nowarn 'JWT 검증 미들웨어를 추가한다')
! printf '%s' "$e" | grep -q '문맥 필터' \
  && ok "T41 strict 판정 → 경고 없음" || nope "T41" "stderr=$e"

# 부정 괄호구 제거는 괄호 안에 `,` `;` `|` 가 없을 때만 — 쉼표로 이어진 긍정 신호를 통째로 지우지 않는다 (C-2)
#   괄호가 남으면 split 이 조각으로 나눠 부정 조각만 뺀다. 신호별 단독 입력(signals_json 첫 신호만 기록 — T39 주석)
r=$(_rp_case 20260914-rp-paren-comma-auth '- 세션 교체 (OAuth 도입, 기존 쿠키 세션 제거 없음)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T42a 쉼표 괄호 안 긍정 OAuth → strict(auth)" || nope "T42a" "$r"
r=$(_rp_case 20260914-rp-paren-comma-rmrf '- 레거시 삭제 (rm -rf /var/lib/app/cache 포함, 백업 없음)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T42b 쉼표 괄호 안 긍정 rm -rf → strict(destructive_fs)" || nope "T42b" "$r"

# 부정 표지를 담은 산문 괄호는 지우지 않고 `(` `)` 를 `|` 경계로 바꾼다 — 괄호 안이 독립 조각 (C-3)
#   괄호 안 부정 조각이 구분자보다 앞이어도 괄호 밖 긍정 신호가 그 조각에 묶이지 않는다. 신호별 단독 입력(T39 주석)
r=$(_rp_case 20260914-rp-c3-auth '- JWT 인증 미들웨어 추가 (기존 세션 제거 없음, 로그 유지)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T43a 괄호 앞 조각 부정 + 괄호 밖 JWT → strict(auth)" || nope "T43a" "$r"
r=$(_rp_case 20260914-rp-c3-rmrf '- rm -rf /opt/app 수행 (백업 없음, 되돌림 불가)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T43b 괄호 앞 조각 부정 + 괄호 밖 rm -rf → strict(destructive_fs)" || nope "T43b" "$r"
r=$(_rp_case 20260914-rp-c3-drop '- DROP TABLE legacy (백업 없음, 확인 완료)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" db_migration \
  && ok "T43c 괄호 앞 조각 부정 + 괄호 밖 DROP TABLE → strict(db_migration)" || nope "T43c" "$r"
# `—` 로만 나뉜 괄호도 부정은 괄호 안에 갇힌다 (M-3)
r=$(_rp_case 20260914-rp-m3-pay '- 결제 모듈 (payment 연동 — 로그 제외)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" payment_pii \
  && ok "T44 — 로만 나뉜 부정 괄호 → strict(payment_pii)" || nope "T44" "$r"
# 탐지 토큰 exec(·unlink( 의 호출 괄호는 경계 치환 대상이 아니다 — exec( 신호 보존 (unlink( 짝은 T49b)
r=$(_rp_case 20260914-rp-call-neg '- 실행 exec(cmd, 셸 금지)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" external_exec \
  && ok "T45 호출 괄호 안 부정어 → exec( 유지(external_exec)" || nope "T45" "$r"
# 줄머리 괄호·한글 인접 괄호도 경계 치환된다
r=$(_rp_case 20260914-rp-head-paren '(기존 없음) JWT 추가')
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T46a 줄머리 부정 괄호 → strict(auth)" || nope "T46a" "$r"
r=$(_rp_case 20260914-rp-hangul-paren '조건부(RBAC 없음) JWT 추가')
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T46b 한글 인접 부정 괄호 → strict(auth)" || nope "T46b" "$r"
# 부정 대조군 — 괄호 밖이 부정이면 여전히 strict 아님
r=$(_rp_case 20260914-rp-neg-ctrl '- JWT 변경 없음 (해당 없음)')
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" auth \
  && ok "T47 괄호 밖 부정 + 부정 괄호 → strict 아님" || nope "T47" "$r"

# 영숫자 직후 산문 부정 괄호도 경계 치환된다 — 가림은 탐지기가 괄호를 요구하는 exec(·unlink( 만 (C-4)
#   신호별 단독 입력(signals_json 첫 신호만 기록 — T39 주석)
r=$(_rp_case 20260914-rp-c4-rbac 'RBAC(없음) JWT 추가')
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T48a 영문 직후 부정 괄호 RBAC( → strict(auth)" || nope "T48a" "$r"
r=$(_rp_case 20260914-rp-c4-mw '- JWT 검증을 middleware(기존 로직 변경 없음)에 추가')
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T48b middleware( 부정 괄호 → strict(auth)" || nope "T48b" "$r"
r=$(_rp_case 20260914-rp-c4-v2 '- rm -rf /opt/app 수행 v2(백업 없음)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T48c 숫자 직후 부정 괄호 v2( → strict(destructive_fs)" || nope "T48c" "$r"
r=$(_rp_case 20260914-rp-c4-drop '- DROP TABLE legacy_v1(백업 없음)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" db_migration \
  && ok "T48d _숫자 직후 부정 괄호 legacy_v1( → strict(db_migration)" || nope "T48d" "$r"
r=$(_rp_case 20260914-rp-c4-cell '| 인증 | JWT(기존 세션 없음) 도입 |')
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T48e 표 셀 JWT( 부정 괄호 → strict(auth)" || nope "T48e" "$r"
# 보존 가드 — unlink( 호출 괄호는 가려진다 (T45 exec( 과 짝)
r=$(_rp_case 20260914-rp-c4-unlink 'unlink(path) 호출 (백업 없음)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T49a unlink( 호출 괄호 보존 → strict(destructive_fs)" || nope "T49a" "$r"
#   호출 괄호 안 부정어 — unlink 가림 줄이 빠지면 여기서 끊긴다 (T49a 는 괄호 안 부정어가 없어 가림 무관)
r=$(_rp_case 20260914-rp-c4-unlink-neg '- 삭제 unlink(path, 백업 금지)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T49b 호출 괄호 안 부정어 → unlink( 유지(destructive_fs)" || nope "T49b" "$r"

# 가림은 탐지기 grep -i 와 같게 대소문자 무시 — EXEC(·Unlink( 도 호출 괄호로 가려진다 (Phase C I-1)
#   신호별 단독 입력(signals_json 첫 신호만 기록 — T39 주석)
r=$(_rp_case 20260914-rp-i1-exec '- 실행 EXEC(cmd, 셸 금지)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" external_exec \
  && ok "T50a 대문자 EXEC( 호출 괄호 안 부정어 → strict(external_exec)" || nope "T50a" "$r"
r=$(_rp_case 20260914-rp-i1-unlink '- 삭제 Unlink(path, 백업 금지)')
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T50b 대소문자 섞인 Unlink( 호출 괄호 안 부정어 → strict(destructive_fs)" || nope "T50b" "$r"
#   가림 표지는 \002 하나 — 입력에 이미 든 \001 이 가림 표지로 오인되지 않는다 (m-1 재노출 가드)
r=$(_rp_case 20260914-rp-i1-ctl1 "$(printf -- '- JWT 추가 (\001없음)')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T50c 입력 제어문자 \\001 + 부정 괄호 → strict(auth) 유지" || nope "T50c" "$r"
#   입력에 이미 든 \002 는 가림 전에 지운다 — `(\002` 가 가림 표지로 소비되어 경계 치환이 빠지지 않는다
r=$(_rp_case 20260914-rp-i1-ctl2 "$(printf -- '- JWT 추가 (\002없음)')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T50d 입력 제어문자 \\002 + 부정 괄호 → strict(auth) 유지" || nope "T50d" "$r"


# T51: ★ 낡은 로컬 main — 기준은 HEAD 에 가장 가까운 ref(origin/main)여야 한다 (20261008 측정 실행에서 발견)
#   로컬 main 이 원격보다 뒤처진 repo 에서 클린 트리(decompose 시점)의 base...HEAD 가 "그동안 원격에 쌓인 모든 변경"을
#   이 FID 의 변경으로 읽었다 — 3줄 수정이 infra(.github/workflows) strict 로 판정돼 lite 가 풀 경로로 승격됐다.
TD=$(mktemp -d); FID=20261008-rp-stale
_setup "$TD" "$FID"
( cd "$TD" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git branch -M main \
  && git checkout -q -b up && mkdir -p .github/workflows && printf 'on: push\n' > .github/workflows/ci.yml \
  && printf 'a\n' > src/a.sh && printf 'b\n' > src/b.sh \
  && git add -A && git -c user.name=t -c user.email=t@e.com commit -qm upstream \
  && git update-ref refs/remotes/origin/main HEAD \
  && git checkout -q -b feat && printf 'z\n' > src/z.sh && git add src/z.sh \
  && git -c user.name=t -c user.email=t@e.com commit -qm feat ) >/dev/null 2>&1
printf '**§유형**: 신규\n일반 기능\n' > "$TD/.specops/$FID/spec.md"
out=$(cd "$TD" && bash "$RP" compute "$FID" 2>/dev/null | tail -1)
[ "$out" != "strict" ] && jq -e '(.signals.strict|index("infra"))==null and .signals.impl_files==1' \
  "$TD/.specops/$FID/risk-profile.json" >/dev/null \
  && ok "T51 ★ 낡은 로컬 main — origin/main 기준으로 이 FID 의 변경 1파일만 본다(infra 오탐 없음)" \
  || nope "T51" "out=$out $(jq -c '.signals' "$TD/.specops/$FID/risk-profile.json" 2>/dev/null)"
# T51b: 원격 추적 ref 가 없으면 종전대로 로컬 main 기준(회귀 없음)
( cd "$TD" && git update-ref -d refs/remotes/origin/main ) >/dev/null 2>&1
out=$(cd "$TD" && bash "$RP" compute "$FID" 2>/dev/null | tail -1)
[ "$out" = "strict" ] && jq -e '.signals.strict|index("infra")' "$TD/.specops/$FID/risk-profile.json" >/dev/null \
  && ok "T51b origin ref 부재 → 로컬 main 기준 유지(infra 신호 그대로)" || nope "T51b" "out=$out"
rm -rf "$TD"

# T52~T58: ★ 설계 문서 "인용" 과 "변경" 의 구분 (20261008 lite 점검에서 발견)
#   specifying-ko 는 spec §참조에 `.specops/memory/api-spec.md`·`data-model.md` 경로를 자동 인용한다. 그 경로 문자열이
#   public_api·db_migration 신호로 읽혀, 설계 문서가 있는 프로젝트의 모든 FID 가 strict 였다 — "(변경 없음)" 이라 적어도
#   그랬다(실기록: 인용한 FID 67건 전부 strict). lite 는 매번 LITE-STRICT-GUARD 에 걸렸다.
#   이제 git 이 추적하는 문서는 §참조 인용 글머리표의 경로 토큰만 가리고, 바꿨는지는 변경 파일·tasks 로 판정한다.
_rp_doc_case() {  # $1=fid $2=spec 본문 $3=tasks 본문('' 가능) $4=문서 상태 → stdout "<rc> <effective> <signals.strict json>" · stderr 는 $RP_DOC_ERR
  local td rc=0; td=$(mktemp -d)
  _setup "$td" "$1"
  ( cd "$td" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && mkdir -p .specops/memory \
    && printf '# api\n' > .specops/memory/api-spec.md && printf '# dm\n' > .specops/memory/data-model.md
    case "$4" in
      untracked) ;;
      *) git add .specops/memory && git -c user.name=t -c user.email=t@e.com commit -qm docs ;;
    esac
    case "$4" in
      dirty)  printf 'x\n' >> .specops/memory/data-model.md ;;
      staged) printf 'x\n' >> .specops/memory/data-model.md && git add .specops/memory/data-model.md ;;
      committed-dirty-other)
        git branch -M main && git checkout -q -b feat && printf 'x\n' >> .specops/memory/data-model.md \
          && git add .specops/memory/data-model.md && git -c user.name=t -c user.email=t@e.com commit -qm schema \
          && printf 'y\n' >> README.md ;;
    esac ) >/dev/null 2>&1
  printf '%s\n' "$2" > "$td/.specops/$1/spec.md"
  [ -n "$3" ] && printf '%s\n' "$3" > "$td/.specops/$1/tasks.md"
  RP_DOC_ERR=$(cd "$td" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && bash "$RP" compute "$1" 2>&1 >/dev/null) || rc=$?
  printf '%s %s %s\n' "$rc" "$(jq -r .effective "$td/.specops/$1/risk-profile.json" 2>/dev/null)" \
    "$(jq -c .signals.strict "$td/.specops/$1/risk-profile.json" 2>/dev/null)"
  RP_DOC_JSON=$(cat "$td/.specops/$1/risk-profile.json" 2>/dev/null)
  rm -rf "$td"
}
_doc_run() { _rp_doc_case "$@" > "$_DOC_OUT"; r=$(cat "$_DOC_OUT"); }   # 서브셸 없이 호출해 RP_DOC_ERR·RP_DOC_JSON 을 남긴다
_DOC_OUT=$(mktemp)
_LITE_HEAD='# 스펙
**§유형**: trivial
**§lite**: true
## 1. 개요
저장 버튼 문구를 바꾼다.'
_CITE='## 10. 참조
- 헌법 준수 — `.specops/memory/constitution.md`
- IF 설계서 — `.specops/memory/api-spec.md`
- 테이블 설계서 — `.specops/memory/data-model.md`'

# 오탐 — 인용만 있으면 strict 가 아니다
_doc_run 20261008-rp-cite-bare "$_LITE_HEAD
$_CITE" '' tracked
[ "${r%% *}" = 0 ] && case "$r" in *strict*|*public_api*|*db_migration*) false ;; *) true ;; esac \
  && ok "T52a ★ §참조 인용뿐인 lite → strict 아님 · LITE-STRICT-GUARD 미발동" || nope "T52a" "$r"
! printf '%s' "$RP_DOC_ERR" | grep -q '문맥 필터' \
  && ok "T52b 인용 가림은 '--floor strict' 를 권하는 필터 경고를 내지 않는다" || nope "T52b" "stderr=$RP_DOC_ERR"
_doc_run 20261008-rp-cite-note "$_LITE_HEAD
## 참조
- IF 설계서 — \`.specops/memory/api-spec.md\` (**무변경** — 신규 엔드포인트 없음)
- 테이블 설계서 — \`.specops/memory/data-model.md\` (FR-19 가 이 테이블을 읽는다)" '' tracked
[ "${r%% *}" = 0 ] && case "$r" in *strict*) false ;; *) true ;; esac \
  && ok "T52c 주석이 붙은 인용(무변경·읽기) → strict 아님" || nope "T52c" "$r"

# 보존 — 실제 변경 신호는 살아남는다
_doc_run 20261008-rp-cite-api "$_LITE_HEAD
## 참조
- IF 설계서 — \`.specops/memory/api-spec.md\` §1 (\`/api/credentials\` 신설)" '' tracked
[ "${r%% *}" = 3 ] && _has "$r" public_api \
  && ok "T53a 인용 줄의 나머지 글(/api/ 경로)은 그대로 판정 → public_api" || nope "T53a" "$r"
_doc_run 20261008-rp-cite-tasks "$_LITE_HEAD
$_CITE" '- Modify: `.specops/memory/data-model.md:166-167`' tracked
[ "${r%% *}" = 3 ] && _has "$r" db_migration \
  && ok "T53b tasks 의 Modify: data-model.md → db_migration 유지" || nope "T53b" "$r"
_doc_run 20261008-rp-cite-dirty "$_LITE_HEAD
$_CITE" '' dirty
[ "${r%% *}" = 3 ] && _has "$r" db_migration \
  && ok "T53c 추적 문서를 실제로 고침(미스테이지) → db_migration 유지" || nope "T53c" "$r"
_doc_run 20261008-rp-cite-staged "$_LITE_HEAD
$_CITE" '' staged
[ "${r%% *}" = 3 ] && _has "$r" db_migration \
  && ok "T53d 추적 문서를 실제로 고침(스테이지) → db_migration 유지" || nope "T53d" "$r"
_doc_run 20261008-rp-cite-marker "$_LITE_HEAD
**인터페이스 반영**: \`.specops/memory/data-model.md\` §10.2 locator (Phase 2.5-B)
$_CITE" '' tracked
[ "${r%% *}" = 3 ] && _has "$r" db_migration \
  && ok "T53e §참조 밖의 '인터페이스 반영' 줄 → db_migration 유지" || nope "T53e" "$r"
_doc_run 20261008-rp-cite-scope "$_LITE_HEAD
## 2. 범위
- \`.specops/memory/data-model.md\` 의 orders 표에 컬럼을 더한다
$_CITE" '' tracked
[ "${r%% *}" = 3 ] && _has "$r" db_migration \
  && ok "T53i §참조 밖 글머리표(범위 절)의 문서 경로 → db_migration 유지" || nope "T53i" "$r"
_doc_run 20261008-rp-cite-para "$_LITE_HEAD
## 참조
\`.specops/memory/data-model.md\` 의 orders 표를 이번에 손본다" '' tracked
[ "${r%% *}" = 3 ] && _has "$r" db_migration \
  && ok "T53j §참조 안이라도 글머리표가 아닌 문장은 가리지 않는다 → db_migration 유지" || nope "T53j" "$r"
_doc_run 20261008-rp-cite-sect "$_LITE_HEAD
## §7. 참조
- 테이블 설계서 — \`.specops/memory/data-model.md\`" '' tracked
[ "${r%% *}" = 0 ] && case "$r" in *strict*) false ;; *) true ;; esac \
  && ok "T52d '§7. 참조' 제목도 §참조다 → strict 아님" || nope "T52d" "$r"
_doc_run 20261008-rp-cite-fkhead "$_LITE_HEAD
### 3. 참조 무결성 변경
- \`.specops/memory/data-model.md\` 의 orders.user_id 를 users.id 에 FK 로 건다" '' tracked
[ "${r%% *}" = 3 ] && _has "$r" db_migration \
  && ok "T53k 제목에 '참조' 가 들었을 뿐인 절(참조 무결성)은 §참조가 아니다 → db_migration 유지" || nope "T53k" "$r"
_doc_run 20261008-rp-cite-new "$_LITE_HEAD
## 참조
- 테이블 설계서 — \`.specops/memory/data-model.md\` (orders 표 신설)" '' tracked
[ "${r%% *}" = 3 ] && _has "$r" db_migration \
  && ok "T53l '신설' 을 말하는 인용 줄은 가리지 않는다 → db_migration 유지" || nope "T53l" "$r"
_doc_run 20261008-rp-cite-kept "$_LITE_HEAD
## 참조
- IF 설계서 — \`.specops/memory/api-spec.md\` (**Step 5.6 에서 \`SmartMoney\` 갱신**)" '' tracked
[ "${r%% *}" = 3 ] && _has "$r" public_api \
  && ok "T53f 갱신을 말하는 인용 줄은 가리지 않는다 → public_api 유지" || nope "T53f" "$r"
_doc_run 20261008-rp-cite-untracked "$_LITE_HEAD
$_CITE" '' untracked
[ "${r%% *}" = 3 ] && case "$r" in *strict*) true ;; *) false ;; esac \
  && ok "T53g git 이 추적하지 않는 문서 → 종전대로 인용도 신호(변경 여부를 알 수 없다)" || nope "T53g" "$r"
_doc_run 20261008-rp-cite-union "$_LITE_HEAD
$_CITE" '' committed-dirty-other
[ "${r%% *}" = 3 ] && _has "$r" db_migration \
  && ok "T53h 문서 변경은 커밋됐고 다른 파일이 더럽다 → 브랜치 변경도 함께 본다(db_migration 유지)" || nope "T53h" "$r"

# T54: signals.strict 는 신호를 전부 기록한다 (종전: 공백 구분 한 줄의 첫 신호만)
_doc_run 20261008-rp-multi '**§유형**: 신규
JWT 검증을 추가하고 DROP TABLE legacy 를 수행한다' '' untracked
_has "$r" auth && _has "$r" db_migration \
  && ok "T54 다중 신호 → signals.strict 에 전부 기록" || nope "T54" "$r"

# T55: LITE-STRICT-GUARD override 사유는 risk-profile.json 에 남는다 (종전: '사유 기록됨' 이라 출력만 하고 미저장)
TD=$(mktemp -d); FID=20261008-rp-ovr
_setup "$TD" "$FID"
printf '**§유형**: trivial\n**§lite**: true\nJWT 검증 문구 수정\n' > "$TD/.specops/$FID/spec.md"
e=$(cd "$TD" && SPECOPS_LITE_STRICT_OVERRIDE=1 SPECOPS_LITE_STRICT_REASON='오탐 — 주석의 JWT 언급' bash "$RP" compute "$FID" 2>&1 >/dev/null); rc=$?
[ "$rc" = 0 ] && [ "$(jq -r '.lite_strict_override.reason // empty' "$TD/.specops/$FID/risk-profile.json")" = '오탐 — 주석의 JWT 언급' ] \
  && printf '%s' "$e" | grep -q '사유 기록됨' \
  && ok "T55 override 사유 → risk-profile.json lite_strict_override.reason" \
  || nope "T55" "rc=$rc $(jq -c '.lite_strict_override' "$TD/.specops/$FID/risk-profile.json" 2>/dev/null) err=$e"
rm -rf "$TD"

# T56: 부정 수량 `0개` 도 `0건` 과 같이 부정 조각이다
r=$(_rp_case 20261008-rp-zero-gae '해당 없음 — read-only 도구다. `irreversible: true` 노드 0개. 롤백은 git revert 1회.')
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" destructive_fs \
  && ok "T56 'irreversible: true 노드 0개' → strict 아님" || nope "T56" "$r"
r=$(_rp_case 20261008-rp-zero-gaeseon 'JWT 모듈 v2.0개선 작업')
[ "$(_eff "$r")" = "strict" ] && _has "$r" auth \
  && ok "T56c '2.0개선' 은 부정 수량이 아니다 → strict(auth) 유지" || nope "T56c" "$r"
r=$(_rp_case 20261008-rp-ten-gae '- irreversible: true 노드 10개')
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T56b '10개' 는 부정이 아니다 → strict 유지" || nope "T56b" "$r"

# T57: 유지보수 lite 의 가드 메시지는 mini 분석이 남는다는 점과 /maintain 재진입을 알린다
_doc_run 20261008-rp-maint-msg '**§유형**: 유지보수
**§lite**: true
JWT 만료 처리 수정' '' untracked
[ "${r%% *}" = 3 ] && printf '%s' "$RP_DOC_ERR" | grep -q '/maintain' \
  && ok "T57 유지보수 lite 가드 메시지 → /maintain 재진입 안내" || nope "T57" "rc=${r%% *} err=$RP_DOC_ERR"
rm -f "$_DOC_OUT"

# T58: ★ 테스트 샌드박스 정리 — 같은 코드 구간에서 mktemp 로 만든 변수만 지우는 rm -rf 는 신호가 아니다
#   종전 면제는 변수 이름이 $TD·$TMP·$TMPDIR 일 때뿐이라, tasks.md 의 TDD 스텝에 실린 테스트 코드
#   `T=$(mktemp -d)` … `rm -rf "$T"` 가 destructive_fs 로 잡혔다(실기록: §lite 가드 발동 9건 중 6건이 이 형태 · 8건이 override).
#   이름이 아니라 **출처**로 판정한다 — 같은 구간(코드펜스·제목 사이)에서 mktemp 로 대입된 변수여야 한다.
_fence() { printf '%s\n' '```bash' "$@" '```'; }
r=$(_rp_case 20261008-rp-sb-basic "$(_fence 'T=$(mktemp -d)' 'printf x > "$T/a"' 'rm -rf "$T"')")
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" destructive_fs \
  && ok "T58a ★ mktemp 로 만든 \$T 의 rm -rf → strict 아님" || nope "T58a" "$r"
r=$(_rp_case 20261008-rp-sb-multi "$(_fence '_d=$(mktemp -d); _d2="$(mktemp -d)"' 'rm -rf "$_d" "${_d2}/sub"')")
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" destructive_fs \
  && ok "T58b 대상 여러 개·따옴표·\${}·하위 경로 → strict 아님" || nope "T58b" "$r"
r=$(_rp_case 20261008-rp-sb-semi "$(_fence 'W=$(mktemp -d)' 'rm -rf "$W/scripts"; cp -R scripts "$W/scripts"')")
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" destructive_fs \
  && ok "T58c 같은 줄 뒤 명령(;)이 있어도 대상만 본다 → strict 아님" || nope "T58c" "$r"
e=$(_rp_err 20261008-rp-sb-quiet "$(_fence 'T=$(mktemp -d)' 'rm -rf "$T"')")
! printf '%s' "$e" | grep -q '문맥 필터' \
  && ok "T58d 출처가 확인된 정리는 필터 경고(--floor strict 권유)를 내지 않는다" || nope "T58d" "stderr=$e"
# 보존 — 출처를 모르면 그대로 신호다
r=$(_rp_case 20261008-rp-sb-noprov "$(_fence 'rm -rf "$T"')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58e mktemp 대입이 없는 변수 → destructive_fs 유지" || nope "T58e" "$r"
r=$(_rp_case 20261008-rp-sb-otherblock "$(_fence 'T=$(mktemp -d)'; printf '\n본문\n\n'; _fence 'rm -rf "$T"')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58f 대입이 다른 코드 구간에 있다 → destructive_fs 유지" || nope "T58f" "$r"
r=$(_rp_case 20261008-rp-sb-mixed "$(_fence 'T=$(mktemp -d)' 'rm -rf "$T" "$HOME/cache"')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58g 대상 중 하나라도 샌드박스 밖 → destructive_fs 유지" || nope "T58g" "$r"
r=$(_rp_case 20261008-rp-sb-dotdot "$(_fence 'T=$(mktemp -d)' 'rm -rf "$T/../other"')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58h 하위 경로에 .. → destructive_fs 유지" || nope "T58h" "$r"
r=$(_rp_case 20261008-rp-sb-reassign "$(_fence 'T=$(mktemp -d)' 'T=/var/lib/app' 'rm -rf "$T"')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58i mktemp 뒤 다른 값으로 재대입 → destructive_fs 유지" || nope "T58i" "$r"
r=$(_rp_case 20261008-rp-sb-literal "$(_fence 'T=$(mktemp -d)' 'rm -rf /opt/app')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58j 리터럴 경로 → destructive_fs 유지" || nope "T58j" "$r"
r=$(_rp_case 20261008-rp-sb-other "$(_fence 'T=$(mktemp -d)' 'rm -rf "$T" && psql -c "DROP TABLE legacy"')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" db_migration && ! _has "$r" destructive_fs \
  && ok "T58k 같은 줄의 다른 신호(DROP TABLE)는 그대로 → db_migration 유지" || nope "T58k" "$r"
r=$(_rp_case 20261008-rp-sb-two "$(_fence 'T=$(mktemp -d)' 'rm -rf "$T"; rm -rf "$DEPLOY_ROOT"')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58l 같은 줄의 두 번째 rm -rf 가 샌드박스 밖 → destructive_fs 유지" || nope "T58l" "$r"
r=$(_rp_case 20261008-rp-sb-lit2 "$(_fence 'T=$(mktemp -d)' 'rm -rf "$T" /opt/app')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58m 샌드박스 변수 + 리터럴 경로가 섞임 → destructive_fs 유지" || nope "T58m" "$r"
#   코드 안의 `# 주석` 줄은 마크다운 제목이 아니다 — 구간을 끊지 않는다(실기록 3건이 대입과 정리 사이에 주석 줄이 있었다)
r=$(_rp_case 20261008-rp-sb-comment "$(_fence '_d=$(mktemp -d)' '# M6 — 원자 교체 확인' 'run_case "$_d"' 'rm -rf "$_d"')")
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" destructive_fs \
  && ok "T58n 코드펜스 안 주석 줄은 구간 경계가 아니다 → strict 아님" || nope "T58n" "$r"
#   출처 판정의 구멍 (리뷰 M-2 — 전부 실행으로 확인된 입력)
r=$(_rp_case 20261008-rp-sb-cmt-assign "$(_fence '# 테스트에서는 DATA_DIR=$(mktemp -d) 로 바꿔 쓴다' 'rm -rf "$DATA_DIR"')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58p 주석 줄의 대입은 출처가 아니다 → destructive_fs 유지" || nope "T58p" "$r"
r=$(_rp_case 20261008-rp-sb-prefix "$(_fence 'D=$(mktemp_backup_dir /var/lib/app)' 'rm -rf "$D"')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58q mktemp_* 접두 일치는 출처가 아니다 → destructive_fs 유지" || nope "T58q" "$r"
r=$(_rp_case 20261008-rp-sb-for "$(_fence 'T=$(mktemp -d)' 'for T in /var/lib/app /opt/data; do rm -rf "$T"; done')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58r for 루프가 변수를 다시 묶는다 → destructive_fs 유지" || nope "T58r" "$r"
r=$(_rp_case 20261008-rp-sb-read "$(_fence 'T=$(mktemp -d)' 'read -r T < target.txt' 'rm -rf "$T"')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58s read 가 변수를 다시 묶는다 → destructive_fs 유지" || nope "T58s" "$r"
r=$(_rp_case 20261008-rp-sb-append "$(_fence 'T=$(mktemp -d)' 'T+=/../..' 'rm -rf "$T"')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58t += 로 값이 바뀐다 → destructive_fs 유지" || nope "T58t" "$r"
r=$(_rp_case 20261008-rp-sb-subvar "$(_fence 'T=$(mktemp -d)' 'rm -rf "$T/$SUB"')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58u 하위 경로에 다른 변수 → destructive_fs 유지" || nope "T58u" "$r"
r=$(_rp_case 20261008-rp-sb-tilde "$(printf '%s\n' '~~~bash' 'T=$(mktemp -d)' '~~~' '' '~~~bash' 'rm -rf "$T"' '~~~')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58v ~~~ 펜스도 구간 경계다 → destructive_fs 유지" || nope "T58v" "$r"
r=$(_rp_case 20261008-rp-sb-forother "$(_fence 'T=$(mktemp -d)' 'for f in a b; do touch "$T/$f"; done' 'rm -rf "$T"')")
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" destructive_fs \
  && ok "T58w 다른 변수를 도는 for 는 출처를 끊지 않는다 → strict 아님" || nope "T58w" "$r"
r=$(_rp_case 20261008-rp-sb-heading "$(printf '%s\n' '    T=$(mktemp -d)' '## 다음 절' '    rm -rf "$T"')")
[ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs \
  && ok "T58o 펜스 밖에서는 제목이 구간 경계다 → destructive_fs 유지" || nope "T58o" "$r"

# T59: ★ 재대입 키워드는 줄 전체에서 찾는다 — 종전 판정을 잠근다 (20261011-risk-sandbox-quote-rebind)
#   이 판정은 문자열·주석 속 낱말에도 반응하는 오발이 있다(`printf '%s\n' 'unset X' > "$T/a.sh"` 뒤의 정리가 신호로 남는다 —
#   PR #180 에서 경량 승격 가드가 틀리게 울렸다). 따옴표·주석을 읽어 빼는 수정을 네 번 설계했고, 독립 리뷰가 그때마다
#   "종전에는 잡히던 재대입이 빠지는" 입력을 찾아 접었다. 아래는 그 입력들이다 — 문자열이 실제로 실행되거나,
#   따옴표·주석을 잘못 읽으면 실행되는 코드가 사라지는 형태. 다시 고칠 때 이 단언이 깨지면 새 미탐이다.
#   종전에 단언이 없던 재대입 경로(unset·mapfile·readarray·getopts·printf -v·:=)와 가림 실패 경로도 함께 잠근다.
_sb() { _fence 'T=$(mktemp -d)' "$@" 'rm -rf "$T"'; }   # 가운데 줄만 바꾸는 틀
_sb_sig() {  # $1=fid $2=id $3=설명 $4…=가운데 줄 → destructive_fs 를 유지해야 한다
  local fid=$1 id=$2 msg=$3; shift 3
  r=$(_rp_case "$fid" "$(_sb "$@")")
  [ "$(_eff "$r")" = "strict" ] && _has "$r" destructive_fs && ok "$id $msg → destructive_fs 유지" || nope "$id" "$r"
}
#   문자열에 담은 재대입이 실제로 실행된다 — 따옴표 안이라고 빼면 놓친다
_sb_sig 20261011-rp-w-btcmt   T59a "백틱 안의 # 뒤에서 닫히고 unset" 'x=`echo a #b`; unset T'
_sb_sig 20261011-rp-w-assign  T59b "대입 줄의 문자열 — 뒤에서 \$cmd 로 실행된다" "cmd='unset T'" '$cmd'
_sb_sig 20261011-rp-w-brace   T59c "대입 줄의 문자열 — 뒤에서 \${cmd} 로 실행된다" 'cmd="read -r T"' '${cmd} < /dev/null'
_sb_sig 20261011-rp-w-func    T59d "함수에 넘긴 문자열 — 함수가 \$1 로 실행한다" 'f() { $1; }' "f 'unset T' > \"\$T/log\""
#   재대입 키워드 경로 (unset·mapfile·readarray·getopts·printf -v·:= 는 종전에 단언이 없었다)
_sb_sig 20261011-rp-k-unset   T59e "명령 위치의 unset" 'unset T'
_sb_sig 20261011-rp-k-mapfile T59f "mapfile 이 변수를 다시 묶는다" 'mapfile -t T < /dev/null'
_sb_sig 20261011-rp-k-rdarr   T59g "readarray 가 변수를 다시 묶는다" 'readarray -t T < /dev/null'
_sb_sig 20261011-rp-k-getopts T59h "getopts 가 변수를 다시 묶는다" 'getopts "ab" T'
_sb_sig 20261011-rp-k-pluseq  T59i "따옴표 안 +=" 'declare "T+=/../.."'
_sb_sig 20261011-rp-k-pv      T59j "printf -v 가 변수를 다시 묶는다" "printf -v T '%s' /var/lib/app"
#   (다음 줄은 경로 잠금이다 — 변수가 이미 있으면 := 는 값을 바꾸지 않는다. := 판정을 바르게 고치면 이 단언은 지운다)
_sb_sig 20261011-rp-k-coleq   T59k "큰따옴표 안 :=" ': "${T:=/var/lib/app}"'
_sb_sig 20261011-rp-k-qname   T59l "이름이 따옴표 안인 unset" 'unset "T"'
_sb_sig 20261011-rp-k-bsl     T59m "역슬래시로 부른 unset" '\unset T'
_sb_sig 20261011-rp-k-hash    T59n "\${#T} 는 주석이 아니다 — 뒤의 unset" 'n=${#T}; unset T'
#   따옴표 짝이 어긋나기 쉬운 입력 — 잘못 짝지으면 실행되는 재대입이 문자열로 보인다
_sb_sig 20261011-rp-k-apos    T59o "아포스트로피 사이의 진짜 unset" "echo \"don't\"; unset T; echo 'x'"
_sb_sig 20261011-rp-k-escq    T59p "이스케이프된 따옴표 뒤의 unset" 'echo \"; unset T; echo \"'
_sb_sig 20261011-rp-k-dqesc   T59q "큰따옴표 안 이스케이프된 따옴표 뒤의 unset" 'echo "a\"b"; unset T; echo "c"'
_sb_sig 20261011-rp-k-escsq   T59r "이스케이프된 작은따옴표 사이의 unset" "echo \\'; unset T; echo \\'"
_sb_sig 20261011-rp-k-dqcmt   T59s "큰따옴표 안 이스케이프 + 주석의 따옴표 — 사이의 unset" 'echo "a\"b"; unset T   # say "hi'
_sb_sig 20261011-rp-k-cmtapos T59t "주석의 아포스트로피 다음 줄 unset" "# it's a temp dir" 'unset T'
#   여러 줄에 걸친 문자열·ANSI-C 따옴표 — 줄마다 따로 읽으면 안팎이 뒤집힌다
_sb_sig 20261011-rp-k-multi   T59u "여러 줄 문자열이 닫힌 뒤의 unset" 'echo "first' 'second"; unset T; echo "third' 'fourth"'
_sb_sig 20261011-rp-k-heredoc T59v "heredoc 본문의 아포스트로피 뒤 unset" 'cat <<EOF' "don't" 'EOF' "unset T; echo 'x'"
_sb_sig 20261011-rp-k-ansi    T59w "ANSI-C 따옴표 뒤의 unset" "echo \$'it\\'s'; unset T; echo 'x'"
_sb_sig 20261011-rp-k-ansicmt T59x "ANSI-C 따옴표 + 주석의 아포스트로피 — 사이의 unset" "X=\$'\\''; unset T   # it's gone"
_sb_sig 20261011-rp-k-ansiml  T59y "여러 줄 ANSI-C 문자열이 닫힌 뒤의 unset" "X=\$'first" "second\\''; unset T   # it's gone"
_sb_sig 20261011-rp-k-dqmis   T59z "큰따옴표 안의 이스케이프된 따옴표 뒤에서 닫히고 unset — 주석에 따옴표가 하나 더 있다" 'echo > "$T/a" "\""; unset T  # "'
#   echo 로 시작하지만 뒤에 재대입이 이어지는 줄 — 따옴표·주석을 잘못 읽으면 단순한 파일 쓰기로 보인다
_sb_sig 20261011-rp-k-mlcmt   T59aa "여러 줄 문자열이 닫힌 뒤의 unset" 'X="first' 'echo > "$T/a" x"; unset T  # "'
_sb_sig 20261011-rp-k-anscmt  T59ab "ANSI-C 문자열 뒤의 unset" "echo > \"\$T/a\" \$'\\''; unset T  # '"
_sb_sig 20261011-rp-k-ansml2  T59ac "여러 줄 ANSI-C 문자열이 닫힌 뒤의 unset" "X=\$'first" "echo > \"\$T/a\" x\\''; unset T  # '"
_sb_sig 20261011-rp-k-escsp   T59ad "이스케이프된 공백 뒤의 # 는 주석이 아니다 — 뒤의 unset" 'echo > "$T/a" a \ # b; unset T'
#   문자열을 현재 셸에서 실행하는 명령
_sb_sig 20261011-rp-k-eval    T59ae "eval 문자열의 unset" "eval 'unset T'"
_sb_sig 20261011-rp-k-source  T59af "source 에 넘긴 문자열의 read" 'source <(echo "read -r T < /dev/null")'
_sb_sig 20261011-rp-k-dot     T59ag "점 명령에 넘긴 문자열의 unset" '. /dev/stdin <<< "unset T"'
_sb_sig 20261011-rp-k-thendot T59ah "then 뒤의 점 명령" 'if true; then . /dev/stdin <<< "unset T"; fi'
_sb_sig 20261011-rp-k-dodot   T59ai "do 뒤의 점 명령" 'for i in 1; do . /dev/stdin <<< "unset T"; done'
_sb_sig 20261011-rp-k-semidot T59aj "; 바로 뒤의 점 명령" 'true;. /dev/stdin <<< "unset T"'
_sb_sig 20261011-rp-k-anddot  T59ak "&& 바로 뒤의 점 명령" 'true &&. /dev/stdin <<< "unset T"'
#   echo·printf 가 함수로 다시 정의돼 있으면 파일에 쓰는 줄의 문자열도 실행된다
_sb_sig 20261011-rp-w-echofn  T59al "함수로 다시 정의한 echo 가 문자열을 실행한다" 'echo() { $1; }' "echo 'unset T' > \"\$T/f\""
_sb_sig 20261011-rp-w-printffn T59am "함수로 다시 정의한 printf 가 문자열을 실행한다" 'function printf { $1; }' "printf 'unset T' > \"\$T/f\""
#   파일에 쓴 문자열을 뒤에서 실행한다
_sb_sig 20261011-rp-k-fdot    T59an "파일에 쓴 unset 을 점 명령으로 읽는다" "echo 'unset T' > \"\$T/f.sh\"" '. "$T/f.sh"'
_sb_sig 20261011-rp-k-fsource T59ao "파일에 쓴 read 를 source 로 읽는다" "printf '%s\\n' 'read -r T < /dev/null' > \"\$T/f.sh\"" 'source "$T/f.sh"'
_sb_sig 20261011-rp-k-fpv     T59ap "파일에 쓴 printf -v 를 뒤에서 실행한다" "echo 'printf -v T %s /var/lib/app' > \"\$T/f.sh\"" '. "$T/f.sh"'
_sb_sig 20261011-rp-k-ffor    T59aq "파일에 쓴 for 를 뒤에서 실행한다" "echo 'for T in /var/lib/app; do :; done' > \"\$T/f.sh\"" '. "$T/f.sh"'
_sb_sig 20261011-rp-k-fopen   T59ar "숨겨 넘긴 뒤 닫히지 않은 따옴표를 지나 실행한다" "echo 'unset T' > \"\$T/f.sh\"" 'echo "open' 'close"' 'eval "$(cat "$T/f.sh")"'
_sb_sig 20261011-rp-k-fthen   T59as "파일에 쓴 unset 을 then 뒤의 점 명령이 읽는다" "echo 'unset T' > \"\$T/f.sh\"" 'if true; then . "$T/f.sh"; fi'
_sb_sig 20261011-rp-k-fsemi   T59at "파일에 쓴 unset 을 ; 바로 뒤의 점 명령이 읽는다" "echo 'unset T' > \"\$T/f.sh\"" 'true;. "$T/f.sh"'
_sb_sig 20261011-rp-k-fand    T59au "파일에 쓴 unset 을 && 바로 뒤의 점 명령이 읽는다" "echo 'unset T' > \"\$T/f.sh\"" 'true &&. "$T/f.sh"'
_sb_sig 20261011-rp-k-for     T59av "파일에 쓴 unset 을 || 바로 뒤의 점 명령이 읽는다" "echo 'unset T' > \"\$T/f.sh\"" 'false ||. "$T/f.sh"'
_sb_sig 20261011-rp-k-fearly  T59aw "읽는 함수를 먼저 정의하고 그 뒤에 파일을 쓴다" 'run() { . "$T/f.sh"; }' "echo 'unset T' > \"\$T/f.sh\"" 'run'
_sb_sig 20261011-rp-k-evcont  T59ax "eval 과 문자열이 줄 이음으로 나뉜다" 'eval \' "  'unset T'"
_sb_sig 20261011-rp-k-wrapper T59ay "eval 하는 함수를 먼저 정의하고 문자열을 넘긴다" 'f() { eval "$1"; }' "f 'unset T'"
#   \${ } 안의 # · 낱말 중간의 # 는 주석이 아니다
_sb_sig  20261011-rp-k-brace  T59az "\${y/ #/} 뒤의 unset" 'echo > "$T/a" ${y/ #/}; unset T'
_sb_sig  20261011-rp-k-midhash T59ba "낱말 중간의 # 뒤의 unset" 'echo > "$T/a" a#b; unset T'
#   다른 변수의 재대입은 출처를 끊지 않는다 — 키워드가 있어도 이름이 다르면 그대로 가린다
r=$(_rp_case 20261011-rp-q-other "$(_sb 'unset OTHER; read -r LINE < /dev/null')")
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" destructive_fs \
  && ok "T59bb 이름이 다른 변수의 unset·read → strict 아님" || nope "T59bb" "$r"
#   가림 awk 가 실패하면 조용히 약해지지 않는다 — 원 코퍼스로 판정하고 stderr 에 알린다(T31 과 같은 shim: 표지가 있는 호출만 실패)
TD=$(mktemp -d); FID=20261011-rp-q-fallback; SHIM=$(mktemp -d)
_setup "$TD" "$FID"
printf '**§유형**: 신규\n' > "$TD/.specops/$FID/spec.md"
_sb 'printf x > "$T/a"' > "$TD/.specops/$FID/tasks.md"   # 평소에는 가려지는 정리다(T58a 와 같은 형태)
printf '#!/bin/sh\ncase "$*" in *rp-sandbox*) exit 2 ;; esac\nexec %s "$@"\n' "$(command -v awk)" > "$SHIM/awk"
chmod +x "$SHIM/awk"
out=$(cd "$TD" && PATH="$SHIM:$PATH" bash "$RP" compute "$FID" 2>"$TD/err"); rc=$?
[ "$rc" -eq 0 ] && grep -q 'sandbox mask unavailable' "$TD/err" \
  && jq -e '.signals.strict | index("destructive_fs")' "$TD/.specops/$FID/risk-profile.json" >/dev/null \
  && ok "T59bc 가림 awk 실패 → 원 코퍼스 판정(destructive_fs) + stderr 경고" || nope "T59bc" "rc=$rc out=$out err=$(cat "$TD/err")"
rm -rf "$TD" "$SHIM"

# ── T60: 신호별 키워드와 가드 — 변이 실측(20261009)에서 지워도 아무 테스트도 실패하지 않던 것들 ──
#   신호 정규식은 대안(|)이 여럿이라 하나를 지워도 다른 대안으로 잡히는 테스트뿐이었다. 대안마다 그 낱말만으로 판정한다.
r=$(_rp_case 20261009-rp-api-path '`src/app/api/users/route.ts` 의 응답 필드를 정리한다')
[ "$(_eff "$r")" = "strict" ] && _has "$r" public_api \
  && ok "T60a 경로의 /api/ → public_api" || nope "T60a" "$r"
r=$(_rp_case 20261009-rp-deploy 'deploy 스크립트의 대상 리전을 바꾼다')
[ "$(_eff "$r")" = "strict" ] && _has "$r" infra \
  && ok "T60b deploy → infra" || nope "T60b" "$r"
r=$(_rp_case 20261009-rp-subproc 'subprocess 로 외부 변환기를 부른다')
[ "$(_eff "$r")" = "strict" ] && _has "$r" external_exec \
  && ok "T60c subprocess → external_exec" || nope "T60c" "$r"
r=$(_rp_case 20261009-rp-kafka 'kafka 토픽에 이벤트를 발행한다')
[ "$(_eff "$r")" = "strict" ] && _has "$r" cross_service \
  && ok "T60d kafka → cross_service" || nope "T60d" "$r"
# 영어 부정어 no — "no <신호>" 는 부재 선언이다 (none·not 과 같은 취급)
r=$(_rp_case 20261009-rp-neg-no 'This change has no migration and touches no payment code')
[ "$(_eff "$r")" != "strict" ] && ! _has "$r" db_migration && ! _has "$r" payment_pii \
  && ok "T60e 'no migration' → strict 아님" || nope "T60e" "$r"
r=$(_rp_case 20261009-rp-pos-no 'Add a migration for the notes table')
[ "$(_eff "$r")" = "strict" ] && _has "$r" db_migration \
  && ok "T60f 대조 — 부정어 없는 migration → strict" || nope "T60f" "$r"

# 문서 확장자 .rst — 문서만 바꾼 FID 는 lite 다 (.md·.txt 와 같은 취급)
TD=$(mktemp -d); FID=20261009-rp-rst
_setup "$TD" "$FID"
printf 'Title\n=====\n' > "$TD/docs/guide.rst"; (cd "$TD" && git add docs/guide.rst)
printf '**§유형**: 신규\n' > "$TD/.specops/$FID/spec.md"
out=$(cd "$TD" && bash "$RP" compute "$FID" 2>/dev/null | tail -1)
[ "$out" = "lite" ] && jq -e '.signals.docs_only == true and .signals.impl_files == 0' "$TD/.specops/$FID/risk-profile.json" >/dev/null \
  && ok "T60g .rst 만 변경 → lite · docs_only" || nope "T60g" "out=$out $(jq -c .signals "$TD/.specops/$FID/risk-profile.json" 2>/dev/null)"
rm -rf "$TD"

# impl_files 는 구현 파일만 센다 — 테스트 파일은 세지 않는다
TD=$(mktemp -d); FID=20261009-rp-impl
_setup "$TD" "$FID"
mkdir -p "$TD/tests"; printf 'x\n' > "$TD/src/a.sh"; printf 'y\n' > "$TD/tests/test_a.sh"; (cd "$TD" && git add src tests)
printf '**§유형**: 신규\n일반 기능\n' > "$TD/.specops/$FID/spec.md"
(cd "$TD" && bash "$RP" compute "$FID" >/dev/null 2>&1)
[ "$(jq -r '.signals.impl_files' "$TD/.specops/$FID/risk-profile.json" 2>/dev/null)" = "1" ] \
  && ok "T60h 구현 1 + 테스트 1 → impl_files=1" || nope "T60h" "$(jq -c .signals "$TD/.specops/$FID/risk-profile.json" 2>/dev/null)"
rm -rf "$TD"

# 기록 필드 — lite_eligible 은 계산값이 lite 일 때만 true, irreversible 은 그 선언이 있을 때 true
TD=$(mktemp -d); FID=20261009-rp-fields
_setup "$TD" "$FID"
printf '# n\n' > "$TD/docs/n.md"; (cd "$TD" && git add docs/n.md)
printf '**§유형**: 신규\n' > "$TD/.specops/$FID/spec.md"
(cd "$TD" && bash "$RP" compute "$FID" >/dev/null 2>&1)
jq -e '.signals.lite_eligible == true and .signals.irreversible == false' "$TD/.specops/$FID/risk-profile.json" >/dev/null \
  && ok "T60i lite → lite_eligible=true · irreversible=false" || nope "T60i" "$(jq -c '.signals' "$TD/.specops/$FID/risk-profile.json" 2>/dev/null)"
printf 'tasks:\n  - id: T1\n    irreversible: true\n    depends_on: []\n' > "$TD/.specops/$FID/tasks.md"
(cd "$TD" && bash "$RP" compute "$FID" >/dev/null 2>&1)
jq -e '.signals.lite_eligible == false and .signals.irreversible == true' "$TD/.specops/$FID/risk-profile.json" >/dev/null \
  && ok "T60j irreversible 선언 → irreversible=true · lite_eligible=false" || nope "T60j" "$(jq -c '.signals' "$TD/.specops/$FID/risk-profile.json" 2>/dev/null)"
rm -rf "$TD"

# 환경변수 하한 strict — standard 뿐 아니라 strict 도 올린다 (내리지는 못한다)
TD=$(mktemp -d); FID=20261009-rp-envfloor
_setup "$TD" "$FID"
printf 'x\n' > "$TD/src/a.sh"; printf 'y\n' > "$TD/src/b.sh"; (cd "$TD" && git add src)
printf '**§유형**: 신규\n일반 기능\n' > "$TD/.specops/$FID/spec.md"
out=$(cd "$TD" && SPECOPS_RISK_PROFILE_FLOOR=strict bash "$RP" compute "$FID" 2>/dev/null | tail -1)
[ "$out" = "strict" ] && ok "T60k SPECOPS_RISK_PROFILE_FLOOR=strict → strict" || nope "T60k" "out=$out"
out=$(cd "$TD" && SPECOPS_RISK_PROFILE_FLOOR=lite bash "$RP" compute "$FID" 2>/dev/null | tail -1)
[ "$out" = "standard" ] && ok "T60l 하한 lite 는 무시 — 내리지 못한다" || nope "T60l" "out=$out"
rm -rf "$TD"

# FID 디렉토리가 symlink 면 거부한다 (기록이 저장소 밖으로 나가지 않는다)
TD=$(mktemp -d); OUTSIDE=$(mktemp -d); FID=20261009-rp-symlink
_setup "$TD" "$FID"; rmdir "$TD/.specops/$FID"; ln -s "$OUTSIDE" "$TD/.specops/$FID"
printf '**§유형**: 신규\n' > "$OUTSIDE/spec.md"
e=$(cd "$TD" && bash "$RP" compute "$FID" 2>&1 >/dev/null); rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$e" | grep -q 'symlink' && [ ! -f "$OUTSIDE/risk-profile.json" ] \
  && ok "T60m FID 디렉토리 symlink → 거부 · 밖에 기록 없음" || nope "T60m" "rc=$rc e=$e outside=$(ls "$OUTSIDE" | tr '\n' ' ')"
rm -rf "$TD" "$OUTSIDE"

# T61: ★ 테스트 전용 변경의 rm -rf 인용 — 파일 목록으로 면제한다 (20261015-risk-test-only-rmrf)
#   비문서 변경 파일이 1개 이상이고 전부 엄격한 테스트 경로이며 destructive_fs 의 근거가 `rm -rf` 글자뿐이면 그 신호를 뺀다.
#   실기록: 테스트 1파일만 바꾸는 lite FID 가 tasks.md 산문 한 줄로 LITE-STRICT-GUARD 에 걸렸다.
_RP61_ERR=$(mktemp)
_rp_files() {  # $1=fid $2=tasks.md 본문 $3…=스테이지할 경로 → stdout "<rc> <effective> <signals.strict json>" · stderr 는 $_RP61_ERR
  local td fid=$1 body=$2 p rc; shift 2; td=$(mktemp -d)
  _setup "$td" "$fid"
  { printf '**§유형**: trivial\n'; printf '**§lite**: true\n'; } > "$td/.specops/$fid/spec.md"
  printf '%s\n' "$body" > "$td/.specops/$fid/tasks.md"
  for p in "$@"; do mkdir -p "$td/$(dirname "$p")"; printf 'x\n' > "$td/$p"; (cd "$td" && git add "$p"); done
  (cd "$td" && bash "$RP" compute "$fid" >/dev/null 2>"$_RP61_ERR"); rc=$?
  printf '%s %s %s\n' "$rc" "$(jq -r .effective "$td/.specops/$fid/risk-profile.json" 2>/dev/null)" \
    "$(jq -c .signals.strict "$td/.specops/$fid/risk-profile.json" 2>/dev/null)"
  rm -rf "$td"
}
_RP61_PROSE='- [ ] EXIT 트랩을 `( sleep 0.5; rm -rf … ) &` 로 바꾼 사본에서 종전 R6.g 실행.'
r=$(_rp_files 20261015-rp-to-prose "$_RP61_PROSE" scripts/tests/test-reuse-metrics.sh CHANGELOG.md)
[ "${r%% *}" = "0" ] && ! _has "$r" destructive_fs && grep -q 'rm -rf 인용만의 destructive_fs' "$_RP61_ERR" \
  && ok "T61a ★ 테스트 전용 변경의 산문 rm -rf → strict 아님 · 가드 없음 · stderr 1줄" || nope "T61a" "$r err=$(cat "$_RP61_ERR")"
r=$(_rp_files 20261015-rp-to-paths "$_RP61_PROSE" src/__tests__/a.ts pkg/foo_test.go web/a.test.ts app/b.spec.ts tests/test_x.py lib/y_test.py src/test/java/FooIT.java)
[ "${r%% *}" = "0" ] && ! _has "$r" destructive_fs \
  && ok "T61b 테스트 경로 관례 7종 → 테스트 전용으로 면제" || nope "T61b" "$r"
r=$(_rp_files 20261015-rp-to-backtest "$_RP61_PROSE" app/analytics/backtest.py)
[ "${r%% *}" = "3" ] && _has "$r" destructive_fs \
  && ok "T61c 이름에 test 가 든 제품 경로(backtest.py) → destructive_fs 유지" || nope "T61c" "$r"
r=$(_rp_files 20261015-rp-to-near "$_RP61_PROSE" tests/test_backtest.py app/services/backtests.py scripts/_internal/extract-test-commands.sh)
[ "${r%% *}" = "3" ] && _has "$r" destructive_fs \
  && ok "T61d 테스트 + 이름이 비슷한 제품 경로 → destructive_fs 유지" || nope "T61d" "$r"
r=$(_rp_files 20261015-rp-to-empty "$_RP61_PROSE")
[ "${r%% *}" = "3" ] && _has "$r" destructive_fs \
  && ok "T61e 변경 파일 없음 → destructive_fs 유지" || nope "T61e" "$r"
r=$(_rp_files 20261015-rp-to-doconly "$_RP61_PROSE" CHANGELOG.md)
[ "${r%% *}" = "3" ] && _has "$r" destructive_fs \
  && ok "T61f 문서만 변경(테스트 0개) → destructive_fs 유지" || nope "T61f" "$r"
r=$(_rp_files 20261015-rp-to-mixed "$_RP61_PROSE" scripts/tests/test-x.sh scripts/x.sh)
[ "${r%% *}" = "3" ] && _has "$r" destructive_fs \
  && ok "T61g 테스트 + 제품 파일 → destructive_fs 유지" || nope "T61g" "$r"
r=$(_rp_files 20261015-rp-to-irr "$(printf '%s\n' "$_RP61_PROSE" 'tasks:' '  - id: T1' '    irreversible: true' '    depends_on: []')" scripts/tests/test-x.sh)
[ "${r%% *}" = "3" ] && _has "$r" destructive_fs \
  && ok "T61h 테스트 전용 + irreversible: true → destructive_fs 유지" || nope "T61h" "$r"
r=$(_rp_files 20261015-rp-to-delete "$(printf '%s\n' "$_RP61_PROSE" '- Delete: `scripts/tests/old.sh`')" scripts/tests/test-x.sh)
[ "${r%% *}" = "3" ] && _has "$r" destructive_fs \
  && ok "T61i 테스트 전용 + Delete: → destructive_fs 유지" || nope "T61i" "$r"
r=$(_rp_files 20261015-rp-to-unlink "$(printf '%s\n' "$_RP61_PROSE" '정리는 os.unlink(path) 로 한다')" tests/test_x.py)
[ "${r%% *}" = "3" ] && _has "$r" destructive_fs \
  && ok "T61j 테스트 전용 + unlink( → destructive_fs 유지" || nope "T61j" "$r"
r=$(_rp_files 20261015-rp-to-auth "$(printf '%s\n' "$_RP61_PROSE" 'JWT 검증 미들웨어를 추가한다')" scripts/tests/test-x.sh)
[ "${r%% *}" = "3" ] && _has "$r" auth && ! _has "$r" destructive_fs \
  && ok "T61k 테스트 전용 + 다른 strict 신호 → 그 신호는 유지 · destructive_fs 만 제외" || nope "T61k" "$r"
r=$(_rp_files 20261015-rp-to-upper "- [ ] 정리: \`RM -RF \"\$OUT\"\`" scripts/tests/test-x.sh)
[ "${r%% *}" = "0" ] && ! _has "$r" destructive_fs \
  && ok "T61l 대문자 RM -RF 도 rm -rf 로 보고 면제" || nope "T61l" "$r"
#   깨진 UTF-8 바이트 뒤의 다른 파괴 신호 — 가림 sed 가 그 줄에서 멈추면 Delete: 가 사라져 면제로 뒤집혔다(plan 리뷰 I-1)
r=$(LANG=en_US.UTF-8 _rp_files 20261015-rp-to-badbyte "$(printf '\377 깨진 바이트\n- [ ] rm -rf "$OUT" 정리\n- Delete: scripts/tests/old.sh')" scripts/tests/test-x.sh)
[ "${r%% *}" = "3" ] && _has "$r" destructive_fs \
  && ok "T61m 깨진 UTF-8 바이트 뒤의 Delete: → destructive_fs 유지" || nope "T61m" "$r"
#   같은 깨진 바이트라도 근거가 rm -rf 뿐이면 면제된다 — 가림 sed 가 바이트 단위(LC_ALL=C)로 돌아야 한다(plan 리뷰 2회차 m-1)
r=$(LANG=en_US.UTF-8 _rp_files 20261015-rp-to-badbyte-ok "$(printf '\377 깨진 바이트\n- [ ] rm -rf "$OUT" 정리')" scripts/tests/test-x.sh)
[ "${r%% *}" = "0" ] && ! _has "$r" destructive_fs \
  && ok "T61n 깨진 UTF-8 바이트 + rm -rf 만 → 면제(가림이 바이트 단위)" || nope "T61n" "$r"
rm -f "$_RP61_ERR"

finish
