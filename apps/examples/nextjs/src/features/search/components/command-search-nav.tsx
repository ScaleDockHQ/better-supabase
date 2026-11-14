import { getNavLabel } from "@/features/navigation/components/nav-label-server";
import { navItems } from "@/features/navigation/nav-items";
import { getVisibleNavIds } from "@/features/navigation/visible-nav";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { CommandSearchLazy } from "./command-search-lazy";

// skeleton: the header renders the closed `CommandSearchLazy` as the fallback
/**
 * Render inside `<Suspense>`: the command center with the entries of the menu
 * the caller may see, so its "Go to" group never offers a page the proxy would
 * answer with a 403.
 */
export async function CommandSearchNav() {
  const [visible, label, permissions] = await Promise.all([
    getVisibleNavIds(),
    getNavLabel(),
    getPermissions(),
  ]);

  return (
    <CommandSearchLazy
      canCreate={{
        customer: can(permissions, "customers.write"),
        contact: can(permissions, "contacts.write"),
        deal: can(permissions, "deals.write"),
        quote: can(permissions, "quotes.write"),
      }}
      pages={navItems
        .filter((item) => visible.includes(item.id))
        .map((item) => ({
          id: item.id,
          href: item.href,
          label: label(item.id),
        }))}
    />
  );
}
