---
name: specifying-ko
description: 모든 창작 작업 전에 반드시 사용 — 기능 신설·컴포넌트 구축·동작 수정 전 사용자 의도·요구사항·설계를 탐색. 설계 승인 전 어떤 구현 스킬도 호출하지 않는다.
layer: 2
reference_upstream: obra/superpowers@v5.0.7 skills/brainstorming/SKILL.md
  - obra/superpowers@v5.0.7 skills/brainstorming/SKILL.md (전반 "의도 탐색" + spec 산출 분리)
  - skills/brainstorming-ko/SKILL.md
specops_version: 2.17.0
used_by: using-specops-ko, /start, /start-lite, /start-lite-auto, /start-auto, /start-foundation, /start-all, /start-all-auto, /maintain, /maintain-lite, /maintain-auto, /maintain-lite-auto, /promote
---

# Engine 스킬 — 아이디어를 설계로 (specifying)

아이디어를 자연스러운 대화로 완성된 설계·스펙으로 탈바꿈시킨다. 현재 프로젝트 맥락을 먼저 이해한 뒤, 아이디어를 정교화하는 질문을 **한 번에 하나씩** 던진다. 무엇을 만들지 이해되면 설계를 제시하고 사용자 승인을 받는다.

<HARD-GATE>
설계를 제시하고 **사용자가 승인하기 전까지** 어떤 구현 스킬도 호출하지 않는다. 코드 작성 금지, 프로젝트 스캐폴딩 금지, 어떠한 구현 행위도 금지. 이는 **모든** 프로젝트에 적용된다 — 인지된 단순성과 무관하게.

**판정: 대화 게이트 (기계화 불가)** — "사용자가 승인했는가" 는 대화 사실이라 아티팩트가 없다. 다만 **후속 관문이 우회를 좁힌다**: `emit-context` 가 spec.md·acceptance-criteria.md 실재를 요구하고(승인 없이 구현하면 이 산출물이 없다), R-1 이 커밋 전 verify 실행 증거를 요구한다. 승인 자체는 못 잡아도 **승인 없이 만든 코드는 커밋되지 않는다**.
</HARD-GATE>

## 안티패턴: "너무 간단해서 설계 불필요"

할 일 목록, 단일 함수 유틸, 설정 변경 — 전부 이 프로세스를 거친다. "간단한" 프로젝트가 **점검되지 않은 가정**으로 가장 많은 낭비를 만든다. 설계는 짧아도 된다(정말 단순하면 몇 문장). 하지만 **반드시 제시하고 승인**받는다.

## 체크리스트

다음 각 항목을 순서대로 태스크로 만들어 완료한다:

0. **[신규 분기] FID 생성 + 브랜치 생성** — args에서 슬러그를 추출해 FID를 결정하고, 디렉토리와 feat 브랜치를 함께 생성한다.

   ```bash
   # FID 결정 (날짜 + 기능 설명 슬러그)
   # 슬러그 규칙: 소문자 kebab-case, 영숫자+하이픈만, 최대 40자(초과 시 의미 단위로 절단),
   #   추출 불가(빈값·특수문자만·이모지) 시 fallback `feature-<HHMM>` 사용 — trailing dash 금지
   #   args 의 주석 줄(`<!-- step: true -->` 등)은 슬러그에서 뺀다
   FID="YYYYMMDD-<slug>"
   mkdir -p .specops/$FID
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/git-branch-create.sh $FID
   # 단계 소요 측정의 기준점 — 실패해도 chain 을 막지 않는다(graceful).
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/record-metric.sh --fid $FID --phase fid-start >/dev/null 2>&1 || true
   ```

   기존 `.specops/<FID>/` 디렉토리가 있으면 (유지보수 분기 재진입) 스킵.
   [유지보수 분기]는 analyzing-ko Step 0이 브랜치 생성을 담당하므로 본 스텝 적용 제외.

   **[batch 분기]**: args 첫 줄이 `<!-- entry: batch -->` 이면 → `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/git-branch-create.sh` **호출 금지** (브랜치는 `/start-all` 오케스트레이터가 이미 생성). 둘째 줄 `<!-- batch-id: <id> -->` 에서 batch-id를 추출해 Step 6에서 `**§batch**: <id>` 라벨 기재에 사용.

