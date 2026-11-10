import type { Metadata, Viewport } from "next";

import { ThemeProvider } from "@wrksz/themes/next";
import { NextIntlClientProvider, useLocale } from "next-intl";
import { getExtracted } from "next-intl/server";

import { LazyToaster } from "@/components/ui/lazy-toaster";
import { ServiceWorkerRegistrar } from "@/features/offline/components/service-worker-registrar";
import { routing } from "@/i18n/routing";
import { geistMono, geistSans } from "@/lib/fonts";
import { cn } from "@/lib/utils";

import "../globals.css";
import { Providers } from "../providers";

// Every route group keeps its app shell static: a default <Link> loads only
// prerendered output, and anything that reads the session or a route token
// renders behind its own <Suspense> boundary (Next.js 16.4, ADR 0481).
export const ensureStatic = "shell";

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata(): Promise<Metadata> {
  const t = await getExtracted("app");

  return {
    title: { default: "Acme Cloud", template: "%s · Acme Cloud" },
    description: t("A multi-tenant SaaS example built on better-supabase."),
    // `app/manifest.ts` adds the manifest link; iOS reads these instead.
    appleWebApp: { capable: true, title: "Acme", statusBarStyle: "default" },
    icons: { apple: "/icons/apple-touch-icon.png" },
  };
}

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#0a0a0a" },
  ],
};

/**
 * The locale comes from the `[locale]` root param, so it is known at build time
 * and the shell stays static. The theme provider never reads the theme cookie
 * on the server: its inline script sets the class before paint.
 */
export default function LocaleLayout({ children }: LayoutProps<"/[locale]">) {
  const locale = useLocale();

  return (
    <html
      lang={locale}
      suppressHydrationWarning
      className={cn(geistSans.variable, geistMono.variable)}
    >
      <body className="min-h-svh bg-background font-sans text-foreground antialiased">
        <ThemeProvider storage="cookie" themes={["light", "dark"]}>
          <NextIntlClientProvider messages={null}>
            <Providers>{children}</Providers>
            <LazyToaster />
            <ServiceWorkerRegistrar />
          </NextIntlClientProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
