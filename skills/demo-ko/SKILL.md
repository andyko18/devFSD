---
name: demo-ko
description: PR 생성 게이트 직전에 호출 — 만든 것을 실제로 실행해 화면 스크린샷·실행 출력을 사용자에게 보여 주고, 사용자가 보는 결과가 바뀐 작업은 "맞다/아니다" 확인을 받는다. 결과를 눈으로 확인하지 못한 채 발행하는 일을 막는다
layer: 2
discipline: true
reference_upstream: specops-ko 독자 추가
specops_version: 3.1.6
used_by: performance-test-ko (PR 생성 게이트 직전 호출-복귀)
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

- **화면**: 앱 안 브라우저(`mcp__Claude_Browser__*` — `preview_start`·`navigate`)로 열어 스크린샷을 찍어 보여 준다. 설계 화면 `screens/<name>.html` 이 있으면 나란히 놓는다.
- **iOS 앱**: `mcp__Claude_Code_iOS_Simulator__control` 로 실행해 스크린샷.
- **진행 패널(mod)**: 패널이 렌더한 결과를 보여 준다.
- **명령·스크립트**: 대표 입력으로 **실제 실행한** 출력 몇 줄(정상 경로 1건 + 경계/오류 1건). 입력과 명령을 함께 적는다.
- **내부**: 확인 방법 1~2줄(예: 관련 스위트 PASS 수치, 변경 전후 비교)을 적는다 — 이 종류만 테스트 요약이 허용된다.
- **보여 줄 방법이 없을 때**(브라우저·시뮬레이터 부재, 외부 서비스 필요): 이유와 **사용자가 직접 확인하는 방법**(명령·URL)을 적는다. 숨기거나 "확인함"이라 쓰지 않는다.

## 3단계: 확인 필요 판정

다음 중 하나라도 해당하거나 **판단이 애매하면** 확인이 **필수**다(fail-safe):
화면·UI 소스 · iOS 앱 · 진행 패널 · 최상위 `scripts/*.sh` 의 출력 · `commands/`·`skills/` 의 사용자 문구 · 훅 메시지 · **미분류 포함**.
미분류는 사용자에게 보이는지 알 수 없으므로 확인 필수로 다룬다(fail-safe).
**내부**만이면 보여 주기만 하고 멈추지 않는다.

확인 필수일 때 사용자에게 한 번에 묻는다:

> "위 결과가 의도한 모습입니까? [맞다 / 아니다 — 어디가 다른지]"

- **맞다** → 4단계.
- **아니다** → 다른 점을 받아 `systematic-debugging-ko` 또는 implementer 로 고치고(영향 단계 verify 재실행) **2단계부터 다시** 보여 준다.
- **보여 줄 방법이 없었던 경우** → 사용자가 직접 확인했다고 답할 때까지 넘어가지 않는다.

## 합리화 차단표

| 생각 | 실제 |
|---|---|
| "테스트가 다 통과했으니 보여 줄 필요 없다" | 테스트는 실제 모습을 보지 않는다 — 보여 주기는 항상 한다 |
| "사소한 출력 변경이라 확인은 생략" | 사용자가 보는 출력이면 확인 필수. 애매하면 필수 |
| "브라우저를 못 열었으니 넘어가자" | 이유와 직접 확인 방법을 적고 사용자 응답을 기다린다 |
| "아니다 라지만 곧 고칠 테니 PR 부터" | 고치고 다시 보여 준 뒤에만 넘어간다 |
| "내부 변경이라 빈 칸으로 둔다" | 내부여도 확인 방법 1~2줄을 evidence 에 남긴다 |

## 레드 플래그 — 중단

- 실행 없이 "데모 완료" 기록
- 확인 필수인데 사용자 응답 없이 PR 생성 y/n 으로 진행
- 스크린샷·출력이 변경 전 상태

## 4단계: 기록

```markdown
## /demo — <ISO-8601>

**종류**: 화면 | iOS 앱 | 진행 패널 | 명령·스크립트 | 내부 | 미분류 (복수 가능)
**실행**: <명령 또는 URL>
**보여 준 것**: <스크린샷 설명 / 출력 요약>
**확인 필요**: yes | no (<이유>)
**사용자 판정**: 맞다 | 아니다→수정 후 재확인 | 직접 확인 응답 | 해당 없음(내부)
```

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /demo DONE|SKIP "<요약>"
```

PR 생성 시 본문에 `## 데모` 절로 위 요약(종류·보여 준 것·사용자 판정)을 넣는다 — 요약은 `performance-test-ko` 의 PR 템플릿이 evidence.md `## /demo` 에서 가져온다.

## 5원칙 주입

| 원칙 | 적용 |
|---|---|
| 1 투명성 | 실행한 명령·URL 과 본 것을 그대로 기록 |
| 2 문지기 | 확인 필수 FID 는 사용자 판정 전에 PR 게이트로 넘기지 않는다 |
| 3 깊이 | 요약이 아니라 실제 실행 결과를 보여 준다 |
| 4 주권 존중 | 결과가 맞는지는 사용자가 판정한다 |
| 5 한계 고백 | 보여 줄 수 없으면 이유와 직접 확인 방법을 적는다 |

## 참조

- `skills/performance-test-ko/SKILL.md` `## PR 생성 게이트` — 호출자·복귀 지점
- `skills/integration-test-ko/SKILL.md` — 적용성 게이트·증거화 구조
- `skills/systematic-debugging-ko/SKILL.md` — "아니다" 시 수정 경로