1. **프로젝트 맥락 탐색** — 파일·문서·최근 커밋 확인
   - 프로젝트 루트 `DESIGN.md` 존재 확인 (`ls DESIGN.md`)
     → **있으면**: 생성하는 `spec.md` §참조에 "`DESIGN.md` 디자인 시스템 준수" 포함
     → **없으면**: UI 컴포넌트 포함 기능이면 (HTML/CSS/React/Vue 등 시각 렌더링 포함) `/init-project` 실행 안내 (Phase 6 에서 DESIGN.md 생성 — `/start-design` 은 deprecated, `/init-project` 로 통합)
   - 프로젝트 루트 `screens/` 존재 확인 (`ls screens/ 2>/dev/null`)
     → **있으면 + UI 기능**: 기존 화면 목록 표시 — "현재 N개 화면: {name1}, {name2} ..." (신규는 Step 5.5 · **batch는 Phase 2.5-A**에서 설계)
     → **있으면 + 비UI 기능**: 무시 (screens/ 존재만 확인)
     → **없으면 + UI 기능**: `screens/` 자동 생성 예정 (신규: Step 5.5 · **batch: `/start-all` Phase 2.5-A → 2.5-B IF**)
   - **`.specops/memory/*` 부트스트랩 산출물 자동 감지** (v2.0 신규 — `/init-project` 산출):
     - `.specops/memory/` 부재 → **graceful skip** (기존 dogfood 회귀 보호 — 부트스트랩되지 않은 프로젝트도 specifying-ko 정상 동작)
     - 존재 시: `ls .specops/memory/*.md 2>/dev/null` 결과를 spec.md `§참조` 에 자동 인용 (Step 6 작성 시):

       | 감지 파일 | spec.md §참조 인용 (bullet) |
       |---|---|
       | `constitution.md` | 헌법 준수 — `.specops/memory/constitution.md` |
       | `requirements.md` | FR/NFR 마스터 — `.specops/memory/requirements.md` |
       | `architecture.md` | 시스템 컴포넌트 — `.specops/memory/architecture.md` |
       | `frontend-architecture.md` | 프론트 아키텍처 — `.specops/memory/frontend-architecture.md` |
       | `backend-architecture.md` | 백엔드 아키텍처 — `.specops/memory/backend-architecture.md` |
       | `api-spec.md` | IF 설계서 — `.specops/memory/api-spec.md` |
       | `data-model.md` | 테이블 설계서 — `.specops/memory/data-model.md` |
       | `process-design.md` | 프로세스 설계서 — `.specops/memory/process-design.md` |
       | `screens-overview.md` | 화면 목록 마스터 — `.specops/memory/screens-overview.md` |
       | `test-strategy.md` | 테스트 전략 — `.specops/memory/test-strategy.md` |
       | `project-context.md` | 프로젝트 컨텍스트 — `.specops/memory/project-context.md` |
       | `decisions.md` | 결정 원장 — `.specops/memory/decisions.md` |

     - **프로세스 연결** — `process-design.md` 가 있으면 이 기능이 속한 프로세스 ID(`P-NNN`)를 찾아 spec §1 에 `**프로세스**: P-NNN <이름>` 을 적고, 그 블록의 트리거·결과·예외를 AC 도출의 입력으로 쓴다. 대응 프로세스가 없으면 `**프로세스**: 해당 없음 (신규 — process-design.md 갱신 필요)` 로 적는다(문서 자체는 여기서 고치지 않는다)
     - 레거시: `memory/intent.md` 가 프로세스 형식으로 남아 있으면 프로세스 설계서로 인용하고 `process-design.md` 로의 이관을 1줄 안내한다(자동 변경 금지)

     - **`.specops/memory/brainstorming-*.md` PRD-first 합성** (v2.2 신규):
       - `ls .specops/memory/brainstorming-*.md 2>/dev/null` — 부재 시 graceful skip (AC-1)
       - 존재 시: 최신 파일(`ls -t | head -1` 수정 시간 기준) 읽기 → 핵심 인사이트(문제·대상·방향) 추출 → spec.md **§1 개요** 하단에 아래 블록 주입 (AC-2):
         ```markdown
         > **브레인스토밍 컨텍스트** (`<실제 파일명>`):
         > - 문제: <Startup: ## 현재 상태 요약 / Builder: ## 핵심 감탄 포인트 요약>
         > - 대상: <Startup: ## 고객 증거 §Q3 인물 / Builder: ## 핵심 감탄 포인트에서 추론 — 없으면 "미명시">
         > - 방향: <Startup: ## 최소 버전 Spec / Builder: ### 선택된 방향>
         ```
       - §참조에도 동일 파일 citation bullet 추가 (기존 패턴 유지, AC-3)
     - 위 표에 없는 `.specops/memory/*.md` 추가 산출물도 동일 패턴 (`brainstorming-*.md` 제외 — 위 PRD-first 합성 처리). (AC-5)
     - **회귀 보호 계약**: 본 분기는 spec.md §참조에 **인용만 추가**한다. 다른 섹션·내용을 변경하지 않는다 (T24 회귀 검증 대상). 단, `brainstorming-*.md` 감지 시 §1 개요 합성은 예외 (PRD-first 패턴, AC-4).
   - **`CONTEXT.md` 프로젝트 컨텍스트 자동 감지** (v2.1 신규):
     - `ls CONTEXT.md 2>/dev/null` — 부재 시 graceful skip
     - 존재 시: spec.md `§참조`에 `"프로젝트 컨텍스트 — \`CONTEXT.md\`"` 인용
   - **`docs/adr/*.md` Architecture Decision Records 자동 감지** (v2.1 신규):
     - `ls docs/adr/*.md 2>/dev/null | wc -l` — 0이면 graceful skip
     - N > 0이면: spec.md `§참조`에 `"아키텍처 결정 기록 — \`docs/adr/\` (N건)"` 인용
   - **gbrain 과거 인사이트 환류** (v2.3 신규 — learning-loop):
     - `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gbrain-recall.sh "<args 원문 — entry HTML 주석 줄 제외>"` 실행
     - learnings.jsonl 부재 또는 매칭 0건 → graceful skip (환류 블록 미출력)
     - 결과 있으면 (≤3건): spec.md `§참조` 에 각 건을 `- 과거 인사이트 (gbrain, <fid>): <insight>` bullet 로 인용
     - **회귀 보호 계약**: §참조에 인용만 추가 — 다른 섹션·내용 무변경 (memory 감지 표와 동일)
   - **유지보수·foundation·batch·lite 분기 진입 신호 검사** (Phase A) — **순서 고정** (`maintain-lite`를 `maintain`보다 먼저):
     - args 첫 줄이 `<!-- entry: maintain-lite -->` HTML 주석이면 **[maintain-lite 분기]** 진입
     - args 첫 줄이 `<!-- entry: maintain -->` HTML 주석이면 [유지보수 분기] 진입
     - args 첫 줄이 `<!-- entry: lite -->` HTML 주석이면 **[lite 분기]** 진입
     - args 첫 줄이 `<!-- entry: foundation -->` HTML 주석이면 **[foundation 분기]** 진입 — Step 5.5는 **셸 전용**(allowlist `app-shell`·`layout`·`login` + `<!-- foundation-shell -->`). 기능 화면 금지. 공통부 컴포넌트(라우팅·레이아웃·인증·공통 UI·DB 스키마)를 spec.md §2 포함 항목으로 DAG 의도 추출(독립/의존 표기). **단 Step 5.6(인터페이스 설계)은 적용한다** — foundation 은 DB 스키마·공통 API 의 본진이므로 design-first 가 가장 중요: 공통부 DB 스키마는 `data-model.md`, 공통 제공 API 는 `api-spec.md` 에 **먼저 반영**. (**역할 분리**: §2 DAG 추출 = 구현 **태스크 분해** 단위 / Step 5.6 `data-model`·`api-spec` 갱신 = **설계 기준 계약** — 둘은 다른 산출물이며 **모두 수행**한다.) spec.md §참조에 `.specops/memory/frontend-architecture.md`·`backend-architecture.md`·`data-model.md`·`api-spec.md` 자동 인용(기존 memory 감지 표 재사용)
     - args 첫 줄이 `<!-- entry: batch -->` HTML 주석이면 **[batch 분기]** 진입 — Step 0 git-branch-create skip. **Step 5.5·5.6 SKIP**(화면·인터페이스 본설계는 `/start-all` Phase 2.5에서 **화면→인터페이스** 순으로 통합 1회). UI면 §참조에 예정 화면 이름만, API/스키마면 예정 엔드포인트·테이블 이름만 남기고 상세 생성·승인 루프는 하지 않는다. Step 6에서 spec.md §1에 `**§batch**: <batch-id>` 라벨 기재(둘째 줄 `<!-- batch-id: ... -->` 에서 추출). **추가로 셋째 줄이 `<!-- auto: true -->` 이면 spec.md §1에 `**§auto**: true` 도 동시 기재** (무인 batch — `/start-all-auto` 진입. 다운스트림 §auto 자동통과 전파).
     - args 첫 줄이 `<!-- entry: auto -->` HTML 주석이면 **[auto 분기]** 진입 — git-branch-create.sh **호출 유지** (§auto는 단독 기능, 자체 브랜치 필요). Step 6에서 spec.md §1에 `**§auto**: true` 라벨 기재. 이후 `[신규 분기]` 동작 계속 (DESIGN.md·screens/ 점검 동일)
     - 그렇지 않으면 [신규 분기] (현재 동작 — DESIGN.md / screens/ 점검)
       - **★ 유지보수 오분류 백스톱** (soft — 하드강제 아님, 5원칙4 주권): [신규 분기]로 왔으나 요청이 **이미 구현된 코드·동작의 수정**(버그 수정·리팩터·기존 기능 변경)이면, 메타스킬 유지보수 분류나 `<!-- entry: maintain -->` 라벨이 누락됐을 수 있다(라벨은 모델-prepend 프로즈라 훅 강제 없음). 신규로 계속하기 전 사용자에게 **1회 확인**: "이 요청이 기존 코드 수정이면 `analyzing-ko` 선행이 회귀 안전망(current-state·impact-analysis + 회귀 AC-R 데이터/동작 보존)을 켭니다 — [신규 진행 / 유지보수 전환]?". `유지보수 전환` 응답 시 `analyzing-ko` 부터(★ HARD GATE) 재진입. **오탐 방지 계약**: 순수 신규 창작이 "개선·변경" 어휘를 포함하는 건 흔하므로, **기존 산출물(코드·스키마·API)을 실제로 건드리는 경우에만** 확인한다 — 신규 창작이면 묻지 말 것. 근거: 라벨 누락 시 analyzing HARD GATE 통째 skip → 유지보수가 신규로 처리돼 회귀 AC 미적용(커맨드 감사 20260719 [MED] — 관찰 실패 0의 백스톱).
     - **§일괄 판정 (기본 — 20261023)**: 신규·유지보수·lite·maintain-lite 분기에서 args 앞쪽 주석 줄에 `<!-- step: true -->`·`<!-- auto: true -->` 가 없으면 `§일괄` 이다(`entry: auto`·`batch`·`foundation` 은 해당 없음). Step 6 에서 spec §1 에 `**§일괄**: true` 를 적고, spec 이전(Step 1~5.6)과 `analyzing-ko` 는 이 args 판정을 쓴다. `§일괄` 이면 이 skill 의 사람 확인 — 명확화 질문 · 접근 선택 · intent 게이트 · 설계 섹션 승인 · 화면별 승인 · IF 확인 · 계약 칸 질문 · 유지보수 오분류 확인 · trivial 축약 제안 · 스펙 검토 — 은 같은 디렉터리 `once-approval.md` 를 Read 해 따른다(질문은 Step 3 에서 묶음 1회, 나머지는 승인 묶음). `<!-- step: true -->` 면 각 절의 기존 동작 그대로다. `<!-- step: true -->` 줄은 FID 슬러그·대상 설명에서 뺀다(주석 줄).

   **[유지보수 분기]** (Phase C 적용 — 본문 축약, analyzing-ko 결과 참조):
     - `analyzing-ko` 가 이미 호출되어 `.specops/<FID>/current-state.md` + `.specops/<FID>/impact-analysis.md` 가 산출되어 있어야 함
     - 본 skill 은 두 산출물을 **참조만** — 재분석 안 함
     - spec.md `§참조` 에 `current-state.md` + `impact-analysis.md` 경로 자동 포함
     - Step 3 명확화 질문으로 진행 (이후 순차 체크리스트로 Step 5.5/5.6 도달)
     - **★ 기존 API/스키마 수정 시 Step 5.6(인터페이스 design-first) 적용** — 변경된 엔드포인트/테이블을 구현 전 `api-spec.md`·`data-model.md` 에 반영(신규와 동일). 파괴적 스키마는 `impact-analysis.md §2`(expand-contract·data-down)·회귀 AC-R-2(데이터 보존) 연계.

     **Phase A 단독 시점 fallback** (analyzing-ko 부재 시 — Phase A 만 적용된 환경):
     - 본 skill 이 5 항목 mini-checklist 직접 실행:
       1. 변경 대상 파일·진입점 식별 (`grep -rn`, `Read`)
       2. 호출자/의존 매핑
       3. 기존 테스트 커버리지 확인
       4. 관찰 가능 동작 1~3 건 캡처
       5. 회귀 위험 1 줄 메모
     - 산출물: `.specops/<FID>/current-state.md` (templates/current-state.md 기반)
     - ★ HARD GATE: "분석 결과 검토. 진행? [y/n]"

   **[lite 분기]** (`/start-lite` — clarify·plan ceremony 축약, 화면/IF·teeth 유지):
     - FID·브랜치 생성은 [신규 분기] Step 0과 동일
     - **★ strict 승격 가드** (진입 직후·설계 전): 요청/변경 표면에 auth·oauth·jwt·rbac·credential·migration·ALTER/DROP TABLE·결제/PII·파괴적 스키마·public API 신설 등 **strict 신호**가 보이면 lite 진행 **금지**. 사용자에게 "`/start-lite` 범위 밖(고위험) — `/start`로 진행하세요" 안내 후 **중단**(강제 다운그레이드 금지). 무인 표지가 있으면 중단 대신 승격한다 — 아래 `[무인 표지 (둘째 줄)]`.
       > 본 가드는 조기 차단(설계 전)이지만 **모델 판단**이다. 놓쳐도 `decomposing-ko` Step 10c 의 `risk-profile.sh` 가 `LITE-STRICT-GUARD` rc=3 으로 기계 탐지한다(승격 강제). 이중 안전망 — 여기서 잡는 게 손실이 가장 적다.
     - Step 6에서 `**§lite**: true` + `**§유형**: trivial` **질문 없이 강제**(슬래시 진입=축약 승인). "축약할까요?" 제안 **하지 않음**.
     - Step 3~4(명확화 질문·2~3 접근)는 **경량화**: 블로킹 모호점만 0~2문장으로 확인하거나 명백하면 skip — **clarifying-ko·planning-ko 스킬은 호출하지 않음**.
     - Step 5 설계 제시 → ★ HARD GATE 1회(스펙+(해당 시) 화면/IF 통합 승인) (**§일괄**: 이 1회가 승인 묶음이다 — `once-approval.md` 형식으로)
     - **Step 5.5·5.6: [신규 분기]와 동일 조건·동일 의무** — UI면 화면, API/스키마면 IF. lite라도 제외 금지.
     - 승인 후 `## 다음 skill`의 **§lite/trivial 단축 경로**로 decomposing-ko 직행

   **[maintain-lite 분기]** (`/maintain-lite` — analyzing-mini 산출물 참조 + clarify·plan 축약):
     - `analyzing-ko` [lite-mini]가 남긴 `current-state.md` + `impact-analysis.md` **참조만**
     - **★ strict 승격 가드**: strict 신호면 "`/maintain`으로 진행" 안내 후 중단 (무인 표지가 있으면 중단 대신 승격 — 아래 `[무인 표지 (둘째 줄)]`)
     - Step 6: `**§유형**: 유지보수` + `**§lite**: true` 강제. acceptance-criteria **AC-R-1** 필수(DB·스키마면 AC-R-2)
     - Step 5.5·5.6: [유지보수 분기]와 동일(기존 API/스키마 수정 시 5.6 등) — **제외 금지**
     - clarifying-ko·planning-ko **호출 금지** — 승인 후 §lite 단축으로 decomposing-ko 직행

   **[무인 표지 (둘째 줄)]** (`/maintain-auto`·`/maintain-lite-auto`·`/start-lite-auto` — 위 분기 중 하나에 **겹친다**):
     - **판정**: 첫 줄이 `maintain`·`maintain-lite`·`lite` 약속어이고 **둘째 줄이 `<!-- auto: true -->`** 일 때. 슬래시가 붙인 표지만 인정한다 — 자연어로 추론하지 않는다. FID 슬러그·gbrain 조회는 주석 줄(약속어·무인 표지·승격 표지)을 뺀 나머지로 한다
     - **무인 판정은 이 표지로 한다** — Step 5.5·5.6·사용자 검토 게이트의 `[§auto 모드]` 는 spec.md 가 아직 없어도(Step 6 이전) 이 표지가 있으면 무인이다
     - **묻지 않는다**: Step 3~4 의 명확화 질문·접근 제안, intent·설계 승인(Step 5)·스펙 검토 게이트를 전부 사용자 응답 없이 지난다. 모호한 점은 best-guess 로 정하고 intent·spec 에 `(ASSUMED)` 로 적는다 — lite 계열은 뒤에 clarifying-ko 가 없으므로 **여기서 적지 않으면 어디에도 남지 않는다**
     - **라벨**: 그 분기의 라벨에 `**§auto**: true` 를 **함께** 적고, 유지보수 계열은 `**자동 결정 분석**: current-state.md · impact-analysis.md — <변경 대상·보존할 동작 1줄> (사용자 미검토)` 를 적는다(분석 검토가 자동 통과됐다는 표시)
     - **★ strict 는 중단하지 않고 승격한다** (lite 계열의 `★ strict 승격 가드` 대신): strict 신호가 보이면 풀 무인 경로로 올린다. 승격하면 **`§lite` 를 적지 않고 `§유형` 은 `신규`(`/start-lite-auto`) 또는 `유지보수`(`/maintain-lite-auto`)** 로 적는다 — `trivial` 로 적으면 trivial 단축 경로가 clarify·plan 을 다시 건너뛰고, `§lite` 가 없어 `LITE-STRICT-GUARD` 도 걸리지 않는다. spec §1 에 `**자동 승격**: lite → 풀 경로 (<신호>)` 를 적고, 다음 skill 은 정상 경로(`clarifying-ko`)다
     - **analyzing 이 이미 승격한 경우**: args 셋째 줄이 `<!-- promoted: lite -->` 면(analyzing-ko 가 mini 대신 풀 분석을 돌렸다) [유지보수 분기]로 진행하되 spec §1 에 같은 `**자동 승격**` 줄을 적는다 — 이 줄이 없으면 승격이 PR 게이트 다이제스트에서 빠진다

