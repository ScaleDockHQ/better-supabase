import type { Route } from "next";
import type { ComponentProps } from "react";

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

export function SiteLink({
  href,
  children,
  ...props
}: ComponentProps<"a"> & { href: string }) {
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
