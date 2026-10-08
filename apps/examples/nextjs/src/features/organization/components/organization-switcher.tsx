import { tenantOf } from "better-supabase/next";

import {
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuSkeleton,
} from "@/components/ui/sidebar";
import { getSession } from "@/features/user/user-queries";

import { getMyOrganizations } from "../organization-queries";
import { OrganizationSwitcherMenu } from "./organization-switcher-menu";

/** Render inside `<Suspense>`; the fallback is `OrganizationSwitcherSkeleton`. */
export async function OrganizationSwitcher() {
  const [session, organizations] = await Promise.all([
    getSession(),
    getMyOrganizations(),
  ]);
  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <OrganizationSwitcherMenu
          organizations={organizations}
          activeId={tenantOf(session) ?? null}
        />
      </SidebarMenuItem>
    </SidebarMenu>
  );
}

export function OrganizationSwitcherSkeleton() {
  return (
    <SidebarMenu aria-busy="true">
      <SidebarMenuItem>
        <SidebarMenuSkeleton showIcon />
      </SidebarMenuItem>
    </SidebarMenu>
  );
}
