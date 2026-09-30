import type { ComponentProps } from "react";

import Link from "next/link";

/** True for URLs this app does not render: /docs is a separate deployment. */
function isExternal(href: string): boolean {
  return (
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
  if (isExternal(href)) {
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
