#!/usr/bin/env bash
#
# team-upgrade / agent-skills 설치 스크립트
# 실제 설치는 vercel-labs/skills (`npx skills`) 에 위임합니다.
#
# 사용법:
#   curl -sSL https://raw.githubusercontent.com/team-upgrade/agent-skills-installer/main/install.sh | bash
#   curl -sSL ... | bash -s -- upgrade-api                  # 특정 스킬만
#   curl -sSL ... | bash -s -- upgrade-api -a claude-code   # 에이전트 지정
#   curl -sSL ... | bash -s -- -l                           # 스킬 목록
#   curl -sSL ... | bash -s -- --help
#
set -euo pipefail

ORG="team-upgrade"
REPO="agent-skills"

# 토큰이 새로 입력되어 rc 파일에 저장이 필요한지 추적 (재사용 시 0)
TOKENS_CHANGED=1

info()  { printf "\033[36m==>\033[0m %s\n" "$*"; }
warn()  { printf "\033[33m!!!\033[0m %s\n" "$*"; }
fail()  { printf "\033[31mERR\033[0m %s\n" "$*" >&2; exit 1; }

read_input() {
  local prompt="$1" var_name="$2" secret="${3:-0}"
  if [[ ! -r /dev/tty ]]; then
    fail "터미널 입력을 읽을 수 없습니다. 스크립트를 파일로 저장 후 직접 실행하세요."
  fi
  printf "%s" "$prompt" > /dev/tty
  if [[ "$secret" == "1" ]]; then
    IFS= read -rs "$var_name" < /dev/tty
    echo > /dev/tty
  else
    IFS= read -r "$var_name" < /dev/tty
  fi
}

confirm() {
  local prompt="$1" ans=""
  read_input "$prompt [Y/n]: " ans 0
  case "${ans:-}" in ""|y|Y|yes|Yes) return 0 ;; *) return 1 ;; esac
}

detect_rc_file() {
  case "${SHELL:-}" in
    */zsh)  echo "$HOME/.zshrc" ;;
    */bash)
      if [[ "${OSTYPE:-}" == darwin* ]]; then
        echo "$HOME/.bash_profile"
      else
        echo "$HOME/.bashrc"
      fi
      ;;
    *) echo "$HOME/.profile" ;;
  esac
}

read_existing_export() {
  local rc_file="$1" var_name="$2"
  [[ -f "$rc_file" ]] || { echo ""; return 0; }
  local line
  line=$(grep "^export ${var_name}=" "$rc_file" 2>/dev/null | tail -n1 || true)
  [[ -z "$line" ]] && { echo ""; return 0; }
  printf '%s\n' "$line" | sed -E "s/^export ${var_name}=\"(.*)\"\$/\1/"
}

check_gh_token() {
  curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$ORG/$REPO" 2>/dev/null || echo "0"
}

resolve_tokens() {
  local rc_file="$1"
  local existing_gh existing_api http_code
  existing_gh=$(read_existing_export "$rc_file" "AGENT_SKILLS_GH_TOKEN")
  existing_api=$(read_existing_export "$rc_file" "UPGRADE_API_TOKEN")

  # 저장된 토큰이 둘 다 있고 GH 토큰이 유효하면 묻지 않고 그대로 사용
  if [[ -n "$existing_gh" && -n "$existing_api" ]]; then
    GH_TOKEN="$existing_gh"
    UPGRADE_API_TOKEN="$existing_api"
    http_code=$(check_gh_token)
    if [[ "$http_code" == "200" ]]; then
      info "이미 등록된 토큰이 있습니다. (재입력 생략)"
      TOKENS_CHANGED=0
      return 0
    fi
    warn "저장된 GH 토큰이 유효하지 않습니다 (HTTP $http_code). 재입력하세요."
  fi

  echo
  info "GitHub Personal Access Token을 입력하세요"
  read_input "GH_TOKEN: " GH_TOKEN 1
  if [[ -z "${GH_TOKEN:-}" ]]; then
    fail "GH_TOKEN이 비어있습니다."
  fi
  info "GitHub 토큰 검증 중..."
  http_code=$(check_gh_token)
  case "$http_code" in
    200) info "GitHub 토큰 OK" ;;
    401) fail "GH_TOKEN 인증 실패 (401)." ;;
    403) fail "권한 부족 (403)." ;;
    404) fail "$ORG/$REPO에 접근할 수 없습니다." ;;
    *)   fail "GitHub API 응답 이상 (HTTP $http_code)" ;;
  esac

  echo
  info "Upgrade API 토큰을 입력하세요"
  if [[ -n "$existing_api" ]] && confirm "저장된 Upgrade API 토큰을 재사용할까요?"; then
    UPGRADE_API_TOKEN="$existing_api"
  else
    read_input "UPGRADE_API_TOKEN: " UPGRADE_API_TOKEN 1
    if [[ -z "${UPGRADE_API_TOKEN:-}" ]]; then
      fail "UPGRADE_API_TOKEN이 비어있습니다."
    fi
  fi
  return 0
}

