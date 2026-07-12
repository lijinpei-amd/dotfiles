#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: migrate-from-stow.sh [OPTIONS]

Replace links from the former code_snippets GNU Stow packages with regular
files managed by the current chezmoi source state.

Options:
  --stow-dir DIR              Legacy package root.
                              Default: ~/development/code_snippets/dotfiles
  --source-dir DIR            Chezmoi source directory.
                              Default: `chezmoi source-path`
  --dry-run                   Validate and show the planned transition only.
  --accept-legacy-changes     Replace differing content only when reached
                              through a verified legacy Stow-owned link.
  -h, --help                  Show this help.

The script never removes an unexpected file or link. Run without
--accept-legacy-changes first; use it only after reviewing reported local
changes that have already been preserved in the chezmoi repository.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

note() {
    echo "==> $*"
}

warn() {
    echo "warning: $*" >&2
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

realpath_m() {
    realpath -m -- "$1"
}

resolve_link() {
    local path="$1" link
    link=$(readlink -- "$path")
    if [[ "$link" == /* ]]; then
        realpath_m "$link"
    else
        realpath_m "$(dirname -- "$path")/$link"
    fi
}

DRY_RUN=0
ACCEPT_LEGACY_CHANGES=0
STOW_DIR="${STOW_DIR:-$HOME/development/code_snippets/dotfiles}"
SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-}"
CHEZMOI_BIN="${CHEZMOI:-chezmoi}"
DEST_DIR=$(realpath_m "$HOME")

while (($#)); do
    case "$1" in
        --stow-dir)
            (($# >= 2)) || die "--stow-dir requires a path"
            STOW_DIR="$2"
            shift 2
            ;;
        --stow-dir=*)
            STOW_DIR="${1#*=}"
            shift
            ;;
        --source-dir)
            (($# >= 2)) || die "--source-dir requires a path"
            SOURCE_DIR="$2"
            shift 2
            ;;
        --source-dir=*)
            SOURCE_DIR="${1#*=}"
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --accept-legacy-changes)
            ACCEPT_LEGACY_CHANGES=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            (($# == 0)) || die "unexpected positional arguments: $*"
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

command_exists "$CHEZMOI_BIN" || die "chezmoi not found: $CHEZMOI_BIN"
for command_name in cmp find git grep mktemp readlink realpath; do
    command_exists "$command_name" || die "required command not found: $command_name"
done

if [[ -z "$SOURCE_DIR" ]]; then
    SOURCE_DIR=$("$CHEZMOI_BIN" source-path) \
        || die "chezmoi is not initialized; run 'chezmoi init REPO' first"
fi
SOURCE_DIR=$(realpath_m "$SOURCE_DIR")
STOW_DIR=$(realpath_m "$STOW_DIR")
[[ -d "$SOURCE_DIR" ]] || die "chezmoi source directory does not exist: $SOURCE_DIR"

cm() {
    HOME="$DEST_DIR" "$CHEZMOI_BIN" \
        --source "$SOURCE_DIR" \
        --destination "$DEST_DIR" \
        "$@"
}

MANAGED_PATHS=(
    .bashrc_stow
    .claude/hooks/confirm-publish.sh
    .claude/settings.json
    .claude/skills/working-on-llvm/SKILL.md
    .claude/skills/working-on-llvm/references/local-workspace.md
    .claude/skills/working-on-llvm/references/reviewer-patterns.md
    .codex/config.toml
    .codex/hooks.json
    .codex/hooks/confirm-publish.sh
    .codex/skills/work-on-llvm/SKILL.md
    .codex/skills/work-on-llvm/agents/openai.yaml
    .codex/skills/work-on-llvm/references/debugging-and-reduction.md
    .codex/skills/work-on-llvm/references/local-workspace.md
    .codex/skills/work-on-llvm/references/reviewer-patterns.md
    .config/ccache/ccache.conf
    .config/gdb/gdbinit
    .config/nvim/init.lua
    .env_stow.sh
    .gitconfig
    .gitignore
    .inputrc
    .tmux.conf
    .tmux/name-session.sh
    .zshenv_stow
    .zshrc_stow
)

declare -A LEGACY_SOURCES=(
    [.bashrc_stow]='bash/dot-bashrc_stow'
    [.claude/hooks/confirm-publish.sh]='claude/dot-claude/hooks/confirm-publish.sh;claude/.claude/hooks/confirm-publish.sh'
    [.claude/settings.json]='claude/dot-claude/settings.json;claude/.claude/settings.json'
    [.claude/skills/working-on-llvm/SKILL.md]='claude/dot-claude/skills/working-on-llvm/SKILL.md;claude/.claude/skills/working-on-llvm/SKILL.md'
    [.claude/skills/working-on-llvm/references/local-workspace.md]='claude/dot-claude/skills/working-on-llvm/references/local-workspace.md;claude/.claude/skills/working-on-llvm/references/local-workspace.md'
    [.claude/skills/working-on-llvm/references/reviewer-patterns.md]='claude/dot-claude/skills/working-on-llvm/references/reviewer-patterns.md;claude/.claude/skills/working-on-llvm/references/reviewer-patterns.md'
    [.codex/config.toml]='codex/dot-codex/config.toml;codex/.codex/config.toml'
    [.codex/hooks.json]='codex/dot-codex/hooks.json;codex/.codex/hooks.json'
    [.codex/hooks/confirm-publish.sh]='codex/dot-codex/hooks/confirm-publish.sh;codex/.codex/hooks/confirm-publish.sh'
    [.codex/skills/work-on-llvm/SKILL.md]='codex/dot-codex/skills/work-on-llvm/SKILL.md;codex/.codex/skills/work-on-llvm/SKILL.md'
    [.codex/skills/work-on-llvm/agents/openai.yaml]='codex/dot-codex/skills/work-on-llvm/agents/openai.yaml;codex/.codex/skills/work-on-llvm/agents/openai.yaml'
    [.codex/skills/work-on-llvm/references/debugging-and-reduction.md]='codex/dot-codex/skills/work-on-llvm/references/debugging-and-reduction.md;codex/.codex/skills/work-on-llvm/references/debugging-and-reduction.md'
    [.codex/skills/work-on-llvm/references/local-workspace.md]='codex/dot-codex/skills/work-on-llvm/references/local-workspace.md;codex/.codex/skills/work-on-llvm/references/local-workspace.md'
    [.codex/skills/work-on-llvm/references/reviewer-patterns.md]='codex/dot-codex/skills/work-on-llvm/references/reviewer-patterns.md;codex/.codex/skills/work-on-llvm/references/reviewer-patterns.md'
    [.config/ccache/ccache.conf]='ccache/dot-config/ccache/ccache.conf'
    [.config/gdb/gdbinit]='gdb/dot-config/gdb/gdbinit'
    [.config/nvim/init.lua]='nvim/dot-config/nvim/init.lua'
    [.env_stow.sh]='env/dot-env_stow.sh'
    [.gitignore]='git/dot-gitignore'
    [.inputrc]='inputrc/dot-inputrc'
    [.tmux.conf]='tmux/dot-tmux.conf'
    [.tmux/name-session.sh]='tmux/dot-tmux/name-session.sh'
    [.zshenv_stow]='zsh/dot-zshenv_stow'
    [.zshrc_stow]='zsh/dot-zshrc_stow'
)

SPECIAL_REL=.codex/skills/work-on-llvm
SPECIAL_SOURCES='codex/dot-codex/skills/work-on-llvm;codex/.codex/skills/work-on-llvm'
CLEANUP_REL=sync-skills.sh
CLEANUP_SOURCES='codex/sync-skills.sh'

tmp=$(mktemp -d "${TMPDIR:-/tmp}/stow-to-chezmoi.XXXXXX")
RENDER_ROOT="$tmp/rendered"
mkdir -p "$RENDER_ROOT"

TRANSACTION_ACTIVE=0
declare -a REMOVED_PATHS=()
declare -a REMOVED_LINKS=()
declare -a REMOVED_TYPES=()
declare -a OWNED_PATHS=()
declare -A OWNED_LINK_TEXT=()
declare -A TARGET_REL=()
SPECIAL_OWNED=0
SPECIAL_LINK_TEXT=
CLEANUP_OWNED=0
CLEANUP_LINK_TEXT=

restore_link() {
    local path="$1" link="$2"
    mkdir -p -- "$(dirname -- "$path")"
    ln -s -- "$link" "$path"
}

special_tree_matches_rendered() {
    local path="$1" actual rel expected
    [[ -d "$path" && ! -L "$path" ]] || return 1
    if find "$path" -mindepth 1 \! -type d \! -type f -print -quit | grep -q .; then
        return 1
    fi
    while IFS= read -r -d '' actual; do
        rel=${actual#"$path"/}
        case "$rel" in
            agents|references) ;;
            *) return 1 ;;
        esac
    done < <(find "$path" -mindepth 1 -type d -print0)
    while IFS= read -r -d '' actual; do
        rel=${actual#"$path"/}
        expected="$RENDER_ROOT/$SPECIAL_REL/$rel"
        [[ -f "$expected" ]] || return 1
        cmp -s -- "$actual" "$expected" || return 1
    done < <(find "$path" -type f -print0)
}

rollback() {
    local i path link type rel
    set +e
    warn "migration failed; restoring verified legacy links"
    for ((i=${#REMOVED_PATHS[@]} - 1; i >= 0; i--)); do
        path=${REMOVED_PATHS[$i]}
        link=${REMOVED_LINKS[$i]}
        type=${REMOVED_TYPES[$i]}
        if [[ -L "$path" && "$(readlink -- "$path")" == "$link" ]]; then
            continue
        fi
        if [[ ! -e "$path" && ! -L "$path" ]]; then
            restore_link "$path" "$link" || warn "could not restore $path"
            continue
        fi
        case "$type" in
            file)
                rel=${TARGET_REL[$path]:-}
                if [[ -n "$rel" && -f "$path" ]] \
                    && cmp -s -- "$path" "$RENDER_ROOT/$rel"; then
                    if ! rm -- "$path" || ! restore_link "$path" "$link"; then
                        warn "could not restore $path"
                    fi
                else
                    warn "not overwriting unexpected replacement at $path"
                fi
                ;;
            special)
                if special_tree_matches_rendered "$path"; then
                    if ! rm -rf -- "$path" || ! restore_link "$path" "$link"; then
                        warn "could not restore $path"
                    fi
                else
                    warn "not overwriting unexpected replacement tree at $path"
                fi
                ;;
            cleanup)
                warn "not overwriting unexpected replacement at $path"
                ;;
        esac
    done
}

on_exit() {
    local status=$?
    trap - EXIT
    if ((TRANSACTION_ACTIVE)); then
        rollback
    fi
    rm -rf -- "$tmp"
    exit "$status"
}
trap on_exit EXIT

match_legacy_source() {
    local resolved="$1" candidates="$2" candidate expected
    local -a candidate_list=()
    IFS=';' read -r -a candidate_list <<< "$candidates"
    for candidate in "${candidate_list[@]}"; do
        expected=$(realpath_m "$STOW_DIR/$candidate")
        if [[ "$resolved" == "$expected" ]]; then
            printf '%s\n' "$expected"
            return 0
        fi
    done
    return 1
}

legacy_source_is_clean() {
    local source="$1" repo_root rel
    repo_root=$(realpath_m "$(dirname -- "$STOW_DIR")")
    [[ -d "$repo_root/.git" ]] || return 1
    case "$source" in
        "$repo_root"/*) rel=${source#"$repo_root"/} ;;
        *) return 1 ;;
    esac
    git -C "$repo_root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 \
        || return 1
    git -C "$repo_root" diff --quiet -- "$rel" || return 1
    git -C "$repo_root" diff --cached --quiet -- "$rel" || return 1
}

check_legacy_content() {
    local target="$1" rendered="$2" source="$3"
    cmp -s -- "$target" "$rendered" && return 0
    if legacy_source_is_clean "$source"; then
        warn "replacing clean legacy content with current chezmoi state: $target"
        return 0
    fi
    if ((ACCEPT_LEGACY_CHANGES)); then
        warn "replacing reviewed modified legacy content: $target"
        return 0
    fi
    die "legacy content differs from chezmoi state: $target
       Preserve or merge it first, or rerun with --accept-legacy-changes after review."
}

note "rendering and validating chezmoi source state"
for rel in "${MANAGED_PATHS[@]}"; do
    target="$DEST_DIR/$rel"
    rendered="$RENDER_ROOT/$rel"
    mkdir -p -- "$(dirname -- "$rendered")"
    cm cat "$target" > "$rendered" \
        || die "target is not renderable from chezmoi source state: $target"
    TARGET_REL["$target"]="$rel"
done

APPLY_RELS=(
    .bashrc_stow
    .claude
    .codex
    .config
    .env_stow.sh
    .gitconfig
    .gitignore
    .inputrc
    .tmux
    .tmux.conf
    .zshenv_stow
    .zshrc_stow
)
APPLY_TARGETS=()
for rel in "${APPLY_RELS[@]}"; do
    APPLY_TARGETS+=("$DEST_DIR/$rel")
done

special_target="$DEST_DIR/$SPECIAL_REL"
if [[ -L "$special_target" ]]; then
    special_resolved=$(resolve_link "$special_target")
    match_legacy_source "$special_resolved" "$SPECIAL_SOURCES" >/dev/null \
        || die "unexpected symlink at $special_target -> $(readlink -- "$special_target")"
    SPECIAL_OWNED=1
    SPECIAL_LINK_TEXT=$(readlink -- "$special_target")
elif [[ -e "$special_target" && ! -d "$special_target" ]]; then
    die "expected a directory at $special_target"
fi

note "checking destination files before making changes"
for rel in "${MANAGED_PATHS[@]}"; do
    target="$DEST_DIR/$rel"
    rendered="$RENDER_ROOT/$rel"

    if [[ -L "$target" ]]; then
        resolved=$(resolve_link "$target")
        candidates=${LEGACY_SOURCES[$rel]:-}
        [[ -n "$candidates" ]] \
            || die "unexpected symlink at $target -> $(readlink -- "$target")"
        matched_source=$(match_legacy_source "$resolved" "$candidates") \
            || die "unexpected symlink at $target -> $(readlink -- "$target")"
        if [[ -e "$target" ]]; then
            [[ -f "$target" ]] || die "legacy target is not a regular file: $target"
            check_legacy_content "$target" "$rendered" "$matched_source"
        else
            warn "legacy link is broken and will be replaced: $target"
        fi
        OWNED_PATHS+=("$target")
        OWNED_LINK_TEXT["$target"]=$(readlink -- "$target")
        continue
    fi

    if ((SPECIAL_OWNED)) && [[ "$rel" == "$SPECIAL_REL/"* ]]; then
        if [[ -e "$target" ]]; then
            [[ -f "$target" ]] || die "legacy skill target is not a regular file: $target"
            check_legacy_content "$target" "$rendered" "$(realpath_m "$target")"
        fi
        continue
    fi

    if [[ -e "$target" ]]; then
        [[ -f "$target" ]] || die "expected a regular file at $target"
        cmp -s -- "$target" "$rendered" \
            || die "existing non-Stow file differs from chezmoi state: $target
       It was left untouched; merge or move it before retrying."
    fi
done

cleanup_target="$DEST_DIR/$CLEANUP_REL"
if [[ -L "$cleanup_target" ]]; then
    cleanup_resolved=$(resolve_link "$cleanup_target")
    if match_legacy_source "$cleanup_resolved" "$CLEANUP_SOURCES" >/dev/null; then
        CLEANUP_OWNED=1
        CLEANUP_LINK_TEXT=$(readlink -- "$cleanup_target")
    else
        warn "leaving unrelated symlink untouched: $cleanup_target"
    fi
elif [[ -e "$cleanup_target" ]]; then
    warn "leaving unrelated file untouched: $cleanup_target"
fi

note "planned legacy link removals"
for target in "${OWNED_PATHS[@]}"; do
    echo "  $target -> ${OWNED_LINK_TEXT[$target]}"
done
if ((SPECIAL_OWNED)); then
    echo "  $special_target -> $SPECIAL_LINK_TEXT"
fi
if ((CLEANUP_OWNED)); then
    echo "  $cleanup_target -> $CLEANUP_LINK_TEXT (obsolete helper)"
fi
if ((${#OWNED_PATHS[@]} == 0 && !SPECIAL_OWNED && !CLEANUP_OWNED)); then
    echo "  (none; destination is already unstowed)"
fi

if ((DRY_RUN)); then
    note "validating chezmoi apply in dry-run mode"
    cm --dry-run --force --no-tty apply "${APPLY_TARGETS[@]}"
    note "dry run complete; no files were changed"
    exit 0
fi

record_and_unlink() {
    local type="$1" path="$2" expected_link="$3"
    [[ -L "$path" ]] || die "path changed after preflight: $path"
    [[ "$(readlink -- "$path")" == "$expected_link" ]] \
        || die "link changed after preflight: $path"
    REMOVED_TYPES+=("$type")
    REMOVED_PATHS+=("$path")
    REMOVED_LINKS+=("$expected_link")
    rm -- "$path"
}

TRANSACTION_ACTIVE=1
for target in "${OWNED_PATHS[@]}"; do
    record_and_unlink file "$target" "${OWNED_LINK_TEXT[$target]}"
done
if ((SPECIAL_OWNED)); then
    record_and_unlink special "$special_target" "$SPECIAL_LINK_TEXT"
fi
if ((CLEANUP_OWNED)); then
    record_and_unlink cleanup "$cleanup_target" "$CLEANUP_LINK_TEXT"
fi

note "applying chezmoi state"
cm --force --no-tty apply "${APPLY_TARGETS[@]}"
cm verify "${APPLY_TARGETS[@]}"

status_output=$(cm status)
[[ -z "$status_output" ]] \
    || die "chezmoi still reports differences after apply:
$status_output"
[[ -d "$special_target" && ! -L "$special_target" ]] \
    || die "Codex skill directory was not materialized correctly: $special_target"

TRANSACTION_ACTIVE=0
note "migration complete; chezmoi now owns ${#MANAGED_PATHS[@]} files"
