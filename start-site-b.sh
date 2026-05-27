#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${PROJECT_DIR}/.env.site-b"
COMPOSE_FILE_PATH="${PROJECT_DIR}/docker-compose.site-b.macvlan.yml"

usage() {
  cat <<'EOF'
Usage:
  ./start-site-b.sh [--install-deps] [--down-first]

Options:
  --install-deps  Reinstall Docker/dependencies with install-deps-linux.sh before compose up.
  --down-first    Stop the Site B stack before starting it again.

Required file:
  .env.site-b

Create it from:
  cp .env.site-b.example .env.site-b
  nano .env.site-b
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
  printf 'Create it with: cp .env.site-b.example .env.site-b\n' >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "${ENV_FILE}"
set +a

: "${DMZ_IFACE:?DMZ_IFACE is required in .env.site-b}"

printf '== Site B macvlan ==\n'
printf 'DMZ_IFACE=%s\n' "${DMZ_IFACE}"

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
