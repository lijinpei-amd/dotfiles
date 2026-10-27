#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
chezmoi_bin="${CHEZMOI:-chezmoi}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-source-test.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

test_home="$tmp/home"
mkdir -p "$test_home"

# chezmoi on Windows, run from MSYS2 or Git Bash, takes its home from
# USERPROFILE and renders native paths.
rendered_home="$test_home"
if command -v cygpath >/dev/null; then
    rendered_home="$(cygpath -m "$test_home")"
fi

cm() {
    LLM_GATEWAY_KEY="" HOME="$test_home" USERPROFILE="$rendered_home" \
        "$chezmoi_bin" \
        --source "$repo_root" \
        --destination "$test_home" \
        "$@"
}

# On Windows the shell and tmux files go to MSYS2's home through a config with
# msys2 set, and the Windows profile gets none of them; shell_cm stands in for
# that config, here applying to the same test home.
windows=false
[ "$(cm execute-template '{{ .chezmoi.os }}')" = windows ] && windows=true
shell_cm() {
    if $windows; then
        cm --override-data '{"msys2": true}' "$@"
    else
        cm "$@"
    fi
}

# Codex owns parts of config.toml at runtime; the modify_ template must enforce
# the managed keys and carry those sections through untouched.
mkdir -p "$test_home/.codex"
cat > "$test_home/.codex/config.toml" <<'TOML'
model = "stale-model"
model_catalog_json = "/stale/catalog.json"
notify = [
  "/seeded/notifier",
  "turn-ended",
]
web_search = "live"

[projects."/seeded/project"]
trust_level = "trusted"

[mcp_servers.node_repl]
command = "/seeded/node_repl"

[mcp_servers.node_repl.env]
SEEDED = "1"

[mcp_servers.stale]
url = "https://stale.invalid"

[windows]
sandbox = "elevated"

[features]
hooks = false
apps = false

[desktop]
codeFontSize = 13

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

# The retired Codex publish guard.
mkdir -p "$test_home/.codex/hooks"
printf '%s\n' '{}' > "$test_home/.codex/hooks.json"
printf '%s\n' '#!/bin/bash' > "$test_home/.codex/hooks/confirm-publish.sh"

cm --force --no-tty apply --exclude=scripts
cm verify --exclude=scripts
test -z "$(cm status --exclude=scripts)"
if $windows; then
    for target in .bashrc .zshrc .tmux.conf .profile; do
        if cm managed --include=all | grep -Fxq "$target"; then
            echo "error: Windows profile manages $target" >&2
            exit 1
        fi
    done
    test -e "$test_home/.profile"
    shell_cm --force --no-tty apply --exclude=scripts
    shell_cm verify --exclude=scripts
fi

for target in "${retired_shell_targets[@]}"; do
    test ! -e "$target"
    printf '%s\n' '# recreated shell startup file' > "$target"
done
shell_cm --force --no-tty apply --exclude=scripts "${retired_shell_targets[@]}"
for target in "${retired_shell_targets[@]}"; do
    test ! -e "$target"
done

test ! -e "$test_home/README.md"
test ! -e "$test_home/tests"

test ! -e "$test_home/.codex/hooks.json"
test ! -e "$test_home/.codex/hooks"
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
python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' \
    "$test_home/.codex/config.toml"

for bash_startup in \
    "$test_home/.bash_profile" \
    "$test_home/.bashrc" \
    "$test_home/.env_stow.sh" \
    "$test_home/.env_login_stow.sh" \
    "$test_home/.tmux/name-session.sh"; do
    bash -n "$bash_startup"
done
for zsh_startup in "$test_home/.zprofile" "$test_home/.zshrc"; do
    zsh -n "$zsh_startup"
done

grep -Fq "excludesfile = $rendered_home/.gitignore" "$test_home/.gitconfig"
if git config --file "$test_home/.gitconfig" --get-regexp '^(user|includeif|http)\.' \
    >/dev/null || grep -Fxq '[user]' "$test_home/.gitconfig"; then
    echo "error: gitconfig has an identity, includeIf, or proxy with none configured" >&2
    exit 1
fi
# The Git identity is per machine. gitIncludeIf sections come after [user], so a
# matching include can still override gitName and gitEmail.
git_config="$tmp/gitconfig"
cm --override-data '{"gitName": "Home Name", "gitEmail": "home@example.test",
    "gitIncludeIf":
    {"hasconfig:remote.*.url:git@work-alias:**/*": "/work/gitconfig"}}' \
    cat "$test_home/.gitconfig" > "$git_config"
test "$(git config --file "$git_config" user.name)" = "Home Name"
test "$(git config --file "$git_config" user.email)" = home@example.test
test "$(git config --file "$git_config" \
    'includeIf.hasconfig:remote.*.url:git@work-alias:**/*.path')" = /work/gitconfig
test "$(grep '^\[' "$git_config" | tail -n1)" = \
    '[includeIf "hasconfig:remote.*.url:git@work-alias:**/*"]'
cm --override-data '{"gitProxy": "http://proxy.test:7890"}' \
    cat "$test_home/.gitconfig" > "$git_config"
