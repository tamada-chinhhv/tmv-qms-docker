#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${COMPOSE_ENV_FILE:-${ROOT_DIR}/.env}"

if [[ $# -lt 1 ]]; then
  echo "Cach dung: $0 <backup-bundle.tar[.age|.gpg]>" >&2
  exit 1
fi

INPUT="$1"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Thieu file ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a && source "${ENV_FILE}" && set +a

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${ROOT_DIR}/docker-compose.yml")

PLAIN="${WORKDIR}/bundle.tar"
case "${INPUT}" in
  *.age)
    age -d -o "${PLAIN}" "${INPUT}"
    ;;
  *.gpg)
    gpg --decrypt -o "${PLAIN}" "${INPUT}"
    ;;
  *)
    cp "${INPUT}" "${PLAIN}"
    ;;
esac

tar -xf "${PLAIN}" -C "${WORKDIR}"

DB_DUMP="$(find "${WORKDIR}" -name 'qms_db_*.dump' | head -n 1)"
STORAGE_TAR="$(find "${WORKDIR}" -name 'qms_storage_*.tar' | head -n 1)"

if [[ -z "${DB_DUMP}" || -z "${STORAGE_TAR}" ]]; then
  echo "Bundle khong hop le: can qms_db_*.dump va qms_storage_*.tar" >&2
  exit 1
fi

echo "==> Dung tang ung dung"
"${COMPOSE[@]}" stop qms-fe qms-be nginx

echo "==> Khoi phuc co so du lieu"
cat "${DB_DUMP}" | "${COMPOSE[@]}" exec -T postgres \
  pg_restore -U "${POSTGRES_SUPERUSER:-postgres}" -d "${POSTGRES_DB:-qms_db}" --clean --if-exists

echo "==> Khoi phuc storage"
"${COMPOSE[@]}" run --rm --no-deps -T --entrypoint sh qms-be -c 'rm -rf /data/storage/*'
cat "${STORAGE_TAR}" | "${COMPOSE[@]}" run --rm --no-deps -T --entrypoint sh qms-be -c 'tar -C /data/storage -xf -'

echo "==> Khoi dong stack"
"${COMPOSE[@]}" up -d

echo "==> Luu y: job doi chieu storage/DB (sha256) chua tu dong (Phase 0)."