#!/usr/bin/env bash
#
# team-upgrade / agent-skills 설치 스크립트
#
# 사용법:
#   curl -sSL https://raw.githubusercontent.com/team-upgrade/agent-skills-installer/main/install.sh | bash
#   curl -sSL ... | bash -s -- upgrade-api                 # 특정 스킬만
#   curl -sSL ... | bash -s -- upgrade-api other-skill     # 여러 스킬
#   curl -sSL ... | bash -s -- --help
#
set -euo pipefail

ORG="team-upgrade"
REPO="agent-skills"
BRANCH="main"
SKILLS_ROOT="$HOME/.agents/skills"

# 설치 가능한 에이전트 환경 (key:label:path)
AGENT_ENV_KEYS=(claude codex hermes)
AGENT_ENV_LABELS=(
  "Claude Code    (~/.claude/skills/)"
  "OpenClaw       (~/.codex/skills/)"
  "Hermes         (~/.hermes/skills/)"
)
AGENT_ENV_PATHS=(
  "$HOME/.claude/skills"
  "$HOME/.codex/skills"
  "$HOME/.hermes/skills"
)

# 선택 결과 (select_agent_envs가 채움)
SELECTED_ENV_KEYS=()
SELECTED_ENV_PATHS=()

info()  { printf "\033[36m==>\033[0m %s\n" "$*"; }
warn()  { printf "\033[33m!!!\033[0m %s\n" "$*"; }
fail()  { printf "\033[31mERR\033[0m %s\n" "$*" >&2; exit 1; }

to_tty() { printf '%s' "$*" > /dev/tty; }

usage() {
  cat <<'EOF'
agent-skills installer

사용법:
  curl -sSL <URL> | bash                              # 모든 스킬 설치
  curl -sSL <URL> | bash -s -- <skill-name>           # 특정 스킬만
  curl -sSL <URL> | bash -s -- <skill1> <skill2>      # 여러 스킬
  curl -sSL <URL> | bash -s -- -h                     # 도움말

에이전트 환경(Claude Code / OpenClaw / Hermes)은 실행 중 체크박스로 선택합니다.
EOF
}

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

# rc 파일에서 export 라인 값만 추출
read_existing_export() {
  local rc_file="$1"
  local var_name="$2"
  [[ -f "$rc_file" ]] || { echo ""; return 0; }
  local line=""
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

# --- 체크박스 멀티셀렉트 UI -----------------------------------------------
# 사용: preset_csv 에는 pre-check할 인덱스들 (0-based, 쉼표 구분). 빈 문자열이면 0번만 기본 선택.
# 결과: 선택된 인덱스가 한 줄에 하나씩 stdout 출력.
multi_select() {
  local preset="$1"; shift
  local labels=("$@")
  local count=${#labels[@]}
  local -a selected
  local i

  for ((i=0; i<count; i++)); do selected[i]=0; done
  if [[ -n "$preset" ]]; then
    local IFS_old="$IFS"
    IFS=','
    local -a _arr
    read -ra _arr <<< "$preset"
    IFS="$IFS_old"
    for i in "${_arr[@]}"; do
      if [[ "$i" =~ ^[0-9]+$ ]] && (( i < count )); then
        selected[i]=1
      fi
    done
  else
    (( count > 0 )) && selected[0]=1
  fi

  local old_stty=""
  old_stty=$(stty -g < /dev/tty 2>/dev/null || true)

  _restore_tty() {
    [[ -n "$old_stty" ]] && stty "$old_stty" < /dev/tty 2>/dev/null || true
    printf '\033[?25h' > /dev/tty 2>/dev/null || true
  }
  trap '_restore_tty; exit 130' INT TERM

  printf '\033[?25l' > /dev/tty 2>/dev/null || true

  local first=1
  local lines_drawn=0

  while true; do
    if (( first )); then
      first=0
    else
      # 이전 렌더를 덮기 위해 커서를 위로 이동 후 화면 끝까지 클리어
      printf '\033[%dA\r\033[0J' "$lines_drawn" > /dev/tty
    fi

    printf '\n' > /dev/tty
    for ((i=0; i<count; i++)); do
      local mark=" "
      (( selected[i] )) && mark="x"
      printf '  [%s] %d) %s\n' "$mark" "$((i+1))" "${labels[i]}" > /dev/tty
    done
    printf '  번호로 토글 / Enter로 완료: ' > /dev/tty
    lines_drawn=$((count + 1))

    local key=""
    IFS= read -rsn1 key < /dev/tty || break

    case "$key" in
      ""|$'\n'|$'\r')
        printf '\n' > /dev/tty
        break
        ;;
      [0-9])
        local idx=$((key - 1))
        if (( idx >= 0 && idx < count )); then
          selected[idx]=$((1 - selected[idx]))
        fi
        ;;
      *)
        : # 다른 키는 무시
        ;;
    esac
  done

  trap - INT TERM
  _restore_tty

  for ((i=0; i<count; i++)); do
    (( selected[i] )) && echo "$i"
  done
}

