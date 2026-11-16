import type { FacetOptions, PageOptions } from "better-supabase/blocks";
import type { Conversation } from "better-supabase/blocks/inbox";
import type { EntityListReads } from "better-supabase/list";

import type { OrganizationReads } from "@/lib/block-entity-page";

import { blockEntityReads, organizationPager } from "@/lib/block-entity-page";

import type { ConversationRow } from "./inbox-types";

import { toConversationRow } from "./inbox-types";

/** The part of the route's `db` the queue reads. */
interface Db {
  readonly inbox: { readonly conversations: OrganizationReads<Conversation> };
}

/**
 * "Anyone" and an empty list are no filter. `page_inbox_conversations` reads
 * `assignee` as one value and rejects an empty list, so the filters leave them
 * out.
 */
function withoutEmpty<T extends PageOptions | FacetOptions>(options: T): T {
  if (options.filters === undefined) {
    return options;
  }

  const filters: Record<string, readonly string[]> = {};

  for (const [key, values] of Object.entries(options.filters)) {
    if (values.length > 0 && !(key === "assignee" && values[0] === "anyone")) {
      filters[key] = values;
    }
  }

  return { ...options, filters };
}

/**
 * The reads module of the `app.inbox` entity page (ADR 0893): the queue's
 * `page` and status `facets` over `inbox.conversations.page` and `facets`,
 * newest activity first. Search, status, assignee and channel (the inbox id)
 * run in the database, and the status counts come from the same filters but the
 * status. The cursor is the block's keyset `[lastMessageAt, id]`.
 */
export function inboxReads(db: Db): EntityListReads<ConversationRow> {
  const reads = blockEntityReads<Conversation, ConversationRow>({
    pager: (organizationId) =>
      organizationPager(organizationId, db.inbox.conversations),
    map: {
      sorts: { lastMessageAt: { by: "lastMessageAt", direction: "desc" } },
      filters: { channel: "inboxId" },
    },
    wire: toConversationRow,
  });

  return {
    page: (options) => reads.page(withoutEmpty(options)),
    facets: (options) => reads.facets(withoutEmpty(options)),
  };
}
