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

# 토큰/gateway 설정이 새로 입력되어 rc 파일에 저장이 필요한지 추적
TOKENS_CHANGED=0

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
  local rc_file="$1" need_api="$2" need_db="$3"
  local existing_gh existing_api existing_db_api_url existing_db_api_token http_code
  existing_gh=$(read_existing_export "$rc_file" "AGENT_SKILLS_GH_TOKEN")
  existing_api=$(read_existing_export "$rc_file" "UPGRADE_API_TOKEN")
  existing_db_api_url=$(read_existing_export "$rc_file" "UPGRADE_DB_API_URL")
  existing_db_api_token=$(read_existing_export "$rc_file" "UPGRADE_DB_API_TOKEN")

  UPGRADE_API_TOKEN="${existing_api:-}"
  UPGRADE_DB_API_URL="${existing_db_api_url:-}"
  UPGRADE_DB_API_TOKEN="${existing_db_api_token:-}"

  # 저장된 GH 토큰이 유효하면 묻지 않고 그대로 사용
  if [[ -n "$existing_gh" ]]; then
    GH_TOKEN="$existing_gh"
    http_code=$(check_gh_token)
    if [[ "$http_code" == "200" ]]; then
      info "이미 등록된 GitHub 토큰이 있습니다. (재입력 생략)"
    else
      warn "저장된 GH 토큰이 유효하지 않습니다 (HTTP $http_code). 재입력하세요."
    fi
  fi

  if [[ "${http_code:-}" != "200" ]]; then
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
    TOKENS_CHANGED=1
  fi

  if [[ "$need_api" == "1" && -z "${UPGRADE_API_TOKEN:-}" ]]; then
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
    TOKENS_CHANGED=1
  fi

  if [[ "$need_db" == "1" && ( -z "${UPGRADE_DB_API_URL:-}" || -z "${UPGRADE_DB_API_TOKEN:-}" ) ]]; then
    echo
    info "Upgrade DB gateway 정보를 입력하세요"
    warn "DB URL은 저장하지 않습니다. 외부 에이전트는 UPGRADE_DB_API_URL + UPGRADE_DB_API_TOKEN만 사용합니다."
    if [[ -z "${UPGRADE_DB_API_URL:-}" ]]; then
      read_input "UPGRADE_DB_API_URL: " UPGRADE_DB_API_URL 0
      if [[ -z "${UPGRADE_DB_API_URL:-}" ]]; then
        fail "UPGRADE_DB_API_URL이 비어있습니다."
      fi
    fi
    if [[ -z "${UPGRADE_DB_API_TOKEN:-}" ]]; then
      read_input "UPGRADE_DB_API_TOKEN: " UPGRADE_DB_API_TOKEN 1
      if [[ -z "${UPGRADE_DB_API_TOKEN:-}" ]]; then
        fail "UPGRADE_DB_API_TOKEN이 비어있습니다."
      fi
    fi
    TOKENS_CHANGED=1
  fi
  return 0
}

persist_exports() {
  local rc_file="$1"
  info "환경변수를 $rc_file 에 저장..."
  touch "$rc_file"
  local var
  for var in AGENT_SKILLS_GH_TOKEN UPGRADE_API_TOKEN UPGRADE_DB_API_URL UPGRADE_DB_API_TOKEN UPGRADE_DB_READ_ONLY_CREDENTIAL; do
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
    if [[ -n "${UPGRADE_API_TOKEN:-}" ]]; then
      echo "export UPGRADE_API_TOKEN=\"$UPGRADE_API_TOKEN\""
    fi
    if [[ -n "${UPGRADE_DB_API_URL:-}" ]]; then
      echo "export UPGRADE_DB_API_URL=\"$UPGRADE_DB_API_URL\""
    fi
    if [[ -n "${UPGRADE_DB_API_TOKEN:-}" ]]; then
      echo "export UPGRADE_DB_API_TOKEN=\"$UPGRADE_DB_API_TOKEN\""
    fi
  } >> "$rc_file"
}

