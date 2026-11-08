import type { ReactNode } from "react";

import { useExtracted } from "next-intl";

import { Separator } from "@/components/ui/separator";
import { SidebarTrigger } from "@/components/ui/sidebar";
import { HelpSheetLazy } from "@/features/inbox/components/help-sheet-lazy";
import { UnreadBadge } from "@/features/notifications/components/unread-badge";
import { CommandSearchLazy } from "@/features/search/components/command-search-lazy";

/**
 * Synchronous, so it is part of the static shell of every page. The layout
 * places the boundary around `breadcrumbs`, the one part that reads the
 * session.
 */
export function AppHeader({ breadcrumbs }: { breadcrumbs: ReactNode }) {
  const t = useExtracted("navigation");

  return (
    <header
      data-recipe="notification-bell"
      className="sticky top-0 z-10 flex h-14 shrink-0 items-center gap-2 border-b bg-background/80 px-4 backdrop-blur"
    >
      <SidebarTrigger className="-ml-1" aria-label={t("Toggle sidebar")} />
      <Separator orientation="vertical" className="mr-2 h-4" />
      {breadcrumbs}
      <div className="ml-auto flex items-center gap-1">
        <CommandSearchLazy />
        <HelpSheetLazy />
        <UnreadBadge />
      </div>
    </header>
  );
}
