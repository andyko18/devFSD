---
name: demo-ko
description: PR 생성 게이트 직전에 호출 — 만든 것을 실제로 실행해 화면 스크린샷·실행 출력을 사용자에게 보여 주고, 사용자가 보는 결과가 바뀐 작업은 "맞다/아니다" 확인을 받는다. 결과를 눈으로 확인하지 못한 채 발행하는 일을 막는다
layer: 2
discipline: true
reference_upstream: specops-ko 독자 추가
specops_version: 3.1.22
used_by: performance-test-ko (PR 생성 게이트 직전 호출-복귀), /start-all·/start-all-auto (batch PR 직전 batch-final 호출)
---

# Engine 스킬 — 데모 (demo)

테스트가 통과해도 실제로 어떻게 보이는지는 아무도 보지 않는다. PR 을 만들기 **전에** 만든 것을 직접 실행해 결과를 사용자에게 보여 준다. 사용자가 보는 결과가 바뀐 작업은 사용자가 "맞다"고 해야 넘어간다.

**호출-복귀**: `performance-test-ko` 의 `## PR 생성 게이트` 가 이 skill 을 부르고, 끝나면 그 게이트의 나머지(가정 다이제스트·PR 생성 y/n)로 돌아간다. chain primary edge 는 아니다(`hooks/chain.yaml` 불변).

## 모드 분기

```bash
if grep -qE '^\*\*§batch\*\*:' .specops/<FID>/spec.md; then echo BATCH
elif grep -qE '^\*\*§auto\*\*:[[:space:]]*true' .specops/<FID>/spec.md; then echo AUTO
else echo SINGLE; fi
```

- **BATCH** → `BATCH-DEMO-SKIP: <FID>` 출력 + 근거 1줄(batch 오케스트레이터가 PR 을 소유) 후 **즉시 복귀**. evidence.md 에 `## /demo` 절을 `결과: SKIP — batch` 로 남긴다.
- **AUTO**(무인) → 아래 1~2단계는 수행하고, 3단계 확인 대기는 하지 않는다. 확인 필요 항목은 PR 게이트의 가정 다이제스트에 `데모: 사용자 확인 대기` 로 올린다.
- **SINGLE**(`§lite` 포함 — lite 라고 생략하지 않는다) → 1~4단계 전부.

### batch 최종 호출 (`batch-final`)

`/start-all`·`/start-all-auto` 오케스트레이터가 **batch PR 직전**에 `Skill: devfsd:demo-ko` 를 인자 `batch-final <BATCH_ID>` 로 부르면 위 분기를 보지 않는다. per-FR FID 는 PR 이 없어 위 BATCH 로 건너뛰지만, batch PR 은 사용자가 결과를 처음 보는 지점이다(11회차 F-1).

- 1단계 diff 는 batch 브랜치 전체(`origin/$BASE...HEAD`)다. 2~3단계는 SINGLE 과 같다 — 멈추지 않고, 확인 필요 항목은 batch PR 질문에서 함께 확인받는다.
- 무인(`/start-all-auto`)은 인자를 `batch-final <BATCH_ID> auto` 로 부른다 — 3단계 대기를 하지 않고, 확인 필요 항목을 batch PR 게이트의 가정 다이제스트에 `데모: 사용자 확인 대기` 로 올린다.
- 기록은 `.specops/<BATCH_ID>/demo.md` 에 4단계 양식으로 남긴다. FID 가 없어 session-progress 줄은 남기지 않는다. batch PR 본문 `## 데모` 가 이 파일에서 가져온다.

## 1단계: 종류 판정

```bash
BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||'); BASE=${BASE:-main}
git diff "origin/$BASE"...HEAD --name-only
```

`git diff` 가 실패하거나(rc≠0: origin 없음·기준 브랜치가 다름 등) 출력이 비어 있으면 종류를 정할 수 없는 것이므로 `미분류` 로 보고 확인 필수로 다룬다(빈 출력을 `내부` 로 읽지 않는다). 기준 브랜치를 못 찾으면 `git diff HEAD~N...HEAD` 등으로 범위를 좁히거나 사용자에게 변경 범위를 확인해 달라고 요청한다.

변경 파일로 종류를 정한다(여럿이면 모두).

| 종류 | 신호 |
|---|---|
| 화면 | `screens/`, `*.html`, `*.tsx`, `*.jsx`, `*.vue`, `*.css` |
| iOS 앱 | `*.swift`, `*.xcodeproj`, `*.xcworkspace` |
| 진행 패널(mod) | `hooks/progress-pane.*`, 패널 렌더 코드 |
| 명령·스크립트 출력 | 최상위 `scripts/*.sh`, `commands/`, `skills/`, 훅 메시지 |
| 내부 | `tests/`·`test-*`·`*.test.*` 같은 테스트, 문서(`*.md`·`docs/`), `scripts/_internal/`, 내부 라이브러리로 확인된 파일 **만** |
| 미분류 | 위 어느 행에도 명시되지 않은 소스 파일(예: `*.py` `*.go` `*.rs` `*.svelte` `*.scss`, API 서버 코드) |

## 2단계: 실제로 실행해 보여 주기

**테스트 통과 요약은 데모가 아니다.** 사용자가 보게 될 것을 직접 만들어 낸다.

