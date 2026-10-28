---
name: start-foundation
disable-model-invocation: true
description: "[공통부·대화형] specops-ko 한국어 자율 Lifecycle — 공통부 우선 개발 진입. specifying-ko 를 foundation 분기로 호출"
triggers:
  - "/start-foundation"
mode: ask
specops_version: 2.17.0
specops_layer: Lifecycle
reference_upstream: specops-ko 독자 추가
---

# /start-foundation [<공통부 설명>]

## 목적

specops-ko Lifecycle 에서 **per-feature `/start` 사이클 이전에** 실행 가능한 공통부 코드(라우팅·레이아웃·인증·공통 컴포넌트·DB 마이그레이션)를 생성하는 독립 커맨드.

한국 SI 표준 "공통부 먼저 개발" 단계를 지원한다. `/init-project`(doc-only) → **`/start-foundation`(공통 코드)** → `/start`(기능 단위) 순서로 진행.

## Process

0. **init 원장 우선** — `.specops/memory/project-context.md`·`decisions.md`가 있으면 clarifying이 이미 확정된 스택·인증·배포를 **재질문하지 않는다**(clarifying-ko 결정 원장 HARD). init 없이 진입했고 architecture placeholder만 있으면 기존 BLOCKING 게이트 유지.
0b. **범위는 공통부 FR 에서 온다** — `.specops/memory/requirements.md` 가 있으면 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-fr-table.sh --classify` 의 `SKIP|<FR-ID>|foundation-scope|…` 줄이 이 명령의 대상이다(설명 선두 `[공통]` 또는 `<!-- foundation-fr: … -->` 목록). 인자가 없거나 범위가 모호하면 그 FR 목록을 제시하고 이번 FID 가 다룰 FR 을 확인받는다 — 표에 없는 공통부를 임의로 더하지 않는다. 표에 공통부 FR 이 하나도 없으면 인자를 범위로 삼는다.
1. `devfsd:specifying-ko` 스킬 호출 — args 첫 줄에 `<!-- entry: foundation -->` HTML 주석을 prepend 하고 나머지 args 이어붙임
2. specifying-ko 가 foundation 분기 감지 → Step 5.5 **셸 전용**(allowlist `app-shell`·`layout`·`login` + `<!-- foundation-shell -->`, 기능 화면 금지) → **Step 5.6 인터페이스 design-first** — 이번 공통부가 **API 엔드포인트(제공)·DB 스키마(테이블·필드)·클라이언트 영속 데이터(localStorage·IndexedDB) 중 하나를 신설·변경할 때만** 적용한다(`specifying-ko` Step 5.6 적용 조건 — 순수 UI·CLI 로직만이면 skip). 공통부는 DB 스키마·공통 API 의 **본진**이라 design-first 가 가장 중요하다 → 공통부 컴포넌트 spec 작성 (§유형=`foundation`)
3. 이후 chain: clarifying-ko(기술스택 BLOCKING 게이트 — 원장에 없으면) → planning-ko(foundation-manifest.md 산출) → decomposing-ko → implementing-ko → verifying-evidence-ko → requesting-code-review-ko → receiving-code-review-ko → security-review-ko → integration-test-ko → performance-test-ko → PR
4. **완료 기록** — verify 가 PASS 하면 이번 FID 가 만든 공통부 FR 을 요구사항 표에 남긴다(공통부 FR 은 `/start-all` queue 에서 SKIP 이라 FID 칸이 없다 — 여기 적지 않으면 어느 FID 가 그 FR 을 만들었는지 표에서 찾을 수 없다):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/fr-set-fid.sh <FID> <FR-ID> [<FR-ID>...]
   ```
   verify 출력의 `FOUNDATION-MANIFEST: NOTE — 공통부 FR 의 관련 spec 칸이 비어 있다` 줄이 남은 FR 을 알려 준다. 이번 FID 가 다루지 않은 FR 은 적지 않는다.

## manifest — 한 번 쓰고 끝나는 문서가 아니다

- **다시 실행할 때**(공통부를 나눠 만들거나 나중에 더할 때): `.specops/memory/foundation-manifest.md` 가 이미 있으면 템플릿으로 **다시 쓰지 않는다** — 기존 표에 행을 더하거나 고친다. verify 는 이전 manifest 에 있던 모듈명이 사라지면 경고한다.
- **최소 내용**: 표에 적은 경로 가운데 저장소에 실재하는 것이 하나는 있어야 verify(`check-foundation-manifest.sh`)와 `/start-all` 입구(`check-foundation-present.sh`)를 통과한다. 없는 경로는 경고로 나열된다.
- **기능 FID 가 공통 모듈을 바꿀 때**: 경로·공개 이름·사용법을 바꾸거나 새 공통 모듈을 더하는 커밋은 같은 커밋에서 표를 고친다(템플릿의 `갱신 규약`). 재사용 게이트의 `FOUNDATION-REUSE: WARN`(선언이 manifest 의 어떤 이름도 담지 않음)과 입구의 없는 경로 경고가 낡은 manifest 의 신호다.

## 앞뒤 조건

