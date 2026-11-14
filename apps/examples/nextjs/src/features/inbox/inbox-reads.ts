import type { AsyncResult } from "better-supabase";
import type { FacetResult, PageOptions } from "better-supabase/blocks";
import type {
  Conversation,
  ConversationFilter,
} from "better-supabase/blocks/inbox";
import type { EntityListReads } from "better-supabase/list";

import { ok } from "better-supabase";
import { Temporal } from "temporal-polyfill";

import type { ConversationRow } from "./inbox-types";

import { toConversationRow } from "./inbox-types";

/** The part of the route's `db` the queue reads. */
interface Db {
  readonly inbox: {
    readonly conversations: {
      list(input: {
        tenant: string | null;
        filter?: ConversationFilter | undefined;
      }): AsyncResult<readonly Conversation[]>;
    };
  };
}

/** `ConversationFilter` without `readonly`, built field by field. */
type DraftFilter = {
  -readonly [K in keyof ConversationFilter]: ConversationFilter[K];
};

/** The tenant travels as the page option `tenantOption: "tenant"` names. */
type InboxPageOptions = PageOptions & { readonly tenant?: string | null };

const PAGE_SIZE = 40;

/** The most conversations the status counts read. */
const COUNT_CAP = 200;

const STATUSES = ["open", "pending", "snoozed", "resolved"] as const;

const isStatus = (value: string): value is ConversationStatus =>
  value === "all" || STATUSES.some((status) => status === value);

type ConversationStatus = (typeof STATUSES)[number] | "all";

function filterOf(options: PageOptions): DraftFilter {
  const [status = "open"] = options.filters?.["status"] ?? [];
  const [assignee] = options.filters?.["assignee"] ?? [];
  const [channel] = options.filters?.["channel"] ?? [];
  const [id, lastMessageAt] = options.after ?? [];

  const filter: DraftFilter = {
    status: isStatus(status) ? status : "open",
    limit: options.limit ?? PAGE_SIZE,
  };

  if (assignee !== undefined && assignee !== "anyone") {
    filter.assignee = assignee;
  }

  if (channel !== undefined && channel !== "") {
    filter.inboxId = channel;
  }

  if (options.q !== undefined && options.q !== "") {
    filter.search = options.q;
  }

  if (id !== undefined) {
    filter.cursor = {
      id,
      lastMessageAt:
        lastMessageAt === undefined || lastMessageAt === ""
          ? null
          : Temporal.Instant.from(lastMessageAt),
    };
  }

  return filter;
}

/**
 * The reads module of the `app.inbox` entity page (ADR 0893): the queue's
 * `page` and status `facets` over `inbox.conversations.list`, newest activity
 * first. Search, status, assignee and channel run in the database. The cursor
 * is the last row's `[id, lastMessageAt]`.
 */
export function inboxReads(db: Db): EntityListReads<ConversationRow> {
  return {
    async page(options: InboxPageOptions) {
      const filter = filterOf(options);

      const listed = await db.inbox.conversations.list({
        tenant: options.tenant ?? null,
        filter,
      });

      if (!listed.ok) {
        return listed;
      }

      const items = listed.data.map(toConversationRow);
      const last = items.at(-1);
      const hasMore = items.length === filter.limit;

      return ok({
        items,
        hasMore,
        nextCursor:
          hasMore && last !== undefined
            ? [last.id, last.lastMessageAt ?? ""]
            : null,
      });
    },
    async facets(options: InboxPageOptions) {
      // The counts read one capped list under every filter but the status.
      const filter = filterOf({
        ...options,
        filters: { ...options.filters, status: ["all"] },
      });

      const listed = await db.inbox.conversations.list({
        tenant: options.tenant ?? null,
        filter: { ...filter, limit: COUNT_CAP },
      });

      if (!listed.ok) {
        return listed;
      }

      const counts = new Map<string, number>();

      for (const conversation of listed.data) {
        counts.set(
          conversation.status,
          (counts.get(conversation.status) ?? 0) + 1,
        );
      }

      const exact = listed.data.length < COUNT_CAP;

      const status: FacetResult = {
        facet: "status",
        values: [...counts].map(([value, count]) => ({
          value,
          count: { value: count, exact },
        })),
      };

      return ok([status]);
    },
  };
}