install_upgrade_db_cli() {
  command -v npm >/dev/null 2>&1 || fail "upgrade-db CLI 설치에는 npm이 필요합니다. 설치: 'brew install node' 또는 https://nodejs.org"

  info "upgrade-db CLI를 GitHub Packages에서 설치/업데이트 중..."
  local npmrc
  npmrc="$(mktemp /tmp/upgrade-db-npmrc.XXXXXX)"
  chmod 600 "$npmrc"
  {
    echo "@team-upgrade:registry=https://npm.pkg.github.com"
    echo "//npm.pkg.github.com/:_authToken=$GH_TOKEN"
    echo "always-auth=true"
  } > "$npmrc"

  if ! npm_config_userconfig="$npmrc" npm install -g @team-upgrade/upgrade-db --registry=https://npm.pkg.github.com >/dev/null; then
    rm -f "$npmrc"
    fail "upgrade-db CLI GitHub Packages 설치 실패"
  fi
  rm -f "$npmrc"
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
  command -v git >/dev/null 2>&1 || fail "git이 필요합니다."
  if ! command -v npx >/dev/null 2>&1; then
    fail "Node.js/npx가 필요합니다. 설치: 'brew install node' 또는 https://nodejs.org"
  fi

  local rc_file
  rc_file=$(detect_rc_file)

  # 인자 분해: 위치 인자(스킬 이름) → -s 플래그, 나머지(-...)는 passthrough
  local -a skill_args=() passthrough=()
  local need_api=1 need_db=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--agent)
        local opt="$1"
        passthrough+=("$opt")
        shift
        [[ $# -gt 0 ]] || fail "$opt requires a value"
        passthrough+=("$1")
        ;;
      --skill)
        shift
        [[ $# -gt 0 ]] || fail "--skill requires a value"
        skill_args+=(-s "$1")
        ;;
      -*) passthrough+=("$1") ;;
      *)  skill_args+=(-s "$1") ;;
    esac
    shift
  done

  if (( ${#skill_args[@]} > 0 )); then
    need_api=0
    need_db=0
    local i skill
    for (( i = 1; i < ${#skill_args[@]}; i += 2 )); do
      skill="${skill_args[$i]}"
      case "$skill" in
        upgrade-api) need_api=1 ;;
        upgrade-db) need_db=1 ;;
      esac
    done
  elif [[ " ${passthrough[*]} " == *" -l "* || " ${passthrough[*]} " == *" --list "* ]]; then
    need_api=0
    need_db=0
  fi

  resolve_tokens "$rc_file" "$need_api" "$need_db"
  if (( TOKENS_CHANGED )); then
    persist_exports "$rc_file"
  fi
  if [[ "$need_db" == "1" ]]; then
    install_upgrade_db_cli
  fi

  local repo_url="https://github.com/${ORG}/${REPO}.git"
  local askpass
  askpass="$(mktemp /tmp/agent-skills-git-askpass.XXXXXX)"
  AGENT_SKILLS_ASKPASS_FILE="$askpass"
  chmod 700 "$askpass"
  cat > "$askpass" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' 'x-access-token' ;;
  *Password*) printf '%s\n' "${AGENT_SKILLS_GH_TOKEN:?}" ;;
  *) printf '\n' ;;
esac
EOF
  local git_auth_home
  git_auth_home="$(mktemp -d /tmp/agent-skills-git-home.XXXXXX)"
  AGENT_SKILLS_GIT_AUTH_HOME="$git_auth_home"
  chmod 700 "$git_auth_home"
  {
    echo "machine github.com"
    echo "  login x-access-token"
    echo "  password $GH_TOKEN"
  } > "$git_auth_home/.netrc"
  chmod 600 "$git_auth_home/.netrc"
  trap 'rm -f "${AGENT_SKILLS_ASKPASS_FILE:-}"; rm -rf "${AGENT_SKILLS_GIT_AUTH_HOME:-}"' EXIT

  local source_dir="$HOME/.cache/agent-skills/sources/${ORG}-${REPO}"
  mkdir -p "$(dirname "$source_dir")"
  if [[ -d "$source_dir/.git" ]]; then
    info "agent-skills source 업데이트 중..."
    HOME="$git_auth_home" AGENT_SKILLS_GH_TOKEN="$GH_TOKEN" GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 \
      git -C "$source_dir" pull --ff-only >/dev/null
  elif [[ -e "$source_dir" ]]; then
    fail "$source_dir 가 git checkout이 아닙니다. 확인 후 제거하거나 이동하세요."
  else
    info "agent-skills source 준비 중..."
    HOME="$git_auth_home" AGENT_SKILLS_GH_TOKEN="$GH_TOKEN" GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 \
      git clone --depth=1 "$repo_url" "$source_dir" >/dev/null
  fi

  # set -u + 빈 배열 expansion이 "unbound variable"을 던지므로 길이로 가드
  local -a npx_cmd=(npx skills@latest add "$source_dir" -g)
  if (( ${#skill_args[@]} > 0 )); then
    npx_cmd+=("${skill_args[@]}")
  fi
  if (( ${#passthrough[@]} > 0 )); then
    npx_cmd+=("${passthrough[@]}")
  fi

  echo
  info "npx skills 실행 중..."
  echo

  # `curl | bash`로 실행하면 bash의 stdin은 파이프(EOF). 인터랙티브 모드에서는
  # /dev/tty로 연결하고, -y/--yes 또는 -l/--list 같은 비대화식 모드는 stdin 없이 실행한다.
  local noninteractive=0
  case " ${passthrough[*]} " in
    *" -y "*|*" --yes "*|*" -l "*|*" --list "*) noninteractive=1 ;;
  esac
  if ! {
    if [[ "$noninteractive" == "1" ]]; then
      AGENT_SKILLS_GH_TOKEN="$GH_TOKEN" GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 "${npx_cmd[@]}"
    elif [[ -r /dev/tty ]]; then
      AGENT_SKILLS_GH_TOKEN="$GH_TOKEN" GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 "${npx_cmd[@]}" < /dev/tty
    else
      fail "/dev/tty를 읽을 수 없어 인터랙티브 설치가 불가능합니다. -y / --all 플래그 사용을 고려하세요."
    fi
  }; then
    fail "npx skills 설치 실패"
  fi

  echo
  info "설치 완료"
  if (( TOKENS_CHANGED )); then
    echo
    echo "  저장된 환경변수를 '현재 터미널'에 반영하려면:"
    echo "    source $rc_file"
    echo "  (또는 터미널을 새로 여세요. 새 셸은 $rc_file 을 자동 로드합니다.)"
    echo
    echo "  upgrade-db 외부 실행은 기존 API 서버의 API gateway 토큰만 사용합니다:"
    echo "    export UPGRADE_DB_API_URL=\"https://<upgrade-api-host>/upgrade-db\""
    echo "    export UPGRADE_DB_API_TOKEN=\"<permanent upgrade-db cli token>\""
    echo
    echo "  * 자식 프로세스는 부모 셸의 환경을 바꿀 수 없어 자동 source가 불가능합니다."
  fi
}

main "$@"
