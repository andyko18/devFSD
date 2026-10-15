#!/usr/bin/env bash
# foundation-kind.sh — UI/BE/풀스택/모바일이면 foundation 필수 KIND (20260812)
# source 전용. 호출: foundation_kind_is_required → 0=필수 · 1=비필수
#
# SoT: check-foundation-present / check-foundation-merged 가 공유.
# SPECOPS_ROOT 또는 cwd 의 .specops/memory 를 본다.
# 원장 칸 계약: check-decisions-ledger.sh 와 같다 — $3=주제 · $4=확정값, 새 칸은 끝에만(20261015).
# shellcheck shell=bash

_fk_uninformative() {
  local v="$1"
  [ -z "$v" ] && return 0
  printf '%s' "$v" | grep -qE '^<[^>]*>$' && return 0
  printf '%s' "$v" | grep -qE '^(TBD|tbd|N/A|n/a|-|—|\(미정\)|미정|미확정|해당없음|해당 없음|\?\?\?)$' && return 0
  printf '%s' "$v" | grep -qE '^<미확정' && return 0
  return 1
}

foundation_kind_is_required() {
  local mem="${SPECOPS_ROOT:-.specops}/memory"
  local ledger="$mem/decisions.md"
  local ctx="$mem/project-context.md"

  [ -f "$mem/frontend-architecture.md" ] && return 0
  [ -f "$mem/backend-architecture.md" ] && return 0

  # 기록된 종류(/init-project 가 project-context.md 머리에 적는다 — 20261009)를 추정보다 먼저 쓴다.
  #   1 Web/UI · 2 백엔드/API · 4 풀스택 · 5 모바일 → 필수.
  #   3 CLI·라이브러리 → **스택 칸 추정만 끈다**(`백엔드 | Python CLI` 같은 서술을 "백엔드 있음"으로 읽지 않는다).
  #     명시적 신호(`UI 유무 | 있음` · 원장의 `프로젝트 종류` 행)는 그대로 본다 — 기록은 init 시점의 값이라
  #     나중에 UI 가 붙은 프로젝트에서 낡을 수 있다(독립 리뷰 지적).
  #   6 기타·기록 없음 → 아래 추정 전부.
  local kind="" skip_stack=0
  [ -f "$ctx" ] && kind=$(sed -n 's/^<!-- specops:project-kind: \([1-6]\)[^0-9].*/\1/p' "$ctx" 2>/dev/null | head -1)
  case "$kind" in
    1|2|4|5) return 0 ;;
    3) skip_stack=1 ;;
  esac

  if [ -f "$ledger" ]; then
    local rows topic value
    rows=$(awk -F'|' '
      /^\|/ {
        if ($2 ~ /DECISION-ID/) next
        if ($2 ~ /^[[:space:]]*-+[[:space:]]*$/) next
        if (NF < 4) next
        topic = $3; value = $4
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", topic)
        gsub(/`/, "", value)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        if (topic == "") next
        if (topic ~ /^\(예시\)/) next
        if (value == "") next
        if (value ~ /^<[^>]*>$/) next
        if (value ~ /^(TBD|tbd|N\/A|n\/a|-|—|\(미정\)|미정|미확정|해당없음|해당 없음|\?\?\?)$/) next
        print topic "|" value
      }
    ' "$ledger")
    while IFS='|' read -r topic value; do
      [ -n "$topic" ] || continue
      if printf '%s' "$topic" | grep -q 'UI 유무'; then
        printf '%s' "$value" | grep -q '있음' && return 0
      fi
      if printf '%s' "$topic" | grep -q '프로젝트 종류'; then
        printf '%s' "$value" | grep -qE '풀스택|Web|UI|BE|API|모바일|Mobile|프론트|백엔드' && return 0
      fi
    done <<EOF
$rows
EOF
  fi

  if [ -f "$ctx" ]; then
    local area value
    while IFS='|' read -r _ area value _; do
      area=$(printf '%s' "$area" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      # 백틱을 벗긴 뒤 본다 — 골격의 칸은 백틱으로 감싼 자리표시자다(`<미확정 — 근거 필요>` · `<있음 \| 없음>`).
      #   벗기지 않으면 자리표시자가 "값 있음"으로, 선택지 표기가 "있음"으로 읽힌다(20261009 재현:
      #   CLI 로 init 한 직후 필수 판정). `<` 로 시작하는 값은 채워지지 않은 칸이다.
      value=$(printf '%s' "$value" | tr -d '`' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      case "$value" in '<'*) continue ;; esac
      if printf '%s' "$area" | grep -q 'UI 유무'; then
        printf '%s' "$value" | grep -q '있음' && return 0
      fi
      if [ "$skip_stack" = "0" ] && printf '%s' "$area" | grep -qE '^(프론트|백엔드)$'; then
        _fk_uninformative "$value" && continue
        printf '%s' "$value" | grep -qiE '없음|해당[[:space:]]*없음|N/A' && continue
        [ -n "$value" ] && return 0
      fi
    done <<EOF
$(grep -E '^\|[[:space:]]*[^|]+[[:space:]]*\|' "$ctx" 2>/dev/null)
EOF
  fi

  return 1
}
