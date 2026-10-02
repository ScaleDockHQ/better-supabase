import { describe, expect, it, vi } from "vitest";

import type {
  ExecuteContext,
  ExecuteResult,
  Executor,
} from "../../src/core/executor.ts";
import type { AnyPlugin } from "../../src/core/plugin.ts";
import type { Condition, Operation, SelectOp } from "../../src/ir/types.ts";

import { encodeCursor } from "../../src/core/cursor.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { DbException, dbError } from "../../src/core/errors.ts";
import { err, ok, type Result } from "../../src/core/result.ts";
import { schema } from "../fixtures/generated-camel.ts";

type Answer = (op: Operation, index: number) => Result<ExecuteResult>;

const rowsOf = (rows: Record<string, unknown>[], count: number | null = null) =>
  ok({ rows, count });

/** An executor that records every operation and answers from `answer`. */
function scripted(answer: Answer = () => rowsOf([])) {
  const ops: Operation[] = [];
  const contexts: ExecuteContext[] = [];
  const executor: Executor = {
    name: "scripted",
    async execute(op, context) {
      ops.push(op);
      contexts.push(context);
      return answer(op, ops.length - 1);
    },
  };
  const op = (index = 0): Operation => {
    const found = ops[index];
    if (!found) throw new Error(`No operation ${index}`);
    return found;
  };
  const select = (index = 0): SelectOp => {
    const found = op(index);
    if (found.kind !== "select") throw new Error("Expected a select");
    return found;
  };
  return { executor, ops, contexts, op, select };
}

function connect(answer?: Answer, plugins: AnyPlugin[] = []) {
  const fake = scripted(answer);
  let sb = defineSupabase(schema);
  for (const plugin of plugins) sb = sb.use(plugin);
  return { db: sb.connect(fake.executor), ...fake };
}

const col = (
  column: string,
  op: Extract<Condition, { kind: "column" }>["op"],
  value: unknown,
): Condition => ({ kind: "column", column, op, value });

const timeout = dbError("timeout", "slow", { code: "57014" });
const failing: Answer = () => err(timeout);
const timeoutResult = {
  ok: false,
  data: null,
  error: { ...timeout, table: "customers" },
};

describe("single-row reads", () => {
  it("returns null from findFirst and findUnique when nothing matches", async () => {
    const { db, select } = connect();
    expect(await db.customers.findFirst({ select: ["id"] })).toEqual(ok(null));
    expect(
      await db.customers.findUnique({ where: { id: "c1" }, select: ["id"] }),
    ).toEqual(ok(null));
    expect(select(0)).toMatchObject({
      limit: 1,
      where: undefined,
      orderBy: [],
    });
    expect(select(1)).toMatchObject({
      limit: 1,
      where: { kind: "and", items: [col("id", "eq", "c1")] },
    });
  });

  it("returns the first row", async () => {
    const { db } = connect(() => rowsOf([{ id: "a" }, { id: "b" }]));
    expect(await db.customers.findFirst({ select: ["id"] })).toEqual(
      ok({ id: "a" }),
    );
    expect(
      await db.customers.findUnique({ where: { id: "a" }, select: ["id"] }),
    ).toEqual(ok({ id: "a" }));
  });

  it.each(["findFirst", "findUnique", "findById", "findMany"] as const)(
    "passes executor errors through %s with the table",
    async (method) => {
      const { db } = connect(failing);
      const calls = {
        findFirst: () => db.customers.findFirst(),
        findUnique: () => db.customers.findUnique({ where: { id: "c1" } }),
        findById: () => db.customers.findById("c1"),
        findMany: () => db.customers.findMany(),
      };
      expect(await calls[method]()).toEqual(timeoutResult);
    },
  );

  it("keeps a table the executor already set", async () => {
    const { db } = connect(() =>
      err(dbError("timeout", "slow", { table: "notes" })),
    );
    expect((await db.customers.findMany()).error?.table).toBe("notes");
  });

  it("skips the default order for a table without a primary key", async () => {
    const tags = schema.meta.tables["tags"];
    if (!tags) throw new Error("No tags table");
    const keyless: typeof schema = {
      meta: {
        ...schema.meta,
        tables: { ...schema.meta.tables, tags: { ...tags, primaryKey: [] } },
      },
    };
    const fake = scripted();
    await defineSupabase(keyless)
      .connect(fake.executor)
      .tags.findMany({ select: ["id"] });
    expect(fake.select().orderBy).toEqual([]);
  });
});

