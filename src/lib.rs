pub mod config;
pub mod server;
pub mod providers;
pub mod auth;
pub mod types;
pub mod router;
pub mod metrics;
pub mod rate_limit;
pub mod circuit_breaker;
pub mod cache;
pub mod models_dev;

// Re-export commonly used types
pub use config::Config;
pub use types::{ChatMessage, ChatRequest, ChatResponse, Provider as ProviderType};

// gRPC generated code
pub mod proto {
    tonic::include_proto!("thanos");

    // File descriptor set for gRPC reflection
    pub const FILE_DESCRIPTOR_SET: &[u8] =
        include_bytes!("../target/thanos_descriptor.bin");
}

pub const VERSION: &str = env!("CARGO_PKG_VERSION");
