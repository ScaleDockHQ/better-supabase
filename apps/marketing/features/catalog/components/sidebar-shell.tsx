import type { ReactNode } from "react";

import { CatalogSheet } from "./catalog-sheet";
import { SidebarScroll } from "./sidebar-scroll";

/**
 * A section layout with a sticky sidebar on large screens and the same nav in a
 * sheet on small ones. The layout stays mounted, so the sidebar keeps its
 * scroll position while the pages under it change.
 */
export function SidebarShell({
  nav,
  sheetLabel,
  sheetTitle,
  children,
}: {
  nav: ReactNode;
  sheetLabel: string;
  sheetTitle: string;
  children: ReactNode;
}) {
  return (
    <div className="mx-auto flex w-full max-w-7xl gap-10 px-6 md:px-8">
      <aside className="sticky top-14 hidden h-[calc(100svh-3.5rem)] w-60 shrink-0 lg:block">
        <SidebarScroll className="py-10 pr-3">{nav}</SidebarScroll>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col gap-6 py-8 lg:py-10">
        <div className="lg:hidden">
          <CatalogSheet label={sheetLabel} title={sheetTitle}>
            {nav}
          </CatalogSheet>
        </div>
        {children}
      </div>
    </div>
  );
}