- **화면**: 통합 테스트의 브라우저 점검 결과(`.specops/<FID>/ui/*.png` — 375·768·1280 폭)가 있으면 그 PNG 를 Read 로 열어 그대로 보여 주고 `UI-PROBE:` 판정 줄을 함께 적는다. 없으면 앱 안 브라우저(`mcp__Claude_Browser__*` — `preview_start`·`navigate`)로 열어 스크린샷을 찍어 보여 준다. 하네스가 목업도 같은 폭으로 찍었으면(`<이름>@<폭>.mock.png`) 구현 PNG 와 폭마다 나란히 보여 준다. 설계 화면 `screens/<name>.html` 이 있는데 `.mock.png` 가 없으면 앱 안 브라우저로 열어 나란히 놓고, `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-mock-css.sh` 결과 1줄(목업 클래스가 앱 CSS 에 살아남은 비율 — `WARN` 이면 화면이 브라우저 기본 모양일 수 있다)을 함께 보여 준다.
- **iOS 앱**: `mcp__Claude_Code_iOS_Simulator__control` 로 실행해 스크린샷.
- **진행 패널(mod)**: 패널이 렌더한 결과를 보여 준다.
- **명령·스크립트**: 대표 입력으로 **실제 실행한** 출력 몇 줄(정상 경로 1건 + 경계/오류 1건). 입력과 명령을 함께 적는다.
- **내부**: 확인 방법 1~2줄(예: 관련 스위트 PASS 수치, 변경 전후 비교)을 적는다 — 이 종류만 테스트 요약이 허용된다.
- **보여 줄 방법이 없을 때**(브라우저·시뮬레이터 부재, 외부 서비스 필요): 이유와 **사용자가 직접 확인하는 방법**(명령·URL)을 적는다. 숨기거나 "확인함"이라 쓰지 않는다.

## 3단계: 확인 필요 판정

**멈추지 않는다** (20261109 — 사용자 결정). 도입 뒤 5건 실행에서 "아니다" 가 0건이었고 대기는 사람 시간을 썼다. 보여 주기는 그대로 하고, 확인은 PR 생성 질문에서 한 번에 받는다.

다음 중 하나라도 해당하거나 **판단이 애매하면** 확인이 **필수**다(fail-safe):
화면·UI 소스 · iOS 앱 · 진행 패널 · 최상위 `scripts/*.sh` 의 출력 · `commands/`·`skills/` 의 사용자 문구 · 훅 메시지 · **미분류 포함**.
미분류는 사용자에게 보이는지 알 수 없으므로 확인 필수로 다룬다(fail-safe).

확인 필수면 4단계 기록의 `확인 필요` 를 `yes` 로 두고, PR 게이트 요약 맨 앞에 "결과를 보고 PR 생성 여부를 정하세요 — 다르면 아니다라고 말해 주세요" 한 줄과 함께 2단계에서 보여 준 것(스크린샷·출력)을 다시 붙인다. 사용자가 PR 질문에서 다르다고 하면 `systematic-debugging-ko` 또는 implementer 로 고치고(영향 단계 verify 재실행) **2단계부터 다시** 보여 준다.
**보여 줄 방법이 없었던 경우**(찍지 못함·외부 서비스 필요) → 그 사실과 사용자가 직접 확인하는 방법을 같은 자리에 적는다 — 확인한 척하지 않는다.

## 합리화 차단표

| 생각 | 실제 |
|---|---|
| "테스트가 다 통과했으니 보여 줄 필요 없다" | 테스트는 실제 모습을 보지 않는다 — 보여 주기는 항상 한다 |
| "사소한 출력 변경이라 확인 표시는 생략" | 사용자가 보는 출력이면 확인 필요 yes. 애매하면 yes |
| "브라우저를 못 열었으니 넘어가자" | 이유와 직접 확인 방법을 PR 게이트 요약에 적는다 |
| "아니다 라지만 곧 고칠 테니 PR 부터" | PR 질문에서 아니다면 고치고 다시 보여 준 뒤에만 PR 로 간다 |
| "내부 변경이라 빈 칸으로 둔다" | 내부여도 확인 방법 1~2줄을 evidence 에 남긴다 |

## 레드 플래그 — 중단

- 실행 없이 "데모 완료" 기록
- 확인 필수인데 PR 게이트 요약에 보여 준 것(스크린샷·출력)을 붙이지 않음
- 스크린샷·출력이 변경 전 상태

## 4단계: 기록

```markdown
## /demo — <ISO-8601>

**종류**: 화면 | iOS 앱 | 진행 패널 | 명령·스크립트 | 내부 | 미분류 (복수 가능)
**실행**: <명령 또는 URL>
**보여 준 것**: <스크린샷 설명 / 출력 요약>
**확인 필요**: yes | no (<이유>)
**사용자 판정**: PR 게이트에서 확인 | 아니다→수정 후 재확인 | 해당 없음(내부)
```

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /demo DONE|SKIP "<요약>"
```

PR 생성 시 본문에 `## 데모` 절로 위 요약(종류·보여 준 것·사용자 판정)을 넣는다 — 요약은 `performance-test-ko` 의 PR 템플릿이 evidence.md `## /demo` 에서 가져온다.

## 5원칙 주입

| 원칙 | 적용 |
|---|---|
| 1 투명성 | 실행한 명령·URL 과 본 것을 그대로 기록 |
| 2 문지기 | 확인 필수 FID 는 보여 준 것을 PR 게이트 요약 맨 앞에 붙여 PR 질문에서 함께 확인받는다 |
| 3 깊이 | 요약이 아니라 실제 실행 결과를 보여 준다 |
| 4 주권 존중 | 결과가 맞는지는 사용자가 판정한다 |
| 5 한계 고백 | 보여 줄 수 없으면 이유와 직접 확인 방법을 적는다 |

## 참조

- `skills/performance-test-ko/SKILL.md` `## PR 생성 게이트` — 호출자·복귀 지점
- `skills/integration-test-ko/SKILL.md` — 적용성 게이트·증거화 구조
- `skills/systematic-debugging-ko/SKILL.md` — "아니다" 시 수정 경로
