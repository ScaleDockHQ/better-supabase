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
  readonly "aria-label"?: string;
  readonly "aria-current"?: "page" | undefined;
  readonly children: ReactNode;
}

export function SiteLink({ href, children, ...props }: SiteLinkProps) {
  if (!isAppRoute(href)) {
    return (
      <a href={href} {...props}>
        {children}
      </a>
    );
  }

  return (
    <Link href={href} {...props}>
      {children}
    </Link>
  );
}
