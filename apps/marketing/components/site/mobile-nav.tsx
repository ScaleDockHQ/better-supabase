"use client";

import { MenuIcon } from "lucide-react";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { siGithub } from "simple-icons";

import { BrandLogo } from "@/components/site/brand-icons";
import { LinkButton } from "@/components/site/link-button";
import { NavLink } from "@/components/site/nav-link";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetFooter,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { navLinks, site } from "@/lib/site";

/**
 * The main nav below `sm`, in a sheet. It closes when a link is tapped and when
 * the route changes some other way, such as the back button.
 */
export function MobileNav() {
  const pathname = usePathname();
  const [openOn, setOpenOn] = useState<string | null>(null);
  const open = openOn === pathname;

  return (
    <Sheet
      open={open}
      onOpenChange={(next) => {
        setOpenOn(next ? pathname : null);
      }}
    >
      <SheetTrigger
        render={
          <Button
            variant="ghost"
            size="icon"
            className="sm:hidden"
            aria-label="Open menu"
          >
            <MenuIcon aria-hidden="true" />
          </Button>
        }
      />
      <SheetContent side="right">
        <SheetHeader>
          <SheetTitle>Menu</SheetTitle>
        </SheetHeader>
        {/* oxlint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions -- delegated from the links inside, which handle keys themselves */}
        <div
          className="flex min-h-0 flex-1 flex-col gap-6 overflow-y-auto"
          onClick={(event) => {
            if (event.target instanceof Element && event.target.closest("a")) {
              setOpenOn(null);
            }
          }}
        >
          <nav aria-label="Main" className="flex flex-col gap-1 px-4">
            {navLinks.map((link) => (
              <NavLink
                key={link.href}
                href={link.href}
                className="flex min-h-10 items-center rounded-md px-3 text-sm text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
              >
                {link.label}
              </NavLink>
            ))}
          </nav>
          <SheetFooter>
            <LinkButton variant="outline" size="lg" href="/contact">
              Contact
            </LinkButton>
            <LinkButton variant="outline" size="lg" href={site.github}>
              <BrandLogo mark={siGithub} className="size-4" />
              GitHub
            </LinkButton>
            <LinkButton variant="outline" size="lg" href={site.signIn}>
              Sign in
            </LinkButton>
            <LinkButton size="lg" href={site.getStarted}>
              Get started
            </LinkButton>
          </SheetFooter>
        </div>
      </SheetContent>
    </Sheet>
  );
}
