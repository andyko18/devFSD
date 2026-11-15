#!/usr/bin/env bash
# specops-ko v0.2 묶음 3 · 훅 guard 유틸리티
# 각 훅 첫 줄에서 `|| exit 0` 로 호출 — 비활성화 시 조용히 종료
# Usage: is-hook-enabled.sh <hook-name>
# Exit: 0 = 활성 또는 config 없음(default) / 1 = 비활성 / 2 = 사용법 오류
# Env  : SPECOPS_CONFIG (기본 .specops/config.yaml), SPECOPS_YAML_WARNED (1회 경고 가드)
set -u

if [ "$#" -ne 1 ]; then
  echo "usage: is-hook-enabled.sh <hook-name>" >&2
  exit 2
fi

HOOK=$1
# SPECOPS_GOVERNANCE_PROFILE ENV 프리셋 (최우선 — config.yaml·pyyaml 불요)
# 우선순위: ENV > config.yaml profile > hooks.enabled > default strict
PROFILE_ENV="${SPECOPS_GOVERNANCE_PROFILE:-}"
if [ -n "$PROFILE_ENV" ]; then
  case "$PROFILE_ENV" in
    strict) exit 0 ;;
    standard)
      case "$HOOK" in
        pretool-governance|posttool-governance|stop-governance|session-start) exit 0 ;;
        *) exit 1 ;;
      esac ;;
    minimal)
      case "$HOOK" in
        pretool-governance|session-start) exit 0 ;;
        *) exit 1 ;;
      esac ;;
    *)
      echo "⚠️  is-hook-enabled: SPECOPS_GOVERNANCE_PROFILE='$PROFILE_ENV' 미지원 프리셋 — default strict 적용" >&2
      exit 0 ;;
  esac
fi
CONFIG=${SPECOPS_CONFIG:-.specops/config.yaml}

# config 파일 없음 → default enabled (strict 동작 유지)
if [ ! -f "$CONFIG" ]; then
  exit 0
fi

# python3 또는 pyyaml 부재 → 한계 고백, default enabled + stderr 1회 경고
#   탐침도 작업 폴더를 import 경로에서 뺀다 (20261114) — `python3 -c` 는 cwd 를 sys.path 맨 앞에 두므로, 빼지 않으면
#   config 가 있는 저장소의 yaml.py 가 Bash 호출마다 실행된다(아래 파싱 단계는 이미 뺀다).
_NOCWD='import sys, os; _c = os.getcwd(); sys.path[:] = [p for p in sys.path if p not in ("", ".", _c)]'
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "$_NOCWD; import yaml" 2>/dev/null; then
  if [ -z "${SPECOPS_YAML_WARNED:-}" ]; then
    echo "⚠️  is-hook-enabled: pyyaml 미설치, config 무시 (전체 훅 default enabled)" >&2
    export SPECOPS_YAML_WARNED=1
  fi
  exit 0
fi

# 파싱
python3 - "$CONFIG" "$HOOK" <<'PYEOF'
import sys, os
_c = os.getcwd()
sys.path[:] = [p for p in sys.path if p not in ("", ".", _c)]
import yaml
try:
    with open(sys.argv[1]) as f:
        c = yaml.safe_load(f) or {}
except Exception as e:
    sys.stderr.write(f"⚠️  is-hook-enabled: config 파싱 실패 ({e}), default enabled\n")
    sys.exit(0)

# 구조가 예상과 달라도 꺼지지 않는다 (20261114) — 매핑이 아닌 값(목록·문자열·수)은 "설정 없음"으로 읽는다.
#   종전엔 .get 이 없는 값에서 예외로 rc 1 이 나갔고, 호출부는 rc 1 을 "비활성"으로 읽어 훅 전체가 조용히 꺼졌다.
#   rc 1 은 아래 두 곳(프로파일의 전체 끄기 · 개별 enabled: false)에서만 낸다.
def _map(x):
    return x if isinstance(x, dict) else {}

try:
    c = _map(c)
    hook = sys.argv[2]
    profile_name = c.get('profile', 'strict')
    profiles = _map(c.get('profiles'))

    # profile.enforce_all_hooks=true → 무조건 활성 (개별 hooks.<name>.enabled 무시)
    # profile.enforce_all_disabled=true → 무조건 비활성 (none profile 의미 보장)
    prof = _map(profiles.get(profile_name)) if isinstance(profile_name, str) else {}
    if prof.get('enforce_all_hooks') is True:
        sys.exit(0)
    if prof.get('enforce_all_disabled') is True:
        sys.exit(1)

    # 개별 hooks.<name>.enabled 확인 (기본값 True) — false·0 만 끈다(빈 값·그 밖의 값은 끄지 않는다)
    hc = _map(_map(c.get('hooks')).get(hook))
    v = hc.get('enabled', True)
    sys.exit(1 if (isinstance(v, (bool, int)) and v == 0) else 0)
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write(f"⚠️  is-hook-enabled: config 구조 해석 실패 ({e}), default enabled\n")
    sys.exit(0)
PYEOF
