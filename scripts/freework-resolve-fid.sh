#!/usr/bin/env bash
# 자유작업 FID 귀속/신규 판정. 종결된 lifecycle 오귀속 차단.
# Usage: freework-resolve-fid.sh <candidate-fid>
#   출력: NEW (mini-FID 생성)  |  ATTACH:<fid> (활성 FID 귀속)
set -u

fid="${1:-}"
# 1) 빈 후보 → 순수 자유작업
[ -z "$fid" ] && { echo "NEW"; exit 0; }
# 1b) FID 포맷 불량(정규식 메타문자 등) → awk 동적정규식 오판정 차단·오귀속 방지 위해 신규 처리
printf '%s' "$fid" | grep -Eq '^[0-9]{8}-[a-z0-9-]+$' || { echo "NEW"; exit 0; }

progress=".specops/session-progress.md"
[ -f "$progress" ] || { echo "ATTACH:$fid"; exit 0; }

# 2) 해당 FID 섹션의 첫 활동 줄(최신 — 섹션 헤더 바로 아래 '- ' 줄) 추출
latest=$(awk -v f="## $fid" '
  $0 ~ "^"f"( |$)" {insec=1; next}
  insec && /^## / {exit}
  insec && /^- / {print; exit}
' "$progress")

# 3) 종결 마커 검사 — 종결이면 NEW, 아니면 ATTACH
#    AC-12 의 'PR #<n>' 는 false-positive(진행중 줄 "PR #999 참조") 차단 위해 '생성' 인접 필수로 협소 적용.
#    command 슬래시 앵커(/lifecycle·/finish)로 본문 우연 매칭 배제.
#    `/finishing 완료` 도 종결이다 — 메타 스킬의 재개 통보(using-specops-ko)가 종결로 치는 목록과 같아야 한다.
if printf '%s' "$latest" | grep -qE '/(lifecycle|finish)[[:space:]]+DONE|/finishing[[:space:]]+완료|DONE[[:space:]]*\(PR|PR[[:space:]]*#[0-9]+[[:space:]]+생성'; then
  echo "NEW"
  exit 0
fi

# 4) 종결 줄이 없어도 **이미 머지된** FID 는 귀속하지 않는다 (20261114) — 사고: 종결 줄 없이 PR 로 머지된 옛 FID 에 자유작업이 귀속돼
#    그 FID 가 활성이 됐고 이후 커밋이 그 FID 의 검증 기록을 요구했다. 판정은 reconcile-check.sh(SessionStart 가 쓰는 것)와 같다 —
#    브랜치 feat/<FID> 가 머지 커밋으로 기본 브랜치에 들어갔는가. git·브랜치가 없어 판정하지 못하면 종전대로 귀속한다.
_recon="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_internal/reconcile-check.sh"
if [ -f "$_recon" ] && SPECOPS_ROOT="$(pwd)/.specops" bash "$_recon" "$fid" --hook 2>/dev/null | grep -q '이미 머지됨'; then
  echo "NEW"
else
  echo "ATTACH:$fid"
fi
