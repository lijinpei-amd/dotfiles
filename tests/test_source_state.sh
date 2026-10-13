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

# Codex owns parts of config.toml at runtime; the modify_ script must enforce
# the managed keys and carry those sections through untouched.
mkdir -p "$test_home/.codex"
cat > "$test_home/.codex/config.toml" <<'TOML'
model = "stale-model"

[projects."/seeded/project"]
trust_level = "trusted"

[notice.model_migrations]
"old-model" = "new-model"
TOML

cm --force --no-tty apply
cm verify
test -z "$(cm status)"

test ! -e "$test_home/README.md"
test ! -e "$test_home/tests"

test -x "$test_home/.codex/hooks/confirm-publish.sh"
test -x "$test_home/.tmux/name-session.sh"

jq empty "$test_home/.claude/settings.json"
jq empty "$test_home/.codex/hooks.json"
python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' \
    "$test_home/.codex/config.toml"

bash -n \
    "$test_home/.bashrc" \
    "$test_home/.bashenv" \
    "$test_home/.env_stow.sh" \
    "$test_home/.codex/hooks/confirm-publish.sh" \
    "$test_home/.tmux/name-session.sh"
zsh -n "$test_home/.zshenv" "$test_home/.zshrc"

grep -Fq "excludesfile = $test_home/.gitignore" "$test_home/.gitconfig"
grep -Fq "base_dir = $test_home/development" \
    "$test_home/.config/ccache/ccache.conf"
grep -Fq "_development_root = \"$test_home/development\"" \
    "$test_home/.config/gdb/gdbinit"
grep -Fq "model_catalog_json = \"$test_home/.codex/amd-pinned-models.json\"" \
    "$test_home/.codex/config.toml"
# Codex refuses to load its config when model_catalog_json names a missing file.
test -f "$test_home/.codex/amd-pinned-models.json"
if grep -Fq 'stale-model' "$test_home/.codex/config.toml"; then
    echo "error: Codex config kept a stale managed key" >&2
    exit 1
fi
grep -Fq '[projects."/seeded/project"]' "$test_home/.codex/config.toml"
grep -Fq '"old-model" = "new-model"' "$test_home/.codex/config.toml"

echo "source-state tests passed"
