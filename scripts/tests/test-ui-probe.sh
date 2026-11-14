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

# U6 — 인자·기록 읽기·중복·로그인 상태 (Playwright 보다 앞에서 결정되므로 브라우저 없이도 돈다)
node "$P" --out "$TMP/o6" --a11y-baseline-update "file://$TMP/x.html" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "U6a --a11y-baseline-update 만 주면 rc 2" || no "U6a" "rc=$rc"

out=$(node "$P" --out "$TMP/o6" --memory "$TMP/none.json" 2>&1); rc=$?
out2=$(node "$P" --out "$TMP/o6" --memory "$TMP/m-bad.json" 2>&1); rc2=$?
[ "$rc" -eq 2 ] && has "$out" '기록 없음:' && [ "$rc2" -eq 2 ] && has "$out2" '기록을 읽지 못함:' \
  && ok "U6b URL 없이 기록만 — 없음/깨짐을 구분해 rc 2" || no "U6b" "rc=$rc [$out] rc2=$rc2 [$out2]"

mkdir -p "$TMP/d1" "$TMP/d2"; : > "$TMP/d1/x.html"; : > "$TMP/d2/x.html"
c1=$(node "$P" --out "$TMP/o6" --memory "$TMP/mm.json" http://127.0.0.1:9/ http://127.0.0.1:9/home 2>&1); r1=$?
c2=$(node "$P" --out "$TMP/o6" --memory "$TMP/mm.json" "http://127.0.0.1:9/list?tab=a" "http://127.0.0.1:9/list?tab=b" 2>&1); r2=$?
c3=$(node "$P" --out "$TMP/o6" --a11y-baseline "$TMP/bb.json" http://127.0.0.1:9/a/b http://127.0.0.1:9/a-b 2>&1); r3=$?
c4=$(node "$P" --out "$TMP/o6" --mock "$TMP/d1/x.html" --mock "$TMP/d2/x.html" http://127.0.0.1:9/q 2>&1); r4=$?
[ "$r1" -eq 2 ] && has "$c1" '화면 이름 중복: home' && [ "$r2" -eq 2 ] && has "$c2" '화면 이름 중복: list' && [ "$r3" -eq 2 ] && has "$c3" '화면 이름 중복: a-b' \
  && [ "$r4" -eq 2 ] && has "$c4" '화면 이름 중복: x' && [ ! -e "$TMP/mm.json" ] \
  && ok "U6c 새 플래그 + 화면 이름 중복 — / 와 /home · 쿼리만 다름 · /a/b 와 /a-b · 목업 이름 중복 → rc 2" || no "U6c" "r=$r1,$r2,$r3,$r4 [$c1|$c2|$c3|$c4]"

mkdir -p "$TMP/empty"
e1=$(DEVFSD_UI_HARNESS_DIR="$TMP/empty" node "$P" --out "$TMP/o6" http://127.0.0.1:9/ http://127.0.0.1:9/home 2>&1); q1=$?
e2=$(DEVFSD_UI_HARNESS_DIR="$TMP/empty" node "$P" --out "$TMP/o6" --mock "$TMP/d1/x.html" http://127.0.0.1:9/x 2>&1); q2=$?
[ "$q1" -eq 3 ] && has "$e1" 'NO_TOOL' && [ "$q2" -eq 3 ] && has "$e2" 'NO_TOOL' \
  && ok "U6d 중복 검사는 새 플래그가 있을 때만 — 플래그 없는 / 와 /home, 구현·목업 이름이 같은 쌍은 거부하지 않는다(rc 3 NO_TOOL)" || no "U6d" "q=$q1,$q2 [$e1|$e2]"

g1=$(node "$P" --out "$TMP/o6" http://127.0.0.1:9/a --memory 2>&1); s1=$?
g2=$(node "$P" --out "$TMP/o6" http://127.0.0.1:9/a --mock 2>&1); s2=$?
g3=$(node "$P" --out "$TMP/o6" http://127.0.0.1:9/a --a11y-baseline 2>&1); s3=$?
g4=$(node "$P" --out "$TMP/o6" --memory --start-cmd x http://127.0.0.1:9/a 2>&1); s4=$?
[ "$s4" -eq 2 ] && has "$g4" '--memory 에 값이 없다' && [ ! -e "$TMP/--start-cmd" ] && [ "$s1" -eq 2 ] && has "$g1" '--memory 에 값이 없다' && [ "$s2" -eq 2 ] && has "$g2" '--mock 에 값이 없다' && [ "$s3" -eq 2 ] && has "$g3" '--a11y-baseline 에 값이 없다' \
  && ok "U6e 값이 빠진 플래그는 rc 2 (조용히 꺼지지 않는다) · 값 자리에 다른 플래그가 오면 삼키지 않는다" || no "U6e" "s=$s1,$s2,$s3,$s4 [$g1|$g2|$g3|$g4]"

printf '{bad' > "$TMP/ss-bad.json"
printf '{"baseUrl":"http://127.0.0.1:9","routes":["/a"],"storageState":"%s"}' "$TMP/ss-none.json" > "$TMP/m-ss.json"
a1=$(node "$P" --out "$TMP/o6" --storage-state "$TMP/ss-none.json" "file://$TMP/x.html" 2>&1); r1=$?
a2=$(node "$P" --out "$TMP/o6" --storage-state "$TMP/ss-bad.json" "file://$TMP/x.html" 2>&1); r2=$?
a3=$(node "$P" --out "$TMP/o6" --memory "$TMP/m-ss.json" 2>&1); r3=$?
ne=1; for o in "$a1" "$a2" "$a3"; do printf '%s\n' "$o" | grep -q '^UI-PROBE: SKIP (NO_ENV' || ne=0; done
[ "$r1" -eq 3 ] && [ "$r2" -eq 3 ] && [ "$r3" -eq 3 ] && [ "$ne" = 1 ] && has "$a1" '찾지 못했다' && has "$a2" '읽지 못했다' \
  && ok "U6f 로그인 상태 파일 없음/깨짐/기록의 storageState 없음 → 모두 SKIP(NO_ENV) rc 3 · 원인 문구 구분 (NO_BROWSER 아님)" || no "U6f" "r=$r1,$r2,$r3 [$a1|$a2|$a3]"


# U8 — 판정·기록 로직 (가짜 Playwright: 브라우저 경계만 대체 — ui-probe.cjs 는 실물. Playwright 없는 CI 에서도 돈다)
FK="$TMP/fakepw"; mkdir -p "$FK/node_modules/playwright-core" "$FK/node_modules/axe-core"
: > "$FK/node_modules/axe-core/index.js"; : > "$FK/node_modules/axe-core/axe.min.js"
cat > "$FK/node_modules/playwright-core/index.js" <<'EOF'
// 가짜 Playwright — 화면별 결과는 FAKE_PW_FIX(slug → {fail, overflow, violations, layout, layoutThrow, layoutThrowAt, responses, requestfailed}), 컨텍스트마다 FAKE_PW_LOG 에 {width, storageState} 한 줄
const fs = require('fs'), path = require('path');
const FIX = process.env.FAKE_PW_FIX ? JSON.parse(fs.readFileSync(process.env.FAKE_PW_FIX, 'utf8')) : {};
const log = (o) => { if (process.env.FAKE_PW_LOG) fs.appendFileSync(process.env.FAKE_PW_LOG, JSON.stringify(o) + '\n'); };
const png = (w) => { const b = Buffer.alloc(33); Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex').copy(b); b.writeUInt32BE(w, 16); return b; };
const slug = (u) => { const p = new URL(u); return p.protocol === 'file:' ? path.basename(p.pathname).replace(/\.html?$/, '') : (p.pathname.replace(/^\/+|\/+$/g, '') || 'home'); };
exports.chromium = { launch: async () => ({
  newContext: async (opts) => {
    log({ width: opts.viewport.width, storageState: opts.storageState || '' });
    let url = '';
    const H = {};
    return { newPage: async () => ({
      on(ev, fn) { (H[ev] = H[ev] || []).push(fn); },
      goto: async (u) => {
        url = u; const f = FIX[slug(u)] || {};
        if (f.fail) throw new Error('boom');
        for (const r of f.responses || []) for (const fn of H.response || []) fn({ status: () => r.status, url: () => r.url, request: () => ({ method: () => r.method || 'GET' }) });
        for (const r of f.requestfailed || []) for (const fn of H.requestfailed || []) fn({ url: () => r.url, method: () => r.method || 'GET', failure: () => (r.error ? { errorText: r.error } : null) });
      },
      evaluate: async (fn, arg) => {
        const f = FIX[slug(url)] || {};
        if (typeof fn === 'function' && fn.name === 'measureLayout') {
          if (f.layoutThrow || f.layoutThrowAt === opts.viewport.width) throw new Error('layout boom');
          return 'layout' in f ? f.layout : { clip: [], overlap: [] };
        }
        return Array.isArray(arg) ? (f.violations || []) : Boolean(f.overflow);
      },
      screenshot: async ({ path: p }) => fs.writeFileSync(p, png(opts.viewport.width)),
      addScriptTag: async () => {},
    }), close: async () => {} };
  },
  close: async () => {},
}) };
EOF
FK2="$TMP/fakepw-noaxe"; mkdir -p "$FK2/node_modules"; cp -R "$FK/node_modules/playwright-core" "$FK2/node_modules/"
FIX="$TMP/fix.json"; LOGF="$TMP/fake.log"
fk() { DEVFSD_UI_HARNESS_DIR="$FK" FAKE_PW_FIX="$FIX" FAKE_PW_LOG="$LOGF" node "$P" "$@"; }
fix() { printf '%s' "$1" > "$FIX"; }
jstr() { node -e 'console.log(JSON.stringify(require(process.argv[1])))' "$1"; }
png_w() { node -e 'console.log(require("fs").readFileSync(process.argv[1]).readUInt32BE(16))' "$1"; }
BN1='{"id":"button-name","impact":"critical","nodes":1,"help":"H1"}'
BN2='{"id":"button-name","impact":"critical","nodes":2,"help":"H1"}'
IA1='{"id":"image-alt","impact":"critical","nodes":1,"help":"H2"}'
mkdir -p "$TMP/fm" "$TMP/fb" "$TMP/mk"

# U8a·U8b — 플래그 없는 실행은 v3.1.23 그대로 (AC-R-1) — 전체 출력 골든 · out 폴더 내용 · mocks 키 없음
fix '{}'; out=$(fk --out "$TMP/p1" http://h:1/a 2>&1); rc=$?
exp="UI-PROBE: PASS (1화면·3폭 · 넘침 0 · 콘솔 오류 0 · 접근성 심각 0)
  png: $TMP/p1/a@375.png
  png: $TMP/p1/a@768.png
  png: $TMP/p1/a@1280.png"
[ "$rc" -eq 0 ] && [ "$out" = "$exp" ] && [ "$(LC_ALL=C ls "$TMP/p1" | tr '\n' ' ')" = "a@1280.png a@375.png a@768.png ui-probe.json " ] && node -e 'process.exit("mocks" in require(process.argv[1]) ? 1 : 0)' "$TMP/p1/ui-probe.json" \
  && ok "U8a 플래그 없는 실행 — 전체 출력 골든 · out 폴더 내용 · mocks 키 없음" || no "U8a" "rc=$rc out=[$out]"
fix "{\"a\":{\"violations\":[$BN2]}}"; out=$(fk --out "$TMP/p2" http://h:1/a 2>&1); rc=$?
fix '{}'; out2=$(fk --out "$TMP/p3" http://h:1/ http://h:1/home 2>&1); rc2=$?
[ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = '  - a@1280 접근성 critical button-name(2곳): H1' ] && [ "$rc2" -eq 0 ] && has "$out2" '(2화면·3폭' \
  && ok "U8b 플래그 없는 위반 줄 형식(종전) · 중복 화면 이름도 거부하지 않는다" || no "U8b" "rc=$rc [$out] rc2=$rc2 [$out2]"
# U8b2 — 위반 줄 아래에 어느 요소인지(선택자)와 대비 색 쌍을 적는다 — 건수만으로는 고칠 곳을 찾지 못한다(20261114 실측: 경고색 토큰 1개가 3화면 7곳)
CC='{"id":"color-contrast","impact":"serious","nodes":7,"help":"H3","detail":[{"t":".badge-warning","c":"#9a6700 / #f3ede0 = 4.17 (기준 4.5:1)"},{"t":".unassigned","c":""},{"t":"a3","c":""},{"t":"a4","c":""},{"t":"a5","c":""},{"t":"a6","c":""}]}'
fix "{\"a\":{\"violations\":[$CC]}}"; out=$(fk --out "$TMP/p2b" http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = '  - a@1280 접근성 serious color-contrast(7곳): H3' ] \
  && [ "$(printf '%s\n' "$out" | sed -n 3p)" = '      · .badge-warning — 글자 / 배경 #9a6700 / #f3ede0 = 4.17 (기준 4.5:1)' ] && [ "$(printf '%s\n' "$out" | sed -n 4p)" = '      · .unassigned' ] \
  && [ "$(printf '%s\n' "$out" | grep -c '^      · ')" = 6 ] && [ "$(printf '%s\n' "$out" | sed -n 8p)" = '      · 외 2곳' ] \
  && node -e 'const r=require(process.argv[1]).results.find(x=>x.width===1280); process.exit(r.a11y[0].detail.length===6?0:1)' "$TMP/p2b/ui-probe.json" \
  && ok "U8b2 ★ 위반 요소 상세 — 선택자·대비 색 쌍 5줄까지 + '외 N곳' · json 에는 받은 대로" || no "U8b2" "rc=$rc [$out]"
fix "{\"a\":{\"violations\":[$CC]}}"; out=$(fk --out "$TMP/p2c" --a11y-baseline "$TMP/fb/cc.json" http://h:1/a 2>&1); rc=$?
printf '{"_widest":1280,"a|color-contrast":2}' > "$TMP/fb/cc2.json"; out2=$(fk --out "$TMP/p2d" --a11y-baseline "$TMP/fb/cc2.json" http://h:1/a 2>&1); rc2=$?
[ "$rc" -eq 0 ] && has "$out" '기준선 기록: a@1280 serious color-contrast(7곳)' && [ "$(printf '%s\n' "$out" | grep -c '^      · ')" = 6 ] && [ "$rc2" -eq 1 ] && has "$out2" 'color-contrast(7곳, 기준선 2곳)' && has "$out2" '      · .badge-warning — 글자 / 배경 #9a6700' \
  && ok "U8b3 기준선 기록 실행도 기록 줄 아래에 요소 상세를 낸다(막지는 않는다 — rc 0) · 기준선보다 늘어난 위반도 상세를 낸다" || no "U8b3" "rc=$rc [$out] rc2=$rc2 [$out2]"

# U8c — 기록(--memory)·로그인 상태
M="$TMP/fm/ui-probe.json"; SS="$TMP/ss.json"; echo '{"cookies":[],"origins":[]}' > "$SS"
fix '{}'
fk --out "$TMP/m1" --memory "$M" --start-cmd "npm run dev" http://h:1/a http://h:1/b >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(jstr "$M")" = '{"baseUrl":"http://h:1","routes":["/a","/b"],"startCmd":"npm run dev"}' ] && ok "U8c1 첫 실행 — 기록에 baseUrl·routes·startCmd" || no "U8c1" "rc=$rc $(jstr "$M" 2>&1)"
out=$(fk --out "$TMP/m2" --memory "$M" 2>&1); rc=$?
[ "$rc" -eq 0 ] && has "$out" 'UI-PROBE: PASS (2화면·3폭' && ok "U8c2 URL 없이 기록만 — 같은 두 화면을 다시 점검" || no "U8c2" "rc=$rc [$out]"
fk --out "$TMP/m3" --memory "$M" http://h:1/a >/dev/null 2>&1
[ "$(jstr "$M")" = '{"baseUrl":"http://h:1","routes":["/a","/b"],"startCmd":"npm run dev"}' ] && ok "U8c3 화면 하나만 준 실행도 routes 합집합(/b 보존) · startCmd 유지" || no "U8c3" "$(jstr "$M")"
M2="$TMP/fm/m2.json"
fk --out "$TMP/m4" --memory "$M2" --storage-state "$SS" http://h:1/a >/dev/null 2>&1
rm -f "$LOGF"; out=$(fk --out "$TMP/m5" --memory "$M2" 2>&1); rc=$?
[ "$(jstr "$M2")" = "{\"baseUrl\":\"http://h:1\",\"routes\":[\"/a\"],\"storageState\":\"$SS\"}" ] && [ "$rc" -eq 0 ] && [ "$(grep -cF "\"storageState\":\"$SS\"" "$LOGF")" = 3 ] \
  && ok "U8c4 storageState — 기록에 저장 · 다음 실행이 브라우저 컨텍스트 3폭 모두에 전달" || no "U8c4" "rc=$rc mem=$(jstr "$M2") log=$(cat "$LOGF")"
rm -f "$LOGF"; fk --out "$TMP/m6" http://h:1/a >/dev/null 2>&1
[ "$(grep -cF '"storageState":""' "$LOGF")" = 3 ] && ok "U8c5 플래그·기록이 없으면 컨텍스트에 storageState 를 넘기지 않는다" || no "U8c5" "log=$(cat "$LOGF")"
rm -f "$SS"; out=$(fk --out "$TMP/m7" --memory "$M2" 2>&1); rc=$?
[ "$rc" -eq 3 ] && has "$out" 'UI-PROBE: SKIP (NO_ENV' && ok "U8c6 기록이 가리키는 상태 파일을 지우면 SKIP(NO_ENV) rc 3" || no "U8c6" "rc=$rc [$out]"

before=$(cksum < "$M"); out=$(fk --out "$TMP/m8" --memory "$M" http://h:1/a http://g:1/b 2>&1)
[ "$(cksum < "$M")" = "$before" ] && has "$out" '기록 안 함: origin 이 하나가 아니다' && ok "U8c7 origin 이 둘이면 기록 불변 · 안내 줄" || no "U8c7" "[$out]"
out=$(fk --out "$TMP/m9" --memory "$TMP/fm/m3.json" "file://$TMP/good.html" 2>&1)
[ ! -e "$TMP/fm/m3.json" ] && has "$out" '기록 안 함: http(s) 가 아닌 화면이 있다' && ok "U8c8 file:// 만이면 기록 파일을 만들지 않는다" || no "U8c8" "[$out]"
printf '{bad' > "$TMP/fm/m4.json"; out=$(fk --out "$TMP/m10" --memory "$TMP/fm/m4.json" http://h:1/a 2>&1)
[ "$(cat "$TMP/fm/m4.json")" = '{bad' ] && has "$out" '기록 안 함: 기존 기록을 읽지 못함' && ok "U8c9 깨진 기록은 덮어쓰지 않고 안내" || no "U8c9" "[$out]"
fix '{"zzz":{"fail":true}}'; out=$(fk --out "$TMP/m11" --memory "$TMP/fm/m5.json" --a11y-baseline "$TMP/fb/b5.json" http://h:1/a http://h:1/zzz 2>&1); rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$TMP/fm/m5.json" ] && [ ! -e "$TMP/fb/b5.json" ] && has "$out" '기록 안 함: 열기에 실패한 화면이 있다' && has "$out" '기준선을 쓰지 않음: 열기에 실패한 화면이 있다' \
  && ok "U8c10 열기에 실패한 화면이 섞이면 기록·기준선을 쓰지 않는다" || no "U8c10" "rc=$rc [$out]"
fix '{}'; M7="$TMP/fm/m7.json"
fk --out "$TMP/m12" --memory "$M7" http://h:1/ >/dev/null 2>&1
out=$(fk --out "$TMP/m13" --memory "$M7" http://h:1/home 2>&1); rc=$?
out2=$(fk --out "$TMP/m14" --memory "$M7" 2>&1); rc2=$?
[ "$rc" -eq 0 ] && [ "$(jstr "$M7")" = '{"baseUrl":"http://h:1","routes":["/"]}' ] && has "$out" '기록 안 함: 화면 이름 중복: home' && [ "$rc2" -eq 0 ] && has "$out2" '(1화면' \
  && ok "U8c11 합친 routes 의 화면 이름이 겹치면 쓰지 않는다 — 기록이 스스로를 못 읽는 상태 방지" || no "U8c11" "rc=$rc [$out] mem=$(jstr "$M7") rc2=$rc2 [$out2]"
: > "$TMP/afile"; fix "{\"a\":{\"violations\":[$BN1]}}"
out=$(fk --out "$TMP/m15" --memory "$TMP/afile/m.json" --a11y-baseline "$TMP/afile/b.json" http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 0 ] && has "$out" "기록을 쓰지 못함: $TMP/afile/m.json" && has "$out" "기록을 쓰지 못함: $TMP/afile/b.json" && ! has "$out" 'NO_BROWSER' && ! has "$out" '기준선 기록:' \
  && ok "U8c12 쓰기 실패 — 판정은 그대로(rc 0) · 안내 줄 · NO_BROWSER 로 오분류하지 않는다" || no "U8c12" "rc=$rc [$out]"
fix '{}'; bad13=""; i=0
for body in '"x"' '{"cookies":"a"}' '{"cookies":[{"name":"a"}],"origins":[]}'; do
  i=$((i+1)); printf '%s' "$body" > "$TMP/ssbad$i.json"
  out=$(fk --out "$TMP/s13-$i" --storage-state "$TMP/ssbad$i.json" http://h:1/a 2>&1); rc=$?
  { [ "$rc" -eq 3 ] && has "$out" 'UI-PROBE: SKIP (NO_ENV' && has "$out" '모양이 맞지 않는다' && ! has "$out" 'NO_BROWSER'; } || bad13="$bad13 [$body rc=$rc $out]"
done
printf '{}' > "$TMP/ssempty.json"; out=$(fk --out "$TMP/s13-0" --storage-state "$TMP/ssempty.json" http://h:1/a 2>&1); rc=$?
[ -z "$bad13" ] && [ "$rc" -eq 0 ] && has "$out" 'UI-PROBE: PASS (1화면' \
  && ok "U8c13 모양이 틀린 로그인 상태 파일 3종은 SKIP(NO_ENV) rc 3 · {} 는 통과" || no "U8c13" "$bad13 empty: rc=$rc [$out]"
SSA="$TMP/ssA.json"; SSB="$TMP/ssB.json"; echo '{"cookies":[],"origins":[]}' > "$SSA"; echo '{"cookies":[],"origins":[]}' > "$SSB"; M14="$TMP/fm/m14.json"
fk --out "$TMP/s14a" --memory "$M14" --storage-state "$SSA" http://h:1/a >/dev/null 2>&1
mem14=$(jstr "$M14" 2>&1)
rm -f "$LOGF"; out=$(fk --out "$TMP/s14b" --memory "$M14" --storage-state "$SSB" 2>&1); rc=$?
[ "$rc" -eq 0 ] && has "$mem14" "\"storageState\":\"$SSA\"" && [ "$(grep -cF "\"storageState\":\"$SSB\"" "$LOGF")" = 3 ] && [ "$(grep -cF "\"storageState\":\"$SSA\"" "$LOGF")" = 0 ] \
  && ok "U8c14 로그인 상태 우선순위 — --storage-state 가 기록의 storageState 보다 앞선다(3폭 모두)" || no "U8c14" "rc=$rc mem=$mem14 [$out] log=$(cat "$LOGF" 2>&1)"

# U8d — 목업 (AC-3)
printf '<html></html>' > "$TMP/mk/m.html"; printf '<html></html>' > "$TMP/mk/a.html"
fix "{\"m\":{\"overflow\":true,\"violations\":[$BN2]}}"
out=$(fk --out "$TMP/k1" --mock "$TMP/mk/m.html" --mock "$TMP/mk/nomock.html" http://h:1/a 2>&1); rc=$?
exp="UI-PROBE: PASS (1화면·3폭 · 넘침 0 · 콘솔 오류 0 · 접근성 심각 0)
  - nomock 목업 촬영 실패: 파일 없음
  png: $TMP/k1/a@375.png
  png: $TMP/k1/a@768.png
  png: $TMP/k1/a@1280.png
  mock: $TMP/k1/m@375.mock.png
  mock: $TMP/k1/m@768.mock.png
  mock: $TMP/k1/m@1280.mock.png"
[ "$rc" -eq 0 ] && [ "$out" = "$exp" ] && [ "$(png_w "$TMP/k1/m@375.mock.png")" = 375 ] && [ "$(png_w "$TMP/k1/m@768.mock.png")" = 768 ] && [ "$(png_w "$TMP/k1/m@1280.mock.png")" = 1280 ] \
  && ok "U8d1 목업 — 폭마다 촬영(PNG 폭 375·768·1280) · 판정·화면 수에서 제외(넘침·위반 있는 목업도 PASS) · 없는 파일은 안내만" || no "U8d1" "rc=$rc [$out]"
fix '{}'; fk --out "$TMP/k2" --mock "$TMP/mk/a.html" http://h:1/a >/dev/null 2>&1
[ -s "$TMP/k2/a@375.png" ] && [ -s "$TMP/k2/a@375.mock.png" ] && ok "U8d2 구현과 목업 이름이 같아도 .mock.png 가 구현 PNG 를 덮어쓰지 않는다" || no "U8d2" "$(ls "$TMP/k2")"

# U8e — 접근성 기준선 (AC-4·AC-5)
BL="$TMP/fb/bl.json"
fix "{\"a\":{\"overflow\":true,\"violations\":[$BN1]}}"; out=$(fk --out "$TMP/e1" --a11y-baseline "$TMP/fb/bq.json" http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 1 ] && [ "$(jstr "$TMP/fb/bq.json")" = '{"_widest":1280,"a|button-name":1}' ] && has "$out" '기준선 기록: a@1280 critical button-name(1곳)' \
  && ok "U8e1 넘침으로 FAIL 인 최초 실행도 기준선을 쓴다(Q-A) — 접근성은 독립" || no "U8e1" "rc=$rc [$out]"
fix "{\"a\":{\"violations\":[$BN1]}}"; out=$(fk --out "$TMP/e2" --a11y-baseline "$BL" http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(jstr "$BL")" = '{"_widest":1280,"a|button-name":1}' ] && has "$out" '접근성 심각 0 · 기준선 기록 1' && ok "U8e2 기준선 없음 — 위반을 기록하고 막지 않는다(rc 0 · _widest)" || no "U8e2" "rc=$rc [$out]"
cp "$BL" "$TMP/fb/keep.json"
out=$(fk --out "$TMP/e3" --a11y-baseline "$BL" http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 0 ] && has "$out" '접근성 심각 0 · 기준선 1' && cmp -s "$BL" "$TMP/fb/keep.json" && ok "U8e3 같은 화면 — rc 0 · 기준선 1 · 파일 바이트 불변" || no "U8e3" "rc=$rc [$out]"
fix "{\"a\":{\"violations\":[$BN1,$IA1]}}"; out=$(fk --out "$TMP/e4" --a11y-baseline "$BL" http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 1 ] && has "$out" 'image-alt(1곳, 기준선 없음)' && ! has "$out" 'button-name(' && has "$out" '접근성 심각 1 · 기준선 1' && cmp -s "$BL" "$TMP/fb/keep.json" \
  && ok "U8e4 새 위반만 FAIL 줄 — 변하지 않은 항목은 줄에 안 나오고 센다 · 파일 불변" || no "U8e4" "rc=$rc [$out]"
fix "{\"a\":{\"violations\":[$BN2]}}"; out=$(fk --out "$TMP/e5" --a11y-baseline "$BL" http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 1 ] && has "$out" 'button-name(2곳, 기준선 1곳)' && cmp -s "$BL" "$TMP/fb/keep.json" && ok "U8e5 노드 수가 늘면 FAIL — 현재곳·기준선곳 표기" || no "U8e5" "rc=$rc [$out]"
printf '{"_widest":1280,"a|button-name":5}' > "$TMP/fb/hi.json"; cp "$TMP/fb/hi.json" "$TMP/fb/hi.keep"
fix "{\"a\":{\"violations\":[$BN1]}}"; out=$(fk --out "$TMP/e6" --a11y-baseline "$TMP/fb/hi.json" http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 0 ] && has "$out" '기준선 1' && cmp -s "$TMP/fb/hi.json" "$TMP/fb/hi.keep" && ok "U8e6 노드 수가 줄어도 통과 · 기준선을 자동으로 낮추지 않는다(Q-G)" || no "U8e6" "rc=$rc [$out]"
printf '{bad' > "$TMP/fb/broken.json"; out=$(fk --out "$TMP/e7" --a11y-baseline "$TMP/fb/broken.json" http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 1 ] && has "$out" '기준선 파일을 읽지 못해 무시함' && [ "$(cat "$TMP/fb/broken.json")" = '{bad' ] && ok "U8e7 깨진 기준선 — 기준선 없이 판정(rc 1) · 파일 불변" || no "U8e7" "rc=$rc [$out]"
out=$(fk --out "$TMP/e8" --a11y-baseline "$TMP/fb/broken.json" --a11y-baseline-update http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(jstr "$TMP/fb/broken.json")" = '{"_widest":1280,"a|button-name":1}' ] && ok "U8e8 깨진 기준선 + update → 이번 결과로 새로 쓴다(Q-F)" || no "U8e8" "rc=$rc [$out]"
cp "$TMP/fb/keep.json" "$BL"; fix "{\"a\":{\"violations\":[$BN2]}}"
out=$(fk --out "$TMP/e9" --a11y-baseline "$BL" --a11y-baseline-update http://h:1/a 2>&1); rc=$?
out2=$(fk --out "$TMP/e10" --a11y-baseline "$BL" http://h:1/a 2>&1); rc2=$?
[ "$rc" -eq 0 ] && [ "$(jstr "$BL")" = '{"_widest":1280,"a|button-name":2}' ] && [ "$rc2" -eq 0 ] && has "$out2" '기준선 1' && ok "U8e9 update — 이번 결과로 다시 쓰고 그다음 같은 점검은 rc 0" || no "U8e9" "rc=$rc $(jstr "$BL") rc2=$rc2 [$out2]"
BL2="$TMP/fb/bl2.json"
fix "{\"a\":{\"violations\":[$BN1]},\"b\":{\"violations\":[$BN1]}}"; fk --out "$TMP/e11" --a11y-baseline "$BL2" http://h:1/a http://h:1/b >/dev/null 2>&1
fix "{\"a\":{\"violations\":[$BN2]}}"; fk --out "$TMP/e12" --a11y-baseline "$BL2" --a11y-baseline-update http://h:1/a >/dev/null 2>&1
g1=$(jstr "$BL2")
cp "$BL2" "$TMP/fb/bl3.json"
fk --out "$TMP/e15" --a11y-baseline "$TMP/fb/bl3.json" --a11y-baseline-update --widths 375,768 http://h:1/a >/dev/null 2>&1
g3=$(jstr "$TMP/fb/bl3.json")
fix '{}'; fk --out "$TMP/e13" --a11y-baseline "$BL2" --a11y-baseline-update http://h:1/a >/dev/null 2>&1
g2=$(jstr "$BL2")
[ "$g1" = '{"_widest":1280,"a|button-name":2,"b|button-name":1}' ] && [ "$g2" = '{"_widest":1280,"b|button-name":1}' ] \
  && ok "U8e10 update 는 점검한 화면만 교체 — 점검하지 않은 화면 항목 보존 · 고친 위반은 삭제" || no "U8e10" "g1=$g1 g2=$g2"
cp "$TMP/fb/keep.json" "$BL"; fix "{\"a\":{\"violations\":[$BN1]}}"
out=$(fk --out "$TMP/e14" --a11y-baseline "$BL" --widths 375,768 http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 1 ] && has "$out" '기준선 폭(1280)과 이번 폭(768)이 달라 무시함' && [ "$g3" = '{"_widest":768,"a|button-name":2}' ] \
  && ok "U8e11 폭이 다르면 비교하지 않고 안내 · 폭 불일치 + update 는 점검한 화면만으로 새로 쓴다" || no "U8e11" "rc=$rc [$out] g3=$g3"
fix "{\"a\":{\"violations\":[$BN1]}}"
out=$(DEVFSD_UI_HARNESS_DIR="$FK2" FAKE_PW_FIX="$FIX" node "$P" --out "$TMP/e16" --a11y-baseline "$TMP/fb/b6.json" http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$TMP/fb/b6.json" ] && has "$out" '기준선을 쓰지 않음: axe-core 를 찾지 못했다' && has "$out" '접근성 SKIP(axe-core 없음)' \
  && ok "U8e12 axe-core 없음 — 기준선 파일을 만들지 않고 안내(AC-4)" || no "U8e12" "rc=$rc [$out]"

# U9 — 배치 계측(잘림·겹침): 경고만 · 판정 불변 · 못 잰 것은 0 이 아니다 (FID 20261110-visual-severity-clip-overlap AC-6·AC-9·AC-11)
L="$PLUGIN/scripts/_internal/ui-probe-layout.cjs"
cnt() { printf '%s\n' "$1" | awk -v k="$2" 'index($0, k) { n++ } END { print n + 0 }'; }   # 런타임에 조합되는 출력 줄을 세는 헬퍼(has 와 같은 이유 — 소스에 통째 리터럴이 없다)
out=$(node "$P" --rules 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^| L-')" = 5 ] && [ "$(printf '%s\n' "$out" | sed -n 's/^| \(L-[A-Z-]*\) |.*/\1/p' | tr '\n' ' ')" = 'L-CLIP-X L-OVERLAP L-WRAP-CHIP L-SCROLL-X L-FIXED-COVER ' ] && printf '%s\n' "$out" | grep -E '^\| L-CLIP-X \|' | grep -qF '가로' && printf '%s\n' "$out" | grep -qE '^\| L-OVERLAP \|' \
  && ok "U9a --rules — 규칙 5개 표(순서 고정) · 잘림 정의에 '가로'(AC-11) · 브라우저 없이 rc 0" || no "U9a" "rc=$rc [$out]"
fix '{"a":{"layout":{"clip":["<table> — <div.card> 안에서 512px 가려짐"],"overlap":["<label> ↔ <span.hint> — 86×5px 겹침","x ↔ y — 9×9px 겹침"]}}}'
out=$(fk --out "$TMP/l1" --widths 390 http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = 'UI-PROBE: PASS (1화면·1폭 · 넘침 0 · 콘솔 오류 0 · 접근성 심각 0 · 배치 경고 3(잘림 1 · 겹침 2))' ] \
  && [ "$(printf '%s\n' "$out" | sed -n 2p)" = '  - a@390 배치 경고 L-CLIP-X(가로 잘림): <table> — <div.card> 안에서 512px 가려짐' ] \
  && [ "$(cnt "$out" '배치 경고 L-OVERLAP(글자 겹침): ')" = 2 ] \
  && [ "$(node -e 'const r=require(process.argv[1]).results[0].layout;console.log(r.state,r.clip.length,r.overlap.length)' "$TMP/l1/ui-probe.json")" = 'ok 1 2' ] \
  && ok "U9b 경고만 있는 실행 — rc 0 · PASS · 요약에 건수 덧붙음 · 경고 줄 형식 · 기록에 같은 건수(AC-6)" || no "U9b" "rc=$rc [$out]"
# U9b2 — 좁은 폭 규칙 3종(줄바꿈·가로 스크롤에 숨음·고정 막대 가림): 경고만 · 있을 때만 요약에 붙는다 (20261114: 문장 지침은 재현되지 않고 계측은 재현됐다)
fix '{"a":{"layout":{"clip":[],"overlap":[],"wrap":["<span.chip> \"처리 중\" — 2줄로 꺾임"],"scroll":["<nav.tabs> — 가로 스크롤 안에 212px 숨음"],"cover":["<div.actions> — 문서 끝 64px 가 고정 막대 뒤에 가린다"]}}}'
out=$(fk --out "$TMP/l1b" --widths 390 http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = 'UI-PROBE: PASS (1화면·1폭 · 넘침 0 · 콘솔 오류 0 · 접근성 심각 0 · 배치 경고 3(잘림 0 · 겹침 0 · 줄바꿈 1 · 스크롤 숨음 1 · 고정 가림 1))' ] \
  && [ "$(cnt "$out" 'a@390 배치 경고 L-WRAP-CHIP(칩 줄바꿈): <span.chip>')" = 1 ] && [ "$(cnt "$out" 'a@390 배치 경고 L-SCROLL-X(가로 스크롤에 숨음): <nav.tabs>')" = 1 ] && [ "$(cnt "$out" 'a@390 배치 경고 L-FIXED-COVER(고정 막대 가림): <div.actions>')" = 1 ] \
  && [ "$(node -e 'const r=require(process.argv[1]).results[0].layout;console.log(r.state,r.wrap.length,r.scroll.length,r.cover.length)' "$TMP/l1b/ui-probe.json")" = 'ok 1 1 1' ] \
  && ok "U9b2 ★ 좁은 폭 규칙 3종 — rc 0 · 요약에 0 아닌 것만 덧붙음 · 규칙 ID·이름 줄 · 기록에 같은 건수" || no "U9b2" "rc=$rc [$out]"
fix '{"a":{"layout":{"clip":[],"overlap":[],"wrap":"x"}}}'; out=$(fk --out "$TMP/l1c" --widths 390 http://h:1/a 2>&1)
has "$out" 'a@390 배치 계측 못 함: 계측 결과를 읽지 못함' && ok "U9b3 새 칸의 모양이 틀리면 0건이 아니라 '계측 못 함'" || no "U9b3" "[$out]"
fix '{"a":{"overflow":true,"layout":{"clip":["c1"],"overlap":[]}}}'; out=$(fk --out "$TMP/l2" --widths 390 http://h:1/a 2>&1); rc=$?
fix '{"a":{"overflow":true}}'; out0=$(fk --out "$TMP/l3" --widths 390 http://h:1/a 2>&1); rc0=$?
[ "$rc" -eq 1 ] && [ "$rc0" -eq 1 ] && has "$out" 'a@390 가로 넘침' && has "$out0" 'UI-PROBE: FAIL (1화면·1폭 · 넘침 1 · 콘솔 오류 0 · 접근성 심각 0)' && ! has "$out0" '배치' \
  && ok "U9c 판정은 넘침·콘솔·접근성만으로 — 경고가 있어도 없어도 같은 rc · 경고 0 이면 요약에 아무것도 안 붙는다" || no "U9c" "rc=$rc,$rc0 [$out|$out0]"
many=$(node -e 'console.log(JSON.stringify({a:{layout:{clip:Array.from({length:8},(_,i)=>"c"+i),overlap:[]}}}))'); fix "$many"
out=$(fk --out "$TMP/l4" --widths 390 http://h:1/a 2>&1)
[ "$(printf '%s\n' "$out" | grep -c '배치 경고 L-CLIP-X')" = 6 ] && has "$out" '배치 경고 L-CLIP-X(가로 잘림): 외 3건' && has "$out" '배치 경고 8(잘림 8 · 겹침 0)' \
  && ok "U9d 한 화면·폭·규칙에 5줄까지 + '외 N건' · 건수는 전부 센다" || no "U9d" "[$out]"
many=$(node -e 'console.log(JSON.stringify({a:{layout:{clip:[],overlap:Array.from({length:8},(_,i)=>"o"+i)}}}))'); fix "$many"
out=$(fk --out "$TMP/l4b" --widths 390 http://h:1/a 2>&1)
[ "$(cnt "$out" '배치 경고 L-OVERLAP(글자 겹침): ')" = 6 ] && has "$out" '배치 경고 L-OVERLAP(글자 겹침): 외 3건' && has "$out" '배치 경고 8(잘림 0 · 겹침 8)' \
  && ok "U9d2 겹침도 같은 상한 — 5줄 + '외 3건'" || no "U9d2" "[$out]"
fix "{\"a\":{\"layoutThrow\":true,\"violations\":[$BN1]},\"b\":{\"layout\":{\"clip\":[\"c1\"],\"overlap\":[]}}}"
out=$(fk --out "$TMP/l5" http://h:1/a http://h:1/b 2>&1); rc=$?
fix "{\"a\":{\"violations\":[$BN1]},\"b\":{\"layout\":{\"clip\":[\"c1\"],\"overlap\":[]}}}"
ref=$(fk --out "$TMP/l6" http://h:1/a http://h:1/b 2>&1); rcr=$?
[ "$rc" -eq "$rcr" ] && [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c 'a@.* 배치 계측 못 함: 계측 중 오류: layout boom')" = 3 ] && has "$out" '배치 계측 못 함 3' \
  && [ "$(printf '%s\n' "$out" | grep -c 'b@.* 배치 경고 L-CLIP-X')" = 3 ] && [ "$(printf '%s\n' "$out" | grep -F '접근성')" = "$(printf '%s\n' "$ref" | grep -F '접근성' | sed 's/ · 배치 경고 3(잘림 3 · 겹침 0)/ · 배치 경고 3(잘림 3 · 겹침 0) · 배치 계측 못 함 3/')" ] \
  && [ "$(node -e 'const r=require(process.argv[1]).results;console.log(r.filter(x=>x.layout.state==="unmeasured").length,r.filter(x=>x.layout.state==="ok"&&x.layout.clip.length===1).length)' "$TMP/l5/ui-probe.json")" = '3 3' ] \
  && ok "U9e 계측 예외 — 그 화면·폭만 '계측 못 함'(0 으로 쓰지 않음) · 다른 화면의 계측과 접근성 판정·rc 는 예외가 없을 때와 같다(AC-9)" || no "U9e" "rc=$rc/$rcr [$out] ref=[$ref]"
fix '{"a":{"layout":"x"}}'; out=$(fk --out "$TMP/l7" --widths 390 http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 0 ] && has "$out" 'a@390 배치 계측 못 함: 계측 결과를 읽지 못함' \
  && ok "U9f 모양이 틀린 계측 결과는 0건이 아니라 '계측 못 함'" || no "U9f" "rc=$rc [$out]"
fix '{"a":{"layoutThrowAt":390}}'; out=$(fk --out "$TMP/l9" --widths 390,1280 http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(cnt "$out" '배치 계측 못 함: ')" = 1 ] && has "$out" 'a@390 배치 계측 못 함: 계측 중 오류: layout boom' && has "$out" '배치 계측 못 함 1)' \
  && [ "$(node -e 'console.log(require(process.argv[1]).results.map(x=>x.width+":"+x.layout.state).join(","))' "$TMP/l9/ui-probe.json")" = '390:unmeasured,1280:ok' ] \
  && ok "U9h 한 폭에서만 예외 — 그 폭만 '계측 못 함', 같은 화면의 다른 폭은 계측됨(AC-9 화면·폭 단위)" || no "U9h" "rc=$rc [$out]"
fix '{"zzz":{"fail":true}}'; out=$(fk --out "$TMP/l8" --widths 390 http://h:1/zzz 2>&1); rc=$?
[ "$rc" -eq 1 ] && has "$out" 'zzz@390 열기 실패' && has "$out" 'zzz@390 배치 계측 못 함: 열기 실패' \
  && ok "U9g 열지 못한 화면도 '계측 못 함'" || no "U9g" "rc=$rc [$out]"

# U7 — 실브라우저 스모크: 가짜가 아닌 Playwright·axe 에서 같은 결과가 나오는지 (없는 환경이면 SKIP 을 세어 적는다)
if [ "${HAVE_BROWSER:-0}" != 1 ]; then sk "U7 (이 환경에 Playwright·브라우저 없음)"; else
cat > "$TMP/srv.cjs" <<'EOF'
const http = require('http'), fs = require('fs');
const page = (b) => `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>t</title></head><body><main><h1>x</h1>${b}</main></body></html>`;
const srv = http.createServer((req, res) => {
  const p = req.url.split('?')[0];
  let b = '<p>정상</p>';
  if (p === '/bad') b = fs.readFileSync(process.argv[3], 'utf8').trim() === '2' ? '<button type="button"></button><button type="button"></button><img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=">' : '<button type="button"></button>';
  if (p === '/auth') b = (req.headers.cookie || '').includes('sid=ok') ? '<p>로그인됨</p>' : '<script>console.error("no session")</script>';
  res.setHeader('content-type', 'text/html; charset=utf-8'); res.end(page(b));
});
srv.listen(0, '127.0.0.1', () => fs.writeFileSync(process.argv[2], String(srv.address().port)));
EOF
echo 1 > "$TMP/mode"; node "$TMP/srv.cjs" "$TMP/port" "$TMP/mode" >/dev/null 2>&1 & SRV=$!
for _ in $(seq 1 20); do [ -s "$TMP/port" ] && break; sleep 0.25; done
PORT=$(cat "$TMP/port" 2>/dev/null); B="http://127.0.0.1:$PORT"
if [ -z "$PORT" ]; then no "U7 서버" "브라우저는 떴는데 테스트 서버를 띄우지 못함"; else
  R="$TMP/real"; mkdir -p "$R"

  # U7a 기록 — 첫 실행 · 기록만으로 재실행
  node "$P" --out "$R/a1" --memory "$R/mem.json" --start-cmd "npm run dev" "$B/a" "$B/b" >/dev/null 2>&1; rc=$?
  out=$(node "$P" --out "$R/a2" --memory "$R/mem.json" 2>&1)
  [ "$rc" -eq 0 ] && [ "$(jstr "$R/mem.json")" = "{\"baseUrl\":\"$B\",\"routes\":[\"/a\",\"/b\"],\"startCmd\":\"npm run dev\"}" ] && has "$out" 'UI-PROBE: PASS (2화면·3폭' \
    && ok "U7a 실브라우저 — 기록 저장 후 URL 없이 두 화면 재점검" || no "U7a" "rc=$rc [$out]"

  # U7b 로그인 상태 — 쿠키가 있을 때만 정상 화면
  cat > "$R/ss.json" <<'EOF'
{"cookies":[{"name":"sid","value":"ok","domain":"127.0.0.1","path":"/","expires":-1,"httpOnly":false,"secure":false,"sameSite":"Lax"}],"origins":[]}
EOF
  out=$(node "$P" --out "$R/b1" --widths 1280 --storage-state "$R/ss.json" "$B/auth" 2>&1); rc=$?
  out2=$(node "$P" --out "$R/b2" --widths 1280 "$B/auth" 2>&1); rc2=$?
  [ "$rc" -eq 0 ] && [ "$rc2" -eq 1 ] && has "$out2" '콘솔 오류: no session' && ok "U7b 실브라우저 — 상태 파일의 쿠키가 있으면 PASS, 없으면 같은 화면이 FAIL(대조)" || no "U7b" "rc=$rc [$out] rc2=$rc2 [$out2]"

  # U7c 목업 — 실제 PNG 폭 · 구현 PNG 와 다른 이미지
  node "$P" --out "$R/c1" --mock "$TMP/good.html" "$B/good" >/dev/null 2>&1
  [ "$(png_w "$R/c1/good@375.mock.png")" = 375 ] && [ "$(png_w "$R/c1/good@768.mock.png")" = 768 ] && [ "$(png_w "$R/c1/good@1280.mock.png")" = 1280 ] && ! cmp -s "$R/c1/good@375.png" "$R/c1/good@375.mock.png" \
    && ok "U7c 실브라우저 — 목업을 폭마다 찍고(375·768·1280) 구현 PNG 와 다른 이미지" || no "U7c" "$(ls "$R/c1")"

  # U7d·U7e 접근성 기준선 (실제 axe)
  out=$(node "$P" --out "$R/d1" --a11y-baseline "$R/bl.json" "$B/bad" 2>&1); rc=$?
  if has "$out" '접근성 SKIP'; then sk "U7d·U7e (axe-core 없음)"; else
    cp "$R/bl.json" "$R/bl.keep.json"
    out2=$(node "$P" --out "$R/d2" --a11y-baseline "$R/bl.json" "$B/bad" 2>&1); rc2=$?
    echo 2 > "$TMP/mode"
    out3=$(node "$P" --out "$R/d3" --a11y-baseline "$R/bl.json" "$B/bad" 2>&1); rc3=$?
    [ "$rc" -eq 0 ] && [ "$(jstr "$R/bl.keep.json")" = '{"_widest":1280,"bad|button-name":1}' ] && [ "$rc2" -eq 0 ] && has "$out2" '기준선 1' \
      && [ "$rc3" -eq 1 ] && has "$out3" 'button-name(2곳, 기준선 1곳)' && has "$out3" 'image-alt(1곳, 기준선 없음)' && cmp -s "$R/bl.json" "$R/bl.keep.json" \
      && ok "U7d 실 axe — 기록 → 같은 점검 통과 → 늘어난·새 위반만 FAIL · 파일 불변" || no "U7d" "rc=$rc,$rc2,$rc3 [$out|$out2|$out3]"
    node "$P" --out "$R/e1" --a11y-baseline "$R/bq.json" "file://$TMP/bad.html" >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 1 ] && [ "$(jstr "$R/bq.json")" = '{"_widest":1280,"bad|button-name":1}' ] && ok "U7e 실브라우저 — 넘침·콘솔 오류로 FAIL 인 최초 실행도 기준선을 쓴다(Q-A)" || no "U7e" "rc=$rc $(jstr "$R/bq.json" 2>&1)"
  fi
fi
fi

# U10 — 실브라우저 배치 계측 (AC-3·AC-4·AC-5): 없는 환경이면 SKIP 을 센다. 조각은 최소 재현이다(.specops 의 픽스처는 저장소에 없다)
if [ "${HAVE_BROWSER:-0}" != 1 ]; then sk "U10 (이 환경에 Playwright·브라우저 없음)"; else
  LY="$TMP/ly"; mkdir -p "$LY"
  pg() { printf '<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>t</title><style>body{margin:0;font:15px/1.6 sans-serif}%s</style></head><body><main>%s</main></body></html>' "$2" "$3" > "$LY/$1.html"; }
  TBL='<table><tr><td>주문번호</td><td>주문 일시</td><td>주문자</td><td>상품 이름이 긴 칸</td><td>결제 금액</td><td>상태</td></tr></table>'
  HINT='<div class="f"><span class="hint">최대 환불 가능액 184,000원</span><label for="a">환불 금액 (배송비 제외)</label><input id="a"></div>'
  # ── 양성(결함)
  pg clip '.box{overflow:hidden;border:1px solid #ccc}table{min-width:860px}td{white-space:nowrap;padding:8px}' "<h1>주문</h1><div class=\"box\">$TBL</div>"
  pg over '.f{position:relative}@media (max-width:600px){.hint{position:absolute;top:6px;left:46px;background:rgba(255,243,205,.72)}}' "<h1>환불</h1>$HINT"
  pg over_smooth 'html{scroll-behavior:smooth}.sp{height:2200px}.f{position:relative}.hint{position:absolute;top:6px;left:46px;background:rgba(255,243,205,.72)}' "<h1>긴 화면</h1><div class=\"sp\"></div>$HINT"
  pg p_left '.box{overflow:hidden;width:300px;border:1px solid #ccc;margin-left:80px}.in{margin-left:-60px;width:200px;height:30px}' '<h1>왼쪽</h1><div class="box"><div class="in">왼쪽으로 잘린 칸</div></div>'
  # ── 음성(정상·제외 조건) 과 그 조건만 뺀 양성 쌍 p_*
  pg ok1 '.g{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}@media (max-width:600px){.g{grid-template-columns:1fr}}' '<h1>회원 상세</h1><div class="g"><div>누적 구매액 2,184,000원</div><div>주문 횟수 23회</div><div>등급 골드</div></div>'
  pg x_ellipsis '.e{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;width:120px}' '<h1>말줄임</h1><div class="e"><span>아주 길어서 잘리는 상품 이름입니다 아주 길어서</span></div>'
  pg p_ellipsis '.e{overflow:hidden;white-space:nowrap;width:120px}' '<h1>말줄임 없음</h1><div class="e"><span>아주 길어서 잘리는 상품 이름입니다 아주 길어서</span></div>'
  pg x_sronly 'h1{margin:0;font-size:15px}.vh{position:absolute;top:0;left:0;width:1px;height:1px;overflow:hidden;white-space:nowrap}' '<h1>검색 화면 제목</h1><label class="vh" for="q">종목 검색</label><input id="q"><p>예시 데이터 안내 문구</p>'
  pg p_sronly 'h1{margin:0;font-size:15px}.vh{position:absolute;top:0;left:0;white-space:nowrap}' '<h1>검색 화면 제목</h1><label class="vh" for="q">종목 검색</label><input id="q"><p>예시 데이터 안내 문구</p>'
  pg x_hidden '.box{overflow:hidden;width:200px}.off{display:none}.inv{visibility:hidden}' '<h1>숨김</h1><div class="box"><div class="off" style="width:900px">숨긴 넓은 내용</div><div class="inv" style="width:900px">안 보이는 넓은 내용</div><p>보이는 글</p></div>'
  pg p_hidden '.box{overflow:hidden;width:200px}' '<h1>숨김 아님</h1><div class="box"><div style="width:900px">보이는 넓은 내용 보이는 넓은 내용 보이는 넓은 내용</div><p>보이는 글</p></div>'
  pg x_scroll '.w{overflow-x:auto}table{min-width:860px}td{white-space:nowrap;padding:8px}' "<h1>표</h1><div class=\"w\">$TBL</div>"
  pg p_scroll '.w{overflow-x:hidden}table{min-width:860px}td{white-space:nowrap;padding:8px}' "<h1>표</h1><div class=\"w\">$TBL</div>"
  pg x_sticky 'header{position:sticky;top:0}h1{margin:-14px 0 0;font-size:15px}p{margin:0 0 600px}' '<header>고정 머리글 제목</header><h1>머리글 아래로 지나가는 제목</h1><p>본문</p>'
  pg p_sticky 'h1{margin:-14px 0 0;font-size:15px}p{margin:0 0 600px}' '<header>고정 머리글 제목</header><h1>머리글 아래로 지나가는 제목</h1><p>본문</p>'
  pg x_nested '.c{position:relative;width:200px}.b{position:absolute;left:0;top:2px;color:#888}' '<h1>포함</h1><div class="c">부모 안의 글자 부모 안의 글자<span class="b">자식 글자 겹침 허용</span></div>'
  pg p_nested '.c{position:relative;width:200px}.b{position:absolute;left:0;top:2px;color:#888}' '<h1>포함</h1><div class="c"><span>형제 글자 형제 글자 형제 글자</span><span class="b">다른 형제 글자 겹침</span></div>'
  pg x_popup '.wrap{position:relative}p{margin:0}.pop{position:absolute;top:0;left:0;background:#fff;width:240px}' '<h1>검색</h1><div class="wrap"><p>아래에 깔린 목록 글자입니다</p><p>둘째 줄 목록 글자입니다</p><div class="pop">열린 드롭다운 항목 하나</div></div>'
  pg p_popup '.wrap{position:relative}p{margin:0}.pop{position:absolute;top:0;left:0;width:240px}' '<h1>검색</h1><div class="wrap"><p>아래에 깔린 목록 글자입니다</p><p>둘째 줄 목록 글자입니다</p><div class="pop">열린 드롭다운 항목 하나</div></div>'
  pg x_decor '.box{overflow:hidden;width:300px;height:20px;position:relative}.bar{width:900px;height:6px;background:#ccc}' '<h1>진행</h1><div class="box"><div class="bar"></div></div><p>본문</p>'
  pg p_decor '.box{overflow:hidden;width:300px;position:relative}.bar{width:900px;background:#ccc}' '<h1>진행</h1><div class="box"><div class="bar">막대 안에 글자가 있다</div></div><p>본문</p>'
  pg x_tiny '.box{overflow:hidden;width:300px;border:1px solid #ccc}.in{width:303px;height:30px}' '<h1>작은 삐져나옴</h1><div class="box"><div class="in">3px 삐져나온 칸</div></div>'
  pg p_tiny '.box{overflow:hidden;width:300px;border:1px solid #ccc}.in{width:312px;height:30px}' '<h1>조금 삐져나옴</h1><div class="box"><div class="in">12px 삐져나온 칸</div></div>'
  pg x_abs '.outer{position:relative;padding:8px}.card{overflow:hidden;width:200px;border:1px solid #ccc}.tip{position:absolute;left:150px;top:40px;width:160px;background:#fff;border:1px solid #999}' '<h1>툴팁</h1><div class="outer"><div class="card"><p>카드 안의 글</p><div class="tip">카드 밖으로 나오는 툴팁 글자</div></div></div>'
  pg p_abs '.outer{padding:8px}.card{position:relative;overflow:hidden;width:200px;border:1px solid #ccc}.tip{position:absolute;left:150px;top:10px;width:160px;background:#fff;border:1px solid #999}' '<h1>툴팁</h1><div class="outer"><div class="card"><p>카드 안의 글</p><div class="tip">카드에 잘리는 툴팁 글자</div></div></div>'
  pg x_root 'html,body{overflow-x:hidden}.off{position:absolute;left:100%;top:0;width:260px}' '<h1>정상</h1><p>화면 안의 글</p><nav class="off">화면 밖에 완전히 숨긴 서랍 메뉴</nav>'
  pg p_root 'html,body{overflow-x:hidden}' '<h1>모바일 땜질</h1><div style="width:900px">화면보다 넓은 내용 화면보다 넓은 내용 화면보다 넓은 내용 화면보다 넓은 내용 화면보다 넓은 내용 화면보다 넓은 내용</div>'
  # ── 좁은 폭 규칙 3종 — 양성 p_* 와 그 조건만 뺀 음성 x_*
  CHIPS='<p><span class="chip">처리 중</span> <span class="chip">고객 대기</span></p>'
  pg p_wrapchip '.c{width:44px}.chip{display:inline-flex;border-radius:999px;background:#e8edf3;padding:0 8px}' "<h1>칩</h1><div class=\"c\">$CHIPS</div>"
  pg x_wrapchip '.c{width:44px}.chip{display:inline-flex;border-radius:999px;background:#e8edf3;padding:0 8px;white-space:nowrap}' "<h1>칩</h1><div class=\"c\">$CHIPS</div>"
  pg x_wrappara '.c{width:120px}' '<h1>문단</h1><div class="c"><p>칩이 아닌 평범한 문단은 좁으면 여러 줄로 꺾이는 것이 정상이다</p><a href="#">여러 줄로 꺾이는 긴 링크 글자 긴 링크 글자</a></div>'
  TABS='<a href="#">출고 현황</a><a href="#">지연 주문</a><a href="#">도크 관리</a><a href="#">입고 현황</a><a href="#">재고 조회</a><a href="#">담당자 현황</a>'
  pg p_scrollx '.tabs{display:flex;gap:16px;overflow-x:auto;white-space:nowrap}' "<h1>탭</h1><nav class=\"tabs\">$TABS</nav>"
  pg x_scrollfit '.tabs{display:flex;gap:16px;overflow-x:auto;white-space:nowrap}' '<h1>탭</h1><nav class="tabs"><a href="#">출고</a><a href="#">지연</a></nav>'
  FORM='<h1>청구서</h1><p>첫 줄</p><div class="sp"></div><label for="m">마지막 입력</label><input id="m">'
  pg p_cover '.sp{height:1600px}.bar{position:fixed;left:0;right:0;bottom:0;height:64px;background:#fff;border-top:1px solid #ccc}' "$FORM<div class=\"bar\"><button>제출</button></div>"
  pg x_cover 'main{padding-bottom:80px}.sp{height:1600px}.bar{position:fixed;left:0;right:0;bottom:0;height:64px;background:#fff;border-top:1px solid #ccc}' "$FORM<div class=\"bar\"><button>제출</button></div>"
  pg x_modal '.sp{height:1600px}.back{position:fixed;inset:0;background:rgba(0,0,0,.4)}' "$FORM<div class=\"back\"><p>열린 대화상자</p></div>"
  pg x_smooth 'html{scroll-behavior:smooth}p{margin:0 0 1500px}' '<h1>부드러운 스크롤 화면</h1><p>첫 문단</p><p>둘째 문단</p><p>셋째 문단</p>'
  # 알려진 구멍: 불투명한 배지가 라벨을 완전히 덮으면 '포개져 보이는 글자' 가 아니라 가림이라 잡지 않는다(열린 드롭다운과 구별 불가). 이 구멍을 메우면 이 조각이 적중으로 바뀐다 — 의도한 변경인지 확인할 것
  pg x_badge_opaque '.f{position:relative}.hint{position:absolute;top:6px;left:46px;background:#fff3cd}' "<h1>환불</h1>$HINT"
  lyrun() { node "$P" --out "$LY/out-$1" --widths 390,1280 "file://$LY/$1.html" 2>&1; }
  out=$(lyrun clip)
  [ "$(cnt "$out" 'clip@390 배치 경고 L-CLIP-X(가로 잘림): <table>')" = 1 ] && ! has "$out" 'clip@1280 배치 경고' && ! has "$out" 'L-OVERLAP' \
    && [ "$(node -e 'const r=require(process.argv[1]).results;console.log(r.map(x=>x.width+":"+x.layout.clip.length).join(","))' "$LY/out-clip/ui-probe.json")" = '390:1,1280:0' ] \
    && ok "U10a 가림 상자 밖으로 나간 표 — 390 에서 잘림 1건(가장 바깥 요소) · 1280 은 0 · 기록 일치(AC-3)" || no "U10a" "[$out]"
  out=$(lyrun over)
  [ "$(cnt "$out" 'over@390 배치 경고 L-OVERLAP(글자 겹침): ')" = 1 ] && has "$out" '환불 금액' && has "$out" '최대 환불 가능액' && ! has "$out" 'over@1280 배치 경고' \
    && ok "U10b 포개진 글자 — 390 에서 겹침 1건(두 글자 덩어리 식별) · 1280 은 0(AC-4)" || no "U10b" "[$out]"
  bad10=""
  for n in ok1 x_ellipsis x_sronly x_hidden x_scroll x_sticky x_nested x_popup x_decor x_tiny x_abs x_root x_smooth x_badge_opaque x_wrapchip x_wrappara x_scrollfit x_cover x_modal; do
    out=$(lyrun "$n"); { has "$out" '배치 경고' || has "$out" '배치 계측 못 함'; } && bad10="$bad10 [$n: $(printf '%s' "$out" | grep -F '배치' | head -2 | tr '\n' ' ')]"
  done
  for f in "$PLUGIN/screens/login.html" "$PLUGIN/templates/screen.html"; do
    out=$(node "$P" --out "$LY/out-repo" --widths 390,1280 "file://$f" 2>&1); { has "$out" '배치 경고' || has "$out" '배치 계측 못 함'; } && bad10="$bad10 [$(basename "$f")]"
  done
  [ -z "$bad10" ] && ok "U10c 정상 화면·제외 조건 조각 19개·저장소 예시 2개 — 양 폭 경고 0 · 못 잰 것 0(AC-5)" || no "U10c" "적중:$bad10"
  out=$(lyrun over_smooth)
  [ "$(cnt "$out" 'over_smooth@390 배치 경고 L-OVERLAP(글자 겹침): ')" = 1 ] && [ "$(cnt "$out" 'over_smooth@1280 배치 경고 L-OVERLAP(글자 겹침): ')" = 1 ] \
    && [ "$(node -e 'const fs=require("fs"),r=require(process.argv[1]).results;console.log(r.every(x=>x.overflow===false&&fs.statSync(x.png).size>0))' "$LY/out-over_smooth/ui-probe.json")" = true ] \
    && ok "U10d 화면 아래쪽(뷰포트 밖)·smooth 스크롤 화면의 겹침도 잡는다 · 넘침 판정·PNG 는 그대로" || no "U10d" "[$out]"
  miss10=""
  for n in p_ellipsis p_hidden p_scroll p_decor p_tiny p_left p_abs p_root; do out=$(lyrun "$n"); [ "$(cnt "$out" "$n@390 배치 경고 L-CLIP-X(가로 잘림): ")" = 1 ] || miss10="$miss10 [$n]"; done
  for n in p_sronly p_sticky p_nested p_popup; do out=$(lyrun "$n"); [ "$(cnt "$out" "$n@390 배치 경고 L-OVERLAP(글자 겹침): ")" = 1 ] || miss10="$miss10 [$n]"; done
  for pr in 'p_wrapchip|L-WRAP-CHIP(칩 줄바꿈): |2' 'p_scrollx|L-SCROLL-X(가로 스크롤에 숨음): <nav.tabs>|1' 'p_cover|L-FIXED-COVER(고정 막대 가림): <div.bar>|1'; do
    n=${pr%%|*}; rest=${pr#*|}; key=${rest%|*}; want=${rest##*|}; out=$(lyrun "$n"); [ "$(cnt "$out" "$n@390 배치 경고 $key")" = "$want" ] || miss10="$miss10 [$n: $(printf '%s' "$out" | grep -F '배치' | head -3 | tr '\n' ' ')]"
  done
  [ -z "$miss10" ] && ok "U10e 양성 대조 — 제외 조건만 뺀 쌍 11개·왼쪽 가장자리 조각·좁은 폭 규칙 3종은 390 에서 적중(U10c 의 0건이 공허하지 않다)" || no "U10e" "미적중:$miss10"
  SSH="$PLUGIN/scripts/_internal/screen-shot.sh"
  out=$(bash "$SSH" "$LY/over.html" "$LY/shot-over" 2>&1); rc=$?
  if [ "$rc" -eq 3 ]; then sk "U10f (시스템 Chrome 없음 — 촬영 SKIP)"
  else [ "$rc" -eq 0 ] && [ "$(grep -c 'over@390 배치 경고 L-OVERLAP' "$LY/shot-over.probe.txt")" = 1 ] && ! grep -q 'over@1280' "$LY/shot-over.probe.txt" \
    && ok "U10f 촬영 스크립트 실물 — 실 Chrome·실 Playwright 로 찍으면 probe.txt 에 그 화면의 겹침이 남는다(AC-7)" || no "U10f" "rc=$rc [$out] [$(cat "$LY/shot-over.probe.txt" 2>&1)]"; fi
fi

# U4c — integration-test-ko 가 새 플래그를 Step 3b 안에서 쓰게 한다 (AC-6) — 절을 잘라 그 안에서만 본다
SEC=$(awk '/^### Step 3b/{f=1} /^## FAIL 분기/{f=0} f' "$INT")
miss=""; for n in '--memory .specops/memory/ui-probe.json' '--a11y-baseline .specops/memory/ui-a11y-baseline.json' '--mock screens/' '기록의 `startCmd`' '1회만' '`기준선 기록:`' '--a11y-baseline-update' '`기록 안 함:`'; do has "$SEC" "$n" || miss="$miss [$n]"; done
printf '%s\n' "$SEC" | grep -F -- '--storage-state' | grep -qF 'NO_ENV' || miss="$miss [--storage-state 와 NO_ENV 가 같은 줄]"
[ -z "$miss" ] && ok "U4c integration-test-ko Step 3b — 기록·기준선·목업 플래그 · startCmd 로 서버 · 1회만 질문 · 기준선 기록 줄 · 상태 파일 NO_ENV" || no "U4c" "없음:$miss"

# U4d — demo-ko 가 목업 PNG 를 같은 폭 구현 PNG 와 나란히 보여 준다 (AC-6) — 두 말이 같은 줄에 있어야 한다
grep -n -F '.mock.png' "$DEMO" | grep -qF '나란히' && grep -n -F '.mock.png' "$DEMO" | grep -qF '폭마다' \
  && ok "U4d demo-ko — .mock.png 와 구현 PNG 를 폭마다 나란히 (같은 줄)" || no "U4d" ".mock.png 와 나란히·폭마다가 같은 줄에 없다"

# U11 — 실패한 네트워크 요청(4xx·5xx·연결 실패): 경고만 · 판정 불변 · 쿼리 비출력 (20261113-debug-probe-hardening)
fix '{"a":{"responses":[{"status":200,"url":"http://h:1/ok"},{"status":500,"url":"http://h:1/api/items?token=SECRETVALUE#frag"},{"status":404,"url":"http://h:1/x.png"},{"status":500,"url":"http://h:1/api/items?token=OTHER"}]}}'
out=$(fk --out "$TMP/q1" --widths 390 http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = 'UI-PROBE: PASS (1화면·1폭 · 넘침 0 · 콘솔 오류 0 · 접근성 심각 0 · 요청 실패 2)' ] \
  && [ "$(printf '%s\n' "$out" | sed -n 2p)" = '  - a@390 요청 실패 경고: 500 GET http://h:1/api/items' ] \
  && [ "$(printf '%s\n' "$out" | sed -n 3p)" = '  - a@390 요청 실패 경고: 404 GET http://h:1/x.png' ] \
  && [ "$(node -e 'console.log(require(process.argv[1]).results[0].failedRequests.length)' "$TMP/q1/ui-probe.json")" = 2 ] \
  && ok "U11a 4xx·5xx 응답 — rc 0 · PASS · 요약에 건수 · 경고 줄 형식 · 같은 요청은 한 번 · 2xx 는 아님 · 기록에 같은 건수" || no "U11a" "rc=$rc [$out]"
! has "$out" 'SECRETVALUE' && ! has "$out" 'OTHER' && ! has "$out" 'frag' && ! grep -qE 'SECRETVALUE|OTHER|frag' "$TMP/q1/ui-probe.json" \
  && ok "U11b 쿼리·해시는 출력에도 기록에도 남지 않는다" || no "U11b" "[$out]"
fix '{"a":{"requestfailed":[{"error":"net::ERR_CONNECTION_REFUSED","method":"POST","url":"http://h:9/save?x=1"},{"error":"net::ERR_ABORTED","url":"http://h:1/nav"},{"url":"http://h:1/noinfo"}]}}'
out=$(fk --out "$TMP/q2" --widths 390 http://h:1/a 2>&1); rc=$?
[ "$rc" -eq 0 ] && has "$out" '요청 실패 2)' && has "$out" '  - a@390 요청 실패 경고: net::ERR_CONNECTION_REFUSED POST http://h:9/save' && has "$out" '  - a@390 요청 실패 경고: failed GET http://h:1/noinfo' && ! has "$out" 'ERR_ABORTED' \
  && ok "U11c 연결 실패 — 사유·메서드·주소 · 사유 없음은 failed · 중단(ERR_ABORTED)은 세지 않는다" || no "U11c" "rc=$rc [$out]"
fix '{"a":{"overflow":true,"responses":[{"status":503,"url":"http://h:1/api"}]}}'; out=$(fk --out "$TMP/q3" --widths 390 http://h:1/a 2>&1); rc=$?
fix '{"a":{"overflow":true}}'; out0=$(fk --out "$TMP/q4" --widths 390 http://h:1/a 2>&1); rc0=$?
[ "$rc" -eq 1 ] && [ "$rc0" -eq 1 ] && has "$out" '요청 실패 1)' && ! has "$out0" '요청 실패' \
  && ok "U11d 판정 불변 — 요청 실패가 있어도 없어도 같은 rc · 0건이면 요약·줄에 아무것도 안 붙는다" || no "U11d" "rc=$rc,$rc0 [$out|$out0]"
many=$(node -e 'console.log(JSON.stringify({a:{responses:Array.from({length:12},(_,i)=>({status:500,url:"http://h:1/r"+i}))}}))'); fix "$many"
out=$(fk --out "$TMP/q5" --widths 390 http://h:1/a 2>&1)
[ "$(cnt "$out" '요청 실패 경고: 500 GET ')" = 10 ] && has "$out" '  - a@390 요청 실패 경고: 외 2건' && has "$out" '요청 실패 12)' \
  && [ "$(node -e 'console.log(require(process.argv[1]).results[0].failedRequests.length)' "$TMP/q5/ui-probe.json")" = 12 ] \
  && ok "U11e 화면·폭마다 10줄까지 — 넘으면 '외 N건' · 요약과 기록은 전체 건수" || no "U11e" "[$out]"
got=$(node -e 'const s=require(process.argv[1]);console.log(JSON.stringify(["http://h:1/a/b?x=1#y","data:text/plain;base64,QUJD","blob:http://h:1/uuid","not a url","file:///tmp/dir/x.html?q=1","http://user:PASSWD@h:1/a?t=1","about:blank","javascript:alert(1)","chrome-extension://abc/x?y=1"].map((u)=>s.requestLabel(u))))' "$S")
[ "$got" = '["http://h:1/a/b","data:","blob:","(주소를 읽지 못함)","file:///tmp/dir/x.html","http://h:1/a","about:","javascript:","chrome-extension:"]' ] \
  && ok "U11f requestLabel — 쿼리·해시·userinfo 제거 · data:·blob:·origin 없는 스킴은 스킴만 · 읽지 못한 주소는 원문을 내지 않는다" || no "U11f" "$got"

# U4e — integration-test-ko 브라우저 줄에 배치 경고 건수·못 잰 것, 경고는 판정 불변 (AC-10)
_u4e() {  # $1=통합 테스트 스킬 본문 → 빠진 키
  local m=""
  printf '%s' "$1" | grep -F '**브라우저**: 실행(' | grep -qF '배치 경고 <N>' || m="$m [브라우저 줄:건수]"
  printf '%s' "$1" | grep -F '**브라우저**: 실행(' | grep -qF '계측 못 함 <M>' || m="$m [브라우저 줄:못 잼]"
  printf '%s' "$1" | grep -qF '경고는 판정을 바꾸지 않는다' || m="$m [판정 불변]"
  printf '%s' "$1" | grep -qF '0 이 아니라 그렇게 적는다' || m="$m [0 아님]"
  printf '%s' "$m"
}
_int=$(cat "$INT")
[ -z "$(_u4e "$_int")" ] && [ "$(_u4e "${_int//경고는 판정을 바꾸지 않는다/}")" = " [판정 불변]" ] && [ "$(_u4e "${_int//배치 경고 <N>/}")" = " [브라우저 줄:건수]" ] && [ "$(_u4e "${_int//0 이 아니라 그렇게 적는다/}")" = " [0 아님]" ] \
  && ok "U4e integration-test-ko — 브라우저 줄에 배치 경고 건수·못 잰 것 · 판정 불변 · 키를 지우면 그 키만 FAIL(AC-10)" || no "U4e" "없음:$(_u4e "$_int")"

# U4f — integration-test-ko 가 요청 실패 경고 줄을 evidence 로 옮기라 하고 판정 불변을 적는다
grep -F '`요청 실패 경고` 줄' "$INT" | grep -qF '판정 불변' && ok "U4f integration-test-ko — 요청 실패 경고 줄 · 판정 불변" || no "U4f" "문구 없음"

echo "── test-ui-probe: PASS=$PASS FAIL=$FAIL SKIP=$SKIPPED ──"
[ "$FAIL" -eq 0 ]
