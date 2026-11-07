#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_ADMIN_URL:?Defina DATABASE_ADMIN_URL con una cuenta administradora de PostgreSQL 18}"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for script in 01_schema.sql 02_functions.sql 03_security.sql; do
    echo "==> Aplicando ${script}"
    psql "$DATABASE_ADMIN_URL" -X -v ON_ERROR_STOP=1 -f "$BASE_DIR/sql/$script"
done
echo 'Instalación de AutoAudit completa. Configure su rol aa_ui y el archivo .env.'
