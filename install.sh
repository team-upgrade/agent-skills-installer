#!/usr/bin/env bash
#
# team-upgrade / agent-skills 설치 스크립트
#
# 사용법:
#   curl -sSL https://raw.githubusercontent.com/team-upgrade/agent-skills-installer/main/install.sh | bash
#
set -euo pipefail

ORG="team-upgrade"
REPO="agent-skills"
BRANCH="main"
SKILLS_ROOT="$HOME/.agents/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"

info()  { printf "\033[36m==>\033[0m %s\n" "$*"; }
warn()  { printf "\033[33m!!!\033[0m %s\n" "$*"; }
fail()  { printf "\033[31mERR\033[0m %s\n" "$*" >&2; exit 1; }

# curl | bash 환경에서도 stdin이 터미널을 가리키도록 /dev/tty 사용
read_input() {
  local prompt="$1"
  local var_name="$2"
  local secret="${3:-0}"
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

check_dependencies() {
  command -v curl >/dev/null 2>&1 || fail "curl이 필요합니다."
  command -v tar  >/dev/null 2>&1 || fail "tar가 필요합니다."
}

prompt_tokens() {
  echo
  info "GitHub Personal Access Token을 입력하세요"
  echo "   (1Password 공유 vault: 'agent-skills GH PAT')"
  read_input "GH_TOKEN: " GH_TOKEN 1
  [[ -z "${GH_TOKEN:-}" ]] && fail "GH_TOKEN이 비어있습니다."

  echo
  info "Upgrade API 토큰을 입력하세요"
  echo "   (1Password 공유 vault: 'Upgrade Agent API Token')"
  read_input "UPGRADE_API_TOKEN: " UPGRADE_API_TOKEN 1
  [[ -z "${UPGRADE_API_TOKEN:-}" ]] && fail "UPGRADE_API_TOKEN이 비어있습니다."
}

verify_gh_token() {
  info "GitHub 토큰 검증 중..."
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$ORG/$REPO") || true

  case "$http_code" in
    200) info "GitHub 토큰 OK" ;;
    401) fail "GH_TOKEN 인증 실패 (401). 토큰을 다시 확인하세요." ;;
    403) fail "권한 부족 (403). PAT에 contents:read 권한이 있는지 확인하세요." ;;
    404) fail "$ORG/$REPO에 접근할 수 없습니다. PAT scope를 확인하세요." ;;
    *)   fail "GitHub API 응답 이상 (HTTP $http_code)" ;;
  esac
}

install_skills() {
  local tmp
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  info "스킬 tarball 다운로드 중..."
  curl -fsSL \
    -H "Authorization: token $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -o "$tmp/skills.tar.gz" \
    "https://api.github.com/repos/$ORG/$REPO/tarball/$BRANCH" \
    || fail "tarball 다운로드 실패"

  mkdir -p "$tmp/extract"
  tar -xzf "$tmp/skills.tar.gz" -C "$tmp/extract"

  local src_root
  src_root=$(find "$tmp/extract" -maxdepth 1 -mindepth 1 -type d | head -n1)
  [[ -z "$src_root" || ! -d "$src_root/skills" ]] \
    && fail "tarball 구조가 예상과 다릅니다 (skills/ 디렉토리 없음)."

  mkdir -p "$SKILLS_ROOT" "$CLAUDE_SKILLS_DIR"

  local count=0
  for skill_dir in "$src_root"/skills/*/; do
    [[ -d "$skill_dir" ]] || continue
    local name
    name=$(basename "$skill_dir")

    info "설치: $name"
    rm -rf "$SKILLS_ROOT/$name"
    cp -R "$skill_dir" "$SKILLS_ROOT/$name"

    local link="$CLAUDE_SKILLS_DIR/$name"
    [[ -e "$link" || -L "$link" ]] && rm -f "$link"
    ln -s "$SKILLS_ROOT/$name" "$link"

    count=$((count + 1))
  done

  [[ "$count" -eq 0 ]] && fail "설치할 스킬이 없습니다."
  info "스킬 $count개 설치 완료 ($SKILLS_ROOT)"
}

persist_token() {
  local rc_file
  rc_file=$(detect_rc_file)
  info "환경변수를 $rc_file 에 저장..."

  touch "$rc_file"
  if grep -q '^export UPGRADE_API_TOKEN=' "$rc_file" 2>/dev/null; then
    # macOS sed 호환: -i ''
    sed -i.bak '/^export UPGRADE_API_TOKEN=/d' "$rc_file"
    rm -f "$rc_file.bak"
  fi
  {
    echo ""
    echo "# agent-skills: Upgrade API token (added by install.sh)"
    echo "export UPGRADE_API_TOKEN=\"$UPGRADE_API_TOKEN\""
  } >> "$rc_file"

  info "export UPGRADE_API_TOKEN 추가됨"
  RC_FILE_PATH="$rc_file"
}

main() {
  info "agent-skills installer"
  check_dependencies
  prompt_tokens
  verify_gh_token
  install_skills
  persist_token

  echo
  info "설치 완료"
  echo
  echo "  다음 중 하나를 실행해 환경변수를 적용하세요:"
  echo "    source $RC_FILE_PATH"
  echo "    (또는 터미널을 새로 여세요)"
  echo
  echo "  Claude Code를 재시작하면 스킬이 활성화됩니다."
}

main "$@"
