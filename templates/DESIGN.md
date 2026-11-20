<!-- layer: Project-Document -->

# DESIGN.md — [Project Name]

> AI 에이전트용 디자인 시스템 문서. UI 컴포넌트 생성 시 이 파일을 읽고 일관된 스타일을 유지한다.

## 1. Color System

| Role | Value | Usage |
|---|---|---|
| Primary | `#______` | 주요 버튼, 링크, 강조 |
| Secondary | `#______` | 보조 액션, 배지 |
| Background | `#______` | 페이지 배경 |
| Surface | `#______` | 카드, 모달, 패널 |
| Text Primary | `#______` | 본문 텍스트 |
| Text Secondary | `#______` | 보조 텍스트, 레이블 |
| Border | `#______` | 그리드 라인, 카드 테두리 |
| Error | `#______` | 에러 상태 |
| Success | `#______` | 성공 상태 |
| Accent | `#______` | 강조 액션, 배지 |
| Muted | `#______` | 비활성 배경 |
| Ring | `#______` | 포커스 링 |
| On Primary | `#______` | Primary 위 텍스트 |
| On Secondary | `#______` | Secondary 위 텍스트 |
| On Accent | `#______` | Accent 위 텍스트 |
| Card Foreground | `#______` | 카드 내 텍스트 |
| On Destructive | `#______` | Error 위 텍스트 |

**Gradient**: [사용 시 방향·색 기재 — 없으면 "Not applicable"]

**Dark Mode**: [다크 모드 색상 변형 또는 "Not applicable"]

## 2. Typography

| Role | Font | Size | Weight | Usage |
|---|---|---|---|---|
| Heading 1 | [font], system-ui | 2rem | 700 | 페이지 제목 |
| Heading 2 | [font], system-ui | 1.5rem | 600 | 섹션 제목 |
| Body | [font], system-ui | 1rem | 400 | 본문 |
| Caption | [font], system-ui | 0.875rem | 400 | 보조 텍스트 |
| Code | [monospace] | 0.875rem | 400 | 코드 블록 |

**Font Stack**: `[primary], -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif`

**Font Import**: [웹폰트 사용 시 @import 또는 link 태그 — 없으면 시스템 폰트]

## 3. Spacing & Layout

- **Base Unit**: `[N]px` (예: 4px 또는 8px)
- **Spacing Scale**: `4, 8, 12, 16, 24, 32, 48, 64px`
- **Max Content Width**: `[N]px`
- **Grid**: `12-column, [N]px gutter`
- **Border Radius**: `[N]px` (default), `[N]px` (large), `9999px` (pill)

## 4. Components

> DESIGN.md 생성 시: 아래 코드 블록의 `[placeholder]` 값을 §1·§2·§3 실제 값으로 치환한다.

### Button

```
Primary:   bg=[primary], text=white, radius=[N]px, padding=[N]px [N]px
Secondary: bg=transparent, border=1px solid [primary], text=[primary]
Disabled:  opacity=0.5, cursor=not-allowed
```

### Input

```
Border:     1px solid [border-color]
Focus:      border=[primary], ring=[primary]/20
Error:      border=[error]
Radius:     [N]px
Background: [surface]
Label:      입력마다 label 의 for 속성과 입력 id 를 짝지어 연결(감쌈·aria-label 허용), 선택지는 각자 label + fieldset·legend
```

### Card

```
Background: [surface]
Border:     1px solid [border-color]
Radius:     [N]px
Shadow:     [shadow-definition]
Padding:    [N]px
```

## 5. Motion

| 상황 | 지속 | 이징 | 비고 |
|---|---|---|---|
| Hover Micro-interaction | [ms] | [easing] | [설명] |
| Scroll Reveal | [ms] | [easing] | [설명] |
| Stagger List | [ms] | [easing] | [설명] |

> 값은 머리의 디자인 방향 MOTION 다이얼에 맞춰 프로젝트가 정한다(낮을수록 짧고 절제된 전환).

## 6. 레이아웃 패턴

- **권장 패턴**: [권장 레이아웃 패턴 — §6.1 원형 기준]
- **스타일 우선순위**: [스타일 우선순위]
- **핵심 효과**: [핵심 효과]

## 6.1 화면 원형

> 아래는 **기본값**이다. 프로젝트 성격이 다르면 행을 교체·삭제한다.

| 원형 | 필수 요소 | 흔한 누락 |
|---|---|---|
| 목록 | 검색/필터 · 정렬 기준 · 행 액션 · 페이지네이션(또는 무한 스크롤) · 빈 상태 | 빈 상태, 정렬 기준 |
| 상세 | 제목+식별자 · 핵심 속성 그룹 · 관련 목록 · 주 액션 1개 강조 · 뒤로가기 | 주 액션 위계 |
| 폼 | 라벨(placeholder 로 대체 금지 · for 속성과 입력 id 로 연결) · 필수 표시 · 인라인 검증 · 제출 중 비활성 · 취소 경로 | 제출 중 상태, 취소 경로 |
| 다단 폼 | 단계 표시 · 이전·다음 이동 · 단계별 검증 · 중간 저장(또는 이탈 시 입력 보존) · 제출 중 비활성 · 취소 경로 | 중간 저장, 이전 단계 이동 |
| 대시보드 | 핵심 지표 3~5개 · 기간 선택 · 지표별 추세 · 드릴다운 링크 | 기간 선택, 드릴다운 |

