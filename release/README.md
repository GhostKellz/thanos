# Thanos Gateway - Release & Deployment

This directory contains all deployment and packaging files for Thanos AI Gateway.

## Structure

```
release/
├── linux/              # Shared Linux files (all distros)
│   ├── thanos.service        # Systemd service (universal)
│   ├── thanos.env.example    # Environment template
│   └── install.sh            # Universal installer script
├── docker/             # Docker deployment
│   ├── Dockerfile            # Multi-stage build
│   └── docker-compose.yml    # With Ollama, Prometheus, Grafana
├── arch/               # Arch Linux / Manjaro
│   └── PKGBUILD              # AUR package
├── deb/                # Debian / Ubuntu
│   └── README.md             # Build instructions
└── fedora/             # Fedora / RHEL / CentOS
    └── thanos.spec           # RPM spec file
```

## Quick Start

### Option 1: Universal Install Script (Recommended)

Works on: Arch, Debian, Ubuntu, Fedora, RHEL, CentOS, openSUSE

```bash
sudo ./release/linux/install.sh
```

### Option 2: Docker

```bash
cd release/docker
docker-compose up -d
```

### Option 3: Package Manager

#### Arch Linux (AUR)
```bash
cd release/arch
makepkg -si
```

#### Fedora/RHEL/CentOS
```bash
rpmbuild -ba release/fedora/thanos.spec
sudo dnf install ~/rpmbuild/RPMS/x86_64/thanos-gateway-*.rpm
```

## Post-Install

After installation by any method:

1. **Configure API keys:**
   ```bash
   sudo nano /etc/thanos/thanos.env
   ```

2. **OAuth authentication (optional):**
   ```bash
   thanos auth claude
   thanos auth github
   ```

3. **Start service:**
   ```bash
   sudo systemctl start thanos
   sudo systemctl enable thanos
   ```

4. **Verify:**
   ```bash
   curl http://localhost:8080/health
   ```

## Files Installed

- **Binary**: `/usr/bin/thanos`
- **Config**: `/etc/thanos/config.toml`
- **Environment**: `/etc/thanos/thanos.env`
- **Service**: `/usr/lib/systemd/system/thanos.service`
- **Data**: `/var/lib/thanos`
- **Socket**: `/var/run/thanos/thanos.sock` (after start)

## Documentation

- [PROTOCOLS.md](../PROTOCOLS.md) - Complete architecture and protocols
- [README.md](../README.md) - Project overview
- [config.example.toml](../config.example.toml) - Configuration reference

## Support

For issues or questions, see the main [README.md](../README.md)
