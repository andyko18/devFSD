#!/usr/bin/env bash
# design-overview.sh — 설계 문서 → 읽기 전용 HTML 한 장 (20261008)
# 잠그는 계약: ① 그림(구성도·ERD·프로세스 흐름)이 실제로 그려진다 ② 외부 리소스 0 ③ 원문 HTML 은 이스케이프된다
#   ④ 미확정·가정·추적표·미연결 요구가 집계된다 ⑤ --check 가 원본 변경을 낡음으로 판정한다 ⑥ 문서 없음은 rc 2
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SH="$PLUGIN/scripts/design-overview.sh"

if ! command -v python3 >/dev/null 2>&1; then
  ok "D0 skipped — python3 미설치 (생성기의 유일한 의존)"
  finish
  exit 0
fi

_fx() {  # 최소 설계 문서 세트
  local d; d=$(mktemp -d); mkdir -p "$d/.specops/memory" "$d/screens"
  cat > "$d/PRD.md" <<'MD'
# 재고관리 PRD

## 1. 개요

**한 줄 설명**: 창고 재고를 추적한다

- 성능: <TODO — 응답시간>
- 프레임워크: <TODO — `a/b.md` 참조>
- 백엔드: `<미확정 — 근거 필요>`
- 표기: `형식: <TODO — x> 로 표기`
- 굵게: **굵게 <TODO — x> 끝**
- 링크: [문서 <TODO — x>](a/b.md)
- 위험 문자열: <script>alert(1)</script> 와 [링크](javascript:alert(1))
MD
  cat > "$d/.specops/memory/requirements.md" <<'MD'
# 요구사항

| ID | 설명 | 마일스톤 | 우선순위 |
|---|---|---|---|
| FR-1 | 입고 등록 | M1 | must |
| FR-2 | 출고 등록 | M2 | should |
MD
  cat > "$d/.specops/memory/process-design.md" <<'MD'
# 프로세스 설계서 — 재고관리

## 1. 프로세스 목록

| ID | 프로세스명 | 주 행위자 | 관련 FR |
|---|---|---|---|
| P-001 | 입고 처리 | 창고 담당 | FR-1 |

## 2. 프로세스 상세

### P-001 · 입고 처리

- **트리거**: 납품 도착
- **행위자**: 창고 담당
- **화면**: screens/inbound.md
- **API**: POST /v1/inbounds
- **테이블**: INBOUND, STOCK
- **결과**: 재고 증가. 가정: 검수는 즉시 끝난다
- **예외**: 수량 불일치 <미확정 — 근거 필요>
MD
  cat > "$d/.specops/memory/architecture.md" <<'MD'
# 전체 아키텍처

## 1. 시스템 컴포넌트

| 컴포넌트 | 역할 | 기술 | 비고 |
|---|---|---|---|
| Web | UI | Next.js 14 | |
| API | 로직 | <NestJS / Spring> | |

## 2. 컴포넌트 간 통신

| From → To | 프로토콜 | 인증 | 비고 |
|---|---|---|---|
| API → DB | SQL | 계정 | |

## 5. 시스템 다이어그램

```mermaid
graph TD
  User[사용자] --> Web[Web App]
  Web -->|REST| API[API Server]
  API --> DB[(Database)]
  API --> SMS[SMS 게이트웨이]
```
MD
  cat > "$d/.specops/memory/api-spec.md" <<'MD'
# IF 설계서

<!-- specops:example:start -->
| Method | Path | Auth | Request | Response | 비고 |
|---|---|---|---|---|---|
| GET | `/v1/users/:id` | Bearer | — | `User` | 예시 행 |
<!-- specops:example:end -->

| Method | Path | Auth | Request | Response | 비고 |
|---|---|---|---|---|---|
| POST | `/v1/inbounds` | Bearer | `Dto` | `Inbound` | 입고 등록 |
MD
  cat > "$d/.specops/memory/screens-overview.md" <<'MD'
# 화면 목록

| name | 제목 | 목적 | 상세 스펙 | 미리보기 |
|---|---|---|---|---|
| inbound | 입고 등록 | 납품 수량 입력 | [screens/inbound.md](../../screens/inbound.md) | 예정 |
| stock | 재고 조회 | 품목 검색 | [screens/stock.md](../../screens/stock.md) | 예정 |

```mermaid
stateDiagram-v2
  [*] --> 로그인 : 접속
  로그인 --> 대시보드 : 인증
```
MD
  cat > "$d/DESIGN.md" <<'MD'
# 디자인

| 토큰 | 값 |
|---|---|
| primary | `#2F5FD0` |
MD
  cat > "$d/.specops/memory/data-model.md" <<'MD'
# 테이블 설계서

```mermaid
erDiagram
  STOCK ||--o{ INBOUND : receives
  STOCK {
    uuid id PK
    int qty
  }
  INBOUND {
    uuid id PK
    uuid stock_id FK
  }
```

```mermaid
sequenceDiagram
  A->>B: 미지원 문법
```
MD
  : > "$d/screens/inbound.html"
  printf '%s' "$d"
}

