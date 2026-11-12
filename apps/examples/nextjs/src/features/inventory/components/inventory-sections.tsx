"use client";

import { useExtracted } from "next-intl";

import { buttonVariants } from "@/components/ui/button";
import { Link, usePathname } from "@/i18n/navigation";

/** Links between the three views of the stock ledger. */
export function InventorySections() {
  const t = useExtracted("inventory");
  const pathname = usePathname();

  const sections = [
    { href: "/shop/inventory", label: t("Stock levels") },
    { href: "/shop/inventory/movements", label: t("Movements") },
    { href: "/shop/inventory/lots", label: t("Lots") },
  ] as const;

  return (
    <nav aria-label={t("Stock ledger")} className="flex flex-wrap gap-2">
      {sections.map((section) => (
        <Link
          key={section.href}
          href={section.href}
          aria-current={pathname === section.href ? "page" : undefined}
          className={buttonVariants({
            variant: pathname === section.href ? "secondary" : "ghost",
            size: "sm",
          })}
        >
          {section.label}
        </Link>
      ))}
    </nav>
  );
}
