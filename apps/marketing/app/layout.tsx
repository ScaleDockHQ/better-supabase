import type { Metadata } from "next";
import type { ReactNode } from "react";

import { Analytics } from "@vercel/analytics/next";
import { SpeedInsights } from "@vercel/speed-insights/next";

import { SiteFooter } from "@/components/site/footer";
import { Navbar } from "@/components/site/navbar";
import { ThemeHotkey } from "@/components/site/theme-hotkey";
import { ThemeProvider } from "@/components/theme-provider";
import { geistMono, inter } from "@/lib/fonts";
import { site } from "@/lib/site";
import { cn } from "@/lib/utils";

import "./globals.css";

// Every page renders at build time; a request-time read fails the build.
export const ensureStatic = "navigation";

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: {
    default: `${site.name}: the typed layer for Supabase`,
    template: `%s | ${site.name}`,
  },
  description: site.tagline,
  openGraph: {
    title: site.name,
    description: site.tagline,
    siteName: site.name,
    type: "website",
  },
  twitter: { card: "summary_large_image" },
};

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={cn(
        inter.variable,
        geistMono.variable,
        "font-sans antialiased",
      )}
    >
      <body className="flex min-h-svh flex-col">
        <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
          <a
            href="#main"
            className="sr-only z-50 rounded-md bg-background px-3 py-2 text-sm font-medium ring-2 ring-ring focus:not-sr-only focus:fixed focus:top-3 focus:left-3"
          >
            Skip to content
          </a>
          <ThemeHotkey />
          <Navbar />
          <main
            id="main"
            tabIndex={-1}
            className="flex flex-1 flex-col outline-none"
          >
            {children}
          </main>
          <SiteFooter />
        </ThemeProvider>
        <Analytics />
        <SpeedInsights />
      </body>
    </html>
  );
}
