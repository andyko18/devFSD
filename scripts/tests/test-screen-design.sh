#!/usr/bin/env bash
# test-screen-design.sh — 화면 목업 품질 (20261109-screen-quality)
#   frontend-design · 다른 디자인 도구와의 격차 진단: devFSD 는 질문 없이 템플릿으로 즉시 만들고 결과를 렌더해 보지 않았다.
#   템플릿은 보라+다크 기본에 부품 3개(카드·버튼·입력)뿐이었고, 호버·포커스에 보라가 하드코딩돼 팔레트를 바꿔도 샜다.
#   ① 템플릿: 보라 하드코딩 0 · 업무 화면 부품 · 바닥선(포커스·좁은 폭·움직임 줄이기) · 파생 색은 주색에서
#   ② screen-shot.sh: 두 폭 촬영 · 찍지 못하면 SKIP(rc 3 — 통과로 위장하지 않음)
#   ③ frontend-design 원문(Apache-2.0)을 그대로 들여와 따르고, devFSD 보충(판단 지원·상태·토큰 이름·촬영)과 생성 지시 3곳을 연결
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
H="$PLUGIN/templates/screen.html"; G="$PLUGIN/templates/screen-design-guide.md"; SS="$PLUGIN/scripts/_internal/screen-shot.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
ok() { PASS=$((PASS+1)); echo "PASS $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL $1 — $2"; }

# T1 — 보라 하드코딩 0 (기본값·호버·포커스 어디에도)
if grep -qiE '#7C3AED|#6D28D9|#A78BFA|124, ?58, ?237' "$H"; then no "T1 보라 하드코딩" "$(grep -niE '#7C3AED|#6D28D9|#A78BFA|124, ?58, ?237' "$H" | head -2)"
else ok "T1 템플릿에 보라 하드코딩 없음(기본·호버·포커스)"; fi
# T2 — 파생 색은 주색에서 만든다(팔레트를 바꾸면 함께 바뀐다)
for v in -- '--color-primary-hover: color-mix' '--color-primary-soft: color-mix' '--color-ring: color-mix'; do [ "$v" = -- ] && continue
  grep -qF -- "$v" "$H" || { no "T2 파생 색" "없음: $v"; continue; }; done
grep -qF -- '--color-primary-hover: color-mix' "$H" && grep -qF -- '--color-ring: color-mix' "$H" && ok "T2 호버·포커스·옅은 색은 주색에서 color-mix 로 파생"
# T3 — 업무 화면 부품
miss=""; for c in app-shell sidebar nav-item topbar page-header toolbar table badge badge-success badge-warning badge-error tabs kpi pagination alert empty-state skeleton modal toast form-grid btn-ghost btn-danger; do
  grep -qE "\\.${c}[ {,:.\[]" "$H" || miss="$miss $c"; done
[ -z "$miss" ] && ok "T3 업무 화면 부품 22종 정의" || no "T3 부품" "없음:$miss"
# T4 — 바닥선
grep -qF ':focus-visible' "$H" && grep -qE '@media \(max-width: ?768px\)' "$H" && grep -qF 'prefers-reduced-motion' "$H" \
  && ok "T4 바닥선 — 포커스 링 · 좁은 폭 · 움직임 줄이기" || no "T4 바닥선" "focus-visible·768 미디어·reduced-motion 중 없음"
# T5 — 본문이 가운데 400px 카드 하나가 아니다(앱 셸 골격) · 실제 입력은 주석 밖에 없다(계측 0/0 계약)
! grep -qF 'max-width: 400px' "$H" && grep -qF 'class="app-shell"' "$H" && ok "T5 본문 골격은 앱 셸(가운데 좁은 카드 아님)" || no "T5 본문" "가운데 카드 잔존 또는 앱 셸 없음"
body_outside=$(awk '/<!--/{c=1} !c{print} /-->/{c=0}' "$H" | grep -ciE '<(input|select|textarea)[ >]')
[ "$body_outside" -eq 0 ] && ok "T5b 주석 밖 실제 입력 0개" || no "T5b" "주석 밖 입력 ${body_outside}개"

