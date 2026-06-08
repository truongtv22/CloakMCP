#!/usr/bin/env bash
set -euo pipefail

# CloakMCP installer for Codex.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/truongtv22/CloakMCP/main/setup.sh | bash
#
# Optional environment variables:
#   CLOAKMCP_REPO=https://github.com/truongtv22/CloakMCP.git
#   CLOAKMCP_DIR="$HOME/.codex/mcp/cloakmcp"
#   CODEX_CONFIG="$HOME/.codex/config.toml"
#   CLOAKMCP_SERVER_NAME=cloakmcp
#   CLOAKMCP_RUN_TESTS=1
#   CLOAKMCP_SKIP_BINARY=1
#   CLOAKMCP_SKIP_PLAYWRIGHT_DEPS=1

REPO="${CLOAKMCP_REPO:-https://github.com/truongtv22/CloakMCP.git}"
INSTALL_DIR="${CLOAKMCP_DIR:-$HOME/.codex/mcp/cloakmcp}"
CODEX_CONFIG="${CODEX_CONFIG:-$HOME/.codex/config.toml}"
SERVER_NAME="${CLOAKMCP_SERVER_NAME:-cloakmcp}"

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

print_header() {
    printf "\n%b╔══════════════════════════════════════════╗%b\n" "$BOLD" "$NC"
    printf "%b║        CloakMCP Setup for Codex          ║%b\n" "$BOLD" "$NC"
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

print_done() {
    local wrapper="$INSTALL_DIR/bin/cloakbrowsermcp"

    printf "\n%b%s%b\n\n" "$GREEN$BOLD" "CloakMCP is ready." "$NC"
    printf "%bCodex config:%b %s\n" "$BOLD" "$NC" "$CODEX_CONFIG"
    printf "%bServer:%b %s\n" "$BOLD" "$NC" "$SERVER_NAME"
    printf "%bCommand:%b %s/.venv/bin/python -m cloakbrowsermcp.server --caps all\n" "$BOLD" "$NC" "$INSTALL_DIR"
    printf "%bWrapper:%b %s\n\n" "$BOLD" "$NC" "$wrapper"
    printf "Restart Codex, then verify:\n"
    printf "  codex mcp list\n\n"
    printf "Expected tools include:\n"
    printf "  cloak_launch(cdp_endpoint=...)\n"
    printf "  cloak_new_page(page_id=..., same_context=true)\n"
    printf "  cloak_register_existing_pages()\n\n"
}

main() {
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
    print_done
}

main "$@"
