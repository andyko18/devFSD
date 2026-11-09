---
name: design-screen
disable-model-invocation: true
description: "[lifecycle 밖] 화면 1개 설계 — screens/ 에 .md+.html 쌍 생성/수정. lifecycle 안은 Step 5.5(단일)·Phase 2.5-A(batch) 가 자동 처리"
triggers:
  - "/design-screen"
mode: ask
specops_version: 3.1.21
specops_layer: Lifecycle-Tool
reference_upstream: specops-ko 독자 추가
---

# /design-screen [name]

## 목적

`screens/{name}.md` (화면 스펙) + `screens/{name}.html` (HTML 미리보기)을 생성하거나 수정한다.
`scripts/_internal/design-screen.sh`가 보일러플레이트(파일 스캐폴딩·DESIGN.md 색상 추출·screens-overview.md 갱신)를 자동 처리하고, Claude는 레이아웃·컴포넌트 콘텐츠 생성에 집중한다.

## 화면 설계 경로 분업

| 경로 | 진입 | 언제 쓰나 |
|---|---|---|
| **specifying Step 5.5** (인라인) | lifecycle 자동 (UI 기능 spec 승인 직후) | `/start` 흐름 중 — **별도 호출 불필요**. **`/start-all` batch는 SKIP** → Phase 2.5-A. **`/start-foundation`은 셸만**(`app-shell`·`layout`·`login` + `<!-- foundation-shell -->`) |
| **`/start-all` Phase 2.5-A** | batch 오케스트레이터 | 전 FR 화면 1회 통합. 이어서 IF(2.5-B) → **`design-reviewer-ko`(2.5-D)** |
| **`/design-screen [name]`** | 독립 슬래시 | lifecycle 밖에서 **화면 1개** 신규/수정 |
| **`/design-screens`** | 독립 슬래시 | lifecycle 밖에서 **여러 화면 일괄** (목록 자동판단 + 승인게이트 + 순차루프) |

> `/init-project` Phase 11 이 화면 `.md`+`.html` **본설계**를 채운다(UI KIND). 이후 Step 5.5·Phase 2.5-A 는 채워진 화면을 `--check` 로 **재사용**하고, 그 화면에 남은 `<미확정 — 근거 필요>` 만 FR 확정분으로 메운다.
> 즉 `/start` 로 UI 기능 개발 중이면 Step 5.5 가 자동 처리하므로 `/design-screen` 을 따로 부를 필요 없다. 독립 화면 작업 시에만 단수/복수 슬래시 사용.

## Process

### Step 1: 스크립트로 스캐폴딩

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/design-screen.sh {name}
```

- **파일이 이미 존재하면**: exit 1 + 안내 출력. 덮어쓰려면:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/design-screen.sh {name} --force
  ```
- **성공 시**: `screens/{name}.md` + `screens/{name}.html` 생성, `.specops/memory/screens-overview.md` 표 자동 갱신

### Step 2: 화면 목적·레이아웃 질문

사용자에게:

> "화면 설계를 시작합니다. 다음 정보를 알려주세요:
>
> 1. 이 화면의 **목적**은 무엇인가요? (1~2 문장)
> 2. 주요 **컴포넌트**는 무엇인가요? (예: 로그인 버튼, 이메일 입력)
> 3. 이 화면에서 다음으로 이동하는 **화면**이 있나요?"

### Step 3: HTML artifact 생성

