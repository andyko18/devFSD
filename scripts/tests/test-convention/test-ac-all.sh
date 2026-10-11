#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$PLUGIN"

# ----- AC 테스트 추가 영역 시작 -----

# T2.a AC-2: templates/test-conventions-bash.md H2 6 섹션
f=templates/test-conventions-bash.md
if [ -f "$f" ]; then
  miss=""
  for sec in '^## 1\. 위치$' '^## 2\. 명명$' '^## 3\. 실행권한$' '^## 4\. 헤더$' '^## 회귀 금지 체크리스트$' '^## 참조$'; do
    grep -qE "$sec" "$f" || miss="$miss $sec"
  done
  if [ -z "$miss" ]; then
    PASS=$((PASS+1)); echo "PASS T2.a AC-2 H2 6 섹션"
  else
    FAIL=$((FAIL+1)); echo "FAIL T2.a AC-2 (miss:$miss)"
  fi
else
  FAIL=$((FAIL+1)); echo "FAIL T2.a AC-2 (파일 없음)"
fi

# T3.a AC-9 부분 1: §1·§2 본문에 "내부 예시" 등장
f=templates/test-conventions-bash.md
if [ -f "$f" ]; then
  hits=0
  for start in '^## 1\. 위치$' '^## 2\. 명명$'; do
    body=$(awk -v re="$start" '$0 ~ re {p=1; next} p && /^## / {exit} p' "$f")
    echo "$body" | grep -q '내부 예시' && hits=$((hits+1))
  done
  if [ "$hits" -ge 2 ]; then
    PASS=$((PASS+1)); echo "PASS T3.a AC-9 §1·§2 내부 예시"
  else
    FAIL=$((FAIL+1)); echo "FAIL T3.a AC-9 (hits=$hits)"
  fi
else
  FAIL=$((FAIL+1)); echo "FAIL T3.a AC-9 (파일 없음)"
fi

# T4.a AC-9 §3 + AC-10 조건 2·3
f=templates/test-conventions-bash.md
if [ -f "$f" ]; then
  sec3=$(awk '/^## 3\. 실행권한$/{p=1; next} p && /^## / {exit} p' "$f")
  t4a=$(echo "$sec3" | grep -q 'Universal 강제' && echo 1 || echo 0)
  t4b=$(echo "$sec3" | grep -qE '(shebang (직후|바로 다음)|첫[[:space:]]+(두[[:space:]]+)?줄|L2|두 번째 줄)' && echo 1 || echo 0)
  t4c=$(echo "$sec3" | awk '/^```/{p=!p; next} p' | grep -q '# library-only' && echo 1 || echo 0)
  if [ "$t4a$t4b$t4c" = "111" ]; then
    PASS=$((PASS+1)); echo "PASS T4.a AC-9/10 §3 Universal+위치+코드예시"
  else
    FAIL=$((FAIL+1)); echo "FAIL T4.a (a=$t4a b=$t4b c=$t4c)"
  fi
else
  FAIL=$((FAIL+1)); echo "FAIL T4.a (파일 없음)"
fi

# T5.a AC-9 §4: shebang Universal + 내부 예시
f=templates/test-conventions-bash.md
if [ -f "$f" ]; then
  sec4=$(awk '/^## 4\. 헤더$/{p=1; next} p && /^## / {exit} p' "$f")
  t5a=$(echo "$sec4" | grep -qF '#!/usr/bin/env bash' && echo 1 || echo 0)
  t5b=$(echo "$sec4" | grep -q '내부 예시' && echo 1 || echo 0)
  if [ "$t5a$t5b" = "11" ]; then
    PASS=$((PASS+1)); echo "PASS T5.a AC-9 §4 shebang+내부 예시"
  else
    FAIL=$((FAIL+1)); echo "FAIL T5.a (a=$t5a b=$t5b)"
  fi
else
  FAIL=$((FAIL+1)); echo "FAIL T5.a (파일 없음)"
fi

# T6.a AC-5 부분 1: templates §참조 에 SKILL.md 경로
f=templates/test-conventions-bash.md
if [ -f "$f" ]; then
  secref=$(awk '/^## 참조$/{p=1; next} p && /^## / {exit} p' "$f")
  if echo "$secref" | grep -q 'skills/decomposing-ko/SKILL\.md'; then
    PASS=$((PASS+1)); echo "PASS T6.a AC-5 templates→SKILL 참조"
  else
    FAIL=$((FAIL+1)); echo "FAIL T6.a AC-5 templates→SKILL 참조 부재"
  fi
