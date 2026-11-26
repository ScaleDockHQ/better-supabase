import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { getAdminList } from "@/features/admin-lists/admin-list-load";
import { tags } from "@/lib/supabase/generated.tags";
import { bsbShell } from "@/lib/supabase/server-shell";

import { incomingWebhookList } from "./incoming-webhooks-list";
import { incomingWebhookSource } from "./incoming-webhooks-source";

/**
 * The first page of the organization's incoming endpoints with the count per
 * state and verification mode, read with the user's token.
 */
export async function getIncomingWebhooks() {
  "use cache: private";
  const { session } = await bsbShell.cached();
  cacheTag(tags.incomingWebhooks());
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  return getAdminList({
    session,
    tenant,
    list: incomingWebhookList,
    source: incomingWebhookSource,
    access: "user",
    query: incomingWebhookList.defaults,
  });
}
