import { describe, expect, it } from "vitest";

import { __testing } from "./env";

const { requireEnv, requireUrl } = __testing;

describe("requireEnv", () => {
  it("يعيد القيمة الصالحة كما هي بعد إزالة الفراغات", () => {
    expect(requireEnv("X", "  قيمة  ")).toBe("قيمة");
  });

  it("يرمي خطأً يسمّي المتغير الناقص", () => {
    // الرسالة يجب أن تحمل الاسم؛ خطأ لا يذكر ما ينقص هو سبب وجود هذا الملف
    expect(() => requireEnv("NEXT_PUBLIC_SUPABASE_URL", undefined)).toThrow(
      /NEXT_PUBLIC_SUPABASE_URL/,
    );
  });

  it("يعامل السلسلة الفارغة كغياب", () => {
    // متغير مضاف في اللوحة بقيمة فارغة أسوأ من غيابه: يبدو موجوداً
    expect(() => requireEnv("X", "")).toThrow();
    expect(() => requireEnv("X", "   ")).toThrow();
  });

  it("ينبّه على بادئة NEXT_PUBLIC_ لأنها سبب العطل الشائع", () => {
    expect(() => requireEnv("X", undefined)).toThrow(/NEXT_PUBLIC_/);
  });
});

describe("requireUrl", () => {
  it("يقبل عنوان Supabase الصحيح", () => {
    expect(requireUrl("X", "https://abc.supabase.co")).toBe(
      "https://abc.supabase.co",
    );
  });

  it("يقبل http للتطوير المحلي", () => {
    expect(requireUrl("X", "http://127.0.0.1:54321")).toBe(
      "http://127.0.0.1:54321",
    );
  });

  it("يرفض قيمة ليست عنواناً", () => {
    // متغير موجود بقيمة خاطئة يجب أن يفشل بنفس وضوح الغائب
    expect(() => requireUrl("X", "abc.supabase.co")).toThrow(/غير صالحة/);
  });

  it("يرفض مفتاحاً وُضع في خانة العنوان بالخطأ", () => {
    expect(() => requireUrl("X", "eyJhbGciOiJIUzI1NiIs")).toThrow(/غير صالحة/);
  });
});
