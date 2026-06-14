# --- Build Stage ---
FROM rust:1.91 AS builder
WORKDIR /app

COPY hello-world/Cargo.toml hello-world/Cargo.lock* ./hello-world/
COPY hello-world/src hello-world/src

WORKDIR /app/hello-world
RUN rm -f Cargo.lock

RUN cargo update

RUN cargo build --release

FROM ubuntu:24.04
WORKDIR /app

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/hello-world/target/release/hello-world .

EXPOSE 8080
CMD ["./hello-world"]