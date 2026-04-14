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

confirm() {
  local prompt="$1"
  local ans=""
  read_input "$prompt [Y/n]: " ans 0
  case "${ans:-}" in
    ""|y|Y|yes|Yes) return 0 ;;
    *) return 1 ;;
  esac
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

# rc 파일에서 export 라인 값만 추출 (매칭 없어도 안전)
read_existing_export() {
  local rc_file="$1"
  local var_name="$2"
  [[ -f "$rc_file" ]] || { echo ""; return 0; }
  local line=""
  # grep이 매칭 실패해도 set -e로 죽지 않도록 || true
  line=$(grep "^export ${var_name}=" "$rc_file" 2>/dev/null | tail -n1 || true)
  [[ -z "$line" ]] && { echo ""; return 0; }
  printf '%s\n' "$line" | sed -E "s/^export ${var_name}=\"(.*)\"\$/\1/"
}

resolve_tokens() {
  local rc_file="$1"
  local existing_gh existing_api
  existing_gh=$(read_existing_export "$rc_file" "AGENT_SKILLS_GH_TOKEN")
  existing_api=$(read_existing_export "$rc_file" "UPGRADE_API_TOKEN")

  if [[ -n "$existing_gh" && -n "$existing_api" ]]; then
    echo
    info "기존에 저장된 토큰을 찾았습니다 ($rc_file)."
    if confirm "기존 토큰을 그대로 사용할까요?"; then
      GH_TOKEN="$existing_gh"
      UPGRADE_API_TOKEN="$existing_api"
      return
    fi
  fi

  echo
  info "GitHub Personal Access Token을 입력하세요"
  read_input "GH_TOKEN: " GH_TOKEN 1
  [[ -z "${GH_TOKEN:-}" ]] && fail "GH_TOKEN이 비어있습니다."

  echo
  info "Upgrade API 토큰을 입력하세요"
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
  [[ -z "$src_root" ]] && fail "tarball 구조가 예상과 다릅니다."

  mkdir -p "$SKILLS_ROOT" "$CLAUDE_SKILLS_DIR"

  local count=0
  # 레포 루트의 각 디렉토리 중 SKILL.md가 있는 것만 스킬로 간주
  for entry in "$src_root"/*/; do
    [[ -d "$entry" ]] || continue
    [[ -f "$entry/SKILL.md" ]] || continue
    local name
    name=$(basename "$entry")

    info "설치: $name"
    rm -rf "$SKILLS_ROOT/$name"
    cp -R "$entry" "$SKILLS_ROOT/$name"

    local link="$CLAUDE_SKILLS_DIR/$name"
    [[ -e "$link" || -L "$link" ]] && rm -f "$link"
    ln -s "$SKILLS_ROOT/$name" "$link"

    count=$((count + 1))
  done

  [[ "$count" -eq 0 ]] && fail "설치할 스킬이 없습니다 (SKILL.md 보유 디렉토리를 찾지 못함)."
  info "스킬 $count개 설치 완료 ($SKILLS_ROOT)"
}

# rc 파일에 여러 export를 idempotent하게 기록
persist_exports() {
  local rc_file="$1"
  info "환경변수를 $rc_file 에 저장..."

  touch "$rc_file"

  # 기존 라인 제거 (있다면)
  for var in AGENT_SKILLS_GH_TOKEN UPGRADE_API_TOKEN; do
    if grep -q "^export ${var}=" "$rc_file" 2>/dev/null; then
      sed -i.bak "/^export ${var}=/d" "$rc_file"
      rm -f "$rc_file.bak"
    fi
  done

  # 기존 안내 블록도 제거 (재실행 시 중복 방지)
  sed -i.bak '/^# agent-skills (added by install.sh)$/d' "$rc_file"
  rm -f "$rc_file.bak"

  {
    echo ""
    echo "# agent-skills (added by install.sh)"
    echo "export AGENT_SKILLS_GH_TOKEN=\"$GH_TOKEN\""
    echo "export UPGRADE_API_TOKEN=\"$UPGRADE_API_TOKEN\""
  } >> "$rc_file"

  info "AGENT_SKILLS_GH_TOKEN / UPGRADE_API_TOKEN 저장됨"
}

main() {
  info "agent-skills installer"
  check_dependencies

  local rc_file
  rc_file=$(detect_rc_file)

  resolve_tokens "$rc_file"
  verify_gh_token
  install_skills
  persist_exports "$rc_file"

  echo
  info "설치 완료"
  echo
  echo "  다음 중 하나를 실행해 환경변수를 적용하세요:"
  echo "    source $rc_file"
  echo "    (또는 터미널을 새로 여세요)"
  echo
  echo "  Claude Code를 재시작하면 스킬이 활성화됩니다."
}

main "$@"
