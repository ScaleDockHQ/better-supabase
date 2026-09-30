import type { Metadata } from "next";

import { ThemeProvider } from "@/components/theme-provider";
import { geistMono, inter } from "@/lib/fonts";
import { site } from "@/lib/site";
import { cn } from "@/lib/utils";

import NotFound from "./not-found";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: `Page not found | ${site.name}`,
  description: site.tagline,
};

/** URLs that match no route skip the root layout, so this renders the whole document. */
export default function GlobalNotFound() {
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
          <main className="flex flex-1 flex-col">
            <NotFound />
          </main>
        </ThemeProvider>
      </body>
    </html>
  );
}
