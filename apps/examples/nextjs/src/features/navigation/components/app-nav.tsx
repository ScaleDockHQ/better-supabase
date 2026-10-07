import { getEnabledFlags } from "@/features/flags/flag-queries";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { navItems } from "../nav-items";
import { SideNav } from "./side-nav";

/**
 * Render inside `<Suspense>`: picks the entries the session's permissions
 * and the organization's flags allow, then hands plain ids to the client menu.
 */
export async function AppNav() {
  const [session, flags] = await Promise.all([getSession(), getEnabledFlags()]);
  const visible = navItems
    .filter(
      (item) =>
        (!item.requires || can(session, item.requires)) &&
        (!item.flag || flags.some((flag) => flag === item.flag)),
    )
    .map((item) => item.id);
  return <SideNav visible={visible} />;
}
