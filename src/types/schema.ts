/**
 * أنواع الصفوف التي يقرأها التطبيق.
 *
 * تُكتب يدوياً بمحاذاة ملفات الترحيل حتى يتوفر التوليد الآلي. المرجع
 * الوحيد للمخطط هو `supabase/migrations/` — إن اختلف هذا الملف عنها،
 * فالخطأ هنا.
 *
 * ملاحظة على الأرقام: كل حقل numeric في Postgres يصل إلى JavaScript
 * كسلسلة نصية، لا كرقم. هذا مقصود — تحويله إلى number يفقد الدقة في
 * المبالغ الكبيرة. لذلك أنواع المال والوزن هنا `string`، ولا تُحوَّل
 * إلا عند العرض عبر دوال `src/lib/format.ts`.
 */

/** الأدوار الخمسة (§12). */
export type UserRole =
  "owner" | "operations" | "collections" | "finance" | "auditor";

export const ROLE_LABELS: Record<UserRole, string> = {
  owner: "المالك / المدير",
  operations: "مسؤول العمليات",
  collections: "مسؤول التحصيل",
  finance: "مسؤول مالي",
  auditor: "مدقق / مشاهد",
};

export type Profile = {
  id: string;
  full_name: string;
  role: UserRole;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type AppSetting = {
  key: string;
  value: unknown;
  description: string;
  updated_at: string;
};

/** مبلغ مالي — numeric(18,4) يصل كسلسلة نصية. */
export type MoneyAmount = string;

/** وزن بالجرام — numeric(14,3) يصل كسلسلة نصية. */
export type WeightGrams = string;

/** تكلفة أو سعر الجرام — numeric(18,6) يصل كسلسلة نصية. */
export type RatePerGram = string;
