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
  local file="$1" line name val bad="" badfmt=0 stale=""
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
    #   경로를 가리키는 변수인데 그 경로가 없으면 낡은 값이다(JDK 를 바꿨다 · 임시 신뢰 저장소가 지워졌다) — 적용하지 않는다.
    case "$name" in JAVA_HOME|GRADLE_USER_HOME|SSL_CERT_FILE|NODE_EXTRA_CA_CERTS|REQUESTS_CA_BUNDLE)
      if [ ! -e "$val" ]; then stale="$stale $name"; continue; fi ;;
    esac
    export "$name=$val" 2>/dev/null || { badfmt=$((badfmt + 1)); continue; }
    _VE_FROM_FILE="$_VE_FROM_FILE$name "
  done < "$file"
  [ -z "$bad" ] || echo "WARN: $file 의 다음 이름은 쓰지 않았다(허용 목록 밖 —$bad). 받는 이름: $_VE_NAMES TESTCONTAINERS_*" >&2
  [ "$badfmt" -eq 0 ] || echo "WARN: $file 에서 '이름=값' 꼴이 아닌 줄 ${badfmt}개를 건너뛰었다" >&2
  [ -z "$stale" ] || echo "WARN: $file 의 다음 값은 가리키는 경로가 없어 쓰지 않았다(낡은 값 —$stale). 그 줄을 고치거나 지운다" >&2
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

# ve_save <파일> — 통과한 검증에서 셸에만 있던 값을 local-env 로 남긴다(파일이 아직 없을 때만).
#   모델에게 안내만 하면 쓰지 않는다(하류 2회차 실주행: 안내 줄이 자식 세션에 2번 떴지만 파일은 만들어지지 않았다).
#   통과한 실행의 값만 굳힌다 — 호출자가 PASS 를 확정한 뒤 부른다. 판정·종료 코드에 영향을 주지 않는다(전부 fail-open).
#   저장하지 않는 값: 가림 대상(비밀번호·토큰·자격 증명이 든 값)·줄바꿈이 든 값 — 이름만 알린다.
#   커밋되지 않게: 이미 무시되는 경로가 아니면 이 저장소의 .git/info/exclude(로컬 전용)에 한 줄 더한다. 추적 파일은 건드리지 않는다.
# 저장해도 되는 값인가 — 가림보다 넓게 본다(증거에는 가려서 적으면 되지만, 파일에는 평문이 남는다).
#   비밀로 보이는 낱말(pass·pwd·pw·secret·token·credential·key·login·auth·sig·pat·user(name)=)이 들었거나
#   URL·프록시 값에 `이름:암호@` 가 들었으면 저장하지 않는다. `ssh://deploy@host` 처럼 이름만 있는 것은 저장한다.
#   한계: 낱말 없이 값만 띄운 비밀은 못 잡는다 — 비밀은 환경 변수 값에 넣지 않는 것이 원칙이다.
_ve_sensitive() {
  case "$1" in *$'\n'*|*$'\r'*) return 0 ;; esac
  printf '%s' "$1" | grep -Eiq 'pass|pwd|(^|[^a-z])pw([^a-z]|$)|secret|token|credential|key|login|auth|sig=|(^|[^a-z])pat([^a-z]|$)|user(name)?=|bearer|basic ' && return 0
  printf '%s' "$1" | grep -Eq '(://|^)[^/@[:space:]]+:[^/@[:space:]]*@' && return 0
  return 1
}

ve_save() { # <파일>
  local file="$1" names n v keep="" skip="" body="" excl
  [ ! -e "$file" ] && [ ! -L "$file" ] || return 0
  [ -d "$(dirname "$file")" ] && [ ! -L "$(dirname "$file")" ] || return 0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  names=$(ve_shell_names)
  [ -n "$names" ] || return 0
  for n in $names; do
    v="${!n-}"
    if _ve_sensitive "$v"; then skip="$skip${skip:+ }$n"; continue; fi
    body="$body$n=$v
"
    keep="$keep${keep:+ }$n"
  done
  if [ -n "$keep" ]; then
    if ! git check-ignore -q -- "$file" 2>/dev/null; then
      excl=$(git rev-parse --git-path info/exclude 2>/dev/null) || excl=""
      #   같은 줄이 이미 있으면 더하지 않는다. 파일이 줄바꿈 없이 끝나면 줄바꿈부터 쓴다(사용자의 마지막 규칙에 이어 붙지 않게).
      if [ -n "$excl" ] && ! grep -qxF -- "/$file" "$excl" 2>/dev/null; then
        mkdir -p "$(dirname "$excl")" 2>/dev/null
        if [ -s "$excl" ] && [ -n "$(tail -c 1 "$excl" 2>/dev/null)" ]; then printf '\n' >> "$excl" 2>/dev/null; fi
        printf '%s\n' "/$file" >> "$excl" 2>/dev/null
      fi
      git check-ignore -q -- "$file" 2>/dev/null || { echo "NOTE: 이 검증은 셸에만 있는 환경 변수($names)와 함께 통과했다 — $file 을 git 이 무시하게 만들지 못해 저장하지 않았다(.specops/.gitignore 에 local-env 를 더한 뒤 '이름=값' 으로 적으면 다음 세션이 그대로 쓴다)" >&2; return 0; }
    fi
    ( umask 077; { printf '# 이 머신 전용 실행 환경 — 검증 러너가 통과한 실행의 셸 값을 저장했다(커밋하지 않는다 · 값은 글자 그대로)\n'; printf '%s' "$body"; } > "$file" ) 2>/dev/null || return 0
    echo "NOTE: 이 검증은 셸에만 있던 환경 변수와 함께 통과했다 — 다음 세션(새 셸)도 같은 값으로 돌도록 $file 에 저장했다: $keep${skip:+ · 저장하지 않음(비밀·줄바꿈이 든 값 — 필요하면 직접 설정): $skip}" >&2
  else
    echo "NOTE: 이 검증은 셸에만 있는 환경 변수($skip)와 함께 통과했다 — 비밀이나 줄바꿈이 든 값이라 $file 에 저장하지 않았다. 새 셸에서는 결과가 다를 수 있다" >&2
  fi
  return 0
}
