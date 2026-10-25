# dotfiles

Personal dotfiles managed by [chezmoi](https://www.chezmoi.io/).

The repository manages:

- shell environment and prompt fragments;
- Git identity, defaults, and global ignore rules;
- Readline, tmux, and Neovim configuration;
- ccache and GDB configuration for LLVM worktrees;
- Claude Code, Codex, and pi settings, and the Codex publish guard.

The ccache, GDB, Git, Claude Code, Codex, and pi files are templates. Absolute paths are
rendered from the home directory chezmoi applies to.

## Per-Machine Settings

Values that differ between machines live in that machine's
`~/.config/chezmoi/chezmoi.toml`, which is not part of this repository:

```toml
[data]
    llmProxyBaseUrl = "http://<host>:<port>"
    deepseekApiKey = ""
    gitName = "<name>"
    gitEmail = "<address>"
    gitProxy = "http://<host>:<port>"

[data.gitIncludeIf]
    "hasconfig:remote.*.url:git@<ssh-host-alias>:**/*" = "<path to a gitconfig>"
```

| Key | Used by |
| --- | --- |
| `llmProxyBaseUrl` | Claude Code's `settings.json`, Codex's three provider URLs, and pi's `models.json`: the LLM gateway proxy, before the API route. A trailing slash is optional. |
| `deepseekApiKey` | Optional official DeepSeek API key for pi. A nonempty value adds the `deepseek` provider and includes its models in pi's scope; omitted, empty, or whitespace-only values add nothing. |
| `gitName`, `gitEmail` | `~/.gitconfig`'s `user.name` and `user.email`. There is no default: each is written only when set and non-empty. |
| `gitProxy` | `~/.gitconfig`'s `http.proxy`, such as `http://127.0.0.1:7890`, which git uses for both HTTP and HTTPS remotes. Unset or empty, none is written. |
| `gitIncludeIf` | `~/.gitconfig`'s `[includeIf]` sections: each key is a condition, each value the file to include when it holds. They come last, so an included `user.name` or `user.email` overrides `gitName` or `gitEmail`. Unset, none are written. |
| `msys2` | When true, only what MSYS2 uses is managed: the bash, zsh, and tmux setup, Git, ccache, Neovim, and GDB; see [Windows](#windows). Other per-machine keys, such as the Git identity, go in the same config. |

When `llmProxyBaseUrl` is unset or empty, Claude Code and Codex default to
`http://127.0.0.1:30101`. Pi's `models.json` is left unmanaged when neither a
nonempty `llmProxyBaseUrl` nor `deepseekApiKey` is configured. On existing
machines, replace `codexProxyBaseUrl` and `piProxyBaseUrl` with `llmProxyBaseUrl`.

Codex appends routes to `llmProxyBaseUrl`, with providers
`amd_llm` (`/OpenAI/`), `amd_llm_dvue` (`/OpenAI-dvue/`, the default), and
`amd_llm_pdue` (`/OpenAI-pdue/`). The pinned routes select deployment instances
while Codex uses canonical model names and its bundled model metadata.
Configure these Nginx routes at the chosen proxy before using Codex on a fresh
machine. Nginx injects the gateway subscription key for all three Codex routes.
Pi appends `/OpenAI` and `/Anthropic` to the same base URL.
Claude Code appends `/Anthropic`; Nginx injects the gateway subscription key.
Its settings contain a dummy API key for the client and need no gateway key
when rendered by chezmoi.
After changing the machine's `llmProxyBaseUrl`, apply all three configs:

```sh
chezmoi apply ~/.claude/settings.json ~/.codex/config.toml ~/.pi/agent/models.json
```

To enable official DeepSeek, set `deepseekApiKey` only in the machine-local
chezmoi config, never in this repository. Pi uses `https://api.deepseek.com`
and its built-in DeepSeek model catalog; the gateway URL and default model
stay unchanged. DeepSeek also works without an LLM gateway. Apply both pi files,
then restart pi to rebuild its model scope:

```sh
chmod 600 ~/.config/chezmoi/chezmoi.toml
chezmoi apply ~/.pi/agent/models.json ~/.pi/agent/settings.json
```

The rendered `models.json` is owner-only because it can contain this key.

## Windows

The Claude Code, Codex, and pi settings are `modify_` templates rather than
scripts, so they need no shell. The scripts in `.chezmoiscripts` are bash, which
Windows cannot run by itself; point chezmoi at Git Bash in
`~/.config/chezmoi/chezmoi.toml`:

```toml
[interpreters.sh]
    command = "C:/Program Files/Git/bin/bash.exe"
```

Git Bash's `$HOME` is the Windows profile, the same home chezmoi applies to.

The Windows profile also gets Git, and Neovim and ccache under
`%LOCALAPPDATA%`, where their native Windows builds look:
`AppData/Local/nvim/init.lua`, vim-plug under `AppData/Local/nvim-data`, and
`AppData/Local/ccache/ccache.conf`, rendered from the same sources as their
`~/.config` counterparts.

MSYS2 keeps its own home, `/home/<user>` under the MSYS2 root. The bash, zsh,
and tmux setup and GDB go there rather than to the Windows profile, along with
their own Git, ccache, and Neovim. Apply them through a second config,
`~/.config/chezmoi/msys2.toml`:

```toml
destDir = "C:/msys64/home/<user>"

[data]
    msys2 = true
    gitName = "<name>"
    gitEmail = "<address>"
```

```sh
chezmoi -c ~/.config/chezmoi/msys2.toml diff
chezmoi -c ~/.config/chezmoi/msys2.toml apply
```

Everything else, scripts included, is ignored under that config; the main
config leaves those files out of the Windows profile. MSYS2's Neovim and ccache
are native Windows builds too, so MSYS2 login shells set `XDG_CONFIG_HOME`,
`XDG_DATA_HOME`, and `CCACHE_CONFIGPATH` to point them at this home: config in
`~/.config`, and vim-plug under `~/.local/share/nvim-data`. ccache keeps its one
cache under `%LOCALAPPDATA%`.

The Git template adds the Git LFS filter when chezmoi finds `git-lfs` on its
own `PATH`, which on Windows is the Windows one. MSYS2's Git needs `git-lfs` on
its `PATH` as well, or LFS repositories fail there: such as
`mingw-w64-ucrt-x86_64-git-lfs`, which the UCRT64 shell puts on `PATH`.

## Fresh Machine

Install chezmoi, then initialize and apply the repository:

```sh
chezmoi init --apply git@github.com:lijinpei-amd/dotfiles.git
```

The repository is public, so HTTPS also works:

```sh
chezmoi init --apply https://github.com/lijinpei-amd/dotfiles.git
```

Bash's `~/.bash_profile` and `~/.bashrc`, plus zsh's `~/.zprofile` and
`~/.zshrc`, are managed directly. Bash login setup
lives in `~/.bash_profile`, which replaces `~/.profile`.

Removal markers keep retired startup files absent on every `chezmoi apply`:

| Target kept absent | Removal marker |
| --- | --- |
| `~/.bashenv` | `remove_dot_bashenv` |
| `~/.zshenv` | `remove_dot_zshenv` |
| `~/.zlogin` | `remove_dot_zlogin` |
| `~/.profile` | `remove_dot_profile` |
| `~/.bash_login` | `remove_dot_bash_login` |

| Shell startup | Managed script | Optional private script |
| --- | --- | --- |
| Interactive only | `~/.env_stow.sh` | `~/.env.sh` |
| Login only | `~/.env_login_stow.sh` | `~/.env_login.sh` |

Each managed script sources its corresponding private script after its own
settings. Shell startup files source only the managed scripts.

Interactive scripts load through `~/.zshrc` or `~/.bashrc`. Login scripts load
through `~/.zprofile` or `~/.bash_profile`. Interactive login shells load the
login pair before the interactive pair in both shells; noninteractive login
shells load only the login pair. Noninteractive,
non-login shells inherit exported environment variables without sourcing either
pair. `BASH_ENV` is not set.

## Daily Use

```sh
chezmoi edit ~/.codex/config.toml
chezmoi diff
chezmoi apply
chezmoi cd
git status
```

Commit and push changes from the shell opened by `chezmoi cd`. To pull and apply
the latest committed state on another machine:

```sh
chezmoi update
```

## Validation

From the source directory:

```sh
./tests/test_source_state.sh
python3 -m unittest tests.test_pi_providers
python3 -m unittest tests.test_shell_startup
python3 -m unittest tests.test_publish_hooks
```

Only intentional configuration belongs here. Private `~/.env.sh` and
`~/.env_login.sh`, Claude and Codex credentials, shell histories, caches,
sessions, project state, generated files, backups, and `~/.claude.json` are not
managed.
