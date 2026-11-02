import { describe, expect, it } from "vitest";

import {
  createModeration,
  moderationBlock,
  moderationEvents,
  moderationBinding,
} from "../../../src/blocks/moderation/index.ts";

const AT = "2026-10-22T10:00:00Z";

const ITEM = {
  id: "i1",
  organizationId: "org-1",
  subjectType: "comment",
  subjectId: "c1",
  authorId: "u1",
  status: "hidden",
  openReports: 2,
  reason: "Spam",
  decidedBy: null,
  decidedAt: AT,
  createdAt: AT,
  updatedAt: AT,
};

const REPORT = {
  id: "r1",
  organizationId: "org-1",
  itemId: "i1",
  reporterId: "u2",
  reason: "spam",
  note: "Ads",
  status: "open",
  resolvedBy: null,
  resolvedAt: null,
  createdAt: AT,
};

const BAN = {
  id: "b1",
  organizationId: "org-1",
  userId: "u1",
  reason: null,
  bannedBy: "u3",
  expiresAt: "2026-10-23T10:00:00Z",
  liftedBy: null,
  liftedAt: null,
  createdAt: AT,
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

describe("createModeration", () => {
  it("reports content and reads the queue and one item", async () => {
    const fake = fakeTransport({
      report_content: { ...REPORT, autoHidden: true },
      moderation_queue: [
        ITEM,
        {
          ...ITEM,
          id: "i2",
          authorId: null,
          reason: null,
          decidedAt: null,
          openReports: null,
        },
      ],
      moderation_item: {
        ...ITEM,
        reports: [REPORT],
        actions: [
          {
            id: "a1",
            action: "auto_hide",
            fromStatus: "visible",
            toStatus: "hidden",
            reason: "Hidden after 2 reports",
            actorId: null,
            createdAt: AT,
          },
          {
            id: "a0",
            action: "submit",
            fromStatus: null,
            toStatus: "visible",
            reason: null,
            actorId: "u1",
            createdAt: AT,
          },
        ],
      },
    });

    const moderation = createModeration({
      transport: fake.transport,
      tenant: "org-1",
    });

    const report = await moderation
      .report({
        subject: { type: "comment", id: "c1" },
        report: { reason: "spam", note: "Ads" },
      })
      .orThrow();

    expect(report).toMatchObject({
      id: "r1",
      reporterId: "u2",
      note: "Ads",
      status: "open",
      autoHidden: true,
    });
    expect(report.resolvedAt).toBeUndefined();

    const queue = await moderation
      .queue({
        status: "hidden",
        subjectType: "comment",
        pageSize: 10,
        before: Temporal.Instant.from(AT),
      })
      .orThrow();

    expect(queue[0]).toMatchObject({
      subject: { type: "comment", id: "c1" },
      authorId: "u1",
      status: "hidden",
      openReports: 2,
      reason: "Spam",
    });
    expect(queue[0]?.decidedAt?.toString()).toBe(AT);
    expect(queue[0]?.decidedBy).toBeUndefined();
    expect(queue[1]).toMatchObject({ openReports: 0 });
    expect(queue[1]?.authorId).toBeUndefined();

    const detail = await moderation
      .item({ type: "comment", id: "c1" })
      .orThrow();

    expect(detail?.reports.map((row) => row.id)).toEqual(["r1"]);
    expect(detail?.actions[0]).toMatchObject({
      action: "auto_hide",
      fromStatus: "visible",
      toStatus: "hidden",
    });
    expect(detail?.actions[1]?.fromStatus).toBeUndefined();
    expect(detail?.actions[1]?.actorId).toBe("u1");

    expect(fake.calls).toEqual([
      [
        "report_content",
        {
          tenant: "org-1",
          subject_type: "comment",
          subject_id: "c1",
          reason: "spam",
          note: "Ads",
        },
      ],
      [
        "moderation_queue",
        {
          tenant: "org-1",
          status: "hidden",
          subject_type: "comment",
          page_size: 10,
          before: AT,
        },
      ],
      [
        "moderation_item",
        { tenant: "org-1", subject_type: "comment", subject_id: "c1" },
      ],
    ]);
  });

  it("defaults the filters and reads an unmoderated subject as null", async () => {
    const fake = fakeTransport({
      report_content: { ...REPORT, note: null },
      moderation_queue: [],
      moderation_item: null,
      moderation_statuses: null,
      list_bans: [],
    });

    const moderation = createModeration({
      transport: fake.transport,
      tenant: "org-1",
    });

    expect(
      await moderation
        .report({
          subject: { type: "post", id: "p1" },
          report: { reason: "spam" },
        })
        .orThrow(),
    ).toMatchObject({ autoHidden: false });
    expect(await moderation.queue().orThrow()).toEqual([]);
    expect(
      await moderation.item({ type: "post", id: "p1" }).orThrow(),
    ).toBeNull();
    expect(
      await moderation.statuses({ subjectType: "post", ids: ["p1"] }).orThrow(),
    ).toEqual({});
    expect(await moderation.bans().orThrow()).toEqual([]);
    expect(fake.calls.map(([, args]) => args)).toEqual([
      {
        tenant: "org-1",
        subject_type: "post",
        subject_id: "p1",
        reason: "spam",
        note: null,
      },
      {
        tenant: "org-1",
        status: null,
        subject_type: null,
        page_size: null,
        before: null,
      },
      { tenant: "org-1", subject_type: "post", subject_id: "p1" },
      { tenant: "org-1", subject_type: "post", subject_ids: ["p1"] },
      { tenant: "org-1", active: true, page_size: null },
    ]);
  });

  it("decides, reads statuses and manages bans", async () => {
    const fake = fakeTransport({
      moderate: { ...ITEM, status: "visible", reason: null },
      moderation_statuses: { c1: "hidden", c2: "pending" },
      ban_user: BAN,
      unban_user: true,
      list_bans: [BAN, { ...BAN, id: "b2", expiresAt: null, liftedAt: AT }],
    });

    const moderation = createModeration({
      transport: fake.transport,
      tenant: "org-1",
    });

    expect(
      (await moderation.decide({ itemId: "i1", decision: "restore" }).orThrow())
        .status,
    ).toBe("visible");
    await moderation
      .decide({ itemId: "i1", decision: "ban", reason: "Spam ring" })
      .orThrow();
    expect(
      await moderation
        .statuses({ subjectType: "comment", ids: ["c1", "c2", "c3"] })
        .orThrow(),
    ).toEqual({ c1: "hidden", c2: "pending" });

    const ban = await moderation
      .ban({
        userId: "u1",
        reason: "Spam",
        expiresAt: Temporal.Instant.from("2026-10-23T10:00:00Z"),
      })
      .orThrow();

    expect(ban.expiresAt?.toString()).toBe("2026-10-23T10:00:00Z");
    expect(ban.reason).toBeUndefined();
    expect(await moderation.unban("b1").orThrow()).toBe(true);

    const bans = await moderation
      .bans({ active: false, pageSize: 5 })
      .orThrow();

    expect(bans[1]?.liftedAt?.toString()).toBe(AT);
    expect(bans[1]?.expiresAt).toBeUndefined();
    await moderation.ban({ userId: "u2" }).orThrow();

    expect(fake.calls).toEqual([
      ["moderate", { item_id: "i1", action: "restore", reason: null }],
      ["moderate", { item_id: "i1", action: "ban", reason: "Spam ring" }],
      [
        "moderation_statuses",
        {
          tenant: "org-1",
          subject_type: "comment",
          subject_ids: ["c1", "c2", "c3"],
        },
      ],
      [
        "ban_user",
        {
          tenant: "org-1",
          user_id: "u1",
          reason: "Spam",
          expires_at: "2026-10-23T10:00:00Z",
        },
      ],
      ["unban_user", { ban_id: "b1" }],
      ["list_bans", { tenant: "org-1", active: false, page_size: 5 }],
      [
        "ban_user",
        { tenant: "org-1", user_id: "u2", reason: null, expires_at: null },
      ],
    ]);
  });

  it("rejects an unknown status from the database", async () => {
    const moderation = createModeration({
      transport: fakeTransport({
        moderate: { ...ITEM, status: "deleted" },
        moderation_statuses: { c1: "gone" },
      }).transport,
      tenant: "org-1",
    });

    expect(
      (await moderation.decide({ itemId: "i1", decision: "hide" })).ok,
    ).toBe(false);
    expect(
      (await moderation.statuses({ subjectType: "comment", ids: ["c1"] })).ok,
    ).toBe(false);
  });

  it("fails tenant-scoped calls without a tenant", async () => {
    const fake = fakeTransport({});
    const moderation = createModeration({ transport: fake.transport });

    expect(
      (
        await moderation.report({
          subject: { type: "comment", id: "c1" },
          report: { reason: "spam" },
        })
      ).ok,
    ).toBe(false);
    expect((await moderation.queue()).ok).toBe(false);
    expect((await moderation.ban({ userId: "u1" })).ok).toBe(false);
    expect(fake.calls).toEqual([]);
  });
});

describe("moderationBinding", () => {
  it("loads a record's moderation item", async () => {
    const fake = fakeTransport({ moderation_item: ITEM });

    const moderation = createModeration({
      transport: fake.transport,
      tenant: "org-1",
    });

    const item = await moderationBinding
      .load(moderation, { type: "comment", id: "c1" }, undefined)
      .orThrow();

    expect(item).toMatchObject({ status: "hidden", reports: [], actions: [] });
    expect(moderationBlock.record).toBe(moderationBinding);
    expect(moderationBinding.events).toEqual([
      "moderation_report.created",
      "moderation_item.decided",
    ]);
    expect(moderationEvents.types).toContain("moderation_ban.lifted");
  });
});
