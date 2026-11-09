# devFSD 종합 평가 11회차 (2026-11-09, v3.1.15)

> **성격**: 8·10회차와 같은 방법(독립 에이전트 5개)으로 다시 잰 평가. 축·가중은 5회차부터 고정이다. 기존 회차는 고치지 않고 새 회차를 추가한다(`README.md` 규약).
> **범위**: v3.1.15 릴리즈 직전 main(`8718da3d`)을 `git clone --local` 로 고정한 사본. 에이전트는 사본에서만 테스트·변이·우회 재현을 했고, 실저장소와 `.specops/` 는 읽기 전용 입력이었다.
> **구간**: v2.17.0(10회차) → v3.1.15. 이름이 specops-ko 에서 devfsd 로 바뀐 구간(v3.0.0)을 포함한다.
> **편향 고지**: 아래 "방법의 한계" 참조. 평가자는 이 구간 변경의 상당수를 만든 세션이다.

---

> 10-09 5.8(v2.17.0, 독립 에이전트 5개)에 이은 **11회차**.

## 총점: **6.4 / 10** (10회차 대비 +0.6)

| 축 | 가중 | 10회차 | **11회차** | 근거 |
|---|---|---|---|---|
| 기계적 완성도 | 0.20 | 6.5 | **6.95** | 프롬프트 일관성 7.4(10회차 6.5) · 테스트 품질 6.5(제자리) 의 평균 |
| 실사용 시 가치 | 0.25 | 6.5 | **6.8** | 실사용 데이터 감사 |
| 경제성·비례성 | 0.20 | 4.5 | **4.8** | 실사용 데이터 감사 |
| 강제력 | 0.20 | 5.5 | **6.4** | 독립 감사(10회차에는 감사 에이전트 정지로 독립 점수 없음) |
| 온보딩·적합도 | 0.15 | 5.5 | **6.8** | 독립 감사 |

계산: 0.20×6.95 + 0.25×6.8 + 0.20×4.8 + 0.20×6.4 + 0.15×6.8 = 6.35 → 6.4

## 오른 곳 — 10회차 지적이 닫혔다 (재현으로 확인)

| 10회차 지적 | 11회차 확인 |
|---|---|
| 비도입 저장소에 훅이 흔적을 남겨 관할로 편입(Critical) | 훅 전종(SessionStart · Stop 3종 · PreToolUse · PostToolUse · Notification · SubagentStop)을 `.specops/` 없는 저장소에서 돌려 파일 생성 0, 커밋 통과. `/doctor` 부트스트랩 전 점검과 `/status` 오류도 해소 |
| 커밋 인식 표기 사각 | `/usr/bin/git commit` · 제어문 안 커밋 · `gh pr -R … create` 차단 확인 |
| 검증 뒤 셸 수정이 통과 | STALE 차단 확인 |
| 다른 FID 의 실행 증거가 통함 | 불인정 확인 |
| batch FR 보류 신호를 받는 쪽 없음 | `BATCH-FR-HELD` 수신자 닫힘. 신호 생산자↔소비자 전수 짝 |
| must AC 커버리지 검사를 지워도 스위트 통과 | 변이 4종 모두 격추 |
| main 브랜치 보호 없음 | 설정됨(2026-10-10) |

이 구간에 새로 생긴 예외(quick 실흐름 · STALE `untracked-only` · DRYRUN · full-suite-fresh)는 공격해도 열리지 않았다. quick-scope 변이 9/9, full-suite-fresh 5/5, governance-lib worktree·STALE 부분 7/7 격추.

바닥도 단단하다: `validate-structure` 전 항목 OK · 문서가 가리키는 경로 140개와 환경변수 14개 전부 실재 · 스위트 격리 211/211(위반 0).

## 새로 나온 것 — 우선순위 순

### 강제력 6.4 (Critical 0 · High 1 · Medium 3 · Minor 8)

