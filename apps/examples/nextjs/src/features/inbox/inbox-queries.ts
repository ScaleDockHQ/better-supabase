import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import "server-only";

import { bsbShell } from "@/lib/supabase/server-shell";

import type { ConversationRow } from "./inbox-types";

import { INBOX_TAG } from "./inbox-cache";
import { toConversationRow } from "./inbox-types";

/** The open conversations of the active organization, newest activity first. */
export async function getConversations(): Promise<readonly ConversationRow[]> {
  "use cache: private";
  const { session, db } = await bsbShell.cached();
  cacheTag(INBOX_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return [];
  }

  const conversations = await db.inbox.conversations
    .list({ tenant, filter: { limit: 40 } })
    .orThrow();

  return conversations.map(toConversationRow);
}

/** What sits beside a thread: the conversation and the contact's history. */
export interface ConversationContext {
  readonly conversation: ConversationRow;
  readonly history: readonly ConversationRow[];
}

/**
 * The conversation's contact and their earlier conversations, newest first.
 * `null` when the caller cannot read the conversation.
 */
export async function getConversationContext(
  conversationId: string,
): Promise<ConversationContext | null> {
  "use cache: private";
  const { session, db } = await bsbShell.cached();
  cacheTag(INBOX_TAG);
  const tenant = tenantOf(session);

  const found = await db.inbox.conversations.get(conversationId).orThrow();

  if (found === null || !tenant) {
    return null;
  }

  const earlier = await db.inbox.conversations
    .list({
      tenant,
      filter: { contactId: found.contactId, status: "all", limit: 6 },
    })
    .orThrow();

  return {
    conversation: toConversationRow(found),
    history: earlier
      .filter((conversation) => conversation.id !== found.id)
      .map(toConversationRow),
  };
}
