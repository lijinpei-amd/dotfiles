# dotfiles

Personal dotfiles managed by [chezmoi](https://www.chezmoi.io/).

## Bootstrap

With an existing GitHub SSH key:

```sh
chezmoi init --apply git@github.com:lijinpei-amd/dotfiles.git
```

The repository is public, so HTTPS also works:

```sh
chezmoi init --apply https://github.com/lijinpei-amd/dotfiles.git
```

## Daily use

```sh
chezmoi edit ~/.claude/settings.json
chezmoi diff
chezmoi apply
chezmoi cd
git status
```

Commit and push changes from the shell opened by `chezmoi cd`.

Only intentional configuration belongs here. Claude Code caches, history,
sessions, project state, credentials, and `~/.claude.json` are not managed.
