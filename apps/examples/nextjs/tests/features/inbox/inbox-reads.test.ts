import type { FacetOptions, PageOptions } from "better-supabase/blocks";
import type { Conversation } from "better-supabase/blocks/inbox";

import { ok } from "better-supabase";
import { describe, expect, it, vi } from "vitest";

import { inboxReads } from "@/features/inbox/inbox-reads";

function conversation(id: string, status: string) {
  return {
    id,
    status,
    subject: null,
    snoozedUntil: null,
    botMode: "off",
    assigneeId: null,
    teamId: null,
    preview: null,
    lastMessageAt: null,
    unread: false,
    contactId: "contact",
    inboxId: "inbox",
    priority: "normal",
    firstResponseAt: null,
    lastInboundAt: null,
    createdAt: { toString: () => "2026-01-01T00:00:00Z" },
  };
}

function fake(rows: readonly ReturnType<typeof conversation>[]) {
  const page = vi.fn(
    (_options: PageOptions & { readonly organizationId: string }) =>
      Promise.resolve(
        ok({
          // SAFETY: the stub rows carry the fields `toConversationRow` reads.
          items: rows as unknown as readonly Conversation[],
          hasMore: false,
          nextCursor: null,
        }),
      ),
  );

  const facets = vi.fn(
    (_options: FacetOptions & { readonly organizationId: string }) =>
      Promise.resolve(ok([])),
  );

  // SAFETY: the stubs return plain results where the block returns an `AsyncResult`.
  const db = { inbox: { conversations: { page, facets } } } as never;

  return { db, page, facets };
}

describe("inboxReads", () => {
  it("maps the page options to the block page", async () => {
    const { db, page } = fake([conversation("a", "open")]);

    await inboxReads(db).page({
      tenant: "org",
      q: "refund",
      limit: 10,
      filters: { status: ["pending"], assignee: ["me"], channel: ["inbox-1"] },
    });

    expect(page).toHaveBeenCalledWith({
      organizationId: "org",
      q: "refund",
      limit: 10,
      filters: { status: ["pending"], assignee: ["me"], inboxId: ["inbox-1"] },
    });
  });

  it("ignores the anyone assignee and empty lists", async () => {
    const { db, page } = fake([]);

    await inboxReads(db).page({
      tenant: "org",
      filters: { assignee: ["anyone"], channel: [] },
    });

    expect(page).toHaveBeenCalledWith({ organizationId: "org" });
  });

  it("counts the facets under the same search and filters", async () => {
    const { db, facets } = fake([]);

    await inboxReads(db).facets({
      tenant: "org",
      q: "x",
      filters: { channel: ["inbox-1"] },
    });

    expect(facets).toHaveBeenCalledWith({
      organizationId: "org",
      q: "x",
      filters: { inboxId: ["inbox-1"] },
    });
  });

  it("answers no rows without an organization", async () => {
    const { db, page } = fake([]);

    const result = await inboxReads(db).page({});

    expect(result.ok && result.data.items).toStrictEqual([]);
    expect(page).not.toHaveBeenCalled();
  });
});
