import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { loadAdminList } from "@/features/admin-lists/admin-list-load";
import { readPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsbShell } from "@/lib/supabase/server-shell";

import { numberingList } from "./numbering-list";
import { numberingSource } from "./numbering-source";

/**
 * The first page of numbering; `null` without an organization or the
 * permission.
 */
export async function getNumbering() {
  "use cache: private";
  const request = await bsbShell.cached();
  cacheTag("numbering");
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, "numbering.assign")) {
    return null;
  }

  return loadAdminList({
    session: request.session,
    tenant,
    list: numberingList,
    source: numberingSource,
    access: "admin",
    query: numberingList.defaults,
  });
}