- **슬래시 전용** — 자연어("공통부 만들어줘")로는 이 분기에 들어오지 않는다(메타 skill 은 신규·유지보수만 가른다). 자연어로 시작하면 일반 `/start` 로 가서 manifest 게이트·셸 규칙이 적용되지 않는다.
- **`/start-all` 은 이 FID 가 main 에 머지된 뒤** — `/start-all` Phase 0 의 `check-foundation-merged.sh` 가 `feat/<FID>` 미머지면 막는다. squash·rebase 머지는 git 조상 판정에 안 잡히므로 `gh` 로 PR 상태를 읽을 수 있어야 한다(읽을 수 없으면 로컬의 머지된 `feat/<FID>` 브랜치를 지운다 — 브랜치가 없으면 머지 후 삭제로 본다).
- **태스크는 9개까지** — 10개 이상이면 구현 직전 `FID-SIZE: FAIL` 로 막힌다(다른 대화형 FID 와 같다 · 실기록: 21 태스크 FID 는 32시간이 걸렸고 plan 리뷰가 2회 FAIL 했다). 공통부가 크면 **spec 단계에서 층별로 나눠** 시작한다 — 예: 스캐폴딩·DB 베이스 → 인증 → 화면 셸. 층마다 `/start-foundation` 을 다시 돌리고, manifest 는 다음 FID 가 행을 더한다. 0b 에서 이번 FID 가 다룰 FR 을 고를 때 이 상한을 함께 본다.
- **스택 근거** — architecture 문서의 스택 줄(프레임워크·언어·런타임)에 미확정이 남아 있으면 구현 직전 `check-stack-decided.sh` 가 결정 원장 또는 clarifications 의 RESOLVED 를 요구한다. architecture 문서가 없는 프로젝트(CLI·라이브러리)는 막지 않고, 근거가 어디에도 없을 때만 `STACK-DECIDED: NOTE` 로 알린다.

## 사용 예

```
/start-foundation React 기반 SPA 공통부 — 라우팅, 인증, 레이아웃, API 클라이언트

→ specifying-ko 호출 (args 첫 줄: <!-- entry: foundation -->)
→ foundation 분기 진입 → Step 5.5 셸(app-shell 등) → 공통부 spec 작성
→ Step 5.6: 공통 API·테이블을 api-spec.md·data-model.md 에 먼저 반영 (foundation-baseline 마커 안에)
→ clarifying-ko: 기술 프레임워크 BLOCKING 확정
→ planning-ko: 공통부 구현 + foundation-manifest.md 산출
→ decomposing-ko: 태스크 분해 (이 FID 는 공통부를 **만드는** 쪽이라 재사용 선언 대상이 아니다)
→ verify: manifest 채움·실재 경로 검사 → 통과 후 fr-set-fid.sh 로 공통 FR 기록
→ main 머지 뒤 /start·/start-all 의 각 task 가 재사용 선언 의무(manifest 가 생겼으므로)
```

## 안티패턴

- **기능 화면을 foundation에서 설계** — `dashboard`/`home` 등 allowlist 밖 `screens/*` 금지. 셸(`app-shell`·`layout`·`login`)만. 기능 화면은 `/start-all` Phase 2.5-A
- **화면 단위 기능 구현 요구** — `/start-foundation` 은 인프라·공통부 전용. 기능 FR은 foundation 완료 후 `/start`·`/start-all`
- **specifying-ko 생략** — 공통부라도 spec → clarify → plan → decompose 체인 필수. 직접 구현 금지
- **`/init-project` 대체** — `/start-foundation` 은 foundation 코드 생성 전용. 프로젝트 문서 부트스트랩은 `/init-project` 담당
- **§batch 라벨 병기** — foundation FID 에 `**§batch**` 를 쓰지 않는다(hybrid 금지). requirements 의 `[공통]` FR 은 `/start-all` 이 SKIP 하므로 batch queue 에 넣을 필요 없음

## 참조

- `skills/specifying-ko/SKILL.md` — foundation 분기 처리 (Step 5.5 셸 전용 · Step 5.6 적용, §유형=foundation)
- `skills/clarifying-ko/SKILL.md` — 기술스택 BLOCKING 게이트
- `skills/planning-ko/SKILL.md` — foundation-manifest.md 산출 지시
- `skills/decomposing-ko/SKILL.md` — 재사용 HARD GATE 조건
- `templates/foundation-manifest.md` — manifest 템플릿
- `commands/start.md` — 기능 단위 구현 진입 슬래시 (미러링 패턴 참조)
- `scripts/_internal/check-fr-table.sh` — `[공통]` → `foundation-scope` SKIP (start-all Phase 0)
- `scripts/_internal/check-foundation-manifest.sh` — **verify HARD 게이트**. §유형=foundation FID 완료 시 `.specops/memory/foundation-manifest.md` 존재·채움을 검사해 미산출이면 `VERIFY: FAIL` (`run-verification.sh` 가 호출)
- `scripts/_internal/check-spec-label-compat.sh` — **verify HARD 게이트**. `§유형=foundation` 과 `§batch` hybrid 라벨을 금지 (emit-context·verify 양쪽에서 FAIL)

---

*specops-ko v2.17.0 · 2026-10-09 · 공통부 FR 범위·완료 기록 · manifest 최소 내용과 갱신 규약 · 앞뒤 조건*
