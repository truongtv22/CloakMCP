#!/usr/bin/env bash
set -euo pipefail

# CloakMCP installer for Codex and Claude Code.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/truongtv22/CloakMCP/main/setup.sh | bash
#
# Optional environment variables:
#   CLOAKMCP_REPO=https://github.com/truongtv22/CloakMCP.git
#   CLOAKMCP_DIR="$HOME/.cloakbrowsermcp"
#   CODEX_CONFIG="$HOME/.codex/config.toml"
#   CLOAKMCP_SERVER_NAME=cloakmcp
#   CLOAKMCP_SKIP_CODEX=1
#   CLOAKMCP_SKIP_CLAUDE=1
#   CLOAKMCP_CLAUDE_SCOPE=user
#   CLOAKMCP_RUN_TESTS=1
#   CLOAKMCP_SKIP_BINARY=1
#   CLOAKMCP_SKIP_PLAYWRIGHT_DEPS=1
#
# Commands:
#   ./setup.sh --list-targets
#   ./setup.sh --target codex
#   ./setup.sh --target claude-code
#   ./setup.sh --uninstall
#   ./setup.sh --uninstall --target codex
#   ./setup.sh --uninstall --target claude-code

REPO="${CLOAKMCP_REPO:-https://github.com/truongtv22/CloakMCP.git}"
INSTALL_DIR="${CLOAKMCP_DIR:-$HOME/.cloakbrowsermcp}"
CODEX_CONFIG="${CODEX_CONFIG:-$HOME/.codex/config.toml}"
SERVER_NAME="${CLOAKMCP_SERVER_NAME:-cloakmcp}"
CLAUDE_SCOPE="${CLOAKMCP_CLAUDE_SCOPE:-user}"
ACTION="install"
TARGET_WAS_SPECIFIED=0
TARGETS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { printf "%b[INFO]%b %s\n" "$CYAN" "$NC" "$*"; }
ok() { printf "%b[OK]%b   %s\n" "$GREEN" "$NC" "$*"; }
warn() { printf "%b[WARN]%b %s\n" "$YELLOW" "$NC" "$*"; }
fail() { printf "%b[FAIL]%b %s\n" "$RED" "$NC" "$*" >&2; exit 1; }

print_usage() {
    cat <<EOF
CloakMCP setup for Codex and Claude Code.

Usage:
  ./setup.sh [--target codex|claude-code]...
  ./setup.sh --list-targets
  ./setup.sh --uninstall [--target codex|claude-code]...

Targets:
  codex
  claude-code

Examples:
  ./setup.sh
  ./setup.sh --target codex
  ./setup.sh --target claude-code
  ./setup.sh --uninstall
  ./setup.sh --uninstall --target codex
  ./setup.sh --uninstall --target claude-code
EOF
}

list_targets() {
    printf "codex\n"
    printf "claude-code\n"
}

add_target() {
    local target="$1"
    case "$target" in
        codex|claude-code) ;;
        *) fail "Unknown target '$target'. Run --list-targets." ;;
    esac

    local existing
    for existing in ${TARGETS[@]+"${TARGETS[@]}"}; do
        [ "$existing" = "$target" ] && return
    done
    TARGETS+=("$target")
    TARGET_WAS_SPECIFIED=1
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --list-targets)
                list_targets
                exit 0
                ;;
            --target)
                [ "$#" -ge 2 ] || fail "--target requires one value. Run --list-targets."
                shift
                add_target "$1"
                ;;
            --uninstall)
                ACTION="uninstall"
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                fail "Unknown argument '$1'. Run --help."
                ;;
        esac
        shift
    done

    if [ "${#TARGETS[@]}" -eq 0 ]; then
        TARGETS=(codex claude-code)
    fi
}

has_target() {
    local target="$1"
    local selected
    for selected in ${TARGETS[@]+"${TARGETS[@]}"}; do
        [ "$selected" = "$target" ] && return 0
    done
    return 1
}

