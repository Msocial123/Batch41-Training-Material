#!/usr/bin/env bash
set -euo pipefail

# 1) CONFIG
COMPOSE_FALLBACK_VERSION="v2.20.2"   # fallback compose binary version if package not available
TMPDIR="/tmp/install-tools-$$"
AWS_TMP="$TMPDIR/awscli"
ARCH="$(uname -m)"   # x86_64 or aarch64
SUDO_USER="${SUDO_USER:-${USER}}"

# 2) PREP
mkdir -p "$TMPDIR"
echo "Temporary workdir: $TMPDIR"

# ------------------------------------------------------------------
# NOTE: Do NOT attempt to install 'curl' here because Amazon Linux
# images often include 'curl-minimal' which conflicts with 'curl'
# packages. We only *check* for curl and warn if missing.
# ------------------------------------------------------------------
if command -v curl >/dev/null 2>&1; then
  echo "curl present: $(curl --version | head -n1)"
else
  echo "WARNING: curl is not installed. This script assumes curl is available"
  echo "         (not installing curl to avoid package conflicts)."
  echo "         Please install curl manually if required."
  # we continue, but AWS CLI / downloads will fail without curl
fi

# Install unzip only if missing (safe to attempt)
if command -v unzip >/dev/null 2>&1; then
  echo "unzip present: $(unzip -v | head -n1)"
else
  echo "unzip not found - attempting to install unzip..."
  if ! dnf -y install unzip; then
    echo "Failed to install unzip. Please install 'unzip' manually if needed."
  fi
fi

# 3) GIT
if command -v git >/dev/null 2>&1; then
  echo "git already installed: $(git --version)"
else
  echo "Installing git..."
  dnf -y install git
fi

# 4) DOCKER
if command -v docker >/dev/null 2>&1; then
  echo "docker already installed: $(docker --version || true)"
else
  echo "Installing docker..."
  dnf -y install docker || { echo "Failed to install docker via dnf. You may need to enable repos."; exit 1; }
fi

# Enable and start docker
echo "Enabling and starting docker service..."
systemctl enable --now docker

# Add user to docker group so they can run docker without sudo (if user exists)
if id -u "$SUDO_USER" >/dev/null 2>&1; then
  echo "Adding $SUDO_USER to docker group..."
  groupadd -f docker || true
  usermod -aG docker "$SUDO_USER" || true
  echo "Note: $SUDO_USER may need to logout/login for group membership to take effect."
fi

# 5) DOCKER-COMPOSE (try package, fallback to download)
if docker compose version >/dev/null 2>&1; then
  echo "docker compose already available: $(docker compose version 2>/dev/null || true)"
elif dnf -y install docker-compose-plugin >/dev/null 2>&1; then
  echo "Installed docker-compose-plugin via dnf."
else
  echo "docker-compose-plugin not available via dnf; falling back to downloading standalone compose binary..."
  if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "x86-64" ]; then
    COMPOSE_BIN_URL="https://github.com/docker/compose/releases/download/${COMPOSE_FALLBACK_VERSION}/docker-compose-linux-x86_64"
  elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    COMPOSE_BIN_URL="https://github.com/docker/compose/releases/download/${COMPOSE_FALLBACK_VERSION}/docker-compose-linux-aarch64"
  else
    echo "Unsupported architecture for fallback compose binary: $ARCH"
    exit 1
  fi

  echo "Downloading docker-compose from: $COMPOSE_BIN_URL"
  curl -fsSL -o /usr/local/bin/docker-compose "$COMPOSE_BIN_URL"
  chmod +x /usr/local/bin/docker-compose
  if [ ! -f /usr/bin/docker-compose ]; then
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose || true
  fi
  echo "Installed docker-compose binary to /usr/local/bin/docker-compose"
fi

# 6) AWS CLI v2
if command -v aws >/dev/null 2>&1 && aws --version >/dev/null 2>&1; then
  echo "AWS CLI already installed: $(aws --version)"
else
  echo "Installing AWS CLI v2..."
  mkdir -p "$AWS_TMP"
  if [ "$ARCH" = "x86_64" ]; then
    AWS_ZIP_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
  elif [ "$ARCH" = "aarch64" ]; then
    AWS_ZIP_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
  else
    echo "Unsupported architecture for AWS CLI installer: $ARCH"
    exit 1
  fi

  echo "Downloading AWS CLI from $AWS_ZIP_URL..."
  curl -fsSL -o "$TMPDIR/awscliv2.zip" "$AWS_ZIP_URL"
  unzip -q "$TMPDIR/awscliv2.zip" -d "$AWS_TMP"
  "$AWS_TMP"/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin --update || {
    echo "AWS CLI install failed"; exit 1;
  }
  echo "AWS CLI installed: $(/usr/local/bin/aws --version)"
fi

# 7) Set docker socket permissions as requested
DOCKER_SOCK="/var/run/docker.sock"
if [ -S "$DOCKER_SOCK" ]; then
  echo "Setting permissions on $DOCKER_SOCK to 0777 (as requested)"
  chmod 0777 "$DOCKER_SOCK"
else
  echo "Warning: $DOCKER_SOCK does not exist yet. Will set permissions after docker starts."
fi

# 8) CLEANUP
rm -rf "$TMPDIR"
echo "Installation complete."

echo
echo "Summary:"
echo "  - git: $(command -v git >/dev/null 2>&1 && git --version || echo 'not installed')"
echo "  - docker: $(command -v docker >/dev/null 2>&1 && docker --version || echo 'not installed')"
if docker compose version >/dev/null 2>&1; then
  echo "  - docker compose: $(docker compose version 2>/dev/null || true)"
elif command -v docker-compose >/dev/null 2>&1; then
  echo "  - docker-compose (binary): $(docker-compose --version 2>/dev/null || true)"
else
  echo "  - docker compose: not detected"
fi
echo "  - aws: $(command -v aws >/dev/null 2>&1 && aws --version || echo 'not installed')"
echo
echo "If you want non-root docker use without sudo, ensure you log out/login to apply group membership for user: $SUDO_USER"
