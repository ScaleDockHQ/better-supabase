import { tenantOf } from "better-supabase/next";
import "server-only";

import { bsb } from "@/lib/supabase/server";

import type { ConversationRow } from "./inbox-types";

import { toConversationRow } from "./inbox-types";

/** The open conversations of the active organization, newest activity first. */
export async function getConversations(): Promise<readonly ConversationRow[]> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return [];
  }

  const conversations = await db.inbox.conversations
    .list({ tenant, filter: { limit: 50 } })
    .orThrow();

  return conversations.map(toConversationRow);
}
