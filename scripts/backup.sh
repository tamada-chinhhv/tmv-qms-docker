#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${COMPOSE_ENV_FILE:-${ROOT_DIR}/.env}"
BACKUP_DIR="${BACKUP_DIR:-${ROOT_DIR}/backups}"
RETENTION="${BACKUP_RETENTION_DAYS:-14}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "${BACKUP_DIR}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Thieu file ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a && source "${ENV_FILE}" && set +a

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${ROOT_DIR}/docker-compose.yml")

DB_DUMP="${BACKUP_DIR}/qms_db_${TS}.dump"
STORAGE_TAR="${BACKUP_DIR}/qms_storage_${TS}.tar"
BUNDLE="${BACKUP_DIR}/qms_backup_${TS}.tar"

echo "==> pg_dump (dinh dang tuy chinh)"
"${COMPOSE[@]}" exec -T postgres \
  pg_dump -U "${POSTGRES_SUPERUSER:-postgres}" -d "${POSTGRES_DB:-qms_db}" -Fc > "${DB_DUMP}"

echo "==> Dong goi volume storage (tu container qms-be)"
"${COMPOSE[@]}" exec -T qms-be sh -c 'tar -C /data/storage -cf - .' > "${STORAGE_TAR}"

tar -cf "${BUNDLE}" -C "${BACKUP_DIR}" "$(basename "${DB_DUMP}")" "$(basename "${STORAGE_TAR}")"
rm -f "${DB_DUMP}" "${STORAGE_TAR}"

ENCRYPTED="${BUNDLE}"
if [[ -n "${AGE_RECIPIENT:-}" ]] && command -v age >/dev/null 2>&1; then
  ENCRYPTED="${BUNDLE}.age"
  age -r "${AGE_RECIPIENT}" -o "${ENCRYPTED}" "${BUNDLE}"
  rm -f "${BUNDLE}"
  echo "==> Da ma hoa bang age: ${ENCRYPTED}"
elif [[ -n "${GPG_RECIPIENT:-}" ]] && command -v gpg >/dev/null 2>&1; then
  ENCRYPTED="${BUNDLE}.gpg"
  gpg --batch --yes -r "${GPG_RECIPIENT}" -o "${ENCRYPTED}" -e "${BUNDLE}"
  rm -f "${BUNDLE}"
  echo "==> Da ma hoa bang gpg: ${ENCRYPTED}"
else
  echo "==> Ban backup (chua ma hoa): ${ENCRYPTED}"
  echo "Dat AGE_RECIPIENT hoac GPG_RECIPIENT trong .env de ma hoa."
fi

find "${BACKUP_DIR}" -maxdepth 1 -type f \( -name 'qms_backup_*.tar' -o -name 'qms_backup_*.tar.age' -o -name 'qms_backup_*.tar.gpg' \) -mtime "+${RETENTION}" -print -delete

echo "==> Hoan tat backup"