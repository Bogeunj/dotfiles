#!/usr/bin/env bash

set -euo pipefail

trap 'echo "[ERROR] install failed at line ${LINENO}" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR"
NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh"

log() {
    printf '[dotfiles] %s\n' "$1"
}

backup_if_needed() {
    local target="$1"
    local source="$2"

    if [[ -L "$target" ]] && [[ "$(readlink -f "$target")" == "$(readlink -f "$source")" ]]; then
        return 0
    fi

    if [[ -e "$target" ]] || [[ -L "$target" ]]; then
        local backup_path="${target}.backup.$(date +%Y%m%d%H%M%S)"
        mv "$target" "$backup_path"
        log "Backed up $target -> $backup_path"
    fi
}

link_file() {
    local source="$1"
    local target="$2"

    mkdir -p "$(dirname "$target")"
    backup_if_needed "$target" "$source"
    ln -sfn "$source" "$target"
}

activate_brew_env() {
    if command -v brew >/dev/null 2>&1; then
        eval "$("$(command -v brew)" shellenv)"
        return
    fi

    for candidate in /home/linuxbrew/.linuxbrew/bin/brew /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$candidate" ]]; then
            eval "$("$candidate" shellenv)"
            return
        fi
    done
}

ensure_brew() {
    activate_brew_env
    if command -v brew >/dev/null 2>&1; then
        return
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "[ERROR] curl is required to install Homebrew." >&2
        exit 1
    fi

    log "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    activate_brew_env

    if ! command -v brew >/dev/null 2>&1; then
        echo "[ERROR] Homebrew installation failed." >&2
        exit 1
    fi
}

ensure_nvm_and_node() {
    if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
        log "Installing nvm..."
        curl -fsSL "$NVM_INSTALL_URL" | bash
    fi

    # shellcheck source=/dev/null
    source "$HOME/.nvm/nvm.sh"

    log "Installing Node LTS via nvm..."
    nvm install --lts
    nvm alias default 'lts/*'
    nvm use --lts >/dev/null
}

ensure_opencode() {
    if ! command -v npm >/dev/null 2>&1; then
        echo "[ERROR] npm is not available after Node installation." >&2
        exit 1
    fi

    log "Installing opencode-ai with npm..."
    npm install -g opencode-ai

    local npm_global_bin
    npm_global_bin="$(npm prefix -g)/bin"
    if [[ -x "$npm_global_bin/opencode" ]]; then
        mkdir -p "$HOME/.local/bin"
        ln -sfn "$npm_global_bin/opencode" "$HOME/.local/bin/opencode"
    fi

    if ! command -v opencode >/dev/null 2>&1; then
        echo "[ERROR] opencode command is not available." >&2
        exit 1
    fi
}

ensure_gitconfig_local() {
    if [[ -f "$HOME/.gitconfig.local" ]]; then
        return
    fi

    if [[ -f "$HOME/.gitconfig" ]] && [[ ! -L "$HOME/.gitconfig" ]]; then
        cp "$HOME/.gitconfig" "$HOME/.gitconfig.local"
        log "Created ~/.gitconfig.local from existing ~/.gitconfig"
        return
    fi

    cp "$DOTFILES_DIR/.gitconfig.local.example" "$HOME/.gitconfig.local"
    log "Created ~/.gitconfig.local from template"
}

log "Starting dotfiles installation..."

ensure_brew

log "Installing core tools (git tmux lazygit fzf starship git-delta ripgrep)..."
brew install git tmux lazygit fzf starship git-delta ripgrep

ensure_nvm_and_node
ensure_opencode

log "Linking dotfiles into home directory..."
link_file "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
link_file "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"

ensure_gitconfig_local
link_file "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"

log "Linking helper scripts..."
mkdir -p "$HOME/.local/bin"
chmod +x "$DOTFILES_DIR/bin/dev"
link_file "$DOTFILES_DIR/bin/dev" "$HOME/.local/bin/dev"
chmod +x "$HOME/.local/bin/dev"

log "Verifying installs..."
git --version
tmux -V
node -v
npm -v
opencode --version

log "Done. Restart your terminal or run: source ~/.bashrc"