1.5. **Intent 캡처 (spec 이전)** — 요청을 요청자의 말로 옮긴 `.specops/<FID>/intent.md` 를 먼저 남긴다. 5절: 문제(요청 원문 인용) · 기대 결과 · 영향 사용자·시스템 · 제약 · 열린 질문(IQ-n · 없으면 `- 없음`). 템플릿 `templates/intent.md`. **판정 SoT = `scripts/_internal/check-intent.sh`** (구현 직전 emit-context 가 존재·채움 재검 — 도입 전 FID·비날짜 FID 는 SKIP). 승인된 intent 는 **커밋해 공유한다**(PR 에서 보이고 git 이력이 감사 추적이 된다): `git check-ignore -q .specops/<FID>/intent.md` 가 rc 1(추적 대상)일 때만 `git add .specops/<FID>/intent.md` → 별도 호출로 `git commit -m "docs(intent): <FID>"`. 무시되는 프로젝트(구 `.specops/.gitignore`)는 건너뛴다.

   | 분기 | 내용 | 게이트 |
   |---|---|---|
   | 신규 · foundation | 5절 전체 | ★ 독립 HARD GATE — "intent 초안이 의도와 맞습니까? [y/수정]" · 승인 시 `Status: accepted` |
   | 유지보수 · maintain-lite | 문제는 요청 + `current-state.md` §4·§5 | Step 5 설계 제시에 intent 동봉 → **설계 승인과 통합**(게이트 1회) |
   | lite | 5절 각 1~2줄 | 설계 승인과 통합 |
   | batch | **FR 행** + PRD §1·§3 에서 도출 · `Status: draft` | per-FR 게이트 없음 → `/start-all` Phase 2.5-E 일괄 확인 |
   | auto (무인 표지 포함) | 추정 항목에 `(ASSUMED)` · spec §1 에 `**자동 결정 intent**` 1줄 | 자동 통과(PR 게이트 다이제스트로 집계) |
   | §일괄 (기본 · 신규·유지보수·lite) | 분기별 내용 그대로 | 독립 게이트·설계 승인 통합 없음 → 승인 묶음에 싣는다(`once-approval.md`) · 승인되면 `Status: accepted` |

