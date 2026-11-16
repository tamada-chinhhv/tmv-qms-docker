#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${COMPOSE_ENV_FILE:-${ROOT_DIR}/.env}"
BACKUP_DIR="${BACKUP_DIR:-${ROOT_DIR}/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
RETENTION_WEEKS="${BACKUP_RETENTION_WEEKS:-8}"
OFFSITE_DIR="${BACKUP_OFFSITE_DIR:-}"
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

if [[ -n "${OFFSITE_DIR}" ]]; then
  mkdir -p "${OFFSITE_DIR}"
  cp -p "${ENCRYPTED}" "${OFFSITE_DIR}/"
  echo "==> Da sao chep offsite (tuy chon): ${OFFSITE_DIR}/$(basename "${ENCRYPTED}")"
fi

NOW_EPOCH="$(date -u +%s)"
WEEKLY_MAX_SECONDS=$((RETENTION_WEEKS * 7 * 86400))
DAILY_MAX_SECONDS=$((RETENTION_DAYS * 86400))

while IFS= read -r -d '' backup_file; do
  base_name="$(basename "${backup_file}")"
  if [[ ! "${base_name}" =~ ^qms_backup_([0-9]{8})T ]]; then
    continue
  fi
  ymd="${BASH_REMATCH[1]}"
  file_epoch="$(date -u -d "${ymd:0:4}-${ymd:4:2}-${ymd:6:2}" +%s 2>/dev/null || date -u -j -f "%Y%m%d" "${ymd}" +%s 2>/dev/null || echo 0)"
  if [[ "${file_epoch}" -eq 0 ]]; then
    continue
  fi
  age_seconds=$((NOW_EPOCH - file_epoch))
  if (( age_seconds <= DAILY_MAX_SECONDS )); then
    continue
  fi
  dow="$(date -u -d "@${file_epoch}" +%u 2>/dev/null || date -u -r "${file_epoch}" +%u 2>/dev/null || echo 0)"
  if [[ "${dow}" == "7" ]] && (( age_seconds <= WEEKLY_MAX_SECONDS )); then
    continue
  fi
  echo "Xoa ban cu: ${backup_file}"
  rm -f "${backup_file}"
done < <(find "${BACKUP_DIR}" -maxdepth 1 -type f \( -name 'qms_backup_*.tar' -o -name 'qms_backup_*.tar.age' -o -name 'qms_backup_*.tar.gpg' \) -print0)

echo "==> Hoan tat backup"