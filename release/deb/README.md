# Debian Package Build

To build a `.deb` package for Debian/Ubuntu:

```bash
# Install build tools
sudo apt-get install debhelper cargo rustc protobuf-compiler libssl-dev pkg-config

# Build the package
dpkg-buildpackage -b -uc -us

# Install
sudo dpkg -i ../thanos-gateway_1.0.0_amd64.deb
```

Note: Full `debian/` directory with control, rules, changelog, etc. should be created for proper package building.
