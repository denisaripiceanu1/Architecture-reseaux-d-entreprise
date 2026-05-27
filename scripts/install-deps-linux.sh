#!/usr/bin/env bash
set -Eeuo pipefail

# install-deps-linux.sh
#
# Robust dependency installer for Debian/Ubuntu.
#
# Docker behavior:
# - stop docker/containerd systemd units
# - reset-failed and unmask docker.service, docker.socket, containerd.service
# - remove conflicting Docker packages
# - purge official Docker packages before reinstalling
# - remove stale runtime sockets
# - remove Docker data by default for a clean lab reinstall
# - reinstall Docker from the official repository
# - enable containerd, docker.socket and docker.service
#
# By default, Docker data is deleted:
#   /var/lib/docker
#   /var/lib/containerd
#
# To keep existing Docker images, volumes and containers:
#   KEEP_DOCKER_DATA=1 ./scripts/install-deps-linux.sh
#
# Vault local storage is prepared at:
#   ./data/vault
#
# Override Vault storage ownership if needed:
#   VAULT_DATA_UID=100 VAULT_DATA_GID=1000 ./scripts/install-deps-linux.sh
#
# The script installs dependencies and can optionally deploy a Compose stack.
# For the day-of lab, prefer the site launchers:
#   ./scripts/start-site-a.sh --install-deps
#   ./scripts/start-site-b.sh --install-deps
#
# To deploy a Compose file directly:
#   COMPOSE_FILE=docker-compose.site-a.macvlan.yml ./scripts/install-deps-linux.sh
#   COMPOSE_FILE=docker-compose.site-b.macvlan.yml ./scripts/install-deps-linux.sh

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APT_UPDATED=0

bold() { printf "\n== %s ==\n" "$*"; }
info() { printf "[info] %s\n" "$*"; }
ok() { printf "[ok] %s\n" "$*"; }
warn() { printf "[warn] %s\n" "$*"; }
err() { printf "[error] %s\n" "$*" >&2; }

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing required command: $1"
    exit 1
  fi
}

detect_os() {
  if [[ ! -r /etc/os-release ]]; then
    err "Cannot read /etc/os-release. This script targets Debian/Ubuntu."
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  case "${ID:-}" in
    ubuntu|debian)
      ;;
    *)
      err "Unsupported distribution: ${ID:-unknown}. Use Debian or Ubuntu."
      exit 1
      ;;
  esac

  OS_ID="${ID}"
  OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"

  if [[ -z "${OS_CODENAME}" ]]; then
    err "Cannot determine VERSION_CODENAME for apt repositories."
    exit 1
  fi

  ok "Detected OS: ${PRETTY_NAME:-$OS_ID $OS_CODENAME}"
}

apt_update_once() {
  if [[ "${APT_UPDATED}" != "1" ]]; then
    $SUDO apt-get update
    APT_UPDATED=1
  fi
}

install_base_packages() {
  bold "1/6 Base packages"
  apt_update_once
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common
  ok "Base packages installed"
}

stop_docker_units() {
  info "Stopping existing Docker/containerd units..."
  $SUDO systemctl stop docker.service docker.socket containerd.service 2>/dev/null || true
  $SUDO systemctl reset-failed docker.service docker.socket containerd.service 2>/dev/null || true
  $SUDO systemctl unmask docker.service docker.socket containerd.service 2>/dev/null || true
}

stop_docker_processes() {
  info "Stopping leftover Docker/containerd processes..."

  if command -v pkill >/dev/null 2>&1; then
    $SUDO pkill -TERM -x dockerd 2>/dev/null || true
    $SUDO pkill -TERM -x containerd 2>/dev/null || true
    $SUDO pkill -TERM -x docker-proxy 2>/dev/null || true
    $SUDO pkill -TERM -f 'containerd-shim' 2>/dev/null || true
    sleep 2
    $SUDO pkill -KILL -x dockerd 2>/dev/null || true
    $SUDO pkill -KILL -x containerd 2>/dev/null || true
    $SUDO pkill -KILL -x docker-proxy 2>/dev/null || true
    $SUDO pkill -KILL -f 'containerd-shim' 2>/dev/null || true
  else
    warn "pkill not found; skipping leftover process cleanup"
  fi
}