2. **Visual Companion 제안** (시각 질문이 예상되면) — 자체 메시지로만. 명확화 질문과 섞지 말 것. 아래 Visual Companion 섹션 참조
3. **명확화 질문** — 한 번에 하나, 목적·제약·성공 기준 이해 (**lite·maintain-lite**: 위 분기 경량 규칙 — clarifying-ko 미호출) · **§일괄**: 질문을 한 번에 묶어 1회(많아야 4개 — `once-approval.md`)
4. **2~3 접근 제안** — 트레이드오프와 권고 제시 (**lite·maintain-lite**: 생략 가능) · **§일괄**: 고르게 하지 않고 추천안으로 설계하고 버린 대안을 승인 묶음에 싣는다
5. **설계 제시** — 섹션을 복잡도에 맞춰 스케일, 각 섹션 후 사용자 승인 확인 (**§일괄**: 섹션별 승인 없이 승인 묶음에 싣는다)
5.5. **[UI 기능인 경우] 인라인 화면 설계** — 설계 승인 직후 실행:

   > lifecycle 밖에서 개별/일괄 화면을 따로 손보려면 `/design-screen`(단수)·`/design-screens`(복수). 본 Step 5.5 는 lifecycle 내 자동 처리다.

   **[batch 분기]**: 본 Step **SKIP**. `/start-all` Phase 2.5-A가 전 FR 화면을 **1회 통합** 설계한다 — 여기서 `screens/*`를 만들거나 승인 루프를 돌리지 않는다. UI면 Step 6 §참조에 예정 화면 이름만 기재. Step 5.6도 SKIP이므로 **Step 6으로 진행**.

   **[foundation 분기] — 셸 전용 Step 5.5 (20260812)**: 전면 SKIP **아님**. UI 신호(FE arch / decisions UI 있음 / project-context 프론트 실값 — `foundation-kind.sh`와 동형)이면 **셸 screens만** 설계한다.
   - **allowlist 슬러그(정확 일치)**: `app-shell` · `layout` · `login` 만 생성·수정 허용. `dashboard`/`home` 등 기능 화면은 **거부** — "기능 화면은 `/start-all` Phase 2.5-A".
   - 각 셸 `.md` 제목 직후에 **의무** 마커: `<!-- foundation-shell -->`. 짝 `.html`은 동일 slug면 Phase 2.5-A baseline에 자동 포함.
   - 채움 요건·껍데기 판정은 아래 **[공통]**과 동일(필수 8섹션).
   - 권장 최소: `app-shell` 1장. UI KIND인데 셸 0장이면 **WARN** 1줄(`app-shell` 권장) 후 Step 5.6 진행(HARD 아님 — 순수 토큰/컴포넌트 foundation false-block 방지).
   - 비UI foundation → 본 Step **SKIP** → Step 5.6.
   - Phase 2.5-A는 이 셸을 기계적으로 불변 검사한다(`check-foundation-shell-baseline.sh`). 의도적 셸 변경은 `/start-foundation` 또는 `/design-screen`(셸 슬러그)만.

   **[공통 — 껍데기 판정·채움 요건]** (모드 무관 적용 · batch 제외 · foundation 셸에는 적용):
   - 화면 파일이 **이미 있으면** 먼저 판정한다:
     `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/design-screen.sh --check screens/{name}.md screens/{name}.html`
     - exit 1(정상) → 재사용. 재생성 금지 (false-trigger 방지). 단 `<미확정 — 근거 필요>` 중 이번 기능이 확정하는 것은 **그 마커만** 채운다(init 보강분).
     - exit 0(껍데기) → 재사용 금지. 아래 생성 루프를 그대로 진행해 덮어쓴다.
   - **`.md` 채움 요건**: `screens/{name}.md` 는 **필수 8섹션**(목적 · Layout · Components · States · Interactions · 필드 정의표 · 데이터 소스 · 에러 메시지)을 실제 내용으로 완성한다. 조건부 4섹션(RBAC 권한별 표시 · 반응형 브레이크포인트 · 접근성 · 진입/이탈 경로)은 **해당할 때만** 넣는다 — 미해당 섹션을 `—` 로 채우지 않는다. (`/design-screen(s)` 와 동일 요건 — lifecycle 안/밖 비대칭 해소)
   - **DESIGN.md 준수**: 화면 작성 시 `DESIGN.md` **§2 타이포·§3 간격** · §6 레이아웃 패턴 · §6.1 화면 원형 · §7 상태 표현 · §8 원칙/안티패턴 · §9 AI 지침을 읽고 따른다 (DESIGN.md 부재 시 skip).
   - **입력 접근성**: 입력(input·select·textarea)마다 label 의 for 속성과 입력 id 를 같은 값으로 짝지어 연결한다(label 이 입력을 감싸거나 aria-label 도 허용 — for 없이 형제로만 둔 label 은 연결이 아니다). 라디오·체크박스는 선택지마다 자기 label 을 두고 그룹 이름은 fieldset 과 legend 로 둔다. 템플릿 html 의 주석 속 입력 예시를 복사해 쓴다.
   - **저장 시 껍데기 마커 줄을 삭제**한다 (`.md`·`.html` 양쪽). 마커가 남으면 verify backstop 이 껍데기로 경고한다.

   **[§auto 모드]** (`grep -qE '^\*\*§auto\*\*:[[:space:]]*true' .specops/<FID>/spec.md`):
   - 화면 목록을 자동 판단하여 **즉시 생성·수락** (수정 루프 없음):
     1. `templates/screen.html` + 현재 spec 맥락 기반으로 HTML artifact 즉시 생성
     2. **자동 수락** — 사용자 응답 대기 없이 `screens/{name}.md` + `screens/{name}.html` 저장
     3. spec.md §1에 "**자동 결정 화면**: {name1}, {name2}, ..." 한 줄 기록 (투명성·PR 게이트 가정 다이제스트 용)
   - 모든 화면 저장 완료 후 **Step 5.6 진행** (인터페이스 설계도 거친다 — Step 6 직행 금지)

   **[§auto 이외 모드]** (기존 동작):
   - **§일괄 이면 화면을 모두 만든 뒤** 경로 목록만 승인 묶음에 싣는다 — 아래 2(보여 주고 수정 요청 수렴)·3(승인)을 화면마다 하지 않고 1 로 만든 화면을 바로 저장한다. 수정 요청은 승인 묶음에서 받는다.
   - 이 기능에 필요한 화면 목록을 자동 판단하여 명시:
     > "이 기능에 필요한 화면은 N개입니다: {name1}({설명}), {name2}({설명}) ..."
   - **[design system]**: 프로젝트 `DESIGN.md` 가 화면 스타일의 유일한 출처다 — 각 화면 생성 시 [공통] 의 DESIGN.md 준수 지시를 따른다(부재 시 `templates/screen.html` 기본 토큰).
   - 각 화면을 순서대로 설계:
     1. `templates/screen.html` + 현재 spec 맥락 기반으로 HTML artifact 즉시 생성 (별도 질문 없이)
     2. 사용자에게 보여주고 수정 요청 수렴 → 수정 요청 시 재생성 루프
     3. 승인 → `screens/{name}.md` + `screens/{name}.html` 저장 (`mkdir -p screens` 선행)
   - 모든 화면 완료 후 Step 5.6 진행
5.6. **[API/스키마 기능인 경우] 인라인 인터페이스 설계** — 설계 승인 직후 실행 (화면 Step 5.5 와 **대칭** — 인터페이스도 design-first):

   > **적용 조건**: 이번 기능이 **API 엔드포인트**(제공) · **DB 스키마**(테이블·필드) · **클라이언트 영속 데이터**(localStorage·IndexedDB) 중 하나를 신설·변경한다. 순수 UI·CLI 로직만이면 본 스텝 skip.
   > **대상 산출물**: `.specops/memory/api-spec.md`(IF 설계서) · `.specops/memory/data-model.md`(테이블 설계서) — 영향받는 것만. 화면이 `screens/`(화면별 파일)을 생성하듯, 인터페이스는 이 **마스터 문서의 해당 섹션을 갱신**한다.
   > **원칙**: 구현이 이 설계를 따른다(design-first). 구현 중 불가피하게 벗어나면 `verifying-evidence-ko` 의 "memory 설계 동기화 점검"(역방향 안전망)이 사후 감지한다.
   > lifecycle 밖에서 개별/일괄 인터페이스를 따로 손보려면 `/design-interface`(단수)·`/design-interfaces`(복수). 본 Step 5.6 은 lifecycle 내 자동 처리다. (분업 기준: `commands/design-interface.md` §인터페이스 설계 경로 분업)

   **[batch 분기]**: 본 Step **SKIP**. `/start-all` Phase 2.5-B가 전 FR 인터페이스를 **화면 설계(A) 직후** 1회 통합한다 — 여기서 api-spec/data-model을 갱신하지 않는다. API/스키마면 Step 6 §참조에 예정 엔드포인트·테이블 이름만 기재 후 **Step 6으로 진행**.

   **[foundation 분기] — baseline 마커 의무 (20260812)**: 공통 테이블·공통 API(라우팅·auth·health·베이스 스키마 등)를 `api-spec.md`·`data-model.md`에 쓸 때 **반드시** 아래 마커 안에 둔다. Phase 2.5-B 는 이 구간을 기계적으로 불변 검사한다(`check-foundation-if-baseline.sh`).
   ```html
   <!-- foundation-baseline:start -->
   … 공통 엔드포인트 행 / 공통 엔티티 …
   <!-- foundation-baseline:end -->
   ```
   - 마커 **밖**에 FR 전용 엔티티를 foundation이 쓰지 않는다(공통부 범위).
   - 공통 IF를 실제로 안 건드린 foundation(순수 모듈·프론트 셸만)은 마커 0 허용 → 이후 Phase 2.5 검사는 SKIP.
   - 의도적 baseline 변경은 batch가 아니라 `/start-foundation` 또는 `/design-interface`로만.

   **[§auto 모드]** (`grep -qE '^\*\*§auto\*\*:[[:space:]]*true' .specops/<FID>/spec.md`):
   - **부재 가드**: `api-spec.md`·`data-model.md` 가 없으면(KIND 1/3/5 init 또는 8f skip) 무인 모드는 **마스터 문서를 신규 생성하지 않는다** (안전 — 무인이 cross-feature 전역 문서를 임의 생성 금지). spec.md §1 에 "**인터페이스 미반영**: memory 부재" 한 줄 기록 후 Step 6 진행.
   - **클라이언트 스토리지 도출**: 화면 영속화 Interaction(FR-9 류) → `data-model.md` 엔티티 자동 append (존재 시). 부재 시 무인은 신규 생성 안 함(기존 부재 가드 계승)
   - 존재 시 — 이번 기능이 추가·변경하는 엔드포인트/테이블을 자동 판단해 **append**(섹션 **덮어쓰기 금지** — `/start-all-auto` batch 의 다수 기능이 같은 마스터 문서를 순차 기록할 때 충돌·오염 방지):
     1. `api-spec.md` 의 **채택된 정의방식 섹션**(§1 표 또는 OpenAPI/GraphQL/RPC 중 선택분)에 신규 행 **추가** (동일 메서드+경로/테이블 행이 이미 있으면 신규 추가 대신 **해당 행 갱신** — 중복 행 금지)
     2. `data-model.md` §3(핵심 엔티티)·§2(ERD)에 신규 테이블/필드 **추가**
     3. spec.md §1 에 "**자동 결정 인터페이스**: {엔드포인트/테이블 요약}" 한 줄 기록 (투명성·PR 게이트 가정 다이제스트 용)
   - 반영 완료 후 Step 6 진행

   **[§auto 이외 모드]**:
   - **§일괄 이면 바꾸는 인터페이스를** 명시하고 확인을 묻지 않은 채 아래대로 memory 문서를 갱신한다 — 바꾼 행은 승인 묶음에 싣는다. memory 문서가 없어 생성 여부를 물어야 하는 경우와 계약 칸 점검 `WARN` 도 승인 묶음에 싣는다.
   - 이번 기능이 건드리는 인터페이스/스키마를 명시:
     > "이 기능은 다음 인터페이스를 추가/변경합니다: {POST /orders — 주문 생성}, {orders 테이블 — id·user_id·status ...}"
   - 사용자 확인 후 해당 memory 문서 섹션을 **구현 전에 먼저 갱신**:
     - `api-spec.md`: **채택된 정의방식 섹션**(§1 Markdown 표 또는 §2 OpenAPI/§3 GraphQL/§4 RPC 중 init 8f 에서 선택·보존된 것)에 엔드포인트·요청/응답 스키마·인증 반영 (동일 메서드+경로/테이블 행이 이미 있으면 신규 추가 대신 **해당 행 갱신** — 중복 행 금지)
     - `data-model.md`: §3 엔티티 표·§2 ERD·§4 인덱스 반영
     - **클라이언트 스토리지**(localStorage·IndexedDB): `data-model.md` §1 유형=해당 스토리지(localStorage/IndexedDB)로 §3 엔티티·저장 키 반영 (기존 서버 DB 유형이 있으면 §1 에 `+` 복수 표기 — 덮어쓰기 금지) (HTTP api-spec 아님). 부재 시 생성 확인
   - memory 문서가 **부재**하면(예: UI-only 로 init 되어 api-spec 미생성) → 생성 여부를 사용자에게 확인 (제공 API 인지 외부 소비 인지 구분 — 제공이면 `templates/api-spec.md`, 외부 소비면 `templates/api-spec-consumer.md` 기반 생성)
   - 반영 완료 후 Step 6 진행
   **[계약 칸 점검 — 두 모드 공통 · 경고 전용 (20261021)]**: `api-spec.md` 를 고쳤으면 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-api-contract.sh <FID>` 를 한 번 실행한다(바꾼 행만 · Status 열·오류 형식·오류 코드·목록 정책·멱등 정책·rate limit·버전 전략). `WARN` 줄이 있으면 대화형은 사용자에게 보여 주고 지금 채울지 묻는다 · §auto 는 채울 수 있는 칸만 채우고 나머지는 spec.md §1 "자동 결정 인터페이스" 줄 뒤에 남긴다. 막지 않는다 — 종료 코드와 무관하게 Step 6 진행(같은 판정을 검증 러너가 evidence.md `### api-contract` 에 다시 남긴다). **보안 칸**: `api-spec.md` 또는 `data-model.md` 를 고쳤으면 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-security-design.sh <FID>` 를 한 번 실행한다(바꾼 행의 Auth 칸·URL 민감정보·응답 민감 필드 · 인증 방식·권한 모델·CORS·CSRF·개인정보 분류·보존·삭제 칸 · 위험 기능 결정) — `WARN` 은 위와 같이 다루고, 이것도 막지 않는다(같은 판정을 검증 러너가 evidence.md `### security-design` 에 다시 남긴다).
