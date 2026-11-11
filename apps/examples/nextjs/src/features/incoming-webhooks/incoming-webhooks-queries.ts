import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { loadAdminList } from "@/features/admin-lists/admin-list-load";
import { bsbShell } from "@/lib/supabase/server-shell";

import { INCOMING_WEBHOOKS_TAG } from "./incoming-webhooks-cache";
import { incomingWebhookList } from "./incoming-webhooks-list";
import { incomingWebhookSource } from "./incoming-webhooks-source";

/**
 * The first page of the organization's incoming endpoints with the count per
 * state and verification mode, read with the user's token.
 */
export async function getIncomingWebhooks() {
  "use cache: private";
  const { session } = await bsbShell.cached();
  cacheTag(INCOMING_WEBHOOKS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  return loadAdminList({
    session,
    tenant,
    list: incomingWebhookList,
    source: incomingWebhookSource,
    access: "user",
    query: incomingWebhookList.defaults,
  });
}
