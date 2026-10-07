import {
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuSkeleton,
} from "@/components/ui/sidebar";

import { roleOf } from "../user-permissions";
import { getMyProfile, getSession } from "../user-queries";
import { UserMenuDropdown } from "./user-menu-dropdown";

/** Render inside `<Suspense>`; the fallback is `UserMenuSkeleton`. */
export async function UserMenu() {
  const [session, profile] = await Promise.all([getSession(), getMyProfile()]);
  if (session.kind !== "user") return null;
  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <UserMenuDropdown
          name={profile?.fullName ?? null}
          email={session.user.email ?? profile?.email ?? null}
          avatarUrl={profile?.avatarUrl ?? null}
          role={roleOf(session) ?? null}
        />
      </SidebarMenuItem>
    </SidebarMenu>
  );
}

export function UserMenuSkeleton() {
  return (
    <SidebarMenu aria-busy="true">
      <SidebarMenuItem>
        <SidebarMenuSkeleton showIcon />
      </SidebarMenuItem>
    </SidebarMenu>
  );
}