6. **설계 문서 작성** — `.specops/<FID>/spec.md` + `acceptance-criteria.md`로 저장하고 커밋
   - **AC 필수 필드 (기계 검증)** — AC 블록마다 `### AC-<n>: <제목>` 헤더 + **Given·When·Then·우선순위** 를 반드시 채운다. `**우선순위**` 값은 `must`·`should`·`nice-to-have` 중 하나. 판정 SoT = `scripts/_internal/check-ac-format.sh` (구현 직전 `emit-context.sh` 가 자동 호출 — 미충족 시 dispatch 가 열리지 않는다). **`**우선순위**` 는 서식이 아니라 스위치다** — 없으면 `emit-context` 의 must AC 역방향 커버리지 검사가 그 AC 를 보지 못해, 필수 AC 가 태스크 매핑 없이 통과하고 영영 구현되지 않는다. 쓰지 않는 템플릿 골격 AC(`<...>`·`...`)는 **남기지 말고 삭제**한다(골격 잔존도 차단 대상).
   - **AC 개수 상한 (should — 하드 게이트가 아니다)** — 코드 변경이 **50줄 미만이면 AC 6건**을 넘기지 않는 것을 권고한다. 넘어간다면 **계약이 아니라 설명을 쓰고 있는지** 의심하라. AC 가 늘면 plan·tasks·리뷰 대상이 함께 늘어 **비용이 곱으로 번진다** (실측 20260808: 코드 **18줄** 변경에 AC **12건** → plan 558줄·tasks 468줄·plan-reviewer 2회 dispatch). `check-ac-format.sh` 는 개수를 **검사하지 않는다** — 계약이 진짜로 필요하면 6건을 넘겨도 된다. 이 상한은 **되묻는 장치**지 금지가 아니다. (반대 방향 주의: 상한을 지키려고 **must AC 를 빠뜨리면** `emit-context` 의 역방향 커버리지가 막는다 — 줄일 것은 AC 개수가 아니라 **설명으로 쓴 AC** 다.)
   - **Intent 추적**: spec §1 에 `**Intent**: .specops/<FID>/intent.md` 를 적고, §1 목적·성공 판정을 intent 의 문제·기대 결과에서 도출한다
   - **§일괄 라벨**: Step 1 의 §일괄 판정이 참이면 spec §1 의 `**§유형**` 줄 다음에 `**§일괄**: true` 를 적는다(`--step`·무인·batch·foundation 은 적지 않는다).
   - **열린 질문 처리**: intent 의 IQ 를 spec §8 에 `IQ-n → 답변(§섹션)` 또는 `IQ-n → 이월(Qn)` 로 적는다(IQ 가 없었으면 "해당 없음")
   - UI 기능이면 §참조에 `screens/{name}.md` 목록 자동 포함
   - API/스키마 기능이면 §참조에 `.specops/memory/api-spec.md`·`data-model.md` 자동 포함 (Step 5.6 갱신분)
   - **§유형 라벨 자동 기재** (Phase A — 신규 추가): spec.md §1 개요 의 `**§유형**` 라벨을 다음 규칙으로 자동 부여 — 진입 신호 + current-state.md §1 라인 범위 메타 합산 기반:

     | 진입 신호 | current-state.md §1 라인 범위 합산 / 예상 산출 규모 | 라벨 |
     |---|---|---|
     | **lite 분기** (`/start-lite`) | N/A (슬래시=축약 승인) | `**§유형**: trivial` + `**§lite**: true` (**질문 없이 강제**) |
     | **maintain-lite 분기** | N/A | `**§유형**: 유지보수` + `**§lite**: true` + AC-R-1 강제 |
     | 신규 분기 (소규모 + 사용자 trivial 승인) | 예상 산출 ≤ 1 파일·소규모 (수 라인) | `**§유형**: trivial` (신규 단축 경로 — 아래 ★ 참조) |
     | 신규 분기 (기본) | 위 조건 미충족 | `**§유형**: 신규` |
     | foundation 분기 | N/A | `**§유형**: foundation` (**`§batch` 기재 금지** — hybrid HARD) |
     | 유지보수 분기 | ≤ 5 | `**§유형**: trivial` (사용자가 자기선언으로 거부 가능) |
     | 유지보수 분기 | > 5 또는 미산출 | `**§유형**: 유지보수` |
     | batch 분기 | N/A | `**§유형**: 신규` + `**§batch**: <batch-id>` (**`§유형=foundation` 금지** — hybrid HARD) |

     **★ hybrid 금지 (20260812)**: `§유형=foundation` 과 `§batch` 를 **같은 spec.md 에 쓰지 않는다**. 공통부는 `/start-foundation`(foundation only), 기능은 `/start-all` batch(`신규`+`§batch`). 겹치면 `check-spec-label-compat.sh` 가 emit-context·verify 에서 FAIL.

     **근거**: clarify Q-B 결정 — trivial 자동 판정 시점은 analyzing-ko current-state.md §1 메타 사전 추정. Phase A 단독 시점에는 specifying-ko Step 1 mini-checklist §1 라인 범위 메타로 대체. 라벨은 clarifying-ko 단계에서 갱신 가능.

     **★ 신규 trivial 단축 경로 (완주율 개선 — 20260714-trivial-new-shortcut)**: 신규 분기에서 설계 승인 직후, 예상 산출이 **단일 파일·소규모(수 라인)** 라 판단되면 사용자에게 **명시적으로** 제안한다 — "이 작업은 소규모라 clarify·plan 단계를 생략(specify → decompose → implement → verify)할 수 있습니다. 축약할까요?". **사용자가 승인해야만** `§유형: trivial` 부여 (자기선언 우선 — 오분류 안전판). 이 경로는 **clarify·plan ceremony 만** 건너뛴다 — decompose·implement·**verify/TDD/security teeth 는 그대로 유지**되므로 오분류돼도 검증 게이트가 안전망이다. `batch`·`foundation` 분기는 이 축약 대상이 아니다 (요구 규모가 본질적으로 크므로).

     **★ lite / maintain-lite**: `/start-lite`·`/maintain-lite` 슬래시가 곧 축약 승인이다 — "축약할까요?"를 **묻지 않는다**. `**§lite**: true`를 반드시 기재. 화면(5.5)·IF(5.6)는 해당 시 **풀 `/start`/`/maintain`과 동일** (제외 금지). Phase B/C·verify 생략 금지.

     라벨이 `유지보수` 면 acceptance-criteria.md 의 "## 회귀 방지 AC (유지보수 FID 필수)" 섹션이 자동 활성 — sprint-contracts-ko evaluator 가 `AC-R-*` ≥ 1 강제.

   - **성공지표 작성 유도 (권장 — should)**: §유형이 `trivial`이 아니면 spec.md §1 개요 하위 `### 성공지표` 서브섹션에 measurable target을 작성한다(정량 우선, 불가 시 정성+검증방법). **권장 — 미작성이 evaluator FAIL은 아니나**, 기능 가치 입증·learning-loop 추적을 위해 작성 강력 권고. trivial FID는 면제.
