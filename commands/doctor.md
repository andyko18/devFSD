---
name: doctor
disable-model-invocation: true
description: specops 설치·환경 건강 진단 — git hook 2단 게이트·memory 채움·고아 FID·progress 정합·부트스트랩 종결·무음 실패 적체·거버넌스 훅 활성·필수 의존·관제판 버전·effort 환경변수 10항목 read-only 점검
triggers:
  - "/doctor"
mode: ask
specops_version: 2.18.0
specops_layer: Lifecycle-Tool
reference_upstream: specops-ko 독자 추가
---

# /doctor

## 목적

사용자 프로젝트의 **specops 설치·환경 건강**을 read-only 로 진단한다. `validate-structure.sh` 는 플러그인 개발자용이라 사용자 프로젝트 상태를 보는 층이 없었다.

`/status` 와 역할이 다르다 — `/status` = FID 진행 상황, `/doctor` = 설치·환경 건강.

## Process

1. `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/doctor.sh` 실행
2. 출력 표를 그대로 사용자에게 제시
3. `⚠️` 항목의 **조치 명령**을 함께 안내

## 점검 항목

| 항목 | 판정 |
|---|---|
| `git_hooks` | 플러그인 repo(`scripts/_internal/install-git-hooks.sh` + `.githooks/` 실재)면 `core.hooksPath=.githooks` + `pre-commit`·`pre-push` 실행 가능. 하류 repo 면 ⚠️ + 조치 없음 — **specops 2단 게이트 미설치**(이 repo 는 플러그인 관할 밖). 검사는 specops 게이트만 보므로 **사용자가 직접 만든 훅의 유무는 판정하지 않는다** |
| `memory` | `.specops/memory/*.md` placeholder 잔존 (판정 SoT = `scan-enrich-placeholders.sh`) |
| `orphan_fid` | `spec.md` 만 있고 `tasks.md`·`evidence.md` 둘 다 없는 FID |
| `progress` | `/verify PASS` 기록인데 `evidence.md` 부재 (**디렉터리째 없는 FID 는 아카이브로 제외**) |
| `bootstrap` | `/init-project` 부트스트랩이 **커밋으로 종결**됐는가 — `chore(init)` 커밋 부재 시 ⚠️ (조치: `init-finalize.sh`). `.specops/memory` 부재·비-git 은 `unknown`. memory 도 FID 도 없으면 이전 버전 훅이 남긴 흔적일 수 있음을 알린다(플러그인을 쓰지 않는 저장소라면 `.specops/` 를 지우면 관할에서 빠진다) |
| `stale` | 무음 실패 — pending 적체(>7일) · freelog 정체(>14일 + 그 사이 커밋) · 최근 30일 우회 ≥3건 |
| `governance` | 거버넌스 훅 4종(`pretool-governance`·`posttool-governance`·`stop-governance`·`session-start`)이 실제로 켜져 있는가 — 전부 활성이면 `훅 4종 활성`, 아니면 `훅 N/4 비활성: <목록>` (조치: `.specops/config.yaml` 의 profile/hooks 설정 확인). 훅이 켜져 있어도 `jq` 가 없으면 ⚠️ — 전부 fail-open 이라 동작하지 않는다 |
| `deps` | 거버넌스가 의존하는 도구. **두 부재의 귀결이 다르다** — `jq` 부재 → 훅이 전면 fail-open(거버넌스 비활성) · `python3`/`pyyaml` 부재 → `is-hook-enabled` 가 default enabled 로 답해 위 `governance` 항목이 config 킬스위치를 **탐지하지 못한다**. `jq` 가 있고 pyyaml 만 없으면 훅 자체는 정상 동작한다 |
| `console` | 관제판(mod)은 Claude Code **2.1.287 이상**에서만 로드된다. `claude --version` 의 버전을 `sort -V` 로 비교 — 이상 ✅ · 미만 ⚠️(관제판 비활성, 올리라고 안내) · `claude` 없음·출력 판독 불가 `unknown`(⚠️ 가 아니다, 판정 불가를 사유와 함께 적는다). 조회만 한다 |
| `effort_env` | `CLAUDE_CODE_EFFORT_LEVEL` 환경변수 설정 여부. 설정되면 skill·agent frontmatter effort(서브에이전트 effort 프로파일 포함)가 **전부 무력화**된다(env 가 frontmatter 보다 우선 — 공식 문서, skill 은 20261007 실측으로도 확인). 미설정 ✅ · 설정 ⚠️(값 앞 24자 표시, 의도한 설정이면 무시 가능). 빈 값은 미설정으로 본다. doctor 는 **자기 프로세스 env 만 관측**하므로 ✅ 가 무력화 없음의 증명은 아니다 |

