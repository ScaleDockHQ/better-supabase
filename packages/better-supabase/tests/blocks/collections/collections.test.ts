import { describe, expect, it } from "vitest";

import { createCollections } from "../../../src/blocks/collections/index.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const LIST = {
  id: "c1",
  organizationId: "o",
  subjectType: "company",
  scope: "team",
  ownerId: null,
  teamId: "t1",
  name: "Key accounts",
  description: null,
  archivedAt: null,
  createdBy: "u1",
  createdAt: "2026-10-14T09:00:00Z",
  updatedAt: "2026-10-14T09:00:00Z",
};

const ENTRY = (id: string, rank: string) => ({
  collectionId: "c1",
  subjectType: "company",
  subjectId: id,
  rank,
  addedBy: "u1",
  addedAt: "2026-10-14T09:00:00Z",
  title: `Company ${id}`,
  url: null,
});

const STAR = {
  organizationId: "o",
  subjectType: "deal",
  subjectId: "d1",
  rank: "V",
  starredAt: "2026-10-14T09:00:00Z",
  title: "Renewal",
  url: "/deals/d1",
};

describe("collections block", () => {
  it("creates a list and reads its row", async () => {
    const t = transport({ create_collection: () => LIST });

    const list = await createCollections({ transport: t })
      .create({
        organizationId: "o",
        input: {
          name: "Key accounts",
          subjectType: "company",
          scope: "team",
          teamId: "t1",
        },
      })
      .orThrow();

    expect(t.calls[0]).toEqual([
      "create_collection",
      {
        tenant: "o",
        subject_type: "company",
        name: "Key accounts",
        scope: "team",
        team: "t1",
        description: null,
      },
    ]);
    expect(list).toEqual({
      id: "c1",
      organizationId: "o",
      subjectType: "company",
      scope: "team",
      teamId: "t1",
      name: "Key accounts",
      archived: false,
      createdBy: "u1",
      createdAt: Temporal.Instant.from("2026-10-14T09:00:00Z"),
      updatedAt: Temporal.Instant.from("2026-10-14T09:00:00Z"),
    });
  });

  it("defaults the scope, renames, archives and lists", async () => {
    const archived = {
      ...LIST,
      scope: "nonsense",
      ownerId: "u1",
      description: "Q4",
      archivedAt: "2026-10-15T09:00:00Z",
    };

    const t = transport({
      create_collection: () => LIST,
      rename_collection: () => archived,
      archive_collection: () => true,
      list_collections: () => [LIST, archived],
      collections_of: () => [LIST],
    });

    const collections = createCollections({ transport: t });
    await collections.create({
      organizationId: "o",
      input: { name: "x", subjectType: "company" },
    });
    expect(t.calls[0]?.[1]).toMatchObject({ scope: "user", team: null });

    const renamed = await collections
      .rename({ id: "c1", input: { name: "y" } })
      .orThrow();

    expect(renamed).toMatchObject({
      scope: "user",
      ownerId: "u1",
      description: "Q4",
      archived: true,
    });
    expect(renamed.archivedAt?.toString()).toBe("2026-10-15T09:00:00Z");
    await collections.rename({ id: "c1", input: { description: null } });
    await collections.rename({ id: "c1", input: { description: "z" } });
    expect(t.calls.slice(1, 4).map(([, args]) => args)).toEqual([
      { collection: "c1", name: "y", description: null },
      { collection: "c1", name: null, description: "" },
      { collection: "c1", name: null, description: "z" },
    ]);
    expect(await collections.archive({ id: "c1" }).orThrow()).toBe(true);
    expect(t.calls[4]?.[1]).toEqual({ collection: "c1", archived: true });
    expect(
      (await collections.list({ organizationId: "o" }).orThrow()).map(
        (list) => list.archived,
      ),
    ).toEqual([false, true]);
    await collections.list({
      organizationId: "o",
      subjectType: "company",
      includeArchived: true,
    });
    expect(t.calls[6]?.[1]).toEqual({
      tenant: "o",
      subject_type: "company",
      include_archived: true,
    });
    expect(
      await collections.listsOf({ type: "company", id: "a" }).orThrow(),
    ).toHaveLength(1);
  });

  it("adds, removes, reorders and pages entries", async () => {
    const t = transport({
      add_collection_entries: () => ({ added: ["a"] }),
      remove_collection_entries: () => 2,
      rank_collection_entry: () => true,
      collection_entries: (args) =>
        args["after_rank"] === null
          ? [ENTRY("a", "V"), ENTRY("b", "k")]
          : [ENTRY("c", "s")],
      collection_subject_ids: () => ["b", "a"],
    });

    const collections = createCollections({ transport: t });
    expect(
      await collections.add({ id: "c1", subjectIds: ["a", "b"] }).orThrow(),
    ).toEqual({ added: ["a"] });
    expect(t.calls[0]?.[1]).toEqual({
      collection: "c1",
      subject_ids: ["a", "b"],
      subject_type: null,
    });
    expect(
      await collections.remove({ id: "c1", subjectIds: ["a", "b"] }).orThrow(),
    ).toBe(2);

    const key = await collections
      .reorder({ id: "c1", subjectId: "b", neighbors: { next: "V" } })
      .orThrow();

    expect(key < "V").toBe(true);
    expect(
      (
        await collections.reorder({
          id: "c1",
          subjectId: "b",
          neighbors: { previous: "!" },
        })
      ).ok,
    ).toBe(false);

    const first = await collections.entries({ id: "c1", limit: 2 }).orThrow();
    expect(first.next).toEqual({ rank: "k", subjectId: "b" });
    expect(first.items[0]).toMatchObject({ title: "Company a", addedBy: "u1" });
    expect(first.items[0]?.url).toBeUndefined();

    const second = await collections
      .entries({ id: "c1", limit: 2, cursor: first.next! })
      .orThrow();

    expect(second.next).toBeUndefined();
    expect(t.calls.at(-1)?.[1]).toEqual({
      collection: "c1",
      after_rank: "k",
      after_id: "b",
      page_size: 2,
    });
    expect(
      (await collections.entries({ id: "c1" }).orThrow()).next,
    ).toBeUndefined();

    expect(
      await collections.subjectIds({ id: "c1", max: 10 }).orThrow(),
    ).toEqual(["b", "a"]);
    expect(await collections.where({ id: "c1" }).orThrow()).toEqual({
      id: { in: ["b", "a"] },
    });
    expect(
      await collections.where({ id: "c1", column: "company_id" }).orThrow(),
    ).toEqual({ company_id: { in: ["b", "a"] } });
  });

  it("reads an empty add result as nothing added", async () => {
    const t = transport({ add_collection_entries: () => null });
    expect(
      await createCollections({ transport: t })
        .add({ id: "c1", subjectIds: [] })
        .orThrow(),
    ).toEqual({ added: [] });
  });

  it("stars, unstars and reorders favorites", async () => {
    const t = transport({
      star_subject: () => STAR,
      unstar_subject: () => true,
      starred_subjects: () => [STAR, { ...STAR, title: null, url: null }],
      rank_star: () => true,
    });

    const collections = createCollections({ transport: t });
    const deal = { type: "deal", id: "d1" };

    const star = await collections
      .star({ organizationId: "o", subject: deal })
      .orThrow();

    expect(star).toEqual({
      organizationId: "o",
      subjectType: "deal",
      subjectId: "d1",
      rank: "V",
      starredAt: Temporal.Instant.from("2026-10-14T09:00:00Z"),
      title: "Renewal",
      url: "/deals/d1",
    });
    expect(await collections.unstar(deal).orThrow()).toBe(true);

    const stars = await collections
      .starred({ organizationId: "o", type: "deal" })
      .orThrow();

    expect(stars[1]?.title).toBeUndefined();
    expect(t.calls[2]?.[1]).toEqual({ tenant: "o", subject_type: "deal" });
    await collections.starred({ organizationId: "o" });
    expect(t.calls[3]?.[1]).toEqual({ tenant: "o", subject_type: null });
    expect(
      await collections
        .reorderStar({ subject: deal, neighbors: { previous: "V" } })
        .orThrow(),
    ).toBe("k");
    expect(
      (
        await collections.reorderStar({
          subject: deal,
          neighbors: { next: "!" },
        })
      ).ok,
    ).toBe(false);
  });

  describe("save for later", () => {
    const SAVED = {
      id: "s1",
      organizationId: "o",
      userId: "u1",
      subjectType: "message",
      subjectId: "m1",
      note: "Reply after the call",
      remindAt: "2026-10-23T09:00:00Z",
      remindedAt: null,
      completedAt: null,
      createdAt: "2026-10-22T09:00:00Z",
      title: "Can you check the quote?",
      url: null,
    };

    it("saves a record with a note and reminder, then lists and completes it", async () => {
      const t = transport({
        save_for_later: () => SAVED,
        list_saved_items: () => [
          SAVED,
          {
            ...SAVED,
            id: "s2",
            note: null,
            remindAt: null,
            completedAt: "2026-10-22T10:00:00Z",
          },
        ],
        complete_saved_item: () => true,
        remove_saved_item: () => false,
      });

      const collections = createCollections({ transport: t });
      const message = { type: "message", id: "m1" };

      const saved = await collections
        .saveForLater({
          organizationId: "o",
          subject: message,
          input: {
            note: "Reply after the call",
            remindAt: Temporal.Instant.from("2026-10-23T09:00:00Z"),
          },
        })
        .orThrow();

      expect(t.calls[0]).toEqual([
        "save_for_later",
        {
          tenant: "o",
          subject_type: "message",
          subject_id: "m1",
          note: "Reply after the call",
          remind_at: "2026-10-23T09:00:00Z",
        },
      ]);
      expect(saved).toEqual({
        id: "s1",
        organizationId: "o",
        userId: "u1",
        subjectType: "message",
        subjectId: "m1",
        note: "Reply after the call",
        remindAt: Temporal.Instant.from("2026-10-23T09:00:00Z"),
        completed: false,
        createdAt: Temporal.Instant.from("2026-10-22T09:00:00Z"),
        title: "Can you check the quote?",
      });

      await collections.saveForLater({ organizationId: "o", subject: message });
      expect(t.calls[1]?.[1]).toMatchObject({ note: null, remind_at: null });

      const page = await collections
        .saved({ organizationId: "o", options: { limit: 2 } })
        .orThrow();

      expect(page.items[1]).toMatchObject({
        id: "s2",
        completed: true,
        completedAt: Temporal.Instant.from("2026-10-22T10:00:00Z"),
      });
      expect(page.items[1]?.note).toBeUndefined();
      expect(page.next).toEqual({
        createdAt: Temporal.Instant.from("2026-10-22T09:00:00Z"),
        id: "s2",
      });
      expect(t.calls[2]?.[1]).toEqual({
        tenant: "o",
        completed: false,
        before: null,
        before_id: null,
        max_rows: 2,
      });

      const completed = await collections
        .saved({
          organizationId: "o",
          options: { completed: true, ...(page.next && { cursor: page.next }) },
        })
        .orThrow();

      expect(completed.next).toBeUndefined();
      expect(t.calls[3]?.[1]).toEqual({
        tenant: "o",
        completed: true,
        before: "2026-10-22T09:00:00Z",
        before_id: "s2",
        max_rows: null,
      });

      expect(await collections.completeSaved({ id: "s1" }).orThrow()).toBe(
        true,
      );
      expect(t.calls[4]).toEqual([
        "complete_saved_item",
        { item: "s1", completed: true },
      ]);
      await collections.completeSaved({ id: "s1", completed: false });
      expect(t.calls[5]?.[1]).toEqual({ item: "s1", completed: false });
      expect(await collections.removeSaved("s1").orThrow()).toBe(false);
      expect(t.calls[6]).toEqual(["remove_saved_item", { item: "s1" }]);
    });

    it("claims due reminders and notifies the member who saved each", async () => {
      const due = [
        { ...SAVED, remindedAt: "2026-10-23T09:00:05Z" },
        { ...SAVED, id: "s2", note: null },
      ];

      const t = transport({ remind_due_saved_items: () => due });
      const sent: [string, unknown][] = [];

      const collections = createCollections({
        transport: t,
        notifier: {
          send: ({ type, input }) => {
            sent.push([type, input]);
          },
        },
        notification: "saved_item_reminder",
      });

      const items = await collections.remindDue({ limit: 10 }).orThrow();
      expect(t.calls[0]).toEqual(["remind_due_saved_items", { max_rows: 10 }]);
      expect(items[0]?.remindedAt).toEqual(
        Temporal.Instant.from("2026-10-23T09:00:05Z"),
      );
      expect(sent).toEqual([
        [
          "saved_item_reminder",
          {
            recipients: ["u1"],
            tenant: "o",
            key: "saved_item:s1:2026-10-23T09:00:00Z",
            subject: { type: "message", id: "m1" },
            data: { savedItemId: "s1", note: "Reply after the call" },
          },
        ],
        [
          "saved_item_reminder",
          {
            recipients: ["u1"],
            tenant: "o",
            key: "saved_item:s2:2026-10-23T09:00:00Z",
            subject: { type: "message", id: "m1" },
            data: { savedItemId: "s2", note: null },
          },
        ],
      ]);

      await createCollections({ transport: t }).remindDue().orThrow();
      expect(t.calls[1]?.[1]).toEqual({ max_rows: null });
      expect(sent).toHaveLength(2);
    });

    it("fails remindDue with the notifier's error", async () => {
      const t = transport({ remind_due_saved_items: () => [SAVED] });
      const error = { kind: "unexpected", message: "down", status: 500 };

      const result = await createCollections({
        transport: t,
        notifier: { send: () => ({ ok: false, error }) },
        notification: "saved_item_reminder",
      }).remindDue();

      expect(result.ok).toBe(false);
      expect(result.ok ? undefined : result.error.message).toBe("down");

      const ignored = await createCollections({
        transport: t,
        notifier: { send: () => ({ ok: false, error: "not a DbError" }) },
        notification: "saved_item_reminder",
      }).remindDue();

      expect(ignored.ok).toBe(true);
    });
  });
});
