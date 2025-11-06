fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Compile protobuf files for gRPC
    tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .file_descriptor_set_path("target/thanos_descriptor.bin") // For gRPC reflection
        .compile(
            &["proto/thanos.proto"],
            &["proto/"],
        )?;

    Ok(())
}
