#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${PROJECT_DIR}/.env.site-a"
COMPOSE_FILE_PATH="${PROJECT_DIR}/docker-compose.site-a.macvlan.yml"

usage() {
  cat <<'EOF'
Usage:
  ./start-site-a.sh [--install-deps] [--down-first]

Options:
  --install-deps  Reinstall Docker/dependencies with install-deps-linux.sh before compose up.
  --down-first    Stop the Site A stack before starting it again.

Required file:
  .env.site-a

Create it from:
  cp .env.site-a.example .env.site-a
  nano .env.site-a
EOF
}

INSTALL_DEPS=0
DOWN_FIRST=0

for arg in "$@"; do
  case "${arg}" in
    --install-deps)
      INSTALL_DEPS=1
      ;;
    --down-first)
      DOWN_FIRST=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[error] Unknown option: %s\n\n' "${arg}" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${ENV_FILE}" ]]; then
  printf '[error] Missing %s\n' "${ENV_FILE}" >&2
  printf 'Create it with: cp .env.site-a.example .env.site-a\n' >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "${ENV_FILE}"
set +a

: "${SERVICES_IFACE:?SERVICES_IFACE is required in .env.site-a}"
: "${VOICE_IFACE:?VOICE_IFACE is required in .env.site-a}"
: "${OPENVPN_HOSTNAME:?OPENVPN_HOSTNAME is required in .env.site-a}"

printf '== Site A macvlan ==\n'
printf 'SERVICES_IFACE=%s\n' "${SERVICES_IFACE}"
printf 'VOICE_IFACE=%s\n' "${VOICE_IFACE}"
printf 'OPENVPN_HOSTNAME=%s\n' "${OPENVPN_HOSTNAME}"

if [[ "${INSTALL_DEPS}" == "1" ]]; then
  COMPOSE_FILE="${COMPOSE_FILE_PATH}" "${PROJECT_DIR}/install-deps-linux.sh"
  exit 0
fi

if [[ "${DOWN_FIRST}" == "1" ]]; then
  docker compose --project-directory "${PROJECT_DIR}" -f "${COMPOSE_FILE_PATH}" down --remove-orphans
fi

docker compose --project-directory "${PROJECT_DIR}" -f "${COMPOSE_FILE_PATH}" config --quiet
docker compose --project-directory "${PROJECT_DIR}" -f "${COMPOSE_FILE_PATH}" up -d --build --remove-orphans
docker compose --project-directory "${PROJECT_DIR}" -f "${COMPOSE_FILE_PATH}" ps
