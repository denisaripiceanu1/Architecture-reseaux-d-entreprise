#!/usr/bin/env bash
set -Eeuo pipefail

# install-deps-linux-v2.sh
#
# Installe les dépendances du projet sur Debian/Ubuntu.
# Le bloc Docker est volontairement robuste :
#   - arrêt des unités systemd Docker/containerd
#   - reset/unmask des unités, y compris docker.socket
#   - suppression des paquets Docker conflictuels
#   - purge des paquets Docker officiels déjà présents
#   - suppression des sockets runtime obsolètes
#   - réinstallation depuis le dépôt officiel Docker
#   - réactivation de containerd, docker.socket et docker.service
#
# Par défaut, les données Docker (/var/lib/docker, /var/lib/containerd) sont
# supprimées pour repartir d'une installation totalement propre.
# Pour conserver images, volumes et conteneurs :
#
#   KEEP_DOCKER_DATA=1 ./install-deps-linux-v2.sh

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DATA_DIR="${PROJECT_DIR}/data/vault"

mkdir -p "$VAULT_DATA_DIR"
$SUDO chown -R "${VAULT_DATA_UID:-100}:${VAULT_DATA_GID:-1000}" "$VAULT_DATA_DIR"
$SUDO chmod 700 "$VAULT_DATA_DIR"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
info() { printf "ℹ️  %s\n" "$*"; }
ok() { printf "✅ %s\n" "$*"; }
warn() { printf "⚠️  %s\n" "$*"; }
err() { printf "❌ %s\n" "$*" >&2; }

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Commande requise introuvable: $1"
    exit 1
  fi
}

detect_os() {
  if [[ ! -r /etc/os-release ]]; then
    err "Impossible de lire /etc/os-release. Script prévu pour Debian/Ubuntu."
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  case "${ID:-}" in
    ubuntu|debian)
      ;;
    *)
      err "Distribution non supportée: ${ID:-inconnue}. Utiliser Debian ou Ubuntu."
      exit 1
      ;;
  esac

  OS_ID="${ID}"
  OS_CODENAME="${VERSION_CODENAME:-}"

  if [[ -z "${OS_CODENAME}" ]]; then
    OS_CODENAME="$(. /etc/os-release && printf "%s" "${UBUNTU_CODENAME:-}")"
  fi

  if [[ -z "${OS_CODENAME}" ]]; then
    err "Impossible de déterminer VERSION_CODENAME pour le dépôt Docker."
    exit 1
  fi

  ok "OS détecté: ${PRETTY_NAME:-$OS_ID $OS_CODENAME}"
}

apt_update_once() {
  if [[ "${APT_UPDATED:-0}" != "1" ]]; then
    $SUDO apt-get update
    APT_UPDATED=1
  fi
}

install_base_packages() {
  bold "[1/6] Paquets de base"
  apt_update_once
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common
  ok "Paquets de base installés"
}

stop_docker_units() {
  info "Arrêt des services Docker/containerd existants..."
  $SUDO systemctl stop docker.service docker.socket containerd.service 2>/dev/null || true
  $SUDO systemctl reset-failed docker.service docker.socket containerd.service 2>/dev/null || true
  $SUDO systemctl unmask docker.service docker.socket containerd.service 2>/dev/null || true
}

purge_docker_packages() {
  info "Suppression des anciens paquets Docker/conflictuels..."

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

  ok "Paquets Docker précédents supprimés"
}

cleanup_docker_runtime() {
  info "Nettoyage des sockets et états runtime Docker..."

  $SUDO rm -f \
    /run/docker.sock \
    /var/run/docker.sock \
    /run/docker.pid \
    /var/run/docker.pid

  $SUDO rm -rf \
    /run/docker \
    /run/containerd

  if [[ "${KEEP_DOCKER_DATA:-0}" == "1" ]]; then
    info "KEEP_DOCKER_DATA=1: conservation de /var/lib/docker et /var/lib/containerd"
  else
    warn "Suppression de /var/lib/docker et /var/lib/containerd"
    $SUDO rm -rf /var/lib/docker /var/lib/containerd
  fi
}

