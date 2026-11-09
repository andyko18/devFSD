---
name: design-screens
disable-model-invocation: true
description: "[lifecycle 밖] 복수 화면 일괄 설계 — 목록 자동판단·승인 게이트·순차 루프. lifecycle 안은 Step 5.5·Phase 2.5-A 가 자동 처리"
triggers:
  - "/design-screens"
mode: ask
specops_version: 3.1.21
specops_layer: Lifecycle-Tool
reference_upstream: specops-ko 독자 추가
---

# /design-screens [기능 설명]

여러 화면을 한 번에 standalone 으로 디자인하는 오케스트레이터. 기능 설명을 입력받아 ① 필요한 화면 목록을 자동 판단하고 ② 사용자 승인 게이트를 거친 뒤 ③ 각 화면을 기존 `/design-screen` 대화 루프로 순차 디자인한다.

> **분업**: lifecycle 안에서는 **Step 5.5**(단일 `/start`·`/maintain`)·**Phase 2.5-A**(`/start-all` batch)가 자동 처리한다 — 본 슬래시는 **lifecycle 밖 전용**이다. 분업 기준 SoT: `commands/design-screen.md` §화면 설계 경로 분업

## Step 1: 화면 목록 자동 판단 + 승인 게이트

args = 기능 설명. 비어 있거나 너무 짧으면(10자 미만) 최소 예시 목록을 제안하고 편집 게이트를 연다:

> "기능 설명이 없거나 짧습니다. 아래 예시 화면 목록으로 시작하고 수정해 주세요:
> 1. Login — 로그인 화면
> 2. Dashboard — 메인 대시보드
> [추가/삭제/이름변경 후 완성된 목록을 알려주세요]"

기능 설명이 충분하면 LLM이 필요한 화면 목록을 자동 도출한다. 각 항목은 `{name}` + 한 줄 설명으로 구성한다.

- `{name}` 은 반드시 `^[A-Za-z0-9_-]{1,64}$` 충족 (design-screen.sh CLI 계약). 위반 후보는 자동 정규화 후 표기.
- 충돌하는 기존 화면(`screens/{name}.html` 이미 존재)은 목록에 `⚠️ 기존 파일 존재` 표시.

사용자에게 목록 제시 후 **승인/편집 루프**:
> "이 목록으로 진행할까요? 추가/삭제/이름변경이 있으면 말씀해 주세요. [y/수정]"

`y` 응답 시 Step 2로 진행. 수정 시 수정된 목록 재확인 후 진행.

## Step 2: DESIGN.md 로드 (1회 공유)

**첫 화면 전 단 1회** 프로젝트 `DESIGN.md` 를 읽어 모든 화면에 공유 적용한다(부재 시 `templates/screen.html` 기본 토큰). 화면별 준수 항목은 Step 3 의 DESIGN.md 준수 지시를 따른다.

화면마다 `templates/frontend-design-guide.md`(frontend-design 원문)를 그대로 따른다 — 디자인 계획 → 흔한 기본값인지 검토 → 작성 → `screen-shot.sh` 로 1280·390 두 장을 찍어 1~2회 다듬기(찍지 못하면 그렇다고 적는다). 업무 화면 보충(판단 지원·상태·토큰 이름)은 `templates/screen-design-guide.md` (20261109).

## Step 3: 화면별 순차 대화 루프

승인된 화면 목록을 순서대로 처리한다. 각 화면에 대해:

**Step 3-1: 스캐폴딩**

`screens/{name}.html` 이 이미 존재하는지 먼저 확인한다:
> "화면 `{name}`이 이미 존재합니다(`screens/{name}.html`). 덮어쓸까요? [y/n(건너뜀)]"
> - `y` → `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/design-screen.sh {name} --force` 실행
> - `n` → 해당 화면 건너뜀, 다음 화면 진행

존재하지 않으면:

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/design-screen.sh {name}
```

**Step 3-2: 목적·컴포넌트·다음화면 질문**

단수 `/design-screen` Step 2와 동일한 3개 질문을 순서대로 한다:
1. 이 화면의 목적은 무엇인가요?
2. 주요 컴포넌트는 무엇인가요?
3. 이 화면에서 이동 가능한 다음 화면은 무엇인가요?

**Step 3-3: HTML artifact 생성 + 수정 루프**

Step 3-1에서 스크립트가 이미 `screens/{name}.html`을 생성했으므로, Step 2에서 로드한 DESIGN.md 토큰을 반영하여 그 내용을 채워 완성한다.

- **DESIGN.md 준수**: 화면 작성 시 `DESIGN.md` **§2 타이포·§3 간격** · §6 레이아웃 패턴 · §6.1 화면 원형 · §7 상태 표현 · §8 원칙/안티패턴 · §9 AI 지침을 읽고 따른다 (DESIGN.md 부재 시 skip).
- **입력 접근성**: 입력(input·select·textarea)마다 label 의 for 속성과 입력 id 를 같은 값으로 짝지어 연결한다(label 이 입력을 감싸거나 aria-label 도 허용 — for 없이 형제로만 둔 label 은 연결이 아니다). 라디오·체크박스는 선택지마다 자기 label 을 두고 그룹 이름은 fieldset 과 legend 로 둔다. 템플릿 html 의 주석 속 입력 예시를 복사해 쓴다.

사용자에게 artifact를 보여주고 수정 요청을 받는다:
> "위 HTML 미리보기를 확인해 주세요. 수정이 필요하시면 말씀해 주세요. 진행할까요? [y/n]"

- `y` 또는 수정 없음 → Step 3-4 진행
- `n` 또는 수정 요청 → HTML artifact 재생성 후 재확인 루프

**Step 3-4: 저장**

승인 시 `screens/{name}.md` + `screens/{name}.html` 저장:
- screen.md: **필수 8섹션**(목적 · Layout · Components · States · Interactions · 필드 정의표 · 데이터 소스 · 에러 메시지) 완성 + 조건부 4섹션은 해당할 때만(미해당이면 섹션 자체를 넣지 않는다). 채운 뒤 껍데기 **마커 줄을 삭제**한다. (단수 Step 4와 동일 요건)
- screen.html: Step 3-3에서 승인한 HTML로 교체
- screens-overview.md 갱신은 Step 3-1 스크립트가 이미 완료

**Step 3-5: 커밋**

단수 Step 5와 동일하게 화면별 commit:

```bash
git add screens/{name}.md screens/{name}.html
git add .specops/memory/screens-overview.md 2>/dev/null || true
git commit -m "feat(screens): {name} 화면 설계 추가"
```

진행 표시:
> "화면 N/M: `{name}` 완료. 다음 화면으로 진행합니다."

모든 화면 완료 후:
> "총 M개 화면 설계 완료: {name1}, {name2}, ..."

## 참조

- `commands/design-screen.md` — 단수 커맨드 (화면 1개씩 `/design-screen`)
- 화면 설계 경로 분업 기준: `commands/design-screen.md` §화면 설계 경로 분업
- `scripts/_internal/design-screen.sh` — 스캐폴딩 백엔드 (CLI: `<name> [--force]`, name regex `^[A-Za-z0-9_-]{1,64}$`)
- `templates/screen.html` — HTML 기반 템플릿
- `screens/` — 화면 산출물 저장 디렉터리

---

*specops-ko v2.6.0 · 2026-06-19 · 복수 화면 일괄 디자인 오케스트레이터*