6.5. **[데이터를 다루는 spec] 요구사항 전문가 패스** — spec.md·AC 를 저장한 직후, 자체 검토(7) 전에 부른다. spec 이 입력 데이터를 받아 저장·계산·판정하거나 외부 소스·배치를 다루면 발동한다. 화면 문구·설정·문서만 바꾸는 spec 은 부르지 않는다. 판단이 서지 않으면 부른다(측정: 데이터 규칙 빈칸 결함을 plan-reviewer 0/6 · 이 전문가 6/6 · 결함 없는 대조군 헛지적 0/3).
   - **제외**: `§batch` · `§lite`(`/start-lite`·`/maintain-lite`) · `§유형: trivial` · promote(`promote-fid`) · foundation 은 부르지 않는다(기록 행도 남기지 않는다). 유지보수 분기와 `§auto` 는 부른다.
   - **dispatch**: `Agent` 도구, `subagent_type: "specops-ko:req-designer-ko"` · 입력은 경로만 — `.specops/<FID>/spec.md` · `acceptance-criteria.md` · `intent.md` · `.specops/memory/requirements.md`·`data-model.md`·`api-spec.md`(있으면).
   - **반영**: `.specops/<FID>/experts/req.md` 의 지적은 spec·AC 에 반영하거나 기각하고 같은 파일 끝 `## 반영` 에 `반영(spec §/AC-N)` 또는 `기각(근거)` 1줄씩 적는다. `## 확인 필요` 질문은 spec §8 열린 질문으로 옮긴다(clarifying-ko 가 사용자에게 묻는다). `§auto` 면 질문을 best-guess 로 정해 §8 에 `(ASSUMED)` 로 남긴다.
   - **모델 불가·산출 없음**: opus 를 쓸 수 없으면 같은 에이전트를 가용 모델 override 로 다시 dispatch 한다(부모가 대신 검토하지 않는다). `experts/req.md` 가 없으면 1회 다시 부르고, 그래도 없으면 dispatch-log 에 `| <N> | <ISO-8601> | req-expert | req-designer-ko | 산출 없음 | - |` 를 남기고 7 로 진행한다.
   - **기록** (결과 칸에 `DONE`·`IMPL` 을 쓰지 않는다 — 재개 판독기가 구현 증거로 읽는다): dispatch-log 에 `| <N> | <ISO-8601> | req-expert | req-designer-ko | 반영 | experts/req.md (지적 N · 반영 N · 기각 N · 질문 N) |`. 발동하지 않으면 `| <N> | <ISO-8601> | req-expert | - | SKIP | 데이터 표면 없음 |` 1행.
6.6. **[기능 화면을 만들거나 고친 FID] 화면 전문가 패스** — 6.5 뒤, 자체 검토(7) 전에 부른다. 이번 FID 가 Step 5.5 에서 기능 화면 `screens/<name>.md` 를 만들거나 고쳤으면 발동한다(측정: 화면 상태 빈칸 결함을 design-reviewer 5/6 · 이 전문가 6/6 · 결함 없는 대조군 헛지적 0/3). spec·AC 가 있어야 하므로 화면 설계(5.5) 직후가 아니라 여기서 부른다.
   - **제외**: `§batch`(`/start-all` Phase 2.5 A2 가 batch 당 1회 맡는다) · `§lite`(`/start-lite`·`/maintain-lite`) · `§유형: trivial` · foundation 셸 화면(`<!-- foundation-shell -->`)만 바꾼 경우는 부르지 않는다(기록 행도 남기지 않는다). 화면 변경이 없으면 부르지 않고 SKIP 행을 남긴다. 유지보수 분기와 `§auto` 는 부른다.
   - **dispatch**: `Agent` 도구, `subagent_type: "specops-ko:ui-designer-ko"` · 입력은 경로만 — 이번에 만든·고친 `screens/<name>.md`·`.html` · `.specops/<FID>/spec.md` · `acceptance-criteria.md` · `DESIGN.md`(있으면).
   - **반영**: `.specops/<FID>/experts/ui.md` 의 지적은 화면 파일에 반영하거나 기각하고 같은 파일 끝 `## 반영` 에 `반영(screens/<name>.md §)` 또는 `기각(근거)` 1줄씩 적는다. `## 확인 필요` 질문은 spec §8 열린 질문으로 옮긴다(clarifying-ko 가 사용자에게 묻는다). `§auto` 면 질문을 best-guess 로 정해 §8 에 `(ASSUMED)` 로 남긴다. 사용자 검토(8)에서 바뀐 화면 행을 함께 보여 준다.
   - **모델 불가·산출 없음**: opus 를 쓸 수 없으면 같은 에이전트를 가용 모델 override 로 다시 dispatch 한다(부모가 대신 검토하지 않는다). `experts/ui.md` 가 없으면 1회 다시 부르고, 그래도 없으면 dispatch-log 에 `| <N> | <ISO-8601> | ui-expert | ui-designer-ko | 산출 없음 | - |` 를 남기고 7 로 진행한다.
   - **기록** (결과 칸에 `DONE`·`IMPL` 을 쓰지 않는다 — 재개 판독기가 구현 증거로 읽는다): dispatch-log 에 `| <N> | <ISO-8601> | ui-expert | ui-designer-ko | 반영 | experts/ui.md (지적 N · 반영 N · 기각 N · 질문 N) |`. 화면 변경이 없으면 `| <N> | <ISO-8601> | ui-expert | - | SKIP | 화면 변경 없음 |` 1행.
7. **스펙 자체 검토** — 플레이스홀더·모순·모호성·범위 인라인 점검 (아래 참조)
8. **사용자 스펙 검토** — 파일 검토를 사용자에게 요청, 승인 대기 (**§일괄**: `### 사용자 검토 게이트` 의 [§일괄 모드])
9. **session-progress append** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /specify 완료 "spec.md, AC.md" "<기능명>"` (첫 진입이라 신규 FID 섹션 생성)
10. **구현으로 전환** — `specops-ko:clarifying-ko` 스킬 호출

## 프로세스 흐름

```
프로젝트 맥락 탐색
    ↓
args 첫 줄 = "<!-- entry: maintain-lite -->"? ── yes ──▶ [maintain-lite] analyzing-mini 참조 · §lite+유지보수 · 5.5/5.6 유지 · clarify/plan skip → decomposing
    │
    └── no ──▶ "<!-- entry: maintain -->"? ── yes ──▶ [유지보수 분기] … → Step 3
                    │
                    └── no ──▶ "<!-- entry: lite -->"? ── yes ──▶ [lite] §lite+trivial 강제 · 5.5/5.6 유지 · clarify/plan skip → decomposing
                                    │
                                    └── no ──▶ "<!-- entry: foundation -->"? ── yes ──▶ **[foundation 분기]** …
                                                    │
                                                    └── no ──▶ "<!-- entry: batch -->"? ── yes ──▶ **[batch 분기]** …
                                                                    │
                                                                    └── no ──▶ [신규 분기] ↓
    ↓
DESIGN.md 존재? ── yes ──▶ spec.md §참조에 "DESIGN.md 디자인 시스템 준수" 포함
    │                              ↓
    └── no (UI 기능이면 /init-project 안내 — Phase 6 에서 DESIGN.md 생성)
    ↓
screens/ 존재? ── yes ──▶ 기존 화면 목록 표시 (참고용)
    │
    └── no
    ↓
