/**
 * التحقق من متغيرات البيئة عند بدء التشغيل.
 *
 * سبب وجود هذا الملف: الشيفرة كانت تكتب `process.env.X!`، وعلامة `!`
 * تُسكت TypeScript فقط. في وقت التشغيل تمرّ `undefined` إلى عميل Supabase
 * فينتج خطأ غامض لا يذكر أي متغير ينقص — وهو ما جعل خطأ تسمية بسيطاً
 * (`PUBLIC_` بدل `NEXT_PUBLIC_`) صعب التشخيص.
 *
 * الفحص هنا يقع وقت استيراد الوحدة، أي **أثناء البناء** لا بعد النشر.
 * هذا مقصود: متغيرات `NEXT_PUBLIC_*` تُحقن في حزمة المتصفح وقت البناء،
 * فغيابها حينها يعني تطبيقاً معطوباً دائماً مهما صُحّحت البيئة لاحقاً.
 * فشل البناء برسالة واضحة أفضل من نشر ناجح لا يعمل.
 */

/**
 * ⚠️ القيمة تُمرَّر لا الاسم.
 *
 * Next.js يستبدل `process.env.NEXT_PUBLIC_X` نصياً في حزمة المتصفح.
 * أي قراءة ديناميكية مثل `process.env[name]` لا تخضع لهذا الاستبدال
 * فتعود `undefined` في المتصفح دائماً — أي أن الحارس نفسه يصبح مصدر
 * العطل. لذلك يستقبل الاسم للرسالة فقط، والقيمة تُقرأ حرفياً عند النداء.
 */
function requireEnv(name: string, value: string | undefined): string {
  const trimmed = value?.trim() ?? "";

  if (trimmed === "") {
    throw new Error(
      `متغير البيئة ${name} غير معرَّف.\n\n` +
        `أضفه في Vercel → Settings → Environment Variables، أو في ملف ` +
        `.env.local للتطوير المحلي.\n\n` +
        `تنبيه على التسمية: البادئة NEXT_PUBLIC_ إلزامية وليست اختيارية. ` +
        `اسم مثل PUBLIC_SUPABASE_URL يصل الخادم لكنه يصل المتصفح كـ undefined، ` +
        `فيفشل تسجيل الدخول بلا رسالة واضحة.`,
    );
  }

  return trimmed;
}

/** يتحقق أيضاً من الشكل: متغير موجود بقيمة خاطئة يفشل بنفس الوضوح. */
function requireUrl(name: string, value: string | undefined): string {
  const url = requireEnv(name, value);

  if (!/^https?:\/\//.test(url)) {
    throw new Error(
      `متغير البيئة ${name} قيمته غير صالحة: "${url}".\n\n` +
        `يجب أن يكون عنواناً كاملاً يبدأ بـ https:// — مثل ` +
        `https://xxxxxxxx.supabase.co — تجده في Supabase → Settings → Data API.`,
    );
  }

  return url;
}

export const SUPABASE_URL = requireUrl(
  "NEXT_PUBLIC_SUPABASE_URL",
  process.env.NEXT_PUBLIC_SUPABASE_URL,
);

export const SUPABASE_ANON_KEY = requireEnv(
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
);

// تُصدَّر للاختبار وحده
export const __testing = { requireEnv, requireUrl };
