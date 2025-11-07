# Multi-stage build for Thanos AI Gateway
# Stage 1: Builder
FROM rust:1.75-bookworm as builder

WORKDIR /build

# Install protobuf compiler for gRPC
RUN apt-get update && apt-get install -y \
    protobuf-compiler \
    libprotobuf-dev \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency manifests
COPY Cargo.toml Cargo.lock ./
COPY proto ./proto

# Create dummy main to cache dependencies
RUN mkdir src && \
    echo "fn main() {}" > src/main.rs && \
    echo "pub fn dummy() {}" > src/lib.rs

# Build dependencies (this layer is cached)
RUN cargo build --release && \
    rm -rf src

# Copy actual source code
COPY src ./src
COPY build.rs ./

# Build the actual binary
RUN cargo build --release && \
    strip target/release/thanos

# Stage 2: Runtime
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN useradd -m -u 1000 -s /bin/bash thanos

# Create necessary directories
RUN mkdir -p /var/run/thanos /var/log/thanos /etc/thanos && \
    chown -R thanos:thanos /var/run/thanos /var/log/thanos /etc/thanos

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/target/release/thanos /usr/local/bin/thanos

# Copy default config (optional)
COPY thanos.toml.example /etc/thanos/thanos.toml.example

# Switch to non-root user
USER thanos

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Expose ports
EXPOSE 8080 50051 9090

# Set environment variables
ENV RUST_LOG=info
ENV THANOS_CONFIG=/etc/thanos/thanos.toml

# Run the binary
ENTRYPOINT ["/usr/local/bin/thanos"]
CMD []