else
  FAIL=$((FAIL+1)); echo "FAIL T6.a AC-5 (파일 없음)"
fi

# T7.a AC-7: frontmatter description 에 "테스트 컨벤션"
f=skills/decomposing-ko/SKILL.md
desc=$(awk '/^---$/{c++} c==1 && /^description:/' "$f")
if echo "$desc" | grep -q '테스트 컨벤션'; then
  PASS=$((PASS+1)); echo "PASS T7.a AC-7 description 확장"
else
  FAIL=$((FAIL+1)); echo "FAIL T7.a AC-7 description 에 '테스트 컨벤션' 부재"
fi

# T8.a AC-1: §테스트 컨벤션 (bash) + 4 항목 + 강도 두 값
f=skills/decomposing-ko/SKILL.md
cnt=$(grep -c '^## 테스트 컨벤션 (bash)$' "$f")
section=$(awk '/^## 테스트 컨벤션 \(bash\)$/{p=1; next} p && /^## / {exit} p' "$f")
rows_ok=1
for kw in 위치 명명 실행권한 헤더; do
  echo "$section" | grep -qE "^\|[^|]*${kw}" || rows_ok=0
done
uni=$(echo "$section" | grep -c 'Universal 강제')
ex=$(echo "$section" | grep -c '내부 예시')
if [ "$cnt" = "1" ] && [ "$rows_ok" = "1" ] && [ "$uni" -ge 1 ] && [ "$ex" -ge 1 ]; then
  PASS=$((PASS+1)); echo "PASS T8.a AC-1 §테스트 컨벤션 섹션"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.a AC-1 (cnt=$cnt rows=$rows_ok uni=$uni ex=$ex)"
fi

# T8.b AC-5 부분 2: SKILL §테스트 컨벤션 에서 templates 경로 참조
if echo "$section" | grep -q 'templates/test-conventions-bash\.md'; then
  PASS=$((PASS+1)); echo "PASS T8.b AC-5 SKILL→templates 참조"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.b AC-5 SKILL→templates 참조 부재"
fi

# T9.a AC-4: 체크리스트 Step 6.5
f=skills/decomposing-ko/SKILL.md
checklist=$(awk '/^## 체크리스트$/{p=1; next} p && /^## / {exit} p' "$f")
t9a=$(echo "$checklist" | grep -qE '(6\.5|테스트 컨벤션 점검)' && echo 1 || echo 0)
t9b=$(echo "$checklist" | grep -q 'test-conventions-bash\.md' && echo 1 || echo 0)
if [ "$t9a$t9b" = "11" ]; then
  PASS=$((PASS+1)); echo "PASS T9.a AC-4 체크리스트 Step 6.5"
else
  FAIL=$((FAIL+1)); echo "FAIL T9.a AC-4 (a=$t9a b=$t9b)"
fi

# T10.a AC-3: HARD-GATE 3 조건
f=skills/decomposing-ko/SKILL.md
gate=$(awk '/<HARD-GATE>/,/<\/HARD-GATE>/' "$f")
t10a=$(echo "$gate" | grep -qE '(exec-bit|실행권한)' && echo 1 || echo 0)
t10b=$(echo "$gate" | grep -q 'shebang' && echo 1 || echo 0)
t10c=$(echo "$gate" | grep -qE '(library-only|library only)' && echo 1 || echo 0)
if [ "$t10a$t10b$t10c" = "111" ]; then
  PASS=$((PASS+1)); echo "PASS T10.a AC-3 HARD-GATE 3 조건"
else
  FAIL=$((FAIL+1)); echo "FAIL T10.a AC-3 (a=$t10a b=$t10b c=$t10c)"
fi

# T10.b AC-10 조건 1: HARD-GATE 에 "# library-only" 리터럴
if echo "$gate" | grep -q '# library-only'; then
  PASS=$((PASS+1)); echo "PASS T10.b AC-10 조건 1 마커 리터럴"
else
  FAIL=$((FAIL+1)); echo "FAIL T10.b AC-10 조건 1 리터럴 부재"
fi

# ----- AC 테스트 추가 영역 끝 -----

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
