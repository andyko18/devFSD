# 실제 브라우저 시나리오 (integration-test-ko 보조 문서 · 선택 기능)

> `skills/integration-test-ko/SKILL.md` Step 3c 에서 참조. `e2e-coverage.sh <FID>` 가 `SKIP (OFF …)` 가 **아닐 때만** 읽는다.
> 기본은 꺼져 있다 — `.specops/config.yaml` 의 `browser_e2e.mode: observe`(지켜보기) 또는 `enforce`(막기)로 켠 프로젝트에서만 돈다.
> **경로**: 이 문서는 Read 로 읽힌다 — 명령에 적힌 플러그인 루트 변수(CLAUDE_PLUGIN_ROOT)는 치환되지 않고 Bash 에도 없다. 이 파일 경로에서 `/skills/` 앞까지(플러그인 루트 절대경로)로 바꿔 실행한다.

## 왜 하는가

하류 프론트 테스트는 가짜 브라우저(jsdom)로 돈다. 포커스 이동 · 키보드 조작 · 실제 내비게이션 · 뒤로 가기 복귀는 실제 브라우저에서만 드러난다(20261119 시범: 리뷰가 눈으로 잡은 결함이 전부 이 종류였다). Step 3b 의 브라우저 점검은 화면을 **여는 데까지만** 본다 — 여기서는 수용 기준대로 **눌러 본다**.

목표는 "화면 수용 기준 가운데 실제 브라우저 시나리오로 검증된 비율"이다(기본 95% 이상).

## 모드 — 새 게이트는 지켜보기부터

| `browser_e2e.mode` | 동작 |
|---|---|
| `off` (기본) | 돌리지 않는다 |
| `observe` | 돌리되 **막지 않는다** — 막았을 판정을 `.specops/e2e-observe.jsonl` 에 기록만 한다 |
| `enforce` | 기준 미달 · 시나리오 실패면 막는다 |

- 처음 켤 때는 `observe` 로 둔다. 기록이 몇 건 쌓이면 사용자가 막았을 판정이 진짜 결함이었는지 헛경보였는지 보고 `enforce` 로 올리거나 끈다. 모드를 스스로 바꾸지 않는다.
- 옛 표기 `enabled: true` 는 `enforce` 로 읽는다.
- **게이트 설정은 기준 브랜치 값보다 느슨해질 수 없다.** `mode` 를 내리거나 `min_coverage` 를 낮춘 변경은 그 변경 안에서는 효력이 없다 — 판정기가 기본 브랜치와의 갈림점 값을 쓰고 `게이트 설정:` 알림 줄을 낸다(환경변수로 낮추는 것도 무시한다). 느슨하게 바꾸려면 그 설정 변경을 **먼저 기본 브랜치에** 넣는다. 통과시키려고 설정을 고치지 않는다 — 알림 줄이 나오면 evidence 에 그대로 옮기고 끝 보고에 싣는다.

## 절차

### 1. 수용 기준을 가른다 — `.specops/<FID>/e2e-scope.txt`

`acceptance-criteria.md` 의 **모든** AC 를 한 줄씩 적는다(빠진 AC 가 있으면 판정이 FAIL 이다):

```
AC-1 browser
AC-2 browser
AC-3 backend — 서버 응답만 본다
AC-R-1 none — 빌드 설정 검사
```

- `browser` — 화면 · 포커스 · 키보드 · 내비게이션 · 보낸 요청 · 문구처럼 브라우저에서 관측할 수 있다.
- `backend` · `none` — 브라우저로 볼 수 없다. **사유를 반드시 적는다.** 화면에 닿는 AC 를 여기로 빼서 비율을 맞추지 않는다 — 판정 줄의 `백엔드 <N> · 해당 없음 <N>` 이 evidence 에 남아 사람이 본다.
- 화면 명세(`screens/<이름>.md`)에만 있고 AC 에 없는 키보드 · 배치 약속은 그 화면의 AC 시나리오에 조건으로 넣는다.

### 2. 시나리오를 쓴다

