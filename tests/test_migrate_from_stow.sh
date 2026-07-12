#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
migrate="$repo_root/scripts/migrate-from-stow.sh"
chezmoi_bin="${CHEZMOI:-$(command -v chezmoi)}"

new_fixture() {
    fixture=$(mktemp -d "${TMPDIR:-/tmp}/stow-migration-test.XXXXXX")
    home="$fixture/home"
    stow_dir="$home/development/code_snippets/dotfiles"
    mkdir -p "$home" "$stow_dir"
}

cleanup_fixture() {
    rm -rf -- "$fixture"
}

cm() {
    HOME="$home" "$chezmoi_bin" \
        --source "$repo_root" \
        --destination "$home" \
        "$@"
}

render_to() {
    local target_rel="$1" output="$2"
    mkdir -p -- "$(dirname -- "$output")"
    cm cat "$home/$target_rel" > "$output"
}

make_owned_file_link() {
    local target_rel="$1" source_rel="$2" source
    source="$stow_dir/$source_rel"
    render_to "$target_rel" "$source"
    mkdir -p -- "$(dirname -- "$home/$target_rel")"
    ln -s -- "$source" "$home/$target_rel"
}

run_migration() {
    HOME="$home" CHEZMOI="$chezmoi_bin" CHEZMOI_SOURCE_DIR="$repo_root" \
        "$migrate" --stow-dir "$stow_dir" "$@"
}

assert_fails() {
    local output_file="$1"
    shift
    if "$@" >"$output_file" 2>&1; then
        echo "error: command unexpectedly succeeded: $*" >&2
        return 1
    fi
}

test_success_and_idempotence() (
    new_fixture
    trap cleanup_fixture EXIT

    make_owned_file_link .bashrc_stow bash/dot-bashrc_stow

    skill_source="$stow_dir/codex/dot-codex/skills/work-on-llvm"
    for rel in \
        SKILL.md \
        agents/openai.yaml \
        references/debugging-and-reduction.md \
        references/local-workspace.md \
        references/reviewer-patterns.md; do
        render_to ".codex/skills/work-on-llvm/$rel" "$skill_source/$rel"
    done
    mkdir -p "$home/.codex/skills"
    ln -s -- "$skill_source" "$home/.codex/skills/work-on-llvm"

    mkdir -p "$stow_dir/codex"
    printf '%s\n' '# obsolete helper' > "$stow_dir/codex/sync-skills.sh"
    ln -s -- "$stow_dir/codex/sync-skills.sh" "$home/sync-skills.sh"

    run_migration > "$fixture/first.log"

    test -f "$home/.bashrc_stow"
    test ! -L "$home/.bashrc_stow"
    test -d "$home/.codex/skills/work-on-llvm"
    test ! -L "$home/.codex/skills/work-on-llvm"
    test ! -e "$home/sync-skills.sh"
    test -x "$home/.codex/hooks/confirm-publish.sh"
    test -z "$(cm status)"
    cm verify

    run_migration > "$fixture/second.log"
    grep -Fq '(none; destination is already unstowed)' "$fixture/second.log"
    test -z "$(cm status)"
)

test_dry_run_changes_nothing() (
    new_fixture
    trap cleanup_fixture EXIT

    make_owned_file_link .bashrc_stow bash/dot-bashrc_stow
    before=$(readlink -- "$home/.bashrc_stow")
    run_migration --dry-run > "$fixture/dry-run.log"

    test -L "$home/.bashrc_stow"
    test "$(readlink -- "$home/.bashrc_stow")" = "$before"
    test ! -e "$home/.gitconfig"
    grep -Fq 'no files were changed' "$fixture/dry-run.log"
)

test_unexpected_symlink_is_refused() (
    new_fixture
    trap cleanup_fixture EXIT

    printf '%s\n' unrelated > "$fixture/unrelated"
    ln -s -- "$fixture/unrelated" "$home/.bashrc_stow"
    assert_fails "$fixture/error.log" run_migration

    test -L "$home/.bashrc_stow"
    grep -Fq 'unexpected symlink' "$fixture/error.log"
)

test_modified_legacy_content_requires_opt_in() (
    new_fixture
    trap cleanup_fixture EXIT

    source="$stow_dir/bash/dot-bashrc_stow"
    mkdir -p "$(dirname -- "$source")"
    printf '%s\n' 'local unpreserved change' > "$source"
    ln -s -- "$source" "$home/.bashrc_stow"

    assert_fails "$fixture/error.log" run_migration
    test -L "$home/.bashrc_stow"
    grep -Fq 'legacy content differs' "$fixture/error.log"

    run_migration --accept-legacy-changes > "$fixture/accepted.log" 2>&1
    test -f "$home/.bashrc_stow"
    test ! -L "$home/.bashrc_stow"
    cmp -s "$home/.bashrc_stow" <(cm cat "$home/.bashrc_stow")
)

test_non_stow_file_is_never_overwritten() (
    new_fixture
    trap cleanup_fixture EXIT

    printf '%s\n' '[user]' 'name = Local User' > "$home/.gitconfig"
    cp "$home/.gitconfig" "$fixture/before"
    assert_fails "$fixture/error.log" run_migration --accept-legacy-changes

    cmp -s "$home/.gitconfig" "$fixture/before"
    grep -Fq 'existing non-Stow file differs' "$fixture/error.log"
)

test_apply_failure_restores_removed_links() (
    new_fixture
    trap cleanup_fixture EXIT

    make_owned_file_link .bashrc_stow bash/dot-bashrc_stow
    original_link=$(readlink -- "$home/.bashrc_stow")

    fake_chezmoi="$fixture/chezmoi-fail-apply"
    cat > "$fake_chezmoi" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
    if [[ "\$arg" == apply ]]; then
        exit 73
    fi
done
exec "$chezmoi_bin" "\$@"
EOF
    chmod +x "$fake_chezmoi"

    if HOME="$home" CHEZMOI="$fake_chezmoi" CHEZMOI_SOURCE_DIR="$repo_root" \
        "$migrate" --stow-dir "$stow_dir" >"$fixture/error.log" 2>&1; then
        echo 'error: forced apply failure unexpectedly succeeded' >&2
        return 1
    fi

    test -L "$home/.bashrc_stow"
    test "$(readlink -- "$home/.bashrc_stow")" = "$original_link"
    grep -Fq 'restoring verified legacy links' "$fixture/error.log"
)

test_success_and_idempotence
test_dry_run_changes_nothing
test_unexpected_symlink_is_refused
test_modified_legacy_content_requires_opt_in
test_non_stow_file_is_never_overwritten
test_apply_failure_restores_removed_links

echo 'stow migration tests passed'
