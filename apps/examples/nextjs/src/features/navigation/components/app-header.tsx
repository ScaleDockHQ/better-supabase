import { useExtracted } from "next-intl";

import { Separator } from "@/components/ui/separator";
import { SidebarTrigger } from "@/components/ui/sidebar";
import { UnreadBadge } from "@/features/inbox/components/unread-badge";

/** Synchronous, so it is part of the static shell of every page. */
export function AppHeader() {
  const t = useExtracted("navigation");
  return (
    <header className="bg-background/80 sticky top-0 z-10 flex h-14 shrink-0 items-center gap-2 border-b px-4 backdrop-blur">
      <SidebarTrigger className="-ml-1" aria-label={t("Toggle sidebar")} />
      <Separator orientation="vertical" className="mr-2 h-4" />
      <span className="text-muted-foreground text-sm font-medium">
        Acme Cloud
      </span>
      <div className="ml-auto flex items-center gap-1">
        <UnreadBadge />
      </div>
    </header>
  );
}
