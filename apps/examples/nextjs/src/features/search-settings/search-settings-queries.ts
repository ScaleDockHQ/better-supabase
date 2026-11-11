import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { loadAdminList } from "@/features/admin-lists/admin-list-load";
import { readPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsbShell } from "@/lib/supabase/server-shell";

import { searchDocumentList } from "./search-settings-list";
import { searchDocumentSource } from "./search-settings-source";

/**
 * The first page of search index; `null` without an organization or the
 * permission.
 */
export async function getSearchDocuments() {
  "use cache: private";
  const request = await bsbShell.cached();
  cacheTag("search-settings");
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, "settings.read")) {
    return null;
  }

  return loadAdminList({
    session: request.session,
    tenant,
    list: searchDocumentList,
    source: searchDocumentSource,
    access: "user",
    query: searchDocumentList.defaults,
  });
}
