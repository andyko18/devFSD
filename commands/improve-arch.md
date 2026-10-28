---
name: improve-arch
disable-model-invocation: true
description: 코드베이스 아키텍처 분석 슬래시 — improve-codebase-architecture-ko 호출. deep module 원칙 기준 split/merge 권고안 제시.
triggers:
  - "/improve-arch"
mode: ask
specops_version: 2.6.0
specops_layer: Lifecycle-Tool
reference_upstream: specops-ko 독자 추가 (mattpocock improve-codebase-architecture 한국어 재창작)
---

# /improve-arch [--lean] [<경로>]

## 목적

코드베이스 파일/모듈 경계를 정적 분석해 deep module 원칙 위반(책임 과부하·과잉 분해)을 탐지하고 split/merge 권고안을 제시한다.

## Process

1. **즉시 `devfsd:improve-codebase-architecture-ko` 호출** — 전달된 `<경로>`를 분석 대상으로 제공
2. 4단계 정적 분석 진행 (find + wc + grep)
3. 권고안 stdout 출력
4. 필요 시 `/maintain <파일>` 진입 안내

## `--lean` — 과잉 설계 감사 (repo 전체 · 읽기 전용)

`--lean` 이 붙으면 deep module 분석 대신 **지울 수 있는 것**만 찾는다(오픈소스 DietrichGebert/ponytail 의 `ponytail-audit` 번안). skill 호출 없이 아래 절차를 직접 수행한다 — 아무것도 적용하지 않는다.

1. **탐색** — 한 곳에서 뜯어 낼 수 있는 것: 표준 라이브러리·플랫폼이 이미 하는 일을 하는 의존성, 구현이 하나뿐인 인터페이스, 제품이 하나뿐인 팩토리, 위임만 하는 래퍼, 한 가지만 export 하는 파일, 죽은 플래그·설정, 손으로 만든 stdlib, 이 repo 안에 이미 있는 헬퍼와 중복되는 코드
2. **`delete:` 전 확인** — 지우자고 쓰기 전에 심볼을 트리 전체(테스트·fixture·문자열/동적 참조 포함)에서 grep 한다
3. **출력** — 가장 크게 자르는 순으로 번호를 매긴다(사용자가 "2번, 5번 고쳐" 라고 말할 수 있게): `<N>. <tag> <자를 것>. <대체>. [경로]` — 태그는 `delete:` · `stdlib:` · `native:` · `reuse:` · `yagni:` · `shrink:`. 끝에 `net: -<N> lines, -<M> deps possible.` 자를 것이 없으면 `Lean already. Ship.`
4. **장부** — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/scan-shortcuts.sh` 결과(`shortcut:` 부채)를 이어 붙인다
5. **범위** — 과잉 설계·복잡도만 본다. 정확성·보안·성능은 범위 밖(일반 리뷰로 보낸다). 검증·에러 처리·보안·접근성, AC 가 요구하는 테스트와 한 번의 실행 가능한 자체 검사는 **절감 대상이 아니다**. 고칠 항목이 정해지면 `/maintain-lite <번호 항목>` 으로 넘긴다

## 사용 예

```
/improve-arch src/

→ improve-codebase-architecture-ko 호출
→ src/ 내 소스 파일 스캔 (.ts .js .py .sh .go)
→ split/merge 권고 테이블 출력
```

```
/improve-arch
(인자 없음 — 현재 디렉토리)
```

## 안티패턴

- **리팩터링 직접 실행** — 본 슬래시는 분석만. 변경은 `/maintain <파일>` 진입
- **대용량 프로젝트 전체 스캔** — 필요한 하위 경로만 지정 권장

## 참조

- `skills/improve-codebase-architecture-ko/SKILL.md` — 실행 skill
- John Ousterhout "A Philosophy of Software Design" — deep module 원칙

---

*specops-ko v2.6.0 · 2026-05-19 · mattpocock improve-codebase-architecture 한국어 재창작*
