import { getEnabledFlags } from "@/features/flags/flag-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { navItems } from "../nav-items";
import { PermissionRedirect } from "./permission-redirect";
import { SideNav } from "./side-nav";

/**
 * Render inside `<Suspense>`: picks the entries the session's permissions and
 * the organization's flags allow, then hands plain ids to the client menu.
 */
export async function AppNav() {
  const [flags, permissions] = await Promise.all([
    getEnabledFlags(),
    getPermissions(),
  ]);

  const allowed = navItems.filter(
    (item) => !item.requires || can(permissions, item.requires),
  );

  const visible = allowed
    .filter((item) => !item.flag || flags.some((flag) => flag === item.flag))
    .map((item) => item.id);

  return (
    <>
      <SideNav visible={visible} />
      <PermissionRedirect allowed={allowed.map((item) => item.id)} />
    </>
  );
}