d=$(_fx); OUT="$d/.specops/design-overview.html"
out=$(bash "$SH" "$d" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ -s "$OUT" ] && ok "D1 생성 rc0 + 파일 존재" || nope "D1" "rc=$rc out=$out"
H=$(cat "$OUT" 2>/dev/null)

# ① 그림 — 구성도(개요+본문 2회)·ERD·프로세스 흐름
n_svg=$(printf '%s' "$H" | grep -o '<svg ' | wc -l | tr -d ' ')
[ "$n_svg" -eq 4 ] && ok "D2 그림 4개 (구성도·업무 흐름·화면 흐름·ERD — 장 머리로 올린 그림은 본문에서 다시 그리지 않는다)" || nope "D2" "svg=$n_svg"
printf '%s' "$H" | grep -q 'API Server' && printf '%s' "$H" | grep -q 'aria-label="시스템 구성도"' && ok "D2b 구성도 노드·레이블" || nope "D2b" "구성도 부재"
printf '%s' "$H" | grep -q 'aria-label="ERD"' && printf '%s' "$H" | grep -q 'class="cf"' && printf '%s' "$H" | grep -q 'class="cfo"' \
  && printf '%s' "$H" | grep -q 'k-pk">PK' && ok "D2c ERD — 까마귀발(막대·원) + PK 표기" || nope "D2c" "ERD 통상 표기 부재"
printf '%s' "$H" | grep -q 'aria-label="프로세스 흐름 P-001"' && ok "D2d 프로세스 흐름" || nope "D2d" "흐름 부재"
# 통상 표기 — 계층형 구성도(계층 띠·외부 연계 칸·기술·프로토콜) · 스윔레인(레인·시작/끝·예외 분기) · 화면 흐름도
printf '%s' "$H" | grep -q 'band b-client' && printf '%s' "$H" | grep -q 'band b-app' && printf '%s' "$H" | grep -q 'band b-data' \
  && printf '%s' "$H" | grep -q 'band b-ext' && ok "D2f 구성도 — 계층 띠(사용자·애플리케이션·데이터) + 외부 연계 칸" || nope "D2f" "계층 띠 부재"
printf '%s' "$H" | grep -q '>Next.js 14<' && ! printf '%s' "$H" | grep -q 'class="at ty">&lt;NestJS' && ok "D2g 구성 요소 기술 표기(미채움 값은 제외)" || nope "D2g" "기술 표기"
printf '%s' "$H" | grep -q 'class="el" text-anchor="middle">SQL<' && printf '%s' "$H" | grep -q '>REST<' && ok "D2h 연결선 프로토콜(다이어그램 레이블 + §2 통신 표)" || nope "D2h" "프로토콜 레이블 부재"
printf '%s' "$H" | grep -q 'class="lanel"' && printf '%s' "$H" | grep -q '>서버 (API)<' && printf '%s' "$H" | grep -q 'class="en"' \
  && printf '%s' "$H" | grep -q 'fk ex">예외' && ok "D2i 업무 흐름도 — 레인·끝 표식·예외 분기" || nope "D2i" "스윔레인 부재"
printf '%s' "$H" | grep -q 'aria-label="화면 흐름도"' && printf '%s' "$H" | grep -q '>대시보드<' && ok "D2j 화면 흐름도(stateDiagram)" || nope "D2j" "화면 흐름도 부재"
# 미지원 문법은 그리지 않고 원문 코드로 남긴다
printf '%s' "$H" | grep -q '<pre><code>sequenceDiagram' && ok "D2e 미지원 mermaid → 원문 코드 유지" || nope "D2e" "원문 미보존"

# ② 외부 리소스 0 — 폐쇄망에서 열려야 한다
ext=$(printf '%s' "$H" | grep -oE '<(script|link|img|iframe)[^>]*(src|href)="(https?:)?//[^"]*"' | wc -l | tr -d ' ')
[ "$ext" -eq 0 ] && ok "D3 외부 리소스 참조 0" || nope "D3" "외부 참조 $ext 건"

# ③ 원문 HTML 이스케이프 · 위험 링크 제거
! printf '%s' "$H" | grep -q '<script>alert(1)</script>' && printf '%s' "$H" | grep -q '&lt;script&gt;alert(1)' \
  && ok "D4 문서 속 <script> 이스케이프" || nope "D4" "스크립트 미이스케이프"
! printf '%s' "$H" | grep -q 'href="javascript:' && ok "D4b javascript: 링크 제거" || nope "D4b" "위험 링크 잔존"