## 계약

- **항상 exit 0** — 조회 도구. 어떤 흐름도 막지 않는다.
- **read-only** — 어떤 파일도 쓰지 않는다.
- `--json` 으로 기계 판독 가능.
- `.specops/` 부재 시 **환경 항목(`deps`·`effort_env`)만** 점검하고 프로젝트 항목은 건너뛴다(건너뛴 사실을 첫 줄에 적는다 · `--json` 은 `"scope":"env-only"`). 설치 직후 의존성을 확인하는 용도다.

## 안티패턴

- **자동 수정** — 본 커맨드는 진단만. 조치는 사용자가 실행한다 (5원칙 4 주권).
- **게이트화** — exit 0 계약을 깨고 CI 를 막지 않는다. 필요해지면 `--strict` 를 별도 설계한다.

## progress 판정 — 아카이브 제외 (v1.65.0, FID 20260808-doctor-progress-archive)

`/verify PASS` 를 기록한 FID 중 **`.specops/<FID>/` 디렉터리 자체가 없는 것**은 **아카이브**로 보고 불일치에서 제외합니다. `.specops/*` 는 `.gitignore` 대상이라 로컬 전용이고 `session-progress.md` 는 append-only 이므로, 과거 FID 디렉터리 정리는 **의도된 동작이지 결함이 아닙니다** — 조치 문구("evidence.md 확인 또는 `/verify` 재실행")도 6주 전 FID 에는 수행 자체가 불가능합니다. 제외된 건수는 `아카이브 N건 제외` 로 함께 표기해 조용히 사라지지 않게 합니다(0건이면 미표기).

**불일치로 남는 것은 `디렉터리는 있는데 evidence.md 만 없는` 경우**입니다 — 검증을 주장한 뒤 증거가 유실된 진짜 결함입니다.

계기: 실측 불일치 83건이 **전부 디렉터리 부재**였고 `evidence.md` 만 없는 경우는 0건이었습니다(누락 `20260426~20260702` · 실재 `20260709~`). 끌 수 없는 ⚠️ 는 아무도 읽지 않습니다.

> **승계**: 이 판정은 FID `20260807-specops-doctor` 의 **AC-5**("그 FID 에 `evidence.md` 가 없을 때 ⚠️")를 **대체(supersede)** 합니다. 원 문면은 디렉터리 유무를 구분하지 않아 아카이브 FID 도 포함했으나, 그 AC 를 검증하던 `T5` 픽스처는 실제로는 디렉터리가 존재하는 케이스였습니다. 종료된 FID 의 계약서는 이력 보존을 위해 **수정하지 않았고**, 승계는 `20260808-doctor-progress-archive` 의 AC-1·AC-2 에 기록돼 있습니다.

## 참조

- `scripts/doctor.sh` — 진단 본체
- `scripts/_internal/install-git-hooks.sh` — `git_hooks` ⚠️ 조치 (**플러그인 repo 한정** — 하류엔 처방하지 않는다)
- `commands/status.md` — FID 진행 상황 (역할 구분)
