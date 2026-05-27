#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LDIF_FILE="${1:-${PROJECT_DIR}/config/ldap/bootstrap.ldif}"

LDAP_CONTAINER="${LDAP_CONTAINER:-openldap}"
LDAP_BASE_DN="${LDAP_BASE_DN:-dc=lafassonnade,dc=lan}"
LDAP_ADMIN_DN="${LDAP_ADMIN_DN:-cn=admin,${LDAP_BASE_DN}}"
LDAP_URL="${LDAP_URL:-ldap://127.0.0.1}"

DOCKER=(docker)
if ! docker ps >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo docker ps >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  fi
fi

docker_cmd() {
  "${DOCKER[@]}" "$@"
}

if [[ ! -f "${LDIF_FILE}" ]]; then
  printf '[error] LDIF file not found: %s\n' "${LDIF_FILE}" >&2
  exit 1
fi

if ! docker_cmd inspect "${LDAP_CONTAINER}" >/dev/null 2>&1; then
  printf '[error] Container not found: %s\n' "${LDAP_CONTAINER}" >&2
  printf 'Start Site A first: ./scripts/start-site-a.sh\n' >&2
  exit 1
fi

container_state="$(docker_cmd inspect -f '{{.State.Status}}' "${LDAP_CONTAINER}")"
if [[ "${container_state}" != "running" ]]; then
  printf '[error] Container %s is %s, expected running\n' "${LDAP_CONTAINER}" "${container_state}" >&2
  exit 1
fi

if [[ -z "${LDAP_ADMIN_PASSWORD:-}" ]]; then
  LDAP_ADMIN_PASSWORD="$(
    docker_cmd exec "${LDAP_CONTAINER}" sh -c 'cat /run/secrets/ldap-admin-password' \
      | tr -d '\r\n'
  )"
fi

printf '== OpenLDAP bootstrap ==\n'
printf 'Container : %s\n' "${LDAP_CONTAINER}"
printf 'Base DN   : %s\n' "${LDAP_BASE_DN}"
printf 'LDIF      : %s\n' "${LDIF_FILE}"

printf 'Waiting for LDAP bind...\n'
for attempt in $(seq 1 30); do
  if docker_cmd exec "${LDAP_CONTAINER}" ldapsearch \
    -x \
    -H "${LDAP_URL}" \
    -D "${LDAP_ADMIN_DN}" \
    -w "${LDAP_ADMIN_PASSWORD}" \
    -b "${LDAP_BASE_DN}" \
    -s base dn >/dev/null 2>&1; then
    break
  fi

  if [[ "${attempt}" == "30" ]]; then
    printf '[error] LDAP is not ready or admin bind failed\n' >&2
    exit 1
  fi

  sleep 2
done

set +e
ldapadd_output="$(
  docker_cmd exec -i "${LDAP_CONTAINER}" ldapadd \
    -c \
    -x \
    -H "${LDAP_URL}" \
    -D "${LDAP_ADMIN_DN}" \
    -w "${LDAP_ADMIN_PASSWORD}" < "${LDIF_FILE}" 2>&1
)"
ldapadd_status=$?
set -e

printf '%s\n' "${ldapadd_output}"

if [[ "${ldapadd_status}" -ne 0 ]]; then
  unexpected_errors="$(
    printf '%s\n' "${ldapadd_output}" \
      | grep -E 'ldap_(add|modify):' \
      | grep -Ev 'Already exists|Type or value exists' || true
  )"

  if [[ -n "${unexpected_errors}" ]]; then
    printf '[error] LDAP bootstrap failed\n' >&2
    exit "${ldapadd_status}"
  fi
fi

printf '\nEntries currently visible under %s:\n' "${LDAP_BASE_DN}"
docker_cmd exec "${LDAP_CONTAINER}" ldapsearch \
  -LLL \
  -x \
  -H "${LDAP_URL}" \
  -D "${LDAP_ADMIN_DN}" \
  -w "${LDAP_ADMIN_PASSWORD}" \
  -b "${LDAP_BASE_DN}" \
  dn \
  | sed -n 's/^dn: /- /p'

printf '\nDone. Test users: alice/alice123, bob/bob123, admin-tp/admin123\n'
