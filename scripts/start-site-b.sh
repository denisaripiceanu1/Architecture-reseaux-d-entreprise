#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/env/site-b.env"
COMPOSE_FILE_PATH="${PROJECT_DIR}/docker-compose.site-b.macvlan.yml"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/start-site-b.sh [--install-deps] [--down-first]

Options:
  --install-deps  Reinstall Docker/dependencies with scripts/install-deps-linux.sh before compose up.
  --down-first    Stop the Site B stack before starting it again.

Required file:
  env/site-b.env

Create it from:
  cp env/site-b.env.example env/site-b.env
  nano env/site-b.env
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
  printf 'Create it with: cp env/site-b.env.example env/site-b.env\n' >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "${ENV_FILE}"
set +a

: "${DMZ_IFACE:?DMZ_IFACE is required in env/site-b.env}"

printf '== Site B macvlan ==\n'
printf 'DMZ_IFACE=%s\n' "${DMZ_IFACE}"

compose() {
  docker compose --env-file "${ENV_FILE}" --project-directory "${PROJECT_DIR}" -f "${COMPOSE_FILE_PATH}" "$@"
}

compose_pull_with_retries() {
  local max_attempts="${COMPOSE_PULL_RETRIES:-5}"
  local attempt

  for attempt in $(seq 1 "${max_attempts}"); do
    if compose pull --ignore-buildable; then
      return 0
    fi

    printf '[warn] Compose image pull failed, retry %s/%s\n' "${attempt}" "${max_attempts}" >&2
    sleep $((attempt * 5))
  done

  printf '[error] Compose image pull failed after %s attempts\n' "${max_attempts}" >&2
  return 1
}

if [[ "${INSTALL_DEPS}" == "1" ]]; then
  COMPOSE_FILE="${COMPOSE_FILE_PATH}" COMPOSE_ENV_FILE="${ENV_FILE}" "${PROJECT_DIR}/scripts/install-deps-linux.sh"
  exit 0
fi

if [[ "${DOWN_FIRST}" == "1" ]]; then
  compose down --remove-orphans
fi

compose config --quiet
compose_pull_with_retries
compose up -d --build --remove-orphans
compose ps
