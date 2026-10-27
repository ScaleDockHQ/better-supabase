import { evaluate } from "flags/next";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { navFlags } from "@/flags";

import { navItems } from "../nav-items";
import { SideNav } from "./side-nav";

/**
 * Render inside `<Suspense>`: picks the entries the session's permissions and
 * the organization's flags allow, then hands plain ids to the client menu.
 * `evaluate` reads every nav flag in one batch.
 */
export async function AppNav() {
  const [flags, permissions] = await Promise.all([
    evaluate(navFlags),
    getPermissions(),
  ]);

  const visible = navItems
    .filter((item) => !item.requires || can(permissions, item.requires))
    .filter((item) => !item.flag || flags[item.flag])
    .map((item) => item.id);

  return <SideNav visible={visible} />;
}
