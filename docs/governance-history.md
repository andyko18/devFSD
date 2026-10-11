# 거버넌스 엔진 — 근거·이력

> 이 파일은 `CLAUDE.md` `## 아키텍처 › ### 거버넌스 엔진` 에서 옮긴 **근거·사건 이력** 이다. 규칙의 SoT 는 CLAUDE.md 다 — 여기서는 "왜 그렇게 됐나"만 읽는다. (20261011-claude-md-diet)

## 1. 플러그인 런타임 예외

**플러그인 런타임 예외** (`_files_all_docs`): `.claude-plugin/plugin.json` 이 있는 repo 에서는 `skills/*/SKILL.md`·`commands/*.md`·`agents/*.md`·`templates/*.md`·`hooks/*`·`.claude-plugin/*` 이 **확장자와 무관하게 코드**다. 이 플러그인의 실행 로직은 산문이라, `*.md` 를 무조건 문서로 보면 verify 강제가 제품 본체에서 통째로 면제됐다 (실측: 최근 커밋의 다수가 면제 클래스였고 그중 실제 행동 변경이 상당수였다 — 릴리즈 스탬프 제외). 제거된 `§auto` 자기발급 면제표보다 넓었다. **플러그인 repo 에서만** 적용한다 — 이 경로는 Claude Code 플러그인 규약이지 앱 규약이 아니라서, 무조건 걸면 하류 앱 repo 의 `templates/email.md` 가 문서 커밋에서 막히고 false-deny 가 BYPASS 관성을 만든다. 같은 트리라도 `skills/*/README.md`·루트 `README`·`CHANGELOG`·`CLAUDE.md` 는 면제 유지(배포 런타임 아님).

## 2. 면제 조회 — "이 커밋은 면제됩니까"를 미리 묻는다

**면제 조회 — "이 커밋은 면제됩니까"를 미리 묻는다**: `bash scripts/_internal/scope-explain.sh '<커밋 명령>'`(인자, 또는 stdin 파이프)이 훅과 **같은 판정 함수**를 불러 `SCOPE=staged|conservative EXEMPT=yes|no REASON=<class>(<N> files)` 1줄로 답한다. rc 계약: **0=판정 성공 · 2=입력 없음/읽기 불가 · 3=판정기 로드 불가** — 판정 불가를 그럴듯한 1줄로 위장하지 않는다. 훅 경로에서 묻고 싶으면 `SPECOPS_DRYRUN=1`(env 또는 **명령 선두 인라인**)을 붙인다: 같은 1줄을 stderr 로 내고 **deny 한다** — 조회이므로 커밋을 실행하지 않는다(allow 를 한 건도 늘리지 않는 deny 전용 경로). 커밋 명령 **앞의** `cd <repo 내부 경로>`·bare `VAR=값` 선행 줄은 **최대 8줄까지** 안전 prelude 로 인정해 그 뒤 커밋을 판정한다(그 밖의 선행 줄 — `cd ..`·`cd -`·타 repo 절대경로·명령치환·`git add -A` 등 — 은 보수 판정). ⚠️ **DRYRUN 의 관할 경계**: `.specops/` 부재 repo 와 **사유를 병기한** `SPECOPS_GOVERNANCE_BYPASS=1`(무사유는 deny 라 실행되지 않는다) 사용 시에는 훅이 **그 앞 분기에서 이미 빠져나가** DRYRUN 이 무시되고 커밋이 **실제로 실행된다**(실측: 두 경우 모두 `{"continue":true}`) — 조회 의도였다면 커밋이 나간 뒤에야 알게 되므로, 그 두 상황에서는 `scope-explain.sh` 를 쓴다.

## 3. 실행 증거는 그 FID 의 것이어야 하고, 검증 뒤 코드가 바뀌면 닫힌다