### 장르 규칙

> 원형을 선언한 화면(`screens/*.md` 머리의 `**원형**:`)에 적용한다. **계측** 규칙은 화면 품질 계측기의 `genre=` 축이 키워드로 짚는다 — 언급 여부만 보는 근사이며 차단하지 않는다. **산문** 규칙은 리뷰어가 판단한다.
> 의도적으로 따르지 않는 규칙은 화면 스펙에 `<!-- genre-override: <규칙 ID> <사유> -->` 를 적는다. 사유 없는 override 는 억제되지 않는다.

| ID | 원형 | 규칙 | 판정 |
|---|---|---|---|
| G-LIST-PAGING | 목록 | 페이징(또는 무한 스크롤)과 총 건수를 함께 보인다 | 계측 |
| G-LIST-SORT | 목록 | 기본 정렬 기준을 밝힌다 | 계측 |
| G-LIST-EMPTY-KIND | 목록 | 빈 상태를 '데이터 없음'(첫 등록 유도)과 '검색·필터 결과 없음'(조건 초기화)으로 나눈다 | 계측 |
| G-FORM-SUBMIT | 폼 · 다단 폼 | 제출 중에는 제출 버튼을 비활성화해 중복 제출을 막는다 | 계측 |
| G-FORM-CANCEL | 폼 · 다단 폼 | 취소 경로를 둔다 | 계측 |
| G-WIZARD-STEP | 다단 폼 | 단계 표시 · 이전 단계 이동 · 중간 저장(또는 이탈 시 입력 보존)을 둔다 | 계측 |
| G-DASH-PERIOD | 대시보드 | 기간 선택을 둔다 | 계측 |
| G-TABLE-ALIGN | 표가 있는 화면 | 숫자·금액 열은 우측 정렬, 긴 표는 헤더 고정, 행 높이는 DENSITY 다이얼을 따른다 | 산문 |
| G-PAGING-SERVER | 목록 | 대량 데이터는 서버 페이징 — 페이지 크기 선택, 현재 페이지·필터를 URL 에 보존한다 | 산문 |
| G-RBAC-VISIBILITY | 전체 | 권한 없는 기능은 숨김과 비활성 중 기준을 정해 일관되게 따르고, 비활성이면 사유를 보인다 | 산문 |

## 7. 상태 표현

| 상태 | 표현 | 비고 |
|---|---|---|
| 로딩 | 300ms 초과가 예상되면 **스켈레톤**(레이아웃 형태 유지). 300ms 이하는 표시하지 않는다. 버튼 등 국소 동작은 인라인 스피너 | 기본값 — 300ms 이하 표시는 깜빡임을 만든다 |
| 빈 상태 | **설명 문구 + 다음 행동 CTA** 필수. 일러스트는 선택. "데이터 없음" 단독 금지 | 기본값 — 근거 자료 없이 정한 규약이다. 프로젝트에서 교체 가능 |
| 에러 | **입력 단위 인라인 메시지 + 폼 상단 요약 배너** 병행. 전체 화면 에러는 페이지 전체 실패에만 | 기본값 — 입력 근처 피드백이 수정 비용을 줄인다 |

## 8. Design Principles

1. **[원칙 1]**: [설명]
2. **[원칙 2]**: [설명]
3. **[원칙 3]**: [설명]

**Anti-patterns** (피해야 할 것):
- [금지 패턴 1]
- [금지 패턴 2]

## 9. AI Usage Guidelines

> 이 섹션을 AI 에이전트가 직접 읽어 일관된 UI를 생성한다.

**컬러 사용**:
- Primary 색상은 CTA(Call-to-Action) 요소에만 사용. 배경 전체에 남용 금지.
- [추가 컬러 지침]

**타이포그래피**:
- Heading은 최대 2단계(H1, H2)만 사용.
- [추가 타이포 지침]

**컴포넌트 생성 시**:
- 항상 §4 Components 스펙 참조. 커스텀 스타일 추가 전 기존 variant 확인.
- 입력마다 label 의 for 속성과 입력 id 를 짝지어 연결한다(감쌈·aria-label 도 허용, for 없이 형제로만 둔 label 은 연결이 아니다). 라디오·체크박스는 선택지마다 자기 label, 그룹 이름은 fieldset 과 legend.
- [프레임워크별 지침 — 예: "Tailwind 사용 시 CSS 변수 우선"]
