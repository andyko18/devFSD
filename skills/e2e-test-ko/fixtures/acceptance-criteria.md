<!-- FID: <FID> -->
<!-- OWNER_COMMAND: /specify -->
<!-- MUTABLE_BY: /clarify (append only) -->
<!-- reference_upstream: specops-ko 독자 추가 -->
<!-- layer: Lifecycle-Artifact -->

# 수락 기준 (Acceptance Criteria) — <FID>

> 이 파일은 **스프린트 계약서**입니다.

## 계약 항목

### AC-1: 정상 인사 출력

**Given** greet-cli.sh가 .specops/<FID>/ 에 존재하고 bash 3.2+ 환경

**When** `bash .specops/<FID>/greet-cli.sh 철수` 실행

**Then** 표준출력에 `안녕하세요, 철수!` 출력되고 exit 0

**검증 방법**: `bash .specops/<FID>/greet-cli.sh 철수` 실행 후 출력 비교
**관련 FR**: FR-1
**우선순위**: must

---

### AC-2: 인자 없을 시 오류

**Given** greet-cli.sh가 .specops/<FID>/ 에 존재

**When** `bash .specops/<FID>/greet-cli.sh` 인자 없이 실행

**Then** 표준오류에 사용법 메시지 출력되고 exit 1

**검증 방법**: `bash .specops/<FID>/greet-cli.sh; echo $?` → exit code 1 확인
**관련 FR**: FR-2
**우선순위**: must

---

## 우선순위 규약

- **must**: 이 항목이 충족되지 않으면 `/verify` PASS 불가
- **should**: 가능하면 충족. 미충족 시 verify.md에 사유 기록

---

*작성: e2e-test-ko · <날짜> · FID: <FID> · 생성 커맨드: /e2e-test*