- **High E-8**: 메인에 verify PASS 가 있으면 **다른 worktree 의 미검증 코드 커밋이 열린다.** `cd W && git commit` · `git -C W commit` · `GIT_DIR=… GIT_WORK_TREE=W git commit` · `pushd W && git commit` · `(cd W; git commit)` · 상대 `cd ../W` 7형태가 전부 ALLOW. 같은 입력에서 transcript 의 러너 증거만 빼면 DENY 라 verify 쪽 구멍이다. 문서 면제 쪽은 `_gov_cmd_moves_elsewhere` 로 이미 닫혀 있다. 정직한 worktree 흐름에서 나오는 형태라 우회가 아니라 구조적 허점이다. **한계**: 훅 입력 cwd 를 직접 구성해 재현했고, 실제 세션이 cwd 를 어떻게 주는지와 발생 빈도는 못 쟀다.
- **Medium E-1**: 플러그인 repo 에서 `skills/*/SKILL.md` 외의 런타임 md 가 "문서"로 면제된다. `skills/implementing-ko/dev-autonomy.md`(implementing-ko 가 wave 직전에 Read 하는 행동 규칙)와 `skills/planning-ko/arch-expert/patterns/*.md` 를 고치고 커밋하면 verify 없이 통과한다. CLAUDE.md 의 "확장자 무관 코드" 계약과 어긋난다.
- **Medium E-6**: `*.txt`·`*.rst` 가 전부 문서라서 `requirements.txt`·`CMakeLists.txt`·`constraints.txt` 변경이 verify 없이 열린다. quick 경로의 파일 수·줄 수에도 안 센다.
- **Medium E-2**: R-4(성공 주장 + 테스트 미실행, 경고 전용)가 "테스트가 통과했습니다"·"정상적으로 동작합니다"·"검증을 완료했습니다"·"All tests pass" 같은 가장 흔한 문장을 놓친다. R-5 는 Write 덮어쓰기와 `sed -i` 를 못 잡는다(E-4).
- Minor: R-4 러너 판정이 문자열 포함 수준(E-3) · PreToolUse matcher 가 Bash 한정이라 다른 셸 도구가 표면 밖(E-5) · 빈 값 env 접두 `VAR= git commit` 미인식(E-7) · R-2 가 비-strict FID 의 STALE 을 hard 로 안 본다(E-9) · transcript 부재 fail-open 이 무기록(E-10).

### 테스트 품질 6.5 (변이 99건 → 격추 59 · 생존 40 · 진짜 구멍 27)

