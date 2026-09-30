import Link from "next/link";

import { LogoMark } from "@/components/site/logo";
import { SiteLink } from "@/components/site/site-link";
import { ThemeToggle } from "@/components/site/theme-toggle";
import { Button } from "@/components/ui/button";
import { navLinks, site } from "@/lib/site";

export function Navbar() {
  return (
    <header className="border-border bg-background/80 sticky top-0 z-20 w-full border-b backdrop-blur">
      <div className="mx-auto flex h-14 w-full max-w-6xl items-center justify-between gap-4 px-6 md:px-8">
        <div className="flex items-center gap-6">
          <Link
            href="/"
            className="flex items-center gap-2 text-sm font-semibold"
          >
            <LogoMark />
            {site.name}
          </Link>
          <nav aria-label="Main" className="hidden items-center gap-1 sm:flex">
            {navLinks.map((link) => (
              <SiteLink
                key={link.href}
                href={link.href}
                className="text-muted-foreground hover:text-foreground hover:bg-muted rounded-md px-3 py-1.5 text-sm"
              >
                {link.label}
              </SiteLink>
            ))}
          </nav>
        </div>
        <div className="flex items-center gap-1">
          <Button
            variant="ghost"
            size="sm"
            nativeButton={false}
            render={<a href={site.github} />}
          >
            GitHub
          </Button>
          <ThemeToggle />
          <Button
            size="sm"
            nativeButton={false}
            render={<a href={site.getStarted} />}
          >
            Get started
          </Button>
        </div>
      </div>
    </header>
  );
}
