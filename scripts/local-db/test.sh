#!/usr/bin/env bash
#
# يشغّل اختبارات pgTAP على قاعدة محلية مبنية من الصفر.
#
# نفس ملفات الاختبار التي يشغّلها `supabase test db` في CI — لا توجد
# نسخة ثانية من الاختبارات، فلا يمكن أن تفترق النتيجتان.
#
# الاستخدام:
#   scripts/local-db/test.sh
#
set -euo pipefail

DB_NAME="seco_seco_test"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"${REPO_ROOT}/scripts/local-db/setup.sh" "${DB_NAME}" > /dev/null

sudo -u postgres psql -v ON_ERROR_STOP=1 --quiet -d "${DB_NAME}" \
  -c "create extension if not exists pgtap;"

echo "▸ تشغيل اختبارات pgTAP"
sudo -u postgres pg_prove --ext .sql -d "${DB_NAME}" \
  "${REPO_ROOT}"/supabase/tests/*.sql
