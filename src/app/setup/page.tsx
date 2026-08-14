import type { Metadata } from "next";

import { getAccessAccountEmail } from "@/lib/supabase/admin";

export const metadata: Metadata = { title: "تهيئة النظام" };

/**
 * صفحة التشخيص — تظهر فقط حين يتعذّر فتح النظام.
 *
 * لا تحل محل شاشة الدخول (أُلغيت): وظيفتها أن تقول ما الناقص بالضبط.
 * ثلاث حالات تبدو من الخارج «الموقع لا يعمل» بينما حلّ كل واحدة مختلف
 * تماماً، ورسالة واحدة تغطيها ترسل المالك إلى المكان الخطأ.
 *
 * بعد اكتمال التهيئة لا يراها أحد.
 */
export default async function SetupPage() {
  let reason: "no_key" | "schema" | "no_owner" | "other" = "other";
  let detail = "";

  try {
    const account = await getAccessAccountEmail();

    if (account.kind === "schema_missing") reason = "schema";
    else if (account.kind === "no_owner") reason = "no_owner";
    else if (account.kind === "error") {
      reason = "other";
      detail = account.message;
    } else if (account.kind === "ok") {
      // الحساب سليم، فالعطل في إنشاء الجلسة نفسها
      reason = "other";
      detail = "تعذّر إنشاء الجلسة رغم وجود حساب المالك.";
    }
  } catch (error) {
    // createAdminClient يرمي حين ينقص مفتاح الإدارة
    reason = "no_key";
    detail = error instanceof Error ? error.message : "";
  }

  const steps: Record<typeof reason, { title: string; body: React.ReactNode }> =
    {
      schema: {
        title: "قاعدة البيانات فارغة",
        body: (
          <>
            <p>الترحيلات لم تُطبَّق بعد، فلا توجد جداول في القاعدة.</p>
            <p className="mt-3">
              افتح <code className="num">docs/bootstrap.sql</code> من الريبو،
              عدّل السطور المعلَّمة في أعلاه (البريد والاسم)، والصقه في Supabase
              ← SQL Editor ← Run.
            </p>
          </>
        ),
      },
      no_owner: {
        title: "لا يوجد حساب مالك",
        body: (
          <>
            <p>
              الترحيلات مطبَّقة، لكن لا يوجد مستخدم بدور <code>owner</code> —
              والنظام يحتاجه ليعمل تحت هويته.
            </p>
            <p className="mt-3">
              أنشئ مستخدماً في Supabase ← Authentication ← Users (مع Auto
              Confirm)، ثم في SQL Editor:
            </p>
            <pre className="border-border bg-surface-muted mt-2 overflow-x-auto rounded-lg border p-3 text-xs">
              <code dir="ltr">{`update public.profiles
set role = 'owner'
where id = (select id from auth.users where email = 'بريدك');`}</code>
            </pre>
          </>
        ),
      },
      no_key: {
        title: "مفتاح الإدارة ناقص",
        body: (
          <>
            <p>
              متغير <code className="num">SUPABASE_SERVICE_ROLE_KEY</code> غير
              مضبوط. النظام يحتاجه لإنشاء الجلسة تلقائياً.
            </p>
            <p className="mt-3">
              أضفه في Vercel ← Settings ← Environment Variables{" "}
              <strong>بدون أي بادئة</strong>، ثم أعد النشر.
            </p>
          </>
        ),
      },
      other: {
        title: "تعذّر فتح النظام",
        body: <p>حدث خطأ أثناء تهيئة الجلسة.</p>,
      },
    };

  const step = steps[reason];

  return (
    <main className="flex min-h-dvh items-center justify-center p-6">
      <div className="w-full max-w-lg">
        <div className="mb-8 text-center">
          <h1 className="text-3xl font-bold tracking-tight">سيكو سيكو</h1>
          <p className="text-muted mt-2 text-sm">تهيئة النظام</p>
        </div>

        <div className="border-warning/40 bg-warning/5 rounded-xl border p-6">
          <h2 className="text-warning font-semibold">{step.title}</h2>
          <div className="text-muted mt-3 text-sm leading-relaxed">
            {step.body}
          </div>

          {detail ? (
            <p className="border-border text-muted mt-4 border-t pt-3 text-xs whitespace-pre-line">
              {detail}
            </p>
          ) : null}
        </div>

        <p className="text-muted mt-6 text-center text-xs">
          بعد اكتمال الخطوة أعلاه، حدّث الصفحة — يفتح النظام مباشرةً.
        </p>
      </div>
    </main>
  );
}
