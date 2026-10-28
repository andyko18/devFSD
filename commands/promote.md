---
name: promote
disable-model-invocation: true
description: 자유작업 mini-FID(freework.md)를 lifecycle full 트리로 in-place 승격 — analyzing-ko maintain 분기 호출
triggers:
  - "/promote"
mode: ask
specops_version: 2.6.0
specops_layer: Lifecycle
reference_upstream: specops-ko 독자 추가 (본가 obra/superpowers@v5.0.7 미존재)
---

# /promote <mini-FID>

## 목적

자유작업이 만든 mini-FID(freework.md 마커만 있는 경량 트랙)를 정식 lifecycle 로 in-place 승격. 자유작업에서 시작한 일을 spec→…→PR 로 끊김 없이 이어받는다. mini-FID 디렉토리를 그대로 재사용(FID 전환 없음).

## Process

1. **진입 검증** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/promote-validate.sh <FID>` 호출. 출력 분기:
   - `REJECT:bad-format` → `"PROMOTE: <FID> 포맷 위배(YYYYMMDD-slug 아님)"`
   - `REJECT:usage` → `"Usage: /promote <mini-FID>"`
   - `REJECT:no-dir` → `"PROMOTE: <FID> 디렉토리 없음 — FID 확인 필요"`
   - `REJECT:not-mini-fid` → `"PROMOTE: <FID> 는 mini-FID 아님(freework.md 없음) — /maintain 사용"`
   - `REJECT:already-promoted` → `"PROMOTE: <FID> 이미 승격됨(spec.md 존재) — lifecycle 진행 중"`
   - `OK` → 2단계 진행
2. **freework.md 읽기** — `.specops/<FID>/freework.md` 의 type·files·prompt·요약 추출 (필드 포맷은 `templates/freework.md` 마커 규약 참조 — type/files/prompt/요약/ts 5필드).
3. **args 합성 + analyzing-ko 호출** — 아래 순서로 합성:
   ```
   <!-- entry: maintain -->
   <!-- promote-fid: <FID> -->
   <freework.md 요약/prompt 를 변경 설명으로 전개> (자유작업 mini-FID 승격)
   ```
   `devfsd:analyzing-ko` 호출. promote-fid 신호가 새 FID 생성 skip + mini-FID 재사용을 지시.
4. **이후 chain** — analyzing-ko → specifying-ko 유지보수 분기(freework 요약=시드) → clarify → … → PR. 본 command 는 진입만 책임.

## /maintain 과의 차이

| | /maintain | /promote |
|---|---|---|
| FID | 새로 생성 | 기존 mini-FID 재사용(in-place) |
| 시드 | 사용자 args | freework.md(자유작업 맥락) |
| 전제 | 임의 대상 | freework.md 존재 필수 |

---

*specops-ko v2.6.0 · 2026-06-25 · mini-FID 승격 진입 슬래시*
