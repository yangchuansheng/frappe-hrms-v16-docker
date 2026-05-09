#!/usr/bin/env bash
set -euo pipefail

cd /home/frappe/frappe-bench
export SEED_SITE="${SEED_SITE:-hrms.localhost}"
export SEED_ADMIN_PASSWORD="${SEED_ADMIN_PASSWORD:-admin}"
export PGDATA="/tmp/hrms-seed-pgdata"
export PGHOST="127.0.0.1"
export PGPORT="5432"
export PGUSER="postgres"
export REDIS_PORT="${REDIS_PORT:-11311}"
export REDIS_DIR="/tmp/hrms-seed-redis"

PG_BIN_DIR=$(find /usr/lib/postgresql -path '*/bin/initdb' -type f | sed 's#/initdb$##' | sort -V | tail -1)
if [ -z "${PG_BIN_DIR}" ]; then
  echo "PostgreSQL server binaries were not found" >&2
  exit 1
fi
export PATH="${PG_BIN_DIR}:${PATH}"

rm -rf "${PGDATA}"
rm -rf "${REDIS_DIR}"
initdb -D "${PGDATA}" -U postgres --auth=trust --encoding=UTF8 --locale=C.UTF-8
pg_ctl -D "${PGDATA}" -o "-c listen_addresses='127.0.0.1' -c unix_socket_directories=/tmp -p ${PGPORT}" -w start
mkdir -p "${REDIS_DIR}"
redis-server --save "" --appendonly no --port "${REDIS_PORT}" --dir "${REDIS_DIR}" --daemonize yes
cleanup() {
  redis-cli -p "${REDIS_PORT}" shutdown nosave >/dev/null 2>&1 || true
  pg_ctl -D "${PGDATA}" -m fast -w stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

python /opt/frappe/scripts/patch_hrms_postgres.py
bench set-config -g redis_cache "redis://127.0.0.1:${REDIS_PORT}"
bench set-config -g redis_queue "redis://127.0.0.1:${REDIS_PORT}"
bench set-config -g redis_socketio "redis://127.0.0.1:${REDIS_PORT}"

bench new-site "${SEED_SITE}" \
  --force \
  --db-type=postgres \
  --db-host="${PGHOST}" \
  --db-port="${PGPORT}" \
  --db-root-username="${PGUSER}" \
  --db-root-password="postgres" \
  --admin-password="${SEED_ADMIN_PASSWORD}" \
  --install-app=hrms

bench --site "${SEED_SITE}" enable-scheduler
bench --site "${SEED_SITE}" clear-cache

mkdir -p /opt/frappe/seed
DB_NAME=$(python - <<'PY'
import json
import os
from pathlib import Path
seed_site = os.environ.get("SEED_SITE", "hrms.localhost")
print(json.loads(Path("sites", seed_site, "site_config.json").read_text())["db_name"])
PY
)
pg_dump -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" --format=plain --no-owner --no-privileges "${DB_NAME}" | gzip -9 > /opt/frappe/seed/hrms-site.sql.gz
printf '%s\n' "${DB_NAME}" > /opt/frappe/seed/source-db-name.txt
rm -rf "sites/${SEED_SITE}"
