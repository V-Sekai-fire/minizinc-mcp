# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

# Build stage
FROM almalinux:9 AS builder

WORKDIR /app

# Install build dependencies
# Use --allowerasing to replace curl-minimal with curl if needed
RUN dnf update -y && dnf install -y --allowerasing \
    gcc g++ make git \
    openssl-devel \
    zlib-devel \
    unzip \
    wget \
    curl \
    which \
    ca-certificates \
    ncurses-devel

# Install Erlang/OTP 26 from EPEL (available in AlmaLinux 9)
RUN dnf install -y epel-release && \
    dnf install -y erlang erlang-erl_interface && \
    erl -version

# Install Elixir 1.18 from precompiled binaries (compatible with OTP 26)
# Using v1.18-latest tag for latest 1.18.x release
RUN cd /tmp && \
    curl -Lf https://github.com/elixir-lang/elixir/releases/download/v1.18-latest/elixir-otp-26.zip -o elixir.zip && \
    unzip -q elixir.zip && \
    mkdir -p /opt/elixir && \
    mv bin lib man /opt/elixir/ && \
    rm -rf elixir.zip && \
    /opt/elixir/bin/elixir --version

ENV PATH="/opt/elixir/bin:/usr/local/bin:${PATH}"
ENV ELIXIR_ERL_OPTIONS="+fnu"
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install MiniZinc
# Download and install MiniZinc from official releases
# Using MiniZincIDE bundle which includes MiniZinc compiler and solvers
RUN cd /tmp && \
    curl -Lf https://github.com/MiniZinc/MiniZincIDE/releases/download/2.9.3/MiniZincIDE-2.9.3-bundle-linux-x86_64.tgz -o minizinc.tar.gz && \
    tar -xzf minizinc.tar.gz && \
    mkdir -p /opt/minizinc && \
    # The bundle extracts to a directory - find it and copy contents
    EXTRACTED_DIR=$(ls -d MiniZincIDE* 2>/dev/null | head -1) && \
    if [ -n "$EXTRACTED_DIR" ] && [ -d "$EXTRACTED_DIR" ]; then \
        cp -r "$EXTRACTED_DIR"/* /opt/minizinc/; \
    else \
        # Fallback: look for bin/minizinc in current directory or subdirectories
        EXTRACTED_DIR=$(find . -name "minizinc" -type f -path "*/bin/minizinc" | head -1 | xargs dirname | xargs dirname) && \
        if [ -n "$EXTRACTED_DIR" ] && [ -d "$EXTRACTED_DIR" ]; then \
            cp -r "$EXTRACTED_DIR"/* /opt/minizinc/; \
        else \
            echo "Error: Could not find extracted MiniZinc directory" && exit 1; \
        fi; \
    fi && \
    rm -rf minizinc.tar.gz MiniZincIDE* && \
    /opt/minizinc/bin/minizinc --version

# Install HiGHS solver binary (LP/MIP; required for --solver highs)
# MiniZinc bundle includes the solver definition but not the binary; put highs in PATH for minizinc to find it
ARG HIGHS_VERSION=1.13.1
RUN cd /tmp && \
    curl -Lf "https://github.com/ERGO-Code/HiGHS/releases/download/v${HIGHS_VERSION}/highs-${HIGHS_VERSION}-x86_64-linux-gnu-static-mit.tar.gz" -o highs.tar.gz && \
    tar -xzf highs.tar.gz && \
    HIGHS_DIR=$(find . -maxdepth 1 -type d -name 'highs-*' | head -1) && \
    cp "$HIGHS_DIR/bin/highs" /opt/minizinc/bin/highs && \
    chmod +x /opt/minizinc/bin/highs && \
    rm -rf highs.tar.gz highs-* && \
    /opt/minizinc/bin/highs --version || true

ENV PATH="/opt/minizinc/bin:${PATH}"

# Copy dependency files
COPY mix.exs mix.lock* ./
COPY config ./config

# Install dependencies
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy source code
COPY lib ./lib

# Compile the application
RUN MIX_ENV=prod mix compile

# Build the release
RUN MIX_ENV=prod mix release

# Runtime stage
FROM almalinux:9

WORKDIR /app

# Install runtime dependencies
# Note: Mix releases include ERTS, but we install Erlang from repos for compatibility
# Install Erlang/OTP 26 from EPEL (same as builder)
RUN dnf update -y && \
    dnf install -y epel-release && \
    dnf install -y \
    openssl \
    ncurses-libs \
    libstdc++ \
    erlang \
    wget \
    ca-certificates \
    glibc-langpack-en && \
    localedef -c -i en_US -f UTF-8 en_US.UTF-8 || true && \
    dnf clean all

# Copy Elixir installation from builder
COPY --from=builder /opt/elixir /opt/elixir

# Copy MiniZinc installation from builder
COPY --from=builder /opt/minizinc /opt/minizinc

# Set PATH to include Elixir and MiniZinc binaries
# This ensures System.cmd("minizinc", ...) in the release can find the minizinc binary
ENV PATH="/opt/elixir/bin:/opt/minizinc/bin:${PATH}"

# Copy the release from builder
COPY --from=builder /app/_build/prod/rel/minizinc_mcp ./minizinc_mcp

# Set environment variables
ENV MIX_ENV=prod
ENV MCP_TRANSPORT=http
ENV PORT=8081
ENV ELIXIR_ERL_OPTIONS="+fnu"
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
# PATH is already set above (line 115) to include /opt/minizinc/bin
# This ensures System.cmd("minizinc", ...) can find the minizinc binary

# Expose the port
EXPOSE 8081

# Start the server
CMD ["./minizinc_mcp/bin/minizinc_mcp", "start"]

