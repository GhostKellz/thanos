# Rust Client Examples for Thanos

These examples show how to call Thanos from Rust clients like **zeke**.

## Prerequisites

1. Start Thanos server:
   ```bash
   cd ../..
   cargo run --release
   ```

2. Configure providers in `~/.config/thanos/config.toml`

## Examples

### 1. gRPC Client (Recommended)
**Best for:** CLI tools, editor plugins, performance-critical apps

```bash
cargo build --example grpc_client
cargo run --example grpc_client
```

**Features:**
- Binary protocol (fast)
- Built-in streaming
- Type-safe with protobuf
- Connection pooling

**Use in zeke:**
```rust
// In your zeke CLI
use tonic::transport::Channel;

let channel = Channel::from_static("http://localhost:50051")
    .connect()
    .await?;

let mut client = ThanosServiceClient::new(channel);
```

### 2. gRPC Streaming
**Best for:** Real-time code generation, chat interfaces

```bash
cargo run --example grpc_streaming
```

**Features:**
- Token-by-token streaming
- Low latency
- Shows progress in real-time

### 3. HTTP Client (Fallback)
**Best for:** Web clients, simple integrations, debugging

```bash
cargo run --example http_client
```

**Features:**
- OpenAI-compatible API
- Easy to debug (curl-friendly)
- Works from any language

**Test with curl:**
```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "Hello!"}],
    "stream": false
  }'
```

### 4. Unix Domain Socket (Fastest)
**Best for:** Local tools, nvim plugins, maximum performance

```bash
cargo run --example uds_client
```

**Features:**
- 2-3x faster than TCP for local IPC
- No network overhead
- Secure (filesystem permissions)

**Use in zeke.nvim:**
```lua
-- In Lua/nvim, use socket directly:
local socket = vim.loop.new_pipe(false)
socket:connect('/var/run/thanos/thanos.sock', function()
    -- Send HTTP request over socket
end)
```

## Performance Comparison

| Transport | Latency | Use Case |
|-----------|---------|----------|
| **UDS** | ~0.1ms | nvim, local CLI |
| **gRPC** | ~0.5ms | zeke, remote tools |
| **HTTP** | ~1ms | Web, curl, debugging |

## Integration Guide for zeke

### 1. Add to zeke's Cargo.toml
```toml
[dependencies]
tonic = "0.11"
prost = "0.12"
tokio = { version = "1", features = ["full"] }

[build-dependencies]
tonic-build = "0.11"
```

### 2. Copy proto file
```bash
cp ../../proto/thanos.proto <zeke-repo>/proto/
```

### 3. Add build.rs
```rust
fn main() {
    tonic_build::compile_protos("proto/thanos.proto").unwrap();
}
```

### 4. Use in zeke
```rust
mod thanos {
    tonic::include_proto!("thanos");
}

use thanos::thanos_service_client::ThanosServiceClient;

async fn chat(prompt: &str) -> Result<String> {
    let mut client = ThanosServiceClient::connect("http://localhost:50051").await?;

    let request = tonic::Request::new(ChatRequest {
        model: "auto".to_string(),
        messages: vec![Message {
            role: "user".to_string(),
            content: prompt.to_string(),
        }],
        stream: true,
        ..Default::default()
    });

    let mut stream = client.chat_completion(request).await?.into_inner();
    let mut result = String::new();

    while let Some(chunk) = stream.message().await? {
        result.push_str(&chunk.content);
    }

    Ok(result)
}
```

## Connection Management

### Single Request
```rust
let mut client = ThanosServiceClient::connect("http://localhost:50051").await?;
let response = client.chat_completion(request).await?;
```

### Persistent Connection (Recommended)
```rust
// Store in your app state
struct App {
    thanos: ThanosServiceClient<Channel>,
}

impl App {
    async fn new() -> Result<Self> {
        let channel = Channel::from_static("http://localhost:50051")
            .connect()
            .await?;

        Ok(Self {
            thanos: ThanosServiceClient::new(channel),
        })
    }
}
```

## Error Handling

```rust
match client.chat_completion(request).await {
    Ok(response) => {
        // Handle streaming
    }
    Err(status) => {
        match status.code() {
            tonic::Code::Unavailable => {
                eprintln!("Thanos server not running");
            }
            tonic::Code::InvalidArgument => {
                eprintln!("Invalid request: {}", status.message());
            }
            _ => {
                eprintln!("gRPC error: {}", status);
            }
        }
    }
}
```

## Configuration

### Connect to custom endpoint
```rust
let endpoint = env::var("THANOS_GRPC_ENDPOINT")
    .unwrap_or_else(|_| "http://localhost:50051".to_string());

let mut client = ThanosServiceClient::connect(endpoint).await?;
```

### Use Unix socket instead
```rust
// For maximum performance in zeke
let channel = Endpoint::try_from("http://[::]:50051")?
    .connect_with_connector(service_fn(|_: Uri| {
        UnixStream::connect("/var/run/thanos/thanos.sock")
    }))
    .await?;
```

## Troubleshooting

### Server not running
```bash
# Check if Thanos is running
lsof -i :50051
lsof -i :8080

# Or check UDS socket
ls -la /var/run/thanos/thanos.sock
```

### Connection refused
```bash
# Check server logs
RUST_LOG=debug cargo run

# Test with grpcurl
grpcurl -plaintext localhost:50051 list
```

### Proto compilation fails
```bash
# Make sure proto file exists
ls -la ../../proto/thanos.proto

# Install protoc if needed
sudo apt install protobuf-compiler  # Linux
brew install protobuf                # macOS
```

## Next Steps

1. **For zeke CLI**: Use gRPC client (fastest, type-safe)
2. **For zeke.nvim**: Use UDS client (lowest latency)
3. **For debugging**: Use HTTP client (curl-friendly)

See main Thanos docs for more: [../../docs/](../../docs/)
