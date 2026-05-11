#!/usr/bin/env bash
set -euo pipefail

cd /home/frappe/frappe-bench
mkdir -p sites logs
printf '%s\n' '{"socketio_port": 9000}' > sites/common_site_config.json
ls -1 apps > sites/apps.txt

cat > Procfile <<'EOF'
web: env/bin/gunicorn --chdir=/home/frappe/frappe-bench/sites --bind=0.0.0.0:8000 --threads=2 --workers=1 --worker-class=gthread --worker-tmp-dir=/dev/shm --timeout=120 --preload frappe.app:application
socketio: node apps/frappe/socketio.js
schedule: bench schedule
worker_short: bench worker --queue short,default
worker_long: bench worker --queue long,default,short
EOF

if [ -d /home/frappe/frappe-bench/sites/assets ]; then
  rm -rf /home/frappe/frappe-bench/assets
  cp -r /home/frappe/frappe-bench/sites/assets /home/frappe/frappe-bench/assets
  rm -rf /home/frappe/frappe-bench/sites/assets
fi
