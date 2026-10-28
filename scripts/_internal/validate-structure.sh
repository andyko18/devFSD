#!/usr/bin/env bash
# specops-ko v0.0 PoC · 플러그인 구조 무결성 정적 검증 (Gate)
# 체크: 디렉토리·파일수·frontmatter·superpowers 런타임 참조·매니페스트 일관성
# 사용: scripts/validate-structure.sh [--json]
# baseline: 실측 카운트의 단일 출처는 scripts/_internal/.structure-baseline (jsonl) — 본 주석에 수치 비기재(드리프트 방지).
#           카테고리: skills/<name>/SKILL.md · commands · agents · templates (conductor 없이 chain)
# 참조: README.md §현재 상태
set -u

JSON_MODE=0
UPDATE_BASELINE=0
case "${1:-}" in
  --json) JSON_MODE=1 ;;
  --update-baseline) UPDATE_BASELINE=1 ;;
esac

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin_root=$(dirname "$(dirname "$script_dir")")
cd "$plugin_root"
BASELINE="$script_dir/.structure-baseline"

FAILS=0
RESULTS=()
emit() { RESULTS+=("$1|$2|${3:-}"); [ "$2" = "FAIL" ] && FAILS=$((FAILS+1)); }

# 1) 디렉토리 존재 (v0.4a: agents/ 추가; docs/ 제거됨)
miss_d=()
for d in commands skills templates hooks scripts agents; do
  [ -d "$d" ] || miss_d+=("$d")
