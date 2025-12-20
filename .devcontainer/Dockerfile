FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    kcov \
    make \
    python3 \
    python3-pip \
    shellcheck \
    strace \
    sudo \
  && rm -rf /var/lib/apt/lists/*
