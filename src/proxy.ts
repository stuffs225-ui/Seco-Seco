import type { NextRequest } from "next/server";

import { updateSession } from "@/lib/supabase/proxy";

/**
 * يعمل قبل تصيير أي مسار (كان اسمه middleware قبل Next.js 16).
 *
 * مهمته الوحيدة: تجديد جلسة Supabase وإعادة توجيه غير المسجلين — فحص متفائل.
 * التحقق الحقيقي من الصلاحيات يقع في طبقتين أعمق: `requireUser()` في
 * كل صفحة وServer Action، وسياسات RLS في قاعدة البيانات.
 */
export async function proxy(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  matcher: [
    /*
     * كل المسارات عدا الملفات الساكنة —
     * الجلسة يجب أن تتجدد قبل أي صفحة تقرأ بيانات، وإلا انتهت صلاحيتها بصمت
     * لأن مكونات الخادم لا تستطيع كتابة الكوكيز.
     */
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|woff2?)$).*)",
  ],
};
