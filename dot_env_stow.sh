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

# Hide $TMUX from processes nvim spawns. A tmux-aware program (Claude Code)
# would otherwise wrap its OSC 9 desktop notification in tmux DCS passthrough,
# \ePtmux;...\e\\, and nvim cannot forward that at all: the protocol doubles
# every ESC, libvterm aborts a string on any ESC that is not part of ST, so
# nvim's TermRequest never fires and the notification is lost. With $TMUX absent
# the child emits bare OSC 9, which the osc9_forward autocmd in init.lua catches
# and re-wraps for tmux at the hop where tmux really is the next consumer.
#
# $NVIM is set only in nvim's child processes, so nvim itself keeps $TMUX and
# vim-tmux-navigator -- which reads it at call time on every navigation -- is
# unaffected. Doing this here rather than around :terminal also covers terminals
# spawned programmatically by plugins, which a cmdline abbreviation never sees.
if [ -n "${NVIM:-}" ]; then
    unset TMUX
fi

# Prepend to PATH only if not already present, including in nested shells.
path_prepend() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$1:$PATH" ;;
    esac
}
# NVM defines shell functions for interactive use.
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

[ -r "$HOME/.env.sh" ] && source "$HOME/.env.sh"
true
