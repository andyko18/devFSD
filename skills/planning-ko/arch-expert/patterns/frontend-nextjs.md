<!-- reference_upstream: wshobson/agents@0874a27 plugins/frontend-mobile-development/skills/nextjs-app-router-patterns/SKILL.md (MIT) — specops-ko 한국어 재작성 (20261021-arch-designer-agent) -->
# 프론트 Next.js App Router 규칙 — arch-designer-ko 보조 파일

`frontend-architecture.md` §2 라우팅 라이브러리가 Next.js App Router 일 때 arch-designer-ko 가 읽는다. React 규칙(`frontend-react.md`)도 함께 읽는다.

- 서버 컴포넌트가 기본이다. `'use client'` 는 상호작용·훅·브라우저 API 가 필요한 컴포넌트에만 붙인다 — `'use client'` 를 붙인 모듈이 import 하는 컴포넌트는 모두 클라이언트 번들에 들어가므로, 상위 모듈(레이아웃·공용 껍데기)에 붙여 그 아래 import 트리를 통째로 클라이언트로 끌어들이는 plan 은 지적한다(`children` prop 으로 넘겨받는 서버 컴포넌트는 그대로 서버에 남는다).
- 서버 컴포넌트에서 훅(useState·useEffect)을 쓰지 않는다.
- 클라이언트 컴포넌트에서 데이터를 직접 fetch 하지 않는다 — 서버 컴포넌트에서 가져오거나 서버 상태 도구를 쓴다.
- 서버 → 클라이언트 경계로 넘기는 props 는 직렬화할 수 있는 값이어야 한다(함수·클래스 인스턴스 금지). 원문 표기("Don't pass serializable data")는 거꾸로 적혀 있어 Next.js 규칙에 맞게 고쳐 적었다.
- 느린 데이터가 있는 경로에는 로딩 상태(`loading.tsx` 또는 Suspense 경계)를 둔다.
- 데이터 변경은 Server Actions 로 하고, 레이아웃 중첩은 꼭 필요한 만큼만 둔다(레이아웃마다 컴포넌트 트리가 깊어진다).
