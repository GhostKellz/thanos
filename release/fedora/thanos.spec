Name:           thanos-gateway
Version:        1.0.0
Release:        1%{?dist}
Summary:        Universal AI Gateway - Multi-provider LLM gateway

License:        MIT
URL:            https://github.com/yourusername/thanos
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  rust cargo protobuf-compiler openssl-devel pkg-config
Requires:       openssl

%description
Thanos is a production-ready AI gateway that provides unified access
to multiple LLM providers through a hybrid transport architecture.

Features:
- Multiple transports: UDS, HTTP/2, gRPC, HTTP/3 (QUIC)
- OAuth support: Claude Max, GitHub Copilot
- Auto-refresh tokens
- High performance with connection pooling
- Rate limiting and circuit breakers

%prep
%autosetup

%build
cargo build --release

%install
# Binary
install -Dm755 target/release/thanos %{buildroot}%{_bindir}/thanos

# Config
install -dm755 %{buildroot}%{_sysconfdir}/thanos
install -Dm644 config.example.toml %{buildroot}%{_sysconfdir}/thanos/config.toml
install -Dm644 release/linux/thanos.env.example %{buildroot}%{_sysconfdir}/thanos/thanos.env

# Systemd service (shared across all distros)
install -Dm644 release/linux/thanos.service %{buildroot}%{_unitdir}/thanos.service

# Directories
install -dm755 %{buildroot}%{_sharedstatedir}/thanos
install -dm755 %{buildroot}/run/thanos

# Documentation
install -Dm644 README.md %{buildroot}%{_docdir}/%{name}/README.md
install -Dm644 PROTOCOLS.md %{buildroot}%{_docdir}/%{name}/PROTOCOLS.md
install -Dm644 LICENSE %{buildroot}%{_licensedir}/%{name}/LICENSE

%pre
getent group thanos >/dev/null || groupadd -r thanos
getent passwd thanos >/dev/null || \
    useradd -r -g thanos -d %{_sharedstatedir}/thanos -s /sbin/nologin thanos
exit 0

%post
%systemd_post thanos.service
chown -R thanos:thanos %{_sharedstatedir}/thanos /run/thanos
chmod 750 %{_sharedstatedir}/thanos /run/thanos
chmod 640 %{_sysconfdir}/thanos/config.toml %{_sysconfdir}/thanos/thanos.env
chown root:thanos %{_sysconfdir}/thanos/config.toml %{_sysconfdir}/thanos/thanos.env

%preun
%systemd_preun thanos.service

%postun
%systemd_postun_with_restart thanos.service

%files
%license LICENSE
%doc README.md PROTOCOLS.md
%{_bindir}/thanos
%config(noreplace) %{_sysconfdir}/thanos/config.toml
%config(noreplace) %{_sysconfdir}/thanos/thanos.env
%{_unitdir}/thanos.service
%dir %attr(0750,thanos,thanos) %{_sharedstatedir}/thanos
%dir %attr(0750,thanos,thanos) /run/thanos

%changelog
* Wed Nov 06 2024 Your Name <your.email@example.com> - 1.0.0-1
- Initial RPM release
- Added support for Anthropic, OpenAI, Gemini, xAI, Ollama
- OAuth support for Claude Max and GitHub Copilot
- UDS socket, HTTP/2, gRPC support
