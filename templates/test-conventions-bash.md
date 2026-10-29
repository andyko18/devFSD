<!-- reference_upstream: specops-ko FID 20260424-decomposing-test-conventions -->
<!-- layer: Template -->

# bash 테스트 컨벤션 — specops-ko

> decomposing-ko 가 bash 테스트 태스크를 분해할 때 따르는 컨벤션.
> 본 문서는 bash 한정. 타 언어는 v0.3+ 에서 별도 템플릿 (예: `test-conventions-python.md`) 으로 확장.
> 플러그인 내부 예시가 곧 universal 표준은 아님 — 각 항목의 강도를 구분한다.

## 1. 위치

**규칙**: bash 테스트는 `scripts/tests/<feature>/test-*.sh` 에 배치. 플러그인 전역 테스트는 `scripts/tests/test-*.sh` (feature 하위 폴더 없이).

**강도**: specops-ko 내부 예시 — downstream 프로젝트가 다른 구조 (예: `tests/`, `spec/`) 를 쓰면 그 관례 우선.

**예시**:
- 전역: `scripts/tests/test-is-hook-enabled.sh`
- feature 별: `scripts/tests/governance/test-rules.sh`

**이유**: suite 간 격리 + 공용 `test-lib.sh` 접근성.

## 2. 명명

**규칙**: `test-<subject>.sh`. `<subject>` 는 대응 프로덕션 파일 basename (확장자 제거) 또는 domain 이름.

**강도**: specops-ko 내부 예시.

**예시**:
- 프로덕션 `scripts/is-hook-enabled.sh` → 테스트 `scripts/tests/test-is-hook-enabled.sh`
- 크로스 기능 테스트: `test-<domain>.sh` (예: `test-manifest.sh`)

**이유**: 1:1 대응으로 커버리지 추적 용이.

## 3. 실행권한

**규칙**: 모든 `test-*.sh` 는 `chmod +x` (mode 755) — 직접 실행 가능해야 한다.

**강도**: ⚠️ **Universal 강제**. 실행권한 누락 시 decomposing-ko 의 `<HARD-GATE>` 가 발동하여 `devfsd:implementing-ko` 호출이 차단된다.

**예외 — library-only 파일**: shebang 바로 다음 줄 (L2) 에 `# library-only` 주석 마커가 있는 파일은 sourced-only 전용으로 간주하여 exec-bit 검증 skip. 범위는 **첫 두 줄 내** (L1 shebang + L2 마커) 로 HARD-GATE 계약과 동일. shebang 자체는 library-only 파일에도 필수다.

**마커 인식 규칙**: 라인 전체가 `# library-only` 와 정확히 일치해야 한다 (선/후 공백 허용). 부분 문자열 (`# library-only-stub`, `# NOT library-only` 등) 은 인식되지 않는다. R-6 후속 FID 의 기계적 스캐너는 anchored regex `^[[:space:]]*#[[:space:]]+library-only[[:space:]]*$` 를 적용한다.

**예시**:

직접 실행용 (exec-bit 필수):
```bash
#!/usr/bin/env bash
set -u
# T1.a example
echo PASS
```

library-only (exec-bit 생략 허용):
```bash
#!/usr/bin/env bash
# library-only
# source 전용 — 직접 실행 금지
common_func() {
  echo "util"
}
```

실측 참고: `scripts/tests/governance/test-lib.sh` 는 본 컨벤션 도입 이전 `318456c` 에서 일괄 +x 부여됐으나, 본 컨벤션 기준으로는 L2 에 `# library-only` 마커 추가로 exec-bit 생략이 가능해진다 (소급 적용은 선택).

**이유**: 실행 불가 테스트 파일은 CI 에서 silent skip 된다. 직전 FID (`20260424-governance-capture`) 외부 리뷰 MINOR 5 마찰의 직접 원인.

## 4. 헤더

**규칙**:
- **L1 shebang**: `#!/usr/bin/env bash` — 모든 bash 테스트 필수
- **L2~ (권장)**: `set -u`, `PASS=0; FAIL=0`, `PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)`, `T<N>.<letter> <설명>` 형식 TEST ID

