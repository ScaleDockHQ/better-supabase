import "server-only";
import { evaluate } from "flags/next";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { navFlags } from "@/flags";

import type { NavId } from "./nav-items";

import { navItems } from "./nav-items";

/**
 * The ids of the entries the session's permissions and the organization's flags
 * allow, for the side menu and the command center. `evaluate` reads every nav
 * flag in one batch.
 */
export async function getVisibleNavIds(): Promise<readonly NavId[]> {
  const [flags, permissions] = await Promise.all([
    evaluate(navFlags),
    getPermissions(),
  ]);

  return navItems
    .filter((item) => !item.requires || can(permissions, item.requires))
    .filter((item) => !item.flag || flags[item.flag])
    .map((item) => item.id);
}
