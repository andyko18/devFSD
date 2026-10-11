#!/usr/bin/env bash
# 테스트 스위트가 **저장소 소스 파일을 변수로 통째 캡처해 단언 대상으로 쓰는 형태**를 금지한다.
# 왜: macOS CI 에서 그 명령치환이 간헐적으로 첫 줄만 반환해 정적 문안 검사가 거짓 FAIL 을 냈다
#   (main 2건 + PR 1건 실측 · 재실행 시 통과). 판정은 파일을 직접 grep 해야 절단에 면역이다.
#   설계 이력·기각한 후보는 FID 20260912-pretool-src-capture-flaky 아티팩트와 커밋 메시지에 있다.
#
# ★★ 이 주석에 **취약 형태의 실행 가능한 예시를 쓰지 마라.** 종전 정규식은 주석줄도 잡아서,
#   이 파일과 다른 스위트 양쪽에서 자기검출 false-FAIL 을 냈다(실측: 가드 자신 → 162/163 red ·
#   `test-pretool.sh:700` 에 "종전 형태" 문서화 주석 1줄 → rc=1). 아래 정규식은 **주석줄을 제외**하지만
#   코드 뒤 트레일링 주석까지 거르지는 못한다 — 예시는 서술로만 남긴다.
# ★★ 자기 파일을 스캔에서 **제외하지 않는다.** 제외하면 이 파일에 진짜 취약 줄이 들어와도 영영
#   못 잡는다(실측: 자기 제외 필터 + 진짜 취약 줄 → 검출 0건). 가드가 자기 결함에 눈감는 구조는
#   이 저장소가 v1.88.0 에서 고친 병과 같은 계열이다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$PLUGIN" || exit 1

# T1.pre 자기 위치 검증 — 이게 없으면 cd 가 빗나갈 때 스캔 대상 0개로 **조용히 PASS** 한다
#   (실측: mktemp 디렉터리에서 돌리니 취약 줄이 버젓이 있는데 PASS=1 FAIL=0).
#   임계 50 근거: 현행 스캔 대상 176개 — 72% 가 사라져야 걸리므로 정상 축소로는 오탐하지 않는다.
_n_scanned=$(find scripts/tests -name '*.sh' -type f 2>/dev/null | wc -l | tr -d ' ')
if [ ! -d scripts/tests ] || [ "${_n_scanned:-0}" -lt 50 ]; then
  echo "FAIL T1.pre 스캔 대상 이상 — scripts/tests 부재이거나 파일 ${_n_scanned:-0}개(<50). 가드가 공허 PASS 할 조건"
  echo "---"; echo "PASS=0 FAIL=1"; exit 1
fi

# T1.a 세 축의 합집합. 하나라도 빼면 실제로 쓰이는 형태를 놓친다(각 축 되돌려-관찰로 실증).
#   ① spec §성공지표 M-1 의 정의 `^_[A-Z_]*=$(cat "` — **정의가 곧 계약**이라 그대로 구현한다.
#   ② 자기 위치에서 경로를 계산해 읽는 관용구(BASH_SOURCE·$(cd·pwd). 주석줄 제외 내장.
#   ③ 저장소 루트 변수(PLUGIN 등) 경유 소스 디렉터리 읽기 — 이 저장소 스위트 **150/176** 이
#      `PLUGIN=$(cd …)` 를 정의한다. 즉 ③이 없으면 **가장 자연스러운 작성법**이 통과한다.
hits=$( { grep -rnE '^[[:space:]]*_[A-Z_]*=\$\(cat "' scripts/tests --include='*.sh' 2>/dev/null
          grep -rnE '^[[:space:]]*[^#[:space:]][^#]*[A-Za-z_][A-Za-z0-9_]*=\$\(cat "[^)]*(BASH_SOURCE|\$\(cd |pwd\))' scripts/tests --include='*.sh' 2>/dev/null
          grep -rnE '^[[:space:]]*[^#].*=\$\(cat "\$\{?(PLUGIN|HERE|ROOT|REPO|script_dir)\}?/(hooks|scripts|skills|commands|agents|templates)/' scripts/tests --include='*.sh' 2>/dev/null
        } | sort -u )
if [ -z "$hits" ]; then
  PASS=$((PASS+1)); echo "PASS T1.a 저장소 소스 파일 캡처 대입 0건"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a 저장소 소스 파일 캡처 대입 검출:"; printf '%s\n' "$hits" | head -5
  echo "  → 변수에 담지 말고 파일을 직접 grep 하라 (macOS CI 간헐 절단에 면역)"
fi

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
