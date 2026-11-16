#!/usr/bin/env bash
# verify-env.sh — 검증 러너의 실행 환경: 로컬 환경 파일 적용 + 증거 기록 (source 전용)
#
# 왜 (20261116 하류 실주행): 사내망·Colima·특정 JDK 를 쓰는 머신에서는 테스트가 환경 변수 없이는 돌지 않는다
#   (DOCKER_HOST · JAVA_TOOL_OPTIONS 의 신뢰 저장소 …). 모델이 호출마다 손으로 붙여 VERIFY: PASS 를 냈는데
#   증거에는 맨 명령만 남았고, 다음 세션(새 셸)에서는 같은 명령이 24건 중 21건 실패했다.
#
# 하는 일:
#   ve_apply <파일>  — `.specops/local-env`(이름=값 · 커밋하지 않는 머신 전용 파일)의 허용된 변수를 export 한다.
#                      셸에 이미 있는 값은 덮지 않는다(이번 세션이 직접 준 값이 우선).
#   ve_report        — 테스트에 영향을 주는 변수 가운데 설정된 것을 출처(셸·local-env)와 함께 마크다운으로 낸다.
#   ve_shell_names   — 그중 셸에서만 온 이름(새 셸에는 없을 값).
#
# 경계: 허용 목록에 있는 이름만 읽는다 — PATH·LD_PRELOAD 처럼 실행 파일을 바꿔치는 변수는 받지 않는다.
#   값은 글자 그대로 쓴다(명령 치환·변수 확장 없음 — eval·source 를 쓰지 않는다).
#   git 이 추적하는 파일은 쓰지 않는다 — 커밋된 파일이 다른 사람의 검증 환경을 바꾸면 안 된다.
#   성격은 보안 경계가 아니라 재현성이다: 허용된 변수(JAVA_TOOL_OPTIONS 등)로도 테스트 동작은 바뀔 수 있고,
#   같은 일은 러너를 부르는 셸에서 export 해도 된다. 그래서 무엇으로 돌았는지를 증거에 남긴다.

_VE_NAMES="JAVA_HOME JAVA_TOOL_OPTIONS JDK_JAVA_OPTIONS GRADLE_USER_HOME GRADLE_OPTS MAVEN_OPTS DOCKER_HOST DOCKER_CONTEXT NODE_OPTIONS NODE_EXTRA_CA_CERTS SSL_CERT_FILE REQUESTS_CA_BUNDLE HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy TZ"
_VE_FROM_FILE=" "   # local-env 에서 온 이름(공백 구분 · 앞뒤 공백 포함)

_ve_allowed() { # <이름>
  case "$1" in
    TESTCONTAINERS_*) case "$1" in *[!A-Z0-9_]*) return 1 ;; *) return 0 ;; esac ;;
  esac
  case " $_VE_NAMES " in *" $1 "*) return 0 ;; esac
  return 1
}

# 증거에 적을 값 — 비밀번호류 대입과 URL 의 자격 증명을 가린다(경로·호스트는 남긴다).
_ve_mask() {
  printf '%s' "$1" | sed -E \
    -e 's/([A-Za-z0-9_.-]*([Pp]assword|[Pp]asswd|[Ss]ecret|[Tt]oken|[Kk]ey)[A-Za-z0-9_.-]*=)[^[:space:]]+/\1***/g' \
    -e 's#(://)[^/@[:space:]]+@#\1***@#g'
}

ve_apply() { # <파일>
  local file="$1" line name val bad=""
  [ -f "$file" ] || return 0
  if git ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
    echo "WARN: $file 은 git 이 추적하는 파일이라 쓰지 않는다 — 머신 전용 환경은 커밋하지 않는다(git rm --cached 후 .specops/.gitignore 에 local-env 를 더한다)" >&2
    return 0
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in *=*) ;; *) bad="$bad ${line%% *}"; continue ;; esac
    name="${line%%=*}"; val="${line#*=}"
    if ! _ve_allowed "$name"; then bad="$bad $name"; continue; fi
    #   셸에 이미 있으면(빈 값 포함) 그대로 둔다
    if eval "[ -n \"\${$name+x}\" ]"; then continue; fi
    export "$name=$val"
    _VE_FROM_FILE="$_VE_FROM_FILE$name "
  done < "$file"
  [ -z "$bad" ] || echo "WARN: $file 의 다음 줄은 쓰지 않았다(허용 목록 밖 —$bad). 받는 이름: $_VE_NAMES TESTCONTAINERS_*" >&2
  return 0
}

_ve_set_names() { # 설정된 허용 변수 이름을 한 줄에 하나씩
  local n
  for n in $_VE_NAMES; do
    if eval "[ -n \"\${$n+x}\" ]"; then printf '%s\n' "$n"; fi
  done
  env | sed -n 's/^\(TESTCONTAINERS_[A-Z0-9_]*\)=.*/\1/p' | sort -u
}

ve_report() {
  local names n v src
  names=$(_ve_set_names)
  [ -n "$names" ] || return 0
  echo "**실행 환경** (테스트에 영향을 주는 변수 — 새 셸에는 \`셸\` 출처의 값이 없다):"
  echo ""
  for n in $names; do
    eval "v=\${$n}"
    case "$_VE_FROM_FILE" in *" $n "*) src="local-env" ;; *) src="셸" ;; esac
    echo "- \`$n=$(_ve_mask "$v")\` ($src)"
  done
  echo ""
}

ve_shell_names() {
  local n out=""
  for n in $(_ve_set_names); do
    case "$_VE_FROM_FILE" in *" $n "*) ;; *) out="$out${out:+ }$n" ;; esac
  done
  printf '%s' "$out"
}
