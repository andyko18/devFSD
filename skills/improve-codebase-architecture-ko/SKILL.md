---
name: improve-codebase-architecture-ko
description: 코드베이스 파일/모듈 경계 정적 분석 — deep module 원칙(단순한 인터페이스+복잡한 구현) 기준으로 책임 과부하(800줄+)·과잉 분해(50줄 미만 클러스터) 탐지 및 split/merge 권고안 제시
layer: 2
reference_upstream: "specops-ko 독자 추가 (mattpocock improve-codebase-architecture 한국어 재창작)"
specops_version: 1.63.0
used_by: /improve-arch
---

# 코드베이스 아키텍처 개선 (improve-codebase-architecture)

<HARD-GATE>
본 skill은 분석·권고만 한다. 리팩터링 실행 금지. 변경이 필요하면 `/maintain <대상 파일>`으로 새 Lifecycle 진입.

**판정: 기계화 불가 (행위 금지형)** — 읽기 전용 분석이라 산출물이 없고, 위반(코드 변경)은 lifecycle 밖이라 관문을 지나지 않는다. 변경이 실제로 일어나면 R-1(커밋 전 verify)이 뒤늦게 잡는다.
</HARD-GATE>

## 개요

John Ousterhout의 deep module 원칙:
- **deep module** (좋음): 단순한 인터페이스 + 복잡한 구현
- **shallow module** (나쁨): 복잡한 인터페이스 + 단순한 구현

## 사용법

```
/improve-arch [경로]
```

경로 미지정 시 현재 디렉토리(`.`).

## 프로세스

### Phase 1: 파일 스캔

대상 경로의 소스 파일 목록을 수집하고 줄 수를 측정한다.

```bash
TARGET="${1:-.}"

find "$TARGET" -type f \( \
  -name "*.ts" -o -name "*.js" -o \
  -name "*.py" -o -name "*.sh" -o -name "*.go" \
\) 2>/dev/null | sort | while read -r f; do
  lines=$(wc -l < "$f" 2>/dev/null || echo 0)
  printf "%5d %s\n" "$lines" "$f"
done | sort -rn
```

**확장자 기본값**: `.ts .js .py .sh .go`
추가 언어가 필요하면 find 조건에 `-o -name "*.rs"` 등을 추가한다.

### Phase 2: 판정

**책임 과부하 (split 권고)** — 800줄 초과 파일:

```bash
find "$TARGET" -type f \( \
  -name "*.ts" -o -name "*.js" -o \
  -name "*.py" -o -name "*.sh" -o -name "*.go" \
\) 2>/dev/null | while read -r f; do
  lines=$(wc -l < "$f" 2>/dev/null || echo 0)
  [ "$lines" -gt 800 ] && printf "SPLIT 후보: %s (%d 줄)\n" "$f" "$lines"
done
```

**과잉 분해 (merge 권고)** — 동일 디렉토리에 50줄 미만 파일 3개 이상:

```bash
find "$TARGET" -type f \( \
  -name "*.ts" -o -name "*.js" -o \
  -name "*.py" -o -name "*.sh" -o -name "*.go" \
\) 2>/dev/null | while read -r f; do
  lines=$(wc -l < "$f" 2>/dev/null || echo 0)
  [ "$lines" -lt 50 ] && dirname "$f"
done | sort | uniq -c | sort -rn | \
  awk '$(1) >= 3 { printf "MERGE 후보: %s (%d개 소형 파일)\n", $(2), $(1) }'
```

### Phase 3: deep/shallow 판정

각 후보 파일에 대해 public 심볼 수를 추정해 deep/shallow 여부를 판정한다.

```bash
# 아래 코드는 루프 내 단편임 — $f는 외부 루프에서 주입. 단독 실행 불가.
# public 심볼 수 추정 (언어별 패턴)
symbols=$(grep -cE "^(export|def|func|pub|public) " "$f" 2>/dev/null || echo 0)
lines=$(wc -l < "$f")
ratio=$((lines / (symbols + 1)))

# 판정
# - deep: ratio > 20 → 좋은 추상화 (줄 많음 + 심볼 적음)
# - shallow: ratio ≤ 20 → 레이어만 추가, 가치 낮음
[ "$ratio" -gt 20 ] && echo "deep (비율 $ratio)" || echo "shallow (비율 $ratio)"
```

> **한계**: public 심볼 추정은 bash grep 기반으로 언어별 정확도 차이가 있다. 참고 지표로만 활용.

### Phase 4: 권고안 출력 (stdout)

분석 결과를 다음 markdown 테이블 형식으로 stdout에 출력한다.

```
## 아키텍처 분석 결과

> 대상: <TARGET> | 분석 파일: N개

### Split 권고 (책임 과부하 — 800줄 초과)

| 파일 | 줄 수 | deep/shallow | 권고 |
|---|---|---|---|
| src/foo.ts | 1200 | deep | 기능 그룹별 2~3개 모듈 분리 |

### Merge 권고 (과잉 분해 — 50줄 미만 3개 이상)

| 디렉토리 | 소형 파일 수 | 권고 |
|---|---|---|
| src/utils/ | 5개 | 연관 파일 통합 후 단일 모듈로 |

### 다음 단계

각 항목에 대해 리팩터링이 필요하면:
  /maintain <파일경로>
```

후보가 없으면 다음을 출력한다:

```
아키텍처 분석 완료 — split/merge 권고 없음.
현재 구조가 deep module 원칙을 잘 따르고 있습니다.
```

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 skill 적용 |
|---|---|
| 1 **투명성** | 판정 근거(줄 수·심볼 수·비율)를 권고안에 함께 표시 |
| 2 **문지기** | 리팩터링 실행 금지 — 진단만. 실행은 사용자 `/maintain` 진입 |
| 3 **깊이** | 800/50 임계값은 경험적 기준임을 Phase 4 출력에 명시 |
| 4 **주권 존중** | merge/split 실행은 사용자 결정. 강제 없음 |
| 5 **한계 고백** | public 심볼 추정은 bash grep 기반 — Phase 3에 한계 명시 |

## 참조

- `commands/improve-arch.md` — 슬래시 진입점
- 설계 원칙: John Ousterhout "A Philosophy of Software Design" Chapter 4 (Modules Should Be Deep)
- upstream 패턴: mattpocock improve-codebase-architecture

## 다음 skill

분석 완료 후 개선이 필요한 파일:
```
/maintain <파일경로>
```

본 skill은 chain 종료. 후속 skill 없음.
