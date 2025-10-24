#!/bin/bash

# Thanos AI Gateway Installer
# Universal AI provider abstraction layer

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║         Thanos AI Gateway Installer              ║"
    echo "║           Version 0.95.0                          ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

check_prerequisites() {
    print_step "Checking prerequisites..."

    if ! command -v zig &> /dev/null; then
        print_error "Zig compiler not found (required >= 0.16.0)"
        echo "  Install from: https://ziglang.org/download/"
        exit 1
    fi

    print_success "Zig $(zig version) found"

    if command -v ollama &> /dev/null; then
        print_success "Ollama found"
    else
        print_warning "Ollama not found (optional)"
        echo "  Install from: https://ollama.com"
    fi
}

build_thanos() {
    print_step "Building Thanos..."

    # Build CLI
    if ! zig build -Doptimize=ReleaseFast; then
        print_error "Build failed!"
        exit 1
    fi

    # Build library
    if ! zig build plugin -Doptimize=ReleaseFast; then
        print_error "Library build failed!"
        exit 1
    fi

    print_success "Build complete"
}

install_thanos() {
    print_step "Installing Thanos..."

    # Install CLI
    sudo install -Dm755 "zig-out/bin/thanos" "/usr/local/bin/thanos"
    print_success "CLI installed to /usr/local/bin/thanos"

    # Install library
    sudo install -Dm755 "zig-out/lib/libthanos.so" "/usr/local/lib/libthanos.so"
    sudo ldconfig
    print_success "Library installed to /usr/local/lib/libthanos.so"

    # Install headers
    sudo mkdir -p /usr/local/include/thanos
    sudo cp src/types.zig /usr/local/include/thanos/
    sudo cp src/root.zig /usr/local/include/thanos/
    print_success "Headers installed"

    # Install config
    mkdir -p ~/.config/thanos
    if [ ! -f ~/.config/thanos/config.zon ]; then
        cp config/default.zon ~/.config/thanos/config.zon
        print_success "Config created at ~/.config/thanos/config.zon"
    fi
}

print_next_steps() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════╗"
    echo -e "║      Thanos Installed Successfully!              ║"
    echo -e "╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Check available providers:"
    echo "   thanos discover"
    echo ""
    echo "2. Test completion:"
    echo "   thanos complete 'Write a Zig function'"
    echo ""
    echo "3. Set up API keys (optional):"
    echo "   export ANTHROPIC_API_KEY='sk-ant-...'"
    echo "   export OPENAI_API_KEY='sk-...'"
    echo ""
    echo "4. Install Ollama models:"
    echo "   ollama pull codellama"
    echo ""
}

main() {
    print_header
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
    cd "$SCRIPT_DIR"

    check_prerequisites
    build_thanos
    install_thanos
    print_next_steps

    echo -e "${GREEN}Installation complete!${NC} 🚀"
}

main "$@"
