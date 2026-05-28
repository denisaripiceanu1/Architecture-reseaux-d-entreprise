#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/env/site-a.env"
COMPOSE_FILE_PATH="${PROJECT_DIR}/docker-compose.site-a.macvlan.yml"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/start-site-a.sh [--install-deps] [--down-first] [--skip-ldap-bootstrap]

Options:
  --install-deps         Reinstall Docker/dependencies with scripts/install-deps-linux.sh before compose up.
  --down-first           Stop the Site A stack before starting it again.
  --skip-ldap-bootstrap  Start containers without loading config/ldap/bootstrap.ldif.

Required file:
  env/site-a.env

Create it from:
  cp env/site-a.env.example env/site-a.env
  nano env/site-a.env
EOF
}

INSTALL_DEPS=0
DOWN_FIRST=0
LDAP_BOOTSTRAP=1

for arg in "$@"; do
  case "${arg}" in
    --install-deps)
      INSTALL_DEPS=1
      ;;
    --down-first)
      DOWN_FIRST=1
      ;;
    --skip-ldap-bootstrap)
      LDAP_BOOTSTRAP=0
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
  printf 'Create it with: cp env/site-a.env.example env/site-a.env\n' >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "${ENV_FILE}"
set +a

: "${SERVICES_IFACE:?SERVICES_IFACE is required in env/site-a.env}"
: "${VOICE_IFACE:?VOICE_IFACE is required in env/site-a.env}"
: "${OPENVPN_HOSTNAME:?OPENVPN_HOSTNAME is required in env/site-a.env}"

printf '== Site A macvlan ==\n'
printf 'SERVICES_IFACE=%s\n' "${SERVICES_IFACE}"
printf 'VOICE_IFACE=%s\n' "${VOICE_IFACE}"
printf 'OPENVPN_HOSTNAME=%s\n' "${OPENVPN_HOSTNAME}"

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

run_ldap_bootstrap() {
  if [[ "${LDAP_BOOTSTRAP}" != "1" ]]; then
    printf '[info] LDAP bootstrap skipped\n'
    return
  fi

  printf '\n== LDAP bootstrap ==\n'
  "${PROJECT_DIR}/scripts/bootstrap-openldap-tree.sh"
}

if [[ "${INSTALL_DEPS}" == "1" ]]; then
  COMPOSE_FILE="${COMPOSE_FILE_PATH}" COMPOSE_ENV_FILE="${ENV_FILE}" "${PROJECT_DIR}/scripts/install-deps-linux.sh"
  run_ldap_bootstrap
  exit 0
fi

if [[ "${DOWN_FIRST}" == "1" ]]; then
  compose down --remove-orphans
fi

compose config --quiet
compose_pull_with_retries
compose up -d --build --remove-orphans
run_ldap_bootstrap
compose ps
