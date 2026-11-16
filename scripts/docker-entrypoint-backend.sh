#!/bin/sh
set -eu

if [ -z "${MIGRATE_DATABASE_URL:-}" ]; then
  echo "MIGRATE_DATABASE_URL is required for prisma migrate deploy" >&2
  exit 1
fi

echo "==> Running prisma migrate deploy (migrator role)"
DATABASE_URL="${MIGRATE_DATABASE_URL}" npx prisma migrate deploy

if [ -f /app/scripts/ensure-system-admin.mjs ]; then
  echo "==> Ensuring system admin (idempotent)"
  node /app/scripts/ensure-system-admin.mjs
fi

unset MIGRATE_DATABASE_URL SYSTEM_ADMIN_PASSWORD

echo "==> Starting application"
exec node dist/main.js