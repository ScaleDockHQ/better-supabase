"use client";

import type { ReactNode } from "react";

import { useExtracted } from "next-intl";
import { Fragment } from "react";

import type { AppHref } from "@/i18n/navigation";

import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import { useTabLabel } from "@/features/settings/components/settings-nav-links";
import { settingsTabs } from "@/features/settings/settings-tabs";
import { Link, usePathname } from "@/i18n/navigation";

import { activeNavId, navItems } from "../nav-items";
import { useNavLabel } from "./side-nav";

interface Crumb {
  readonly label: string;
  readonly href?: AppHref;
}

function sectionOf<T extends { readonly href: AppHref }>(
  items: readonly T[],
  pathname: string,
): T | undefined {
  return items
    .filter(
      (item) => pathname === item.href || pathname.startsWith(`${item.href}/`),
    )
    .toSorted((a, b) => b.href.length - a.href.length)[0];
}

/**
 * The trail from the menus: the section a path belongs to, and "Details" for a
 * page below it. A client component, so the static shell renders it from the
 * URL without waiting for the session.
 */
export function AppBreadcrumbs({ organization }: { organization: ReactNode }) {
  const t = useExtracted("navigation");
  const navLabel = useNavLabel();
  const tabLabel = useTabLabel();
  const pathname = usePathname();
  const crumbs: Crumb[] = [];

  const tab = pathname.startsWith("/settings/")
    ? sectionOf(settingsTabs, pathname)
    : undefined;

  const item = tab
    ? undefined
    : navItems.find((entry) => entry.id === activeNavId(pathname));

  const section = tab
    ? { label: tabLabel(tab.id), href: tab.href }
    : item
      ? { label: navLabel(item.id), href: item.href }
      : undefined;

  if (tab) {
    crumbs.push({ label: t("Settings"), href: "/settings/profile" });
  }

  if (section) {
    crumbs.push(pathname === section.href ? { label: section.label } : section);

    if (pathname !== section.href) {
      crumbs.push({ label: t("Details") });
    }
  }

  return (
    <Breadcrumb className="min-w-0">
      <BreadcrumbList className="flex-nowrap">
        <BreadcrumbItem className="min-w-0 font-medium text-foreground">
          {organization}
        </BreadcrumbItem>
        {crumbs.map((crumb) => (
          <Fragment key={crumb.label}>
            <BreadcrumbSeparator className="max-md:hidden" />
            <BreadcrumbItem className="max-md:hidden">
              {crumb.href ? (
                <BreadcrumbLink render={<Link href={crumb.href} />}>
                  {crumb.label}
                </BreadcrumbLink>
              ) : (
                <BreadcrumbPage>{crumb.label}</BreadcrumbPage>
              )}
            </BreadcrumbItem>
          </Fragment>
        ))}
      </BreadcrumbList>
    </Breadcrumb>
  );
}
