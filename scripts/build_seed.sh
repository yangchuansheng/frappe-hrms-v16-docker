#!/usr/bin/env bash
set -euo pipefail

cd /home/frappe/frappe-bench
export SEED_SITE="${SEED_SITE:-hrms.localhost}"
export SEED_ADMIN_PASSWORD="${SEED_ADMIN_PASSWORD:-admin}"
export PGDATA="/tmp/hrms-seed-pgdata"
export PGHOST="127.0.0.1"
export PGPORT="5432"
export PGUSER="postgres"

PG_BIN_DIR=$(find /usr/lib/postgresql -maxdepth 1 -mindepth 1 -type d | sort -V | tail -1)/bin
export PATH="${PG_BIN_DIR}:${PATH}"

rm -rf "${PGDATA}"
initdb -D "${PGDATA}" -U postgres --auth=trust --no-locale
pg_ctl -D "${PGDATA}" -o "-c listen_addresses='127.0.0.1' -p ${PGPORT}" -w start
cleanup() {
  pg_ctl -D "${PGDATA}" -m fast -w stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

python /opt/frappe/scripts/patch_hrms_postgres.py

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
from pathlib import Path
print(json.loads(Path('sites/hrms.localhost/site_config.json').read_text())['db_name'])
PY
)
pg_dump -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" --format=plain --no-owner --no-privileges "${DB_NAME}" | gzip -9 > /opt/frappe/seed/hrms-site.sql.gz
printf '%s\n' "${DB_NAME}" > /opt/frappe/seed/source-db-name.txt
rm -rf "sites/${SEED_SITE}"
