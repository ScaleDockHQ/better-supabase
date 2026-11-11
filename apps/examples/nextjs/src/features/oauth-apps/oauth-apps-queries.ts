import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { loadAdminList } from "@/features/admin-lists/admin-list-load";
import { readPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsbShell } from "@/lib/supabase/server-shell";

import { oauthAppList } from "./oauth-apps-list";
import { oauthAppSource } from "./oauth-apps-source";

/**
 * The first page of oauth apps; `null` without an organization or the
 * permission.
 */
export async function getOAuthApps() {
  "use cache: private";
  const request = await bsbShell.cached();
  cacheTag("oauth-apps");
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, "settings.manage")) {
    return null;
  }

  return loadAdminList({
    session: request.session,
    tenant,
    list: oauthAppList,
    source: oauthAppSource,
    access: "admin",
    query: oauthAppList.defaults,
  });
}
