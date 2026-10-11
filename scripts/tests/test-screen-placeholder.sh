#!/usr/bin/env bash
# test-screen-placeholder.sh — 화면 껍데기 마커 판정 헬퍼 검증 (FID 20260722-screen-design-quality)
# AC-1(껍데기 판정) · AC-2(정상 무해 통과) · AC-11(bash 3.2) · AC-12(마커 단일출처) · AC-13(함수 배치)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)

PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCRIPT="$PLUGIN/scripts/_internal/design-screen.sh"
PASS=0; FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 스크립트 상수에서 마커 토큰 추출 — 단일 출처 계약 (AC-12 ③)
MARKER=$(grep -m1 '^SCREEN_PLACEHOLDER_MARKER=' "$SCRIPT" | sed 's/^SCREEN_PLACEHOLDER_MARKER="\(.*\)"$/\1/')

# T1: 헬퍼가 design-screen.sh 내 함수로 존재 (AC-13 ①)
grep -qE '^screen_is_placeholder\(\)' "$SCRIPT" \
  && ok  "T1.a screen_is_placeholder() 함수가 design-screen.sh 내 정의" \
  || nope "T1.a screen_is_placeholder() 함수 정의" "design-screen.sh 에 함수 없음"

[ -n "$MARKER" ] \
  && ok  "T1.b SCREEN_PLACEHOLDER_MARKER 상수 정의 (단일 출처)" \
  || nope "T1.b SCREEN_PLACEHOLDER_MARKER 상수" "상수 미정의 또는 추출 실패"

# T2: 껍데기 판정 (AC-1) — fixture 는 마커를 포함한다
cat > "$TMP/shell.md" <<EOF
<!-- $MARKER — 실제 내용으로 채우면 이 줄을 삭제한다 -->
# login 화면 스펙
## 목적
[이 화면이 사용자에게 하는 일 — 1~2 문장]
EOF
bash "$SCRIPT" --check "$TMP/shell.md" >/dev/null 2>&1
[ $? -eq 0 ] \
  && ok  "T2.a 마커 잔존 .md → 껍데기 판정 (exit 0)" \
  || nope "T2.a 껍데기 판정" "exit 0 아님"

cat > "$TMP/shell.html" <<EOF
<!DOCTYPE html>
<!-- $MARKER — 실제 내용으로 채우면 이 줄을 삭제한다 -->
<html lang="ko"><body></body></html>
EOF
bash "$SCRIPT" --check "$TMP/shell.html" >/dev/null 2>&1
[ $? -eq 0 ] \
  && ok  "T2.b 마커 잔존 .html → 껍데기 판정 (exit 0)" \
  || nope "T2.b .html 껍데기 판정" "exit 0 아님"

# T3: 정상 화면 무해 통과 (AC-2 · M-2 핵심 단언)
# (20260806) 필수 8섹션 계약 확장에 맞춰 픽스처 갱신 — 원 의도(마커 부재 = 정상)는 보존.
cat > "$TMP/filled.md" <<'EOF'
# 로그인 화면 스펙
## 목적
사용자가 이메일과 비밀번호로 인증한다.
## Layout
[헤더] 로고
## Components
이메일 입력, 비밀번호 입력, 로그인 버튼
## States
초기 / 로딩 / 오류
## Interactions
로그인 버튼 → 대시보드 이동
## 필드 정의표
email(string, required), password(string, required)
## 데이터 소스
POST /auth/login
## 에러 메시지
자격 증명 불일치 시 안내
EOF
bash "$SCRIPT" --check "$TMP/filled.md" >/dev/null 2>&1
[ $? -eq 1 ] \
  && ok  "T3.a 마커 부재 .md → 정상 판정 (exit 1, false-trigger 0)" \
  || nope "T3.a 정상 판정" "exit 1 아님"

bash "$SCRIPT" --check "$TMP/none.md" >/dev/null 2>&1
[ $? -eq 1 ] \
  && ok  "T3.b 부재 파일 → 정상 집계 (잡음 방지)" \
  || nope "T3.b 부재 파일 처리" "exit 1 아님"

# T3.c: 혼합 인자 — 하나라도 껍데기면 exit 0 + 해당 경로 출력
out=$(bash "$SCRIPT" --check "$TMP/filled.md" "$TMP/shell.md" 2>/dev/null); rc=$?
{ [ $rc -eq 0 ] && echo "$out" | grep -q "PLACEHOLDER: $TMP/shell.md"; } \
  && ok  "T3.c 혼합 인자 → 껍데기 경로만 PLACEHOLDER 출력" \
  || nope "T3.c 혼합 인자" "rc=$rc out=$out"

# T4: 마커 단일 출처 계약 (AC-12 ①②) — 상수 토큰으로 두 템플릿 대조
grep -qF "$MARKER" "$PLUGIN/templates/screen.md" \
  && ok  "T4.a templates/screen.md 에 마커 존재 (상수 대조)" \
  || nope "T4.a screen.md 마커" "상수 토큰이 템플릿에 없음 — drift"

grep -qF "$MARKER" "$PLUGIN/templates/screen.html" \
  && ok  "T4.b templates/screen.html 에 마커 존재 (상수 대조)" \
  || nope "T4.b screen.html 마커" "상수 토큰이 템플릿에 없음 — drift"

