<!-- reference_upstream: wshobson/agents@0874a27 plugins/frontend-mobile-development/skills/react-state-management/SKILL.md (MIT) — specops-ko 한국어 재작성 (20261021-arch-designer-agent) -->
# 프론트 React 상태 관리 규칙 — arch-designer-ko 보조 파일

`frontend-architecture.md` §1 주 프레임워크가 React 또는 Next.js 일 때 arch-designer-ko 가 읽는다.

- 상태를 다섯 갈래로 나눠 각자 맞는 자리에 둔다: 컴포넌트 지역 상태 · 여러 컴포넌트가 함께 쓰는 전역 상태 · 서버 상태(원격 데이터·캐시) · URL 상태(경로 인자·검색어) · 폼 상태. plan 의 새 상태가 어느 갈래인지 적혀 있어야 한다.
- 서버 상태는 서버 상태 도구(React Query·SWR·RTK Query 등) 한 곳이 관리한다. 같은 원격 데이터를 전역 스토어에 복제해 저장하는 plan 은 지적한다.
- 전역 상태를 남용하지 않는다 — 한 화면에서만 쓰는 상태는 그 컴포넌트 가까이 둔다.
- 다른 상태에서 계산할 수 있는 값(합계·필터 결과·개수)은 저장하지 않고 계산한다.
- 상태는 불변 갱신으로 바꾼다(직접 변경 금지). 깊게 중첩된 데이터는 정규화(평평하게)해 갱신을 쉽게 한다.
- 갈래마다 주 도구를 하나만 쓴다 — 같은 갈래에 두 라이브러리를 섞는 plan 은 지적한다.
