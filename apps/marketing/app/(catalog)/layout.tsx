import type { ReactNode } from "react";

import { CatalogNav } from "@/features/catalog/components/catalog-nav";
import { CatalogSheet } from "@/features/catalog/components/catalog-sheet";

/**
 * Blocks, recipes and create share this sidebar, so it stays mounted (and
 * keeps its scroll position) while the pages under it change.
 */
export default function CatalogLayout({ children }: { children: ReactNode }) {
  return (
    <div className="mx-auto flex w-full max-w-7xl gap-10 px-6 md:px-8">
      <aside className="sticky top-14 hidden h-[calc(100svh-3.5rem)] w-60 shrink-0 overflow-y-auto overscroll-contain py-10 pr-2 lg:block">
        <CatalogNav />
      </aside>
      <div className="flex min-w-0 flex-1 flex-col gap-6 py-8 lg:py-10">
        <div className="lg:hidden">
          <CatalogSheet>
            <CatalogNav />
          </CatalogSheet>
        </div>
        {children}
      </div>
    </div>
  );
}
