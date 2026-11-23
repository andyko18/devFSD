# specops-ko 개선 제안 (2026-09-02, v1.91.0)

> **성격**: 5회차 평가에서 **새로 실측된 결함**만 담은 제안서. 전부 재현 명령 포함.
> **원본**: `.specops/audit/improvement-proposals-20260902.md` (lifecycle 산출물, 로컬 전용)
> **왜 여기 있는가**: 위 평가서와 동일 — `.specops/` 로컬 전용 정책의 **의도적 예외**.
>
> **이후 경과 (2026-09-03 추가)**:
> - **1순위** — DAG 산문 헤더 결함: **해소** (PR #25, `7109a90`)
> - **2순위** — whitelist 워크스페이스·의존성관리자 접두: **해소** (PR #26, `377e3be`)
> - **3순위** — `skip-tracker` bare SKIP 이빨: **저자가 스스로 강등**. 전제가 부분적으로 틀렸다 —
>   `release-ready.sh` 가 `skip_cite=BARE` → `ready=0` 으로 **이미 하드 차단**한다(실측으로 직접 맞음).
>   제안의 유효 범위는 lifecycle **중간 단계**의 advisory 에 한정된다.
> - **신규 3순위 후보** — R-1 pretool 이 팀메이트 서브에이전트의 러너 실행을 transcript 에서 보지
>   못한다. 2026-09-03 세션에서 **두 번** 발현(T1 인수 · Phase C degradation).
> - 4~6순위(LICENSE · 죽은 계측 스키마 · FID 파서 중복): **미조치**.

---

> 5회차 평가(`plugin-evaluation-20260902.md`, 7.3/10)에서 **새로 실측된 결함**만 담는다.
> 전부 재현 명령을 붙였다. 추측 항목은 넣지 않았다.

## 1순위 ★ 추천 — tasks.md DAG 가 산문 헤더 하나에 걸려 통째로 비가시가 된다

**증상**: 잘 만들어진 tasks.md 인데 검증 대상이 **0건**이 되고, 아무도 안 읽는 stderr WARN 만 남는다.

**재현** (1줄):
```bash
bash scripts/_internal/extract-test-commands.sh \
  /home/dev/project/Argus/.specops/20260826-argus-chart/tasks.md
# → WARN: ... YAML missing test_command — falling back to Step 4 line grep
# → extract-test-commands: 명령 0건
# 그런데 그 파일 44·48행에 test_command 가 실재한다.
```

**원인** (`scripts/dag/parse-dag.sh:43-49`): `dag::extract_yaml` 의 awk 가
**`^## 의존 그래프` 헤더를 만난 뒤의 ```yaml 펜스만** 읽는다. Argus 는 같은 YAML 을
`## 진행: 2/2` 아래에 뒀다. 헤더 문자열 하나가 어긋나면 DAG 전체가 존재하지 않는 것이 된다.

**범위** (전 디스크 실측): `yaml + test_command` 를 가진 tasks.md **158개 중 10개**가 헤더 부재.
그중 **9개가 Argus**(최대 외부 repo)이고 08-25~08-26 한 주에 몰려 있다 — 한 번의 lifecycle 런이
9 FID 의 DAG 를 통째로 비가시로 만들었다.

**귀결 (추적한 사실만)**:
- 그 8 FID 중 **5개는 evidence.md 자체가 없다** — verify 단계에 도달하지 않았다.
- 나머지 3개는 `RUN-VERIFICATION-RESULT: PASS` 인데, 그 PASS 를 만든 명령은 DAG 가 선언한
  `pnpm --dir frontend test chart-wiring` 이 **아니라** 사람이 고른 다른 명령이다
  (`bash scripts/tests/run-tests.sh tests/unit tests/integration -q` → 727 passed).
- 즉 **PASS 는 정직하되, 태스크↔AC↔명령의 결속은 끊긴 채로 났다.** 선언된 per-task
  `test_command` 는 한 번도 재실행되지 않았고, 그 사실을 아무도 못 본다.

> 한계 고백: `run-verification.sh:285` 는 `executed==0` 이면 `NOT_RUN` 으로 **크게 실패**한다.
> 따라서 위 3건의 PASS 는 "0건인데 통과"가 아니다. 무엇이 그 스탬프를 썼는지(당시 플러그인
> 버전인지 `verifying-ko` 직접 기록인지)는 **추적하지 않았다**. 이 제안은 그 인과가 아니라
> **재현된 추출 0건**과 **5/8 evidence 부재** 위에 선다.

**제안**:
1. `dag::extract_yaml` 을 **헤더 비의존**으로 — 헤더가 없으면 문서 내 `tasks:` 키를 가진 yaml
   펜스를 채택(복수면 첫 번째 + WARN).
2. **판정 승격**: 파일에 `test_command` 문자열이 있는데 추출 0건이면 **WARN 이 아니라 FAIL**.
   지금 구조는 "조용히 잘못되는 구조를 없앤다"는 이 repo 명제의 정면 반례다.
3. `validate-structure` 또는 `decomposing-ko` 산출 직후에 **추출 0건 검사**를 건다.

**비용** 소 (`parse-dag.sh` 1함수 + 회귀 2건) · **효과** 큼 (조용한 false-PASS 제거)

---

## 2순위 — 러너 whitelist 가 워크스페이스·의존성관리자 접두를 모른다 (false-block 10호)

**실측**: 하류 5 repo 의 tasks.md 에서 뽑은 고유 `test_command` 를 현 whitelist 정규식에 통과시켰다.
**실제 러너 명령 중 22종이 차단**된다.

| 형태 | 관측 건수 | 소속 |
|---|---|---|
| `pnpm --dir <dir> test <name>` | 10 | Argus |
| `pnpm --filter <pkg> test <name>` | 6 | ssl-portal |
| `poetry run pytest <file> -q` | 6 | Argus |
| `npm run test:unit` 계열(콜론 스크립트명) | **관측 0** | 정규식 판정으로만 차단 확인 — 실사용 관측 없음 |

> 분모 주의: 추출기가 산문 줄(`- [ ] Step 4b: …` 등 `test_command` 를 **언급**만 한 줄) 약 12건을
> 함께 쓸어담아 원시 고유값은 191종·BLOCK 40이었다. 산문을 걷어낸 **실제 러너 차단이 22종**이다.
> 분모(러너 명령 총수)는 정밀하지 않으므로 비율이 아니라 절대 건수로 읽어야 한다.

현 패턴은 `pnpm exec <bin>` 과 `npm run test` 는 받지만, **워크스페이스 플래그**(`--dir`·`--filter`·`-C`)와
**의존성관리자 접두**(`poetry|pdm|uv|rye run`)는 모른다. 오늘 머지한 #22 는 `FOO=1 <러너>` 형태의
**env 접두만** 고쳤다 — 같은 클래스의 나머지가 남아 있다.

**제안**: 접두 그룹을 하나 더 연다 —
`((poetry|pdm|uv|rye)[[:blank:]]+run[[:blank:]]+)?` 와
`(npm|pnpm|yarn)[[:blank:]]+((--dir|--filter|-C|-w)[[:blank:]]+<safe>[[:blank:]]+)*`.
스크립트명은 `test[A-Za-z0-9:_-]*` 로 콜론 허용. 경로 트래버설 가드(`..`·절대경로)는 기존 그대로 유지.

**비용** 소 (정규식 + 테이블 테스트) · **효과** 중~큼 (4회차가 실증한 false-block → BYPASS 관성 경로)

---

## 3순위 — `skip-tracker` 의 근거 없는 SKIP 에 이빨을 달아라

**실측** (`bash scripts/skip-tracker.sh`): integration SKIP **64%** · performance **62%** · 근거 없는(`bare`)
SKIP **18건**. v1.82.0 릴리즈 노트가 스스로 *"skip-tracker 가 경고만 하고 있다(bare 15건)"* 라고
적어뒀고, **6주 뒤 15 → 18로 늘었다.**

**제안**: 임계값을 발명하지 말고 **`bare > 0` 이면 verify FAIL** 만 건다(사유가 적힌 SKIP 은 통과).
v1.82.0 이 `skill_size` 에서 이미 쓴 래칫 논리 그대로다.

**비용** 소 · **효과** 큼 (외부 완주 63건의 품질 주장을 뒷받침하는 유일한 축)

---

## 4순위 — LICENSE 를 넣어라

2026-08-11 에 저장소를 공개했는데 `licenseInfo: null` 이다. **공개 + 무라이선스 = 법적 전권 유보** —
3자가 설치는 되지만 사용·수정 권리가 없다. 5회 연속 미조치 항목 중 유일하게 비용이 사실상 0이다.

**비용** ~0 · **효과** 중 (온보딩 축 상향 트리거의 전제)

---

## 5순위 — 죽은 계측 스키마 2건: 채우든지 지우든지

- `metrics.jsonl` **143/143 레코드 전량** `tokens={input:null,output:null,cache_read:null,cache_write:null}`.
  `model`·`wall_ms` 도 null. **한 번도 값이 들어간 적 없는 필드**가 스키마에 박혀 있다.
- 비어 있는 계측은 "측정하고 있다"는 착시만 준다. 채울 계획이 없으면 스키마에서 빼는 게 정직하다.

**비용** 소(삭제) / 중(수집 배선) · **효과** 중

---

## 6순위 — FID 파서 8중 복제

**정정**: 2026-08-29 적대감사의 "FID 파서 5중 복제"가 지금 몇 곳인지 **확정하지 못했다**.
`detect_fid` 류를 **정의**하는 파일은 `hooks/governance-lib.sh` · `scripts/session-progress-append.sh`
**2곳**이고, FID 형태(`YYYYMMDD-slug`·`active-fid`)를 **언급**하는 파일이 8곳이다. 후자가 독립
파서인지 상수 참조인지는 확인하지 않았다 — **"5→8 악화" 라고 말할 근거는 없다.**

**제안**: 8곳을 1건씩 열어 독립 해석인지 판별한 뒤, 독립이면 `propagation-matrix.jsonl` 에
레코드로 등재해 드리프트를 기계가 잡게 한다(이 repo 가 이미 쓰는 패턴). 판별 자체가 선행 과제다.

**비용** 중 · **효과** 미확정 (판별 전)

---

## 하지 말 것 (경제성 축 처방)

**게이트를 검사하는 게이트를 한 구간 쉬어라.** 이번 구간 삽입 24,672줄 중 테스트가 13,413(54%),
C(자기유지) 비중이 **~90%로 5회 연속 불변**이다. #19·#21 같은 메타 게이트는 방향이 옳지만,
1~2순위는 **메타층이 아니라 하류 사용자가 실제로 밟는 경로**의 결함이다. 다음 구간은 그쪽만 해도 된다.