persist_exports() {
  local rc_file="$1"
  info "환경변수를 $rc_file 에 저장..."
  touch "$rc_file"
  local var
  for var in AGENT_SKILLS_GH_TOKEN UPGRADE_API_TOKEN; do
    if grep -q "^export ${var}=" "$rc_file" 2>/dev/null; then
      sed -i.bak "/^export ${var}=/d" "$rc_file"
      rm -f "$rc_file.bak"
    fi
  done
  sed -i.bak '/^# agent-skills (added by install.sh)$/d' "$rc_file"
  rm -f "$rc_file.bak"
  {
    echo ""
    echo "# agent-skills (added by install.sh)"
    echo "export AGENT_SKILLS_GH_TOKEN=\"$GH_TOKEN\""
    echo "export UPGRADE_API_TOKEN=\"$UPGRADE_API_TOKEN\""
  } >> "$rc_file"
}

usage() {
  cat <<'EOF'
agent-skills installer (vercel-labs/skills 래핑)

사용법:
  curl -sSL <URL> | bash                               # 인터랙티브 설치
  curl -sSL <URL> | bash -s -- <skill> [<skill>...]    # 특정 스킬만
  curl -sSL <URL> | bash -s -- -l                      # 사용 가능한 스킬 목록
  curl -sSL <URL> | bash -s -- -h                      # 이 도움말

위치 인자는 스킬 이름으로 해석됩니다 (`--skill <name>`으로 변환).
그 외 -로 시작하는 플래그는 `npx skills add`에 그대로 전달됩니다:

  -a, --agent <agent>  특정 에이전트 지정 (claude-code, codex, openclaw 등)
  -g, --global         전역 설치 (기본값, 이 스크립트는 자동 추가)
  -y, --yes            확인 프롬프트 스킵
  --all                모든 스킬 × 모든 에이전트
  --copy               심링크 대신 복사

예:
  curl -sSL <URL> | bash -s -- upgrade-api -a claude-code -a codex -y
  curl -sSL <URL> | bash -s -- -l
EOF
}

main() {
  for arg in "$@"; do
    case "$arg" in -h|--help) usage; exit 0 ;; esac
  done

  info "agent-skills installer"

  command -v curl >/dev/null 2>&1 || fail "curl이 필요합니다."
  if ! command -v npx >/dev/null 2>&1; then
    fail "Node.js/npx가 필요합니다. 설치: 'brew install node' 또는 https://nodejs.org"
  fi

  local rc_file
  rc_file=$(detect_rc_file)

  resolve_tokens "$rc_file"
  if (( TOKENS_CHANGED )); then
    persist_exports "$rc_file"
  fi

  # 인자 분해: 위치 인자(스킬 이름) → -s 플래그, 나머지(-...)는 passthrough
  local -a skill_args=() passthrough=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -*) passthrough+=("$1") ;;
      *)  skill_args+=(-s "$1") ;;
    esac
    shift
  done

  local url="https://${GH_TOKEN}@github.com/${ORG}/${REPO}.git"

  # set -u + 빈 배열 expansion이 "unbound variable"을 던지므로 길이로 가드
  local -a npx_cmd=(npx skills@latest add "$url" -g)
  if (( ${#skill_args[@]} > 0 )); then
    npx_cmd+=("${skill_args[@]}")
  fi
  if (( ${#passthrough[@]} > 0 )); then
    npx_cmd+=("${passthrough[@]}")
  fi

  echo
  info "npx skills 실행 중..."
  echo

  # `curl | bash`로 실행하면 bash의 stdin은 파이프(EOF). npx의 인터랙티브 프롬프트가
  # 입력 없다고 판단해 즉시 종료되므로 명시적으로 /dev/tty를 stdin으로 재지정.
  if [[ ! -r /dev/tty ]]; then
    fail "/dev/tty를 읽을 수 없어 인터랙티브 설치가 불가능합니다. -y / --all 플래그 사용을 고려하세요."
  fi
  exec "${npx_cmd[@]}" < /dev/tty
}

main "$@"
