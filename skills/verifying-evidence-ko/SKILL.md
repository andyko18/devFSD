---
name: verifying-evidence-ko
description: 작업이 완료·수정·통과됐다고 주장하기 직전, 커밋·PR 생성 전 반드시 사용 — 검증 명령을 실행하고 출력을 확인한 뒤에만 성공 주장 허용
layer: 2
discipline: true
reference_upstream: obra/superpowers@v5.0.7 skills/verification-before-completion/SKILL.md
  - obra/superpowers@v5.0.7 skills/verification-before-completion/SKILL.md
  - affaan-m/everything-claude-code@1.2.0 skills/verification-loop
  - skills/verifying-evidence-ko/SKILL.md
specops_version: 2.0.0
used_by: implementing-ko (chain 진입), requesting-code-review-ko (chain 출구)
---

# Engine 스킬 — 증거 기반 검증 (verifying-evidence)

## 개요

**검증 없이 완료를 주장하는 것은 효율이 아니라 부정직.**

**핵심 원칙**: **주장 전에 증거, 항상.**

**규칙의 문구를 어기는 것은 규칙의 정신을 어기는 것이다.**

## 철칙

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
새 검증 증거 없이 완료 주장 금지
```

본 메시지에서 검증 명령을 실행하지 않았다면 **통과한다고 주장할 수 없다**.

## 게이트 함수

```
어떤 상태든 주장하거나 만족을 표현하기 전에:

1. IDENTIFY: 이 주장을 증명할 명령은 무엇인가?
2. RUN: 전체 명령을 실행 (새로, 완전하게)
3. READ: 전체 출력, exit 코드 확인, 실패 개수 집계
4. VERIFY: 출력이 주장을 확증하는가?
   - NO → 증거와 함께 실제 상태 선언
   - YES → 증거와 함께 주장
5. 그런 다음에만: 주장

