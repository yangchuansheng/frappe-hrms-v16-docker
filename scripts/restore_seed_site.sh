#!/usr/bin/env bash
set -euo pipefail

cd /home/frappe/frappe-bench

SITE_NAME="${SITE_NAME:-hrms.localhost}"
READY_MARKER="sites/${SITE_NAME}/.sealos-hrms-ready"
SEED_SQL="${SEED_SQL:-/opt/frappe/seed/hrms-site.sql.gz}"
REDIS_URL="redis://${REDIS_USERNAME}:${REDIS_PASSWORD}@${REDIS_HOST}:${REDIS_PORT}"

wait_for_tcp() {
  local host="$1"
  local port="$2"
  local label="$3"
  for _ in $(seq 1 120); do
    if (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
      echo "${label} is reachable"
      return 0
    fi
    echo "Waiting for ${label} (${host}:${port})..."
    sleep 3
  done
  echo "Timed out waiting for ${label}" >&2
  return 1
}

sql_literal() {
  python - "$1" <<'PY'
import sys
print("'" + sys.argv[1].replace("'", "''") + "'")
PY
}

sql_ident() {
  python - "$1" <<'PY'
import sys
print('"' + sys.argv[1].replace('"', '""') + '"')
PY
}

psql_root() {
  PGPASSWORD="${DB_ROOT_PASSWORD}" psql -v ON_ERROR_STOP=1 -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_ROOT_USER}" -d postgres "$@"
}

wait_for_tcp "${DB_HOST}" "${DB_PORT}" "database"
wait_for_tcp "${REDIS_HOST}" "${REDIS_PORT}" "redis"

mkdir -p sites logs
printf '%s\n' '{"socketio_port": 9000}' > sites/common_site_config.json

if [ ! -d apps/frappe ] || [ ! -d apps/erpnext ] || [ ! -d apps/hrms ]; then
  echo "Frappe, ERPNext and HRMS must be baked into the image" >&2
  exit 1
fi

if [ -d /home/frappe/frappe-bench/assets ]; then
  rm -rf sites/assets
  ln -s /home/frappe/frappe-bench/assets sites/assets
fi

ls -1 apps > sites/apps.txt

bench set-config -g db_type postgres
bench set-config -g db_host "${DB_HOST}"
bench set-config -gp db_port "${DB_PORT}"
bench set-config -g redis_cache "${REDIS_URL}"
bench set-config -g redis_queue "${REDIS_URL}"
bench set-config -g redis_socketio "${REDIS_URL}"
bench set-config -gp socketio_port "9000"
bench set-config -g host_name "${APP_URL}"

if [ -d "sites/${SITE_NAME}" ] && [ ! -f "${READY_MARKER}" ]; then
  echo "Removing incomplete Frappe HR site ${SITE_NAME}..."
  bench drop-site "${SITE_NAME}" --force --no-backup || true
  rm -rf "sites/${SITE_NAME}"
fi

if [ ! -d "sites/${SITE_NAME}" ]; then
  if [ ! -f "${SEED_SQL}" ]; then
    echo "Seed dump not found: ${SEED_SQL}" >&2
    exit 1
  fi

  echo "Restoring seeded Frappe HR PostgreSQL site ${SITE_NAME}..."
  DB_NAME="${FRAPPE_DB_NAME:-_$(python - <<'PY'
import secrets
print(secrets.token_hex(8))
PY
)}"
  DB_USER="${FRAPPE_DB_USER:-${DB_NAME}}"
  DB_PASSWORD="${FRAPPE_DB_PASSWORD:-$(python - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)}"

  DB_NAME_IDENT=$(sql_ident "${DB_NAME}")
  DB_USER_IDENT=$(sql_ident "${DB_USER}")
  DB_NAME_LITERAL=$(sql_literal "${DB_NAME}")
  DB_USER_LITERAL=$(sql_literal "${DB_USER}")
  DB_PASSWORD_LITERAL=$(sql_literal "${DB_PASSWORD}")

  cat > /tmp/create-frappe-db.sql <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ${DB_USER_LITERAL}) THEN
    CREATE ROLE ${DB_USER_IDENT} LOGIN PASSWORD ${DB_PASSWORD_LITERAL};
  ELSE
    ALTER ROLE ${DB_USER_IDENT} LOGIN PASSWORD ${DB_PASSWORD_LITERAL};
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${DB_NAME_IDENT} OWNER ${DB_USER_IDENT}'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = ${DB_NAME_LITERAL})\gexec
ALTER DATABASE ${DB_NAME_IDENT} OWNER TO ${DB_USER_IDENT};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME_IDENT} TO ${DB_USER_IDENT};
SQL
  psql_root -f /tmp/create-frappe-db.sql

  gzip -dc "${SEED_SQL}" | PGPASSWORD="${DB_PASSWORD}" psql -v ON_ERROR_STOP=1 -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}"

  mkdir -p "sites/${SITE_NAME}"
  cat > "sites/${SITE_NAME}/site_config.json" <<JSON
{
 "db_type": "postgres",
 "db_host": "${DB_HOST}",
 "db_port": ${DB_PORT},
 "db_name": "${DB_NAME}",
 "db_user": "${DB_USER}",
 "db_password": "${DB_PASSWORD}"
}
JSON

  bench --site "${SITE_NAME}" set-admin-password "${ADMIN_PASSWORD}"
  bench --site "${SITE_NAME}" enable-scheduler
  bench --site "${SITE_NAME}" clear-cache
  touch "${READY_MARKER}"
else
  echo "Existing Frappe HR site found, skipping seed restore"
fi

bench --site "${SITE_NAME}" set-config db_port "6432"
bench set-config -gp db_port "6432"
bench use "${SITE_NAME}" || true
