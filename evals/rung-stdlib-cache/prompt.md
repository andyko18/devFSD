---
description: 가드 — 직접 만든 캐시 클래스 대신 표준 라이브러리를 먼저 쓰는가 (실제 기능 요청 · 플러그인이 기본 동작을 망치지 않는지 · 20261117 실측 Δ 0 천장)
tags: [rung, guard]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
---

환율 조회가 같은 통화로 여러 번 불려서 외부 API 호출이 너무 많아. 한 번 실행하는 동안 같은 통화는 다시 호출하지 않게 고쳐줘. 어떤 방식으로 고치는지도 같이 알려줘.
