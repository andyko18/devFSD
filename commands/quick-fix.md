---
name: quick-fix
disable-model-invocation: true
description: "[유지보수·최소] 몇 줄짜리 수정 — 명세·분해 문서 없이 테스트 실행 + 코드 리뷰 1회 + 범위 상한(훅 강제)"
triggers:
  - "/quick-fix"
mode: ask
specops_version: 2.20.0
specops_layer: Lifecycle
reference_upstream: specops-ko 독자 추가 (commands/maintain-lite.md 보다 작은 수정)
---

# /quick-fix <고칠 것 한 줄>

## 목적

`/maintain-lite` 로 하기에도 작은 수정을 **문서 없이** 끝낸다. 분석·명세·수용 기준·계획·증거 문서와 보안·통합·성능 게이트, PR 게이트를 만들지 않는다. 남는 것은 셋이다 — **테스트를 실제로 돌린 영수증 · 코드 리뷰 1회 · 기계가 판정하는 범위 상한**.

"작다" 는 여기서 선언하지 않는다. 커밋할 때 훅이 **스테이징된 변경**을 보고 판정한다.

| 기준 | 상한 |
|---|---|
| 구현 파일 수 (테스트·문서 제외) | 2개 |
| 변경 줄 수 (추가+삭제 · 테스트·문서 제외) | 20줄 |
| 고위험 신호 | 없음 — 인증 · 마이그레이션·스키마 · 공개 API · 화면/인터페이스 문서 · (플러그인 저장소) 훅·규칙·에이전트·스킬 본문·커맨드 |

넘으면 커밋이 막히고 `/maintain-lite` 로 가라는 안내가 나온다. 고친 내용은 작업 트리에 그대로 남는다.

## Process

FID 는 `YYYYMMDD-<kebab-slug>` (인자에서 슬러그를 뽑는다 — 정식 경로와 같은 규칙).

1. **시작** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/quick-fix.sh start <FID> "<한 줄 설명>"`
   FID 폴더와 진행 기록을 연다. 기본 브랜치(main/master) 위면 브랜치를 만든다.
2. **고친다** — 동작이 바뀌는 수정이면 **실패하는 테스트를 먼저** 쓰고 실패를 확인한 뒤 고친다(`devfsd:tdd-ko`). 문구·주석·오타처럼 동작이 바뀌지 않으면 테스트 추가는 생략한다.
3. **스테이징** — 이번 수정에 넣을 파일만 `git add <파일…>` (별도 호출). 스테이징된 것이 곧 이 수정의 범위다.
4. **코드 리뷰 1회** — `devfsd:code-reviewer-ko` 를 dispatch 한다. 프롬프트에 아래를 넣는다:
   - `quick 경로: yes` (명세가 없다 — 스펙 리뷰 보고서도 없다)
   - FID · task id `T1` · 고친 의도 한 줄 · 리뷰 대상은 `git diff --cached`
   - 리뷰어는 `<<<REVIEW fid=<FID> tid=T1 phase=C verdict=…>>>` 블록으로 보고하고, 저장 훅이 `.specops/<FID>/reviews/T1-C-report.md` 로 옮긴다.
   - 판정이 `NEEDS_FIX` 면 고치고(다시 `git add`) **리뷰를 다시 받는다**. 리뷰 뒤에 코드를 고치면 그 리뷰는 무효다.
5. **봉인** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/quick-fix.sh seal <FID> "<test_command>"`
   범위·리뷰를 판정하고, 테스트를 실제로 실행해 통과하면 영수증을 남긴다. `test_command` 는 프로젝트의 테스트 명령이다 — 태스크 영수증이 받는 형태(프로젝트의 테스트 스크립트 · `pytest` · `npm test` 등)여야 한다.
   - 종료 코드 **3** = 범위 초과 → 멈추고 사용자에게 `/maintain-lite <설명>` 을 안내한다.
   - 종료 코드 **4** = 리뷰 미충족 → 4번으로.
   - 그 밖의 실패 = 테스트 실패 등 → 고친 뒤 4번부터 다시.
6. **커밋** — `git commit -m "<메시지> (Task: T1)"` 만 따로 실행한다. `-a`·`--all`·경로 인자를 쓰거나 다른 명령과 묶으면 훅이 막는다 — 판정은 스테이징된 변경을 보기 때문이다. 봉인 뒤 코드를 고치면 영수증이 무효다.
7. **마무리** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/quick-fix.sh done <FID> "<한 줄 요약>"`
   진행 기록에 종결 줄, 자유작업 로그(`.specops/freelog.md`)에 1줄.

## `/maintain-lite` 와의 차이

| | `/maintain-lite` | `/quick-fix` |
|---|---|---|
| 사용자 승인 대기 | 분석 검토 · 설계 승인 · PR | 없음 |
| 문서 | 분석 · 의도 · 명세 · 수용 기준 · 태스크 · 증거 | 태스크 문서(자동) · 영수증 · 리뷰 보고서 |
| 리뷰 | 스펙 리뷰 + 코드 리뷰 | 코드 리뷰 |
| 회귀 수용 기준 | 필수 | 없음 |
| 크기 상한 | 없음 | 있음 (훅이 막는다) |
| 끝나는 지점 | PR | 커밋 |

설계 판단이 필요한 수정은 줄 수가 적어도 `/maintain-lite` 다 — quick 은 "보존해야 할 동작" 을 아무도 적지 않는다.

**판정이 보지 못하는 것**(리뷰어가 본다): 테스트·문서 파일은 줄 수 상한 밖이다(테스트를 대량으로 지워도 걸리지 않는다) · 리뷰는 스테이징된 내용에 묶여 있지 않고 수정 시각으로만 비교한다(리뷰 뒤에 오래된 파일을 더 스테이징하면 걸리지 않는다) · 따옴표·역슬래시가 든 파일 이름은 판정할 수 없어 막는다.

## 안티패턴

- **자연어로 quick 추론 금지** — "간단히 고쳐줘" 로 이 경로를 고르지 않는다. 슬래시만.
- **범위를 넘겼는데 쪼개서 여러 번 커밋** — 상한을 피하려는 분할은 금지. 넘으면 `/maintain-lite`.
- **리뷰 생략 · 리뷰 뒤 수정** — 훅이 막는다. 우회하지 않는다.
- **검증 러너를 돌려 여는 것** — quick FID 는 `run-verification.sh` 가 통과해도 열리지 않는다. 범위·리뷰 조건을 맞추거나 `/maintain-lite` 로 간다.
- **태스크 문서를 지우고 그냥 커밋** — quick 을 벗어나는 것이 아니라 기록 없는 커밋이 된다.
- **신규 기능을 `/quick-fix` 로** — `/start-lite` 또는 `/start`.
- **무인 변형** — 없다. 만들지 않는다.

## 참조

- `scripts/quick-fix.sh` — start · seal · done
- `scripts/_internal/quick-scope.sh` — 범위·리뷰 판정기(봉인과 훅이 같이 쓴다)
- `scripts/_internal/check-task-receipt.sh` — 훅이 부르는 영수증 검사기(quick 절)
- `commands/maintain-lite.md` — 범위를 넘었을 때 가는 곳

---

*specops-ko v2.20.0 · 2026-10-10 · 최소 유지보수 진입 (문서 없음 · 영수증 + 코드 리뷰 1회 + 범위 상한)*
