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
# 경계: 허용 목록에 있는 이름만 읽는다 — PATH·LD_PRELOAD 등 목록 밖 이름은 받지 않는다.
#   값은 글자 그대로 쓴다(명령 치환·변수 확장 없음 — eval·source 를 쓰지 않는다).
#   git 작업 트리 안의, git 이 추적하지 않는 실제 파일만 쓴다 — 커밋된 파일·심볼릭 링크로 끌어온 파일·
#   git 밖 사본(압축 풀이)은 남의 설정일 수 있어 쓰지 않는다.
#   **보안 경계가 아니다** — 재현성 장치다. 목록 안의 변수(JAVA_HOME·GRADLE_USER_HOME·NODE_OPTIONS·JAVA_TOOL_OPTIONS …)는
#   실행기나 테스트 동작을 바꿀 수 있고(가짜 java 를 가리키는 JAVA_HOME 이면 테스트 없이 exit 0 이 난다),
#   같은 일은 러너를 부르는 셸에서 export 해도 된다. 막지 않는 대신 무엇으로 돌았는지를 증거에 남긴다.

_VE_NAMES="JAVA_HOME JAVA_TOOL_OPTIONS JDK_JAVA_OPTIONS GRADLE_USER_HOME GRADLE_OPTS MAVEN_OPTS DOCKER_HOST DOCKER_CONTEXT NODE_OPTIONS NODE_EXTRA_CA_CERTS SSL_CERT_FILE REQUESTS_CA_BUNDLE HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy TZ"
_VE_FROM_FILE=" "   # local-env 에서 온 이름(공백 구분 · 앞뒤 공백 포함)

_ve_allowed() { # <이름>
  #   이름 꼴부터 본다 — 공백이 든 "JAVA_HOME JAVA_TOOL_OPTIONS" 가 아래 목록 대조(부분 문자열)를 통과해
  #   export 는 실패하고 출처만 local-env 로 적히던 것을 막는다(리뷰 재현).
  case "$1" in ''|[!A-Za-z_]*|*[!A-Za-z0-9_]*) return 1 ;; esac
  case "$1" in TESTCONTAINERS_?*) case "$1" in *[!A-Z0-9_]*) return 1 ;; *) return 0 ;; esac ;; esac
  case " $_VE_NAMES " in *" $1 "*) return 0 ;; esac
  return 1
}

# 증거에 적을 값 — 한 줄로 접고(줄바꿈이 든 값이 증거에 가짜 제목·종료 줄을 만들지 못하게) 비밀을 가린다.
#   가리는 것: 이름에 pass·pwd·secret·token·credential 이 든 대입(= 또는 :) · Bearer 값 · URL 과 프록시 값의 자격 증명.
#   남기는 것: 경로·호스트(keyStore=/path 같은 저장소 경로는 비밀이 아니다 — 이 기록이 남기려는 값이다).
#   한계: 정규식이라 전부는 못 잡는다(공백으로 띄운 `-Dpassword 값` 등) — 비밀은 환경 변수 값에 넣지 않는 것이 원칙이다.
_ve_mask() {
  printf '%s' "$1" | tr '\n\r' '  ' | sed -E \
    -e 's/([A-Za-z0-9_.-]*([Pp][Aa][Ss][Ss]|[Pp][Ww][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Tt][Oo][Kk][Ee][Nn]|[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll])[A-Za-z0-9_.-]*[=:])("[^"]*"|[^[:space:]]+)/\1***/g' \
    -e 's/([Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]+)[^[:space:]]+/\1***/g' \
    -e 's#(://)[^/[:space:]]*@#\1***@#g' \
    -e 's#^[^/@[:space:]]+:[^/@[:space:]]*@#***@#'
}

ve_apply() { # <파일>
  local file="$1" line name val bad="" badfmt=0
  [ -e "$file" ] || [ -L "$file" ] || return 0
  if [ -L "$file" ] || [ -L "$(dirname "$file")" ] || [ ! -f "$file" ]; then
    echo "WARN: $file 을 쓰지 않는다 — 심볼릭 링크(파일 또는 폴더)이거나 일반 파일이 아니다. 머신 전용 환경은 이 저장소 안의 실제 파일로 둔다" >&2
    return 0
  fi
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "WARN: $file 을 쓰지 않는다 — git 작업 트리가 아니라 이 파일이 커밋된 것인지 가릴 수 없다" >&2
    return 0
  fi
  if git ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
    echo "WARN: $file 은 git 이 추적하는 파일이라 쓰지 않는다 — 머신 전용 환경은 커밋하지 않는다(git rm --cached 후 .specops/.gitignore 에 local-env 를 더한다)" >&2
    return 0
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in *=*) ;; *) badfmt=$((badfmt + 1)); continue ;; esac
    name="${line%%=*}"; val="${line#*=}"
    if ! _ve_allowed "$name"; then
      #   파일 내용을 그대로 내보내지 않는다 — 훅은 러너 출력의 `VERIFY: PASS` 를 실행 증거로 읽는다.
      case "$name" in ''|[!A-Za-z_]*|*[!A-Za-z0-9_]*) badfmt=$((badfmt + 1)) ;; *) bad="$bad $name" ;; esac
      continue
    fi
    #   셸에 이미 있으면(빈 값 포함) 그대로 둔다
    [ -z "${!name+x}" ] || continue
    export "$name=$val" 2>/dev/null || { badfmt=$((badfmt + 1)); continue; }
    _VE_FROM_FILE="$_VE_FROM_FILE$name "
  done < "$file"
  [ -z "$bad" ] || echo "WARN: $file 의 다음 이름은 쓰지 않았다(허용 목록 밖 —$bad). 받는 이름: $_VE_NAMES TESTCONTAINERS_*" >&2
  [ "$badfmt" -eq 0 ] || echo "WARN: $file 에서 '이름=값' 꼴이 아닌 줄 ${badfmt}개를 건너뛰었다" >&2
  return 0
}

_ve_set_names() { # 설정된 허용 변수 이름을 한 줄에 하나씩 (값을 읽지 않는다 — 줄바꿈이 든 값에 속지 않게 이름만 본다)
  local n
  for n in $_VE_NAMES; do
    [ -z "${!n+x}" ] || printf '%s\n' "$n"
  done
  for n in $(compgen -v TESTCONTAINERS_ 2>/dev/null); do
    _ve_allowed "$n" && printf '%s\n' "$n"
  done
}

ve_report() {
  local names n src
  names=$(_ve_set_names)
  [ -n "$names" ] || return 0
  echo "**실행 환경** (테스트에 영향을 주는 변수 — 새 셸에는 \`셸\` 출처의 값이 없다):"
  echo ""
  for n in $names; do
    case "$_VE_FROM_FILE" in *" $n "*) src="local-env" ;; *) src="셸" ;; esac
    echo "- \`$n=$(_ve_mask "${!n-}")\` ($src)"
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
