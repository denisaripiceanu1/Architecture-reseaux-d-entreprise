#!/usr/bin/env bash
# =============================================================================
# install-deps-linux.sh — Installation des dépendances (Debian/Ubuntu)
# Infrastructure Réseau Entreprise 3a / 3b
#
# Usage :
#   chmod +x install-deps-linux.sh
#   ./install-deps-linux.sh
# =============================================================================

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
info() { echo -e "${BLUE}  → $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
fail() { echo -e "${RED}  ✗ $1${NC}"; exit 1; }

echo ""
echo "============================================================"
echo " Installation des dépendances — Linux (Debian/Ubuntu)"
echo " Infrastructure Réseau Entreprise 3a / 3b"
echo "============================================================"
echo ""

# -------------------------------------------------------------------
# Vérification OS
# -------------------------------------------------------------------
if [ ! -f /etc/debian_version ] && [ ! -f /etc/ubuntu_release ]; then
  warn "Ce script est conçu pour Debian/Ubuntu."
  warn "Pour d'autres distributions, adapter les commandes apt en conséquence."
  read -rp "  Continuer quand même ? (o/N) " confirm
  [[ "$confirm" =~ ^[oO]$ ]] || exit 0
fi

# -------------------------------------------------------------------
# Vérification sudo
# -------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  if ! command -v sudo &>/dev/null; then
    fail "sudo n'est pas disponible. Relancer en root ou installer sudo."
  fi
  SUDO="sudo"
else
  SUDO=""
fi

# -------------------------------------------------------------------
# Mise à jour des paquets
# -------------------------------------------------------------------
echo "[1/6] Mise à jour de l'index apt..."
$SUDO apt-get update -qq
ok "Index mis à jour"

# -------------------------------------------------------------------
# Docker
# -------------------------------------------------------------------
echo ""
echo "[2/6] Docker..."
if command -v docker &>/dev/null; then
  DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
  ok "Docker déjà installé (v$DOCKER_VERSION)"
else
  info "Installation de Docker Engine..."
  $SUDO apt-get install -y -qq ca-certificates curl gnupg lsb-release

  install_docker_official_repo() {
    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
      $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
  }

  $SUDO install -m 0755 -d /etc/apt/keyrings
  install_docker_official_repo

  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin

  # Ajouter l'utilisateur courant au groupe docker
  if [ -n "${SUDO_USER:-}" ]; then
    $SUDO usermod -aG docker "$SUDO_USER"
    warn "L'utilisateur '$SUDO_USER' a été ajouté au groupe docker."
    warn "Déconnectez-vous et reconnectez-vous pour que cela prenne effet."
  fi
  ok "Docker installé"
fi

# -------------------------------------------------------------------
# Docker Compose (plugin v2)
# -------------------------------------------------------------------
echo ""
echo "[3/6] Docker Compose..."
if docker compose version &>/dev/null; then
  COMPOSE_VERSION=$(docker compose version --short)
  ok "Docker Compose déjà disponible (v$COMPOSE_VERSION)"
else
  info "Installation du plugin Docker Compose depuis le dépôt officiel Docker..."
  $SUDO apt-get install -y -qq docker-compose-plugin
  if docker compose version &>/dev/null; then
    COMPOSE_VERSION=$(docker compose version --short)
    ok "Docker Compose installé (v$COMPOSE_VERSION)"
  else
    fail "Le paquet docker-compose-plugin n'est pas disponible dans le dépôt Docker configuré. Vérifie le fichier /etc/apt/sources.list.d/docker.list et exécute apt-get update."
  fi
fi

# -------------------------------------------------------------------
# WireGuard Tools
# -------------------------------------------------------------------
echo ""
echo "[4/6] WireGuard Tools..."
if command -v wg &>/dev/null; then
  WG_VERSION=$(wg --version | head -1)
  ok "wireguard-tools déjà installé ($WG_VERSION)"
else
  info "Installation de wireguard-tools..."
  $SUDO apt-get install -y -qq wireguard-tools
  ok "wireguard-tools installé"
fi

# -------------------------------------------------------------------
# Vault CLI
# -------------------------------------------------------------------
echo ""
echo "[5/6] HashiCorp Vault CLI..."
if command -v vault &>/dev/null; then
  VAULT_VERSION=$(vault version | awk '{print $2}')
  ok "Vault CLI déjà installé ($VAULT_VERSION)"
else
  info "Installation de Vault CLI..."
  $SUDO apt-get install -y -qq gpg wget

  wget -O- https://apt.releases.hashicorp.com/gpg | \
    $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    $SUDO tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq vault
  ok "Vault CLI installé"
fi

# -------------------------------------------------------------------
# Utilitaires (ldap-utils, dig, python3)
# -------------------------------------------------------------------
echo ""
echo "[6/6] Utilitaires (ldap-utils, dnsutils, python3)..."

PKGS=()
command -v ldapsearch &>/dev/null || PKGS+=(ldap-utils)
command -v dig       &>/dev/null || PKGS+=(dnsutils)
command -v python3   &>/dev/null || PKGS+=(python3)

if [ ${#PKGS[@]} -eq 0 ]; then
  ok "Utilitaires déjà installés"
else
  info "Installation : ${PKGS[*]}"
  $SUDO apt-get install -y -qq "${PKGS[@]}"
  ok "Utilitaires installés"
fi

# -------------------------------------------------------------------
# Création des dossiers vides WireGuard (gitkeep)
# -------------------------------------------------------------------
mkdir -p config/wireguard/3a config/wireguard/3b
touch config/wireguard/3a/.gitkeep config/wireguard/3b/.gitkeep

# -------------------------------------------------------------------
# Résumé
# -------------------------------------------------------------------
echo ""
echo "============================================================"
echo " INSTALLATION TERMINÉE"
echo "============================================================"
echo ""
echo " Versions installées :"
docker  --version
docker compose version
wg --version | head -1
vault version
python3 --version
echo ""
echo " Prochaine étape :"
echo "   docker compose up -d vault"
echo "   ./config/vault/vault-init.sh"
echo "============================================================"
