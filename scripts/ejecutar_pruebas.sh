#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_ADMIN_URL:?Defina DATABASE_ADMIN_URL con una cuenta administradora de PostgreSQL 18}"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
psql "$DATABASE_ADMIN_URL" -X -v ON_ERROR_STOP=1 -f "$BASE_DIR/tests/01_pruebas_funcionales.sql"
