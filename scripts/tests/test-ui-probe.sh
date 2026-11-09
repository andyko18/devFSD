#!/usr/bin/env bash
# test-ui-probe.sh — 브라우저 점검 하네스 (20261110-ui-probe)
#   하류 실측: 화면 FID 의 통합 테스트가 브라우저를 돌리지 않고 PASS(6/9) · 화면 이미지 0/35 · 반응형·접근성 실행 검증 0.
#   ① ui-probe.cjs: 인자 오류 rc 2 · 도구 없음 SKIP(NO_TOOL) rc 3(PASS 위장 금지)
#   ② Playwright 가 있는 환경이면 실제로: 깨끗한 화면 PASS · 넘침+콘솔 오류+접근성 critical FAIL · 3폭 PNG
#   ③ integration-test-ko 브라우저 줄 의무 · demo-ko 가 PNG 를 보여 준다
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P="$PLUGIN/scripts/_internal/ui-probe.cjs"
TMP=$(mktemp -d) || exit 1
SRV=""
trap 'if [ -n "$SRV" ]; then kill "$SRV" 2>/dev/null; fi; rm -rf "$TMP"' EXIT
ok() { PASS=$((PASS+1)); echo "PASS $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL $1 — $2"; }
SKIPPED=0
sk() { SKIPPED=$((SKIPPED+1)); echo "SKIP $1"; }
# has: 런타임에 조합되는 출력 줄(예: "기록 안 함: ${이유}")은 소스에 통째 리터럴이 없어 grep 리터럴로 잠그면 사전검사가 오판한다 — bash 패턴 비교로 본다
has() { [[ "$1" == *"$2"* ]]; }

if ! command -v node >/dev/null 2>&1; then echo "SKIP 전체 (node 없음)"; echo "── test-ui-probe: PASS=$PASS FAIL=$FAIL SKIP=$SKIPPED ──"; exit 0; fi

# U1 — 인자 오류 rc 2
node "$P" >/dev/null 2>&1; [ $? -eq 2 ] && ok "U1 인자 없음 → rc 2" || no "U1" "rc 2 아님"

# U2 — Playwright 를 찾지 못하면 SKIP(NO_TOOL) rc 3 · 설치 안내 · 파일 없음
mkdir -p "$TMP/empty"
out=$(cd "$TMP/empty" && DEVFSD_UI_HARNESS_DIR="$TMP/empty" node "$P" --out "$TMP/o2" "file://$TMP/x.html" 2>&1); rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q '^UI-PROBE: SKIP (NO_TOOL' && printf '%s' "$out" | grep -qF 'npm install --prefix ~/.cache/devfsd/ui-harness' && [ ! -e "$TMP/o2/ui-probe.json" ] \
  && ok "U2 도구 없음 → SKIP(NO_TOOL) rc 3 · 설치 안내 · 결과 파일 없음" || no "U2" "rc=$rc out=[$out]"

# U3 — 실제 브라우저 (Playwright 가 있는 환경만 — 없으면 SKIP 을 적고 위장하지 않는다)
cat > "$TMP/good.html" <<'EOF'
<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>정상</title></head>
<body><main><h1>재고</h1><label for="q">검색</label><input id="q"><button type="button">발주</button></main></body></html>
EOF
cat > "$TMP/bad.html" <<'EOF'
<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>문제</title></head>
<body><main><h1>재고</h1><div style="width:900px">넓은 표</div><button type="button"></button></main><script>console.error("load failed")</script></body></html>
EOF
HAVE_BROWSER=0
out=$(node "$P" --out "$TMP/og" "file://$TMP/good.html" 2>&1); rc=$?
if [ "$rc" -eq 3 ]; then sk "U3 (이 환경에 Playwright·브라우저 없음: $(printf '%s' "$out" | head -1))"
else
  HAVE_BROWSER=1
  [ "$rc" -eq 0 ] && printf '%s\n' "$out" | sed -n 1p | grep -qE '^UI-PROBE: PASS \(1화면·3폭 · 넘침 0 · 콘솔 오류 0 · (접근성 심각 0|접근성 SKIP\(axe-core 없음\))\)$' && [ "$(printf '%s\n' "$out" | grep -vc '^  png: ')" = 1 ] && [ -s "$TMP/og/good@375.png" ] && [ -s "$TMP/og/good@768.png" ] && [ -s "$TMP/og/good@1280.png" ] && [ -s "$TMP/og/ui-probe.json" ] \
    && ok "U3a 깨끗한 화면 → PASS rc 0 · 3폭 PNG · ui-probe.json" || no "U3a" "rc=$rc out=[$out]"
  out=$(node "$P" --out "$TMP/ob" "file://$TMP/bad.html" 2>&1); rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '^UI-PROBE: FAIL' && printf '%s' "$out" | grep -qF 'bad@375 가로 넘침' \
    && printf '%s' "$out" | grep -qF '콘솔 오류: load failed' && ! printf '%s' "$out" | grep -qF 'bad@1280 가로 넘침' \
    && ok "U3b 넘침(375·768만)·콘솔 오류 → FAIL rc 1" || no "U3b" "rc=$rc out=[$out]"
  if printf '%s' "$out" | grep -qF '접근성 SKIP'; then sk "U3c (axe-core 없음)"
  else printf '%s' "$out" | grep -qE 'bad@1280 접근성 critical button-name' && ok "U3c 이름 없는 버튼 → 접근성 critical" || no "U3c" "out=[$out]"; fi