purge_docker_packages() {
  info "Removing Docker packages and common conflicts..."

  local packages=(
    docker
    docker.io
    docker-doc
    docker-compose
    docker-compose-v2
    podman-docker
    containerd
    runc
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
    docker-ce-rootless-extras
  )

  $SUDO DEBIAN_FRONTEND=noninteractive apt-get remove -y "${packages[@]}" 2>/dev/null || true
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get purge -y "${packages[@]}" 2>/dev/null || true
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get autoremove -y 2>/dev/null || true

  ok "Previous Docker packages removed"
}

cleanup_docker_netns() {
  info "Unmounting leftover Docker network namespaces..."

  if [[ ! -d /run/docker/netns ]]; then
    return
  fi

  if command -v findmnt >/dev/null 2>&1; then
    while IFS= read -r target; do
      [[ -n "${target}" ]] || continue
      $SUDO umount -l "${target}" 2>/dev/null || true
    done < <(findmnt -R /run/docker/netns -n -o TARGET 2>/dev/null | sort -r)
  fi

  while IFS= read -r ns_path; do
    [[ -n "${ns_path}" ]] || continue
    if mountpoint -q "${ns_path}" 2>/dev/null; then
      $SUDO umount -l "${ns_path}" 2>/dev/null || true
    fi
  done < <(find /run/docker/netns -mindepth 1 -maxdepth 1 -print 2>/dev/null || true)
}

cleanup_docker_runtime() {
  info "Cleaning Docker runtime sockets and state..."

  $SUDO rm -f \
    /run/docker.sock \
    /var/run/docker.sock \
    /run/docker.pid \
    /var/run/docker.pid

  cleanup_docker_netns

  $SUDO rm -rf \
    /run/docker \
    /run/containerd || true

  if [[ "${KEEP_DOCKER_DATA:-0}" == "1" ]]; then
    info "KEEP_DOCKER_DATA=1: preserving /var/lib/docker and /var/lib/containerd"
  else
    warn "Deleting /var/lib/docker and /var/lib/containerd for a clean reinstall"
    $SUDO rm -rf /var/lib/docker /var/lib/containerd || true
  fi
}

configure_docker_repository() {
  bold "2/6 Docker official repository"

  $SUDO install -m 0755 -d /etc/apt/keyrings
  $SUDO rm -f /etc/apt/keyrings/docker.gpg

  curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" \
    | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

  local arch
  arch="$(dpkg --print-architecture)"

  printf "deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/%s %s stable\n" \
    "${arch}" "${OS_ID}" "${OS_CODENAME}" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

  APT_UPDATED=0
  apt_update_once

  ok "Docker repository configured"
}

install_docker() {
  bold "3/6 Docker Engine and Compose"

  stop_docker_units
  stop_docker_processes
  purge_docker_packages
  cleanup_docker_runtime
  configure_docker_repository

  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  info "Reloading and repairing systemd units..."
  $SUDO systemctl daemon-reload
  $SUDO systemctl unmask docker.service docker.socket containerd.service 2>/dev/null || true
  $SUDO systemctl reset-failed docker.service docker.socket containerd.service 2>/dev/null || true

  info "Enabling containerd, docker.socket and docker.service..."
  $SUDO systemctl enable --now containerd.service
  $SUDO systemctl enable --now docker.socket
  $SUDO systemctl restart docker.service

  if ! $SUDO systemctl is-active --quiet docker.socket; then
    err "docker.socket is not active"
    $SUDO systemctl status docker.socket --no-pager || true
    exit 1
  fi

  if ! $SUDO systemctl is-active --quiet docker.service; then
    err "docker.service is not active"
    $SUDO systemctl status docker.service --no-pager || true
    $SUDO journalctl -u docker.socket -u docker.service -n 120 --no-pager || true
    exit 1
  fi

  $SUDO docker version >/dev/null
  $SUDO docker compose version >/dev/null

  ok "Docker is installed and active"

  if [[ -n "${SUDO}" ]]; then
    if groups "${USER}" | grep -qw docker; then
      ok "User ${USER} is already in the docker group"
    else
      info "Adding ${USER} to the docker group..."
      $SUDO usermod -aG docker "${USER}"
      warn "Log out and back in to use docker without sudo."
    fi
  fi
}

install_vault_cli() {
  bold "4/5 HashiCorp Vault CLI"

  $SUDO install -m 0755 -d /etc/apt/keyrings
  $SUDO rm -f /etc/apt/keyrings/hashicorp.gpg

  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | $SUDO gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg

  $SUDO chmod a+r /etc/apt/keyrings/hashicorp.gpg

  local arch
  arch="$(dpkg --print-architecture)"

  printf "deb [arch=%s signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com %s main\n" \
    "${arch}" "${OS_CODENAME}" \
    | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

  APT_UPDATED=0
  apt_update_once

  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y vault
  ok "Vault CLI installed"
}

