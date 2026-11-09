---
name: statusline-install
disable-model-invocation: true
description: devFSD HUD statusLine을 프로젝트 .claude/settings.json에 등록 (Lifecycle 진행 상태 상시 표시)
triggers:
  - "/statusline-install"
mode: auto
specops_version: 2.6.0
specops_layer: Lifecycle-Tool
reference_upstream: specops-ko 독자 추가
---

# /statusline-install

## 동작

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/statusline-install.sh"` 를 실행해 statusline.sh 절대경로를 프로젝트 `.claude/settings.json` 의 `statusLine` 키에 주입한다.

> **먼저 확인하려면** `--check` 를 붙인다 — 변경 예정 내용만 보여주고 **파일을 만들지도 고치지도 않는다**
> (exit 0 = 이미 동일 · 1 = 변경 예정). `--help` 는 사용법만 출력한다.
> 미지 인자는 조용히 설치하지 않고 `exit 2` 로 거부한다 — 오타가 사용자 설정을 바꾸면 안 된다.

- 플러그인은 statusLine을 번들 배포할 수 없으므로(Claude Code 제약) 본 command가 수동 등록을 담당한다.
- 기존 `statusLine` 있으면 `.claude/settings.json.bak` 백업 후 갱신. 다른 키는 무손상.
- 멱등 — 재실행해도 동일 결과.

## 표시 포맷

```
◆ specops · <FID> · /<step> <status>
```

- 색상: PASS/완료/DONE 초록, FAIL/BLOCK 빨강.
- session-progress.md 부재(비-specops 프로젝트) → `◆ specops-ko` (graceful).

## 참조

- `scripts/statusline.sh` — 상태줄 렌더러
- `scripts/statusline-install.sh` — 설치 핵심
- `.specops/session-progress.md` — 파싱 소스

---

*specops-ko v2.6.0 · 2026-06-15 · /statusline-install command*
