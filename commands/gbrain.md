---
name: gbrain
disable-model-invocation: true
description: 개발 세션 인사이트 조회·요약 슬래시 — gbrain-ko 호출. learnings.jsonl 최신 10건 + 전체 개수 출력.
triggers:
  - "/gbrain"
mode: ask
specops_version: 2.6.0
specops_layer: Lifecycle-Tool
reference_upstream: specops-ko 독자 추가 (garrytan/gstack office-hours gbrain 패턴 한국어 재창작)
---

# /gbrain [--fid <FID>]

## 목적

`.specops/memory/learnings.jsonl`에 누적된 개발 인사이트를 조회·요약한다.

## Process

1. **즉시 `devfsd:gbrain-ko` 호출** — `--fid` 인자를 그대로 전달
2. learnings.jsonl 읽기 → 전체 개수 + 최신 10건 출력
3. **마찰 집계** — `scripts/gbrain-friction.sh` 로 `friction-log.jsonl` 을 규칙별 집계 + 증류 후보 제시 (기본 출력, 플래그 불요). **증류 후보는 `block`(차단) 건수 기준**입니다 — `warn` 은 posttool 감사 기록이라 성공한 커밋에도 붙으므로 후보 판정에 세지 않습니다(집계 표에는 그대로 남습니다). 설계상 `severity: warn` 인 규칙(R-3·R-4·R-5)에게 "게이트를 더 세게 걸까?"를 묻지 않기 위함입니다. **BYPASS vs receipt** 요약(BYPASS-ENV 행수·FID수 vs `receipts/*.json` 파일수)도 기본 출력에 포함됩니다.
4. `--fid FID` 지정 시 해당 FID 레코드만 추가 출력

## 사용 예

```
/gbrain

→ gbrain-ko 호출
→ 전체 N건, 최신 10건 출력
```

```
/gbrain --fid 20260519-foo

→ 최신 10건 + "20260519-foo" FID 레코드 필터 출력
```

## 인사이트 추가

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gbrain-append.sh "인사이트 내용" --fid <FID> --tags tag1,tag2 --confidence <low|medium|high>
```

연계: `gbrain-collect.sh` (추출 수집) · `gbrain-recall.sh` (환류 조회) — 상세는 `skills/gbrain-ko/SKILL.md` §연계 유틸.

## 안티패턴

- **인사이트 수정·삭제** — 본 슬래시는 읽기 전용
- **gbrain-append.sh 우회 직접 쓰기** — 추가는 `gbrain-append.sh` 경유만 (performance-test-ko 학습 추출 자동 + 수동 호출)

## 참조

- `skills/gbrain-ko/SKILL.md` — 실행 skill
- `scripts/gbrain-append.sh` — 인사이트 추가 스크립트
- `.specops/memory/learnings.jsonl` — 저장소

---

*specops-ko v2.6.0 · 2026-05-19 · garrytan/gstack office-hours gbrain 패턴 한국어 재창작*