# T4.c: 뮤테이션 — 판정이 템플릿 본문 리터럴이 아니라 마커에만 의존함을 입증 (AC-12 ③)
cat > "$TMP/mutated.md" <<EOF
<!-- $MARKER — 실제 내용으로 채우면 이 줄을 삭제한다 -->
# 완전히 다른 본문. 템플릿 리터럴 0개.
EOF
bash "$SCRIPT" --check "$TMP/mutated.md" >/dev/null 2>&1
[ $? -eq 0 ] \
  && ok  "T4.c 본문 리터럴 전무 + 마커만 → 여전히 껍데기 (본문 비의존)" \
  || nope "T4.c 본문 비의존" "본문 리터럴에 의존하는 판정 — AC-12 위반"

# 리터럴 잔존이 그 자체로 껍데기 판정을 유발하면 안 된다(AC-12) — 섹션은 모두 갖춘 상태로 검증.
cat > "$TMP/literal-only.md" <<'EOF'
## 목적
[이 화면이 사용자에게 하는 일 — 1~2 문장]
## Layout
- [ComponentName, 예: Button(primary)] — DESIGN.md §4
## Components
[컴포넌트 목록]
## States
[상태 목록]
## Interactions
[요소 → 결과]
## 필드 정의표
[필드 표]
## 데이터 소스
[출처]
## 에러 메시지
[문구]
EOF
bash "$SCRIPT" --check "$TMP/literal-only.md" >/dev/null 2>&1
[ $? -eq 1 ] \
  && ok  "T4.d 본문 리터럴 잔존 + 마커 부재 → 정상 (마커가 유일 기준)" \
  || nope "T4.d 마커 단독 기준" "리터럴 grep 회귀 — AC-12 위반"

# ── T6: 필수 8섹션 실채움 (20260806 specifying-ko 정밀분석) ──────────────────
# 결함: `--check` 는 `specops:screen-placeholder` **마커 유무**만 본다. 그런데 그 마커는
#   "채우면 이 줄을 삭제한다" 는 규약 — 즉 **모델이 스스로 지워 '채웠다'고 선언**하는
#   자기보고다. specifying-ko:151·design-screen(s) 이 선언한 **필수 8섹션**
#   (목적·Layout·Components·States·Interactions·필드 정의표·데이터 소스·에러 메시지)이
#   실제로 있는지 검사하는 층은 0곳이었다 → 마커만 지우면 반쯤 빈 화면이 FILLED 로 통과.
_mk8() {  # $1=경로 $2=제외할 섹션(빈 문자열이면 전부 포함)
  {
    printf '# 화면\n\n'
    for s in 목적 Layout Components States Interactions "필드 정의표" "데이터 소스" "에러 메시지"; do
      [ "$s" = "$2" ] && continue
      printf '## %s\n\n실제 내용 %s\n\n' "$s" "$s"
    done
  } > "$1"
}

# T6.a: 8섹션 전부 채움 + 마커 없음 → FILLED (통과)
_mk8 "$TMP/full8.md" ""
bash "$SCRIPT" --check "$TMP/full8.md" >/dev/null 2>&1 \
  && nope "T6.a 8섹션 완성" "PLACEHOLDER 로 오판" \
  || ok  "T6.a 8섹션 완성 → FILLED"

# T6.b: ★ 마커만 지우고 섹션 누락 → 미완으로 판정 (자기보고 차단)
_mk8 "$TMP/miss8.md" "Interactions"
out=$(bash "$SCRIPT" --check "$TMP/miss8.md" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'Interactions'; } \
  && ok  "T6.b 섹션 누락 → 미완 판정 + 누락 섹션 지목" \
  || nope "T6.b 자기보고 통과" "rc=$rc out=$out"

# T6.c: 섹션 헤더는 있으나 본문이 비었으면 미완 (헤더만 복사 방지)
{ printf '# 화면\n\n'
  for s in 목적 Layout Components States Interactions "필드 정의표" "데이터 소스" "에러 메시지"; do
    printf '## %s\n\n' "$s"
  done
} > "$TMP/empty8.md"
bash "$SCRIPT" --check "$TMP/empty8.md" >/dev/null 2>&1 \
  && ok  "T6.c 헤더만 있고 본문 빈 섹션 → 미완" \
  || nope "T6.c" "빈 본문을 완성으로 오판"

# T6.d: 조건부 4섹션 부재는 정상 (미해당 시 넣지 않는 규약)
_mk8 "$TMP/cond.md" ""
bash "$SCRIPT" --check "$TMP/cond.md" >/dev/null 2>&1 \
  && nope "T6.d 조건부 섹션" "RBAC 등 부재를 미완으로 오판" \
  || ok  "T6.d 조건부 4섹션 부재 → 정상"

# T6.e: .html 은 8섹션 대상 아님 (마커 판정만)
printf '<html><body>내용</body></html>\n' > "$TMP/ok.html"
bash "$SCRIPT" --check "$TMP/ok.html" >/dev/null 2>&1 \
  && nope "T6.e html" "html 에 섹션 요건 오적용" \
  || ok  "T6.e .html 은 마커 판정만"

# T5: bash 3.2 호환 (AC-11) — 연상배열·mapfile 미사용
grep -nE '^\s*(declare|local)\s+-A\b|^\s*mapfile\b|^\s*readarray\b' "$SCRIPT" >/dev/null 2>&1 \
  && nope "T5.a bash 3.2 호환" "연상배열/mapfile 사용 발견" \
  || ok  "T5.a bash 3.2 전용 문법 미사용 (연상배열·mapfile 0)"

finish