select_agent_envs() {
  local rc_file="$1"
  local saved preset=""
  saved=$(read_existing_export "$rc_file" "AGENT_SKILLS_TARGETS")

  # 저장된 키 → 인덱스 변환
  if [[ -n "$saved" ]]; then
    local indices=()
    local saved_keys
    local IFS_old="$IFS"
    IFS=','
    read -ra saved_keys <<< "$saved"
    IFS="$IFS_old"
    local sk j
    for sk in "${saved_keys[@]}"; do
      for ((j=0; j<${#AGENT_ENV_KEYS[@]}; j++)); do
        if [[ "${AGENT_ENV_KEYS[j]}" == "$sk" ]]; then
          indices+=("$j")
        fi
      done
    done
    if (( ${#indices[@]} > 0 )); then
      preset=$(IFS=','; echo "${indices[*]}")
    fi
  fi

  echo
  info "설치할 에이전트 환경을 선택하세요"

  local selected_indices
  selected_indices=$(multi_select "$preset" "${AGENT_ENV_LABELS[@]}")

  SELECTED_ENV_KEYS=()
  SELECTED_ENV_PATHS=()
  while IFS= read -r idx; do
    [[ -z "$idx" ]] && continue
    SELECTED_ENV_KEYS+=("${AGENT_ENV_KEYS[$idx]}")
    SELECTED_ENV_PATHS+=("${AGENT_ENV_PATHS[$idx]}")
  done <<< "$selected_indices"

  if (( ${#SELECTED_ENV_KEYS[@]} == 0 )); then
    warn "에이전트 환경이 선택되지 않았습니다. ~/.agents/skills/에만 설치되고 심링크는 만들어지지 않습니다."
  else
    info "선택됨: ${SELECTED_ENV_KEYS[*]}"
  fi
}

install_skills() {
  local requested=("$@")

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

  mkdir -p "$SKILLS_ROOT"
  local target
  for target in "${SELECTED_ENV_PATHS[@]:-}"; do
    [[ -z "$target" ]] && continue
    mkdir -p "$target"
  done

  local count=0
  local skipped=0
  for entry in "$src_root"/*/; do
    [[ -d "$entry" ]] || continue
    [[ -f "$entry/SKILL.md" ]] || continue
    local name
    name=$(basename "$entry")

    # 요청된 스킬 필터링
    if (( ${#requested[@]} > 0 )); then
      local matched=0 r
      for r in "${requested[@]}"; do
        if [[ "$r" == "$name" ]]; then matched=1; break; fi
      done
      if (( matched == 0 )); then
        skipped=$((skipped + 1))
        continue
      fi
    fi

    info "설치: $name"
    rm -rf "$SKILLS_ROOT/$name"
    cp -R "$entry" "$SKILLS_ROOT/$name"

    # 선택된 각 에이전트 환경에 심링크
    for target in "${SELECTED_ENV_PATHS[@]:-}"; do
      [[ -z "$target" ]] && continue
      local link="$target/$name"
      [[ -e "$link" || -L "$link" ]] && rm -f "$link"
      ln -s "$SKILLS_ROOT/$name" "$link"
    done

    count=$((count + 1))
  done

  if (( count == 0 )); then
    if (( ${#requested[@]} > 0 )); then
      fail "요청한 스킬을 레포에서 찾지 못했습니다: ${requested[*]}"
    else
      fail "설치할 스킬이 없습니다 (SKILL.md 보유 디렉토리를 찾지 못함)."
    fi
  fi
  info "스킬 $count개 설치 완료 ($SKILLS_ROOT)"
}

persist_exports() {
  local rc_file="$1"
  info "환경변수를 $rc_file 에 저장..."

  touch "$rc_file"

  local var
  for var in AGENT_SKILLS_GH_TOKEN UPGRADE_API_TOKEN AGENT_SKILLS_TARGETS; do
    if grep -q "^export ${var}=" "$rc_file" 2>/dev/null; then
      sed -i.bak "/^export ${var}=/d" "$rc_file"
      rm -f "$rc_file.bak"
    fi
  done

  # 기존 안내 블록 제거 (중복 방지)
  sed -i.bak '/^# agent-skills (added by install.sh)$/d' "$rc_file"
  rm -f "$rc_file.bak"

  local targets_csv=""
  if (( ${#SELECTED_ENV_KEYS[@]} > 0 )); then
    targets_csv=$(IFS=','; echo "${SELECTED_ENV_KEYS[*]}")
  fi

  {
    echo ""
    echo "# agent-skills (added by install.sh)"
    echo "export AGENT_SKILLS_GH_TOKEN=\"$GH_TOKEN\""
    echo "export UPGRADE_API_TOKEN=\"$UPGRADE_API_TOKEN\""
    echo "export AGENT_SKILLS_TARGETS=\"$targets_csv\""
  } >> "$rc_file"
}

main() {
  local -a requested_skills=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --) shift; while [[ $# -gt 0 ]]; do requested_skills+=("$1"); shift; done ;;
      -*) fail "알 수 없는 옵션: $1 (--help 참고)" ;;
      *)  requested_skills+=("$1") ;;
    esac
    shift || true
  done

  info "agent-skills installer"
  check_dependencies

  local rc_file
  rc_file=$(detect_rc_file)

  resolve_tokens "$rc_file"
  verify_gh_token
  select_agent_envs "$rc_file"
  install_skills "${requested_skills[@]:-}"
  persist_exports "$rc_file"

  echo
  info "설치 완료"
  echo
  echo "  다음을 실행해 환경변수를 적용하세요 (또는 새 터미널 열기):"
  echo "    source $rc_file"
  echo
  echo "  에이전트(Claude Code 등)를 재시작하면 스킬이 활성화됩니다."
}

main "$@"