어느 스텝이든 생략 = 거짓말이지 검증이 아님
```

## 흔한 실패

| 주장 | 요구 증거 | 불충분 |
|---|---|---|
| 테스트 통과 | 테스트 명령 출력: 실패 0 | 이전 실행, "통과할 것 같다" |
| 린터 청정 | 린터 출력: 에러 0 | 부분 검사, 외삽 |
| 빌드 성공 | 빌드 명령: exit 0 | 린터 통과, 로그 좋아 보임 |
| 버그 픽스됨 | **원 증상 테스트 통과** | 코드 바뀜, 픽스됐다고 가정 |
| 회귀 테스트 동작 | **Red-green 사이클 검증** | 테스트가 한 번 통과 |
| 에이전트 완료 | VCS diff가 변경 보여줌 | 에이전트 "success" 보고 |
| 요구사항 충족 | 줄 단위 체크리스트 | 테스트 통과 |

## 레드 플래그 — 중단

- "should", "probably", "seems to" 사용
- 검증 전 만족 표현 ("Great!", "Perfect!", "Done!" 등)
- 검증 없이 커밋/푸시/PR 하려 함
- 에이전트 성공 보고 신뢰
- 부분 검증에 의존
- "이번만" 생각
- 지쳐서 작업 끝내고 싶음
- **검증 실행 없이 성공을 암시하는 어떤 표현이라도**

## 빈 출력 규칙

**빈 출력·`0`·무출력은 "없음"·"죽음"·"실패 없음"의 증거가 아니다.** 출력을 가공하는 계층(출력 필터 훅·alias·파이프·`2>/dev/null`·`|| true`)이 있으면 부재와 구별되지 않는다.

- **적용 대상**(빈값이 곧 결론이 되는 판정): ① 프로세스 생존 ② 파일/경로 존재 ③ 건수 ④ 변경 유무 ⑤ 로그 부재 ⑥ 테스트·검증 러너가 아무것도 출력하지 않거나 0건을 실행한 것 — 통과가 아니라 미실행(`NOT_RUN`)이다.
- **재확인 수단**(결론 전 하나 이상): 종료 코드 · 필터 없는 경로(절대경로 바이너리·환경이 제공하는 raw 실행 수단 — 파이프라인이면 각 단계 모두; 출력 필터는 파이프 후단 명령도 재작성하므로 선두만으론 부족하다. 파이프 없이 단계별로 따로 실행해 중간 출력을 봐도 된다) · 독립 교차 확인(다른 명령·다른 신호로 같은 사실을 다시 측정).
- **재확인하지 못하면** `[검증 불가 — 출력 비어 있음]` 로 라벨하고 결론을 내리지 않는다(5원칙 5 한계 고백).
- **행동 금지**: 빈 출력만 보고 행동을 바꾸는 결정(재실행·삭제·재시도·"죽었다/없다" 선언)은 재확인 전에 하지 않는다.
- **사례**(2026-09-06): 예: rtk 훅이 `ps` 출력을 삼켜 빈 출력 → "죽었다" 오진 → 포그라운드 재실행이 사본 삭제와 겹쳐 무효값 `39/6`(유효값 `45/0`). 필터 없는 실행은 `rtk proxy <cmd>`.

## 합리화 차단표

| 변명 | 실제 |
|---|---|
| "이제 동작할 것" | 검증을 **실행**하라 |
| "확신한다" | 확신 ≠ 증거 |
| "이번만" | 예외 없음 |
| "린터 통과" | 린터 ≠ 컴파일러 |
| "에이전트가 성공했다 함" | **독립 검증** |
| "지쳤다" | 피로 ≠ 변명 |
| "부분 검사로 충분" | 부분은 아무것도 증명 못 함 |
| "출력이 비었으니 없다/0이다" | 필터·가공으로 빈 출력은 부재와 구별되지 않는다 — **재확인** |
| "다른 단어라 규칙 무관" | **문구가 아니라 정신** |

## 핵심 패턴

**테스트**:
```
✅ [테스트 명령 실행] [보기: 34/34 pass] "모든 테스트 통과"
❌ "이제 통과할 것" / "맞는 것 같음"
```

**회귀 테스트 (TDD Red-Green)**:
```
✅ 작성 → 실행(pass) → 픽스 되돌림 → 실행(MUST FAIL) → 복원 → 실행(pass)
❌ "회귀 테스트 작성했다" (red-green 검증 없이)
```

**빌드**:
```
✅ [빌드 실행] [보기: exit 0] "빌드 통과"
❌ "린터 통과" (린터는 컴파일 검사 안 함)
```

**요구사항**:
```
✅ 플랜 재독 → 체크리스트 작성 → 각 항목 검증 → 격차·완료 보고
❌ "테스트 통과, 단계 완료"
```

**에이전트 위임**:
```
✅ 에이전트가 성공 보고 → VCS diff 확인 → 변경 검증 → 실제 상태 보고
❌ 에이전트 보고 신뢰
```

## 중요한 이유

원본 24개 실패 기록에서:
- 사용자 파트너가 "I don't believe you" 선언 — 신뢰 파괴
- 미정의 함수 배포 — 크래시
- 누락 요구사항 배포 — 기능 불완전
- 거짓 완료로 시간 낭비 → 재작업
- 위반: "정직은 핵심 가치. 거짓말하면 교체된다."

## 적용 시점

**항상 다음 직전**:
- 성공/완료 주장의 **어떤 변형**이든
- 만족 표현의 **어떤 변형**이든
- 작업 상태에 대한 긍정 발언 어떤 것이든
- 커밋·PR 생성·태스크 완료
- 다음 태스크로 이동
- 에이전트 위임

**규칙은 다음에 적용**:
- 정확한 구문
- 패러프레이즈·유사어
- 성공의 암시
- 완료·정확성을 시사하는 **어떤** 커뮤니케이션이든

## 검증 체크리스트 (specops-ko Lifecycle)

태스크 종료 전 다음 명령을 **실제 실행**하고 출력 첨부:

> **★ 러너는 `timeout` 을 명시해 포그라운드로 실행한다** (20260807-bg-verify-evidence) — `run-all.sh`(~330s) 처럼 오래 걸리는 러너는 Bash 도구 `timeout` 을 명시(최대 600s)하고 **포그라운드**로 돌린다. 백그라운드로 돌리면 tool_result 가 실행 출력이 아니라 스텁이라, **출력 파일을 `Read` 로 회수해야만** R-1/R-2 실행-근거 게이트가 증거로 인정한다. 회수를 빠뜨리면 정직하게 실행하고도 커밋이 막힌다(실측: 수분대 러너 재실행 낭비). 게이트가 막았는데 백그라운드 실행이 감지되면 deny 메시지가 회수할 경로를 알려준다.
>
> **회수했는데도 막히면 ② 를 보라** — 백그라운드+Read 회수는 판정 로직에 실재하고 동작한다(`governance-lib.sh` `$bghit`). 그런데 실행 증거만으로는 면제가 성립하지 않는다: FID 앵커(session-progress `/verify PASS` 줄 또는 evidence 스탬프)가 함께 있어야 한다. 구현 중이라면 `record-task-receipt.sh <FID> <T#>` 로 태스크 receipt 를 남기는 편이 빠르다(단 receipt 창은 verify 가 `NOT_RUN`·`PARTIAL`·`FAIL` 일 때만 열린다 — `PASS`·`STALE`·`WAIVED` 는 닫힘).

