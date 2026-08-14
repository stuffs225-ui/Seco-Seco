import { z } from "zod";

/** نتيجة موحّدة لكل Server Action يستهلكها `useActionState`. */
export type ActionState = { error: string | null; success?: string };

/**
 * رقم يصل من نموذج HTML كنص.
 *
 * يبقى نصاً بعد التحقق ولا يُحوَّل إلى `number`: تحويله يمر بـ double
 * فيفقد الدقة في المبالغ الكبيرة. Postgres يستقبله كـ numeric مباشرة.
 */
export const numericString = z
  .string()
  .trim()
  .min(1, "القيمة مطلوبة")
  .transform((raw) =>
    raw
      // الأرقام العربية والفارسية كما قد تُكتب من لوحة مفاتيح عربية
      .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660))
      .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
      .replace(/[,\s]/g, ""),
  )
  .refine((v) => /^\d+(\.\d+)?$/.test(v), "أدخل رقماً صحيحاً")
  .refine((v) => Number(v) > 0, "القيمة يجب أن تكون أكبر من صفر");

/** تاريخ اختياري: الحقل الفارغ يصبح null لا سلسلة فارغة. */
export const optionalDate = z
  .string()
  .trim()
  .transform((v) => (v === "" ? null : v))
  .nullable();
