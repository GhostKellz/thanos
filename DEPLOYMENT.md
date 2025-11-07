# Thanos Deployment Guide

## Quick Start with Docker Compose

### Prerequisites
- Docker 20.10+
- Docker Compose 2.0+
- 2GB RAM minimum
- API keys for providers (optional)

### 1. Setup Environment

Create a `.env` file in the project root:

```bash
# API Keys (optional - configure what you need)
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=...
XAI_API_KEY=...
```

### 2. Configure Thanos

Copy the example config:

```bash
cp thanos.toml.example thanos.toml
```

Edit `thanos.toml` to enable your providers:

```toml
[server]
bind = "0.0.0.0:8080"
grpc = "0.0.0.0:50051"

[providers.anthropic]
enabled = true
api_key = "${ANTHROPIC_API_KEY}"
model = "claude-sonnet-4-5"

[providers.ollama]
enabled = true
endpoint = "http://ollama:11434"
model = "llama3.2"
```

### 3. Start Services

**Full stack** (Thanos + Ollama + Prometheus + Grafana):
```bash
docker-compose up -d
```

**Thanos only**:
```bash
docker-compose up -d thanos
```

**With Ollama**:
```bash
docker-compose up -d thanos ollama
```

### 4. Verify Deployment

```bash
# Check health
curl http://localhost:8080/health

# List models
curl http://localhost:8080/v1/models

# Test chat completion
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}],
    "stream": false
  }'
```

### 5. Access Services

- **Thanos HTTP API:** http://localhost:8080
- **Thanos gRPC:** localhost:50051
- **Metrics:** http://localhost:9090/metrics
- **Prometheus:** http://localhost:9091
- **Grafana:** http://localhost:3000 (admin/admin)

### 6. View Logs

```bash
# All services
docker-compose logs -f

# Thanos only
docker-compose logs -f thanos

# Last 100 lines
docker-compose logs --tail=100 thanos
```

### 7. Stop Services

```bash
# Stop all
docker-compose down

# Stop and remove volumes
docker-compose down -v
```

---

## Production Deployment

### Docker Standalone

Build the image:
```bash
docker build -t thanos:latest .
```

Run with custom config:
```bash
docker run -d \
  --name thanos \
  -p 8080:8080 \
  -p 50051:50051 \
  -p 9090:9090 \
  -v $(pwd)/thanos.toml:/etc/thanos/thanos.toml:ro \
  -e ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY} \
  -e OPENAI_API_KEY=${OPENAI_API_KEY} \
  thanos:latest
```

### Kubernetes

See `k8s/` directory for Kubernetes manifests (coming soon).

Basic deployment:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos
spec:
  replicas: 3
  selector:
    matchLabels:
      app: thanos
  template:
    metadata:
      labels:
        app: thanos
    spec:
      containers:
      - name: thanos
        image: thanos:latest
        ports:
        - containerPort: 8080
        - containerPort: 50051
        env:
        - name: ANTHROPIC_API_KEY
          valueFrom:
            secretKeyRef:
              name: thanos-secrets
              key: anthropic-api-key
```

### Systemd Service

For bare metal deployment:

```bash
# Copy binary
sudo cp target/release/thanos /usr/local/bin/

# Create service file
sudo tee /etc/systemd/system/thanos.service <<EOF
[Unit]
Description=Thanos AI Gateway
After=network.target

[Service]
Type=simple
User=thanos
Group=thanos
WorkingDirectory=/opt/thanos
ExecStart=/usr/local/bin/thanos
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable thanos
sudo systemctl start thanos
```

---

## Configuration Options

### Environment Variables

- `THANOS_CONFIG` - Path to config file (default: `./thanos.toml`)
- `RUST_LOG` - Log level (trace, debug, info, warn, error)
- `ANTHROPIC_API_KEY` - Anthropic API key
- `OPENAI_API_KEY` - OpenAI API key
- `GEMINI_API_KEY` - Google Gemini API key
- `XAI_API_KEY` - xAI API key

### Volumes

- `/etc/thanos/thanos.toml` - Configuration file
- `/var/run/thanos` - Runtime data (UDS socket)
- `/var/log/thanos` - Logs (if file logging enabled)

### Ports

- `8080` - HTTP API
- `50051` - gRPC API
- `9090` - Prometheus metrics

---

## Monitoring & Observability

### Prometheus Metrics

Available at `http://localhost:9090/metrics`:

- `thanos_requests_total` - Total requests by provider
- `thanos_request_duration_seconds` - Request latency histogram
- `thanos_errors_total` - Errors by provider
- `thanos_cache_hits_total` - Cache hit rate
- `thanos_circuit_breaker_state` - Circuit breaker status

### Grafana Dashboards

1. Open Grafana: http://localhost:3000
2. Login: admin/admin
3. Add Prometheus data source: http://prometheus:9090
4. Import dashboard from `grafana/thanos-dashboard.json` (coming soon)

### Structured Logging

JSON logging for production:

```toml
[logging]
format = "json"
level = "info"
output = "/var/log/thanos/app.log"
```

---

## Troubleshooting

### Container won't start

```bash
# Check logs
docker-compose logs thanos

# Common issues:
# 1. Port already in use
sudo lsof -i :8080

# 2. Config file syntax error
docker-compose exec thanos cat /etc/thanos/thanos.toml

# 3. Missing API keys
docker-compose exec thanos env | grep API_KEY
```

### Health check failing

```bash
# Test manually
curl -v http://localhost:8080/health

# Check if providers are reachable
docker-compose exec thanos curl https://api.anthropic.com
```

### Performance issues

```bash
# Check resource usage
docker stats thanos-gateway

# Increase memory limit in docker-compose.yml:
deploy:
  resources:
    limits:
      memory: 2G
```

### OAuth not working

OAuth requires persistent keyring storage. Mount a volume:

```yaml
volumes:
  - ~/.local/share/keyrings:/home/thanos/.local/share/keyrings
```

---

## Security Considerations

### API Key Storage

**Never commit API keys to git!**

Use:
1. Environment variables (`.env` file, not committed)
2. Docker secrets (Swarm mode)
3. Kubernetes secrets
4. External secret managers (Vault, AWS Secrets Manager)

### Network Security

- Run behind reverse proxy (nginx, Traefik)
- Enable TLS/HTTPS in production
- Use firewall rules to restrict access
- Consider VPN for internal-only deployment

### Authentication

Add authentication layer:
- API keys for HTTP endpoints
- mTLS for gRPC
- Rate limiting per client

(See SECURITY.md for detailed guide - coming soon)

---

## Performance Tuning

### Connection Pooling

```toml
[http]
pool_size = 100
keep_alive = 30
timeout = 60
```

### Caching

```toml
[cache]
enabled = true
ttl = 300  # 5 minutes
max_size = 10000
```

### Concurrency

```bash
# Set TOKIO_WORKER_THREADS
docker run -e TOKIO_WORKER_THREADS=8 thanos:latest
```

---

## Backup & Recovery

### Configuration Backup

```bash
# Backup config
docker cp thanos-gateway:/etc/thanos/thanos.toml ./backup/

# Restore
docker cp ./backup/thanos.toml thanos-gateway:/etc/thanos/
docker-compose restart thanos
```

### OAuth Tokens

Tokens stored in system keyring - not in container by default.
For persistence, mount keyring volume (see OAuth section above).

---

## Scaling

### Horizontal Scaling

Run multiple Thanos instances behind load balancer:

```yaml
# docker-compose.yml
services:
  thanos:
    deploy:
      replicas: 3

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
```

### Load Balancing

Example nginx config:
```nginx
upstream thanos {
    least_conn;
    server thanos:8080 max_fails=3 fail_timeout=30s;
}

server {
    listen 80;
    location / {
        proxy_pass http://thanos;
    }
}
```

---

## Updates & Maintenance

### Updating Thanos

```bash
# Pull latest code
git pull

# Rebuild image
docker-compose build thanos

# Rolling update
docker-compose up -d --no-deps --build thanos
```

### Database Migrations

Not applicable - Thanos is stateless (except OAuth tokens in keyring).

### Rollback

```bash
# Revert to previous image
docker-compose down
docker-compose up -d thanos:v0.1.0
```

---

## Support

- GitHub Issues: https://github.com/yourusername/thanos/issues
- Documentation: https://docs.thanos.dev
- Discord: https://discord.gg/thanos (coming soon)
