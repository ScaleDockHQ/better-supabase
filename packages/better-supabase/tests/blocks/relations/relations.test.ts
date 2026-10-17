import { describe, expect, it } from "vitest";

import {
  createRelations,
  type RelationEdge,
  toGanttTasks,
  toTreeItems,
} from "../../../src/blocks/relations/index.ts";
import { createUndo, isUndoToken } from "../../../src/blocks/undo/undo.ts";

function transport(results: Record<string, unknown>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      const result = results[fn];

      if (result instanceof Error) {
        return Promise.reject(result);
      }

      return Promise.resolve(result);
    },
  };
}

const ORG = "org-1";
const a = { type: "task", id: "a" };
const b = { type: "task", id: "b" };
const c = { type: "task", id: "c" };

const stored = (extra: Record<string, unknown>) => ({
  id: "r1",
  kind: "blocks",
  sourceType: "task",
  sourceId: "b",
  targetType: "task",
  targetId: "a",
  created: true,
  previousData: null,
  replaced: null,
  ...extra,
});

describe("relations client", () => {
  it("links and returns an undo token that unlinks the stored edge", async () => {
    const fake = transport({ link: stored({}) });
    const relations = createRelations({ transport: fake });

    const made = await relations
      .link({ organizationId: ORG, kind: "blocked_by", source: a, target: b })
      .orThrow();

    expect(fake.calls[0]).toEqual({
      fn: "link",
      args: {
        tenant: ORG,
        kind: "blocked_by",
        source_type: "task",
        source_id: "a",
        target_type: "task",
        target_id: "b",
        data: null,
      },
    });
    expect(made).toMatchObject({ kind: "blocks", source: b, target: a });
    expect(made.undo).toEqual({
      v: 1,
      calls: [
        {
          fn: "unlink",
          args: {
            tenant: ORG,
            kind: "blocks",
            source_type: "task",
            source_id: "b",
            target_type: "task",
            target_id: "a",
          },
        },
      ],
    });
  });

  it("puts a replaced target back on undo", async () => {
    const fake = transport({
      link: stored({
        kind: "parent",
        sourceId: "a",
        targetId: "c",
        replaced: { targetType: "task", targetId: "b", data: { x: 1 } },
      }),
    });

    const made = await createRelations({ transport: fake })
      .link({ organizationId: ORG, kind: "parent", source: a, target: c })
      .orThrow();

    expect(made.replaced).toEqual({ target: b, data: { x: 1 } });
    expect(made.undo?.calls.map((call) => call.fn)).toEqual(["unlink", "link"]);
    expect(made.undo?.calls[1]?.args).toMatchObject({
      target_id: "b",
      data: { x: 1 },
    });
  });

  it("restores the old data when a link only changed its data", async () => {
    const fake = transport({
      link: stored({ created: false, previousData: { lag: 1 } }),
    });

    const relations = createRelations({ transport: fake });

    const changed = await relations
      .link({
        organizationId: ORG,
        kind: "blocks",
        source: b,
        target: a,
        data: { lag: 2 },
      })
      .orThrow();

    expect(changed.undo?.calls).toEqual([
      expect.objectContaining({
        fn: "link",
        args: expect.objectContaining({ data: { lag: 1 } }),
      }),
    ]);
    const fakeSame = transport({ link: stored({ created: false }) });

    const same = await createRelations({ transport: fakeSame })
      .link({ organizationId: ORG, kind: "blocks", source: b, target: a })
      .orThrow();

    expect(same.undo).toBeNull();
  });

  it("unlinks with an undo that links again with the old data", async () => {
    const fake = transport({ unlink: { removed: true, data: { lag: 3 } } });
    const relations = createRelations({ transport: fake, schema: "app" });

    const gone = await relations
      .unlink({ organizationId: ORG, kind: "relates", source: a, target: b })
      .orThrow();

    expect(gone.undo?.calls[0]).toMatchObject({
      fn: "link",
      args: { kind: "relates", data: { lag: 3 } },
    });
    const fakeNone = transport({ unlink: { removed: false, data: null } });

    const none = await createRelations({ transport: fakeNone })
      .unlink({ organizationId: ORG, kind: "relates", source: a, target: b })
      .orThrow();

    expect(none).toEqual({ removed: false, undo: null });
  });

  it("reads links, edges, walks and rollups", async () => {
    const fake = transport({
      relations_of: [
        {
          id: "r1",
          kind: "blocked_by",
          direction: "in",
          type: "task",
          subjectId: "b",
          data: {},
          createdAt: "2026-10-13T00:00:00Z",
        },
      ],
      relations_by_kind: [stored({})],
      ancestors: [{ type: "task", id: "b", depth: 1 }],
      descendants: null,
      relation_rollup: 12,
    });

    const relations = createRelations({ transport: fake });
    expect(await relations.of(ORG, a).orThrow()).toEqual([
      {
        id: "r1",
        kind: "blocked_by",
        direction: "in",
        subject: b,
        data: {},
        createdAt: "2026-10-13T00:00:00Z",
        fields: {},
      },
    ]);
    expect(fake.calls[0]?.args).toMatchObject({ kind: null });
    expect(await relations.edges(ORG, "blocks").orThrow()).toEqual([
      { id: "r1", kind: "blocks", source: b, target: a, data: {}, fields: {} },
    ]);
    expect(await relations.ancestors(ORG, "parent", a).orThrow()).toEqual([
      { type: "task", id: "b", depth: 1 },
    ]);
    expect(await relations.descendants(ORG, "parent", a).orThrow()).toEqual([]);
    expect(
      await relations
        .rollup({
          organizationId: ORG,
          kind: "parent",
          subject: a,
          of: "task",
          agg: "sum",
          column: "estimate",
        })
        .orThrow(),
    ).toBe(12);
    expect(fake.calls.at(-1)?.args).toMatchObject({
      of_type: "task",
      column_name: "estimate",
      agg: "sum",
    });
  });
});

