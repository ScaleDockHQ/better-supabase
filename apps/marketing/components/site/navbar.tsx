import Link from "next/link";

import { LinkButton } from "@/components/site/link-button";
import { LogoMark } from "@/components/site/logo";
import { SiteLink } from "@/components/site/site-link";
import { ThemeToggle } from "@/components/site/theme-toggle";
import { buttonVariants } from "@/components/ui/button-variants";
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
          <LinkButton variant="ghost" size="sm" href={site.github}>
            GitHub
          </LinkButton>
          <ThemeToggle
            className={buttonVariants({ variant: "ghost", size: "icon" })}
          />
          <LinkButton size="sm" href={site.getStarted}>
            Get started
          </LinkButton>
        </div>
      </div>
    </header>
  );
}
