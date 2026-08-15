import type { Metadata, Viewport } from "next";
import { IBM_Plex_Sans_Arabic } from "next/font/google";
import "./globals.css";

const arabic = IBM_Plex_Sans_Arabic({
  subsets: ["arabic", "latin"],
  weight: ["300", "400", "500", "600", "700"],
  variable: "--font-arabic",
  display: "swap",
});

export const metadata: Metadata = {
  title: {
    default: "سيكو سيكو",
    template: "%s · سيكو سيكو",
  },
  description:
    "نظام إدارة الشراء بالوزن والتوزيع على التصريف والتحصيل والربحية والشراكة",
};

export const viewport: Viewport = {
  // تصدير viewport مخصص يُسقط قيم Next.js الافتراضية (width/initialScale)
  // ما لم تُذكر صراحة — إسقاطها يكسر التحجيم على الجوال بصمت، وهذا
  // النظام لا يُستخدم إلا من الجوال.
  width: "device-width",
  initialScale: 1,
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#0b1120" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ar" dir="rtl" className={arabic.variable}>
      <body className="bg-background text-foreground min-h-dvh antialiased">
        {children}
      </body>
    </html>
  );
}
