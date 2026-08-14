#!/usr/bin/env bash
#
# يبني قاعدة بيانات محلية من الصفر: المحاكاة ثم كل الترحيلات ثم البذور.
#
# هذا مسار احتياطي لبيئات لا تستطيع تشغيل Docker. المسار المعتمد هو:
#   npm run db:reset   (يستخدم supabase start)
#
# الاستخدام:
#   scripts/local-db/setup.sh [اسم_القاعدة]
#
set -euo pipefail

DB_NAME="${1:-seco_seco_dev}"
PSQL=(sudo -u postgres psql -v ON_ERROR_STOP=1 --quiet)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "▸ إعادة إنشاء القاعدة: ${DB_NAME}"
"${PSQL[@]}" -d postgres -c "drop database if exists ${DB_NAME};"
"${PSQL[@]}" -d postgres -c "create database ${DB_NAME};"

echo "▸ محاكاة بيئة Supabase"
"${PSQL[@]}" -d "${DB_NAME}" -f "${REPO_ROOT}/scripts/local-db/shim.sql"

echo "▸ تطبيق الترحيلات"
for migration in "${REPO_ROOT}"/supabase/migrations/*.sql; do
  [ -e "${migration}" ] || continue
  echo "  · $(basename "${migration}")"
  "${PSQL[@]}" -d "${DB_NAME}" -f "${migration}"
done

if [ -f "${REPO_ROOT}/supabase/seed.sql" ]; then
  echo "▸ تطبيق البذور"
  "${PSQL[@]}" -d "${DB_NAME}" -f "${REPO_ROOT}/supabase/seed.sql"
fi

echo "✓ القاعدة ${DB_NAME} جاهزة"
