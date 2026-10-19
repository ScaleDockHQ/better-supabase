import Link from "next/link";
import { siGithub } from "simple-icons";

import { BrandLogo } from "@/components/site/brand-icons";
import { LinkButton } from "@/components/site/link-button";
import { LogoMark } from "@/components/site/logo";
import { MobileNav } from "@/components/site/mobile-nav";
import { NavLink } from "@/components/site/nav-link";
import { navLinks, site } from "@/lib/site";

export function Navbar() {
  return (
    <header className="sticky top-0 z-20 w-full border-b border-border bg-background/80 backdrop-blur">
      <div className="mx-auto flex h-14 w-full max-w-7xl items-center justify-between gap-4 px-6 md:px-8">
        <div className="flex items-center gap-6">
          <Link
            href="/"
            className="flex h-10 items-center gap-2 text-sm font-semibold"
          >
            <LogoMark />
            {site.name}
          </Link>
          <nav aria-label="Main" className="hidden items-center gap-1 sm:flex">
            {navLinks.map((link) => (
              <NavLink
                key={link.href}
                href={link.href}
                className="rounded-md px-3 py-1.5 text-sm text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
              >
                {link.label}
              </NavLink>
            ))}
          </nav>
        </div>
        <div className="flex items-center gap-1">
          <div className="hidden items-center gap-1 sm:flex">
            <LinkButton variant="ghost" size="sm" href="/contact">
              Contact
            </LinkButton>
            <LinkButton
              variant="ghost"
              size="icon"
              href={site.github}
              aria-label="GitHub repository"
            >
              <BrandLogo mark={siGithub} className="size-4" />
            </LinkButton>
          </div>
          <LinkButton size="sm" href={site.getStarted}>
            Get started
          </LinkButton>
          <MobileNav />
        </div>
      </div>
    </header>
  );
}
