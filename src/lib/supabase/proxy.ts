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

  if (user) return response;

  // ── لا جلسة: ننشئ جلسة المالك ────────────────────────────────────────

  const token = await generateOwnerSessionToken();

  if (token.ok) {
    const { error } = await supabase.auth.verifyOtp({
      token_hash: token.tokenHash,
      type: "email",
    });

    if (!error) return response;
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