targets_display() {
    local joined=""
    local selected
    for selected in ${TARGETS[@]+"${TARGETS[@]}"}; do
        if [ -z "$joined" ]; then
            joined="$selected"
        else
            joined="$joined,$selected"
        fi
    done
    printf "%s" "$joined"
}

print_header() {
    printf "\n%b╔══════════════════════════════════════════╗%b\n" "$BOLD" "$NC"
    printf "%b║   CloakMCP Setup for Codex/Claude Code   ║%b\n" "$BOLD" "$NC"
    printf "%b║  Stealth browser automation MCP          ║%b\n" "$BOLD" "$NC"
    printf "%b╚══════════════════════════════════════════╝%b\n\n" "$BOLD" "$NC"
}

find_python() {
    local cmd ver major minor
    for cmd in python3.13 python3.12 python3.11 python3.10 python3 python; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            continue
        fi

        ver=$("$cmd" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || true)
        major=$("$cmd" -c "import sys; print(sys.version_info.major)" 2>/dev/null || echo 0)
        minor=$("$cmd" -c "import sys; print(sys.version_info.minor)" 2>/dev/null || echo 0)
        if [ "$major" -eq 3 ] && [ "$minor" -ge 10 ]; then
            printf "%s" "$cmd"
            return 0
        fi
        warn "$cmd is $ver; need Python 3.10+"
    done
    return 1
}

clone_or_update_repo() {
    mkdir -p "$(dirname "$INSTALL_DIR")"

    if [ -d "$INSTALL_DIR/.git" ]; then
        info "Updating existing install at $INSTALL_DIR"
        git -C "$INSTALL_DIR" remote set-url origin "$REPO"
        git -C "$INSTALL_DIR" fetch --quiet origin main
        git -C "$INSTALL_DIR" checkout --quiet main
        git -C "$INSTALL_DIR" pull --ff-only --quiet origin main
        ok "Repository updated"
        return
    fi

    if [ -e "$INSTALL_DIR" ]; then
        fail "$INSTALL_DIR exists but is not a git repository. Move it away or set CLOAKMCP_DIR."
    fi

    info "Cloning $REPO to $INSTALL_DIR"
    git clone --quiet "$REPO" "$INSTALL_DIR"
    ok "Repository cloned"
}

install_python_package() {
    local python="$1"
    local venv_dir="$INSTALL_DIR/.venv"

    if [ ! -d "$venv_dir" ]; then
        info "Creating virtual environment"
        "$python" -m venv "$venv_dir"
        ok "venv created at $venv_dir"
    else
        ok "venv already exists"
    fi

    local venv_python="$venv_dir/bin/python"
    [ -x "$venv_python" ] || fail "venv python not found at $venv_python"

    info "Installing cloakbrowsermcp"
    "$venv_python" -m pip install --upgrade pip --quiet
    "$venv_python" -m pip install -e ".[dev]" --quiet
    ok "Python package installed"
}

prepare_browser_runtime() {
    local venv_python="$INSTALL_DIR/.venv/bin/python"

    if [ "${CLOAKMCP_SKIP_BINARY:-0}" = "1" ]; then
        warn "Skipping CloakBrowser binary download because CLOAKMCP_SKIP_BINARY=1"
    else
        info "Preparing CloakBrowser stealth binary"
        if "$venv_python" -c "from cloakbrowser.download import ensure_binary; ensure_binary()"; then
            ok "CloakBrowser binary ready"
        else
            warn "Binary download failed; cloakbrowser may auto-download on first launch"
        fi
    fi

    if [ "${CLOAKMCP_SKIP_PLAYWRIGHT_DEPS:-0}" = "1" ]; then
        warn "Skipping Playwright system deps because CLOAKMCP_SKIP_PLAYWRIGHT_DEPS=1"
        return
    fi

    info "Installing Playwright Chromium dependencies when supported"
    "$venv_python" -m playwright install-deps chromium 2>/dev/null \
        || warn "Could not install system deps automatically. If needed, run: $venv_python -m playwright install-deps chromium"
}

