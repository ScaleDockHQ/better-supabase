import type { Metadata } from "next";

import { RootProvider } from "fumadocs-ui/provider/next";
import Link from "next/link";

import { env } from "@/env";

import "./global.css";

export const metadata: Metadata = {
  metadataBase: new URL(env.NEXT_PUBLIC_SITE_URL),
  title: "Page not found | better-supabase",
  description: "That docs page does not exist.",
  robots: { index: false },
};

/** Unknown docs URLs skip the root layout, so this renders the whole document. */
export default function GlobalNotFound() {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="flex min-h-screen flex-col">
        <RootProvider search={{ enabled: false }}>
          <main className="mx-auto flex w-full max-w-lg flex-1 flex-col items-center justify-center gap-4 px-6 py-24 text-center">
            <h1 className="text-3xl font-semibold">Page not found</h1>
            <p className="text-sm leading-6 text-fd-muted-foreground">
              That docs page does not exist. It may have moved; the
              documentation index lists every page.
            </p>
            <div className="flex gap-3 text-sm">
              {/* Typed routes list the optional catch-all as `/docs/${string}` only, not `/docs` itself. */}
              <Link
                href={{ pathname: "/docs" }}
                className="rounded-md bg-fd-primary px-3 py-2 font-medium text-fd-primary-foreground"
              >
                Documentation
              </Link>
              {/* oxlint-disable-next-line react-doctor/nextjs-no-a-element -- llms.txt is a route handler that returns text, not a page */}
              <a
                href="/llms.txt"
                className="rounded-md border px-3 py-2 font-medium"
              >
                Page index (llms.txt)
              </a>
            </div>
          </main>
        </RootProvider>
      </body>
    </html>
  );
}