**강도**:
- **L1 shebang**: ⚠️ **Universal 강제** — 누락 시 `<HARD-GATE>` 발동
- **L2~ (카운터·PLUGIN·TEST ID)**: specops-ko 내부 예시. downstream 프로젝트에서 bats·shellspec 같은 다른 runner 를 쓰면 그 관례 우선

**예시** (내부 예시 전체 블록):

```bash
#!/usr/bin/env bash
set -u
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

# T1.a 기능 X 검증
if [ 조건 ]; then
  PASS=$((PASS+1)); echo "PASS T1.a 기능 X"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a (context)"
fi

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
```

**이유**: shebang 없이는 exec-bit 가 있어도 실행 실패. L2~ 패턴은 specops-ko 내부 통일성을 위한 것이지 bash 테스트 표준 아님.

## 5. grep 앵커 고유성 (tautology 방지)

`grep -q '<앵커>' "$파일"` 로 문서·코드의 특정 문구 존재를 검사하는 테스트(예: `test-meta-skill.sh`, `test-validate-structure.sh`)는 **앵커가 검사 대상에만 있는 고유 문구**여야 한다.

**규약**: 앵커 추가·수정 시 반드시 확인 —
```bash
grep -c '<앵커>' <검사대상파일>   # == 1 이어야 한다
```

**왜**: 앵커 문구가 파일의 **다른 곳에도 존재**하면, 검사 대상(그 기능의 핵심 줄)을 **통째로 지워도 테스트가 PASS** 한다 — 검증하지 않는 것을 보증한다고 주장하는 tautology(거짓 안심)다.

**실측 함정** (2026-07-13, 3회 연속 발생):
- `T6.b`: `/start`·`안내` 앵커가 SKILL.md 다른 곳에 이미 존재 → 구현 없이 PASS
- `T6.c`: `공회전` 이 배제 조건 블록에도 존재 → 적색 플래그 행을 지워도 PASS
- `T6.a`: Critical 수정이 앵커(`배제 조건`·`repo 밖`)를 오염 → **기능 본체를 지워도 PASS**
- 함정: `PPT` 단독은 count=2(두 곳) → tautology 재건. `PPT·Excel` 이어야 count=1

**한계 고백**: 이는 **리뷰 규율**이지 자동 게이트가 아니다. 정적 탐지는 앵커→파일 연결이 변수·동적이라 52개 테스트 파일에서 false-positive 늪이 된다(regex 두더지잡기). 대신 **mutation 으로 실증**하라 — 검사 대상 줄을 지워보고 테스트가 FAIL 하면 앵커가 실효 있다. `mutation-score.sh` 가 `mutation-targets.conf` 등재 `.sh` 타겟은 자동 커버(주간 cron, `MUTATION_MIN_SCORE`).

## 회귀 금지 체크리스트

본 template 도입 시 다음이 불변해야 한다:

- [ ] `skills/decomposing-ko/SKILL.md` 의 기존 Python/pytest 예시 블록은 문자 단위 무변경 (언어 중립 시그널 유지)
- [ ] decomposing-ko 의 태스크 크기 규약 (2~5분) 문구 유지
- [ ] decomposing-ko 의 AC 커버리지 표 포맷 유지
- [ ] decomposing-ko 의 TDD 5 스텝 순서 (RED → FAIL 검증 → GREEN → PASS 검증 → COMMIT) 유지

## 참조

- `skills/decomposing-ko/SKILL.md` — 본 template 의 소비자 (§테스트 컨벤션 (bash) 섹션에서 참조)
- `skills/tdd-ko/SKILL.md` — TDD 5 스텝 규약
- 선례: `scripts/tests/governance/test-rules.sh` — 본 template 의 내부 예시 모델

---

*생성: FID 20260424-decomposing-test-conventions · 2026-04-24 · bash 한정 (v0.3+ 다른 언어 템플릿 분리)*
