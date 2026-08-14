/**
 * أنواع قاعدة البيانات.
 *
 * الهدف أن يُولَّد هذا الملف آلياً من المخطط:
 *   npm run db:start && npm run db:reset && npm run db:types
 *
 * حتى ذلك الحين يبقى `Database` نوعاً متساهلاً، والاستعلامات تُوصَّف
 * بأنواع صريحة في `src/types/schema.ts`. لا تعتمد على هذا الملف كمرجع
 * للمخطط — المرجع هو ملفات الترحيل في `supabase/migrations/`.
 */
export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Database = any;
