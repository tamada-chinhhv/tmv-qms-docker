#!/bin/bash
# Runs via postgres entrypoint: executable .sh is executed; non-executable .sh is sourced (. file).
# No git +x required on Windows — keep LF line endings (.gitattributes).
set -euo pipefail

: "${QMS_MIGRATOR_PASSWORD:?QMS_MIGRATOR_PASSWORD is required}"
: "${QMS_APP_PASSWORD:?QMS_APP_PASSWORD is required}"

DB_NAME="${POSTGRES_DB:-qms_db}"

escape_sql_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

MIGRATOR_PW="$(escape_sql_literal "${QMS_MIGRATOR_PASSWORD}")"
APP_PW="$(escape_sql_literal "${QMS_APP_PASSWORD}")"

psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${DB_NAME}" <<-EOSQL
  CREATE EXTENSION IF NOT EXISTS pg_trgm;
EOSQL

psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "postgres" <<-EOSQL
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'qms_migrator') THEN
      CREATE ROLE qms_migrator LOGIN PASSWORD '${MIGRATOR_PW}';
    ELSE
      ALTER ROLE qms_migrator PASSWORD '${MIGRATOR_PW}';
    END IF;

    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'qms_app') THEN
      CREATE ROLE qms_app LOGIN PASSWORD '${APP_PW}';
    ELSE
      ALTER ROLE qms_app PASSWORD '${APP_PW}';
    END IF;
  END
  \$\$;

  ALTER DATABASE "${DB_NAME}" OWNER TO qms_migrator;
  REVOKE ALL ON DATABASE "${DB_NAME}" FROM PUBLIC;
  GRANT CONNECT ON DATABASE "${DB_NAME}" TO qms_app;
EOSQL

psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${DB_NAME}" <<-EOSQL
  REVOKE ALL ON SCHEMA public FROM PUBLIC;
  GRANT USAGE ON SCHEMA public TO qms_migrator;
  GRANT USAGE ON SCHEMA public TO qms_app;

  ALTER DEFAULT PRIVILEGES FOR ROLE qms_migrator IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO qms_app;
  ALTER DEFAULT PRIVILEGES FOR ROLE qms_migrator IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO qms_app;

  ALTER ROLE qms_app SET statement_timeout = '10s';
  ALTER ROLE qms_app SET lock_timeout = '5s';
  ALTER ROLE qms_app SET idle_in_transaction_session_timeout = '30s';

  -- Audit append-only: revoke UPDATE/DELETE on audit tables after migrations (runbook).
  -- TODO: ALTER TABLE incident_events ... REVOKE UPDATE, DELETE FROM qms_app;
  -- TODO: ALTER TABLE ncr_events ... REVOKE UPDATE, DELETE FROM qms_app;

EOSQL