시각 질문 예상? ── yes ──▶ Visual Companion 제안 (단독 메시지)
    │                              ↓
    └── no ──▶ 명확화 질문 (한 번에 하나) ◀───┘
                  ↓
              2~3 접근 제안 + 추천
                  ↓
              설계 섹션 제시 ── 사용자 승인?
                  ↑                │
                  └── no, 수정     │ yes
                                   ↓
                         UI 기능? ── yes ──▶ 필요 화면 목록 자동 판단
                              │                      ↓
                              │              HTML artifact 생성 ── 수정 요청?
                              │                      ↑                  │ no
                              │                      └──────────────────┘
                              │                           승인
                              │                      ↓
                              │              screens/{name}.md + .html 저장
                              │                      ↓
                              │              화면 더 있음? ── yes ──▶ 다음 화면
                              │                      │ no
                              └── no ────────────────┘
                                   ↓
                          API/스키마 기능? ── yes ──▶ api-spec/data-model design-first 갱신 (Step 5.6)
                                   │                          ↓
                                   └── no ─────────────────────┘
                                   ↓
                              설계 문서 작성 (spec.md — §참조에 screens/ + api-spec/data-model 포함)
                                   ↓
                              데이터를 다루는 spec? ── yes ──▶ 요구사항 전문가 패스 (Step 6.5)
                                   ↓
                              화면을 만들거나 고쳤나? ── yes ──▶ 화면 전문가 패스 (Step 6.6)
                                   ↓
                              스펙 자체 검토 (인라인 수정)
                                   ↓
                              사용자 스펙 검토 ── 변경 요청?
                                   │              ↑
                                   │ 승인         │
                                   ↓              │
                              specops-ko:clarifying-ko 호출
```

**종착점은 `specops-ko:clarifying-ko` 호출이다.** 본 스킬은 프론트엔드 설계 스킬이나 MCP 빌더 등 어떤 구현 스킬도 호출하지 않는다. specifying 이후 유일한 스킬은 **clarifying-ko**이다.

## 프로세스 세부

### 아이디어 이해

- **현재 프로젝트 상태 먼저** — 파일·문서·최근 커밋
- 세부 질문 전에 **규모 점검**: 요청이 여러 독립 서브시스템(예: "채팅+파일스토리지+결제+분석")을 담으면 **즉시 표시**. 분해 필요한 프로젝트에 세부 질문하지 말 것
- 프로젝트가 단일 스펙으로 너무 크면, 서브 프로젝트로 분해 돕기: 독립 조각은 무엇인가, 어떻게 연결되는가, 어떤 순서로 만들 것인가. 그 뒤 첫 서브 프로젝트를 정상 설계 흐름으로. 각 서브 프로젝트는 자체 spec → plan → implementation 사이클
- 적절한 규모면 질문을 하나씩 refine
- **객관식이 가능하면 객관식**. 열린 질문도 OK
- **한 메시지당 한 질문** — 한 주제에 탐색이 더 필요하면 여러 질문으로 쪼갠다
- 목적·제약·성공 기준에 집중
- **질문 상한**: 명확화 질문은 **최대 4 회 (Q1~Q4)** 까지 수집한 뒤 설계 초안을 제시한다. Q5 이상 추가 명확화가 필요하다고 판단되면 **그 질문을 spec.md §8(열린 질문)에 기재**해 `specops-ko:clarifying-ko` 로 위임 — 본 skill 의 책임은 "구현 가능한 최소 초안" 까지 (FRICTION-LOG F-15). §8 기재가 곧 위임 메커니즘이다 — clarifying-ko 는 §8 카운트로 BLOCKING 존재 여부(경량/풀 모드)를 판정하므로(clarifying-ko L54), 구두 언급만으로는 위임이 성립하지 않는다.

### 접근 탐색

- 2~3 접근을 **트레이드오프와 함께** 제시
- 대화체로, 추천 옵션을 **먼저** 제시하며 이유 설명
- 권고를 앞세우되 대안도 함께

### 설계 제시

- 이해했다고 판단되면 설계 제시
- 각 섹션을 복잡도에 맞게 스케일 (단순하면 몇 문장, 미묘하면 200~300 단어)
- **각 섹션 후** 맞는지 확인
- 아키텍처·컴포넌트·데이터 흐름·에러 처리·테스트를 다룸
- 말이 안 되면 되돌아가 명확화

### 격리와 명확성을 위한 설계

- 시스템을 더 작은 단위로 분해 — 하나의 명확한 목적, 잘 정의된 인터페이스, 독립 이해·테스트 가능
- 각 단위는 답할 수 있어야 함: 무엇을 하는가, 어떻게 쓰는가, 무엇에 의존하는가
- 내부를 읽지 않고 단위의 역할을 이해할 수 있는가? 내부 변경이 소비자를 깨지 않는가? 아니면 경계 재설계
- 작고 잘 구획된 단위는 당신(Claude)에게도 유리 — 한 번에 컨텍스트에 담을 수 있는 코드일수록 추론이 정확하고 편집이 안정적. 파일이 커지는 건 **너무 많은 일**을 하고 있다는 신호

### DAG 의도 추출 (v0.4b 신규)

설계 제시 단계에서 **반드시** 컴포넌트 간 의존 구조를 판단하고 spec.md §2 포함 항목에 명시:

**PARALLEL 신호** — 독립 컴포넌트 2개 이상:
- "A, B, C 각각 독립된 도구/파일/모듈"
- "서로 의존성 없음", "각각 독립", "3개 독립"
- 여러 도구가 공유 상태 없이 동등한 위치
- → spec.md §2 포함에 `(독립 — 병렬 구현 가능)` 표기

**CHAIN 신호** — 단계적 의존:
- "양방향", "파이프라인", "A → B → C 순서"
- 후속 단계가 전 단계 산출물을 입력으로 사용
- → spec.md §2 포함에 `(의존: <선행 컴포넌트>)` 표기

**표기 예시**:
```markdown
## 2. 범위
### 포함
- b64enc: Base64 인코더 (독립 — 병렬 구현 가능)
- b64dec: Base64 디코더 (독립 — 병렬 구현 가능)
- b64val: Base64 검증기 (독립 — 병렬 구현 가능)
- 통합 검증 (의존: b64enc, b64dec, b64val)
```

이 표기는 decomposing-ko가 DAG leaf를 자동 인식하는 데 사용된다. **모호하면 PARALLEL보다 CHAIN을 택하고 clarifying-ko에서 확인.**

### 기존 코드베이스 작업

- 변경 제안 전 현재 구조 탐색. **기존 패턴 따름**
- 기존 코드에 작업과 관련된 문제가 있다면(너무 커진 파일, 불분명한 경계, 얽힌 책임) 설계의 일부로 **타겟팅된 개선** 포함 — 좋은 개발자가 작업 중인 코드를 개선하듯이
- 관련 없는 리팩터링은 금지. 현재 목표에 집중

### NFR 작성 규약

spec §NFR 의 호환성 항목 (`bash 4+`, `Python 3.10+`, `Node.js 18+` 등) 은 **실측 최저 버전 우선 기재**. 확신 없거나 검증 미완료 시 `<ver>+ (실측 미확인)` 형식으로 한계 고백 (원칙 5). 기존 아티팩트의 NFR 을 맹목 복제 금지.

예:
- ✅ `bash 3.2+ (macOS 실측 · Linux 미검증)`
- ❌ `bash 4+` (실제로 bash 3.2 에서 동작하는데 과도 기재)

**근거**: dogfood FID `20260422-csv-lines` 에서 spec NFR-2 가 `bash 4+` 로 기재됐으나 실측 bash 3.2.57 에서 9/9 PASS — 구현 자체가 bash 4+ 전용 문법 (연상배열 · `[[ ]]`) 미사용. specifying-ko 가 `wc-lines` NFR-2 를 맹목 복제한 흔적. sprint-contracts 상 spec 은 후속 단계 읽기 전용이라 재진입 전까지 수정 불가 — 작성 시점에 정확해야 함 (FRICTION-LOG F-13).

## 설계 이후 단계

### 문서화

- 검증된 설계(스펙)를 `.specops/<FID>/spec.md`로 작성
  - 사용자 선호가 있다면 그 경로 우선
- 커밋 (`git add` + 메시지 "spec: <topic>")

### 스펙 자체 검토

스펙 작성 후 새 눈으로 확인:

1. **플레이스홀더 스캔** — "TBD"·"TODO"·미완성 섹션·모호 요구. 수정
2. **내부 일관성** — 섹션 간 모순? 아키텍처가 기능과 일치?
3. **범위 점검** — 단일 구현 플랜으로 집중됐는가? 분해 필요?
4. **모호성 점검** — 두 가지로 해석될 요구? 하나 고르고 명시
5. **intent 추적** — spec 이 intent 의 문제를 푸는가 · 기대 결과가 관찰 가능한 성공 판정·AC 로 내려왔는가 · IQ 전건이 답변 또는 이월로 처리됐는가
6. **최소 범위** — 각 요구에 rung 순서로 질문: 존재 필요(YAGNI)? · 코드베이스 재사용? · stdlib? · 네이티브 기능? · 설치된 의존성? · 한 줄 가능? · 모두 아니면 최소 구현. 검증·에러·보안·접근성은 절감 대상 아님
7. **기존 동작 보존 설계** (기존 코드를 고칠 때) — 설계가 기존 변환·흐름의 **순서나 경로를 바꾸면**, 기존 경로는 그대로 두고 대상 입력만 전·후처리로 분리하는 대안을 먼저 검토한다. 순서를 바꾸는 설계는 테스트에 없는 경계 사례를 연쇄로 깬다(실측 20261008: 그 설계 하나로 수정 라운드 3회 — lite 는 plan 검토가 없어 여기가 마지막 설계 점검이다)

인라인 수정. 재검토 불필요.

### 사용자 검토 게이트

**[§auto 모드]** (`grep -qE '^\*\*§auto\*\*:[[:space:]]*true' .specops/<FID>/spec.md`):

자체 검토 완료 즉시 **자동 통과** — 사용자 응답 대기 없이 다음 단계로 간다(정상 경로는 clarifying-ko · `§lite` 는 `## 다음 skill` 의 §lite 단축 경로로 decomposing-ko). handoff/dispatch-log에 "spec auto-approved (§auto mode)" 기록.

