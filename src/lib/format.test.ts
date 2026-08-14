import { describe, expect, it } from "vitest";

import {
  formatCurrency,
  formatMoney,
  formatPerGram,
  formatPercent,
  formatWeight,
  toNumber,
} from "./format";

describe("toNumber", () => {
  it("يحوّل سلاسل numeric القادمة من Postgres دون فقدان القيمة", () => {
    // Postgres يرسل numeric كسلسلة نصية حفاظاً على الدقة
    expect(toNumber("17.500000")).toBe(17.5);
    expect(toNumber("21000.0000")).toBe(21000);
  });

  it("يعامل القيم الفارغة كصفر بدل NaN", () => {
    expect(toNumber(null)).toBe(0);
    expect(toNumber(undefined)).toBe(0);
    expect(toNumber("")).toBe(0);
  });
});

describe("تنسيق المال", () => {
  it("يعرض خانتين عشريتين دائماً", () => {
    expect(formatMoney("21000")).toBe("21,000.00");
    expect(formatMoney(3250)).toBe("3,250.00");
  });

  it("يلحق رمز العملة في صيغة العملة", () => {
    expect(formatCurrency("12000")).toBe("12,000.00 ريال");
  });
});

describe("تنسيق الوزن", () => {
  it("يعرض الجرامات مع وحدتها", () => {
    expect(formatWeight("1200")).toBe("1,200 ج");
    expect(formatWeight("700.500")).toBe("700.5 ج");
  });

  it("يسقط الوحدة عند الطلب — للجداول الكثيفة", () => {
    expect(formatWeight("500", false)).toBe("500");
  });
});

describe("تنسيق سعر الجرام", () => {
  it("يحتفظ بدقة أعلى لأن كسور الجرام مؤثرة", () => {
    expect(formatPerGram("17.5")).toBe("17.50 ريال/ج");
    expect(formatPerGram("6.5")).toBe("6.50 ريال/ج");
  });
});

describe("تنسيق النسبة", () => {
  it("يحوّل الكسر العشري إلى نسبة مئوية", () => {
    expect(formatPercent(0.6)).toBe("60.0%");
    expect(formatPercent("0.405", 2)).toBe("40.50%");
  });
});
