import type { Metadata } from "next";

import { requireUser } from "@/lib/auth/dal";
import { createClient } from "@/lib/supabase/server";
import { formatDateTime } from "@/lib/format";
import { ROLE_LABELS, type AppSetting, type Profile } from "@/types/schema";

export const metadata: Metadata = { title: "الإعدادات" };

/**
 * شرح القيم المخزَّنة بلغة العمل.
 *
 * الإعدادات تُخزَّن كرموز تقنية (`on_sale`) لأن قواعد الأعمال في قاعدة
 * البيانات تقارنها؛ المستخدم يجب أن يرى معناها لا رمزها.
 */
const VALUE_LABELS: Record<string, string> = {
  on_sale: "عند تسجيل التصريف الفعلي",
  on_collection: "عند تحصيل النقد",
  per_expense_flag: "بمفتاح اختياري لكل مصروف",
  always: "دائماً وإجبارياً",
  never: "لا تُرسمل — مصروف تشغيلي",
  deal_price_per_gram: "بسعر الجرام في الصفقة",
  manual_value: "بقيمة يحددها المستخدم",
  true: "نعم",
  false: "لا",
};

function describeValue(value: unknown): string {
  const raw = typeof value === "string" ? value : JSON.stringify(value);
  return VALUE_LABELS[raw] ?? raw;
}

export default async function SettingsPage() {
  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: settings }, { data: profile }] = await Promise.all([
    supabase
      .from("app_settings")
      .select("key, value, description, updated_at")
      .order("key")
      .returns<AppSetting[]>(),
    supabase
      .from("profiles")
      .select("id, full_name, role, is_active, created_at, updated_at")
      .eq("id", user.id)
      .single<Profile>(),
  ]);

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold">الإعدادات</h1>
        <p className="text-muted mt-1 text-sm">
          القرارات المحاسبية والتشغيلية التي تحكم حسابات النظام
        </p>
      </div>

      <section className="space-y-3">
        <h2 className="text-lg font-semibold">حسابي</h2>
        <div className="border-border bg-surface rounded-xl border p-4">
          <dl className="grid gap-4 sm:grid-cols-3">
            <div>
              <dt className="text-muted text-xs">الاسم</dt>
              <dd className="mt-1 text-sm font-medium">
                {profile?.full_name || "—"}
              </dd>
            </div>
            <div>
              <dt className="text-muted text-xs">البريد الإلكتروني</dt>
              <dd className="num mt-1 text-sm font-medium">{user.email}</dd>
            </div>
            <div>
              <dt className="text-muted text-xs">الدور</dt>
              <dd className="mt-1 text-sm font-medium">
                {profile ? ROLE_LABELS[profile.role] : "—"}
              </dd>
            </div>
          </dl>
        </div>
      </section>

      <section className="space-y-3">
        <h2 className="text-lg font-semibold">قواعد الحساب</h2>
        <p className="text-muted text-sm">
          هذه القيم تُقرأ من قاعدة البيانات وتحكم حساب التكلفة والربح
          والاسترداد. تغييرها يؤثر على الحركات الجديدة فقط ولا يعيد حساب الفترات
          المقفلة، ويُسجَّل كل تغيير في سجل التدقيق.
        </p>

        <div className="border-border bg-surface overflow-hidden rounded-xl border">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-surface-muted text-muted">
                <tr>
                  <th className="px-4 py-2.5 text-start font-medium">
                    الإعداد
                  </th>
                  <th className="px-4 py-2.5 text-start font-medium">
                    القيمة المعتمدة
                  </th>
                  <th className="px-4 py-2.5 text-start font-medium">
                    آخر تحديث
                  </th>
                </tr>
              </thead>
              <tbody className="divide-border divide-y">
                {(settings ?? []).map((setting) => (
                  <tr key={setting.key}>
                    <td className="px-4 py-3">
                      <div className="font-medium">{setting.description}</div>
                      <div className="num text-muted mt-0.5 text-xs">
                        {setting.key}
                      </div>
                    </td>
                    <td className="px-4 py-3 font-medium">
                      {describeValue(setting.value)}
                    </td>
                    <td className="num text-muted px-4 py-3 text-xs">
                      {formatDateTime(setting.updated_at)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <p className="text-muted text-xs">
          تعديل الإعدادات من الواجهة يُضاف في مرحلة لاحقة؛ حتى ذلك الحين يغيّرها
          المالك مباشرةً في قاعدة البيانات مع بقاء أثر التغيير في سجل التدقيق.
        </p>
      </section>
    </div>
  );
}