done
if [ ${#miss_d[@]} -eq 0 ]; then emit directories OK; else emit directories FAIL "누락: ${miss_d[*]}"; fi

# 2) 파일 개수 — .structure-baseline (jsonl) 동적 검증 (U4)
#    각 줄: {"category":"<라벨>","glob":"<패턴>","count":<정수>}
#    --update-baseline: 현 실측으로 baseline 갱신 후 종료
count_glob() {
  local glob="$1"
  if [[ "$glob" == */SKILL.md ]]; then
    # glob 형식 가정: <root>/*/SKILL.md (root 만 fixed). dirname 은 wildcard 포함이라 부적합.
    local root="${glob%%/*}"
    find "$root" -mindepth 2 -maxdepth 2 -name SKILL.md -type f 2>/dev/null | wc -l | tr -d ' '
  else
    ls $glob 2>/dev/null | wc -l | tr -d ' '
  fi
}

# ── skill 크기 래칫 (20260828-skill-size-ratchet) ────────────────────────────
# 왜 래칫인가: 임계 경고는 무시된다(이 repo 의 skip-tracker advisory 가 SKIP 71% 를 방치한 전례).
#   현재 크기를 기록하고 초과하면 FAIL, 늘리려면 --update-baseline 으로 **명시 갱신**한다.
#   임계값 발명 없이 드리프트만 막는다 — 49.5KB SKILL.md 가 생긴 경로를 닫는다.
# 왜 bytes·lines 만인가: 토큰 수는 추정이라 게이트가 지어낸 수치를 출력하면 안 된다(실측 문화).
# 한계 고백: **SKILL.md 본문만** 잰다(= 컨텍스트로 로드되는 것). 본문을 보조 파일로 옮기면
#   수치가 준다 — 그게 의도(온디맨드 읽기)지만, 보조 파일이 정말 온디맨드인지는 기계가 못 본다.
SKILL_BASELINE="$script_dir/.skill-size-baseline"
HARDGATE_BASELINE="$script_dir/.hardgate-baseline"

# chain 집계 대상 = hooks/chain.yaml 의 from/to 합집합 (SoT 단일 — 하드코딩 목록 금지).
#   목록을 여기 복제하면 edge 변경 시 조용히 stale 이 된다 — chain_consistency 가 이미 잡는
#   클래스의 드리프트를 새로 만드는 셈이다.
_chain_skills() {
  [ -f hooks/chain.yaml ] || return 0
  grep -oE '\{from: [a-z-]+, to: [a-z-]+\}' hooks/chain.yaml \
    | grep -oE '[a-z-]+-ko' | sort -u
}

_gen_skill_baseline() {
  local f n
  while IFS= read -r f; do
    n=$(basename "$(dirname "$f")")
    printf '{"skill":"%s","bytes":%s,"lines":%s}\n' "$n" "$(wc -c <"$f" | tr -d ' ')" "$(wc -l <"$f" | tr -d ' ')"
  done < <(find skills -name SKILL.md | sort)
  # chain 집계 — 개별 skill 이 다 baseline 이하여도 총량이 커지는 것을 따로 잠근다
  local tb=0 tl=0 s p
  while IFS= read -r s; do
    p="skills/$s/SKILL.md"; [ -f "$p" ] || continue
    tb=$((tb + $(wc -c <"$p" | tr -d ' ')))
    tl=$((tl + $(wc -l <"$p" | tr -d ' ')))
  done < <(_chain_skills)
  printf '{"chain_bytes":%s,"chain_lines":%s}\n' "$tb" "$tl"
}

# 산문 HARD GATE 검출의 **단일 SoT** — 마커 없이 `HARD GATE` 를 선언하는 skill 이름을 한 줄씩.
#   writer(--update-baseline)와 checker(래칫)가 같은 판정을 써야 한다. 로직이 2벌이면 한쪽만
#   넓어질 때 불필요한 이름이 baseline 에 등재되며 **무음 완화**가 된다(T3 Phase C Important 2).
#   iteration 순서(glob)와 이름 산출 방식은 committed baseline 과 바이트 동일해야 하므로 정렬하지 않는다.
_hardgate_outside_skills() {
  local f
  for f in skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    grep -q '<HARD-GATE>' "$f" 2>/dev/null && continue
    grep -qE 'HARD GATE|HARD-GATE' "$f" 2>/dev/null || continue
    basename "$(dirname "$f")"
  done
  return 0  # 마지막 iteration 의 grep 상태가 함수 종료코드로 새지 않게 (미래에 set -e 도입 대비)
}

if [ "$UPDATE_BASELINE" = "1" ]; then
  if [ ! -f "$BASELINE" ]; then
    echo "❌ .structure-baseline 부재 — 초기 생성은 수동 권장 (스크립트가 카테고리 추측 X)" >&2
    exit 1
  fi
  _gen_skill_baseline > "$SKILL_BASELINE"
  echo "✅ .skill-size-baseline 갱신 완료."
  while IFS= read -r hg_name; do
    [ -n "$hg_name" ] || continue
    printf '{"skill":"%s"}\n' "$hg_name"
  done < <(_hardgate_outside_skills) > "$HARDGATE_BASELINE"
  echo "✅ .hardgate-baseline 갱신 완료."
  tmp=$(mktemp)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    cat=$(echo "$line" | jq -r '.category')
    glob=$(echo "$line" | jq -r '.glob')
    actual=$(count_glob "$glob")
    printf '{"category":"%s","glob":"%s","count":%s}\n' "$cat" "$glob" "$actual" >> "$tmp"
  done < "$BASELINE"
  mv "$tmp" "$BASELINE"
  echo "✅ .structure-baseline 갱신 완료. git diff 로 의도 확인 후 commit 하세요."
  exit 0
fi

if [ ! -f "$BASELINE" ]; then
  emit file_counts FAIL ".structure-baseline 부재. --update-baseline 로 생성하세요"
else
  fc=()
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    cat=$(echo "$line" | jq -r '.category')
    glob=$(echo "$line" | jq -r '.glob')
    expected=$(echo "$line" | jq -r '.count')
    actual=$(count_glob "$glob")
    [ "$actual" = "$expected" ] || fc+=("${cat}: got ${actual}, expect ${expected}")
  done < "$BASELINE"
  if [ ${#fc[@]} -eq 0 ]; then emit file_counts OK; else emit file_counts FAIL "${fc[*]}"; fi
fi

# 2b) 메타 skill SessionStart 주입 경로 필수 (P1 핵심 가설)
meta="skills/using-specops-ko/SKILL.md"
hook="hooks/session-start.sh"
miss_m=()
[ -f "$meta" ] || miss_m+=("$meta")
[ -x "$hook" ] || miss_m+=("$hook (exec-bit)")
if [ ${#miss_m[@]} -eq 0 ]; then emit meta_injection OK; else emit meta_injection FAIL "누락: ${miss_m[*]}"; fi

# 3) frontmatter YAML 유효 (skills/*/SKILL.md + commands + templates)
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
  # 파일마다 python3 를 띄우면(≈110회 × import yaml) 이 체크만 4s 라 test-validate-structure 가 300s 상한을 넘겼다
  #   (20261007-validate-structure-timeout) — 한 번의 python3 가 전 파일을 훑는다. 의미는 종전과 같다:
  #   첫 줄이 `---` 가 아니면 건너뛰고, 다음 `---` 줄 전까지를 YAML 로 읽어 실패한 파일을 모은다.
  bad=()
  while IFS= read -r f; do
    [ -n "$f" ] && bad+=("$f")
  done < <(python3 - <<'PYEOF' 2>/dev/null
import os, sys
# cwd 의 yaml.py 가 진짜 yaml 을 가리지 못하게 한다(yaml-cwd-shadow 와 같은 이유)
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import yaml
for top in ("commands", "skills", "templates"):
    for root, dirs, files in os.walk(top):
        dirs.sort()
        for name in sorted(files):
            if not name.endswith(".md"):
                continue
            path = os.path.join(root, name)
            try:
                lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
            except OSError:
                print(path); continue
            if not lines or lines[0] != "---":
                continue
            fm = []
            for ln in lines[1:]:
                if ln == "---":
                    break
                fm.append(ln)
            try:
                yaml.safe_load("\n".join(fm))
            except Exception:
                print(path)
PYEOF
)
  if [ ${#bad[@]} -eq 0 ]; then emit frontmatter OK; else emit frontmatter FAIL "${bad[*]}"; fi
else
  emit frontmatter SKIP "python3+pyyaml 미설치 — 한계 고백"
fi

# 4) commands/ 에 superpowers 런타임 참조 0건 (v0.0: agents/ 없음)
# 허용: #/<!-- 주석, YAML 리스트(- superpowers), reference_upstream:, superpowers:/... 경로
sp=$(grep -rE '^[^#<-]*superpowers:' commands/ 2>/dev/null \
     | grep -vE '^[^:]*:[[:space:]]*(#|reference_upstream)' || true)
if [ -z "$sp" ]; then emit no_superpowers OK; else emit no_superpowers FAIL "$(echo "$sp" | head -3 | tr '\n' ';')"; fi

# 5) 매니페스트 version 일관성
if command -v python3 >/dev/null 2>&1; then
  pv=$(python3 -c "import json; print(json.load(open('.claude-plugin/plugin.json'))['version'])" 2>/dev/null || echo ERR)
  mv=$(python3 -c "import json; print(json.load(open('.claude-plugin/marketplace.json'))['plugins'][0]['version'])" 2>/dev/null || echo ERR)
  if [ "$pv" = "$mv" ] && [ "$pv" != ERR ]; then
    emit manifest OK "both=$pv"
  else
    emit manifest FAIL "plugin.json=$pv vs marketplace.json=$mv"
  fi
else
  emit manifest SKIP "python3 미설치"
fi

# 6) reference_upstream 포맷 정보성
# 유효 포맷: (a) owner/repo@version path  (b) specops-ko 독자 추가 (upstream 미존재 명시)
total=$(grep -rh '^reference_upstream:' commands/ skills/ docs/ 2>/dev/null | wc -l | tr -d ' ')
struct_std=$(grep -rhE '^reference_upstream:[[:space:]]+[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+@[a-zA-Z0-9._-]+[[:space:]]+[^[:space:]]+' \
         commands/ skills/ docs/ 2>/dev/null | wc -l | tr -d ' ')
struct_local=$(grep -rh '^reference_upstream:' commands/ skills/ docs/ 2>/dev/null | grep -c '독자 추가' || true)
struct=$((struct_std + struct_local))
emit ref_upstream_fmt INFO "struct=${struct}/${total}"

# 7) skill_conventions — SKILL.md frontmatter + 섹션 규약 검증
if [ ! -f "scripts/tests/test-skill-conventions.sh" ]; then
  emit skill_conventions SKIP "test-skill-conventions.sh 미존재"
elif bash scripts/tests/test-skill-conventions.sh >/dev/null 2>&1; then
  emit skill_conventions OK
else
  detail=$(bash scripts/tests/test-skill-conventions.sh 2>&1 | grep '^FAIL' | head -3 | tr '\n' '; ')
  emit skill_conventions FAIL "$detail"
fi

# 8) version_sync — plugin.json 기준 README header/footer · CHANGELOG 최신 헤딩 · marketplace description 동기화
pv2=$(jq -r '.version // empty' .claude-plugin/plugin.json 2>/dev/null || true)
if [ -z "$pv2" ]; then
  emit version_sync SKIP "plugin.json version 미확인"
elif [ ! -f README.md ] && [ ! -f CHANGELOG.md ]; then
  emit version_sync SKIP "README/CHANGELOG 부재"
else
  vs=()
  mdesc=$(jq -r '.metadata.description // empty' .claude-plugin/marketplace.json 2>/dev/null || true)
  mdv=$(printf '%s' "$mdesc" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  [ -n "$mdv" ] && [ "$mdv" != "v$pv2" ] && vs+=("marketplace.description=$mdv")
  if [ -f README.md ]; then
    rh=$(grep -oE '\(v[0-9]+\.[0-9]+\.[0-9]+\)' README.md | head -1 | tr -d '()' || true)
    [ -n "$rh" ] && [ "$rh" != "v$pv2" ] && vs+=("README.header=$rh")
    rf=$(grep -oE '최신: v[0-9]+\.[0-9]+\.[0-9]+' README.md | head -1 | grep -oE 'v[0-9.]+' || true)
    [ -n "$rf" ] && [ "$rf" != "v$pv2" ] && vs+=("README.footer=$rf")
  fi
  if [ -f CHANGELOG.md ]; then
    cl=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
    [ -n "$cl" ] && [ "$cl" != "$pv2" ] && vs+=("CHANGELOG.latest=$cl")
  fi
  if [ ${#vs[@]} -eq 0 ]; then emit version_sync OK "v$pv2"; else emit version_sync FAIL "plugin.json=v$pv2 vs ${vs[*]}"; fi
fi

# 9) readme_counts — README 구조 트리 카운트 (SKILL.md × N / templates ← N건 / agents ← N건 / 슬래시 진입로 N건) vs 실측
if [ ! -f README.md ]; then
  emit readme_counts SKIP "README.md 부재"
else
  rc_i=()
  r_sk=$(grep -oE 'SKILL\.md × [0-9]+' README.md | head -1 | grep -oE '[0-9]+' || true)
  a_sk=$(find skills -mindepth 2 -maxdepth 2 -name SKILL.md -type f 2>/dev/null | wc -l | tr -d ' ')
  [ -n "$r_sk" ] && [ "$r_sk" != "$a_sk" ] && rc_i+=("skills: README=$r_sk actual=$a_sk")
  r_tp=$(grep -E 'templates/.*← [0-9]+건' README.md | head -1 | grep -oE '[0-9]+건' | tr -d '건' || true)
  a_tp=$(find templates -type f ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')
  [ -n "$r_tp" ] && [ "$r_tp" != "$a_tp" ] && rc_i+=("templates: README=$r_tp actual=$a_tp")
  r_ag=$(grep -E 'agents/.*← [0-9]+건' README.md | head -1 | grep -oE '[0-9]+건' | tr -d '건' || true)
  a_ag=$(ls agents/*.md 2>/dev/null | wc -l | tr -d ' ')
  [ -n "$r_ag" ] && [ "$r_ag" != "$a_ag" ] && rc_i+=("agents: README=$r_ag actual=$a_ag")
  # 슬래시 명령 수 — 종전엔 세지 않아 README 25 · 설계 문서 24 · 실제 28 로 갈라져 있었다(20261009)
  r_cm=$(grep -E 'commands/.*슬래시 진입로 [0-9]+건' README.md | head -1 | grep -oE '[0-9]+건' | tr -d '건' || true)
  a_cm=$(ls commands/*.md 2>/dev/null | wc -l | tr -d ' ')
  [ -n "$r_cm" ] && [ "$r_cm" != "$a_cm" ] && rc_i+=("commands: README=$r_cm actual=$a_cm")
  if [ -f docs/architecture.md ]; then
    d_cm=$(grep -E '^\| 슬래시 커맨드 \| [0-9]+건' docs/architecture.md | head -1 | grep -oE '[0-9]+건' | tr -d '건' || true)
    [ -n "$d_cm" ] && [ "$d_cm" != "$a_cm" ] && rc_i+=("commands: docs/architecture.md=$d_cm actual=$a_cm")
  fi
  if [ ${#rc_i[@]} -eq 0 ]; then emit readme_counts OK; else emit readme_counts FAIL "${rc_i[*]}"; fi
fi

# 10) changelog_body — 최신 릴리즈 섹션 본문 비공백 (공백 릴리즈 노트 차단)
if [ ! -f CHANGELOG.md ]; then
  emit changelog_body SKIP "CHANGELOG.md 부재"
elif ! grep -qE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md; then
  emit changelog_body SKIP "릴리즈 헤딩 없음"
else
  latest=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | head -1)
  body=$(awk '
    /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ { if (found) exit; found=1; next }
    found && /^## /        { exit }
    found && /^\[[0-9A-Za-z]/ { exit }
    found && NF && !/^-+$/ { print }
  ' CHANGELOG.md)
  if [ -n "$body" ]; then emit changelog_body OK "$latest"; else emit changelog_body FAIL "최신 릴리즈 ${latest} 본문 공백"; fi
fi

# 11) xref_resolve — skills/·commands/ 본문의 skill/agent 참조 토큰이 skills/·commands/·agents/ 에 실재
#     ① prefix 형: devfsd:<name>  ② bare 형: <name>-ko (FID 20260713-ghost-agent-drift)
#     bare 확장 배경: prefix 토큰만 수집하던 탓에 bare 로 서술된 유령 에이전트(analyzer-ko·planner-ko 등)가
#     검사망 밖이었다 — 문서가 존재하지 않는 에이전트를 서술해도 전 테스트가 통과했다.
#     allowlist: 플러그인명 자체(specops-ko) · 구 플러그인명(specops-auto-ko — 케이스 스터디 파일명 참조)
#     · upstream 프로젝트/파일 참조 — 본 repo 에 파일이 없는 게 정상.
#     (두 grep 을 합집합 — 단일 alternation 은 BSD/GNU leftmost-longest 차이에 노출)
XREF_ALLOW=" specops-ko specops-auto-ko writing-plans-ko subagent-driven-development-ko "
xr=()
while IFS= read -r tok; do
  [ -z "$tok" ] && continue
  short="${tok#devfsd:}"
  case "$XREF_ALLOW" in *" $short "*) continue ;; esac
  [ -f "skills/$short/SKILL.md" ] || [ -f "commands/$short.md" ] || [ -f "agents/$short.md" ] || xr+=("$tok")
done < <({ grep -rhoE 'devfsd:[a-z0-9][a-z0-9-]*' skills commands templates --include='*.md' 2>/dev/null
           grep -rhoE '[a-z][a-z0-9-]*-ko' skills commands templates --include='*.md' 2>/dev/null; } | sort -u)
if [ ${#xr[@]} -eq 0 ]; then emit xref_resolve OK; else emit xref_resolve FAIL "미해석: ${xr[*]}"; fi

# 12) used_by_fmt — skill used_by 는 short name 규약 (CLAUDE.md): skill 참조는 <name>-ko, command 는 /<name>.
#     full `devfsd:` prefix 금지 (used_by 역참조·기계 파싱 일관성). 본문 토큰(xref_resolve 대상)은 무관.
ubf=$(grep -rlE '^used_by:.*devfsd:' skills --include='SKILL.md' 2>/dev/null \
  | sed 's#.*/skills/##; s#/SKILL.md##' | tr '\n' ' ')
if [ -z "$ubf" ]; then emit used_by_fmt OK; else emit used_by_fmt FAIL "full-prefix 위반: $ubf"; fi

# 12.5) plugin_root_paths — 사용자 프로젝트 cwd(≠plugin)서 실행되는 커맨드/스킬 본문의 번들 스크립트 호출은
#       상대 `bash scripts/` 금지 (외부 cwd 서 스크립트 부재 → No such file). 정식형 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/`
#       (docs: Skill·agent 본문의 ${CLAUDE_PLUGIN_ROOT} 는 로드 시점 절대경로 치환). 예외 2종:
#       ① 자기유지보수 전용 파일(cwd=plugin 서만 실행): release.md·release-ko·e2e-test-ko
#       ② 라이브 호출 아닌 산문·PR템플릿: `scripts/*.sh` 러너 glob · `scripts/tests/test-*` · `scripts/_internal/validate-structure`
# 판정은 check-plugin-paths.sh 가 SoT (bash|source + scripts|hooks|skills 경로 · skills/agents/commands/templates 전체 + scripts·hooks 의 안내문 — test-plugin-paths 가 회귀 잠금).
#   종전 인라인 grep 은 commands/·skills/ 의 `bash scripts/` 만 봤다 — `bash hooks/`·`source scripts/`·agents/·templates/ 는 검사망 밖이었다.
if [ ! -f "$(dirname "$0")/check-plugin-paths.sh" ]; then
  emit plugin_root_paths FAIL "check-plugin-paths.sh 부재 — 판정 SoT 스크립트가 없다"
elif prp=$(bash "$(dirname "$0")/check-plugin-paths.sh" "$PWD" 2>&1); then
  emit plugin_root_paths OK
else
  emit plugin_root_paths FAIL "$(printf '%s\n' "$prp" | sed -n '2,4p' | tr -s ' ' | tr '\n' ' ')"
fi

# 13) agent_tools — role: evaluator 역방향 스캔 (Generator-Evaluator 도구 박탈 하드강제)
#     ① 마킹 evaluator 전체: tools 명시 + Write/Edit/MultiEdit/NotebookEdit 박탈 ② 파일명 *reviewer* 미마킹 FAIL (2차 방어)
#     ③ 파일 존재 + 마킹 0건 FAIL (공회전 방지) ④ agents/*.md 0건(sandbox) SKIP
#     한계 고백: 미마킹 + 파일명 비reviewer 신규 evaluator (critic 류) 는 사각 — 마킹 규약(CLAUDE.md)으로 안내
#     ★ -w Edit 만으로는 MultiEdit/NotebookEdit 를 못 잡음(한 단어) — 명시 토큰 필수
if ! ls agents/*.md >/dev/null 2>&1; then
  emit agent_tools SKIP "agents/*.md 부재 (sandbox 등)"
else
  atf=()
  ev=$(grep -l '^role: evaluator' agents/*.md 2>/dev/null || true)
  if [ -z "$ev" ]; then
    atf+=("evaluator마킹0건")
  else
    for f in $ev; do
      a=$(basename "$f" .md)
      tl=$(grep -E '^tools:' "$f" 2>/dev/null)
      if [ -z "$tl" ]; then atf+=("$a:tools누락"); continue; fi
      printf '%s' "$tl" | grep -qwE 'Write|Edit|MultiEdit|NotebookEdit' && atf+=("$a:Write/Edit포함")
    done
  fi
  for f in agents/*reviewer*.md; do
    [ -f "$f" ] || continue
    grep -q '^role: evaluator' "$f" || atf+=("$(basename "$f" .md):role마킹누락")
  done
  if [ ${#atf[@]} -eq 0 ]; then emit agent_tools OK; else emit agent_tools FAIL "${atf[*]}"; fi
fi

# 14) chain_consistency — hooks/chain.yaml(단일 source) ↔ SKILL.md `## 다음 skill` ↔ 메타 skill 화살표 목록
#     primary edge 만 대조 (조건 분기 산문은 xref_resolve 관할). T-H1(prefilter≡rules.jsonl) 동일 클래스.
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import yaml" 2>/dev/null; then
  emit chain_consistency SKIP "python3+pyyaml 미설치 — 한계 고백"
elif [ ! -f hooks/chain.yaml ]; then
  emit chain_consistency FAIL "hooks/chain.yaml 부재"
else
  cc_out=$(python3 - <<'PYEOF' 2>&1
import glob, re, sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import yaml

try:
    with open('hooks/chain.yaml') as f:
        data = yaml.safe_load(f)
    declared = {(e['from'], e['to']) for e in data['edges']}
except Exception as ex:
    print(f"chain.yaml 파싱 실패: {ex}"); sys.exit(1)

actual = set()
for path in glob.glob('skills/*/SKILL.md'):
    name = path.split('/')[1]
    in_sec = False
    for line in open(path, encoding='utf-8'):
        if line.startswith('## 다음 skill'):
            in_sec = True; continue
        if in_sec and line.startswith('## '):
            in_sec = False; continue  # 섹션 종료 리셋 — 후속 섹션 Skill: 라인 오수집 방지
        m = re.match(r'^Skill: devfsd:([a-z-]+)\s*$', line)
        if in_sec and m:
            actual.add((name, m.group(1)))

issues = [f"chain.yaml에만: {f} → {t}" for f, t in sorted(declared - actual)]
issues += [f"SKILL.md에만: {f} → {t}" for f, t in sorted(actual - declared)]

# 메타 skill 화살표 목록: 인접 pair ⊆ declared (요약 목록이라 생략 허용 — 존재하지 않는 edge 주장만 FAIL)
meta = open('skills/using-specops-ko/SKILL.md', encoding='utf-8').read()
for line in meta.splitlines():
    if '→' not in line or '-ko' not in line:
        continue
    toks = [t for t in (re.fullmatch(r'([a-z][a-z-]*-ko)\b.*', s.strip()) for s in line.split('→')) if t]
    names = [t.group(1) for t in toks]
    for a, b in zip(names, names[1:]):
        if (a, b) not in declared:
            issues.append(f"메타목록 미선언 edge: {a} → {b}")

# 네 번째 출처 — commands/*.md 의 chain 서술 (20260829-chain-4th-source).
#   왜 추가하나: 위 세 출처(chain.yaml · SKILL.md · 메타목록)를 대조하면서, **사용자가 흐름을
#   이해하려고 실제로 읽는 문서**만 빠져 있었다. 커맨드 문서의 chain 이 틀려도 아무도 울지 않았다.
#   비대칭은 메타목록과 **동일**하다: 요약 문서이므로 생략은 허용하고, chain.yaml 에 **없는 edge 를
#   주장할 때만** FAIL 한다 — /start-all 이 3 edge 만 적는 것은 batch 가 decompose 에서 멈춰서지
#   오류가 아니다. 이 방향이라 오탐 위험이 낮다(같은 규칙이 메타목록에서 이미 검증됐다).
for path in sorted(glob.glob('commands/*.md')):
    for line in open(path, encoding='utf-8'):
        if '→' not in line or '-ko' not in line:
            continue
        toks = [t for t in (re.fullmatch(r'([a-z][a-z-]*-ko)\b.*', s.strip()) for s in line.split('→')) if t]
        names = [t.group(1) for t in toks]
        for a, b in zip(names, names[1:]):
            if (a, b) not in declared:
                issues.append(f"{path} 미선언 edge: {a} → {b}")

if issues:
    print('; '.join(issues)); sys.exit(1)
PYEOF
)
  if [ $? -eq 0 ]; then emit chain_consistency OK; else emit chain_consistency FAIL "$cc_out"; fi
fi

# 15) contract_consistency — cross-skill 계약 토큰(BATCH-*-DONE halt signal) 방출↔감시 정합
#     skill 이 방출(emit)하는 signal 을 오케스트레이터 command 가 감시(watch)하는지 + suffix 일치.
#     recurring 결함 클래스(feedback_skill_body_infra_propagation)의 구조적 절반을 결정적으로 적발:
#     start-all F1(suffix drift <BATCH_ID>↔<FID>)·고아 signal 을 LLM 없이 CI 에서 차단.
if ! command -v python3 >/dev/null 2>&1; then
  emit contract_consistency SKIP "python3 미설치 — 한계 고백"
else
  ct_out=$(python3 - <<'PYEOF' 2>&1
import glob, re, sys
sig_re = re.compile(r'(BATCH-[A-Z0-9]+-(?:DONE|HELD)): <([A-Z_]+)>')   # -HELD: FR 보류 신호(20261009) — 받는 쪽이 없던 halt 를 신호로 만들었다
emit_, watch = {}, {}   # token -> set(suffix)
for path in glob.glob('skills/*/SKILL.md'):
    for line in open(path, encoding='utf-8'):
        for m in sig_re.finditer(line):
            emit_.setdefault(m.group(1), set()).add(m.group(2))
for path in glob.glob('commands/*.md'):
    for line in open(path, encoding='utf-8'):
        for m in sig_re.finditer(line):
            watch.setdefault(m.group(1), set()).add(m.group(2))
tokens = sorted(set(emit_) | set(watch))
if not tokens:
    print("0 signals"); sys.exit(0)
issues = []
for t in tokens:
    e, w = emit_.get(t, set()), watch.get(t, set())
    if not e:
        issues.append(f"{t}: 오케스트레이터 감시하나 skill 방출 없음(고아 watcher)")
    if not w:
        issues.append(f"{t}: skill 방출하나 오케스트레이터 감시 없음(고아 emitter)")
    sfx = e | w
    if len(sfx) > 1:
        issues.append(f"{t}: suffix 불일치 {sorted(sfx)} (emit↔watch drift)")
if issues:
    print('; '.join(issues)); sys.exit(1)
print(f"{len(tokens)} signals OK")
PYEOF
)
  if [ $? -eq 0 ]; then emit contract_consistency OK "$ct_out"; else emit contract_consistency FAIL "$ct_out"; fi
fi

# ── hardgate_classified — 클래스 A 재발 방지 메타 규칙 (20260806) ──────────────
# 20260806 감사에서 **동일 클래스 결함 9건**이 나왔다: SKILL.md 가 HARD 를 선언하는데
#   그것을 검사하는 구현이 0곳(foundation manifest·재사용·회귀 AC·advisor 협의·
#   DAST 소유확인·브랜치 삭제·B/C 존재·화면 8섹션·analyzing baseline).
#   개별 수정만으로는 **다음에 또 나온다** — 선언 시점에 결정을 강제하는 규칙이 필요하다.
#
# 규칙: `<HARD-GATE>` 형식 블록을 가진 skill 은 그 게이트를 **분류**해야 한다.
#   ① `판정 SoT = <스크립트>` — 기계 판정 (스크립트 실재도 함께 검사)
#   ② `기계화 불가` 또는 `대화 게이트` — 사유와 함께 명시 (사용자 승인 등)
#   둘 다 없으면 FAIL — "선언만 하고 구현 여부를 결정하지 않은" 상태를 금지한다.
hg_fail=()
for f in skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  grep -q '<HARD-GATE>' "$f" 2>/dev/null || continue
  name=$(basename "$(dirname "$f")")
  if ! grep -qE '판정 SoT|기계화 불가|대화 게이트' "$f" 2>/dev/null; then
    hg_fail+=("$name(미분류)")
    continue
  fi
  # 판정 SoT 를 주장하면 그 스크립트가 실재해야 한다 (dangling 인용 금지)
  while IFS= read -r sp; do
    [ -n "$sp" ] || continue
    [ -f "$sp" ] || hg_fail+=("$name(SoT 부재:$sp)")
  done <<EOF
$(grep -oE 'scripts/_internal/check-[A-Za-z0-9._-]+\.sh' "$f" 2>/dev/null | sort -u)
EOF
done
  # ── 래칫: 마커 없이 산문으로 HARD GATE 를 선언하는 skill 감시 ──
  # 규칙이 꺾쇠 마커 보유 파일만 봤기 때문에 **회피법이 "마커를 안 쓰는 것"** 이었다.
  # 전부를 규칙 안으로 넣는 대신(마커를 기계적으로 붙여 경고를 끄는 ritual 이 된다 —
  #   §auto 자기발급 면제표 선례) 현 상태를 baseline 에 이름으로 고정하고 증가만 막는다.
  # ★ 검출은 **파일 단위**다(clarify Q2) — 선언형 패턴만 세면 새 표기법을 놓쳐 조용히
  #   미탐한다. 오탐은 baseline 1줄 등록으로 끝나고 그 결정이 diff 에 남는다.
  hg_marker=0; hg_outside=0
  for f in skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    grep -q '<HARD-GATE>' "$f" 2>/dev/null && hg_marker=$((hg_marker+1))
  done
  # ★ 검출은 _hardgate_outside_skills() 하나만 쓴다 — writer 와 같은 판정(위 정의 참조).
  #   grep -qF 의 **닫는 따옴표**가 계약이다: 없으면 baseline 이름의 접두인 신규 skill
  #   (`planning-k` ⊂ `planning-ko`)이 등재된 것처럼 매치돼 조용히 숨는다 (H6.b 가 잠금).
  while IFS= read -r sn; do
    [ -n "$sn" ] || continue
    hg_outside=$((hg_outside+1))
    if [ -f "$HARDGATE_BASELINE" ] \
       && ! grep -qF "\"skill\":\"$sn\"" "$HARDGATE_BASELINE" 2>/dev/null; then
      hg_fail+=("$sn(래칫: baseline 밖 신규 산문 HARD GATE — 마커+분류를 달거나 --update-baseline 으로 등록)")
    fi
  done < <(_hardgate_outside_skills)
  hg_total=$(find skills -name SKILL.md | wc -l | tr -d ' ')
  hg_note="마커 ${hg_marker}/${hg_total} · 규칙밖 ${hg_outside}"
  if [ ! -f "$HARDGATE_BASELINE" ]; then
    # baseline 부재는 SKIP 이다 — FAIL 이 아니다. validate-structure 는 sandbox 최소 트리에서도
    #   돌고, 거기서 FAIL 을 내면 무관한 케이스가 red 가 된다(skill_size 와 동일 관할 규약).
    #   실 repo 삭제는 test-hardgate-ratchet H1.a 가 잡는다.
    emit hardgate_classified SKIP ".hardgate-baseline 부재 — --update-baseline 으로 생성 ($hg_note)"
    hg_skip=1
  fi

# ★ baseline 부재(SKIP)라도 **기존 마커 검사의 FAIL 은 삼키지 않는다** — FR-6 은 마커
#   검사 무변경을 요구하고, 래칫 baseline 유무는 그것과 독립이다(plan-review 2회차 제안).
if [ "${hg_skip:-0}" = "1" ] && [ ${#hg_fail[@]} -eq 0 ]; then
  :
elif [ ${#hg_fail[@]} -eq 0 ]; then
  emit hardgate_classified OK "$hg_note"
else
  emit hardgate_classified FAIL "${hg_fail[*]} ($hg_note)"
fi

# ── skill_size — SKILL.md 크기 래칫 (20260828-skill-size-ratchet) ──────────────
# 초과 = FAIL. 늘리려면 --update-baseline 으로 명시 갱신하고 diff 로 의도를 남긴다.
if ! command -v jq >/dev/null 2>&1; then
  emit skill_size SKIP "jq 미설치 — 한계 고백"
elif [ ! -f "$SKILL_BASELINE" ]; then
  # baseline 부재는 SKIP 이다 — FAIL 이 아니다. validate-structure 는 sandbox 최소 트리에서도
  #   돌고(test-validate-structure 가 그렇게 검증한다), 거기서 FAIL 을 내면 무관한 케이스가 red 가 된다.
  #   "실 repo 에서 baseline 이 사라지는" 위험은 여기가 아니라 test-skill-size-ratchet T1.a 가 잠근다
  #   (그쪽은 실 트리를 보므로 삭제 시 FAIL). 게이트마다 관할을 지킨다.
  emit skill_size SKIP ".skill-size-baseline 부재 — --update-baseline 으로 생성 (실 repo 부재는 test-skill-size-ratchet T1.a 가 적발)"
else
  ss_fail=()
  # 신규 skill 무기록 누수 차단 — baseline 에 없는 skill 은 래칫 밖이라 무제한이 된다
  while IFS= read -r sf; do
    sn=$(basename "$(dirname "$sf")")
    rec=$(jq -sr --arg s "$sn" '[.[] | select(.skill == $s)] | .[0] // empty' "$SKILL_BASELINE")
    if [ -z "$rec" ]; then ss_fail+=("$sn: baseline 무기록"); continue; fi
    ab=$(wc -c <"$sf" | tr -d ' '); al=$(wc -l <"$sf" | tr -d ' ')
    eb=$(printf '%s' "$rec" | jq -r '.bytes'); el=$(printf '%s' "$rec" | jq -r '.lines')
    [ "$ab" -gt "$eb" ] && ss_fail+=("$sn: ${ab}B > ${eb}B")
    [ "$al" -gt "$el" ] && ss_fail+=("$sn: ${al}줄 > ${el}줄")
  done < <(find skills -name SKILL.md | sort)
  # chain 집계 — 개별이 다 통과해도 총량이 늘 수 있다(작은 skill 여러 개로 분산)
  cb=$(jq -sr '[.[] | select(.chain_bytes)] | .[0].chain_bytes // empty' "$SKILL_BASELINE")
  cl=$(jq -sr '[.[] | select(.chain_bytes)] | .[0].chain_lines // empty' "$SKILL_BASELINE")
  acb=0; acl=0
  while IFS= read -r cs; do
    cp="skills/$cs/SKILL.md"; [ -f "$cp" ] || continue
    acb=$((acb + $(wc -c <"$cp" | tr -d ' ')))
    acl=$((acl + $(wc -l <"$cp" | tr -d ' ')))
  done < <(_chain_skills)
  if [ -z "$cb" ]; then ss_fail+=("chain 집계 baseline 무기록")
  else
    [ "$acb" -gt "$cb" ] && ss_fail+=("chain 총량: ${acb}B > ${cb}B")
    [ "$acl" -gt "$cl" ] && ss_fail+=("chain 총량: ${acl}줄 > ${cl}줄")
  fi
  if [ ${#ss_fail[@]} -eq 0 ]; then
    emit skill_size OK "chain ${acb}B/${acl}줄"
  else
    emit skill_size FAIL "${ss_fail[*]} — 의도한 증가면 --update-baseline"
  fi
fi

# 출력
if [ "$JSON_MODE" -eq 1 ]; then
  printf '{"fails":%d,"checks":[' "$FAILS"
  i=0
  for r in "${RESULTS[@]}"; do
    name=${r%%|*}; rest=${r#*|}; status=${rest%%|*}; detail=${rest#*|}
    [ $i -gt 0 ] && printf ','
    esc=$(printf '%s' "$detail" | python3 -c "import sys,json; sys.stdout.write(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '""')
    printf '{"name":"%s","status":"%s","detail":%s}' "$name" "$status" "$esc"
    i=$((i+1))
  done
  printf ']}\n'
else
  for r in "${RESULTS[@]}"; do
    name=${r%%|*}; rest=${r#*|}; status=${rest%%|*}; detail=${rest#*|}
    case "$status" in
      OK)   echo "✅ $name: OK${detail:+ ($detail)}" ;;
      FAIL) echo "❌ $name: FAIL — $detail" ;;
      SKIP) echo "⚠️  $name: SKIP — $detail" ;;
      INFO) echo "ℹ️  $name: $detail" ;;
    esac
  done
fi

[ "$FAILS" -eq 0 ] && exit 0 || exit 1
