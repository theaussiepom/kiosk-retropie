FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# GitHub Actions installs markdownlint via npm (modern Node). The ubuntu-22.04
# base image can ship an older Node, so install a current LTS from NodeSource.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
  && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    kcov \
    make \
    nodejs \
    python3 \
    python3-pip \
    shellcheck \
    shfmt \
    strace \
    sudo \
    systemd \
    yamllint \
  && rm -rf /var/lib/apt/lists/*

# markdownlint used by scripts/ci.sh expects the Node CLI with JSON config.
RUN npm install -g markdownlint-cli \
  && npm cache clean --force
