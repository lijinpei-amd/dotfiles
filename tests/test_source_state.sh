#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# Absolute, so tests can run chezmoi with a PATH that lacks it.
chezmoi_bin="$(command -v -- "${CHEZMOI:-chezmoi}")"
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

[marketplaces.superpowers-dev]
source_type = "local"
source = "/stale/superpowers"

[marketplaces.codex-owned]
source_type = "local"
source = "/seeded/marketplace"

[plugins."superpowers@superpowers-dev"]
enabled = false

[plugins."retired@superpowers-dev"]
enabled = true

[plugins."visualize@openai-bundled"]
enabled = true

[plugins."hand-added@elsewhere"]
enabled = true

[marketplaces.jinpei-skills]
source_type = "git"
source = "https://github.com/lijinpei-amd/skills.git"

[plugins."working-on-llvm@jinpei-skills"]
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
# Skills come from the skills CLI; only hook-carrying plugins stay.
assert settings["enabledPlugins"]["superpowers@superpowers-dev"] is True
assert settings["enabledPlugins"]["i-have-adhd@i-have-adhd"] is True
for retired in ("jinpei-skills", "mattpocock", "anthropic-agent-skills"):
    assert not any(p.endswith("@" + retired) for p in settings["enabledPlugins"])
    assert retired not in settings["extraKnownMarketplaces"]
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
if grep -Fq '/stale/superpowers' "$test_home/.codex/config.toml"; then
    echo "error: Codex config kept a stale superpowers-dev marketplace" >&2
    exit 1
fi
if grep -Fq 'jinpei-skills' "$test_home/.codex/config.toml"; then
    echo "error: Codex config kept the retired jinpei-skills plugins" >&2
    exit 1
fi
# Managed tables are corrected where Codex put them, not moved: Codex inserts
# its own tables beside them, and moving them would never settle.
header_line() {
    grep -nF "$1" "$test_home/.codex/config.toml" | cut -d: -f1
}
test "$(header_line '[marketplaces.superpowers-dev]')" -lt "$(header_line '[marketplaces.codex-owned]')"
test "$(header_line '[marketplaces.codex-owned]')" -lt \
    "$(header_line '[plugins."superpowers@superpowers-dev"]')"
python3 - "$test_home/.codex/config.toml" <<'PY'
import sys, tomllib
config = tomllib.load(open(sys.argv[1], "rb"))
plugins = config["plugins"]
assert "retired@superpowers-dev" not in plugins, plugins
# Plugins from other marketplaces stay, disabled: skills come only from the
# managed plugins and the skills CLI.
assert plugins["visualize@openai-bundled"] == {"enabled": False}, plugins
assert plugins["hand-added@elsewhere"] == {"enabled": False}, plugins
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
jq -e '.packages | index("https://github.com/ayghri/i-have-adhd")' "$pi_settings" >/dev/null
if jq -e '.packages | index("git:github.com/lijinpei-amd/skills")' "$pi_settings" >/dev/null; then
    echo "error: pi settings kept the retired jinpei-skills package" >&2
    exit 1
fi
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

skills_cli="$(cm execute-template '{{ .skillsCli }}')"
read -r -a listed_skills <<< \
    "$(cm execute-template '{{ range .agentSkills }}{{ join " " .skills }} {{ end }}')"
listed="${listed_skills[0]}"
last_listed="${listed_skills[${#listed_skills[@]} - 1]}"

# The skill directories are exact_ and ignore the listed skills, so chezmoi
# status shows every other entry as one to delete, apply deletes it, and
# Codex's bundled .system skills are left alone.
mkdir -p "$test_home/.agents/skills/$listed/references" \
    "$test_home/.agents/skills/stray-dir" \
    "$test_home/.codex/skills/.system/imagegen" \
    "$test_home/.codex/skills/stray-codex"
ln -s "../../.agents/skills/$listed" "$test_home/.claude/skills/$listed"
ln -s ../../.agents/skills/stray-dir "$test_home/.claude/skills/stray-link"
test "$(cm status --exclude=scripts)" = "$(printf ' D %s\n' \
    .agents/skills/stray-dir .claude/skills/stray-link .codex/skills/stray-codex)"
