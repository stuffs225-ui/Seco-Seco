import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/** المسارات المتاحة بدون تسجيل دخول. */
const PUBLIC_PATHS = ["/login", "/auth"];

/**
 * يجدّد جلسة Supabase على كل طلب ويعيد توجيه غير المسجلين.
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

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
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
    },
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname } = request.nextUrl;
  const isPublic = PUBLIC_PATHS.some(
    (path) => pathname === path || pathname.startsWith(`${path}/`),
  );

  if (!user && !isPublic) {
    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = "/login";
    loginUrl.search = "";
    // نحفظ الوجهة الأصلية ليعود إليها المستخدم بعد الدخول.
    loginUrl.searchParams.set("next", pathname);
    return NextResponse.redirect(loginUrl);
  }

  if (user && pathname === "/login") {
    const homeUrl = request.nextUrl.clone();
    homeUrl.pathname = "/dashboard";
    homeUrl.search = "";
    return NextResponse.redirect(homeUrl);
  }

  return response;
}
