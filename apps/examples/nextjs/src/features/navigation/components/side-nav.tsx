"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { can } from "@/features/user/user-permissions";
import { useSession } from "@/lib/hooks";

import { navItems } from "../nav-items";

export function SideNav() {
  const session = useSession();
  const pathname = usePathname();
  const visible = navItems.filter(
    (item) => !item.requires || can(session, item.requires),
  );
  return (
    <nav aria-label="Main">
      <ul>
        {visible.map((item) => (
          <li key={item.href}>
            <Link
              href={item.href}
              aria-current={pathname === item.href ? "page" : undefined}
            >
              {item.label}
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}

export function SideNavSkeleton() {
  return (
    <nav aria-label="Main" aria-busy="true">
      <ul>
        {Array.from({ length: 5 }, (_, index) => (
          <li key={index} className="skeleton" />
        ))}
      </ul>
    </nav>
  );
}
