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
      if (!result) return Promise.reject(new Error(`unexpected ${fn}`));
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
      .create("o", {
        name: "Key accounts",
        subjectType: "company",
        scope: "team",
        teamId: "t1",
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
    await collections.create("o", { name: "x", subjectType: "company" });
    expect(t.calls[0]?.[1]).toMatchObject({ scope: "user", team: null });
    const renamed = await collections.rename("c1", { name: "y" }).orThrow();
    expect(renamed).toMatchObject({
      scope: "user",
      ownerId: "u1",
      description: "Q4",
      archived: true,
    });
    expect(renamed.archivedAt?.toString()).toBe("2026-10-15T09:00:00Z");
    await collections.rename("c1", { description: null });
    await collections.rename("c1", { description: "z" });
    expect(t.calls.slice(1, 4).map(([, args]) => args)).toEqual([
      { collection: "c1", name: "y", description: null },
      { collection: "c1", name: null, description: "" },
      { collection: "c1", name: null, description: "z" },
    ]);
    expect(await collections.archive("c1").orThrow()).toBe(true);
    expect(t.calls[4]?.[1]).toEqual({ collection: "c1", archived: true });
    expect(
      (await collections.list("o").orThrow()).map((list) => list.archived),
    ).toEqual([false, true]);
    await collections.list("o", {
      subjectType: "company",
      includeArchived: true,
    });
    expect(t.calls[6]?.[1]).toEqual({
      tenant: "o",
      subject_type: "company",
      include_archived: true,
    });
    expect(
      (await collections.listsOf({ type: "company", id: "a" }).orThrow())
        .length,
    ).toBe(1);
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
    expect(await collections.add("c1", ["a", "b"]).orThrow()).toEqual({
      added: ["a"],
    });
    expect(t.calls[0]?.[1]).toEqual({
      collection: "c1",
      subject_ids: ["a", "b"],
      subject_type: null,
    });
    expect(await collections.remove("c1", ["a", "b"]).orThrow()).toBe(2);
    const key = await collections.reorder("c1", "b", { next: "V" }).orThrow();
    expect(key < "V").toBe(true);
    expect((await collections.reorder("c1", "b", { previous: "!" })).ok).toBe(
      false,
    );

    const first = await collections.entries("c1", { limit: 2 }).orThrow();
    expect(first.next).toEqual({ rank: "k", subjectId: "b" });
    expect(first.items[0]).toMatchObject({ title: "Company a", addedBy: "u1" });
    expect(first.items[0]?.url).toBeUndefined();
    const second = await collections
      .entries("c1", { limit: 2, cursor: first.next! })
      .orThrow();
    expect(second.next).toBeUndefined();
    expect(t.calls.at(-1)?.[1]).toEqual({
      collection: "c1",
      after_rank: "k",
      after_id: "b",
      page_size: 2,
    });
    expect((await collections.entries("c1").orThrow()).next).toBeUndefined();

    expect(await collections.subjectIds("c1", { max: 10 }).orThrow()).toEqual([
      "b",
      "a",
    ]);
    expect(await collections.where("c1").orThrow()).toEqual({
      id: { in: ["b", "a"] },
    });
    expect(
      await collections.where("c1", { column: "company_id" }).orThrow(),
    ).toEqual({ company_id: { in: ["b", "a"] } });
  });

  it("reads an empty add result as nothing added", async () => {
    const t = transport({ add_collection_entries: () => null });
    expect(
      await createCollections({ transport: t }).add("c1", []).orThrow(),
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
    const star = await collections.star("o", deal).orThrow();
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
    const stars = await collections.starred("o", { type: "deal" }).orThrow();
    expect(stars[1]?.title).toBeUndefined();
    expect(t.calls[2]?.[1]).toEqual({ tenant: "o", subject_type: "deal" });
    await collections.starred("o");
    expect(t.calls[3]?.[1]).toEqual({ tenant: "o", subject_type: null });
    expect(
      await collections.reorderStar(deal, { previous: "V" }).orThrow(),
    ).toBe("k");
    expect((await collections.reorderStar(deal, { next: "!" })).ok).toBe(false);
  });
});
