import type { Route } from "next";
import type { ReactNode } from "react";

import Link from "next/link";

/** False for URLs this app does not render: /docs is a separate deployment. */
function isAppRoute(href: string): href is Route {
  return !(
    href === "/docs" ||
    href.startsWith("/docs/") ||
    href.startsWith("http") ||
    href.startsWith("mailto:")
  );
}

interface SiteLinkProps {
  readonly href: string;
  readonly className?: string;
  readonly children: ReactNode;
}

export function SiteLink({ href, className, children }: SiteLinkProps) {
  if (!isAppRoute(href)) {
    return (
      <a href={href} className={className}>
        {children}
      </a>
    );
  }
  return (
    <Link href={href} className={className}>
      {children}
    </Link>
  );
}
