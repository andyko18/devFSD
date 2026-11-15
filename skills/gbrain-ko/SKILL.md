---
name: gbrain-ko
description: 개발 세션 인사이트를 learnings.jsonl에서 조회·요약 — 최신 10건 + 전체 개수 출력, --fid 필터링 가능
layer: 2
reference_upstream: specops-ko 독자 추가 (garrytan/gstack office-hours gbrain 패턴 한국어 재창작)
specops_version: 1.73.0
used_by: /gbrain
---

# gbrain — 세션 인사이트 조회·요약

## 개요

`scripts/gbrain-append.sh`로 누적된 `.specops/memory/learnings.jsonl` 레코드를 읽어 최신 10건을 요약 출력한다.

- 레코드에 `confidence`(low/medium/high) 필드가 있으면 조회·요약 출력에 신뢰도로 표시한다 (없으면 생략 — 기존 레코드 호환).

## 사용법

```
/gbrain [--fid FID]
```

## 프로세스

### Step 1: learnings.jsonl 존재 확인

```bash
GBRAIN_FILE="${GBRAIN_FILE:-.specops/memory/learnings.jsonl}"
if [ ! -f "$GBRAIN_FILE" ]; then
  echo "learnings.jsonl 없음 — 아직 인사이트 없음"
  exit 0
fi
```

### Step 2: 전체 개수 + 최신 10건 출력

```bash
total=$(wc -l < "$GBRAIN_FILE" | tr -d ' ')
echo "## gbrain 인사이트 요약 (전체 ${total}건)"
echo ""
echo "### 최신 10건"

parse_line() {
  local line="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$line" <<'PYEOF'
import sys, json
try:
    obj = json.loads(sys.argv[1])
    ts = obj.get("ts", "")
    fid = obj.get("fid", "")
    insight = obj.get("insight", "")
    conf = obj.get("confidence", "")
    fid_part = f" (FID: {fid})" if fid else ""
    conf_part = f" [conf:{conf}]" if conf else ""
    print(f"- [{ts}]{fid_part} {insight}{conf_part}")
except Exception:
    print(f"- [parse error] {sys.argv[1][:80]}")
PYEOF
  else
    ts=$(echo "$line" | grep -o '"ts":"[^"]*"' | cut -d'"' -f4)
    insight=$(echo "$line" | grep -o '"insight":"[^"]*"' | cut -d'"' -f4)
    fid=$(echo "$line" | grep -o '"fid":"[^"]*"' | cut -d'"' -f4)
    conf=$(echo "$line" | grep -o '"confidence":"[^"]*"' | cut -d'"' -f4)
    echo "- [$ts]${fid:+ (FID: $fid)} $insight${conf:+ [conf:$conf]}"
  fi
}

tail -10 "$GBRAIN_FILE" | while IFS= read -r line; do
  parse_line "$line"
done
```

### Step 2b: 마찰 집계 (기본 출력 — 플래그 불요)

`friction-log.jsonl` 은 `.specops/<FID>/` 마다 흩어져 쌓여 **아무도 읽지 않았다** (실측 20260807: 25개 파일 130행, 그중 R-1 89행 = 68%. 한 규칙이 25개 FID 에서 89번 울렸는데 바뀐 것 0). 데이터가 없어서가 아니라 **집계가 없어서**였다.

따라서 **`--friction` 같은 별도 플래그로 감추지 않고 기본 출력에 포함한다** — 감추면 아무도 안 친다.

```bash
echo ""
bash "${CLAUDE_PLUGIN_ROOT:-.}/scripts/gbrain-friction.sh" || true
```

- 반복 임계는 `GBRAIN_FRICTION_MIN`(기본 3 — Hermes 학습 루프의 "3회 이상 반복 → 증류" 차용).
- 기계 판독은 `--json`.
- **증류 후보는 제시일 뿐 자동 조치하지 않는다.** 게이트화 여부는 사람이 정한다 (정적 패턴 자동 판별은 클래스 B 메타 규칙에서 후보 4건 전부 오탐(4/4)으로 철회된 전례).
- **BYPASS vs receipt** — BYPASS-ENV 행수·FID수와 `.specops/*/receipts/*.json` 파일수를 대조해 우회 관성 vs 정직 중간커밋 경로 사용을 기본 출력에 포함한다.

### Step 3: --fid 필터링 (인자 지정 시)

```bash
FID_FILTER="${1:-}"
if [ -n "$FID_FILTER" ]; then
  echo ""
  echo "### FID 필터: $FID_FILTER"
  grep -F "\"fid\":\"$FID_FILTER\"" "$GBRAIN_FILE" | while IFS= read -r line; do
    parse_line "$line"
  done
fi
```

## 연계 유틸 (learning-loop)

| 스크립트 | 역할 | 호출 지점 |
|---|---|---|
| `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gbrain-append.sh` | 인사이트 1줄 기록 | performance-test-ko 학습 추출 (자동) + 수동 |
| `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gbrain-collect.sh <FID>` | handoffs/evidence 결정적 수집 | performance-test-ko 학습 추출 1단계 |
| `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gbrain-recall.sh "<질의>" [--top N]` | 토큰 중첩 관련 인사이트 조회 | specifying-ko Step 1 환류 (자동) + 수동 |
| `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gbrain-friction.sh [--json]` | friction-log 규칙별 집계 + 증류 후보(**block 기준** — warn 은 감사 기록이라 미집계) + **BYPASS vs receipt** | 본 skill Step 2b (기본 출력) |

learnings.jsonl 은 **로컬 전용** (`.specops/` 전량 gitignore — 세션 인사이트에 downstream 프로젝트 문맥이 섞여 배포 저장소 부적합). 파일은 로컬에 계속 누적되며 조회·환류 동작은 불변이다.

## 인사이트 추가

세션 중 발견한 패턴·주의사항을 추가:

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gbrain-append.sh "인사이트 내용" --fid <FID> --tags tag1,tag2 --confidence <low|medium|high>
```

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 skill 적용 |
|---|---|
| 1 **투명성** | 전체 개수 + 최신 10건 동시 출력 |
| 2 **문지기** | 파일 미존재 시 조용히 안내 후 종료 |
| 3 **깊이** | python3 json 파싱 (기본) — 큰따옴표·이스케이프 포함 insight 완전 지원 |
| 4 **주권 존중** | 조회·요약만. 삭제·수정 기능 없음 |
| 5 **한계 고백** | python3 미설치 시 grep fallback — 큰따옴표 포함 insight 깨질 수 있음 |

## 참조

- `scripts/gbrain-append.sh` — 인사이트 추가 스크립트
- `commands/gbrain.md` — 슬래시 진입점
- `.specops/memory/learnings.jsonl` — 저장소
- upstream 패턴: garrytan/gstack office-hours gbrain 누적 패턴

## 다음 skill

chain 종료. 본 skill은 조회·요약만. 인사이트 추가는 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gbrain-append.sh` 직접 호출.
