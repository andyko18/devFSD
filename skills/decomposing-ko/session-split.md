# 구현 직전 세션 분리 (decomposing-ko 보조 문서)

> `skills/decomposing-ko/SKILL.md` `## 다음 skill` 에서 참조. `split-session.sh decide` 가 `SPLIT: yes` 일 때만 읽는다.

## 왜 나누는가

작업 1건 비용의 약 70%가 주 세션이 커진 대화를 호출마다 다시 읽는 것이었다(20261112 실측 — 호출 255회 · 대화 213K→792K 토큰). 호출이 가장 많은 구간이 구현인데, 그 구간은 설계 단계의 대화를 쓰지 않는다 — 필요한 것은 전부 `.specops/<FID>/` 파일에 있다. 그래서 구현부터 성능 게이트까지를 **대화 맥락이 빈 자식 세션**(`claude -p`)에 맡기고, 주 세션은 결과 1줄만 받는다. 사용자는 새 세션을 열거나 "계속"을 칠 필요가 없다.

- 자식이 맡는 구간: `implementing-ko` → `verifying-evidence-ko` → 보안·통합·성능 게이트의 **판정까지**.
- 주 세션이 맡는 구간: 그 앞(설계)과 그 뒤(**PR 생성 게이트** — 데모·PR 질문·PR 생성).
- 적용 대상: 풀 경로(`plan.md` 가 있는 FID)만. `/basic` · `-lite` · `/quick-fix` · trivial · `§batch` 는 나누지 않는다(판정기가 `no` 를 낸다).
- 끄는 방법: `/start --no-split …`(spec 에 `**§분리**: off`) · `.specops/config.yaml` 의 `session_split.enabled: false` · 환경변수 `SPECOPS_NO_SPLIT=1`.

## 절차

### 1. 시작 전 — 사용자에게 물을 것은 주 세션에서 먼저 묻는다

자식 세션에는 사용자 채널이 없다. `../implementing-ko/dev-autonomy.md` §1(알려진 외부·비가역 작업의 일괄 사전 승인)을 **여기서** 수행한다 — `grep -nE 'irreversible:[[:space:]]*true|^[[:space:]]*external:' .specops/<FID>/tasks.md` 로 모아 1회 질문하고 승인 기록(`dispatch/<task-id>-approval.md`)을 남긴다. 표지가 없으면 묻지 않는다.

### 2. 자식 세션 실행

사용자에게 1줄로 알린다: `구현 구간은 새 세션에서 진행합니다 — 진행 상황: bash "${CLAUDE_PLUGIN_ROOT}"/scripts/split-session.sh status <FID>`

Bash 도구의 `run_in_background: true` 로 실행한다(60분 넘게 돈다 — 포그라운드 금지):

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/split-session.sh run <FID>
```

그리고 **무엇을 기다리는지 1줄만 쓰고 턴을 끝낸다** — 자식이 끝나면 알림이 다음 턴을 연다(사용자 입력이 필요 없다). 기다리는 동안 자식의 로그(`.specops/<FID>/split/child.jsonl`)를 읽거나 주기적으로 확인하지 않는다 — 그 읽기가 곧 줄이려던 비용이다. 사용자가 진행을 물으면 `status` 1회로 답한다.

### 3. 결과 처리 — 마지막 줄 `SPLIT-RESULT:` 로 판정한다

| 결과 | 처리 |
|---|---|
| `DONE` | 아래 4 |
| `HELD` | `.specops/<FID>/split/held.md` 를 읽어 그 질문을 사용자에게 그대로 묻는다. 답을 받으면 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/split-session.sh run <FID> --resume "<사용자 답 원문>"` 을 다시 백그라운드로 띄운다(자식은 자기 맥락을 유지한 채 이어 간다). 승인이면 `dispatch/<task-id>-approval.md` 기록도 남긴다 |
| `TIMEOUT` | 1회에 한해 `… run <FID> --resume "이어서 진행하라."` 로 다시 띄운다. 두 번째면 `FAILED` 처럼 처리 |
| `FAILED` | 사용자에게 `detail=` 과 로그 경로(`.specops/<FID>/split/child.err`)를 알리고 멈춘다. 선택지: ① `--resume` 으로 재시도 ② 이 세션에서 직접 이어 가기 — `Skill: devfsd:implementing-ko`(dispatch-log·커밋에서 재개점을 읽는다 · 끝난 태스크를 다시 하지 않는다). 자식의 실패를 완료로 읽지 않는다 |

자식의 요약은 **보고**이지 증거가 아니다 — 판정은 파일(`evidence.md` · `reviews/` · `git log`)로 한다.

### 4. `DONE` 뒤 — 주 세션이 검증을 직접 한 번 돌리고 PR 게이트로 간다

R-2(PR 전 verify)의 실행 증거는 **이 세션의 기록**에 있어야 열린다(세션별 판정 — 자식의 실행은 자식의 기록에만 있다). 그래서 주 세션이 검증 러너를 직접 1회 실행한다(태스크의 테스트 명령만 돈다 — 전체 스위트가 아니다):

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/run-verification.sh <FID>
```

- `VERIFY: PASS` → `Skill: devfsd:performance-test-ko` 를 호출한다. 그 skill 의 「분리 복귀」가 판정을 다시 하지 않고 `## PR 생성 게이트`(데모 → PR 질문)부터 진행한다.
- 그 밖(`FAIL`·`PARTIAL`) → 자식이 통과시킨 검증이 이 트리에서 재현되지 않은 것이다. PR 게이트로 가지 않고 출력을 사용자에게 보인 뒤 `… run <FID> --resume "주 세션 재검증 실패: <출력 요지>. 원인을 고치고 verify 부터 다시 진행하라."` 로 자식에게 돌려보낸다(1회 — 다시 실패하면 멈추고 사용자에게 알린다).

PR 본문에는 `split/result.json` 의 자식 세션 소요(분·호출 수·비용)를 1줄 넣는다.

## 하지 않는 것

- `--dangerously-skip-permissions` · `bypassPermissions` 로 자식을 띄우지 않는다. 자식은 사용자의 권한 설정을 그대로 따른다(기본 모드가 auto 가 아니면 판정기가 `no` 를 낸다 — 그때는 종전대로 이 세션에서 구현한다).
- 자식 세션 안에서 다시 나누지 않는다(판정기가 `SPECOPS_SPLIT_CHILD=1` 을 보고 `no`).
- 자식이 PR 을 만들지 않는다 — 데모와 PR 생성 여부는 사용자가 이 세션에서 본다.