**[trivial 게이트 통합]** (`§유형: trivial` + 신규 trivial 단축 경로 — 20260716 dogfood 관찰 A): 사용자는 직전에 **설계 승인 + trivial 축약 승인** 2회를 이미 응답했다. spec.md 가 승인된 설계와 **내용 동일**하면(자체 검토에서 신규 논점·범위 변화 없음 확인) 본 게이트를 **통합 통과** — 별도 스펙 승인 응답을 요구하지 않고 "스펙 저장 완료(설계 승인 내용과 동일) — decomposing 진행" 1줄 고지 후 진행한다. **단** spec 작성 중 설계 제시에 없던 결정·범위 변화가 생겼으면 게이트를 **유지**한다(동일 내용일 때만 통합 — 주권 불변). trivial 4연속 게이트(포맷Q·설계승인·축약승인·스펙승인)의 마지막 중복 1개를 제거해 단축 경로의 완주율 이득을 보전한다.

**[§일괄 모드]** (`grep -qE '^\*\*§일괄\*\*:[[:space:]]*true' .specops/<FID>/spec.md`): `§lite` 또는 `§유형: trivial` 단축 경로면 여기서 `once-approval.md` 의 승인 묶음을 제시하고, 승인되면 그 문서의 기록을 남긴 뒤 `## 다음 skill` 의 단축 경로로 간다. 정상 경로는 묻지 않고 clarifying-ko 를 호출한다 — 승인 묶음은 clarifying-ko 끝에서 받는다. 아래 기존 동작은 `--step`(`<!-- step: true -->`)일 때만 적용한다. 위 trivial 통합 규칙(설계 승인 + 축약 승인 2회 전제)은 `§일괄` 에 적용하지 않는다 — 이 문단이 대신한다.

**[§auto·trivial 이외 모드]** (기존 동작):

자체 검토 후 사용자에게:

> "스펙을 `.specops/<FID>/spec.md`에 작성했습니다. 검토 후 변경 사항을 말씀해 주세요. 진행해도 되면 `specops-ko:clarifying-ko` 스킬을 호출해 다음 단계(명확화)로 진행하겠습니다."

**응답 대기**. 변경 요청 시 수정하고 자체 검토 루프 재실행. 승인 후에만 진행.

## 5원칙 주입 (specops-ko 고유)

질문·제안·설계 제시·문서화 중 다음 원칙을 항상 적용:

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 추천의 **근거**를 템플릿으로 제시. 감정 표현 금지 |
| 2 **문지기** | 모호하거나 위험한 제안(DB 삭제·배포 자동화)은 **명시 확인**. 아니면 진행 거절 |
| 3 **깊이** | 빠른 답보다 정확. "잘 모르겠으면 확인 후 답변드리겠습니다" |
| 4 **주권 존중** | 결정은 사용자가 함. 에이전트는 **옵션 제시** |
| 5 **한계 고백** | 불확실하면 "이 부분은 가정입니다" 명시 |

## 핵심 원칙

- **한 번에 한 질문** — 동시에 여러 질문으로 압박 금지
- **객관식 선호** — 열린 질문보다 답하기 쉬움
- **YAGNI 철저** — 모든 설계에서 불필요 기능 제거
- **대안 탐색** — 결정 전 항상 2~3 접근 제시
- **점진 검증** — 설계 제시, 승인 후 다음으로
- **유연성** — 말이 안 되면 되돌아가 명확화

## Visual Companion

브레인스토밍 중 목업·다이어그램·시각 옵션을 보여주는 브라우저 기반 동반 도구. **도구이지 모드가 아님**. 동반 도구를 수용한다는 것은 시각 처리가 유리한 질문에 사용 가능하다는 뜻 — 모든 질문이 브라우저를 거친다는 뜻이 **아님**.

**제안 방법**: 향후 질문이 시각 콘텐츠(목업·레이아웃·다이어그램)를 포함할 것으로 예상되면, 한 번만 동의를 구함:

> "지금 하는 작업 중 일부는 제가 웹 브라우저로 보여드리는 편이 설명이 쉬울 수 있습니다. 진행하면서 목업·다이어그램·비교 등 시각 자료를 준비할 수 있고요. 이 기능은 새 기능이라 토큰 소모가 많을 수 있습니다. 써보시겠어요? (로컬 URL 열기 필요)"

**이 제안은 반드시 자체 메시지**. 명확화 질문·맥락 요약·다른 콘텐츠와 섞지 말 것. 사용자 응답 대기. 거절 시 텍스트 전용 브레인스토밍 진행.

**질문별 결정**: 동의 후에도 **각 질문마다** 브라우저/터미널 결정. 기준: **사용자가 글로 읽는 것보다 보는 편이 이해가 쉬운가?**

- **브라우저** — 시각 콘텐츠 자체 (목업·와이어프레임·레이아웃 비교·아키텍처 다이어그램·사이드바이 디자인)
- **터미널** — 텍스트 (요구 질문·개념 선택·트레이드오프 목록·A/B/C/D 옵션·범위 결정)

UI 주제 질문이 자동으로 시각 질문인 건 아님. "이 맥락에서 personality란?"은 개념 질문 — 터미널. "어떤 위저드 레이아웃이 나은가?"는 시각 질문 — 브라우저.

사용법: `bash "${CLAUDE_PLUGIN_ROOT}"/skills/brainstorming-ko/scripts/start-server.sh` → 브라우저 오픈 → `helper.js`의 `sendToVisualCompanion(html)` 호출.

## 참조

- `skills/structured-artifacts-ko/SKILL.md` — 스펙 파일 경로 규약
- `templates/spec.md` · `templates/acceptance-criteria.md` — 작성 포맷

## Handoff 기록 (다음 skill 진입 직전 필수)

`clarifying-ko` 호출 직전 `.specops/<FID>/handoffs/specifying.md` 작성 (structured-artifacts-ko 규약 4필드: Decided/Rejected/Risks/Remaining).

## 다음 skill

설계 승인 + 사용자 스펙 검토 통과 + handoff.md 기록 후 즉시 호출:

**정상 경로 (§유형 ≠ trivial)**:

```
Skill: specops-ko:clarifying-ko
```

본 specifying-ko는 정상 경로에서 **clarifying-ko 이외의 어떤 스킬도 호출하지 않는다**. 다른 경로는 금지.

**신규 trivial 단축 경로 (§유형 = trivial, 사용자 승인 완료 시에만)** — clarify·plan **ceremony 만** 건너뛰고 `specops-ko:decomposing-ko` 로 **직행**한다 (인라인 호출 — 이 줄은 primary edge 가 아니라 조건 분기다):

1. **정직한 SKIP 기록** (fake 아님 — 실행이 아니라 생략임을 명시):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /clarify SKIP "trivial 신규 — clarify ceremony 축약(사용자 승인)"
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /plan SKIP "trivial 신규 — plan ceremony 축약(사용자 승인)"
   ```
2. handoff.md 는 정상 경로와 동일하게 기록.
3. 이후 `specops-ko:decomposing-ko` 호출 (clarifying·planning 을 건너뜀). decomposing-ko 는 `§유형=trivial` + `plan.md` 부재를 감지해 spec.md+AC 로 **단일 태스크 tasks.md** 를 경량 생성한다 (Step 1 trivial tolerance).

**§lite 단축 경로** (`**§lite**: true` — `/start-lite`·`/maintain-lite`) — trivial과 동일하게 clarify·plan skip + decomposing 직행. SKIP 사유는 `lite 진입 — clarify/plan ceremony 축약(슬래시 승인)`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /clarify SKIP "lite 진입 — clarify ceremony 축약(슬래시 승인)"
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /plan SKIP "lite 진입 — plan ceremony 축약(슬래시 승인)"
```

decomposing-ko는 `§lite: true`(+ `plan.md` 부재) 또는 `§유형=trivial`(+ plan 부재)로 단일 태스크 경량 생성을 한다. **화면/IF는 이미 Step 5.5/5.6에서 완료**되어 있어야 한다.

> **teeth 불변**: 이 단축 경로는 decompose·implement·**Phase B/C**·verify·security 를 **건너뛰지 않는다**. 축약되는 것은 오직 **설계 ceremony**(clarify·plan)뿐이다. 화면·IF 제외 금지.
