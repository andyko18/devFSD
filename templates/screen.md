---
screen: "{{name}}"
title: "{{화면 제목}}"
created: "{{created}}"
updated: "{{updated}}"
---

<!-- reference: specops-ko templates/screen.md -->
<!-- layer: Project-Document -->
<!-- specops:screen-placeholder — 실제 내용으로 채우면 이 줄을 삭제한다 -->

# {{화면 제목}} 화면 스펙

> AI 에이전트용 화면 설계 문서. `/design-screen` 커맨드로 생성.
> HTML 미리보기: `screens/{{name}}.html`

**관련 FR**: [FR-N, … — 이 화면이 구현하는 요구사항 ID(`.specops/memory/requirements.md`). 공통 셸 화면이면 `공통`]

**원형**: [목록 | 상세 | 폼 | 다단 폼 | 대시보드 | 기타 — 복합 화면은 쉼표로 나열(예: 목록, 상세). 원형별 장르 규칙은 DESIGN.md §6.1]

## 목적

[이 화면이 사용자에게 하는 일 — 1~2 문장]

## Layout

[헤더]  로고 / 네비게이션
[본문]  메인 컨텐츠 영역
[하단]  액션 버튼 / 링크

## Components

- [ComponentName, 예: Button(primary)] — DESIGN.md §4
- [ComponentName, 예: Input(email)] — DESIGN.md §4
- [ComponentName, 예: Card] — DESIGN.md §4

## States

- Default: [초기 상태 설명]
- Empty: [빈 상태 — 목록이면 '처음부터 비어 있음'과 '조건에 맞는 항목 0건'을 나눠 적는다 · DESIGN.md §6.1 G-LIST-EMPTY-KIND]
- Loading: [로딩 중 상태]
- Error: [에러 발생 상태]
- Success: [성공/완료 상태]

## Interactions

- [요소] 클릭/입력 → [결과 또는 이동할 화면]
- [요소] 클릭/입력 → [결과 또는 이동할 화면]

## 필드 정의표

| 필드 | 라벨 | 타입 | 필수 | 검증 규칙 | 기본값 |
|---|---|---|---|---|---|
| [field] | [화면 표시 라벨] | [text/number/select/date] | Y/N | [예: 이메일 형식, 8자 이상] | [없으면 —] |

> 입력 필드가 없는 화면(조회 전용)이면 표 대신 "입력 필드 없음 — 조회 전용" 한 줄.

## 데이터 소스

| 용도 | 엔드포인트 / 테이블 | 출처 문서 |
|---|---|---|
| [목록 조회] | `GET /api/[resource]` | `.specops/memory/api-spec.md` §[섹션] |
| [저장] | `POST /api/[resource]` | `.specops/memory/api-spec.md` §[섹션] |
| [영속 데이터] | `[table_name]` | `.specops/memory/data-model.md` §3 |

> Step 5.6(인터페이스 design-first)의 마스터 문서를 **참조**한다 — 여기서 새 엔드포인트·테이블을 발명하지 않는다. 아직 없으면 Step 5.6 에서 먼저 정의할 것.

## 에러 메시지

| 상황 | 사용자에게 보이는 문구 | 복구 경로 |
|---|---|---|
| [입력 검증 실패] | [예: 이메일 형식이 올바르지 않습니다] | [해당 필드 포커스] |
| [네트워크 실패] | [예: 연결에 실패했습니다. 다시 시도해 주세요] | [재시도 버튼] |
| [권한 없음] | [예: 접근 권한이 없습니다] | [이전 화면으로] |

---

<!-- 아래 4개는 조건부 섹션 — 적용 조건에 해당할 때만 남기고, 미해당이면 섹션 자체를 넣지 않는다. -->
<!-- `—` 나 "해당 없음" 으로 채우지 말 것 (batch N화면 토큰 낭비 + 빈 껍데기 재생산). -->

## RBAC 권한별 표시

> **적용 조건**: 이 화면이 사용자 역할·권한에 따라 다르게 보인다.

| 역할 | 보이는 요소 | 숨김/비활성 |
|---|---|---|
| [admin] | [전체] | — |
| [user] | [읽기 영역] | [삭제 버튼] |

## 반응형 브레이크포인트

> **적용 조건**: 이 화면이 모바일·태블릿·데스크톱에서 레이아웃이 달라진다.

| 브레이크포인트 | 레이아웃 변화 |
|---|---|
| < 768px | [1단 스택, 사이드바 → 햄버거] |
| ≥ 1024px | [2단 그리드] |

## 접근성

> **적용 조건**: 이 화면에 폼 입력·모달·커스텀 인터랙션이 있다.

- 키보드: [Tab 순서 / Esc 로 모달 닫기]
- 스크린리더: [aria-label 이 필요한 요소]
- 입력 이름: 입력마다 label 의 for 속성과 입력 id 로 연결한다(label 이 입력을 감싸거나 aria-label 도 허용, for 없이 형제로만 둔 label 은 연결이 아니다). 라디오·체크박스는 선택지마다 자기 label, 그룹 이름은 fieldset 과 legend 로 둔다
- 대비: [DESIGN.md 팔레트 기준 WCAG AA 충족 여부]

## 진입/이탈 경로

> **적용 조건**: 이 화면이 다른 화면과 라우팅으로 연결된다(단독 랜딩이 아니다).

| 방향 | 화면 | 조건 |
|---|---|---|
| 진입 | [screens/<name>.md] | [예: 로그인 성공 시] |
| 이탈 | [screens/<name>.md] | [예: 저장 완료 시] |
