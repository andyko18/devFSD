<!-- brand: Claude (AI-native, dark-first) -->

# DESIGN.md — specops-ko

> AI 에이전트용 디자인 시스템 문서. Claude 브랜드 스타일 기반.
> UI 컴포넌트 생성 시 이 파일을 읽고 일관된 스타일을 유지한다.

## 1. Color System

| Role | Value | Usage |
|---|---|---|
| Primary | `#7C3AED` | 주요 버튼, 링크, 강조 (Claude purple) |
| Secondary | `#A78BFA` | 보조 액션, 배지 |
| Background | `#0F0F10` | 페이지 배경 (다크 퍼스트) |
| Surface | `#1A1A1F` | 카드, 모달, 패널 |
| Text Primary | `#F9FAFB` | 본문 텍스트 |
| Text Secondary | `#9CA3AF` | 보조 텍스트, 레이블 |
| Error | `#EF4444` | 에러 상태 |
| Success | `#10B981` | 성공 상태 |
| Accent | `#E0C9FF` | 강조 텍스트, 하이라이트 |

**Gradient**: `linear-gradient(135deg, #7C3AED, #5B21B6)`

**Dark Mode**: 기본값이 다크. 라이트 모드 시 Background=`#FFFFFF`, Surface=`#F9FAFB`, Text Primary=`#111827`.

## 2. Typography

| Role | Font | Size | Weight | Usage |
|---|---|---|---|---|
| Heading 1 | Inter, system-ui | 2rem | 700 | 페이지 제목 |
| Heading 2 | Inter, system-ui | 1.5rem | 600 | 섹션 제목 |
| Body | Inter, system-ui | 1rem | 400 | 본문 |
| Caption | Inter, system-ui | 0.875rem | 400 | 보조 텍스트 |
| Code | JetBrains Mono, monospace | 0.875rem | 400 | 코드 블록, 인라인 코드 |

**Font Stack**: `Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif`

## 3. Spacing & Layout

- **Base Unit**: 4px
- **Spacing Scale**: 4, 8, 12, 16, 24, 32, 48, 64px
- **Max Content Width**: 1200px
- **Grid**: 12-column, 24px gutter
- **Border Radius**: 8px (default), 12px (large), 9999px (pill)

## 4. Components

### Button

```
Primary:   bg=#7C3AED, text=white, radius=8px, padding=8px 16px, hover=bg-#6D28D9
Secondary: bg=transparent, border=1px solid #7C3AED, text=#7C3AED, hover=bg-#7C3AED/10
Ghost:     bg=transparent, text=#9CA3AF, hover=text-#F9FAFB
Disabled:  opacity=0.5, cursor=not-allowed
```

### Input

```
Background: #1A1A1F
Border:     1px solid #374151
Focus:      border=#7C3AED, ring=2px #7C3AED/20
Error:      border=#EF4444
Radius:     8px
Text:       #F9FAFB, placeholder=#6B7280
Label:      입력마다 label 의 for 속성과 입력 id 를 짝지어 연결(감쌈·aria-label 허용), 선택지는 각자 label + fieldset·legend
```

### Card

```
Background: #1A1A1F
Border:     1px solid #374151
Radius:     12px
Shadow:     0 4px 6px -1px rgba(0,0,0,0.3)
Padding:    24px
```

### Badge

```
Default:   bg=#374151, text=#F9FAFB, radius=9999px, padding=2px 8px
Primary:   bg=#7C3AED/20, text=#A78BFA
Success:   bg=#10B981/20, text=#34D399
Error:     bg=#EF4444/20, text=#F87171
```

## 5. Design Principles

1. **AI-native 명확성**: 정보 계층을 명확히. 사용자가 AI 응답을 빠르게 스캔할 수 있게.
2. **미니멀리즘**: 장식 없이 기능에 집중. 여백이 콘텐츠. 불필요한 그래픽 요소 제거.
3. **다크 퍼스트**: 다크 모드가 기본. Claude 사용자의 야간·집중 작업 환경 최적화.

**Anti-patterns**:
- 밝은 배경(#FFFFFF) 남용 — 다크 퍼스트 원칙 위반
- 복잡한 그라디언트 배경 — Primary 그라디언트는 hero/CTA에만
- 14px 미만 본문 폰트
- 3개 이상 Primary 색상 동시 사용

## 6. AI Usage Guidelines

> specops-ko UI 컴포넌트 생성 시 이 지침을 따른다.

**컬러 사용**:
- Primary(`#7C3AED`)는 interactive 요소(버튼, 링크, 포커스 링)에만. 배경 전체 금지.
- 배경은 항상 `#0F0F10` 또는 `#1A1A1F`. 순백(#FFFFFF) 배경 금지.
- Accent(`#E0C9FF`)는 강조 텍스트·선택된 항목 하이라이트에만. 버튼·배경 사용 금지.
- 에러/성공 색상은 아이콘+텍스트 조합으로. 배경색만 사용 금지.

**타이포그래피**:
- Heading은 최대 2단계(H1, H2)만. H3 이하는 bold body로 대체.
- 코드 블록은 반드시 JetBrains Mono + 신택스 하이라이팅.

**컴포넌트 생성 시**:
- §4 Components 스펙 먼저 확인. 커스텀 스타일 추가 전 기존 variant 재사용.
- 입력마다 label 의 for 속성과 입력 id 를 짝지어 연결한다(감쌈·aria-label 도 허용, for 없이 형제로만 둔 label 은 연결이 아니다). 라디오·체크박스는 선택지마다 자기 label, 그룹 이름은 fieldset 과 legend.
- Tailwind CSS 사용 시: `violet-700`(Primary), `violet-400`(Secondary), `gray-900`(Background), `gray-800`(Surface), `red-500`(Error), `emerald-500`(Success).
- React 컴포넌트는 다크 모드 className 포함 (`dark:` prefix).
