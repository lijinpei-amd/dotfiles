alias vim=nvim

# Ensure a UTF-8 locale so multibyte/box-drawing glyphs (tmux panes, Claude
# Code's TUI, etc.) render instead of collapsing to '_'. tmux's persistent
# server can start without SSH-forwarded LANG/LC_*, leaving its panes in the
# C/POSIX locale. Only set a default when the inherited locale isn't already
# UTF-8, so a forwarded locale (e.g. en_US.UTF-8) is preserved. C.UTF-8 is the
# UTF-8 locale available without locale-gen.
case "${LC_ALL:-${LANG:-}}" in
    *[Uu][Tt][Ff]8* | *[Uu][Tt][Ff]-8*) ;;
    *) export LANG=C.UTF-8 ;;
esac

# Prepend to PATH only if not already present, so this layer (sourced on every
# shell, including nested ones) doesn't accumulate duplicate entries.
path_prepend() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$1:$PATH" ;;
    esac
}
path_prepend "$HOME/.local/bin"
path_prepend "$HOME/proot/nvim/bin"
path_prepend "$HOME/proot/bin"
# Go toolchain (installed under ~/proot/go), when present. Guarded like the
# entries above so hosts without it are unaffected and nested shells don't
# accumulate duplicate PATH entries.
if [ -d "$HOME/proot/go" ]; then
    export GOROOT="$HOME/proot/go"
    path_prepend "$GOROOT/bin"
fi
export PATH
[ -r "$HOME/.local/bin/env" ] && source "$HOME/.local/bin/env"
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Rocq prover (formerly Coq), built into its own opam root by build_rocq.sh.
# We export the switch environment directly rather than `eval "$(opam env ...)"`
# to avoid spawning opam on every (including nested) shell; the values mirror
# opam env's output for this switch. Keep the switch name in sync with
# build_rocq.sh. Guarded on the prefix existing so shells on hosts without Rocq
# are unaffected.
__rocq_prefix="$HOME/proot/rocq/CP.2025.08.0~9.0~2025.08"
if [ -d "$__rocq_prefix" ]; then
    # Everything (incl. OPAMROOT) stays inside the guard so hosts without this
    # Rocq build keep their normal opam setup (default root ~/.opam) untouched.
    export OPAMROOT="$HOME/proot/rocq"
    export OPAMSWITCH="CP.2025.08.0~9.0~2025.08"
    export OPAM_SWITCH_PREFIX="$__rocq_prefix"
    # Prepend the switch's OCaml stub/lib dirs (opam env's order), but only if
    # not already present, so re-sourcing in nested shells doesn't accumulate
    # duplicates -- same discipline as path_prepend above.
    for __d in "$__rocq_prefix/lib/stublibs" "$__rocq_prefix/lib/ocaml/stublibs" "$__rocq_prefix/lib/ocaml"; do
        case ":${CAML_LD_LIBRARY_PATH:-}:" in
            *":$__d:"*) ;;
            *) CAML_LD_LIBRARY_PATH="${CAML_LD_LIBRARY_PATH:+$CAML_LD_LIBRARY_PATH:}$__d" ;;
        esac
    done
    export CAML_LD_LIBRARY_PATH
    export OCAML_TOPLEVEL_PATH="$__rocq_prefix/lib/toplevel"
    path_prepend "$__rocq_prefix/bin"
    export PATH
    unset __d
fi
unset __rocq_prefix
