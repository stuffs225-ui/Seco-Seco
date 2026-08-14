import path from "node:path";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "node",
    include: ["src/**/*.test.ts", "src/**/*.test.tsx", "tests/**/*.test.ts"],
    /*
      قيم وهمية صالحة الشكل.

      `src/lib/env.ts` يتحقق من المتغيرات وقت الاستيراد — وهو المقصود
      حتى يفشل البناء لا النشر. لكن ذلك يعني أن مجرد استيراده في اختبار
      يحتاج قيماً موجودة، فنوفّرها هنا. الاختبارات نفسها تفحص دوال
      التحقق مباشرةً لا هذه القيم.
    */
    env: {
      NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
      NEXT_PUBLIC_SUPABASE_ANON_KEY: "test-anon-key",
    },
  },
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
});