describe("count, exists and aggregate", () => {
  it.each([
    [undefined, "exact"],
    ["planned", "planned"],
    ["estimated", "estimated"],
  ] as const)("counts with mode %s", async (mode, expected) => {
    const { db, select } = connect(() => rowsOf([], null));
    expect(
      await db.customers.count({
        where: { status: "lead" },
        ...(mode ? { mode } : {}),
      }),
    ).toEqual(ok(0));
    expect(select()).toMatchObject({
      count: expected,
      head: true,
      selection: { columns: [], includes: [] },
      where: col("status", "eq", "lead"),
    });
  });

  it("passes count errors through", async () => {
    const { db } = connect(failing);
    expect(await db.customers.count()).toEqual(timeoutResult);
  });

  it.each([
    [[{ id: "c1" }], true],
    [[], false],
  ])("exists reads one primary key column (%j)", async (rows, expected) => {
    const { db, select } = connect(() => rowsOf(rows));
    expect(await db.customers.exists({ where: { name: "Acme" } })).toEqual(
      ok(expected),
    );
    expect(select()).toMatchObject({
      selection: { columns: [{ alias: "id", column: "id" }], includes: [] },
      where: col("name", "eq", "Acme"),
      limit: 1,
    });
  });

  it("exists reads the first column of a composite key", async () => {
    const { db, select } = connect();
    await db.customerTags.exists();
    expect(select().selection.columns).toEqual([
      { alias: "customerId", column: "customer_id" },
    ]);
  });

  it("passes exists errors through", async () => {
    const { db } = connect(failing);
    expect(await db.customers.exists()).toEqual(timeoutResult);
  });

  it("rejects sorting an aggregate by a column outside groupBy", async () => {
    const { db, ops } = connect();
    expect(
      await db.customers.aggregate({
        groupBy: ["status"],
        _count: true,
        orderBy: { name: "asc" },
      }),
    ).toEqual({
      ok: false,
      data: null,
      error: {
        kind: "invalid_request",
        status: 400,
        message:
          'aggregate on "customers" can only sort by groupBy columns, not "name"',
        table: "customers",
      },
    });
    expect(ops).toHaveLength(0);
  });

  it("returns grouped rows with paging", async () => {
    const { db, select } = connect(() =>
      rowsOf([{ status: "lead", _count: 2 }]),
    );
    expect(
      await db.customers.aggregate({
        groupBy: ["status"],
        _count: true,
        orderBy: { status: "desc" },
        where: { kvk: null },
        limit: 5,
        offset: 10,
      }),
    ).toEqual(ok([{ status: "lead", _count: 2 }]));
    expect(select()).toMatchObject({
      orderBy: [{ column: "status", direction: "desc" }],
      where: col("kvk", "is", null),
      limit: 5,
      offset: 10,
    });
  });

  it("returns empty aggregates when the database returns no row", async () => {
    const { db } = connect();
    expect(
      await db.customers.aggregate({ _count: true, _max: { name: true } }),
    ).toEqual(ok({ _count: 0, _max: { name: null } }));
  });

  it("passes aggregate errors through", async () => {
    const { db } = connect(failing);
    expect(await db.customers.aggregate({ _count: true })).toEqual(
      timeoutResult,
    );
  });
});