- 처음이면 `templates/e2e-support.mjs` 를 하류의 e2e 폴더(예: `frontend/e2e/support.mjs`)에 복사한다. Playwright 는 새로 설치하지 않는다 — 하류 `node_modules` 에 없으면 Step 3b 와 같은 공용 캐시(`~/.cache/devfsd/ui-harness`)를 쓴다.
- 파일 이름은 `*.e2e.mjs`, 첫머리에 `// FID: <FID>` 한 줄. 테스트 이름에 `@AC-<id>` 태그. 러너는 `node:test`.
- `browser` 로 가른 AC 마다 시나리오를 한 개 이상 쓴다. AC 하나에 조건이 여럿이면 조건마다 단언한다.
- 백엔드를 띄울 수 없으면 `page.route` 로 요청을 가로채 응답을 준다(응답 형태는 `api-spec.md` 를 따른다). 선언하지 않은 요청은 `blockUndeclared` 로 막는다.
- 단언은 관측값으로 한다 — 보이는 글자 · role · 포커스된 요소 · URL · 보낸 요청의 메서드 · 경로 · 헤더. "오류가 안 났다"만으로 통과시키지 않는다.
- 고정 대기(`waitForTimeout` · sleep)와 재시도를 쓰지 않는다.

### 3. 돌린다

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/e2e-run.sh <FID>
```

| 결과 | 처리 |
|---|---|
| `E2E-RUN: PASS` | 4 로 간다 |
| `E2E-RUN: FAIL` | 먼저 시나리오 쪽 잘못인지 본다(DOM 을 덤프하거나 스크린샷). 앱이 AC · 화면 명세와 다르게 동작하면 **시나리오를 약하게 고치지 않는다** — SKILL.md 의 FAIL 분기대로 구현을 고치고 다시 돌린다 |
| `E2E-RUN: OBSERVE (막았을 것 — …)` | 관찰 모드다. **막지 않고 4 로 간다.** 실패한 시나리오가 앱의 결함으로 확인되면 고치는 것이 맞다(고치지 못했으면 끝 보고에 싣는다). 줄은 evidence 에 그대로 옮긴다 |
| `E2E-RUN: SKIP (…)` | **PASS 로 적지 않는다.** `NO_TOOL` 은 안내된 설치 명령을 사용자에게 보이고 `[설치 후 재실행 / 미실행으로 기록]` 을 묻는다 |

판정할 수 없는 조건(AC 문구가 모호하다 · AC 와 화면 명세가 어긋난다 · dev 서버에서는 재현되지 않는다)은 지우지 말고 `{ todo: '<사유>' }` 로 남긴다. `판정 보류 <N>` 으로 드러나며, 사유를 evidence 에 옮기고 사용자가 정할 것은 끝 보고에 싣는다.

### 4. 비율을 잰다

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/e2e-coverage.sh <FID>
```

- `E2E-COVERAGE: PASS` → 다음으로.
- `E2E-COVERAGE: FAIL` → 출력이 짚은 AC 에 시나리오를 더하거나 분류를 고친다(사유 없는 제외 · 분류에서 빠진 AC).
- `E2E-COVERAGE: OBSERVE (막았을 것 — …)` → 관찰 모드다. 막지 않고 다음으로 간다. 줄을 evidence 에 그대로 옮긴다(PASS 로 바꿔 적지 않는다).
- `E2E-COVERAGE: SKIP (NO_BROWSER_AC …)` → 화면 AC 가 없는 작업이다. 그대로 적는다.
- 판정 줄 위에 `게이트 설정:` 알림 줄이 있으면 함께 옮긴다.

### 5. evidence.md 에 남긴다

브라우저 줄 아래에 한 줄을 **반드시** 남긴다(두 판정 줄을 그대로 옮긴다):

```
**E2E**: 실행(E2E-RUN: PASS (…) · E2E-COVERAGE: PASS (화면 AC <n>/<m> = <p>% · 기준 <t>% · 백엔드 <b> · 해당 없음 <k>))
**E2E**: 미실행(NO_TOOL|NO_SPEC|TIMEOUT|USER_SKIP — <한 줄 사유>)
```

## 하지 않는 것

- 꺼 둔 프로젝트에서 시나리오를 요구하지 않는다.
- 하류 저장소에 의존성을 추가하지 않는다(사용자가 원하면 따로 한다).
- 모바일 앱(Maestro 등)은 아직 다루지 않는다.