describe("undo tokens", () => {
  it("applies the calls in order and refuses other functions", async () => {
    const fake = transport({ unlink: { removed: true }, link: {} });
    const undo = createUndo({ transport: fake });

    const token = {
      v: 1,
      calls: [
        { fn: "unlink", args: { kind: "parent" } },
        { fn: "link", args: { kind: "parent" } },
      ],
    };

    expect(isUndoToken(token)).toBe(true);
    expect(await undo.apply(token).orThrow()).toBe(2);
    expect(fake.calls.map((call) => call.fn)).toEqual(["unlink", "link"]);

    const bad = await undo.apply({
      v: 1,
      calls: [{ fn: "drop_all", args: {} }],
    });

    expect(bad.ok).toBe(false);
    expect(isUndoToken({ v: 1, calls: [] })).toBe(false);
    expect(
      await createUndo({ transport: fake, allow: ["drop_all"] })
        .apply({ v: 1, calls: [{ fn: "drop_all", args: {} }] })
        .orThrow(),
    ).toBe(1);
  });

  it("stops at the first failing call", async () => {
    const fake = transport({ unlink: new Error("boom"), link: {} });

    const result = await createUndo({ transport: fake }).apply({
      v: 1,
      calls: [
        { fn: "unlink", args: {} },
        { fn: "link", args: {} },
      ],
    });

    expect(result.ok).toBe(false);
    expect(fake.calls).toHaveLength(1);
  });
});

describe("relation adapters", () => {
  const edge = (
    source: string,
    target: string,
    data: Record<string, unknown> = {},
  ): RelationEdge => ({
    id: `${source}-${target}`,
    kind: "blocks",
    source: { type: "task", id: source },
    target: { type: "task", id: target },
    data,
    fields: {},
  });

  it("turns blocks edges into Gantt dependencies", () => {
    const tasks = [
      { id: "a", name: "Design" },
      { id: "b", name: "Build" },
    ];

    expect(
      toGanttTasks(tasks, [
        edge("a", "b", { type: "SS", lag: 2 }),
        edge("a", "z"),
        edge("b", "a", { type: "nope", lag: "x" }),
      ]),
    ).toEqual([
      {
        id: "a",
        name: "Design",
        dependencies: [{ id: "b", type: "FS", lag: 0 }],
      },
      {
        id: "b",
        name: "Build",
        dependencies: [{ id: "a", type: "SS", lag: 2 }],
      },
    ]);
  });

  it("builds tree items from parent edges", () => {
    const items = [
      { id: "epic", name: "Epic" },
      { id: "one", name: "One" },
      { id: "two", name: "Two" },
    ];

    expect(
      toTreeItems(items, [
        edge("one", "epic"),
        edge("two", "epic"),
        edge("x", "epic"),
      ]),
    ).toEqual({
      root: { name: "", children: ["epic"] },
      epic: { name: "Epic", children: ["one", "two"] },
      one: { name: "One", children: [] },
      two: { name: "Two", children: [] },
    });
    expect(
      Object.keys(toTreeItems([], [], { rootId: "top", rootName: "All" })),
    ).toEqual(["top"]);
  });
});

describe("relations conversions", () => {
  it("reads the converted record and the lineage of created_from", async () => {
    const t = transport({
      converted_into: "q1",
      ancestors: [{ type: "deal", id: "d1", depth: 1 }],
      descendants: [{ type: "invoice", id: "i1", depth: 1 }],
    });

    const relations = createRelations({ transport: t });
    expect(
      await relations
        .convertedInto(ORG, { type: "deal", id: "d1" }, "quote")
        .orThrow(),
    ).toBe("q1");
    expect(
      await relations.lineage(ORG, { type: "quote", id: "q1" }).orThrow(),
    ).toEqual({
      origins: [{ type: "deal", id: "d1", depth: 1 }],
      conversions: [{ type: "invoice", id: "i1", depth: 1 }],
    });
    expect(t.calls.map((call) => [call.fn, call.args["kind"]])).toEqual([
      ["converted_into", undefined],
      ["ancestors", "created_from"],
      ["descendants", "created_from"],
    ]);
  });

  it("reads no conversion as undefined and stops the lineage on an error", async () => {
    const none = createRelations({
      transport: transport({ converted_into: null }),
    });

    expect(await none.convertedInto(ORG, a, "quote").orThrow()).toBeUndefined();
    const failing = transport({ ancestors: new Error("down") });
    expect(
      (await createRelations({ transport: failing }).lineage(ORG, a)).ok,
    ).toBe(false);
    expect(failing.calls.map((call) => call.fn)).toEqual(["ancestors"]);
  });
});
