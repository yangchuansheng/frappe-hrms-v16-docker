#!/bin/bash
set -e

ASSETS_PATH="/home/frappe/frappe-bench/sites/assets"
BAKED_PATH="/home/frappe/frappe-bench/assets"

if [ -d "$BAKED_PATH" ]; then
  echo "Linking fresh assets to volume..."
  rm -rf "$ASSETS_PATH"
  mkdir -p "$(dirname "$ASSETS_PATH")"
  ln -s "$BAKED_PATH" "$ASSETS_PATH"
fi

exec "$@"