test "$(git config --file "$git_config" http.proxy)" = http://proxy.test:7890
cm --override-data '{"gitEmail": "home@example.test"}' \
    cat "$test_home/.gitconfig" > "$git_config"
test "$(git config --file "$git_config" --get-regexp '^user\.')" = \
    'user.email home@example.test'
grep -Fq "base_dir = $rendered_home/development" \
    "$test_home/.config/ccache/ccache.conf"
grep -Fq "_development_root = \"$rendered_home/development\"" \
    "$test_home/.config/gdb/gdbinit"
python3 - "$test_home/.codex/config.toml" <<'PY'
import sys, tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)
assert config["model"] == "gpt-6.1-sol", config["model"]
assert config["model_provider"] == "amd_llm_dvue", config["model_provider"]
assert "model_catalog_json" not in config
assert config["notify"] == ["/seeded/notifier", "turn-ended"], config
assert config["web_search"] == "live", config
assert config["windows"] == {"sandbox": "elevated"}, config
assert config["mcp_servers"]["node_repl"] == {
    "command": "/seeded/node_repl", "env": {"SEEDED": "1"},
}, config["mcp_servers"]
assert "stale" not in config["mcp_servers"], config["mcp_servers"]
assert config["desktop"] == {"codeFontSize": 13}, config
assert config["features"] == {
    "auth_elicitation": True, "hooks": True, "memories": True, "apps": False,
}, config["features"]
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
config = tomllib.load(open(sys.argv[1], "rb"))
plugins = config["plugins"]
assert plugins["working-on-llvm@jinpei-skills"] == {"enabled": True}, plugins
assert plugins["amdgpu-isa-builder@jinpei-skills"] == {"enabled": False}, plugins
assert "retired@jinpei-skills" not in plugins, plugins
assert plugins["superpowers@superpowers-dev"] == {"enabled": True}, plugins
assert plugins["i-have-adhd@i-have-adhd"] == {"enabled": True}, plugins
marketplaces = config["marketplaces"]
assert marketplaces["superpowers-dev"]["source"] == (
    "https://github.com/obra/superpowers.git"
), marketplaces
assert marketplaces["i-have-adhd"]["source"] == (
    "https://github.com/ayghri/i-have-adhd.git"
), marketplaces
PY

pi_settings="$test_home/.pi/agent/settings.json"
test "$(jq -r .defaultModel "$pi_settings")" = seeded-model
test "$(jq -r .lastChangelogVersion "$pi_settings")" = 9.9.9
jq -e '.packages | index("git:github.com/lijinpei-amd/skills")' "$pi_settings" >/dev/null
test "$(jq -c .skills "$pi_settings")" = "[]"
jq -e '.packages | any(type == "object" and
    .source == "git:github.com/lijinpei/pi-extensions@feat/models-discovery-catalog-and-tests")' \
    "$pi_settings" >/dev/null
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

# A config with msys2 set manages only what MSYS2 uses, for its own home on
# Windows: the shell and tmux setup, Git, ccache, Neovim, and GDB.
test "$(cm --override-data '{"msys2": true}' managed --exclude=externals)" = \
    "$(printf '%s\n' .bash_login .bash_profile .bashenv .bashrc .config \
        .config/ccache .config/ccache/ccache.conf .config/gdb \
        .config/gdb/gdbinit .config/nvim .config/nvim/init.lua \
        .env_login_stow.sh .env_stow.sh .gitconfig .gitignore .inputrc \
        .profile .tmux .tmux.conf .tmux/name-session.sh .zlogin .zprofile \
        .zshenv .zshrc)"
test "$(cm --override-data '{"msys2": true}' managed --include=externals |
    grep -v '^\.oh-my-zsh/\|^\.tmux/plugins/[^/]*/' | sort -u)" = \
    "$(printf '%s\n' .local/share/nvim-data/site/autoload/plug.vim .oh-my-zsh \
        .tmux/plugins/tmux .tmux/plugins/tpm .tmux/plugins/vim-tmux-navigator)"

# Native Windows Neovim and ccache read %LOCALAPPDATA%, so the Windows profile
# takes them under AppData, from the same sources as ~/.config; elsewhere
# AppData is not managed.
if $windows; then
    test "$(cm managed --include=files,externals | grep -v '^\.\(claude\|codex\|pi\)/')" = \
        "$(printf '%s\n' .gitconfig .gitignore \
            AppData/Local/ccache/ccache.conf \
            AppData/Local/nvim-data/site/autoload/plug.vim \
            AppData/Local/nvim/init.lua)"
    cmp "$test_home/AppData/Local/nvim/init.lua" \
        "$repo_root/dot_config/nvim/init.lua"
    grep -Fxq "base_dir = $rendered_home/development" \
        "$test_home/AppData/Local/ccache/ccache.conf"
else
    if cm managed --include=all | grep -q '^AppData'; then
        echo "error: AppData is managed outside Windows" >&2
        exit 1
    fi
    cm managed --include=externals |
        grep -Fxq .local/share/nvim/site/autoload/plug.vim
fi

echo "source-state tests passed"
