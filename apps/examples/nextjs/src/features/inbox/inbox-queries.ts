import { tenantOf } from "better-supabase/next";
import "server-only";

import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

import { type ConversationRow, toConversationRow } from "./inbox-types";

/** The open conversations of the active organization, newest activity first. */
export async function getConversations(): Promise<readonly ConversationRow[]> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);
  if (!tenant) return [];
  const conversations = await blocks(supabase)
    .inbox.conversations.list(tenant, { limit: 50 })
    .orThrow();
  return conversations.map(toConversationRow);
}