describe("create and createMany", () => {
  it("returns null without returning", async () => {
    const { db, op } = connect(() => rowsOf([], 1));
    expect(
      await db.tags.create(
        { organizationId: "o", name: "vip" },
        { returning: false },
      ),
    ).toEqual(ok(null));
    expect(op()).toMatchObject({
      kind: "insert",
      returning: undefined,
      onConflict: undefined,
    });
  });

  it("returns null when no row comes back", async () => {
    const { db } = connect();
    expect(await db.tags.create({ organizationId: "o", name: "vip" })).toEqual(
      ok(null),
    );
  });

  it("passes create errors through", async () => {
    const { db } = connect(failing);
    expect(
      await db.customers.create({ organizationId: "o", name: "A" }),
    ).toEqual(timeoutResult);
  });

  it.each([
    [undefined, []],
    [{ returning: false as const }, { count: 0 }],
  ])("skips the database for no rows (%j)", async (args, expected) => {
    const { db, ops } = connect();
    expect(await db.tags.createMany([], args)).toEqual(ok(expected));
    expect(ops).toHaveLength(0);
  });

  it.each([
    [5, { count: 5 }],
    [null, { count: 2 }],
  ])(
    "counts inserted rows without returning (count %s)",
    async (count, expected) => {
      const { db } = connect(() => rowsOf([], count));
      const rows = [
        { organizationId: "o", name: "a" },
        { organizationId: "o", name: "b" },
      ];
      expect(await db.tags.createMany(rows, { returning: false })).toEqual(
        ok(expected),
      );
    },
  );

  it("returns the inserted rows", async () => {
    const { db, op } = connect(() => rowsOf([{ id: "t1" }]));
    expect(
      await db.tags.createMany([{ organizationId: "o", name: "a" }], {
        select: ["id"],
      }),
    ).toEqual(ok([{ id: "t1" }]));
    expect(op()).toMatchObject({ rows: [{ organization_id: "o", name: "a" }] });
  });

  it("passes createMany errors through", async () => {
    const { db } = connect(failing);
    expect(
      await db.customers.createMany([{ organizationId: "o", name: "A" }]),
    ).toEqual(timeoutResult);
  });
});

describe("update and updateMany", () => {
  it("returns the updated row", async () => {
    const { db, op } = connect(() => rowsOf([{ id: "c1", name: "B" }]));
    expect(
      await db.customers.update(
        "c1",
        { name: "B" },
        { select: ["id", "name"] },
      ),
    ).toEqual(ok({ id: "c1", name: "B" }));
    expect(op()).toMatchObject({
      kind: "update",
      set: { name: "B" },
      where: col("id", "eq", "c1"),
    });
  });

  it("returns null without returning when a row changed", async () => {
    const { db } = connect(() => rowsOf([], 1));
    expect(
      await db.customers.update("c1", { name: "B" }, { returning: false }),
    ).toEqual(ok(null));
  });

  it.each<[string, Answer]>([
    ["no returned row", () => rowsOf([])],
    ["a null count", () => rowsOf([], null)],
  ])("reports not_found for %s", async (_name, answer) => {
    const { db } = connect(answer);
    const result = await db.customers.update(
      "c1",
      { name: "B" },
      { returning: false },
    );
    expect(result.error).toMatchObject({
      kind: "not_found",
      message: "No customers row matched",
      table: "customers",
    });
  });

  it.each<[string, Answer]>([
    ["the row is gone", () => rowsOf([], 0)],
    [
      "the existence check fails",
      (_op, index) => (index === 0 ? rowsOf([], 0) : err(timeout)),
    ],
    ["the existence check has no count", () => rowsOf([], null)],
  ])("reports not_found with expect when %s", async (_name, answer) => {
    const { db, select } = connect(answer);
    const result = await db.customers.update(
      "c1",
      { name: "B" },
      { returning: false, expect: { updatedAt: "2026-01-01T00:00:00Z" } },
    );
    expect(result.error?.kind).toBe("not_found");
    expect(select(1)).toMatchObject({
      where: col("id", "eq", "c1"),
      count: "exact",
      head: true,
    });
  });

  it("reports a stale row with expect", async () => {
    const { db, op } = connect((_op, index) => rowsOf([], index === 0 ? 0 : 1));
    const result = await db.customers.update(
      "c1",
      { name: "B" },
      { returning: false, expect: { updatedAt: "2026-01-01T00:00:00Z" } },
    );
    expect(result.error).toEqual({
      kind: "stale",
      status: 412,
      message: "The customers row changed since it was read",
      table: "customers",
    });
    expect(op(0)).toMatchObject({
      where: {
        kind: "and",
        items: [
          col("id", "eq", "c1"),
          col("updated_at", "eq", "2026-01-01T00:00:00Z"),
        ],
      },
    });
  });

  it("passes update errors through", async () => {
    const { db } = connect(failing);
    expect(await db.customers.update("c1", { name: "B" })).toEqual(
      timeoutResult,
    );
  });

  it.each([
    [3, 3],
    [null, 0],
  ])("updateMany returns the count (%s)", async (count, expected) => {
    const { db, op } = connect(() => rowsOf([], count));
    expect(
      await db.customers.updateMany({
        where: { status: "lead" },
        data: { status: "active" },
      }),
    ).toEqual(ok({ count: expected }));
    expect(op()).toEqual({
      kind: "update",
      table: schema.meta.tables["customers"],
      set: { status: "active" },
      where: col("status", "eq", "lead"),
      returning: undefined,
    });
  });

  it("passes updateMany errors through", async () => {
    const { db } = connect(failing);
    expect(
      await db.customers.updateMany({ where: {}, data: { name: "B" } }),
    ).toEqual(timeoutResult);
  });
});

