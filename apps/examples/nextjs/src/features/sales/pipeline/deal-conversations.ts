import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { ConversationRow } from "@/features/inbox/inbox-types";

import { CRM_TAG } from "@/features/crm/crm-cache";
import { INBOX_TAG } from "@/features/inbox/inbox-cache";
import { toConversationRow } from "@/features/inbox/inbox-types";
import { bsb } from "@/lib/supabase/server";

import { SALES_TAG } from "../sales-cache";

/** The newest conversations the lookup reads, across every status. */
const CONVERSATION_WINDOW = 50;

/**
 * The conversations of the people the deal names as contacts, newest first. The
 * deals block lists deals by a person, not a person by a deal, so the lookup
 * walks the contacts of the newest conversations and keeps the ones whose deals
 * include this one.
 */
export async function loadDealConversations(
  dealId: string,
): Promise<readonly ConversationRow[]> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG, INBOX_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return [];
  }

  const conversations = await db.inbox.conversations
    .list({ tenant, filter: { status: "all", limit: CONVERSATION_WINDOW } })
    .orThrow();

  const contactIds = [
    ...new Set(conversations.map((conversation) => conversation.contactId)),
  ];

  const named = await Promise.all(
    contactIds.map(async (contactId) => {
      const deals = await db.deals
        .list({ subject: { type: "person", id: contactId } })
        .orThrow();

      return deals.some((deal) => deal.id === dealId) ? [contactId] : [];
    }),
  );

  const buyers = new Set(named.flat());

  return conversations
    .filter((conversation) => buyers.has(conversation.contactId))
    .map(toConversationRow);
}
