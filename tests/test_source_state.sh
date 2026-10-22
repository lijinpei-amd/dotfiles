#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
chezmoi_bin="${CHEZMOI:-chezmoi}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-source-test.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

test_home="$tmp/home"
mkdir -p "$test_home"

cm() {
    LLM_GATEWAY_KEY="" HOME="$test_home" "$chezmoi_bin" \
        --source "$repo_root" \
        --destination "$test_home" \
        "$@"
}

# Codex owns parts of config.toml at runtime; the modify_ script must enforce
# the managed keys and carry those sections through untouched.
mkdir -p "$test_home/.codex"
cat > "$test_home/.codex/config.toml" <<'TOML'
model = "stale-model"
model_catalog_json = "/stale/catalog.json"

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

# Claude records model preferences at runtime; preserve them and unrelated env.
mkdir -p "$test_home/.claude"
cat > "$test_home/.claude/settings.json" <<'JSON'
{
  "env": {
    "KEEP_ME": "seeded-env",
    "ANTHROPIC_BASE_URL": "https://stale.invalid",
    "ANTHROPIC_CUSTOM_HEADERS": "stale-header"
  },
  "modelSettings": {
    "seeded-model": {"effortLevel": "high"}
  }
}
JSON

# pi rewrites settings.json the same way: it records the last-used model and
# changelog version itself, and writes no trailing newline.
mkdir -p "$test_home/.pi/agent"
printf '%s' '{
  "defaultModel": "seeded-model",
  "lastChangelogVersion": "9.9.9",
  "packages": ["stale-package"]
}' > "$test_home/.pi/agent/settings.json"

# Scripts call out to tools such as codex that the test does not provide.
retired_shell_targets=(
    "$test_home/.bash_login"
    "$test_home/.bashenv"
    "$test_home/.profile"
    "$test_home/.zlogin"
    "$test_home/.zshenv"
)
for target in "${retired_shell_targets[@]}"; do
    printf '%s\n' '# retired shell startup file' > "$target"
done

cm --force --no-tty apply --exclude=scripts
cm verify --exclude=scripts
test -z "$(cm status --exclude=scripts)"

for target in "${retired_shell_targets[@]}"; do
    test ! -e "$target"
    printf '%s\n' '# recreated shell startup file' > "$target"
done
cm --force --no-tty apply --exclude=scripts "${retired_shell_targets[@]}"
for target in "${retired_shell_targets[@]}"; do
    test ! -e "$target"
done

test ! -e "$test_home/README.md"
test ! -e "$test_home/tests"

test -x "$test_home/.codex/hooks/confirm-publish.sh"
test -x "$test_home/.tmux/name-session.sh"

jq empty "$test_home/.claude/settings.json"
python3 - "$test_home/.claude/settings.json" <<'PY'
import json, sys

settings = json.load(open(sys.argv[1]))
assert settings["env"]["ANTHROPIC_BASE_URL"] == (
    "http://127.0.0.1:30101/Anthropic"
)
assert settings["env"]["ANTHROPIC_API_KEY"] == "dummy"
assert "ANTHROPIC_CUSTOM_HEADERS" not in settings["env"]
assert settings["env"]["KEEP_ME"] == "seeded-env"
assert settings["modelSettings"] == {"seeded-model": {"effortLevel": "high"}}
PY
jq empty "$test_home/.codex/hooks.json"
python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' \
    "$test_home/.codex/config.toml"

for bash_startup in \
    "$test_home/.bash_profile" \
    "$test_home/.bashrc" \
    "$test_home/.env_stow.sh" \
    "$test_home/.env_login_stow.sh" \
    "$test_home/.codex/hooks/confirm-publish.sh" \
    "$test_home/.tmux/name-session.sh"; do
    bash -n "$bash_startup"
done
for zsh_startup in "$test_home/.zprofile" "$test_home/.zshrc"; do
    zsh -n "$zsh_startup"
done

grep -Fq "excludesfile = $test_home/.gitignore" "$test_home/.gitconfig"
grep -Fq "base_dir = $test_home/development" \
    "$test_home/.config/ccache/ccache.conf"
grep -Fq "_development_root = \"$test_home/development\"" \
    "$test_home/.config/gdb/gdbinit"
python3 - "$test_home/.codex/config.toml" <<'PY'
import sys, tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)
assert config["model"] == "gpt-6.1-sol", config["model"]
assert config["model_provider"] == "amd_llm_dvue", config["model_provider"]
assert "model_catalog_json" not in config
routes = {
    "amd_llm": "OpenAI",
    "amd_llm_dvue": "OpenAI-dvue",
    "amd_llm_pdue": "OpenAI-pdue",
}
assert set(config["model_providers"]) == set(routes)
for provider_id, route in routes.items():
    provider = config["model_providers"][provider_id]
    assert provider["name"] == route, provider
    assert provider["base_url"] == f"http://127.0.0.1:30101/{route}/", provider
    assert provider["wire_api"] == "responses", provider
    assert provider["supports_websockets"] is False, provider
    assert "env_http_headers" not in provider, provider
PY
test ! -e "$test_home/.codex/amd-pinned-models.json"
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

# models.json needs the machine-local llmProxyBaseUrl; without it the file is
# left alone rather than failing the whole apply.
test ! -e "$test_home/.pi/agent/models.json"
for proxy_url in http://proxy.test:1 http://proxy.test:1/; do
    proxy_data=$(jq -cn --arg url "$proxy_url" '{llmProxyBaseUrl: $url}')
    cm --override-data "$proxy_data" cat "$test_home/.claude/settings.json" \
        > "$tmp/claude-settings.json"
    python3 - "$tmp/claude-settings.json" <<'PY'
import json, sys

settings = json.load(open(sys.argv[1]))
assert settings["env"]["ANTHROPIC_BASE_URL"] == (
    "http://proxy.test:1/Anthropic"
)
PY
    cm --override-data "$proxy_data" cat "$test_home/.codex/config.toml" \
        > "$tmp/codex-config.toml"
    python3 - "$tmp/codex-config.toml" <<'PY'
import sys, tomllib

providers = tomllib.load(open(sys.argv[1], "rb"))["model_providers"]
assert {key: value["base_url"] for key, value in providers.items()} == {
    "amd_llm": "http://proxy.test:1/OpenAI/",
    "amd_llm_dvue": "http://proxy.test:1/OpenAI-dvue/",
    "amd_llm_pdue": "http://proxy.test:1/OpenAI-pdue/",
}, providers
PY
    cm --override-data "$proxy_data" cat "$test_home/.pi/agent/models.json" \
        > "$tmp/pi-models.json"
    python3 - "$tmp/pi-models.json" <<'PY'
import json, sys

providers = json.load(open(sys.argv[1]))["providers"]
assert {key: value["baseUrl"] for key, value in providers.items()} == {
    "amd-openai": "http://proxy.test:1/OpenAI/",
    "amd-openai-dvue": "http://proxy.test:1/OpenAI-dvue/",
    "amd-openai-pdue": "http://proxy.test:1/OpenAI-pdue/",
    "amd-anthropic": "http://proxy.test:1/Anthropic/",
}, providers
PY
done

for script in "$repo_root"/.chezmoiscripts/*.tmpl; do
    cm execute-template < "$script" | bash -n
done

echo "source-state tests passed"