cm --force --no-tty apply --exclude=scripts
test -z "$(cm status --exclude=scripts)"
test -d "$test_home/.agents/skills/$listed/references"
test -e "$test_home/.claude/skills/$listed"
test -d "$test_home/.codex/skills/.system/imagegen"
test ! -e "$test_home/.agents/skills/stray-dir"
test ! -L "$test_home/.claude/skills/stray-link"
test ! -e "$test_home/.codex/skills/stray-codex"

# The skill scripts render and run against the test home with a controlled
# PATH: $tmp/minbin holds only rm, and $tmp/bin holds stubs for npx, node, and
# claude that record their arguments.
mkdir -p "$tmp/minbin" "$tmp/bin"
ln -s "$(command -v rm)" "$tmp/minbin/rm"
for tool in npx node claude; do
    printf '#!/bin/sh\necho "$*" >> "%s/%s-args"\n' "$tmp" "$tool" > "$tmp/bin/$tool"
    chmod +x "$tmp/bin/$tool"
done
stubs="$tmp/bin:$tmp/minbin"
render_script() { # name path
    PATH="$2" XDG_STATE_HOME="" cm execute-template \
        < "$repo_root/.chezmoiscripts/$1" > "$tmp/script.sh"
}
run_script() { # name path
    render_script "$@"
    HOME="$test_home" XDG_STATE_HOME="" PATH="$2" "$BASH" "$tmp/script.sh" \
        2> "$tmp/stderr"
}
renders_empty() { # name path
    render_script "$@"
    ! grep -q '[^[:space:]]' "$tmp/script.sh"
}

# With nothing to remove, the prune and retire scripts render empty, so
# chezmoi status and diff stay clean.
renders_empty run_before_skills-prune.sh.tmpl "$stubs"
renders_empty run_before_retire-skill-plugins.sh.tmpl "$stubs"
lock="$test_home/.agents/.skill-lock.json"
printf '{"version": 3, "skills": {"%s": {}}}' "$listed" > "$lock"
renders_empty run_before_skills-prune.sh.tmpl "$stubs"

# A skill the lock tracks but the list lacks is removed through the skills
# CLI, so `npx skills update` cannot reinstall it; without npx the script fails,
# stopping the apply before chezmoi deletes the folder.
printf '{"version": 3, "skills": {"%s": {}, "stray-tracked": {}}}' "$listed" \
    > "$lock"
run_script run_before_skills-prune.sh.tmpl "$stubs"
test "$(cat "$tmp/npx-args")" = "-y $skills_cli remove --global --yes stray-tracked"
if run_script run_before_skills-prune.sh.tmpl "$tmp/minbin"; then
    echo "error: the prune script passed without npx" >&2
    exit 1
fi
grep -Fq 'stray-tracked' "$tmp/stderr"
rm -- "$lock" "$tmp/npx-args"

# The install script adds each source's listed skills to all three agents,
# then fails while a listed skill is missing from either skill directory, as
# when the stub npx installs nothing, and without npx warns instead.
for name in "${listed_skills[@]}"; do
    [ "$name" = "$last_listed" ] && continue
    mkdir -p "$test_home/.agents/skills/$name"
    touch "$test_home/.agents/skills/$name/SKILL.md"
    ln -sfn "../../.agents/skills/$name" "$test_home/.claude/skills/$name"
done
if run_script run_onchange_after_skills-install.sh.tmpl "$stubs"; then
    echo "error: the install script passed with $last_listed missing" >&2
    exit 1
fi
grep -Fq "not installed: $last_listed." "$tmp/stderr"
test "$(cat "$tmp/npx-args")" = "$(cm execute-template \
    '{{ range $source, $pin := .agentSkills }}-y {{ $.skillsCli }} add {{ $source }}@{{ $pin.commit }} --global --agent claude-code codex pi --yes --skill {{ join " " $pin.skills }}{{ "\n" }}{{ end }}')"
