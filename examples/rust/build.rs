fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Compile the proto file for gRPC examples
    tonic_build::configure()
        .build_client(true)
        .build_server(false)
        .compile(&["../../proto/thanos.proto"], &["../../proto/"])?;

    Ok(())
}