# ④ 집계 — 미확정 7(TODO·미확정)·가정 1 · 추적표 · 미연결 요구(FR-2)
printf '%s' "$H" | grep -q '미확정 7 · 가정 1' && ok "D5 미확정·가정 집계" || nope "D5" "$(printf '%s' "$H" | grep -o '미확정 [0-9]* · 가정 [0-9]*' | head -1)"
printf '%s' "$H" | grep -q 'POST /v1/inbounds' && printf '%s' "$H" | grep -q '추적표' && ok "D5b 추적표" || nope "D5b" "추적표 부재"
printf '%s' "$H" | grep -q '연결되지 않은 요구 1건' && printf '%s' "$H" | grep -A0 '연결되지 않은 요구' | grep -q 'FR-2' \
  && ok "D5c 프로세스 미연결 요구(FR-2) 고지" || nope "D5c" "미연결 요구 미고지"
printf '%s' "$H" | grep -q 'id="lead-ui"' && printf '%s' "$H" | grep -q 'href="../screens/inbound.html">미리보기' \
  && printf '%s' "$H" | grep -q '<code>stock</code>.*설계 전' && ok "D5d 화면 현황 — 목록 + 상태(미리보기 / 설계 전)" || nope "D5d" "화면 현황 부재"
printf '%s' "$H" | grep -q 'mth m-post">POST' && printf '%s' "$H" | grep -q 'pri p-must">must' && ok "D5f 통상 표기 배지 — HTTP 메서드·우선순위" || nope "D5f" "배지 부재"
api_sec=$(python3 -c 'import re,sys; m=re.search(r"id=\"lead-if\".*?</table>", sys.stdin.read(), re.S); print(m.group(0) if m else "")' < "$OUT")
printf '%s' "$api_sec" | grep -q '/v1/inbounds' && ! printf '%s' "$api_sec" | grep -q '/v1/users' \
  && ok "D5g API 목록 — 남은 예시 블록 행은 제외" || nope "D5g" "API 목록"
printf '%s' "$H" | grep -q 'id="lead-req"' && printf '%s' "$H" | grep -q 'class="mx"' && ok "D5h 요구사항 현황(마일스톤 × 우선순위)" || nope "D5h" "현황표 부재"
printf '%s' "$H" | grep -q 'class="sw" style="background:#2F5FD0"' && ok "D5i 색상 견본" || nope "D5i" "견본 부재"
printf '%s' "$H" | grep -q '<mark class="tbd">&lt;TODO — <code>a/b.md</code> 참조&gt;</mark>' \
  && ok "D5j 백틱이 섞인 자리표시도 강조(안의 코드는 유지)" || nope "D5j" "백틱 섞인 자리표시 미강조"
printf '%s' "$H" | grep -q '<code>&lt;미확정 — 근거 필요&gt;</code>' && ! printf '%s' "$H" | grep -q '`<mark class="tbd">' \
  && ok "D5k 백틱으로 통째 감싼 자리표시는 종전대로 code(백틱 비노출)" || nope "D5k" "백틱 감싼 자리표시 퇴행"
printf '%s' "$H" | grep -q '<code>형식: &lt;TODO — x&gt; 로 표기</code>' && ! printf '%s' "$H" | grep -q '`형식:' \
  && ok "D5l 백틱 코드 구간 안 자리표시는 구간 통째 code(mark 비침투)" || nope "D5l" "코드 구간 안 자리표시 퇴행"
printf '%s' "$H" | grep -q '<strong>굵게 <mark class="tbd">&lt;TODO — x&gt;</mark> 끝</strong>' \
  && printf '%s' "$H" | grep -q '<a href="[^"]*">문서 <mark class="tbd">&lt;TODO — x&gt;</mark></a>' \
  && ok "D5m 굵게·링크 안 자리표시도 마크업 유지" || nope "D5m" "굵게/링크 안 자리표시에서 마크업 풀림"
printf '%s' "$H" | grep -q '생성물 — 직접 수정하지 않는다' && ok "D5e 생성물 고지" || nope "D5e" "고지 부재"