mkdir -p "$test_home/.agents/skills/$last_listed"
touch "$test_home/.agents/skills/$last_listed/SKILL.md"
ln -s "../../.agents/skills/$last_listed" "$test_home/.claude/skills/$last_listed"
run_script run_onchange_after_skills-install.sh.tmpl "$stubs"
run_script run_onchange_after_skills-install.sh.tmpl "$tmp/minbin"
grep -Fq 'npx is not on PATH' "$tmp/stderr"
# A source marked submodules: false is added with submodule.active matching
# no path, so the CLI's `git submodule update --init` clones none; others keep
# their submodules.
cm --override-data '{"agentSkills": {"anthropics/skills": {"submodules": false}}}' \
    execute-template < "$repo_root/.chezmoiscripts/run_onchange_after_skills-install.sh.tmpl" \
    > "$tmp/script.sh"
grep -B2 -F 'add anthropics/skills@' "$tmp/script.sh" | grep -Fq 'GIT_CONFIG_KEY_0=submodule.active'
grep -B2 -F 'add mattpocock/skills@' "$tmp/script.sh" > "$tmp/mattpocock"
if grep -Fq 'GIT_CONFIG' "$tmp/mattpocock"; then
    echo "error: the install script skipped submodules of an unmarked source" >&2
    exit 1
fi
# Each source is pinned to a full commit: the CLI would take a short one for a
# skill name, so the install script refuses to render with one.
if cm --override-data '{"agentSkills": {"anthropics/skills": {"commit": "e4bb5d9"}}}' \
    execute-template < "$repo_root/.chezmoiscripts/run_onchange_after_skills-install.sh.tmpl" \
    > /dev/null 2>&1; then
    echo "error: the install script rendered with a short commit" >&2
    exit 1
fi

# The retire script deletes Codex's and pi's caches of the retired plugins,
# uninstalls Claude's through the claude CLI, warns when claude is missing,
# and renders empty once nothing is left.
mkdir -p "$test_home/.codex/plugins/cache/jinpei-skills/working-on-llvm/1.0.0" \
    "$test_home/.pi/agent/git/github.com/lijinpei-amd/skills" \
    "$test_home/.claude/plugins"
printf '%s' '{"version": 2, "plugins": {"working-on-llvm@jinpei-skills": [],
    "superpowers@superpowers-dev": []}}' \
    > "$test_home/.claude/plugins/installed_plugins.json"
printf '%s' '{"jinpei-skills": {}, "superpowers-dev": {}}' \
    > "$test_home/.claude/plugins/known_marketplaces.json"
run_script run_before_retire-skill-plugins.sh.tmpl "$tmp/minbin"
test ! -e "$test_home/.codex/plugins/cache/jinpei-skills"
test ! -e "$test_home/.pi/agent/git/github.com/lijinpei-amd/skills"
grep -Fq 'claude is not on PATH' "$tmp/stderr"
run_script run_before_retire-skill-plugins.sh.tmpl "$stubs"
test "$(cat "$tmp/claude-args")" = "$(printf '%s\n' \
    'plugin uninstall working-on-llvm@jinpei-skills' \
    'plugin marketplace remove jinpei-skills')"
printf '%s' '{"version": 2, "plugins": {"superpowers@superpowers-dev": []}}' \
    > "$test_home/.claude/plugins/installed_plugins.json"
printf '%s' '{"superpowers-dev": {}}' > "$test_home/.claude/plugins/known_marketplaces.json"
renders_empty run_before_retire-skill-plugins.sh.tmpl "$stubs"

# The Codex marketplace upgrade adds each enabled plugin missing from the
# cache, which in the config chezmoi wrote means only the managed ones, then
# puts that config back.
printf '#!/bin/sh\necho "$*" >> "%s/codex-args"\n' "$tmp" > "$tmp/bin/codex"
chmod +x "$tmp/bin/codex"
cp -p "$test_home/.codex/config.toml" "$tmp/codex-config.toml"
run_script run_onchange_after_codex-marketplace-upgrade.sh.tmpl "$tmp/bin:$PATH"
test "$(cat "$tmp/codex-args")" = "$(printf '%s\n' \
    'plugin marketplace upgrade' \
    'plugin add superpowers@superpowers-dev' \
    'plugin add i-have-adhd@i-have-adhd')"
cmp "$tmp/codex-config.toml" "$test_home/.codex/config.toml"

for script in "$repo_root"/.chezmoiscripts/*; do
    if [[ $script == *.tmpl ]]; then
        cm execute-template < "$script" | bash -n
    else
        bash -n "$script"
    fi
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
