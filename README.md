# Frappe HRMS v16 Docker Image

Builds a custom Frappe HRMS v16 image for Sealos deployments.

The image follows the official `frappe/frappe_docker` layered build pattern and uses the official Frappe `build:version-16` base for runtime so Node.js is available for Socket.IO:

- `frappe/frappe` branch `version-16`
- `frappe/erpnext` branch `version-16`
- `frappe/hrms` branch `version-16`

Published image:

```text
ghcr.io/yangchuansheng/frappe-hrms:v16
```

## Why this repo exists

The upstream `ghcr.io/frappe/hrms` workflow currently builds the HRMS image from `version-15`. For HRMS v16 + PostgreSQL, the Sealos template needs a real v16 image with Python 3.14-compatible Frappe/ERPNext/HRMS baked in.

## Manual build

```bash
docker build \
  --no-cache \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-16 \
  --secret=id=apps_json,src=apps.json \
  --tag=ghcr.io/yangchuansheng/frappe-hrms:v16 \
  --file=Containerfile .
```

## Trigger build

Use GitHub Actions → **Build Frappe HRMS v16 image** → **Run workflow**.