fi

# U4 — 연결: integration-test-ko 브라우저 줄 의무 · demo-ko PNG 표시
INT="$PLUGIN/skills/integration-test-ko/SKILL.md"; DEMO="$PLUGIN/skills/demo-ko/SKILL.md"
miss=""; for n in 'ui-probe.cjs' '**브라우저**: 실행(' '**브라우저**: 미실행(NO_TOOL|NO_ENV|NO_SERVER|USER_SKIP' 'PASS 로 적지 않는다' '375·768·1280'; do grep -qF -- "$n" "$INT" || miss="$miss [$n]"; done
[ -z "$miss" ] && ok "U4a integration-test-ko — 하네스 실행 · 브라우저 줄 의무 · SKIP 위장 금지" || no "U4a" "없음:$miss"
grep -qF '.specops/<FID>/ui/*.png' "$DEMO" && grep -qF 'UI-PROBE:' "$DEMO" && ok "U4b demo-ko — 하네스 PNG·판정 줄을 보여 준다" || no "U4b" "연결 없음"

# U5 — 상태 모듈 순수 로직 (브라우저 불필요)
S="$PLUGIN/scripts/_internal/ui-probe-state.cjs"
printf '{"baseUrl":"http://127.0.0.1:3000","routes":["/a","/b"],"startCmd":"npm run dev"}' > "$TMP/m-ok.json"
printf '{bad' > "$TMP/m-bad.json"
printf '{"baseUrl":"http://h:1","routes":[]}' > "$TMP/m-empty.json"
printf '{"baseUrl":"http://h:1/x","routes":["/a"]}' > "$TMP/m-path.json"
printf '{"baseUrl":"http://h:1/","routes":["/a"]}' > "$TMP/m-slash.json"
printf '{"routes":["/a"]}' > "$TMP/m-nourl.json"
printf '[]' > "$TMP/m-arr.json"
printf '{"baseUrl":"http://h:1","routes":[1]}' > "$TMP/m-int.json"
printf '{"baseUrl":"http://h:1","routes":["a"]}' > "$TMP/m-rel.json"
printf '{"baseUrl":"ftp://h:1","routes":["/a"]}' > "$TMP/m-ftp.json"
got=$(node -e 'const s=require(process.argv[1]);console.log(process.argv.slice(2).map((f)=>s.loadMemory(f).state).join(","))' "$S" "$TMP/m-ok.json" "$TMP/m-bad.json" "$TMP/m-empty.json" "$TMP/m-path.json" "$TMP/m-slash.json" "$TMP/m-nourl.json" "$TMP/m-arr.json" "$TMP/m-int.json" "$TMP/m-rel.json" "$TMP/m-ftp.json" "$TMP/none.json" 2>&1)
[ "$got" = "ok,broken,broken,broken,broken,broken,broken,broken,broken,broken,missing" ] && ok "U5a loadMemory — 정상 1 · 깨짐 9종(JSON·빈 routes·경로 든 baseUrl·끝 /·baseUrl 없음·비객체·숫자 route·상대 route·ftp) · 없음" || no "U5a" "got=[$got]"

got=$(node -e 'const s=require(process.argv[1]);const r=[
s.mergeMemory({baseUrl:"http://a:1",routes:["/a","/b"],startCmd:"x"},{origin:"http://a:2",routes:["/b","/c"],startCmd:"",storageState:""}),
s.mergeMemory({baseUrl:"http://a:1",routes:["/a"],startCmd:"x",storageState:"s1"},{origin:"http://a:1",routes:["/a"],startCmd:"y",storageState:""}),
s.mergeMemory(null,{origin:"http://a:1",routes:["/a"],startCmd:"",storageState:"s2"})];console.log(JSON.stringify(r))' "$S" 2>&1)
[ "$got" = '[{"baseUrl":"http://a:2","routes":["/a","/b","/c"],"startCmd":"x"},{"baseUrl":"http://a:1","routes":["/a"],"startCmd":"y","storageState":"s1"},{"baseUrl":"http://a:1","routes":["/a"],"storageState":"s2"}]' ] \
  && ok "U5b mergeMemory — routes 합집합(기존 뒤에 새 것) · baseUrl 갱신 · 플래그 값이 기존 값을 이김 · 없으면 기존 값 유지 · storageState 병합" || no "U5b" "got=[$got]"