**실행 증거는 그 FID 의 것이어야 하고, 검증 뒤 코드가 바뀌면 닫힌다** (20261009): 러너 명령에 FID 가 글자로 적혀 있는데(`run-verification.sh <FID>`) 그것이 활성 FID 가 아니면 실행 증거로 치지 않는다 — 한 세션에서 FID 여럿을 다루면 앞 FID 의 PASS 가 뒤 FID 의 커밋을 열었다(실기록 커밋 919건 중 12건). FID 가 변수거나 `run-all.sh` 면 판단하지 않는다. 그리고 판정 SoT(`verification-state.sh current`)가 `STALE` 이면 진행 기록·스탬프가 있어도 R-1 은 열리지 않는다 — 종전에는 transcript 의 Edit/Write 이벤트로만 무효화를 봐서, 셸 명령·포매터·코드 생성기·서브에이전트가 고친 코드는 검증 없이 커밋됐다. `STALE` 이어도 막지 않는 경우는 둘이다(`_vs_stale_blocks`) — 전체 스위트가 **지금 이 트리**에서 통과했거나(`full-suite-fresh.sh` rc 0 — `run-all.sh` 는 판정 상태를 갱신하지 않는다), 달라진 것이 추적하지 않는 파일뿐일 때(`verification-state.sh stale-scope` = `untracked-only` — 기록의 `tracked_nondoc_hash` 와 대조 · 커밋만 실행하는 명령(`git commit [-a] -m …` 한 줄 — `_commit_scope_is_staged`)일 때만 · compound·파이프·경로 인자는 조회용 명령과 함께여도 제외). 거부 문안은 다른 FID 의 러너였으면 그렇다고 말한다(`cause.exec = otherfid`).

## 4. 커밋·PR 인식 표기

