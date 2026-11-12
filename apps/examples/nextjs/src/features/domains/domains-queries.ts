import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { loadAdminList } from "@/features/admin-lists/admin-list-load";
import { readPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsbShell } from "@/lib/supabase/server-shell";

import { DOMAINS_TAG } from "./domains-cache";
import { domainList } from "./domains-list";
import { domainSource } from "./domains-source";

/**
 * The first page of the organization's hostnames with the count per state and
 * kind. `null` without an organization or `domains.read`. The page doesn't read
 * `searchParams`, so it stays in the instant App Shell; filtered pages go
 * through `/api/domains/list`.
 */
export async function getDomains() {
  "use cache: private";
  const request = await bsbShell.cached();
  cacheTag(DOMAINS_TAG);
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, "domains.read")) {
    return null;
  }

  return loadAdminList({
    session: request.session,
    tenant,
    list: domainList,
    source: domainSource,
    access: "admin",
    query: domainList.defaults,
  });
}
