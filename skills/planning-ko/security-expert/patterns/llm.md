<!-- reference_upstream: addyosmani/agent-skills@aeac41d skills/security-and-hardening (SKILL.md · references/hardening-patterns.md) · references/security-checklist.md (OWASP Top 10 for LLM Applications 2025 대응표) (MIT) — specops-ko 한국어 재작성 -->
# 위험 기능 — LLM 호출

plan 이 LLM(챗봇·요약·에이전트·RAG)을 부르거나 그 출력을 쓸 때 읽는다. LLM 은 새 공격 표면이다 — plan 에 아래 결정이 적혀 있는지 본다.

- 모델 출력은 신뢰할 수 없는 입력이다(LLM05). `eval`·SQL·셸 명령·`innerHTML`·파일 경로에 넣지 않는다 — 방어적으로 파싱하고 스키마로 검증한 뒤 인코딩해서 쓴다.
- 프롬프트는 가로채일 수 있다(LLM01). 사용자 메시지·가져온 웹 페이지·PDF 처럼 컨텍스트에 들어간 신뢰할 수 없는 텍스트가 지시를 담을 수 있다 — 시스템 프롬프트는 보안 경계가 아니므로 권한은 코드에서 강제한다.
- 비밀·다른 테넌트의 데이터·시스템 프롬프트 전문을 컨텍스트에 넣지 않는다(LLM02·LLM07) — 시스템 프롬프트는 샌다고 가정한다.
- 모델이 부르는 도구의 권한을 좁히고 도구 인자마다 검증하며, 되돌릴 수 없는 동작은 사람 확인을 거친다(LLM06).
- RAG 임베딩은 테넌트별로 나누고 색인 전에 문서를 검증한다(LLM08).
- 토큰 수·요청률·반복·재귀 깊이에 상한을 둔다(LLM10) — 상한 없는 에이전트 루프는 비용 폭주와 서비스 거부다.