configure_docker_repository() {
  bold "[2/6] Dépôt officiel Docker"

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

  ok "Dépôt Docker configuré"
}

install_docker() {
  bold "[3/6] Docker Engine + Compose"

  stop_docker_units
  purge_docker_packages
  cleanup_docker_runtime
  configure_docker_repository

  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  info "Réinitialisation systemd Docker..."
  $SUDO systemctl daemon-reload
  $SUDO systemctl unmask docker.service docker.socket containerd.service 2>/dev/null || true
  $SUDO systemctl reset-failed docker.service docker.socket containerd.service 2>/dev/null || true

  info "Activation containerd, docker.socket et docker.service..."
  $SUDO systemctl enable --now containerd.service
  $SUDO systemctl enable --now docker.socket
  $SUDO systemctl restart docker.service

  if ! $SUDO systemctl is-active --quiet docker.socket; then
    err "docker.socket n'est pas actif"
    $SUDO systemctl status docker.socket --no-pager || true
    exit 1
  fi

  if ! $SUDO systemctl is-active --quiet docker.service; then
    err "docker.service n'est pas actif"
    $SUDO systemctl status docker.service --no-pager || true
    $SUDO journalctl -u docker.socket -u docker.service -n 120 --no-pager || true
    exit 1
  fi

  $SUDO docker version >/dev/null
  docker compose version >/dev/null || $SUDO docker compose version >/dev/null

  ok "Docker installé et actif"

  if [[ -n "${SUDO}" ]]; then
    if groups "${USER}" | grep -qw docker; then
      ok "Utilisateur ${USER} déjà membre du groupe docker"
    else
      info "Ajout de ${USER} au groupe docker..."
      $SUDO usermod -aG docker "${USER}"
      warn "Déconnecte/reconnecte ta session pour utiliser docker sans sudo."
    fi
  fi
}

install_wireguard_tools() {
  bold "[4/6] WireGuard Tools"
  apt_update_once
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard-tools
  ok "wireguard-tools installé"
}

install_vault_cli() {
  bold "[5/6] HashiCorp Vault CLI"

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

  ok "Vault CLI installé"
}

install_utilities() {
  bold "[6/6] Utilitaires"
  apt_update_once

  local pkgs=(
    dnsutils
    ldap-utils
    python3
    jq
    netcat-openbsd
    iproute2
    iputils-ping
  )

  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  ok "Utilitaires installés"
}

prepare_project_dirs() {
  info "Création des dossiers de travail du projet..."
  mkdir -p \
    "${PROJECT_DIR}/config/wireguard/3a" \
    "${PROJECT_DIR}/config/wireguard/3b" \
    "${PROJECT_DIR}/vault-credentials"

  touch \
    "${PROJECT_DIR}/config/wireguard/3a/.gitkeep" \
    "${PROJECT_DIR}/config/wireguard/3b/.gitkeep"

  ok "Dossiers projet prêts"
}

print_summary() {
  bold "Résumé"
  docker --version || $SUDO docker --version
  docker compose version || $SUDO docker compose version
  wg --version || true
  vault version || true

  cat <<'EOF'

Commandes utiles :
  sudo systemctl status docker.socket docker.service --no-pager
  docker compose config --quiet
  docker compose up -d

Réinstallation Docker en conservant les données existantes :
  KEEP_DOCKER_DATA=1 ./install-deps-linux-v2.sh
EOF
}

main() {
  bold "Installation dépendances — Entreprise 3"

  require_command apt-get
  require_command systemctl
  detect_os
  install_base_packages
  require_command curl
  require_command gpg
  require_command dpkg
  install_docker
  install_wireguard_tools
  install_vault_cli
  install_utilities
  prepare_project_dirs
  print_summary
}

main "$@"
