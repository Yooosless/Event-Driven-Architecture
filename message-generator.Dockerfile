FROM rust:1.91 AS builder
WORKDIR /app
COPY message-generator/Cargo.toml message-generator/Cargo.toml
COPY message-generator/src message-generator/src
WORKDIR /app/message-generator
RUN cargo build --release


FROM ubuntu:24.04
WORKDIR /app

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/message-generator/target/release/message-generator .

CMD ["./message-generator"]