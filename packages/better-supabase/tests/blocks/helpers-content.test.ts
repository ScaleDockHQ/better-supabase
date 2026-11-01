import { describe, expect, it } from "vitest";

import { createReactions } from "../../src/blocks/reactions/index.ts";
import { createRelations } from "../../src/blocks/relations/index.ts";
import { createTags } from "../../src/blocks/tags/index.ts";
import { fieldsTransport } from "./fields-transport.ts";

const RECORD = { type: "customer", id: "c1" };

describe("tags.replace", () => {
  it("attaches the missing tags and detaches the others", async () => {
    const t = fieldsTransport({
      subject_tags: () => [
        { id: "t1", name: "VIP", slug: "vip" },
        { id: "t2", name: "Churn", slug: "churn" },
      ],
      tag: () => true,
      untag: () => true,
    });

    const tags = createTags({ transport: t, tenant: "o" });

    const changed = await tags
      .replace({ record: RECORD, tagIds: ["t1", "t3"] })
      .orThrow();

    expect(changed).toEqual({ attached: 1, detached: 1 });
    expect(t.calls.map(([fn, args]) => [fn, args["tag_id"]])).toEqual([
      ["subject_tags", undefined],
      ["tag", "t3"],
      ["untag", "t2"],
    ]);
  });
});

describe("reactions.toggle", () => {
  it("removes a reaction the caller already made", async () => {
    const t = fieldsTransport({
      reaction_summary: () => ({
        c1: [{ emoji: "+1", count: 1, reacted: true, actors: [] }],
      }),
      react: () => [],
    });

    const reactions = createReactions({ transport: t, tenant: "o" });

    await reactions.toggle({ subject: RECORD, emoji: "+1" }).orThrow();

    expect(t.calls[1]?.[1]).toMatchObject({ emoji: "+1", present: false });
  });

  it("adds a reaction the caller has not made", async () => {
    const t = fieldsTransport({
      reaction_summary: () => ({}),
      react: () => [],
    });

    const reactions = createReactions({ transport: t, tenant: "o" });

    await reactions.toggle({ subject: RECORD, emoji: "+1" }).orThrow();

    expect(t.calls[1]?.[1]).toMatchObject({ present: true });
  });
});

describe("relations.walk", () => {
  it("walks up through ancestors and down through descendants", async () => {
    const t = fieldsTransport({ ancestors: () => [], descendants: () => [] });

    const relations = createRelations({ transport: t, tenant: "o" });

    await relations
      .walk({ subject: RECORD, kind: "parent", direction: "up" })
      .orThrow();
    await relations
      .walk({ subject: RECORD, kind: "parent", direction: "down" })
      .orThrow();

    expect(t.calls.map(([fn]) => fn)).toEqual(["ancestors", "descendants"]);
  });
});