- 새 주변 검사기의 격추율이 낮다: api-contract 4/10 · security-design 3/9 · import-direction 3/11. import-direction 은 단언 29개로 631줄을 지키는데 202 허용 · reset_token · 긴 접두 우선 · TS 별칭 정렬 변이가 모두 생존했다.
- `mutation-targets.conf` 는 6개 파일 · 연산자 6종뿐이다. v2.17.0 이후 새 스크립트 25개 이상이 변이 게이트 밖이고, 정규식·경계 변이는 카탈로그에 없다.
- **CI 에서 공허한 시험**: `hooks/*.test.*` TS 테스트 244건은 `claude plugin test` 로만 돌아 CI 에는 claude CLI 가 없어 PP-7 이 SKIP 인데 PASS 로 집계된다. `test-plan-predispatch` P10 · `test-reconcile-check` R18 · `test-doctor` T25 는 로컬 `.specops` 코퍼스에 기대고 CI 에서는 비어 있다. 같은 날 평가자가 P10 의 로컬 시점 오탐(완료 FID 의 `dangling-lock`)을 먼저 고쳤고(#268), 이 점수 대상에 그 수정이 들어 있다.
- 시험이 없는 곳: `reconcile-check` 의 증거 frontier 승격 · WAIVED · origin/main 경로(이 평가 당일 추가한 머지됨 판정 포함), `emit-context.sh` 의 `###` 헤더 AC must 판정.

### 프롬프트 일관성 7.4

- **F-1 (Medium)**: **데모 단계가 batch(`/start-all`)에서 안 돈다.** performance-test-ko 가 batch 에서 PR 게이트를 통째로 건너뛰어 demo-ko 를 부르지 않고, start-all 과 start-all-auto 에도 데모 호출이 0건이다. README 의 "PR 직전 데모 확인" 약속이 batch PR 에서는 지켜지지 않는다. `BATCH-DEMO-SKIP` 은 도달 불가한 분기에서 나오고 받는 쪽도 없다.
- F-2: `/start-auto` 류 삭제(2.37.0) 뒤 `§auto` 단일 분기(performance-test-ko · demo-ko AUTO)는 어떤 진입으로도 닿지 않는 죽은 문단이다. `test-demo-stage` 가 이를 오히려 잠근다.
- F-3: README Lifecycle 도식과 using-specops-ko chain 목록에 demo 단계가 없다.
- F-4·F-5: CLAUDE.md 의 `governance-lib.sh` 규모가 낡았다(적힌 값 1892줄·함수 51개, 실제 2115줄·함수 60개). Phase B/C 증거를 만드는 `save-review-report.sh` 가 훅 목록 문서에 없다.
- F-6·F-7: `quick-fix.sh` 가 판정 불가도 "범위 초과 → /maintain-lite" 로 안내한다(CLAUDE.md 가 위장하지 않는다고 한 계약과 어긋남).

### 온보딩 6.8

- **High(일부만 검증)**: `/doctor`·`/status` 가 Claude Code 내장 명령과 이름이 같다. README 설치 2단계가 `/doctor` 로 확인하라고 하는데 내장이 우선하는지는 설치 금지라 못 쟀다. 네임스페이스(`/devfsd:doctor`) 안내가 어디에도 없다.
- Medium: 이름 변경(specops-ko → devfsd) 잔재 196곳 — README 70행 `marketplace add /절대경로/specops-ko`, 슬래시 선택창 설명 25개 중 10개, SessionStart 주입문, doctor 표 제목. 프롬프트 일관성 감사도 같은 문제를 따로 찾았다.
- Medium: 도입 직후 lifecycle 밖 커밋 차단 문안이 막다른 길이다. 안내한 `run-verification.sh` 가 실패하고(`tasks.md` 없음) `/quick-fix`·`/start` 안내 없이 출구가 BYPASS 뿐이다.
- Medium-Low: 건강한 새 설치인데 doctor ⚠️ 3개(그중 `git_hooks` 는 "조치 없음"인데 ⚠️) · pyyaml 없는 기본 python 에서 `config.yaml` 킬스위치가 조용히 무시됨 · `/quick-fix` 는 `.specops/` 없으면 거절되는데 README 에 전제가 없다.

### 실사용 가치 6.8 · 경제성 4.8 (구간: 2026-10-10 이후 FID 119건, 하류 35건 포함)

| 지표 | 10회차 | 11회차 | 비고 |
|---|---|---|---|
| Phase C 1회차 지적 FID | 37~41% | 26%(엄격)~54%(상한) | 정의가 달라 직접 비교 불가 |
| Phase C 표본 10건 중 실결함 | 5 | 7 | |
| plan 리뷰 1회차 FAIL | 74% | 82% (62/76) | 의미 결함 탓 — 사전검사 보강은 효과 작음(05일 실측) |
| 보안 단계 진짜 발견 | 0/161 | 2/70 | |
| integration · performance 실행 | 3 · 1 | 42 · 12 | |
| 데모 단계 | — | 5건 실행 · "아니다" 0 · 실행 출력 4/5 · 스크린샷 0/5 | 대부분 훅·스크립트 FID |
| 50줄 미만 변경의 산출물/변경량 | 약 50배 | 중앙값 38배 (n=12) | |
| 소요와 변경 크기 상관 | r=0.13 | r=0.14 | 제자리 |
| 경량 경로 사용률 | 5/214 (2.3%) | 21/106 (20%) | 10/25 이후 lite 0건 — quick-fix 만 쓴다 |
| 우회/커밋 | 본체 2.8% · Argus 7% · auto-company 54% | 본체 2.4% (10/414) · Argus 약 20% · auto-company 측정 불가 | Argus 32건은 전부 10/15~17 에 몰림 — 이후 무우회가 수정 효과인지 사용 중단인지 구분 안 됨 |
| verify FAIL | — | 15/96 FID | 첫 FAIL 에서 PASS 까지 60초 이하 9건 → 서류·환경 60%+ 추정 (FAIL 원문 미보존으로 직접 분류 불가) |

결함률(`defect-rate.sh`, 평가자 직접 측정): **37%**(46/124 FID, 평균 0.5) — 05일 기준선 40%(42/105). 05일 이후 FID 는 30일 창이 지나지 않아 아직 "관찰중"이다.

## 사전등록 트리거 (10회차가 남긴 것)

| 트리거 | 상태 |
|---|---|
| (a) 수정 이후 하류 FID 5건 이상에서 보유율·우회 비율 재측정 | **충족** — 하류 35건(Argus 20건 등), evidence 보유율 32/35(91%). 우회 비율은 Argus 가 약 20% 로 악화했으나 위 단서가 붙는다 |
| (b) 주간 변이 게이트 matrix 첫 실행 | 이번 회차에서 확인하지 않음 |
| (c) 경량 경로 사용률 | 5/214 → 21/106. 단 lite 는 10/25 이후 0건 |
| (d) 비도입 저장소 흔적 4곳 | 2026-10-11 삭제 완료. 새 흔적은 재현되지 않음(온보딩 감사) |

## 방법의 한계

- **평가자 편향**: 평가자는 이 구간 변경의 상당수를 만든 세션이다. 점수는 독립 에이전트의 값을 그대로 썼고, 평가자가 임의로 가감하지 않았다.
- **평가 당일 커밋이 정식 절차 밖이었다**: 같은 날 평가자가 올린 PR #268(이미 머지된 FID 를 미완으로 보고하지 않는 `reconcile-check` 수정)은 FID·명세·Phase B/C 리뷰 없이 "전체 스위트를 지금 이 트리에서 통과"하는 R-1 예외로 커밋됐다. 10회차의 "평가자 커밋 17건이 R-1 을 거치지 않았다"와 같은 부류이며, 이 변경은 이번 점수 대상(`8718da3d`)에 이미 들어 있다. 위 테스트 품질 감사가 지적한 "reconcile-check 에 시험이 없는 경로"에 이 변경분도 포함된다.
- 강제력 E-8 은 훅 입력 cwd 를 직접 구성해 재현했다. 실제 세션의 cwd 전달과 빈도는 못 쟀다.
- 테스트 품질: 16개 계획한 로캘·시각 매트릭스 중 3개만 실행, 전체 `run-all` · Stop·사후 감사 훅 변이 · `console.tsx`·`progress-pane.tsx` 변이는 못 했다. 에이전트 하나는 종료 시점에 자기 백그라운드 작업이 남아 있었다.
- 온보딩: 실제 설치 후 명령 우선순위, LLM 단계(`/start`·`/maintain`), 메타 스킬의 비도입 저장소 진입 동작, 관제판은 못 쟀다.
- 프롬프트 일관성: 모델이 chain 을 실제로 끝까지 도는지(LLM eval 미실행)와 하류 저장소 실행은 못 쟀다.
- 실사용: 소급 측정이고 표본이 작다(n=10~119). C 리뷰 지적률은 10회차와 정의가 달라 비교에 쓰지 않았다.

## 다음 후보 (평가 결과에서 나온 것 — 결정은 사람의 몫)

1. **E-8** worktree 이동 커밋의 verify 판정 (High · 정직한 흐름에서 나오는 형태)
2. **F-1** batch 에서 데모 단계가 도는지 (README 약속과 실제 불일치) + F-2 죽은 `§auto` 문단 정리
3. **이름 변경 잔재 196곳** + `/doctor`·`/status` 내장 명령 충돌 안내 (온보딩 첫인상)
4. **E-1·E-6** 런타임 md·의존성 txt 의 면제 범위
5. **CI 에서 공허한 시험** — 코퍼스 의존 스위트와 TS 훅 테스트 244건을 CI 가 실제로 돌리게 하거나 SKIP 을 PASS 로 세지 않기
6. 변이 게이트 카탈로그 확대 (정규식·경계 변이, 신규 스크립트 25개+)

## 다음 회차의 사전등록

- (a) E-8 이 닫힌 뒤 같은 7형태 재현. 닫히면 강제력 +0.5.
- (b) 데모 단계 FID 를 스크린샷이 의미 있는 종류(화면·UI 변경)로 3건 이상 확보 — 스크린샷 0/5 가 종류 탓인지 단계 결함인지 가른다.
- (c) 경량 경로 중 lite 사용률 — quick-fix 만 쓰는 현상이 계속되는지.
- (d) Argus 우회 비율 — 사용 재개 후 20% 가 유지되는지.
- (e) 주간 변이 게이트 matrix 첫 실행.
