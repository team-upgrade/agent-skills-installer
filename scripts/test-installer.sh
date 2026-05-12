#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local file="$1" pattern="$2"
  if ! grep -q -- "$pattern" "$file"; then
    printf 'expected %s to contain pattern: %s\n' "$file" "$pattern" >&2
    printf '%s contents:\n' "$file" >&2
    sed -n '1,160p' "$file" >&2 || true
    exit 1
  fi
}

assert_not_contains() {
  local file="$1" pattern="$2"
  if grep -q -- "$pattern" "$file"; then
    printf 'expected %s not to contain pattern: %s\n' "$file" "$pattern" >&2
    printf '%s contents:\n' "$file" >&2
    sed -n '1,160p' "$file" >&2 || true
    exit 1
  fi
}

make_fake_bin() {
  local dir="$1"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 200
EOF
  cat > "$dir/bin/npx" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$HOME/npx-args.txt"
EOF
  cat > "$dir/bin/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "clone" ]]; then
  dest="${@: -1}"
  mkdir -p "$dest/.git"
  exit 0
fi
if [[ "$1" == "-C" ]]; then
  exit 0
fi
printf 'unexpected git args: %s\n' "$*" >&2
exit 1
EOF
  chmod +x "$dir/bin/curl" "$dir/bin/git" "$dir/bin/npx"
}

run_installer() {
  local home="$1"
  shift
  HOME="$home" SHELL=/bin/zsh PATH="$home/bin:$PATH" bash "$ROOT/install.sh" "$@" >"$home/out.txt" 2>"$home/err.txt"
}

test_upgrade_db_only_does_not_require_api_token() {
  local home
  home="$(mktemp -d)"
  trap 'rm -rf "$home"' RETURN
  make_fake_bin "$home"
  printf 'export AGENT_SKILLS_GH_TOKEN="dummy-gh"\n' > "$home/.zshrc"

  run_installer "$home" upgrade-db -a codex -a openclaw -y

  assert_contains "$home/.zshrc" 'QUERYLEDGER_READ_ONLY_DB_CREDENTIAL="true"'
  assert_not_contains "$home/.zshrc" 'UPGRADE_API_TOKEN'
  assert_contains "$home/npx-args.txt" "$home/.cache/agent-skills/sources/team-upgrade-agent-skills"
  assert_contains "$home/npx-args.txt" '-s upgrade-db -a codex -a openclaw -y'
  assert_not_contains "$home/npx-args.txt" 'dummy-gh'
  assert_not_contains "$home/npx-args.txt" 'https://github.com/team-upgrade/agent-skills.git'
  assert_not_contains "$home/npx-args.txt" '-s codex'
  assert_not_contains "$home/npx-args.txt" '-s openclaw'
}

test_upgrade_api_only_does_not_write_db_marker() {
  local home
  home="$(mktemp -d)"
  trap 'rm -rf "$home"' RETURN
  make_fake_bin "$home"
  {
    printf 'export AGENT_SKILLS_GH_TOKEN="dummy-gh"\n'
    printf 'export UPGRADE_API_TOKEN="dummy-api"\n'
  } > "$home/.zshrc"

  run_installer "$home" upgrade-api -a codex -y

  assert_contains "$home/.zshrc" 'UPGRADE_API_TOKEN="dummy-api"'
  assert_not_contains "$home/.zshrc" 'QUERYLEDGER_READ_ONLY_DB_CREDENTIAL'
  assert_contains "$home/npx-args.txt" "$home/.cache/agent-skills/sources/team-upgrade-agent-skills"
  assert_contains "$home/npx-args.txt" '-s upgrade-api -a codex -y'
  assert_not_contains "$home/npx-args.txt" 'dummy-gh'
  assert_not_contains "$home/npx-args.txt" 'https://github.com/team-upgrade/agent-skills.git'
  assert_not_contains "$home/npx-args.txt" '-s codex'
}

test_list_mode_only_needs_github_token() {
  local home
  home="$(mktemp -d)"
  trap 'rm -rf "$home"' RETURN
  make_fake_bin "$home"
  printf 'export AGENT_SKILLS_GH_TOKEN="dummy-gh"\n' > "$home/.zshrc"

  run_installer "$home" -l

  assert_not_contains "$home/.zshrc" 'UPGRADE_API_TOKEN'
  assert_not_contains "$home/.zshrc" 'QUERYLEDGER_READ_ONLY_DB_CREDENTIAL'
  assert_contains "$home/npx-args.txt" "$home/.cache/agent-skills/sources/team-upgrade-agent-skills"
  assert_contains "$home/npx-args.txt" '-l'
  assert_not_contains "$home/npx-args.txt" 'dummy-gh'
  assert_not_contains "$home/npx-args.txt" 'https://github.com/team-upgrade/agent-skills.git'
}

test_upgrade_db_only_does_not_require_api_token
test_upgrade_api_only_does_not_write_db_marker
test_list_mode_only_needs_github_token

printf 'installer tests passed\n'
