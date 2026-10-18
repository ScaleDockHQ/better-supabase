import type { ReactNode } from "react";

import { SidebarShell } from "@/features/catalog/components/sidebar-shell";
import { RecipesNav } from "@/features/recipes/components/recipes-nav";

export default function RecipesLayout({ children }: { children: ReactNode }) {
  return (
    <SidebarShell
      nav={<RecipesNav />}
      sheetLabel="Browse recipes"
      sheetTitle="Recipes"
    >
      {children}
    </SidebarShell>
  );
}