- [ ] **U3 자동화** (1순위): `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/run-verification.sh <FID>` — tasks.md 의 검증 명령을 자동 추출·실행하고 evidence.md 에 전문 append.
  - `VERIFY: PASS` + exit 0: 모든 명령 실행됨 + 전부 PASS (skip 0건)
  - `VERIFY: FAIL <cmd> (exit=N)` (stderr) + exit 1: 1건이라도 FAIL
  - `VERIFY: PARTIAL — N개 명령 whitelist 미통과` + exit 1: whitelist 미통과 명령 존재 — **수동 검증 필수**
  - `VERIFY: NOT_RUN` (stderr) + exit 1: 테스트 명령 0건 또는 실행된 명령 0건 — **PASS로 취급 금지**
  - 판정 SoT: `.specops/<FID>/verification-state.json` (`NOT_RUN|PASS|PARTIAL|FAIL|WAIVED`, PASS 이후 코드 변경 시 조회값 `STALE`). evidence.md 의 `RUN-VERIFICATION-RESULT` 스탬프는 하위 호환용.
  - 수율 계측: 동일 실행이 `.specops/<FID>/metrics.jsonl`에 `phase=verify` 메타데이터를 append (토큰·프롬프트 원문 없음).
  - **실행되는 러너** (v1.45.0 다언어 확장 + #209 downstream 배치): `bash scripts/*.sh`·`bash tests/*.sh`·`bash test/*.sh` · `pytest`(`python -m pytest` 포함) · `npm|pnpm|yarn (run) test` · `go test` · `cargo test`. 각 패턴은 선두 앵커(`^`)로 고정 — `echo pytest`·`foo && pytest` 류 위장은 SKIP 된다. 절대경로·`lib/` 등 비테스트 디렉토리 bash 는 여전히 SKIP.
  - **여전히 SKIP 되는 알려진 형태** (의도된 미지원): `go test ./...` (`..` path-traversal 가드에 먼저 걸림 — 개별 패키지 경로 `go test ./pkg/foo` 를 쓸 것) · `npm run test:unit` (`:` 가 인자 char-class 밖). 위 러너 밖의 명령(린터·빌드 등)도 SKIP → PARTIAL 이면 아래 수동 fallback 필수.
  - `VERIFY: FAIL review-audit` (stderr) + exit 1: Phase B/C 리뷰 리포트(`reviews/<task-id>-[BC]-*.md`)가 `dispatch-log.md` 에 **기록되지 않음**. 테스트가 전부 PASS 여도 감사 추적이 비면 통과시키지 않는다 (Generator↔Evaluator 분리는 기록으로만 검증 가능 — 20260721 test1 dogfood). 해당 task-id 행을 dispatch-log 에 추가하고 재실행할 것. 누락 전용 검사라 리뷰 산출물이 없으면 SKIP(fail-open).
  - ⚠️ **실행-근거 gate 와 직결**: R-1/R-2 커밋 게이트는 이제 이 러너의 `VERIFY: PASS` **실행 출력**(transcript `tool_result`)을 면제 조건으로 요구한다. PARTIAL/FAIL 은 실행 증거로 **불인정** — evidence.md 에 스탬프만 남기고 커밋하려 하면 deny 된다.
- [ ] **전체 스위트 신선도 확인** (`scripts/tests/run-all.sh` 가 있는 repo 한정 — 20261005): 전체 스위트를 포그라운드로 돌리기 **전에** 조회한다(repo 로컬 헬퍼를 우선하고 없으면 플러그인 사본).
  ```bash
  H=scripts/_internal/full-suite-fresh.sh; [ -f "$H" ] || H="${CLAUDE_PLUGIN_ROOT}/scripts/_internal/full-suite-fresh.sh"; bash "$H"
  ```
  - rc 0 (`full-suite FRESH (fp=...)`) → 직전 통과 이후 비문서 트리가 같다. 전체 스위트 **재실행을 생략**하고 그 1줄을 evidence.md 에 남긴다.
  - implementing-ko 가 띄운 백그라운드 `run-all.log` 가 아직 도는 중이면(`==== run-all:` 완료줄 없음) 종료 알림을 기다린 뒤 다시 조회한다.
  - rc 1(STALE)·헬퍼 부재(rc 127)·백그라운드 FAIL·판정 불가 → 종전대로 포그라운드 `run-all.sh` 를 재실행한다. 생략 판정이 애매하면 **재실행**한다.
  - 생략 대상은 이 수동 전체 스위트뿐이다. 게이트 증거는 여전히 `run-verification.sh` 의 `VERIFY: PASS` 실행 출력이다 — 그것이 PARTIAL·NOT_RUN 이면 run-all 의 `VERIFY: PASS` 가 증거이므로 **생략하지 않는다**(포그라운드 재실행).
  - 지문 한계: 읽을 수 없는 untracked 파일이 있으면 헬퍼가 STALE 로 처리한다. 그 밖에 지문을 의심할 사정이 있으면 재실행한다.
- [ ] **수동 fallback** (`run-verification.sh` 미적용 시):
  - `npm test` / `pytest` / 해당 프로젝트의 테스트 명령 — exit 0
  - 린터 / 포매터 — exit 0
  - 빌드 — exit 0
- [ ] 스펙 요구사항 체크리스트 — 각 항목 증거 있음
- [ ] 회귀 테스트 Red-Green 사이클 검증 (버그 픽스 태스크인 경우)
- [ ] **RED 실측 출력 원문 인용** — evidence.md 의 RED 관찰 기록은 카운트 요약 주장이 아니라 실측 출력 원문(요약행+FAIL 라인 ≤10줄) 인용 (GREEN 인용과 대칭)
- [ ] 서브에이전트 위임 태스크면 `git diff` 확인 (변경이 실제로 일어남)
- [ ] **intent 기대 결과 관찰** — intent 의 기대 결과가 실제로 관찰됐는지 evidence.md 에 1줄 기록(비차단 — 부재 시 graceful)
- [ ] **memory 설계 동기화 점검 (역방향 안전망 — design-first 보조)**: `.specops/memory/api-spec.md`·`api-spec-consumer.md`·`data-model.md` 또는 **프로젝트 루트 `screens/`**(`.specops/memory/` 하위가 **아닌** 저장소 루트 `screens/` — M-1 오독 방지) 가 하나라도 존재할 때만 (없으면 graceful skip — CLI 등).
  - **inspect-first**(코드를 진실원천으로): 이번 FID 의 **브랜치 누적 변경**에서 추출한다 — `git diff "$(git show-ref -q --verify refs/heads/main && echo main || echo master)"...HEAD` (base=main/master 자동). **주의**: `/implement` 가 태스크별로 **커밋**하므로 verify 시점엔 working-tree 가 클린 → bare `git diff`(unstaged)는 **빈 출력**이라 무탐지로 항상 통과한다(안전망 무력화). 반드시 `base...HEAD` 커밋분을 본다(R-2 거버넌스 `_detect_base_branch` 와 동일 패턴).
  - 추출 대상: 새/변경 **제공 엔드포인트**(라우트 정의 — 내부 함수 시그니처는 제외, 정방향 Step 5.6 "제공" 기준과 통일) · **외부 API 소비 호출**(신규 외부 호스트로의 fetch/axios/SDK 클라이언트 — UI·Mobile 의 소비 IF 축, `api-spec-consumer.md` 존재 시. 정방향 Step 5.6 "외부 소비" 기준과 통일 — 이 축이 빠지면 소비 IF 만 정방향 설계는 있는데 역방향 대조가 없는 반쪽 안전망이 된다) · **스키마**(테이블·필드·마이그레이션) · **클라이언트 영속 데이터**(localStorage 키(`setItem` 신규 네임스페이스)·IndexedDB objectStore — Step 5.6 클라이언트 스토리지 축과 통일) · **화면 계약**(screens/{name}.md ↔ 구현 산출물 — Step 5.5 design-first. screens-overview.md 화면목록 대비 구현 누락·드리프트).
  - **스키마 추출 heuristic** (gap5 명세 — 도구별 위치): 마이그레이션 디렉토리(`prisma/migrations/`·`alembic/versions/`·`db/migrations/`·`migrations/`·`supabase/migrations/`) 신규 파일 · ORM 스키마(`schema.prisma`·`models.py`·`*_entity.ts`) diff · raw `CREATE|ALTER TABLE` grep. **한계 고백**: `data-model.md` §2 ERD(mermaid)는 수기 문서라 자동 대조 불가 — 대조 기준은 **§3 엔티티 표**(테이블·필드 텍스트)이고, ERD 는 drift 가능성을 전제로 "§3 갱신 시 ERD 도 함께" 권고만 남긴다.
  - 추출분이 `api-spec.md`·`api-spec-consumer.md`(소비 호출↔소비 계약)·`data-model.md` 에 **반영돼 있는지 대조**. 통상 `specifying-ko` Step 5.6(정방향 인터페이스 설계)이 선반영했으면 일치한다.
  - **누락·괴리 발견 시**: evidence.md 에 `## memory 동기화 권고` 섹션 기록 — "코드의 `POST /orders` 가 api-spec 의 **채택된 정의방식 섹션**에 없음 → 반영 검토" 식으로 **무엇을 어디에** 명시 + 사용자에게 출력.
    - 화면 괴리는 evidence.md 에 `## 화면 동기화 권고` 섹션으로 기록(chain 비차단, 자동 수정 금지 — DB 동기화와 동일). screens/ 부재(CLI·순수 로직) 시 graceful skip.
    - **화면 껍데기 점검 (기존 역방향 net 확장 — 새 스크립트·훅 신설 아님)**: 루트 `screens/` 존재 시 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/design-screen.sh --check screens/*.md screens/*.html` 로 판정(태스크 1 헬퍼 재사용). exit 0(껍데기 잔존)이면 evidence.md 에 `## 화면 껍데기 경고` 섹션으로 해당 경로를 나열하고 사용자에게 출력한다.
      - **비차단**: 본 버전에서는 `VERIFY: FAIL` 로 승급하지 않는다 (사용자 결정 — 단계적 적용. 상류 Phase 2.5·Step 5.5 자동 재생성이 실질 공백을 메운다).
      - **차단 승급 조건 (차기 버전 반영 대상 — 현 버전은 위 "비차단"이 우선)**: 이 경고가 실제로 관찰되면 상류 교정 실패의 증거이므로 차단으로 승급 대상이다 (차기 유지보수에서 `VERIFY: FAIL` 승급) — 상류가 정상 동작하면 신규 생성 화면에 마커가 남을 수 없기 때문이다. **현 버전에서는 관찰돼도 승급하지 말 것** (L170 비차단 준수).
      - `screens/` 부재(CLI·순수 로직) 시 graceful skip.
    - **화면 품질 계측 (같은 역방향 net — 단일 모드 도달점)**: 루트 `screens/` 존재 시 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-screen-quality.sh --all` 을 실행해 전 화면 계측 원문을 evidence.md `## 화면 품질 계측` 섹션에 기록한다. 사용자에게는 **상세줄이 있는 화면**만 출력한다(노이즈 최소) — 단 상세줄이 `[genre] 원형 미선언` 하나뿐인 화면(원형을 선언하지 않은 기존 화면)은 화면별로 나열하지 않고 `원형 미선언 N개` 1줄로 모은다. `genre=` 축은 `DESIGN.md` §6.1 장르 규칙이고, `genre=unknown` 은 원형 미선언이지 위반 없음이 아니다.
      - **비차단**: 계측기는 항상 exit 0 이며 이 결과로 `VERIFY: FAIL` 로 승급하지 않는다 — 휴리스틱 오탐이 chain 을 세우면 BYPASS 관성이 생긴다.
      - `screens/` 부재(CLI·순수 로직) 시 graceful skip.
    - **화면 회귀 (같은 역방향 net — 수정 경로 축소 탐지)**: 루트 `screens/` 존재 시 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-screen-quality.sh --regress` 를 실행해 각 화면을 브랜치 분기 시점(main/master merge-base)의 같은 화면과 비교한 원문을 evidence.md `## 화면 회귀` 섹션에 기록한다. 사용자에게는 `[shrink]`(내용 바이트가 기준의 0.60배 미만 — `SPECOPS_SCREEN_SHRINK_RATIO` 로 조정) 또는 `[new-rule]`(이전 버전에 없던 위반)이 있는 화면과, 비교 자체를 못 한 `[scope]` 줄을 출력한다(기능이 조용히 꺼진 상태를 드러낸다). main 위에서 실행하면 기준이 HEAD 라 커밋된 변경은 비교되지 않는다(미커밋분만). `new`·`shell`·`deleted`·`unknown` 은 비교하지 않았다는 뜻이지 회귀 없음이 아니다.
      - **비차단**: 이 결과로 `VERIFY: FAIL` 로 승급하지 않는다 — 임계값 근거가 얇다(표본 화면 1개 · 축소 사례 0).
      - **차단 승급 조건 (차기 버전 검토)**: `[shrink]` 경고가 실제 회귀로 확인된 사례가 쌓이고 정상 개편 오탐이 0 으로 확인되면, 차기 유지보수에서 `VERIFY: FAIL` 승급을 검토한다.
      - `screens/` 부재(CLI·순수 로직) 시 graceful skip.
  - **테스트=spec 커버 점검** (ecc inspect-first 교훈 2 — 빈틈2 해소): 이번 FID 가 **api-spec.md 에 추가·변경한 제공 엔드포인트** 각각에 대해, 브랜치 누적 변경의 테스트 파일에서 해당 라우트를 호출·검증하는 케이스가 존재하는지 대조. 미커버 엔드포인트는 evidence.md `## 미커버 엔드포인트` 섹션에 나열 (감지·권고만 — AC 매핑 커버리지는 decomposing 몫이므로 여기서는 **설계문서↔테스트의 잔여 괴리**만 잡는다. 부재 시 graceful skip).
  - **자동 수정 금지** (5원칙 4 주권 — 기준 설계문서 변경은 사용자 결정). 본 스텝은 **감지·권고만**, chain 비차단.
- [ ] **foundation manifest 산출 게이트 (HARD — §유형=foundation 일 때만)**: `grep -qE '^\*\*§유형\*\*:[[:space:]]*foundation' .specops/<FID>/spec.md` 이면 → `.specops/memory/foundation-manifest.md` 가 **존재**하고 **실제 내용으로 채워졌는지** 확인. §유형≠foundation 이면 graceful skip.
  - **판정 SoT = `scripts/_internal/check-foundation-manifest.sh`** (20260806 기계화). `run-verification.sh` 가 자동 호출하므로 **본 체크리스트는 결과 확인용**이다 — 모델이 이 절을 건너뛰어도 게이트는 발화한다. 종전엔 산문뿐이라(구현 0곳) **침묵 무발동을 막으려는 게이트 자체가 침묵 무발동**이었다.
  - **FAIL 조건**: 파일 부재 **또는** 템플릿 placeholder 잔존(미채움) → `VERIFY: FAIL foundation-manifest 미산출` (stderr) + 완료 주장 차단. 채움 판정은 placeholder SoT(`scan-enrich-placeholders.sh`)를 재사용한다 — 구 판정 `grep -q '<경로>'` 는 **단일 토큰**이라 경로만 채우고 `<설명>`·`<import 예시>`·`<확정된 프레임워크>` 가 전부 남아도 통과했다.
  - **근거**: 소비측 재사용 게이트(`decomposing-ko`)는 이 파일 **존재를 전제**로만 발동한다. 생산은 `planning-ko` 산문 지시뿐(강제 evaluator 부재)이라, verify 가 실제 산출물을 확인하지 않으면 manifest 누락 시 후속 `/start` 재사용 게이트가 **침묵 무발동(no-op)** 한다. 본 게이트가 **Mode1(manifest 태스크 누락)·Mode2(태스크 존재하나 파일 미작성)** 를 모두 차단 → implementing **후** 실제 파일을 검사하는 유일 지점이므로 소비 게이트를 무접촉으로 transitively 건전화한다.
- [ ] **구조 규칙 판정 명령 (헌법에 판정 `명령` 규칙이 있을 때)**: `run-verification.sh` 가 `check-rule-commands.sh` 로 실행하고 결과를 evidence.md `### structure-rule-commands` 에 남긴다. 위반(`FAIL`)은 `VERIFY: FAIL structure-rule-commands` 로 검증을 막는다 — 코드를 고치거나, 규칙이 틀렸으면 사용자에게 알린다(헌법을 스스로 고치지 않는다). `판정 불가`·`TIMEOUT`·`SKIP` 은 경고로 보고한다(`판정 불가` 는 도구·환경이 없어 확인하지 못한 것 — 위반 아님).
- [ ] **import 방향·순환 (경고 전용)**: `run-verification.sh` 가 `check-import-direction.sh` 로 plan 의 허용 의존(화살표 형식)을 이 FID 의 import 와 대조하고 순환을 찾아 evidence.md `### import-direction` 에 남긴다. `WARN` 이어도 검증은 실패하지 않는다 — 역방향·순환은 구현을 고치거나 plan 의 허용 의존을 고쳐 맞추고, 그대로 두려면 PR 본문에 이유를 적는다
- [ ] **API 계약 빈칸·형식 (경고 전용)**: `run-verification.sh` 가 `check-api-contract.sh` 로 `.specops/memory/api-spec.md` 의 이 FID 가 바꾼 엔드포인트 행(경로 동사·중첩 · 상태코드)과 계약 칸(오류 형식·오류 코드·목록 정책·멱등 정책·rate limit·버전 전략)을 보고 evidence.md `### api-contract` 에 남긴다. `WARN` 은 결함 후보일 뿐 VERIFY 결과를 바꾸지 않는다 · 칸이 없는 옛 문서는 `[건너뜀]` · api-spec 부재는 SKIP.
- [ ] `.specops/<FID>/evidence.md`에 출력 캡처 (`run-verification.sh` 가 자동 append)

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 스킬 적용 |
|---|---|
| 1 **투명성** | 검증 명령과 출력을 **`evidence.md`에 전문 기록**. 요약 금지 |
| 2 **문지기** | 증거 없는 완료 주장은 **즉시 반려**. "거의" 불가 |
| 3 **깊이** | 부분 검증은 부분만 증명. 누락된 검증 항목을 **나열** |
| 4 **주권 존중** | 사용자가 "통과했다고 하자"는 주장에도 반드시 증거 요구 |
| 5 **한계 고백** | 검증할 수 없는 항목은 "검증 불가" 라벨 + 이유 |

## 결론

**검증에 지름길 없음.**

명령을 실행하라. 출력을 읽어라. **그런 다음** 결과를 주장하라.

협상 불가.

## 참조

- ECC 보완: `affaan-m/everything-claude-code@1.2.0 skills/verification-loop/`
- specops-ko 한국어 선례: `skills/verifying-evidence-ko/SKILL.md`

## Bounded verify→fix 루프 (P2-2)

검증 FAIL 시 즉시 HARD GATE 대신 **bounded 자율 수렴**. OMC `max_fix_loops=3` 패턴 차용.

### 루프 상태 파일

`.specops/<FID>/verify-loop.md` — 루프 카운터 + 마지막 FAIL 항목 기록:

```markdown
fix_count: 0
last_fails: []
```

파일 부재 시 `fix_count=0`으로 간주 (graceful init).

### 루프 흐름

```
[VERIFY LOOP — 상한 3회]
    ↓
검증 실행 (run-verification.sh or 수동)
    ↓
FAIL 항목 존재?
    ├─ NO (전부 PASS) → verify-loop.md 삭제 → session-progress append → 다음 skill
    └─ YES →
        fix_count = verify-loop.md 의 fix_count + 1
        ├─ fix_count > 3 → HARD GATE: 출력 후 중단
        │   "VERIFY-HARD-GATE: <FID> fix_loop 상한 초과 (3/3)
        │    FAIL: <AC 목록>
        │    원인 분석 필요 — systematic-debugging-ko 또는 사용자 결정"
        └─ fix_count ≤ 3 →
            동일 실패 지문 검사 — fix task dispatch 직전, 스크립트가 판정한다:
              bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/attempt-fp.sh check <FID>
              ├─ rc 1 (ATTEMPT-STOP) → fix task dispatch 없이 cap 초과와 같은 경로로 처리:
              │   단일 모드: HARD GATE "VERIFY-HARD-GATE: <FID> 동일 실패 지문 <n>회 연속 (fp=<앞8자>) — 원인 분석 필요"
              │   §auto: 아래 "[§auto 모드]" 흐름 (systematic-debugging-ko → 전역 재시도)
              └─ rc 0 (지문 상이·PASS 개재·기록 부재 포함) → 계속
            verify-loop.md 갱신 (fix_count, last_fails)
            fix task 컨텍스트 작성:
              - FAIL AC ID 목록
              - evidence.md 에서 실패 출력 발췌
              - 수정 허용 파일 범위 (관련 task outputs)
            implementing-ko 호출 (targeted fix scope)
                ↓
            ← VERIFY LOOP 재진입

### [§auto 모드] fix_loop cap 초과 처리

fix_count > 3 **또는 `attempt-fp.sh check` rc 1(동일 실패 지문 연속)** 시 HARD GATE 대신 **systematic-debugging-ko → 전역 재시도** 흐름:

```
§auto 감지? (grep -qE '^\*\*§auto\*\*:[[:space:]]*true' .specops/<FID>/spec.md)
  ├─ NO  → 기존 HARD GATE: "VERIFY-HARD-GATE: <FID> fix_loop 상한 초과 (3/3)..."
  └─ YES → auto-state.md 읽기 (.specops/<FID>/auto-state.md — 없으면 auto_retry_count=0)
           auto_retry_count < 1?
           ├─ YES → auto_retry_count += 1 저장 + escalations 기록
           │        → verify-loop.md 초기화 (fix_count=0)
           │        → advisor() 1회 자문 시도(보조 입력 — 근본 원인 가설) + escalations 기록. 미연결 시 skip(graceful fallback)
           │        → specops-ko:systematic-debugging-ko 호출
           │        → 복귀 후 VERIFY LOOP 재진입
           └─ NO  → HARD GATE (무인 종료):
                    "AUTO-HARD-GATE: <FID> verify fix_loop 전역 재시도 초과 (1/1)
                     FAIL: <AC 목록>
                     systematic-debugging 또는 사용자 개입 필요"
```

**auto_retry_count 공유**: implementing-ko Phase B/C cap 초과와 동일 카운터 사용 (per-FID 전역, `.specops/<FID>/auto-state.md`).
```

### 동일 실패 지문 정지 (attempt fingerprint)

- `run-verification.sh` 가 FAIL·PASS 판정마다 `.specops/<FID>/attempts.jsonl` 에 실패 출력 정규화 해시 1줄을 기록한다(원문 미저장 · PARTIAL·NOT_RUN 은 기록 안 함). 이 파일은 스크립트 전용 기록이다 — 모델은 읽거나 쓰지 않고 `check` 의 rc 만 따른다.
- `check` rc 1 = 같은 지문의 FAIL 연속 2회(`ATTEMPT_FP_MAX=2`, env 로 못 바꾼다) — cap(3) 이내여도 fix 를 더 돌리지 않는다. rc 0 = 계속(기록 부재·판독 불가는 fail-open — 기존 cap 경로). 지문이 달라져도 `fix_count` 상한은 그대로다 — cap 은 우회되지 않는다.
- 정지 시 session-progress BLOCK 줄은 `fix_loop=3/3 초과` 대신 `동일 실패 지문 <n>회 연속` 으로 쓴다.
- 한계: 실패 줄에 키워드가 없는 출력(한글 전용 메시지·`set -e` 중단·go 상세 줄·긴 메시지만 다른 같은-테스트 실패)과 8자 이상 hex/10진 id(`test_deadbeef01` vs `test_cafebabe02`)는 CMD·EXIT·테스트 id 단위로 같은 지문에 접힌다 — 정지 시 재료 부족일 수 있다.

### 규칙

- fix task는 **FAIL AC에 직접 연결된 파일만** 수정 범위로 제한 (scope creep 금지)
- 각 루프 시도는 `evidence.md`에 `## Fix loop N` 섹션으로 append (투명성)
- `fix_count=1/3`, `2/3`, `3/3` 형태로 사용자에게 진행 상황 고지
- implementing-ko 내 Phase B/C cap은 루프당 독립 리셋 (verify-loop과 별개)

## session-progress append (v0.4-pre P1 신설)

evidence.md 작성 + 모든 검증 PASS 직후, requesting-code-review-ko 호출 직전에:
```
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /verify PASS "evidence.md, AC N/N"
```

검증 실패 + fix_loop 상한 초과 시 (BLOCK):
```
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/session-progress-append.sh <FID> /verify BLOCK "evidence.md (AC-X 미충족), fix_loop=3/3 초과 — HARD GATE"
```

## 다음 skill

모든 검증 항목 PASS + verify-loop.md 삭제 + session-progress append 후:

**[fast path — end-loaded 리뷰 완료 FID]** 먼저 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/review-skip-pass.sh <FID>` 를 실행한다. rc 0 (`review-skip-pass: OK`)이면 requesting·receiving-code-review-ko 를 **호출하지 않고** 곧바로 `Skill: specops-ko:security-review-ko` 를 호출한다 — 두 단계가 남기던 산출물(review-skip.md·session-progress 두 줄)을 스크립트가 이미 남겼다. rc 1 이면(per-task·§batch·리포트 누락·review-skip.md/review-request.md 기존재 등) 아래 기본 경로다. 판정이 애매하면 기본 경로다.

기본 경로 — 즉시 호출:

```
Skill: specops-ko:requesting-code-review-ko
```

requesting-code-review-ko가 전체 변경사항에 대한 외부 리뷰를 요청한다. 본 verifying-evidence-ko는 정상 chain 전진 시 **requesting-code-review-ko 이외의 다음 스킬을 호출하지 않는다** (예외: 위 fast path 의 security-review-ko 직행, 아래 fix_loop 상한 초과 복구).

fix_loop 상한(3회) 초과 시: `specops-ko:systematic-debugging-ko` 호출 (근본 원인 분석 후 chain 복귀).
