import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { ConversationRow } from "@/features/inbox/inbox-types";

import { CRM_TAG } from "@/features/crm/crm-cache";
import { INBOX_TAG } from "@/features/inbox/inbox-cache";
import { toConversationRow } from "@/features/inbox/inbox-types";
import { recordPages } from "@/features/records/record-pages";
import { bsb } from "@/lib/supabase/server";

import { SALES_TAG } from "../sales-cache";

/** The newest conversations the lookup reads, across every status. */
const CONVERSATION_WINDOW = 50;

/**
 * The conversations of the people linked to the deal, newest first. The deals
 * block lists deals by a person and has no read for a deal's contacts, so the
 * buyers are the people on the deal's relations binding (the Related tab links
 * them), read once, and the newest conversations are filtered to those people.
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

  const [conversations, { bindings }] = await Promise.all([
    db.inbox.conversations
      .list({ tenant, filter: { status: "all", limit: CONVERSATION_WINDOW } })
      .orThrow(),
    recordPages.deal.load(dealId, { bindings: ["relations"] }),
  ]);

  if (bindings.relations.kind !== "ok") {
    return [];
  }

  const buyers = new Set(
    bindings.relations.data
      .filter((link) => link.subject.type === "person")
      .map((link) => link.subject.id),
  );

  return conversations
    .filter((conversation) => buyers.has(conversation.contactId))
    .map(toConversationRow);
}
