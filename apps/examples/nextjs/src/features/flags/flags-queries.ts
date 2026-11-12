import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import {
  holdsPlatformPermission,
  loadAdminList,
} from "@/features/admin-lists/admin-list-load";
import { bsbShell } from "@/lib/supabase/server-shell";

import { flagList } from "./flags-list";
import { flagSource } from "./flags-source";

/** The first page of flags; `null` without an organization or the permission. */
export async function getFlags() {
  "use cache: private";
  const request = await bsbShell.cached();
  cacheTag("flags");
  const tenant = tenantOf(request.session);

  if (
    !tenant ||
    !(await holdsPlatformPermission(request.session, "flags.manage"))
  ) {
    return null;
  }

  return loadAdminList({
    session: request.session,
    tenant,
    list: flagList,
    source: flagSource,
    access: "admin",
    query: flagList.defaults,
  });
}