describe("upsert and upsertMany", () => {
  it.each<
    [
      string,
      Record<string, unknown> | undefined,
      { columns: string[]; action: string },
    ]
  >([
    [
      "the primary key by default",
      undefined,
      { columns: ["id"], action: "update" },
    ],
    [
      "the primary key by name",
      { onConflict: "primaryKey" },
      { columns: ["id"], action: "update" },
    ],
    [
      "a column list",
      { onConflict: ["organizationId", "kvk"], ignoreDuplicates: true },
      { columns: ["organization_id", "kvk"], action: "ignore" },
    ],
  ])("targets %s", async (_name, args, onConflict) => {
    const { db, op } = connect(() => rowsOf([{ id: "c1" }]));
    expect(
      await db.customers.upsert(
        { id: "c1", organizationId: "o", name: "A" },
        args as never,
      ),
    ).toEqual(ok({ id: "c1" }));
    expect(op()).toMatchObject({ kind: "insert", onConflict });
  });

  it.each<[string, unknown, string]>([
    [
      "an unknown unique key",
      "nope",
      'Unknown unique key "nope" on "customers"',
    ],
    ["a number", 3, 'Invalid onConflict on "customers"'],
  ])("rejects %s", async (_name, onConflict, message) => {
    const { db, ops } = connect();
    const result = await db.customers.upsert(
      { organizationId: "o", name: "A" },
      { onConflict: onConflict as never },
    );
    expect(result.error).toMatchObject({
      kind: "invalid_request",
      message,
      table: "customers",
    });
    expect(ops).toHaveLength(0);
  });

  it("returns null from upsert without returning or rows", async () => {
    const { db } = connect();
    expect(
      await db.customers.upsert(
        { organizationId: "o", name: "A" },
        { returning: false },
      ),
    ).toEqual(ok(null));
    expect(
      await db.customers.upsert({ organizationId: "o", name: "A" }),
    ).toEqual(ok(null));
  });

  it("passes upsert errors through", async () => {
    const { db } = connect(failing);
    expect(
      await db.customers.upsert({ organizationId: "o", name: "A" }),
    ).toEqual(timeoutResult);
  });

  it.each([
    [undefined, []],
    [{ returning: false as const }, { count: 0 }],
  ])(
    "upsertMany skips the database for no rows (%j)",
    async (args, expected) => {
      const { db, ops } = connect();
      expect(await db.tags.upsertMany([], args)).toEqual(ok(expected));
      expect(ops).toHaveLength(0);
    },
  );

  it.each([
    [4, { count: 4 }],
    [null, { count: 1 }],
  ])(
    "upsertMany counts without returning (count %s)",
    async (count, expected) => {
      const { db, op } = connect(() => rowsOf([], count));
      expect(
        await db.tags.upsertMany([{ organizationId: "o", name: "a" }], {
          returning: false,
          onConflict: "tags_organization_id_name_key",
        }),
      ).toEqual(ok(expected));
      expect(op()).toMatchObject({
        onConflict: { columns: ["organization_id", "name"], action: "update" },
        returning: undefined,
      });
    },
  );

  it("upsertMany returns the rows", async () => {
    const { db } = connect(() => rowsOf([{ id: "t1" }]));
    expect(
      await db.tags.upsertMany([{ organizationId: "o", name: "a" }]),
    ).toEqual(ok([{ id: "t1" }]));
  });

  it("passes upsertMany errors through", async () => {
    const { db } = connect(failing);
    expect(
      await db.customers.upsertMany([{ organizationId: "o", name: "A" }]),
    ).toEqual(timeoutResult);
  });
});

