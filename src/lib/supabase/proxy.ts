import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { SUPABASE_ANON_KEY, SUPABASE_URL } from "@/lib/env";

import { generateOwnerSessionToken } from "./admin";

/**
 * يفتح النظام مباشرةً بلا شاشة دخول.
 *
 * ⚠️ أي شخص يعرف الرابط يدخل بصلاحية المالك: يرى تكلفة الشراء والأرباح
 * وأرصدة الموزعين، ويعدّل ويحذف. قرار المالك، وهذا موضعه في الشيفرة.
 *
 * لماذا بقيت الجلسة رغم إلغاء الدخول: كل سياسات RLS وفحوص الصلاحيات
 * وسجل التدقيق مبنية على auth.uid(). بدون جلسة تعود current_role() فارغة
 * فتُرجع has_permission() كاذباً، ولا يعمل شيء — لا قراءة ولا كتابة.
 * فالمُلغى هو الشاشة لا الجلسة: تُنشأ تلقائياً هنا عند أول طلب.
 *
 * تقع هنا لا في مكوّن خادم لأن إنشاء الجلسة يكتب كوكيز والمكوّنات لا
 * تستطيع ذلك. ومرة واحدة فقط: بعد نجاحها تصبح الكوكيز موجودة فلا تتكرر.
 */
/**
 * يُضاف على الطلب الداخلي المُمرَّر لشجرة React، لا على رد المتصفح —
 * الفرق جوهري: `response.headers` يصل العميل، بينما هذا يصل `headers()`
 * داخل مكوّنات الخادم عبر `NextResponse.next({ request: { headers } })`.
 *
 * `dal.ts` يثق به لتفادي نداء `getUser()` ثانٍ عبر الشبكة لكل صفحة —
 * موثوق لأن هذا الموضع الوحيد الذي يضبطه، ويستبدل أي قيمة قد يرسلها
 * العميل لنفس الاسم دون شرط، فلا يمكن تزويره.
 */
const VERIFIED_HEADER = "x-seco-verified";

function withVerifiedHeader(
  request: NextRequest,
  cookiesFrom: NextResponse,
): NextResponse {
  const headers = new Headers(request.headers);
  headers.set(VERIFIED_HEADER, "1");

  const response = NextResponse.next({ request: { headers } });

  // أي كوكيز تجدّدت أثناء التحقق (تجديد توكن) يجب أن تصل المتصفح أيضاً
  cookiesFrom.cookies
    .getAll()
    .forEach((cookie) => response.cookies.set(cookie));

  return response;
}

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) =>
          request.cookies.set(name, value),
        );
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options),
        );
      },
    },
  });

  /*
    getUser() لا getSession(): الأولى تتحقق من التوكن لدى خادم Supabase
    والثانية تقرأ الكوكي كما هو دون تحقق.
  */
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user) return withVerifiedHeader(request, response);

  // ── لا جلسة: ننشئ جلسة المالك ────────────────────────────────────────

  const token = await generateOwnerSessionToken();

  if (token.ok) {
    const { error } = await supabase.auth.verifyOtp({
      token_hash: token.tokenHash,
      type: "email",
    });

    if (!error) return withVerifiedHeader(request, response);
  }

  /*
    تعذّر إنشاء الجلسة — النظام غير مهيَّأ بعد.

    الأسباب الممكنة: الترحيلات لم تُطبَّق، أو لا يوجد حساب مالك، أو مفتاح
    الإدارة ناقص. صفحة /setup تشخّص أيّها بالضبط، لأن «الصفحة لا تعمل»
    وحدها لا تفيد أحداً.
  */
  if (request.nextUrl.pathname !== "/setup") {
    const setupUrl = request.nextUrl.clone();
    setupUrl.pathname = "/setup";
    setupUrl.search = "";
    return NextResponse.rewrite(setupUrl);
  }

  return response;
}
