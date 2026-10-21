# dotfiles

Personal dotfiles managed by [chezmoi](https://www.chezmoi.io/).

The repository manages:

- shell environment and prompt fragments;
- Git identity, defaults, and global ignore rules;
- Readline, tmux, and Neovim configuration;
- ccache and GDB configuration for LLVM worktrees;
- Claude Code, Codex, and pi settings, and the Codex publish guard.

The ccache, GDB, Git, Claude Code, Codex, and pi files are templates. Absolute paths are
rendered from the current machine's home directory.

## Per-Machine Settings

Values that differ between machines live in that machine's
`~/.config/chezmoi/chezmoi.toml`, which is not part of this repository:

```toml
[data]
    llmProxyBaseUrl = "http://<host>:<port>"
```

| Key | Used by |
| --- | --- |
| `llmProxyBaseUrl` | Claude Code's `settings.json`, Codex's three provider URLs, and pi's `models.json`: the LLM gateway proxy, before the API route. A trailing slash is optional. |

When `llmProxyBaseUrl` is unset or empty, Claude Code and Codex default to
`http://127.0.0.1:30101`. When the key is unset, pi's `models.json` is left
unmanaged. On existing machines, replace `codexProxyBaseUrl` and
`piProxyBaseUrl` with `llmProxyBaseUrl`.

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

## Fresh Machine

Install chezmoi, then initialize and apply the repository:

```sh
chezmoi init --apply git@github.com:lijinpei-amd/dotfiles.git
```

The repository is public, so HTTPS also works:

```sh
chezmoi init --apply https://github.com/lijinpei-amd/dotfiles.git
```

`~/.bashrc`, `~/.zshrc`, and `~/.zshenv` are managed directly. They source the
shared environment layer, which keeps its historical `~/.env_stow.sh` name.

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
python3 -m unittest tests.test_publish_hooks
```

Only intentional configuration belongs here. Private `~/.env.sh`, Claude and
Codex credentials, shell histories, caches, sessions, project state, generated
files, backups, and `~/.claude.json` are not managed.