describe("delete and deleteMany", () => {
  it.each<[string, Answer, string]>([
    ["a count", () => rowsOf([], 1), "deleted"],
    [
      "returned rows without a count",
      () => rowsOf([{ id: "c1" }], null),
      "deleted",
    ],
    ["nothing", () => rowsOf([], null), "not_found"],
  ])("deletes by key and reads %s", async (_name, answer, outcome) => {
    const { db, op } = connect(answer);
    const result = await db.customers.delete("c1");
    expect(result.ok ? "deleted" : result.error.kind).toBe(outcome);
    expect(op()).toMatchObject({
      kind: "delete",
      where: col("id", "eq", "c1"),
      returning: { columns: [{ alias: "id", column: "id" }], includes: [] },
    });
  });

  it("passes delete errors through", async () => {
    const { db } = connect(failing);
    expect(await db.customers.delete("c1")).toEqual(timeoutResult);
  });

  it.each([{}, { where: {} }, { where: { name: undefined } }])(
    "deleteMany refuses an empty where (%j)",
    async (args) => {
      const { db, ops } = connect();
      expect(await db.customers.deleteMany(args as never)).toEqual({
        ok: false,
        data: null,
        error: {
          kind: "invalid_request",
          status: 400,
          message: 'deleteMany needs a non-empty "where"',
          table: "customers",
        },
      });
      expect(ops).toHaveLength(0);
    },
  );

  it.each([
    [2, 2],
    [null, 0],
  ])("deleteMany returns the count (%s)", async (count, expected) => {
    const { db, op } = connect(() => rowsOf([], count));
    expect(
      await db.customers.deleteMany({ where: { status: "lead" } }),
    ).toEqual(ok({ count: expected }));
    expect(op()).toMatchObject({
      kind: "delete",
      where: col("status", "eq", "lead"),
      returning: undefined,
    });
  });

  it("passes deleteMany errors through", async () => {
    const { db } = connect(failing);
    expect(
      await db.customers.deleteMany({ where: { status: "lead" } }),
    ).toEqual(timeoutResult);
  });
});