run_smoke_tests() {
    local venv_python="$INSTALL_DIR/.venv/bin/python"

    if [ "${CLOAKMCP_RUN_TESTS:-0}" != "1" ]; then
        info "Skipping tests by default. Set CLOAKMCP_RUN_TESTS=1 to run smoke tests."
        return
    fi

    info "Running smoke tests"
    "$venv_python" -m pytest tests/test_session.py -q
    "$venv_python" -m ruff check cloakbrowsermcp tests/test_session.py
    ok "Smoke tests passed"
}

write_wrapper() {
    local wrapper="$INSTALL_DIR/bin/cloakbrowsermcp"
    mkdir -p "$INSTALL_DIR/bin"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
exec "$INSTALL_DIR/.venv/bin/python" -m cloakbrowsermcp.server "\$@"
EOF
    chmod +x "$wrapper"
    ok "Wrapper written to $wrapper"
}

escape_sed_replacement() {
    printf "%s" "$1" | sed 's/[\/&]/\\&/g'
}

write_codex_config() {
    if ! has_target codex; then
        return
    fi

    if [ "${CLOAKMCP_SKIP_CODEX:-0}" = "1" ]; then
        warn "Skipping Codex config because CLOAKMCP_SKIP_CODEX=1"
        return
    fi

    local venv_python="$INSTALL_DIR/.venv/bin/python"
    local config_dir
    config_dir="$(dirname "$CODEX_CONFIG")"
    mkdir -p "$config_dir"
    touch "$CODEX_CONFIG"

    local tmp_file escaped_server
    tmp_file="$(mktemp)"
    escaped_server="$(escape_sed_replacement "$SERVER_NAME")"

    awk -v server="$SERVER_NAME" '
        $0 == "[mcp_servers." server "]" { skip = 1; next }
        skip && /^\[/ { skip = 0 }
        !skip { print }
    ' "$CODEX_CONFIG" > "$tmp_file"

    {
        cat "$tmp_file"
        printf "\n[mcp_servers.%s]\n" "$SERVER_NAME"
        printf "command = \"%s\"\n" "$venv_python"
        printf "args = [\"-m\", \"cloakbrowsermcp.server\", \"--caps\", \"all\"]\n"
    } > "$CODEX_CONFIG"
    rm -f "$tmp_file"

    ok "Codex MCP config updated at $CODEX_CONFIG"
    info "Server name: $escaped_server"
}

write_claude_code_config() {
    if ! has_target claude-code; then
        return
    fi

    if [ "${CLOAKMCP_SKIP_CLAUDE:-0}" = "1" ]; then
        warn "Skipping Claude Code config because CLOAKMCP_SKIP_CLAUDE=1"
        return
    fi

    if ! command -v claude >/dev/null 2>&1; then
        warn "Claude Code CLI not found. Configure later with:"
        warn "claude mcp add -s $CLAUDE_SCOPE $SERVER_NAME -- $INSTALL_DIR/.venv/bin/python -m cloakbrowsermcp.server --caps all"
        return
    fi

    local venv_python="$INSTALL_DIR/.venv/bin/python"
    info "Configuring Claude Code MCP server with scope '$CLAUDE_SCOPE'"
    claude mcp remove -s "$CLAUDE_SCOPE" "$SERVER_NAME" >/dev/null 2>&1 || true
    claude mcp add -s "$CLAUDE_SCOPE" "$SERVER_NAME" -- \
        "$venv_python" -m cloakbrowsermcp.server --caps all
    ok "Claude Code MCP config updated"
}

remove_codex_config() {
    if ! has_target codex; then
        return
    fi

    if [ ! -f "$CODEX_CONFIG" ]; then
        ok "Codex config not found; nothing to remove"
        return
    fi

    local tmp_file
    tmp_file="$(mktemp)"
    awk -v server="$SERVER_NAME" '
        $0 == "[mcp_servers." server "]" { skip = 1; next }
        skip && /^\[/ { skip = 0 }
        !skip { print }
    ' "$CODEX_CONFIG" > "$tmp_file"
    mv "$tmp_file" "$CODEX_CONFIG"
    ok "Removed Codex MCP config for $SERVER_NAME"
}

remove_claude_code_config() {
    if ! has_target claude-code; then
        return
    fi

    if ! command -v claude >/dev/null 2>&1; then
        warn "Claude Code CLI not found; cannot remove Claude Code MCP config automatically"
        return
    fi

    info "Removing Claude Code MCP server '$SERVER_NAME'"
    if claude mcp remove -s "$CLAUDE_SCOPE" "$SERVER_NAME" >/dev/null 2>&1; then
        ok "Removed Claude Code MCP config for $SERVER_NAME"
    else
        warn "Claude Code MCP config for $SERVER_NAME was not found at scope '$CLAUDE_SCOPE'"
    fi
}

remove_install_dir_if_full_uninstall() {
    if [ "$TARGET_WAS_SPECIFIED" -eq 1 ]; then
        info "Keeping shared install dir because uninstall target was specified: $INSTALL_DIR"
        return
    fi

    if [ ! -e "$INSTALL_DIR" ]; then
        ok "Install dir not found; nothing to remove"
        return
    fi

    case "$INSTALL_DIR" in
        ""|"/"|"$HOME") fail "Refusing to remove unsafe install dir: $INSTALL_DIR" ;;
    esac

    rm -rf "$INSTALL_DIR"
    ok "Removed shared install dir: $INSTALL_DIR"
}

run_uninstall() {
    print_header
    info "Uninstalling targets: $(targets_display)"
    remove_codex_config
    remove_claude_code_config
    remove_install_dir_if_full_uninstall
    ok "Uninstall complete"
}

print_done() {
    local wrapper="$INSTALL_DIR/bin/cloakbrowsermcp"

    printf "\n%b%s%b\n\n" "$GREEN$BOLD" "CloakMCP is ready." "$NC"
    printf "%bInstall dir:%b %s\n" "$BOLD" "$NC" "$INSTALL_DIR"
    printf "%bTargets:%b %s\n" "$BOLD" "$NC" "$(targets_display)"
    printf "%bCodex config:%b %s\n" "$BOLD" "$NC" "$CODEX_CONFIG"
    printf "%bClaude Code scope:%b %s\n" "$BOLD" "$NC" "$CLAUDE_SCOPE"
    printf "%bServer:%b %s\n" "$BOLD" "$NC" "$SERVER_NAME"
    printf "%bCommand:%b %s/.venv/bin/python -m cloakbrowsermcp.server --caps all\n" "$BOLD" "$NC" "$INSTALL_DIR"
    printf "%bWrapper:%b %s\n\n" "$BOLD" "$NC" "$wrapper"
    printf "Restart Codex/Claude Code, then verify:\n"
    printf "  codex mcp list\n\n"
    printf "  claude mcp list\n\n"
    printf "Expected tools include:\n"
    printf "  cloak_launch(cdp_endpoint=...)\n"
    printf "  cloak_new_page(page_id=..., same_context=true)\n"
    printf "  cloak_register_existing_pages()\n\n"
}

main() {
    parse_args "$@"

    if [ "$ACTION" = "uninstall" ]; then
        run_uninstall
        return
    fi

    print_header

    info "Checking prerequisites"
    command -v git >/dev/null 2>&1 || fail "git not found. Install git first."
    local python
    python="$(find_python)" || fail "Python 3.10+ is required."
    ok "Using Python: $python"

    clone_or_update_repo
    cd "$INSTALL_DIR"

    install_python_package "$python"
    prepare_browser_runtime
    run_smoke_tests
    write_wrapper
    write_codex_config
    write_claude_code_config
    print_done
}

main "$@"
