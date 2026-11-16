#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${COMPOSE_ENV_FILE:-${ROOT_DIR}/.env}"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
cd "${ROOT_DIR}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Thieu file ${ENV_FILE}. Chay: cp .env.example .env va dien gia tri." >&2
  exit 1
fi

load_env() {
  if grep -q $'\r' "${ENV_FILE}" 2>/dev/null; then
    sed -i 's/\r$//' "${ENV_FILE}"
    echo "Da chuan hoa CRLF trong .env"
  fi
  # shellcheck disable=SC1090
  set -a && source "${ENV_FILE}" && set +a
}

compose() {
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

load_env

EDGE_CONF="${NGINX_EDGE_CONF:-nginx/qms.conf}"
case "${EDGE_CONF}" in
  */*) ;;
  *) EDGE_CONF="${ROOT_DIR}/${EDGE_CONF}" ;;
esac

if [[ "${EDGE_CONF}" != *http* ]]; then
  ssl_dir="${NGINX_SSL_DIR:-${ROOT_DIR}/nginx/ssl}"
  if [[ ! -f "${ssl_dir}/fullchain.pem" ]]; then
    echo "Thieu chung chi TLS: ${ssl_dir}/fullchain.pem" >&2
    echo "Xem README.md (muc tao cert dev) hoac dung qms.http.conf + host TLS." >&2
    exit 1
  fi
fi

echo "==> Keo image co so (postgres, redis, nginx)"
compose pull postgres redis nginx

echo "==> Khoi dong stack"
compose up -d

echo "==> Reload nginx (cap nhat upstream DNS)"
if docker ps --format '{{.Names}}' | grep -qx 'tmv-qms-nginx'; then
  docker exec tmv-qms-nginx nginx -t
  docker exec tmv-qms-nginx nginx -s reload
fi

echo "==> Trang thai dich vu"
compose ps