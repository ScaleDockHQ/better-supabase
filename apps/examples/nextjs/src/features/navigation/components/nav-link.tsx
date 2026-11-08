"use client";

import type { ReactNode } from "react";

import type { AppHref } from "@/i18n/navigation";

import { SidebarMenuButton } from "@/components/ui/sidebar";
import { Link, usePathname } from "@/i18n/navigation";

import type { NavId } from "../nav-items";

import { activeNavId } from "../nav-items";

/**
 * One menu entry. The server renders the icon and the label; this leaf only
 * reads the pathname to mark the current page.
 */
export function NavLink({
  id,
  href,
  label,
  children,
}: {
  id: NavId;
  href: AppHref;
  label: string;
  children: ReactNode;
}) {
  const active = activeNavId(usePathname()) === id;

  return (
    <SidebarMenuButton
      isActive={active}
      tooltip={label}
      render={<Link href={href} aria-current={active ? "page" : undefined} />}
    >
      {children}
      <span>{label}</span>
    </SidebarMenuButton>
  );
}
