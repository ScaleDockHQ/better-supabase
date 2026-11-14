import type { ConversationFilter } from "better-supabase/blocks/inbox";

import { ok } from "better-supabase";
import { describe, expect, it } from "vitest";

import { inboxReads } from "@/features/inbox/inbox-reads";

interface Call {
  readonly tenant: string | null;
  readonly filter: ConversationFilter | undefined;
}

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
  const calls: Call[] = [];

  const db = {
    inbox: {
      conversations: {
        list: (input: Call) => {
          calls.push(input);

          // SAFETY: the stub rows carry the fields `toConversationRow` reads.
          return Promise.resolve(ok(rows)) as never;
        },
      },
    },
  };

  return { db, calls };
}

describe("inboxReads", () => {
  it("maps the page options to the conversation filter", async () => {
    const { db, calls } = fake([conversation("a", "open")]);

    await inboxReads(db).page({
      tenant: "org",
      q: "refund",
      limit: 10,
      filters: { status: ["pending"], assignee: ["me"], channel: ["inbox-1"] },
    });

    expect(calls[0]?.tenant).toBe("org");

    expect(calls[0]?.filter).toStrictEqual({
      status: "pending",
      limit: 10,
      assignee: "me",
      inboxId: "inbox-1",
      search: "refund",
    });
  });

  it("opens on the open status and ignores the anyone assignee", async () => {
    const { db, calls } = fake([]);

    await inboxReads(db).page({
      tenant: "org",
      filters: { assignee: ["anyone"] },
    });

    expect(calls[0]?.filter).toStrictEqual({ status: "open", limit: 40 });
  });

  it("returns the last row as the cursor only when the page is full", async () => {
    const full = fake([conversation("a", "open"), conversation("b", "open")]);

    const page = await inboxReads(full.db).page({ tenant: "org", limit: 2 });

    expect(page.ok && page.data.nextCursor).toStrictEqual(["b", ""]);

    const short = fake([conversation("a", "open")]);

    const last = await inboxReads(short.db).page({ tenant: "org", limit: 2 });

    expect(last.ok && last.data.nextCursor).toBeNull();
  });

  it("counts the statuses under every filter but the status", async () => {
    const { db, calls } = fake([
      conversation("a", "open"),
      conversation("b", "open"),
      conversation("c", "resolved"),
    ]);

    const facets = await inboxReads(db).facets({
      tenant: "org",
      filters: { status: ["open"], channel: ["inbox-1"] },
    });

    expect(calls[0]?.filter).toMatchObject({
      status: "all",
      inboxId: "inbox-1",
      limit: 200,
    });

    expect(facets.ok && facets.data).toStrictEqual([
      {
        facet: "status",
        values: [
          { value: "open", count: { value: 2, exact: true } },
          { value: "resolved", count: { value: 1, exact: true } },
        ],
      },
    ]);
  });
});
