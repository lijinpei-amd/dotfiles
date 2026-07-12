# dotfiles

Personal dotfiles managed by [chezmoi](https://www.chezmoi.io/).

The repository manages:

- shell environment and prompt fragments;
- Git identity, defaults, and global ignore rules;
- Readline, tmux, and Neovim configuration;
- ccache and GDB configuration for LLVM worktrees;
- Claude Code and Codex settings, publish guards, and LLVM skills.

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

The managed shell fragments retain their historical `_stow` filenames because
existing `~/.bashrc`, `~/.zshrc`, and `~/.zshenv` files source those names. The
`code_snippets/setup_dev_environment.sh` script wires the zsh fragments while
preserving existing shell startup files.

## Migrate A Stow Machine

Initialize without applying over the existing Stow links:

```sh
chezmoi init git@github.com:lijinpei-amd/dotfiles.git
```

If chezmoi was already initialized, update only its source checkout first:

```sh
git -C "$(chezmoi source-path)" pull --ff-only
```

Review the migration, then run it:

```sh
"$(chezmoi source-path)/scripts/migrate-from-stow.sh" --dry-run
"$(chezmoi source-path)/scripts/migrate-from-stow.sh"
```

The default legacy package path is
`~/development/code_snippets/dotfiles`. Override it when needed:

```sh
"$(chezmoi source-path)/scripts/migrate-from-stow.sh" \
  --stow-dir /path/to/code_snippets/dotfiles
```

The script renders and compares all desired files before changing anything. It
removes only links that resolve to an exact known Stow source, refuses unrelated
files and links, handles the old Codex skill-directory link, and restores removed
links if `chezmoi apply` fails.

If a verified legacy source has uncommitted content that differs from this
repository, the migration stops. Preserve or merge that content first. Only
after review, allow replacement with:

```sh
"$(chezmoi source-path)/scripts/migrate-from-stow.sh" \
  --accept-legacy-changes
```

The option never permits overwriting a differing non-Stow file.

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
./tests/test_migrate_from_stow.sh
python3 -m unittest tests.test_publish_hooks
```

Only intentional configuration belongs here. Private `~/.env.sh`, Claude and
Codex credentials, shell histories, caches, sessions, project state, generated
files, backups, and `~/.claude.json` are not managed.