describe("offset pagination", () => {
  it.each<[string, Record<string, unknown>, string]>([
    ["a zero size", { size: 0 }, '"size" must be a positive integer'],
    ["a fractional size", { size: 1.5 }, '"size" must be a positive integer'],
    ["a missing size", {}, '"size" must be a positive integer'],
    ["a zero page", { size: 10, page: 0 }, '"page" must be a positive integer'],
    [
      "a fractional page",
      { size: 10, page: 1.5 },
      '"page" must be a positive integer',
    ],
  ])("rejects %s", async (_name, args, message) => {
    const { db, ops } = connect();
    expect((await db.customers.paginate(args as never)).error).toMatchObject({
      kind: "invalid_request",
      message,
      table: "customers",
    });
    expect(ops).toHaveLength(0);
  });

  it("starts at the first page without a total", async () => {
    const { db, select } = connect(() =>
      rowsOf([{ id: "a" }, { id: "b" }, { id: "c" }]),
    );
    expect(await db.customers.paginate({ select: ["id"], size: 2 })).toEqual(
      ok({
        items: [{ id: "a" }, { id: "b" }],
        page: { number: 1, size: 2, total: null, pages: null, hasMore: true },
      }),
    );
    expect(select()).toMatchObject({ limit: 3, offset: 0, count: undefined });
  });

  it.each([
    ["planned", 0, 1],
    ["estimated", 45, 5],
  ] as const)("reports %s totals", async (count, total, pages) => {
    const { db, select } = connect(() => rowsOf([], total));
    const result = await db.customers.paginate({
      select: ["id"],
      size: 10,
      page: 2,
      count,
    });
    expect(result.data?.page).toEqual({
      number: 2,
      size: 10,
      total,
      pages,
      hasMore: false,
    });
    expect(select()).toMatchObject({ limit: 11, offset: 10, count });
  });

  it("passes errors through", async () => {
    const { db } = connect(failing);
    expect(await db.customers.paginate({ size: 10 })).toEqual(timeoutResult);
  });
});

describe("cursor pagination", () => {
  it.each<[string, Record<string, unknown>, string]>([
    [
      "a zero size",
      { size: 0, after: null },
      '"size" must be a positive integer',
    ],
    ["an unreadable cursor", { size: 2, after: "%%%" }, "Invalid cursor"],
    [
      "a cursor that is not a list",
      { size: 2, after: "e30" },
      "Invalid cursor",
    ],
    [
      "a cursor of the wrong length",
      { size: 2, after: encodeCursor(["a", "b", "c"]) },
      "Invalid cursor",
    ],
  ])("rejects %s", async (_name, args, message) => {
    const { db, ops } = connect();
    expect((await db.customers.paginate(args as never)).error).toMatchObject({
      kind: "invalid_request",
      message,
    });
    expect(ops).toHaveLength(0);
  });

  it("adds sort columns it needs for the cursor and strips them", async () => {
    const { db, select } = connect(() =>
      rowsOf([
        { name: "C", id: "c3", createdAt: "2026-03-01" },
        { name: "B", id: "c2", createdAt: "2026-02-01" },
        { name: "A", id: "c1", createdAt: "2026-01-01" },
      ]),
    );
    const result = await db.customers.paginate({
      select: ["name"],
      orderBy: { createdAt: "desc" },
      size: 2,
      after: null,
    });
    expect(result).toEqual(
      ok({
        items: [{ name: "C" }, { name: "B" }],
        nextCursor: encodeCursor(["2026-02-01", "c2"]),
        hasMore: true,
      }),
    );
    expect(select()).toMatchObject({
      selection: {
        columns: [
          { alias: "name", column: "name" },
          { alias: "createdAt", column: "created_at" },
          { alias: "id", column: "id" },
        ],
      },
      orderBy: [
        { column: "created_at", direction: "desc" },
        { column: "id", direction: "desc" },
      ],
      limit: 3,
      offset: undefined,
      where: undefined,
    });
  });

  it("continues after a descending cursor", async () => {
    const { db, select } = connect(() =>
      rowsOf([{ id: "c1", createdAt: "2026-01-01" }]),
    );
    const result = await db.customers.paginate({
      select: ["id", "createdAt"],
      orderBy: { createdAt: "desc" },
      where: { status: "lead" },
      size: 2,
      after: encodeCursor(["2026-02-01", "c2"]),
    });
    expect(result).toEqual(
      ok({
        items: [{ id: "c1", createdAt: "2026-01-01" }],
        nextCursor: null,
        hasMore: false,
      }),
    );
    expect(select().where).toEqual({
      kind: "and",
      items: [
        col("status", "eq", "lead"),
        {
          kind: "or",
          items: [
            col("created_at", "lt", "2026-02-01"),
            {
              kind: "and",
              items: [
                col("created_at", "eq", "2026-02-01"),
                col("id", "lt", "c2"),
              ],
            },
          ],
        },
      ],
    });
  });

  it("orders by the primary key alone without orderBy", async () => {
    const { db, select } = connect(() => rowsOf([{ id: "a" }, { id: "b" }]));
    const result = await db.customers.paginate({
      select: ["id"],
      size: 1,
      after: encodeCursor(["0"]),
    });
    expect(result.data).toEqual({
      items: [{ id: "a" }],
      nextCursor: encodeCursor(["a"]),
      hasMore: true,
    });
    expect(select().where).toEqual(col("id", "gt", "0"));
  });

  it("passes errors through", async () => {
    const { db } = connect(failing);
    expect(await db.customers.paginate({ size: 2, after: null })).toEqual(
      timeoutResult,
    );
  });
});