got=$(node -e 'const s=require(process.argv[1]);const a=s.describeUrls(["http://h:1/a?x=1#t","http://h:1/b"]);const b=s.describeUrls(["http://h:1/a","http://g:1/b"]);const c=s.describeUrls(["file:///x/a.html"]);const d=s.describeUrls(["http://h:1/a","file:///x/a.html"]);const e=s.describeUrls(["http://h:1/a#x","http://h:1/a"]);console.log(JSON.stringify([a.ok,a.routes,b.ok,b.reason,c.ok,d.ok,e.routes]))' "$S" 2>&1)
[ "$got" = '[true,["/a?x=1","/b"],false,"origin 이 하나가 아니다",false,false,["/a"]]' ] && ok "U5c describeUrls — 쿼리 포함·해시 제외·중복 제거 · origin 혼합·file://·http+file 혼합 거부" || no "U5c" "got=[$got]"

printf '{"home|button-name":2,"_widest":1280}' > "$TMP/b-ok.json"; printf '{"_widest":1280}' > "$TMP/b-zero.json"
printf '{}' > "$TMP/b-nowidest.json"; printf '[]' > "$TMP/b-arr.json"; printf '{"a|b":"2","_widest":1280}' > "$TMP/b-str.json"
printf '{"a|b":0,"_widest":1280}' > "$TMP/b-zerov.json"; printf '{"a|b":1.5,"_widest":1280}' > "$TMP/b-float.json"; printf '{bad' > "$TMP/b-bad.json"
printf '{"_widest":"1280"}' > "$TMP/b-wstr.json"; printf '{"_widest":0}' > "$TMP/b-w0.json"
got=$(node -e 'const s=require(process.argv[1]);console.log(process.argv.slice(2).map((f)=>s.parseBaseline(f).state).join(","))' "$S" "$TMP/b-ok.json" "$TMP/b-zero.json" "$TMP/b-nowidest.json" "$TMP/b-arr.json" "$TMP/b-str.json" "$TMP/b-zerov.json" "$TMP/b-float.json" "$TMP/b-bad.json" "$TMP/b-wstr.json" "$TMP/b-w0.json" "$TMP/none.json" 2>&1)
[ "$got" = "ok,ok,broken,broken,broken,broken,broken,broken,broken,broken,missing" ] && ok "U5d parseBaseline — 형식 위반 8종(_widest 없음·비객체·문자열·0·소수·JSON·_widest 문자열·_widest 0) broken · 위반 0(_widest 만)은 정상" || no "U5d" "got=[$got]"

got=$(node -e 'const s=require(process.argv[1]);const b={"a|x":2,"_widest":1280};const c1=s.compareBaseline(b,{"a|x":2,"a|y":1});const c2=s.compareBaseline(b,{"a|x":3});const c3=s.compareBaseline(b,{"a|x":1});
const m1=s.mergeBaseline({"a|x":2,"b|y":1,"_widest":1280},["a"],{"a|z":1},1280);const m2=s.mergeBaseline(null,["a"],{"a|z":1},768);
console.log(JSON.stringify([c1.fresh.map((f)=>f.key),c1.same,c2.fresh[0],c3.fresh.length,c3.same,m1,m2]))' "$S" 2>&1)
[ "$got" = '[["a|y"],1,{"key":"a|x","cur":3,"prev":2},0,1,{"_widest":1280,"a|z":1,"b|y":1},{"_widest":768,"a|z":1}]' ] && ok "U5e compare(새 키·증가만 fresh · 감소는 통과) · merge(점검한 화면만 교체, 나머지 보존, 정렬)" || no "U5e" "got=[$got]"

: > "$TMP/afile"
got=$(node -e 'const s=require(process.argv[1]);const w=s.writeJson(process.argv[2]+"/x.json",{});const r=s.readJson(process.argv[2]+"/x.json");console.log(JSON.stringify([w.ok,w.reason.length>0,r.state]))' "$S" "$TMP/afile" 2>&1)
[ "$got" = '[false,true,"missing"]' ] && ok "U5f writeJson 실패는 ok:false+사유 · 부모가 파일인 경로(ENOTDIR)는 없음으로 읽는다" || no "U5f" "got=[$got]"

echo "── test-ui-probe: PASS=$PASS FAIL=$FAIL SKIP=$SKIPPED ──"
[ "$FAIL" -eq 0 ]
