"use client";

import type { Route } from "next";
import type { ReactNode } from "react";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { cn } from "@/lib/utils";

/** A sidebar link that marks itself current when its route is open. */
export function CatalogLink<T extends string>({
  href,
  children,
  className,
}: {
  href: Route<T>;
  children: ReactNode;
  className?: string;
}) {
  const current = usePathname() === href;

  return (
    <Link
      href={href}
      aria-current={current ? "page" : undefined}
      className={cn(
        "flex min-h-8 items-center gap-2 rounded-md px-2 text-sm text-muted-foreground transition-colors hover:bg-muted hover:text-foreground",
        "aria-[current=page]:bg-muted aria-[current=page]:font-medium aria-[current=page]:text-foreground",
        className,
      )}
    >
      {children}
    </Link>
  );
}
