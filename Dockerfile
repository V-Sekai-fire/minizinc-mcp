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
RUN cd /tmp && \
    curl -Lf https://github.com/MiniZinc/MiniZinc/releases/download/2.9.0/minizinc-2.9.0-linux-x86_64.tar.gz -o minizinc.tar.gz && \
    tar -xzf minizinc.tar.gz && \
    mkdir -p /opt/minizinc && \
    mv minizinc-2.9.0/* /opt/minizinc/ && \
    rm -rf minizinc.tar.gz minizinc-2.9.0 && \
    /opt/minizinc/bin/minizinc --version

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

# Expose the port
EXPOSE 8081

# Start the server
CMD ["./minizinc_mcp/bin/minizinc_mcp", "start"]

