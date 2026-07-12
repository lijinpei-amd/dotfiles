#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
chezmoi_bin="${CHEZMOI:-chezmoi}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-source-test.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

test_home="$tmp/home"
mkdir -p "$test_home"

cm() {
    HOME="$test_home" "$chezmoi_bin" \
        --source "$repo_root" \
        --destination "$test_home" \
        "$@"
}

cm --force --no-tty apply
cm verify
test -z "$(cm status)"

test ! -e "$test_home/README.md"
test ! -e "$test_home/scripts"
test ! -e "$test_home/tests"

test -x "$test_home/.claude/hooks/confirm-publish.sh"
test -x "$test_home/.codex/hooks/confirm-publish.sh"
test -x "$test_home/.tmux/name-session.sh"

jq empty "$test_home/.claude/settings.json"
jq empty "$test_home/.codex/hooks.json"
python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' \
    "$test_home/.codex/config.toml"

bash -n \
    "$test_home/.bashrc_stow" \
    "$test_home/.env_stow.sh" \
    "$test_home/.claude/hooks/confirm-publish.sh" \
    "$test_home/.codex/hooks/confirm-publish.sh" \
    "$test_home/.tmux/name-session.sh"
zsh -n "$test_home/.zshenv_stow" "$test_home/.zshrc_stow"

grep -Fq "excludesfile = $test_home/.gitignore" "$test_home/.gitconfig"
grep -Fq "base_dir = $test_home/development" \
    "$test_home/.config/ccache/ccache.conf"
grep -Fq "_development_root = \"$test_home/development\"" \
    "$test_home/.config/gdb/gdbinit"
grep -Fq "[hooks.state.\"$test_home/.codex/hooks.json:pre_tool_use:0:0\"]" \
    "$test_home/.codex/config.toml"
grep -Fq "[projects.\"$test_home/development/code_snippets\"]" \
    "$test_home/.codex/config.toml"

echo "source-state tests passed"
