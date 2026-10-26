import type { Metadata } from "next";

import { CompassIcon } from "lucide-react";
import Link from "next/link";

import { buttonVariants } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { geistMono, geistSans } from "@/lib/fonts";
import { cn } from "@/lib/utils";

import "./globals.css";

export const metadata: Metadata = {
  title: "Page not found · Acme Cloud",
  robots: { index: false },
};

/**
 * A URL outside every locale (for example `/api/unknown`, which the `[locale]`
 * segment reads as an unknown locale) skips the locale layout, so this renders
 * the whole document. It has no locale, so it links to both.
 */
export default function GlobalNotFound() {
  return (
    <html
      lang="en"
      className={cn(geistSans.variable, geistMono.variable)}
      data-testid="global-not-found"
    >
      <body className="min-h-svh bg-background font-sans text-foreground antialiased">
        <main className="flex min-h-svh items-center justify-center p-6">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <CompassIcon />
              </EmptyMedia>
              <EmptyTitle>Page not found</EmptyTitle>
              <EmptyDescription>
                This address doesn&apos;t exist. Pagina niet gevonden.
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent className="flex-row justify-center gap-2">
              <Link href="/en" className={buttonVariants({ size: "sm" })}>
                English
              </Link>
              <Link
                href="/nl"
                className={buttonVariants({ size: "sm", variant: "outline" })}
              >
                Nederlands
              </Link>
            </EmptyContent>
          </Empty>
        </main>
      </body>
    </html>
  );
}
