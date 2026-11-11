import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { loadAdminList } from "@/features/admin-lists/admin-list-load";
import { readPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsbShell } from "@/lib/supabase/server-shell";

import { securityStreamList } from "./security-events-list";
import { securityStreamSource } from "./security-events-source";

/**
 * The first page of security events; `null` without an organization or the
 * permission.
 */
export async function getSecurityStreams() {
  "use cache: private";
  const request = await bsbShell.cached();
  cacheTag("security-events");
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, "audit.read")) {
    return null;
  }

  return loadAdminList({
    session: request.session,
    tenant,
    list: securityStreamList,
    source: securityStreamSource,
    access: "admin",
    query: securityStreamList.defaults,
  });
}