# T6 — screen-shot.sh: 인자 오류 rc 2 · 지정 Chrome 이 없으면 SKIP rc 3(통과 위장 금지)
bash "$SS" >/dev/null 2>&1; [ $? -eq 2 ] && ok "T6a 인자 없음 → rc 2" || no "T6a" "rc 2 아님"
out=$(SCREEN_SHOT_CHROME=/nonexistent/chrome bash "$SS" "$H" "$TMP/x" 2>&1); rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q '^SCREEN-SHOT: SKIP (찍지 못함' && [ ! -e "$TMP/x@1280.png" ] \
  && ok "T6b Chrome 없음 → SKIP(rc 3) · 파일 없음" || no "T6b" "rc=$rc out=[$out]"
# T6c — Chrome 이 있으면 실제로 두 장을 만든다(없는 환경은 SKIP — 이 검사는 위장하지 않는다)
out=$(bash "$SS" "$H" "$TMP/real" 2>&1); rc=$?
if [ "$rc" -eq 3 ]; then echo "SKIP T6c (이 환경에 Chrome 없음)"
elif [ "$rc" -eq 0 ] && [ -s "$TMP/real@1280.png" ] && [ -s "$TMP/real@390.png" ]; then ok "T6c Chrome 있음 → 1280·390 두 장 생성"
else no "T6c" "rc=$rc out=[$out]"; fi

# T7 — frontend-design 원문을 그대로 들여왔다(Apache-2.0 고지·라이선스 사본) + devFSD 보충 지침
FD="$PLUGIN/templates/frontend-design-guide.md"; FDL="$PLUGIN/templates/frontend-design-LICENSE.txt"
miss=""; for n in '# Frontend Design' 'Work in two passes' 'Spend your boldness in one place' 'the SaaS-card kit' 'taking screenshots to review' 'Errors don'"'"'t apologize'; do grep -qF -- "$n" "$FD" || miss="$miss [$n]"; done
[ -z "$miss" ] && ok "T7a frontend-design 원문 핵심 문장 6종 그대로" || no "T7a" "없음:$miss"
grep -qF 'Apache License 2.0' "$FD" && grep -qF '원문 그대로' "$FD" && grep -qF 'Apache License' "$FDL" && grep -qF 'Version 2.0' "$FDL" \
  && ok "T7b 출처·Apache 2.0 고지 + 라이선스 전문 사본" || no "T7b" "출처 고지 또는 LICENSE 사본 없음"
miss=""; for n in 'frontend-design-guide.md' 'frontend-design 원문이 우선' '판단 지원' '증감' '진행·대비 막대' 'check-mock-css.sh' 'screen-shot.sh' '확인한 척하지 않는다'; do grep -qF -- "$n" "$G" || miss="$miss [$n]"; done
[ -z "$miss" ] && ok "T7c 보충 지침 — 원문 우선 · 판단 지원 · 토큰 이름(이식 검사) · 촬영 · 정직" || no "T7c" "없음:$miss"
grep -qF '강조색은 화면당 한 곳' "$G" && no "T7d" "지나친 절제 규칙(강조 한 곳)이 남아 있다 — 블라인드 비교에서 판단 지원 부족의 원인" || ok "T7d '강조색은 화면당 한 곳' 규칙 제거"

# T8 — 생성 지시 3곳 연결 (Step 5.5 · /design-screen · /design-screens)
for f in skills/specifying-ko/SKILL.md commands/design-screen.md commands/design-screens.md; do
  grep -qF 'frontend-design-guide.md' "$PLUGIN/$f" && grep -qF 'screen-design-guide.md' "$PLUGIN/$f" && grep -qF 'screen-shot.sh' "$PLUGIN/$f" \
    && ok "T8 $f — frontend-design 원문 → 보충 → 찍고 다듬기" || no "T8 $f" "원문·보충·촬영 연결 없음"
done

echo "── test-screen-design: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