describe("plugins and options", () => {
  it("fails with the table when a hook throws a DbException", async () => {
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "deny",
      transformQuery: () => {
        throw new DbException(dbError("forbidden", "Denied"));
      },
    };
    const { db, ops } = connect(undefined, [plugin]);
    expect(await db.customers.findMany()).toEqual({
      ok: false,
      data: null,
      error: {
        kind: "forbidden",
        status: 403,
        message: "Denied",
        table: "customers",
      },
    });
    expect(ops).toHaveLength(0);
  });

  it("turns any other hook error into an unexpected result", async () => {
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "broken",
      beforeMutation: () => {
        throw new TypeError("bug");
      },
    };
    const { db, ops } = connect(undefined, [plugin]);
    const result = await db.customers.deleteMany({ where: { status: "lead" } });
    expect(result.error).toMatchObject({ kind: "unexpected", message: "bug" });
    expect(ops).toHaveLength(0);
  });

  it("runs beforeMutation rewrites and logs afterMutation failures", async () => {
    const error = vi.fn();
    const logger = { debug() {}, info() {}, warn() {}, error };
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "audit",
      beforeMutation: (op) =>
        op.kind === "delete" ? { ...op, where: col("id", "eq", "forced") } : op,
      afterMutation: () => {
        throw new Error("audit down");
      },
    };
    const fake = scripted(() => rowsOf([], 1));
    const db = defineSupabase(schema, { logger })
      .use(plugin)
      .connect(fake.executor);
    expect(
      await db.customers.deleteMany({ where: { status: "lead" } }),
    ).toEqual(ok({ count: 1 }));
    expect(fake.op()).toMatchObject({ where: col("id", "eq", "forced") });
    expect(error).toHaveBeenCalledWith('plugin "audit" afterMutation threw', {
      cause: new Error("audit down"),
    });
  });

  it("reports upserts as upsert mutations and passes call options to hooks", async () => {
    const seen: unknown[] = [];
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "spy",
      transformQuery: (op, args) => {
        seen.push(args.options);
        return op;
      },
      afterMutation: (event) => {
        seen.push(event.kind);
      },
    };
    const fake = scripted(() => rowsOf([{ id: "c1" }]));
    const sb = defineSupabase(schema).use(plugin);
    const kinds: string[] = [];
    sb.on("mutation", (event) => kinds.push(event.kind));
    await sb
      .connect(fake.executor)
      .customers.upsert({ organizationId: "o", name: "A" }, {
        select: ["id"],
        audit: "x",
      } as never);
    expect(seen).toEqual([{ audit: "x" }, "upsert"]);
    expect(kinds).toEqual(["upsert"]);
  });

  it("hands the abort signal to the executor", async () => {
    const { db, contexts } = connect();
    const controller = new AbortController();
    await db.customers.findMany({ signal: controller.signal });
    await db.customers.findMany({ signal: "nope" as never });
    expect(contexts[0]?.signal).toBe(controller.signal);
    expect(contexts[1]).not.toHaveProperty("signal");
  });
});
