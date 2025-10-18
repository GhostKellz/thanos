# Installation Guide

This guide covers installing Thanos on various platforms.

## Prerequisites

- **Zig** >= 0.16.0-dev ([download](https://ziglang.org/download/))
- **Git** >= 2.0
- **Optional**: Ollama for local AI ([install](https://ollama.ai))

## Installation Methods

### Method 1: From Source (Recommended)

```bash
# Clone the repository
git clone https://github.com/ghostkellz/thanos
cd thanos

# Build
zig build

# Test the build
./zig-out/bin/thanos version

# Install to system (optional)
zig build install --prefix ~/.local

# Add to PATH (if not already)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Method 2: Zig Package Manager

Add to your project's `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .thanos = .{
            .url = "https://github.com/ghostkellz/thanos/archive/refs/tags/v0.1.0.tar.gz",
            .hash = "12209a3f...", // zig will provide this
        },
    },
}
```

Then in your `build.zig`:

```zig
const thanos = b.dependency("thanos", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("thanos", thanos.module("thanos"));
```

### Method 3: Pre-built Binaries (Coming Soon)

Download from [GitHub Releases](https://github.com/ghostkellz/thanos/releases):

```bash
# Linux x86_64
curl -LO https://github.com/ghostkellz/thanos/releases/download/v0.1.0/thanos-linux-x86_64.tar.gz
tar xzf thanos-linux-x86_64.tar.gz
sudo mv thanos /usr/local/bin/

# macOS (ARM64)
curl -LO https://github.com/ghostkellz/thanos/releases/download/v0.1.0/thanos-macos-arm64.tar.gz
tar xzf thanos-macos-arm64.tar.gz
sudo mv thanos /usr/local/bin/
```

## Platform-Specific Instructions

### Linux

#### Arch Linux (AUR - Coming Soon)

```bash
yay -S thanos-git
```

#### Ubuntu/Debian

```bash
# Install Zig from official site
wget https://ziglang.org/download/0.16.0-dev/zig-linux-x86_64-0.16.0-dev.tar.xz
tar xf zig-linux-x86_64-0.16.0-dev.tar.xz
sudo mv zig-linux-x86_64-0.16.0-dev /opt/zig
export PATH="/opt/zig:$PATH"

# Install Thanos
git clone https://github.com/ghostkellz/thanos
cd thanos
zig build install --prefix ~/.local
```

### macOS

#### Homebrew (Coming Soon)

```bash
brew install ghostkellz/tap/thanos
```

#### Manual Installation

```bash
# Install Zig via Homebrew
brew install zig

# Install Thanos
git clone https://github.com/ghostkellz/thanos
cd thanos
zig build install --prefix ~/.local
```

### Windows

```powershell
# Install Zig from https://ziglang.org/download/

# Clone and build
git clone https://github.com/ghostkellz/thanos
cd thanos
zig build

# Add to PATH
setx PATH "%PATH%;C:\path\to\thanos\zig-out\bin"
```

## Verify Installation

```bash
# Check version
thanos version

# Discover providers
thanos discover

# Test with a simple prompt
thanos complete "hello world"
```

## Optional: Install AI Providers

### Ollama (Local AI)

```bash
# Linux
curl -fsSL https://ollama.ai/install.sh | sh

# macOS
brew install ollama

# Start Ollama
ollama serve

# Pull a model
ollama pull codellama
```

### Omen (Smart Routing - Coming Soon)

```bash
# Via Docker
docker run -d -p 3000:3000 ghcr.io/ghostkellz/omen:latest

# Or build from source
git clone https://github.com/ghostkellz/omen
cd omen
cargo build --release
./target/release/omen
```

## Configuration

Create a configuration file at `~/.config/thanos/config.toml`:

```toml
[general]
debug = false
preferred_provider = "ollama"  # Start with local

[providers.ollama]
enabled = true
model = "codellama:latest"

# Add API keys later
[providers.anthropic]
enabled = false
api_key = "${ANTHROPIC_API_KEY}"
```

See [Configuration Guide](configuration.md) for all options.

## Troubleshooting

### "zig: command not found"

Make sure Zig is in your PATH:

```bash
export PATH="/path/to/zig:$PATH"
```

### "Provider not available"

Check that the provider is running:

```bash
# For Ollama
curl http://localhost:11434/api/version

# For Omen
curl http://localhost:3000/health
```

### Build errors

Make sure you have Zig 0.16+:

```bash
zig version  # Should show 0.16.0 or higher
```

## Next Steps

- [Quick Start Guide](quickstart.md) - Get started in 5 minutes
- [Configuration Reference](configuration.md) - Customize Thanos
- [Provider Setup](providers.md) - Configure AI providers
