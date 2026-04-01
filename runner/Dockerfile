FROM debian:bookworm-slim

ARG RUNNER_VERSION=2.333.1
ARG TARGETARCH

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    git \
    jq \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install the CA certificate so the runner trusts iron-proxy's TLS
COPY ca/ca.crt /usr/local/share/ca-certificates/iron-proxy-ca.crt
RUN update-ca-certificates

# Create a non-root user for the runner
RUN useradd -m -s /bin/bash runner && \
    echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Download and extract the GitHub Actions runner (pick arch automatically)
WORKDIR /home/runner/actions-runner
RUN RUNNER_ARCH=$(case "$TARGETARCH" in arm64) echo "arm64" ;; *) echo "x64" ;; esac) && \
    curl -fL -o runner.tar.gz \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" && \
    tar xzf runner.tar.gz && \
    rm runner.tar.gz && \
    ./bin/installdependencies.sh && \
    chown -R runner:runner /home/runner/actions-runner

COPY runner/entrypoint.sh ./entrypoint.sh
RUN chmod +x entrypoint.sh && chown runner:runner entrypoint.sh

USER runner

ENTRYPOINT ["./entrypoint.sh"]
