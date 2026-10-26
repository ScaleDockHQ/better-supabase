import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { Separator } from "@/components/ui/separator";
import { SidebarTrigger } from "@/components/ui/sidebar";
import { HelpSheet } from "@/features/inbox/components/help-sheet";
import { UnreadBadge } from "@/features/notifications/components/unread-badge";
import {
  ActiveOrganizationName,
  ActiveOrganizationNameSkeleton,
} from "@/features/organization/components/active-organization-name";
import { CommandSearch } from "@/features/search/components/command-search";

import { AppBreadcrumbs } from "./app-breadcrumbs";

/** Synchronous, so it is part of the static shell of every page. */
export function AppHeader() {
  const t = useExtracted("navigation");

  return (
    <header
      data-recipe="notification-bell"
      className="sticky top-0 z-10 flex h-14 shrink-0 items-center gap-2 border-b bg-background/80 px-4 backdrop-blur"
    >
      <SidebarTrigger className="-ml-1" aria-label={t("Toggle sidebar")} />
      <Separator orientation="vertical" className="mr-2 h-4" />
      <Suspense fallback={<ActiveOrganizationNameSkeleton />}>
        <AppBreadcrumbs
          organization={
            <Suspense fallback={<ActiveOrganizationNameSkeleton />}>
              <ActiveOrganizationName />
            </Suspense>
          }
        />
      </Suspense>
      <div className="ml-auto flex items-center gap-1">
        <CommandSearch />
        <HelpSheet />
        <UnreadBadge />
      </div>
    </header>
  );
}