# ⑨ 설계서 순서 — 전체 그림(시스템 구성) 먼저, 상세는 뒤 · 장 번호 · 프로세스는 그림과 설명이 한자리
order=$(python3 -c 'import re,sys
t=sys.stdin.read()
ids=["ch-intro","lead-sys","ch-req","ch-proc","ch-ui","ch-if","ch-data","ch-trace","lead-open"]
pos=[t.find("id=\"%s\"" % i) for i in ids]
print("OK" if all(p>=0 for p in pos) and pos==sorted(pos) else "BAD %s" % pos)' < "$OUT")
[ "$order" = "OK" ] && ok "D10 순서: 개요 → 시스템 구성도 → 요구사항 → 프로세스 → 화면 → 인터페이스 → 데이터 → 추적·미결" || nope "D10" "$order"
printf '%s' "$H" | grep -q '<span class="chn">1</span>개요' && printf '%s' "$H" | grep -q '<span class="chn">2</span>시스템 구성' && ok "D10b 장 번호(1 개요 · 2 시스템 구성)" || nope "D10b" "장 번호 부재"
[ "$(printf '%s' "$H" | grep -o 'aria-label="시스템 구성도"' | wc -l | tr -d ' ')" -eq 1 ] && printf '%s' "$H" | grep -q '이 그림은 장 머리에 있다' \
  && ok "D10c 구성도는 한 번만(본문에는 장 머리 안내 + 원문)" || nope "D10c" "구성도 중복"
proc=$(python3 -c 'import re,sys
t=sys.stdin.read()
m=re.search(r"<h4 id=\"[^\"]*\">P-001[^<]*</h4>\s*<figure class=\"dg\">.*?</figure>\s*<div class=\"tw\"><table><thead><tr><th>항목</th><th>내용</th>", t, re.S)
print("OK" if m else "BAD")' < "$OUT")
[ "$proc" = "OK" ] && ok "D10d 프로세스 — 제목 바로 아래 흐름도, 그 아래 정의 표(항목·내용)" || nope "D10d" "그림+설명 배치"
printf '%s' "$H" | grep -q 'href="../screens/inbound.md"' && ok "D10e 문서 상대 링크를 생성물 위치 기준으로 재기준" || nope "D10e" "링크 재기준 실패"
printf '%s' "$H" | grep -q 'class="banner"' && printf '%s' "$H" | grep -q 'class="lede">창고 재고를 추적한다' && ok "D10f 머리 — 한 줄 설명 + 미결 배너" || nope "D10f" "머리 부재"

# ⑤ --check: 최신 → 원본 변경 → 낡음
bash "$SH" --check "$d" >/dev/null 2>&1; [ $? -eq 0 ] && ok "D6 --check FRESH rc0" || nope "D6" "FRESH 아님"
before=$(cksum < "$OUT")
printf '\n추가 문장\n' >> "$d/PRD.md"
out=$(bash "$SH" --check "$d" 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'STALE' && ok "D6b 원본 변경 → STALE rc1" || nope "D6b" "rc=$rc out=$out"
[ "$before" = "$(cksum < "$OUT")" ] && ok "D6c --check 는 파일을 고치지 않는다" || nope "D6c" "파일 변경됨"
rm -f "$OUT"; bash "$SH" --check "$d" >/dev/null 2>&1; [ $? -eq 1 ] && ok "D6d 파일 없음 → rc1(MISSING)" || nope "D6d" "rc≠1"
rm -rf "$d"

# ⑥ 문서 없음 → rc2 · 사용 오류 → rc2
e=$(mktemp -d); bash "$SH" "$e" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$e/.specops/design-overview.html" ] && ok "D7 설계 문서 없음 → rc2 (빈 파일 미생성)" || nope "D7" "rc=$rc"
bash "$SH" --nope "$e" >/dev/null 2>&1; [ $? -eq 2 ] && ok "D7b 알 수 없는 옵션 → rc2" || nope "D7b" "rc≠2"
rm -rf "$e"

# ⑦ 채우지 않은 골격 템플릿만으로도 죽지 않는다(프로세스 0건·그림 없이 본문만)
t=$(mktemp -d); mkdir -p "$t/.specops/memory"
cp "$PLUGIN/templates/process-design.md" "$PLUGIN/templates/architecture.md" "$PLUGIN/templates/data-model.md" "$t/.specops/memory/"
out=$(bash "$SH" "$t" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ! grep -q 'aria-label="프로세스 흐름' "$t/.specops/design-overview.html" \
  && ok "D8 템플릿 골격만 → rc0 · 빈 골격 행은 프로세스로 세지 않음" || nope "D8" "rc=$rc out=$out"
# 실제 템플릿의 mermaid(graph·erDiagram)가 그려진다 — 템플릿이 바뀌어 파서 밖으로 나가면 여기서 잡힌다
grep -q 'aria-label="시스템 구성도"' "$t/.specops/design-overview.html" && grep -q 'aria-label="ERD"' "$t/.specops/design-overview.html" \
  && grep -q 'band b-app' "$t/.specops/design-overview.html" \
  && ok "D8b 실 템플릿의 구성도·ERD 렌더" || nope "D8b" "템플릿 mermaid 미렌더"
rm -rf "$t"

# ⑧ 생성 규칙 — 새 프로젝트의 .specops/.gitignore 가 생성물을 무시한다
grep -q '^design-overview\.html$' "$PLUGIN/scripts/_internal/init-project/phases-artifacts.sh" \
  && ok "D9 .specops/.gitignore 규칙에 생성물 무시" || nope "D9" "무시 규칙 부재"

finish
