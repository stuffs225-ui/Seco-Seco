"use client";

import { createBrowserClient } from "@supabase/ssr";

import { SUPABASE_ANON_KEY, SUPABASE_URL } from "@/lib/env";
import type { Database } from "@/types/database";

/**
 * عميل Supabase للمتصفح — للمصادقة والاشتراكات الحية فقط.
 * كل كتابة على بيانات النشاط تمر عبر Server Action تنادي RPC.
 */
export function createClient() {
  return createBrowserClient<Database>(SUPABASE_URL, SUPABASE_ANON_KEY);
}
