"use client";

import { createBrowserClient } from "@supabase/ssr";

import type { Database } from "@/types/database";

/**
 * عميل Supabase للمتصفح — للمصادقة والاشتراكات الحية فقط.
 * كل كتابة على بيانات النشاط تمر عبر Server Action تنادي RPC.
 */
export function createClient() {
  return createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
