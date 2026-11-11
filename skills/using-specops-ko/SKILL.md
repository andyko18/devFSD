---
name: using-specops-ko
description: 모든 대화 시작 시 활성 — specops-ko 한국어 자율 Lifecycle 메타 skill. 사용자 입력에서 기능 요청 신호 감지 시 devfsd:specifying-ko 자동 호출 강제 (5원칙 주입)
layer: 1
reference_upstream: obra/superpowers@v5.0.7 skills/using-superpowers/SKILL.md
specops_version: 2.20.0
used_by: 모든 Claude Code 세션 (SessionStart 자동 주입)
---

# Harness 메타 스킬 — specops-ko 자율 Lifecycle 진입

<SUBAGENT-STOP>
서브에이전트로 dispatch되어 특정 task를 실행 중이라면 본 skill 건너뜀.
</SUBAGENT-STOP>

<EXTREMELY-IMPORTANT>
1% 가능성이라도 specops-ko Lifecycle skill이 적용될 수 있다면 **반드시** 호출한다.

특히 사용자 입력이 다음 신호를 포함하면 즉시 `devfsd:specifying-ko` 호출:

**[신규 신호]** — `maintenance flag = false`:
- "X 기능을 만들고 싶어"
- "Y CLI / API / 모듈 신규"
- "Z를 구현해줘"
- "/start <기능>" 슬래시
- 명확한 신규 산출물 요청

**[유지보수 신호]** — `maintenance flag = true`:
- "X 버그 고쳐줘 / 수정해줘"
- "Y 리팩터링 해줘"
- "Z 개선 / 변경"
- "/maintain <대상>" 슬래시

> **배제 조건**: 위 신호가 있어도, 요청이 **명백히 repo 밖 산출물**만 만드는 경우에는 chain 진입을 보류한다 — PPT·Excel·외부 기획서/요구사항 정의서 · 데이터 분석 보고 · 단순 질의응답. 이런 작업은 **테스트할 코드가 없어서** 후속 단계(clarify·plan·decompose·implement·verify)가 전부 공회전하고, 사용자를 도구 밖으로 밀어낸다.
>
> **repo 내 파일**(코드·설정·스크립트·스키마 **및 README·CLAUDE.md 등 문서**)을 만들거나 고치면 **진입한다** — 문서만 고치려다 코드까지 건드리는 일이 흔하다.
>
> **애매하면 호출한다.** 배제는 명백할 때만이다 — 진짜 코딩 작업을 놓치는 것(false-negative)이 그 반대보다 훨씬 나쁘다.
>
> **배제 시 1줄 고지**: "(코딩 작업이 아니라 판단해 lifecycle 을 진입하지 않았습니다. 필요하면 `/start <설명>` 으로 강제 진입할 수 있습니다.)" — `/start` 슬래시는 무조건 직행하므로(`commands/start.md` SoT), 판정이 틀렸을 때 사용자가 즉시 뒤집을 수 있다.

> **경계**: `/start <인자>` 슬래시는 인자 내용을 2차 판단하지 않고 무조건 specifying-ko 직행 — 동작 정의 SoT 는 `commands/start.md`(본 skill 은 자연어 신호 감지만).

> **lite 추론 금지**: "가볍게", "토큰 아끼고", "짧게 해줘" 등 자연어로 `/start-lite`·`/maintain-lite`·`/quick-fix`를 **추론하지 않는다**. 셋 다 슬래시 전용(`commands/`의 각 파일이 SoT). 자연어 신규/유지보수는 기존대로 `/start`·`/maintain` 경로(또는 풀 chain)만.

이는 협상 사항이 아니다. 합리화로 우회 금지.
</EXTREMELY-IMPORTANT>

## 진입 분기

우선순위: 사용자 명시 지시·CLAUDE.md > specops-ko skill > 기본 시스템 프롬프트. 신호 감지 후 신규/유지보수를 1회 분류한다(모호하면 "신규 / 유지보수 어느 쪽?" 1문항).

| flag | 진입 | args |
|---|---|---|
| 신규 | `devfsd:specifying-ko` | 원본 그대로 |
| 유지보수 | `devfsd:analyzing-ko` 먼저(★ HARD GATE) → specifying-ko | 첫 줄 `<!-- entry: maintain -->` prepend 후 원본 |

announce: "Using specifying-ko|analyzing-ko (maintenance) to <purpose>". 이후 chain 은 각 skill 본문 `## 다음 skill` 이 강제한다(Conductor 없음). skill 은 `Skill` 도구로 호출(`devfsd:` namespace) — SKILL.md 를 `Read` 로 직접 읽지 않는다.

> **기본 동작 `§일괄`**: 질문 묶음 → 승인 1회 → PR 까지 무정지. 위 단계별 확인은 `--step` — 슬래시로만(자연어 추론 금지).

## 조건부 보조 문서 (필요할 때만 `Read` — 디렉터리는 훅이 아래에 준다)

- **프로젝트 최초 진입**: 신호 감지 뒤 분류 전에 `.specops/`·`CLAUDE.md` 존재를 1회 본다. 둘 다 없으면 "프로젝트가 초기화되지 않았습니다. `/init-project` 권장 [y/N]" 1줄, 한쪽만 없으면 `/init-project --resume` 권장 1줄(강제 X). 4분기 전체·`y`/`N` 처리: `bootstrap-resume.md`.
- **미완 재개 통보**: `<session-progress-rehydrate>` 최상단 활동 줄이 종결 마커(`/lifecycle DONE`·`/finishing 완료`·`PR #N 생성`·`DONE (PR`)면 침묵, 아니면 `bootstrap-resume.md` 재개 절차(새 신호 우선 · 신호 없으면 능동 제안).
- **chain 흐름도·적색 플래그·5원칙·Karpathy·advisor**: `guardrails.md` (과잉 발동도 적색 플래그다 — 배제 조건 확인).
- **자유작업 pending**: `<freecomment-pending>` 블록이 있으면 그 절차 파일(`using-specops-ko/freework-pending.md`)을 `Read` 해 **다음 사용자 턴 시작 시** 수행.
