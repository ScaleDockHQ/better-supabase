"use client";

import { ChevronsUpDownIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { lazy } from "react";

import { LazyOnIntent } from "@/components/lazy-on-intent";
import { SidebarMenuButton } from "@/components/ui/sidebar";

import type { OrganizationSummary } from "../organization-queries";

const OrganizationSwitcherMenu = lazy(() =>
  import("./organization-switcher-menu").then((mod) => ({
    default: mod.OrganizationSwitcherMenu,
  })),
);

/**
 * The organization menu's closed trigger. The menu, its organizations hook and
 * the create dialog load on the first hover, focus or click.
 */
export function OrganizationSwitcherLazy({
  initial,
  activeId,
}: {
  initial: readonly OrganizationSummary[];
  activeId: string | null;
}) {
  const t = useExtracted("organization");
  const active = initial.find((organization) => organization.id === activeId);

  return (
    <LazyOnIntent
      renderTrigger={(handlers) => (
        <SidebarMenuButton
          size="lg"
          aria-label={t("Switch organization")}
          aria-haspopup="menu"
          {...handlers}
        >
          <div className="flex aspect-square size-8 items-center justify-center rounded-lg bg-sidebar-primary text-sm font-semibold text-sidebar-primary-foreground">
            {(active?.name ?? "?").slice(0, 1).toUpperCase()}
          </div>
          <div className="grid flex-1 text-left text-sm leading-tight">
            <span
              className="truncate font-medium"
              data-testid="organization-name"
            >
              {active?.name ?? t("No organization")}
            </span>
            <span className="truncate text-xs text-muted-foreground capitalize">
              {active ? active.plan : t("Create one to start")}
            </span>
          </div>
          <ChevronsUpDownIcon className="ml-auto" />
        </SidebarMenuButton>
      )}
    >
      <OrganizationSwitcherMenu initial={initial} activeId={activeId} />
    </LazyOnIntent>
  );
}