**커밋·PR 인식 표기** (20261009): 트리거(`hooks/rules.jsonl` R-1·R-2 `trigger_pattern`)는 명령 위치의 `git commit`·`gh pr create` 를 env 접두·래퍼(`rtk`·`time`·`nice`·`sudo`·`env` 와 그 옵션 · `exec`·`nohup`·`timeout N`)·제어 키워드(`then`·`do`·`else`·`if`·`while`·`!`)·`case` 가지 뒤, 경로로 부른 형태(`/usr/bin/git`), 줄 연속, `gh pr -R … create` 까지 인식한다. 트리거 판정은 줄 연속을 이은 문자열과 **잇기 전 원문을 둘 다** 본다(`_trigger_scan_text` — 이은 것만 보면 주석 줄 끝 `\` 다음 줄의 실커밋을 놓친다). 일치 여부는 **파이프 없이** 읽는다(`grep -Eq "$re" <<< "$text"`) — 훅은 `set -uo pipefail` 이라 `producer | grep -q` 는 grep 이 첫 일치에서 끝나는 순간 앞단이 SIGPIPE 로 죽어 일치가 불일치로 읽힌다(20261010: 인용 메시지 + 줄 연속 커밋과 큰 여러 줄 명령이 통째로 통과했다 · `test-hooks.sh` T8.m 이 훅과 훅이 source 하는 파일에서 한 줄 안의 `| grep -q` 재발을 잠그고, T8.o 가 pipefail 을 켜는 훅 밖 스크립트(`scripts/`·`skills/`·`evals/` — 테스트 제외)를 같은 규칙으로 잠근다(20261011: `locale -a | grep -q` 는 입력 3KB 에서도 매번 틀렸다 — 앞단이 나눠 쓰면 입력이 작아도 난다) — 줄을 바꿔 쓴 형태와 다른 조기 종료 소비자는 보지 못한다). 종전에는 이 표기들이 차단도 사후 감사도 거치지 않았다(이 저장소 커밋 80건 중 17건). `sh -c`·`eval`·`xargs`·alias·변수에 든 명령은 여전히 범위 밖이다(`docs/architecture.md` §6-1 표). pretool 을 설정으로 끈 채 커밋·PR 이 나가면 repo 레벨 friction-log 에 `GOVERNANCE-DISABLED` 가 남는다(끄는 것 자체는 막지 않는다).

## 5. ①만으로는 열리지 않는다

**①만으로는 열리지 않는다** — 실행 증거(`_exec_rc ≠ 1` — `0`=러너 실행 확인 · `2`=판정 불가 fail-open)는 자기보고 3경로를 **여는 전제조건**이지 단독 면제가 아니다. 앵커가 하나도 없으면 러너를 몇 번 돌려도 통과하지 않는다. R-1 의 implement 창은 FID 에 `tasks.md` 가 있고 **verify 가 아직 유효 PASS 가 아닐 때**(`verification-state` 가 `NOT_RUN`·`PARTIAL`·`FAIL`) 열리며 receipt 로 면제된다 — 종전의 `evidence.md 부재` 조건은 구현 중 태스크가 그 파일을 쓰면 남은 태스크의 탈출구를 닫았다. `STALE`·`WAIVED` 는 창이 닫힌다. deny 메시지는 세 조건(①·②·receipt)의 **실제 상태**를 표시한다(`cause` 진단이 없거나 파싱 실패면 종전 무조건 3블록 문안으로 떨어지고 deny 는 유지된다).

## 6. quick 경로

**quick 경로** (20261010): 태스크 문서는 있고 명세(`spec.md`)가 없는 FID 는 `/quick-fix` 의 FID 다. R-1 의 receipt 경로가 그대로 쓰이되(테스트 실제 실행 · staged ⊆ outputs · 트리 신선도), `check-task-receipt.sh` 가 판정기(`scripts/_internal/quick-scope.sh`)를 불러 **범위**(구현 파일 수 · 변경 줄 수 상한 — 테스트·문서 제외 · 고위험 신호 없음. 수치는 판정기 머리의 상수가 유일한 정의다)와 **리뷰**(통과 판정의 `reviews/T1-C-report.md` 가 마지막 수정보다 새것)를 함께 요구한다. 넘으면 deny 하고 `/maintain-lite` 를 안내한다(`cause.receipt = quick-over | quick-noreview`). 판정 기준이 모델이 쓰는 표지가 아니라 **구조**인 이유: 표지는 빼면 그만이지만 구조를 피하는 길은 명세 파일을 두는 것뿐이고, 그 경우는 종전의 정식 영수증 경로다(빈 명세 파일로도 피해진다 — 이 경로가 새로 만든 구멍은 아니다). 판정기가 판정하지 못하면(판정 불가 — 따옴표가 든 파일 이름 포함) 막되 범위 초과라고 말하지 않는다. quick 구조의 FID 는 **verify 상태와 무관하게** 이 판정을 받는다 — 검증 러너가 PASS 를 내도 영수증 가지를 타고(`_quick_structure`), 스테이징된 것만 커밋하는 명령이 아니면(`-a`·경로 인자·다른 명령과 묶음) 막는다(`cause.receipt = quick-unstaged`). quick 사유의 거부 문안은 검증 러너 안내(①②)를 붙이지 않는다. 판정이 보지 못하는 것: 테스트·문서의 줄 수 · 리뷰와 스테이징 내용의 결속(수정 시각 비교뿐이다). 명세가 있는 FID 와 태스크 문서가 없는 FID 의 판정은 그대로다. 손으로 쓴 리뷰 보고서 파일은 가리지 못한다(정식 경로의 리뷰 감사와 같은 한계).

## 7. `hooks/governance-lib.sh` 는 800줄 규칙 예외다


`~/.claude/rules/coding-style.md` 는 "파일 800줄 max" 를 언어 한정 없이 적는다. 이 repo 는 그 규칙을 **`hooks/governance-lib.sh`(1892줄 · 함수 51개) 한 파일에 한해 적용하지 않는다** — 51개 함수가 하나의 판정 계약(transcript 조인 · 면제 클래스 · 마찰 기록 · 우회 분류 · degraded 기록)을 공유하는 bash 라이브러리라 응집도가 곧 목적이고, 인터페이스는 훅이 source 해서 함수를 부르는 단일 표면이다. (규칙의 예시 코드가 JS/TS 라 "앱 코드 상정" 으로 읽을 여지가 있으나, **그건 원문 진술이 아니라 해석**이다 — 여기서는 규칙의 적용 범위를 재정의하지 않고 이 파일 하나에 예외를 둔다.)

**분할의 위험**: 가드 하나를 조용히 떨어뜨리면 v1.88.0 이 고친 병의 재발이다 — 그 릴리즈는 "강제층 자신이 조용히 사라지는 경로가 셋 있었다"를 다뤘다. 나눌 이유가 생기면 **되돌려-관찰(변이 주입)로 각 가드의 생존을 실증하며** 나눈다. 이 예외는 분할 검토를 영구 금지하지 않고 근거 없는 분할만 막는다.

**크기가 공짜라는 뜻은 아니다**: gbrain `20260807-governance-lib-freefix`(confidence: low — 근거는 자유 수정 2회 관측)는 이 파일을 훅 4종 공용이라 lifecycle 밖 즉흥 수정이 잦은 핫스팟으로 기록했다. 예외는 이 **한 파일에만** 적용되며 다른 파일의 비대화를 정당화하지 않는다. (참고 — 800줄 초과 파일은 수치가 자주 바뀌므로 여기에 적지 않는다: `git ls-files | xargs wc -l` 로 재확인한다. **프로덕션 코드**는 `hooks/governance-lib.sh` 와, 위 `## 거버넌스 엔진` 의 **플러그인 런타임 예외**로 "확장자와 무관하게 코드"가 되는 `skills/*/SKILL.md` 중 800줄을 넘는 것이다. **그 SKILL.md 에 800줄 예외를 발급하는 것이 아니다**: 이 절의 예외는 여전히 `hooks/governance-lib.sh` **한 파일에만** 적용되고, SKILL.md 의 분할·축소는 별건(크기 래칫과 보조 파일 분리)이다. 나머지 초과 파일은 테스트 스위트와 `CHANGELOG.md` 다.)

