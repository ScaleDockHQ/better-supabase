"use client";

import type { ReactNode } from "react";

import { usePathname } from "next/navigation";

import { SiteLink } from "@/components/site/site-link";
import { cn } from "@/lib/utils";

/** True when `pathname` is `href` or a page under it. */
function isActivePath(pathname: string, href: string): boolean {
  return pathname === href || pathname.startsWith(`${href}/`);
}

/** A navbar link that marks the current section with `aria-current="page"`. */
export function NavLink({
  href,
  className,
  children,
}: {
  readonly href: string;
  readonly className?: string;
  readonly children: ReactNode;
}) {
  const pathname = usePathname();
  const active = isActivePath(pathname, href);

  return (
    <SiteLink
      href={href}
      aria-current={active ? "page" : undefined}
      className={cn(className, active && "bg-muted text-foreground")}
    >
      {children}
    </SiteLink>
  );
}