스크립트가 이미 기본 HTML 구조를 생성했으므로, 사용자 답변 기반으로 **레이아웃·컴포넌트 내용만** 채운 HTML artifact를 생성한다. `templates/frontend-design-guide.md`(frontend-design 원문)를 그대로 따른다 — 디자인 계획을 `.md` 의 `## 디자인 계획` 절에 쓰고 흔한 기본값인지 검토한 뒤 작성하고, 업무 화면 보충은 `templates/screen-design-guide.md` 를 따른 뒤, 그 ③대로 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/screen-shot.sh screens/{name}.html .specops/shots/{name}` 로 1280·390 두 장을 찍어 Read 로 보고 자가 점검 7줄로 1~2회 다듬은 뒤 보여 준다(20261109):
- `screens/{name}.html`에 이미 `--color-primary` CSS 변수가 DESIGN.md 색상으로 설정됨
- 컴포넌트는 `.btn`, `.input`, `.card` 클래스 사용 (DESIGN.md §4 준수)
- `<main>` 영역에 실제 화면 마크업 작성
- **DESIGN.md 준수**: 화면 작성 시 `DESIGN.md` **§2 타이포·§3 간격** · §6 레이아웃 패턴 · §6.1 화면 원형 · §7 상태 표현 · §8 원칙/안티패턴 · §9 AI 지침을 읽고 따른다 (DESIGN.md 부재 시 skip).
- **입력 접근성**: 입력(input·select·textarea)마다 label 의 for 속성과 입력 id 를 같은 값으로 짝지어 연결한다(label 이 입력을 감싸거나 aria-label 도 허용 — for 없이 형제로만 둔 label 은 연결이 아니다). 라디오·체크박스는 선택지마다 자기 label 을 두고 그룹 이름은 fieldset 과 legend 로 둔다. 템플릿 html 의 주석 속 입력 예시를 복사해 쓴다.

사용자에게 artifact를 보여주고 수정 요청을 받는다:
> "위 HTML 미리보기를 확인해 주세요. 수정이 필요하시면 말씀해 주세요. 진행할까요? [y/n]"

- `y` 또는 수정 없음 → Step 4 진행
- `n` 또는 수정 요청 → HTML artifact 재생성 후 재확인 루프

### Step 4: 파일 저장

승인 후 `screens/{name}.md` + `screens/{name}.html`에 실제 콘텐츠를 채워 저장:
- screen.md: **필수 8섹션**(목적 · Layout · Components · States · Interactions · 필드 정의표 · 데이터 소스 · 에러 메시지) 완성. 조건부 4섹션(RBAC 권한별 표시 · 반응형 브레이크포인트 · 접근성 · 진입/이탈 경로)은 해당할 때만 남기고, 미해당이면 **섹션 자체를 넣지 않는다**(`—` 채우기 금지). 채운 뒤 껍데기 **마커 줄을 삭제**한다.
- screen.html: Step 3에서 승인한 HTML로 교체
- `screens-overview.md` 갱신은 Step 1 스크립트가 이미 완료

### Step 5: git commit

```bash
git add screens/{name}.md screens/{name}.html
git add .specops/memory/screens-overview.md 2>/dev/null || true
git commit -m "feat(screens): {name} 화면 설계 추가"
```

## 사용 예

```
/design-screen dashboard
→ bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/design-screen.sh dashboard
  → screens/dashboard.md + screens/dashboard.html 생성
  → DESIGN.md Primary 색상 추출 → --color-primary 주입
  → screens-overview.md 표 갱신
→ "이 화면의 목적은..." 질문
→ 사용자 답변
→ HTML artifact 생성 (레이아웃 + 컴포넌트)
→ 승인 → 파일 저장
→ git commit

/design-screen login  (기존 존재)
→ bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/design-screen.sh login
  → Error: screens/login.md 이미 존재합니다. --force 사용.
→ 사용자에게 안내 후 중단 또는 --force 재시도
```

## 참조

- `scripts/_internal/design-screen.sh` — 보일러플레이트 자동화 스크립트
- `scripts/tests/test-design-screen.sh` — 스크립트 검증 테스트
- `templates/screen.md` — 화면 스펙 마크다운 템플릿
- `templates/screen.html` — HTML 미리보기 템플릿 (CSS 변수 기반)
- `DESIGN.md` — 디자인 시스템 (색상·폰트·컴포넌트)
- `.specops/memory/screens-overview.md` — 화면 목록 마스터
- `commands/design-screens.md` — 복수 커맨드 (여러 화면 일괄 설계 `/design-screens`)

---

*specops-ko v2.6.0 · 2026-05-20 · 화면별 목업 생성 슬래시*
