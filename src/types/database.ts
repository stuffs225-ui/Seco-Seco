/**
 * أنواع قاعدة البيانات — مولَّدة آلياً.
 *
 * لإعادة التوليد بعد أي ترحيل جديد:
 *   npm run db:start   (مرة واحدة)
 *   npm run db:reset
 *   npm run db:types
 *
 * لا تحرر هذا الملف يدوياً — أي تعديل يُفقد عند التوليد التالي.
 * الملف الحالي هيكل مبدئي حتى تُنشأ الترحيلات في المرحلة M1.
 */
export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  public: {
    Tables: Record<string, never>;
    Views: Record<string, never>;
    Functions: Record<string, never>;
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
