FROM rust:1.71-slim-bullseye as builder
ARG GUEST_COMPONENTS_COMMIT=88dcc14

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    libssl-dev \
    pkg-config

RUN git clone https://github.com/confidential-containers/guest-components.git -b main /build
WORKDIR /build
RUN git checkout $GUEST_COMPONENTS_COMMIT
RUN rustup component add rustfmt
RUN cargo b --release -p coco_keyprovider

FROM debian:bullseye-slim
RUN apt-get update && apt-get install -y openssl
COPY --from=builder /build/target/release/coco_keyprovider /usr/local/bin/coco_keyprovider
CMD ["/usr/local/bin/coco_keyprovider", "--socket", "0.0.0.0:50000"]
