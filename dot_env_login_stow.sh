# Shared login environment (managed by chezmoi).
# Login shells may be non-interactive, so define the helper here as well.
path_prepend() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$1:$PATH" ;;
    esac
}

path_prepend "$HOME/.local/bin"
path_prepend "$HOME/proot/nvim/bin"
path_prepend "$HOME/proot/bin"

# Go toolchain (installed under ~/proot/go), when present.
if [ -d "$HOME/proot/go" ]; then
    export GOROOT="$HOME/proot/go"
    path_prepend "$GOROOT/bin"
fi
export PATH
[ -r "$HOME/.local/bin/env" ] && source "$HOME/.local/bin/env"

# MSYS2's Neovim and ccache are native Windows programs, which look for their
# config under %LOCALAPPDATA% rather than in this home. Point them here; MSYS2
# converts these paths to Windows form when it starts a native program.
# Their UCRT64 builds, with gdb and git-lfs, live in /ucrt64/bin, which only the
# UCRT64 shell puts on PATH. Elsewhere put it right after /usr/bin, so MSYS2's
# own tools still come first but these beat Windows copies on an inherited PATH.
if [ -n "${MSYSTEM:-}" ]; then
    case ":$PATH:" in
        *:/ucrt64/bin:*) ;;
        *:/usr/bin:*)
            PATH=":$PATH:"
            PATH="${PATH/:\/usr\/bin:/:/usr/bin:/ucrt64/bin:}"
            PATH="${PATH#:}"
            PATH="${PATH%:}"
            ;;
        *) PATH="$PATH:/ucrt64/bin" ;;
    esac
    export PATH
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_DATA_HOME="$HOME/.local/share"
    export CCACHE_CONFIGPATH="$XDG_CONFIG_HOME/ccache/ccache.conf"
fi

# Rocq prover (formerly Coq), built into its own opam root by build_rocq.sh.
# We export the switch environment directly rather than `eval "$(opam env ...)"`
# to avoid spawning opam on every login shell; the values mirror
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
    # not already present, so repeated login shells don't accumulate duplicates.
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

[ -r "$HOME/.env_login.sh" ] && source "$HOME/.env_login.sh"
true
