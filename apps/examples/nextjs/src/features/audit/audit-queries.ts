import "server-only";
import type {
  AuditListOptions,
  AuditRecord,
} from "better-supabase/blocks/audit";

import { getMembers } from "@/features/organization/organization-queries";
import { bsb } from "@/lib/supabase/server";

import type { loadAuditFilters } from "./audit-search-params";

import {
  AUDIT_COUNT_CAP,
  AUDIT_PAGE_SIZE,
  DEFAULT_WINDOW_DAYS,
} from "./audit-search-params";

export type AuditFilters = Awaited<ReturnType<typeof loadAuditFilters>>;

export interface AuditPageData {
  readonly entries: readonly AuditRecord[];
  /** The `before` of the next, older page. */
  readonly next: string | null;
}

/** The start of the window: the URL's `from`, or the last 30 days. */
function sinceOf(filters: AuditFilters): Temporal.Instant {
  return filters.from
    ? Temporal.Instant.from(filters.from)
    : Temporal.Now.instant().subtract({ hours: DEFAULT_WINDOW_DAYS * 24 });
}

function untilOf(filters: AuditFilters): Temporal.Instant | undefined {
  return filters.to ? Temporal.Instant.from(filters.to) : undefined;
}

function cursorOf(before: string | null) {
  const [at, id] = before?.split("|") ?? [];

  return at && id ? { occurredAt: Temporal.Instant.from(at), id } : undefined;
}

type Listing = { -readonly [K in keyof AuditListOptions]: AuditListOptions[K] };

/** The filters every read of one organization shares. */
function listOf(organizationId: string, filters: AuditFilters): Listing {
  const list: Listing = { organizationId, since: sinceOf(filters) };
  const until = untilOf(filters);

  if (filters.actor) {
    list.actorId = filters.actor;
  }

  if (filters.type) {
    list.eventType = filters.type;
  }

  if (filters.q) {
    list.search = filters.q;
  }

  if (until) {
    list.until = until;
  }

  return list;
}

// The audit reads stay dynamic on purpose: database triggers write the log,
// not app actions, so no tag could say when a page is stale.

/** One page of 50 summary entries, newest first. */
export async function getAuditPage(
  organizationId: string,
  filters: AuditFilters,
): Promise<AuditPageData> {
  const { db } = await bsb.cached();

  const list = listOf(organizationId, filters);
  const cursor = cursorOf(filters.before);

  if (cursor) {
    list.cursor = cursor;
  }

  list.limit = AUDIT_PAGE_SIZE;
  list.fields = "summary";

  const page = await db.audit.list(list).orThrow();

  return {
    entries: page.entries,
    next: page.next
      ? `${page.next.occurredAt.toString()}|${page.next.id}`
      : null,
  };
}

/** How many entries match, up to the cap. */
export async function getAuditTotal(
  organizationId: string,
  filters: AuditFilters,
): Promise<number> {
  const { db } = await bsb.cached();

  const page = await db.audit
    .list({
      ...listOf(organizationId, filters),
      limit: 1,
      fields: "summary",
      count: true,
      countCap: AUDIT_COUNT_CAP,
    })
    .orThrow();

  return page.total ?? 0;
}

export interface AuditFacets {
  readonly actors: readonly { readonly id: string; readonly name: string }[];
  readonly types: readonly string[];
}

/** The choices of the filter bar: the members, and the event types in the log. */
export async function getAuditFacets(
  organizationId: string,
): Promise<AuditFacets> {
  const { db } = await bsb.cached();

  const [members, types] = await Promise.all([
    getMembers(organizationId),
    db.audit.eventTypes({ organizationId }).orThrow(),
  ]);

  return {
    actors: members.map((member) => ({
      id: member.userId,
      name: member.name ?? member.email ?? member.userId,
    })),
    types,
  };
}

/** One entry with its old and new record, for the details sheet. */
export async function getAuditEntry(
  entryId: string,
): Promise<AuditRecord | null> {
  const { db } = await bsb.cached();

  return db.audit.get(entryId).orThrow();
}
