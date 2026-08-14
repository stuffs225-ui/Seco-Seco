import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { SUPABASE_ANON_KEY, SUPABASE_URL } from "@/lib/env";

import { generateOwnerSessionToken, isOpenAccessEnabled } from "./admin";

/** المسارات المتاحة بدون تسجيل دخول. */
const PUBLIC_PATHS = ["/login", "/auth"];

/**
 * يجدّد جلسة Supabase على كل طلب، ويفتح النظام تلقائياً عند تفعيل ذلك.
 *
 * لماذا getUser() لا getSession(): الأولى تتحقق من التوكن لدى خادم Supabase،
 * والثانية تقرأ الكوكي كما هو دون تحقق — فيمكن تزويرها.
 *
 * توثيق Next.js ينبّه إلى أن الـ proxy يعمل على كل مسار بما فيها المسارات
 * المسبقة التحميل، فلا يُوضع فيه منطق تفويض ثقيل. ما نفعله هنا هو الحد الأدنى:
 * تدوير التوكن (لا غنى عنه لأن مكونات الخادم لا تكتب كوكيز) وتوجيه بسيط.
 * صلاحيات الأدوار تُفرض في قاعدة البيانات عبر RLS وفي `requireUser()`.
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

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname } = request.nextUrl;
  const isPublic = PUBLIC_PATHS.some(
    (path) => pathname === path || pathname.startsWith(`${path}/`),
  );

  if (user) {
    // لا داعي لإبقاء شاشة الدخول متاحة لمن دخل أصلاً
    if (pathname === "/login") {
      const homeUrl = request.nextUrl.clone();
      homeUrl.pathname = "/dashboard";
      homeUrl.search = "";
      return NextResponse.redirect(homeUrl);
    }
    return response;
  }

  /*
    لا جلسة. هل النظام مفتوح؟

    الفتح التلقائي يقع هنا لا في مكوّن خادم، لأن إنشاء الجلسة يكتب كوكيز
    والمكوّنات لا تستطيع ذلك. ويقع مرة واحدة فقط: بعد نجاحه تصبح الكوكيز
    موجودة فلا يتكرر مع كل طلب.
  */
  if (await isOpenAccessEnabled()) {
    const token = await generateOwnerSessionToken();

    if (token.ok) {
      const { error } = await supabase.auth.verifyOtp({
        token_hash: token.tokenHash,
        type: "email",
      });

      if (!error) {
        // الجلسة أُنشئت وكُتبت الكوكيز في response عبر setAll
        if (pathname === "/login") {
          const homeUrl = request.nextUrl.clone();
          homeUrl.pathname = "/dashboard";
          homeUrl.search = "";
          return NextResponse.redirect(homeUrl);
        }
        return response;
      }
    }

    /*
      الفتح مفعّل لكن تعذّر إنشاء الجلسة — مفتاح إداري ناقص أو لا مالك
      أو ترحيلات غير مطبَّقة. نسقط إلى شاشة الدخول بدل ترك المستخدم أمام
      صفحة تفشل بلا تفسير؛ الشاشة تعرض سبباً مفهوماً.
    */
  }

  if (!isPublic) {
    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = "/login";
    loginUrl.search = "";
    // نحفظ الوجهة الأصلية ليعود إليها المستخدم بعد الدخول.
    loginUrl.searchParams.set("next", pathname);
    return NextResponse.redirect(loginUrl);
  }

  return response;
}
