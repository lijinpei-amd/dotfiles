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

[marketplaces.jinpei-skills]
source_type = "local"
source = "/stale/skills"

[marketplaces.codex-owned]
source_type = "local"
source = "/seeded/marketplace"

[plugins."working-on-llvm@jinpei-skills"]
enabled = false

[plugins."retired@jinpei-skills"]
enabled = true
TOML

# pi rewrites settings.json the same way: it records the last-used model and
# changelog version itself, and writes no trailing newline.
mkdir -p "$test_home/.pi/agent"
printf '%s' '{
  "defaultModel": "seeded-model",
  "lastChangelogVersion": "9.9.9",
  "packages": ["stale-package"]
}' > "$test_home/.pi/agent/settings.json"

# Scripts call out to tools such as codex that the test does not provide.
cm --force --no-tty apply --exclude=scripts
cm verify --exclude=scripts
test -z "$(cm status --exclude=scripts)"

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
if grep -Fq '/stale/skills' "$test_home/.codex/config.toml"; then
    echo "error: Codex config kept a stale jinpei-skills marketplace" >&2
    exit 1
fi
grep -Fq 'source = "https://github.com/lijinpei-amd/skills.git"' \
    "$test_home/.codex/config.toml"
# jinpei-skills tables are corrected where Codex put them, not moved: Codex
# inserts its own tables beside them, and moving them would never settle.
header_line() {
    grep -nF "$1" "$test_home/.codex/config.toml" | cut -d: -f1
}
test "$(header_line '[marketplaces.jinpei-skills]')" -lt "$(header_line '[marketplaces.codex-owned]')"
test "$(header_line '[marketplaces.codex-owned]')" -lt \
    "$(header_line '[plugins."working-on-llvm@jinpei-skills"]')"
python3 - "$test_home/.codex/config.toml" <<'PY'
import sys, tomllib
plugins = tomllib.load(open(sys.argv[1], "rb"))["plugins"]
assert plugins["working-on-llvm@jinpei-skills"] == {"enabled": True}, plugins
assert plugins["amdgpu-isa-builder@jinpei-skills"] == {"enabled": False}, plugins
assert "retired@jinpei-skills" not in plugins, plugins
PY

pi_settings="$test_home/.pi/agent/settings.json"
test "$(jq -r .defaultModel "$pi_settings")" = seeded-model
test "$(jq -r .defaultProvider "$pi_settings")" = amd-anthropic
test "$(jq -r .lastChangelogVersion "$pi_settings")" = 9.9.9
jq -e '.packages | index("git:github.com/lijinpei-amd/skills")' "$pi_settings" >/dev/null
test "$(jq -c .skills "$pi_settings")" = "[]"
if jq -e '.packages | index("stale-package")' "$pi_settings" >/dev/null; then
    echo "error: pi settings kept a stale managed key" >&2
    exit 1
fi
test "$(tail -c1 "$pi_settings")" = "}"

# models.json needs the machine-local piProxyBaseUrl; without it the file is
# left alone rather than failing the whole apply.
test ! -e "$test_home/.pi/agent/models.json"
pi_models=$(cm --override-data '{"piProxyBaseUrl": "http://proxy.test:1"}' \
    cat "$test_home/.pi/agent/models.json")
printf '%s' "$pi_models" | jq empty
printf '%s' "$pi_models" | grep -Fq '"baseUrl": "http://proxy.test:1/OpenAI"'
printf '%s' "$pi_models" | grep -Fq '"baseUrl": "http://proxy.test:1/Anthropic"'

for script in "$repo_root"/.chezmoiscripts/*.tmpl; do
    cm execute-template < "$script" | bash -n
done

echo "source-state tests passed"