install_utilities() {
  bold "5/5 Utilities"
  apt_update_once

  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
    dnsutils \
    ldap-utils \
    python3 \
    jq \
    netcat-openbsd \
    iproute2 \
    iputils-ping

  ok "Utilities installed"
}

prepare_project_dirs() {
  bold "Project directories"

  mkdir -p \
    "${PROJECT_DIR}/vault-credentials" \
    "${PROJECT_DIR}/vault-credentials/openldap" \
    "${PROJECT_DIR}/vault-credentials/openvpn" \
    "${PROJECT_DIR}/vault-credentials/asterisk" \
    "${PROJECT_DIR}/data/vault"

  info "Preparing local Vault storage permissions..."
  $SUDO chown -R "${VAULT_DATA_UID:-100}:${VAULT_DATA_GID:-1000}" "${PROJECT_DIR}/data/vault"
  $SUDO chmod 700 "${PROJECT_DIR}/data/vault"

  ok "Project directories are ready"
}

deploy_compose_stack() {
  if [[ "${SKIP_COMPOSE_UP:-0}" == "1" ]]; then
    warn "SKIP_COMPOSE_UP=1: skipping Docker Compose build/up"
    return
  fi

  bold "Docker Compose stack"

  local compose_file="${COMPOSE_FILE:-}"

  if [[ -z "${compose_file}" ]]; then
    warn "COMPOSE_FILE is not set: skipping Docker Compose deployment"
    warn "Use ./scripts/start-site-a.sh --install-deps or ./scripts/start-site-b.sh --install-deps for the day-of lab"
    return
  fi

  if [[ "${compose_file}" != /* ]]; then
    compose_file="${PROJECT_DIR}/${compose_file}"
  fi

  if [[ ! -f "${compose_file}" ]]; then
    err "Compose file not found: ${compose_file}"
    exit 1
  fi

  local compose_args=(
    --project-directory "${PROJECT_DIR}"
    -f "${compose_file}"
  )

  if [[ -n "${COMPOSE_PROFILES:-}" ]]; then
    local profile
    IFS=',' read -r -a profiles <<< "${COMPOSE_PROFILES}"
    for profile in "${profiles[@]}"; do
      [[ -n "${profile}" ]] && compose_args+=(--profile "${profile}")
    done
  fi

  if [[ "${COMPOSE_DOWN_FIRST:-0}" == "1" ]]; then
    warn "COMPOSE_DOWN_FIRST=1: stopping existing stack before rebuild"
    $SUDO docker compose "${compose_args[@]}" down --remove-orphans || true
  fi

  info "Validating Compose file..."
  $SUDO docker compose "${compose_args[@]}" config --quiet

  info "Building Compose images..."
  $SUDO docker compose "${compose_args[@]}" build

  info "Starting Compose stack..."
  $SUDO docker compose "${compose_args[@]}" up -d --remove-orphans

  ok "Compose stack is running"
}

print_summary() {
  bold "Summary"

  $SUDO docker --version || true
  $SUDO docker compose version || true
  vault version || true

  cat <<'EOF'

Useful commands:
  sudo systemctl status docker.socket docker.service --no-pager
  sudo journalctl -u docker.socket -u docker.service -n 120 --no-pager
  ./scripts/start-site-a.sh
  ./scripts/start-site-b.sh

Keep existing Docker data:
  KEEP_DOCKER_DATA=1 ./scripts/install-deps-linux.sh

Use the pfSense/macvlan Compose files:
  COMPOSE_FILE=docker-compose.site-a.macvlan.yml ./scripts/install-deps-linux.sh
  COMPOSE_FILE=docker-compose.site-b.macvlan.yml ./scripts/install-deps-linux.sh

Override Vault local storage ownership:
  VAULT_DATA_UID=100 VAULT_DATA_GID=1000 ./scripts/install-deps-linux.sh
EOF
}

main() {
  bold "Entreprise 3 dependency installer"

  require_command apt-get
  require_command systemctl

  detect_os
  install_base_packages

  require_command curl
  require_command gpg
  require_command dpkg

  install_docker
  install_vault_cli
  install_utilities
  prepare_project_dirs
  deploy_compose_stack
  print_summary
}

main "$@"
