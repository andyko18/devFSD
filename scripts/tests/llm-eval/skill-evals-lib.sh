#!/usr/bin/env bash
# library-only
# skill 별 eval 데이터 파일(trigger-queries.json · evals.json) 스키마 판정 — run-skill-evals.sh · test-skill-evals.sh 공용
# 소스 전용. 통과 시 무출력 rc=0 · 위반 시 사유 1줄 rc=1.

# skill_evals::check <trigger|evals> <file> <skills_root>
#   skills_root: skill 실존 확인용(`<skills_root>/<디렉터리명>/SKILL.md`). 디렉터리명 = file 의 부모 디렉터리.
skill_evals::check() {
  local kind="$1" f="$2" root="$3" dir want r
  [ -f "$f" ] || { echo "파일 부재: $(basename "$f")"; return 1; }
  jq -e . "$f" >/dev/null 2>&1 || { echo "JSON 파싱 불가"; return 1; }
  dir=$(basename "$(dirname "$f")")
  want=$(jq -r 'if (.skill|type)=="string" then .skill else "" end' "$f")
  [ -n "$want" ] || { echo "skill 필드 누락"; return 1; }
  [ "$want" = "$dir" ] || { echo "skill 필드($want) ≠ 디렉터리($dir)"; return 1; }
  [ -f "$root/$dir/SKILL.md" ] || { echo "실존하지 않는 skill: $dir"; return 1; }
  case "$kind" in
    trigger) r=$(jq -r "$(skill_evals::_trigger_filter)" "$f") ;;
    evals)   r=$(jq -r "$(skill_evals::_evals_filter)" "$f") ;;
    *)       echo "미지 kind: $kind"; return 1 ;;
  esac
  [ -z "$r" ] && return 0
  echo "$r"; return 1
}

skill_evals::_trigger_filter() {
  cat <<'JQ'
def ok: type=="string" and length>0;
def dup: group_by(.) | map(select(length>1) | .[0]);
if (.should_trigger|type)!="array" or (.should_trigger|length)==0 then "should_trigger 비어 있음"
elif (.should_not_trigger|type)!="array" or (.should_not_trigger|length)==0 then "should_not_trigger 비어 있음"
elif ([.should_trigger[], .should_not_trigger[] | select((type=="object" and (.id|ok) and (.query|ok))|not)] | length) > 0 then "빈 id 또는 query"
else ([.should_trigger[], .should_not_trigger[] | .id] | dup | if length>0 then "id 중복: " + .[0] else "" end)
end
JQ
}

skill_evals::_evals_filter() {
  cat <<'JQ'
def ok: type=="string" and length>0;
def dup: group_by(.) | map(select(length>1) | .[0]);
def vocab: . as $t | any(["contains","regex","cost_lt","llm_rubric"][]; . == $t);
if (.cases|type)!="array" or (.cases|length)==0 then "cases 비어 있음"
elif ([.cases[] | select((type=="object" and (.id|ok) and (.prompt|ok))|not)] | length) > 0 then "빈 id 또는 prompt"
elif ([.cases[] | select(((.asserts|type)=="array" and (.asserts|length)>0)|not)] | length) > 0 then "asserts 비어 있음"
elif ([.cases[].asserts[] | select(type!="object")] | length) > 0 then "assert 형식 오류"
elif ([.cases[].asserts[].type | select((type=="string" and vocab)|not)] | length) > 0
  then "미지 assert type: " + ([.cases[].asserts[].type | select((type=="string" and vocab)|not)][0] | tostring)
elif ([.cases[].asserts[].value | select((. != null and (tostring|length)>0)|not)] | length) > 0 then "빈 assert value"
elif ([.cases[] | select(has("agent")) | .agent | select((type=="string" and test("\\A[a-z0-9-]+\\z"))|not)] | length) > 0
  then "agent 형식 오류: " + ([.cases[] | select(has("agent")) | .agent | select((type=="string" and test("\\A[a-z0-9-]+\\z"))|not)][0] | tostring)
elif ([.cases[] | select(has("knowledge") and (has("agent")|not))] | length) > 0 then "knowledge 는 agent 가 있는 케이스에만"
elif ([.cases[] | select(has("knowledge")) | .knowledge | select(((type=="array") and length>0)|not)] | length) > 0 then "knowledge 형식 오류: 빈 배열 또는 배열 아님"
elif ([.cases[] | select(has("knowledge")) | .knowledge[] | select((type=="string" and test("\\A(skills|agents)/[A-Za-z0-9._/-]+\\.md\\z") and (test("\\.\\.")|not))|not)] | length) > 0
  then "knowledge 형식 오류: " + ([.cases[] | select(has("knowledge")) | .knowledge[] | select((type=="string" and test("\\A(skills|agents)/[A-Za-z0-9._/-]+\\.md\\z") and (test("\\.\\.")|not))|not)][0] | tostring)
else ([.cases[].id] | dup | if length>0 then "id 중복: " + .[0] else "" end)
end
JQ
}

# skill_evals::called <target> <호출 목록(줄 단위)> → 0=호출됨. `<name>` 과 `specops-ko:<name>` 을 같게 본다.
skill_evals::called() {
  printf '%s\n' "$2" | grep -Fxq -e "$1" -e "specops-ko:$1"
}
