# dotfiles

Personal dotfiles managed by [chezmoi](https://www.chezmoi.io/).

The repository manages:

- shell environment and prompt fragments;
- Git identity, defaults, and global ignore rules;
- Readline, tmux, and Neovim configuration;
- ccache and GDB configuration for LLVM worktrees;
- Claude Code and Codex settings, and the Codex publish guard.

The ccache, GDB, Git, and Codex files are templates. Absolute paths are rendered
from the current machine's home directory.

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
