#!/bin/bash
# Thanos Gateway Universal Installation Script
# Supports: Arch Linux, Debian, Ubuntu, Fedora, RHEL, CentOS

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${BLUE}➜${NC} $1"; }
print_warn() { echo -e "${YELLOW}⚠${NC} $1"; }

# Banner
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Thanos AI Gateway - Universal Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
else
    print_error "Cannot detect OS"
    exit 1
fi

print_info "Detected: $PRETTY_NAME"
echo ""

# Install dependencies based on OS
case $OS in
    arch|manjaro)
        print_info "Installing dependencies (Arch Linux)..."
        pacman -S --needed --noconfirm rust cargo protobuf openssl
        ;;
    debian|ubuntu|linuxmint)
        print_info "Installing dependencies (Debian/Ubuntu)..."
        apt-get update -qq
        apt-get install -y build-essential cargo protobuf-compiler libssl-dev pkg-config
        ;;
    fedora)
        print_info "Installing dependencies (Fedora)..."
        dnf install -y rust cargo protobuf-compiler openssl-devel pkg-config
        ;;
    rhel|centos|rocky|almalinux)
        print_info "Installing dependencies (RHEL/CentOS)..."
        dnf install -y rust cargo protobuf-compiler openssl-devel pkg-config
        ;;
    opensuse*|sles)
        print_info "Installing dependencies (openSUSE)..."
        zypper install -y rust cargo protobuf-devel libopenssl-devel pkg-config
        ;;
    *)
        print_error "Unsupported OS: $OS"
        print_info "Supported: Arch, Debian, Ubuntu, Fedora, RHEL, CentOS, openSUSE"
        exit 1
        ;;
esac

print_success "Dependencies installed"
echo ""

# Verify we're in the right directory
if [ ! -f "Cargo.toml" ]; then
    print_error "Cargo.toml not found"
    print_info "Please run this script from the thanos project root directory"
    exit 1
fi

# Build
print_info "Building Thanos (this may take a few minutes)..."
cargo build --release --quiet
print_success "Build complete"
echo ""

# Install binary
print_info "Installing binary to /usr/bin/thanos..."
install -Dm755 "target/release/thanos" "/usr/bin/thanos"
print_success "Binary installed"

# Install config
print_info "Installing configuration..."
mkdir -p /etc/thanos
if [ ! -f "/etc/thanos/config.toml" ]; then
    install -Dm644 "config.example.toml" "/etc/thanos/config.toml"
    print_success "Config installed to /etc/thanos/config.toml"
else
    print_warn "Config already exists at /etc/thanos/config.toml (preserving)"
fi

# Install env example
if [ ! -f "/etc/thanos/thanos.env" ]; then
    install -Dm644 "release/linux/thanos.env.example" "/etc/thanos/thanos.env"
    print_success "Environment template installed to /etc/thanos/thanos.env"
else
    print_warn "Environment file already exists (preserving)"
fi

# Create directories
print_info "Creating directories..."
mkdir -p /var/lib/thanos /var/run/thanos
print_success "Directories created"

# Create user
print_info "Creating thanos user..."
if ! id -u thanos >/dev/null 2>&1; then
    case $OS in
        arch|manjaro)
            useradd -r -s /bin/false -d /var/lib/thanos thanos
            ;;
        *)
            useradd -r -s /usr/sbin/nologin -d /var/lib/thanos thanos
            ;;
    esac
    print_success "User 'thanos' created"
else
    print_info "User 'thanos' already exists"
fi

# Set permissions
print_info "Setting permissions..."
chown -R thanos:thanos /var/lib/thanos /var/run/thanos
chmod 750 /var/lib/thanos /var/run/thanos
chmod 640 /etc/thanos/config.toml /etc/thanos/thanos.env
chown root:thanos /etc/thanos/config.toml /etc/thanos/thanos.env
print_success "Permissions set"

# Install systemd service
print_info "Installing systemd service..."
install -Dm644 "release/linux/thanos.service" "/usr/lib/systemd/system/thanos.service"
systemctl daemon-reload
print_success "Systemd service installed"
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_success "Thanos AI Gateway installed successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📁 Installation locations:"
echo "   Binary:  /usr/bin/thanos"
echo "   Config:  /etc/thanos/config.toml"
echo "   Env:     /etc/thanos/thanos.env"
echo "   Service: /usr/lib/systemd/system/thanos.service"
echo "   Data:    /var/lib/thanos"
echo "   Socket:  /var/run/thanos/thanos.sock (after start)"
echo ""
echo "🔧 Next steps:"
echo ""
echo "1️⃣  Configure API keys:"
echo "   sudo nano /etc/thanos/thanos.env"
echo "   (Uncomment and add your API keys)"
echo ""
echo "2️⃣  OAuth authentication (optional):"
echo "   thanos auth claude     # Claude Max (\$100/month)"
echo "   thanos auth github     # GitHub Copilot"
echo ""
echo "3️⃣  Start the service:"
echo "   sudo systemctl start thanos"
echo "   sudo systemctl enable thanos  # Auto-start on boot"
echo ""
echo "4️⃣  Verify it's running:"
echo "   sudo systemctl status thanos"
echo "   curl http://localhost:8080/health"
echo ""
echo "5️⃣  View logs:"
echo "   sudo journalctl -u thanos -f"
echo ""
echo "6️⃣  Test via UDS socket:"
echo "   curl --unix-socket /var/run/thanos/thanos.sock http://localhost/health"
echo ""
echo "📚 Documentation:"
echo "   README.md"
echo "   PROTOCOLS.md"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
