import type { ReactNode } from "react";

import { BlocksNav } from "@/features/blocks/components/blocks-nav";
import { SidebarShell } from "@/features/catalog/components/sidebar-shell";

export default function BlocksLayout({ children }: { children: ReactNode }) {
  return (
    <SidebarShell
      nav={<BlocksNav />}
      sheetLabel="Browse blocks"
      sheetTitle="Blocks"
    >
      {children}
    </SidebarShell>
  );
}
