import { describe, expect, it, vi } from "vitest";

import type { ExecuteResult, Executor } from "../../src/core/executor.ts";
import type { Operation } from "../../src/ir/types.ts";

import { batchingExecutor } from "../../src/core/batch.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { definePlugin } from "../../src/core/plugin.ts";
import { defineReadSet, readSetTables } from "../../src/core/read-set.ts";
import { ok, type Result } from "../../src/core/result.ts";
import { tenant } from "../../src/plugins/tenant/index.ts";
import { compileReadSet, compileReadSets } from "../../src/sql/read-sets.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);
const USER = "00000000-0000-0000-0000-000000000001";

const chrome = defineReadSet(
  betterSupabase,
  "app_chrome",
  { params: { organizationId: "uuid", kinds: "text[]", search: "text" } },
  (s, p) => ({
    customers: s.customers.findMany({
      select: ["id", "name"],
      where: { organizationId: p.organizationId, name: { contains: p.search } },
      orderBy: { name: "asc" },
      limit: 5,
    }),
    calls: s.notes.count({
      where: {
        organizationId: p.organizationId,
        kind: { in: p.kinds as readonly ("call" | "email")[] },
      },
    }),
    first: s.customers.findFirst({
      select: ["id"],
      where: { organizationId: p.organizationId, status: "active" },
    }),
  }),
);

function fakeExecutor(): Executor & {
  batches: Operation[][];
  executed: Operation[];
} {
  const batches: Operation[][] = [];
  const executed: Operation[] = [];
  const answer = (op: Operation): Result<ExecuteResult> =>
    ok({
      rows: op.kind === "select" && op.head ? [] : [{ id: op.table.key }],
      count: 3,
    });
  return {
    name: "fake",
    batches,
    executed,
    execute: async (op) => {
      executed.push(op);
      return answer(op);
    },
    batch: async (ops) => {
      batches.push([...ops]);
      return ops.map(answer);
    },
  };
}

describe("defineReadSet", () => {
  it("rejects names that are not snake_case", () => {
    expect(() =>
      defineReadSet(betterSupabase, "App-Chrome", {}, (s) => ({
        all: s.tags.count(),
      })),
    ).toThrow(/snake_case/);
  });

  it("rejects parameter types that are not plain type names", () => {
    expect(() =>
      defineReadSet(
        betterSupabase,
        "typed",
        { params: { id: "uuid); drop table x; --" as "uuid" } },
        (s) => ({ all: s.tags.count() }),
      ),
    ).toThrow(/invalid type/);
  });

  it("rejects entries that are not specs", () => {
    expect(() =>
      defineReadSet(betterSupabase, "broken", {}, () => ({
        nope: {} as never,
      })),
    ).toThrow(/not a spec/);
  });

  it("warns when runtime plugins scope tables the generated function reads", () => {
    const warn = vi.fn();
    const logger = { debug() {}, info() {}, warn, error() {} };
    const scoped = defineSupabase(schema, { logger }).use(tenant());
    defineReadSet(scoped, "scoped", {}, (s) => ({
      customers: s.customers.count(),
    }));
    expect(warn).toHaveBeenCalledOnce();
    expect(warn.mock.calls[0]?.[0]).toContain(
      'read set "scoped" reads customers, which tenant scope at runtime',
    );
    defineReadSet(defineSupabase(schema, { logger }), "plain", {}, (s) => ({
      customers: s.customers.count(),
    }));
    expect(warn).toHaveBeenCalledOnce();
  });

  it("names plugins by the flags they declare in scopes", () => {
    const warn = vi.fn();
    const logger = { debug() {}, info() {}, warn, error() {} };
    const transformQuery = (op: Operation): Operation => op;
    const inspector = definePlugin({
      name: "inspector",
      scopes: [],
      transformQuery,
    });
    const versioned = definePlugin({
      name: "versioned",
      scopes: ["version"],
      transformQuery,
    });
    const opaque = definePlugin({ name: "opaque", transformQuery });
    const base = defineSupabase(schema, { logger });
    defineReadSet(base.use(inspector).use(versioned), "quiet", {}, (s) => ({
      tags: s.tags.count(),
    }));
    expect(warn).not.toHaveBeenCalled();
    defineReadSet(base.use(inspector).use(opaque), "loud", {}, (s) => ({
      tags: s.tags.count(),
    }));
    expect(warn.mock.calls[0]?.[0]).toContain(
      'read set "loud" reads tags, which opaque scope at runtime',
    );
  });

  it("lists every table the set reads", () => {
    expect(readSetTables(chrome).sort()).toEqual(["customers", "notes"]);
  });
});

describe("compileReadSet", () => {
  it("writes a stable, security invoker function that reads p", async () => {
    const { sql } = await compileReadSet(chrome);
    expect(sql).toContain(
      "create or replace function public.rs_app_chrome(p jsonb)",
    );
    expect(sql).toContain(
      "language sql stable security invoker set search_path = ''",
    );
    expect(sql).toContain("((p->>'organizationId')::uuid)");
    expect(sql).toContain(
      "(array(select jsonb_array_elements_text(p->'kinds'))::text[])",
    );
    expect(sql).toContain("('%' || (p->>'search') || '%')");
    expect(sql).toContain("'active'");
    expect(sql).not.toMatch(/\$\d/);
    expect(sql).toContain(
      "grant execute on function public.rs_app_chrome(jsonb) to authenticated;",
    );
    expect(sql).not.toContain("to anon");
  });

  it("grants the roles the set lists", async () => {
    const open = defineReadSet(
      betterSupabase,
      "open",
      { roles: ["anon"] },
      (s) => ({
        tags: s.tags.count(),
      }),
    );
    expect((await compileReadSet(open)).sql).toContain(
      "grant execute on function public.rs_open(jsonb) to anon;",
    );
  });

  it("refuses a placeholder used as the wrong shape", async () => {
    const wrong = defineReadSet(
      betterSupabase,
      "wrong",
      { params: { id: "uuid" } },
      (s, p) => ({
        one: s.customers.count({ where: { id: { in: [p.id] } } }),
      }),
    );
    await expect(compileReadSet(wrong)).rejects.toThrow(/used as/);
  });

  it("inlines booleans, numbers, instants and escaped lists", async () => {
    const at = Temporal.Instant.from("2026-01-02T03:04:05Z");
    const set = defineReadSet(betterSupabase, "literals", {}, (s) => ({
      primary: s.locations.count({
        where: { isPrimary: true, city: { notIn: ['a"b', "c\\d"] } },
      }),
      secondary: s.locations.count({ where: { isPrimary: false } }),
      recent: s.customers.count({
        where: {
          createdAt: { gte: at as never },
          kvk: { in: [null, at] as never },
          name: { in: [12 as never, 10n as never] },
        },
      }),
    }));
    const { sql } = await compileReadSet(set);
    expect(sql).toContain("true");
    expect(sql).toContain("false");
    expect(sql).toContain("'2026-01-02T03:04:05Z'");
    expect(sql).toContain(String.raw`{"a\"b","c\\d"}`);
    expect(sql).toContain('{NULL,"2026-01-02T03:04:05Z"}');
    expect(sql).toContain('{"12","10"}');
    expect(sql).not.toMatch(/\$\d/);
  });

  it("writes an empty entry for a filter that matches nothing", async () => {
    const set = defineReadSet(betterSupabase, "nothing", {}, (s) => ({
      none: s.customers.findMany({ where: { id: { in: [] } } }),
    }));
    expect((await compileReadSet(set)).sql).toContain(
      "jsonb_build_object('rows', '[]'::jsonb, 'count', 0)",
    );
  });

  it("refuses values it cannot inline", async () => {
    const infinite = defineReadSet(betterSupabase, "infinite", {}, (s) => ({
      one: s.customers.count({ where: { name: Infinity as never } }),
    }));
    await expect(compileReadSet(infinite)).rejects.toThrow(/Cannot inline/);
    const nested = defineReadSet(
      betterSupabase,
      "nested",
      { params: { id: "uuid" } },
      (s, p) => ({
        one: s.customers.count({
          where: { id: { in: [p.id, "x"] } },
        }),
      }),
    );
    await expect(compileReadSet(nested)).rejects.toThrow(
      /inside a literal list/,
    );
  });

  it("refuses a placeholder for an unknown parameter", async () => {
    const set = defineReadSet(
      betterSupabase,
      "unknown_param",
      { params: { id: "uuid" } },
      (s, p) => ({ one: s.customers.count({ where: { id: p.id } }) }),
    );
    await expect(compileReadSet({ ...set, params: {} })).rejects.toThrow(
      /no parameter "id"/,
    );
  });

  it("refuses an entry for an unknown table", async () => {
    const set = defineReadSet(betterSupabase, "unknown_table", {}, (s) => ({
      one: s.tags.count(),
    }));
    const broken = {
      ...set,
      specs: { one: { ...set.specs.one, table: "nope" } },
    };
    await expect(compileReadSet(broken)).rejects.toThrow(
      /unknown table "nope"/,
    );
  });

  it("refuses a body that holds the dollar-quote tag", async () => {
    const set = defineReadSet(betterSupabase, "tagged", {}, (s) => ({
      one: s.customers.count({ where: { name: "$rs$" } }),
    }));
    await expect(compileReadSet(set)).rejects.toThrow(/contains "\$rs\$"/);
  });
});

describe("compileReadSets", () => {
  const a = defineReadSet(betterSupabase, "b_set", {}, (s) => ({
    one: s.tags.count(),
  }));
  const b = defineReadSet(betterSupabase, "a_set", {}, (s) => ({
    one: s.tags.count(),
  }));

  it("compiles each set once, sorted by name", async () => {
    const compiled = await compileReadSets([a, b, a]);
    expect(compiled.map((set) => set.name)).toEqual(["a_set", "b_set"]);
  });

  it("throws on two sets with the same name", async () => {
    const twin = defineReadSet(betterSupabase, "b_set", {}, (s) => ({
      one: s.notes.count(),
    }));
    await expect(compileReadSets([a, twin])).rejects.toThrow(
      /Two read sets are named "b_set"/,
    );
  });
});

describe("db.$many over PostgREST", () => {
  it("runs a read set as one GET and decodes each entry", async () => {
    const { client, requests } = capturingClient(() => ({
      body: {
        customers: { rows: [{ id: "c1", name: "Acme" }], count: null },
        calls: { rows: [], count: 4 },
        first: { rows: [], count: null },
      },
    }));
    const db = betterSupabase.connect(client);
    const result = await db.$many(chrome, {
      organizationId: USER,
      kinds: ["call"],
      search: "ac",
    });
    expect(result.ok && result.data).toEqual({
      customers: [{ id: "c1", name: "Acme" }],
      calls: 4,
      first: null,
    });
    expect(requests).toHaveLength(1);
    expect(requests[0]!.method).toBe("GET");
    expect(requests[0]!.path).toBe("/rest/v1/rpc/rs_app_chrome");
    expect(JSON.parse(requests[0]!.params.get("p")!)).toEqual({
      organizationId: USER,
      kinds: ["call"],
      search: "ac",
    });
    expect(db.$stats().calls).toBe(1);
  });

  it("fails without calling the database when a parameter is missing", async () => {
    const { client, requests } = capturingClient();
    const result = await betterSupabase
      .connect(client)
      .$many(chrome, { organizationId: USER } as never);
    expect(!result.ok && result.error.kind).toBe("invalid_request");
    expect(requests).toHaveLength(0);
  });

  it("runs ad-hoc specs in parallel and returns a tuple", async () => {
    const { client, requests } = capturingClient((request) =>
      request.path.endsWith("/tags")
        ? { body: [{ id: "t1" }] }
        : { body: [], headers: { "content-range": "*/7" } },
    );
    const db = betterSupabase.connect(client);
    const result = await db.$many([
      betterSupabase.spec.tags.findMany({ select: ["id"] }),
      betterSupabase.spec.notes.count(),
    ]);
    expect(result.ok && result.data).toEqual([[{ id: "t1" }], 7]);
    expect(requests).toHaveLength(2);
    expect(db.$stats().waves).toBe(1);
  });
});

describe("db.$many with Executor.batch", () => {
  it("sends ad-hoc specs as one batch", async () => {
    const executor = fakeExecutor();
    const result = await betterSupabase
      .connect(executor)
      .$many([
        betterSupabase.spec.tags.findMany({ select: ["id"] }),
        betterSupabase.spec.notes.count(),
      ]);
    expect(result.ok && result.data).toEqual([[{ id: "tags" }], 3]);
    expect(executor.batches).toHaveLength(1);
    expect(executor.batches[0]!.map((op) => op.table.key)).toEqual([
      "tags",
      "notes",
    ]);
    expect(executor.executed).toHaveLength(0);
  });

  it("binds read-set parameters instead of calling a function", async () => {
    const executor = fakeExecutor();
    const result = await betterSupabase.connect(executor).$many(chrome, {
      organizationId: USER,
      kinds: ["call", "email"],
      search: "ac",
    });
    expect(result.ok).toBe(true);
    expect(executor.batches).toHaveLength(1);
    const text = JSON.stringify(executor.batches[0]);
    expect(text).toContain(USER);
    expect(text).toContain("email");
    expect(text).not.toContain("\\u0000");
  });
});

describe("batchingExecutor", () => {
  it("waits for every reader, and batches a second round separately", async () => {
    const executor = fakeExecutor();
    const batcher = batchingExecutor(
      executor as Executor & { batch: NonNullable<Executor["batch"]> },
      2,
    );
    const op = await captureOp();
    const context = { errorMappers: [] };
    const first = (async () => {
      await batcher.executor.execute(op, context);
      await batcher.executor.execute(op, context);
      batcher.done();
    })();
    const second = (async () => {
      await batcher.executor.execute(op, context);
      batcher.done();
    })();
    await Promise.all([first, second]);
    expect(executor.batches.map((batch) => batch.length)).toEqual([2, 1]);
  });
});

async function captureOp(): Promise<Operation> {
  let seen: Operation | undefined;
  await betterSupabase
    .connect({
      name: "capture",
      execute: async (op) => {
        seen = op;
        return ok({ rows: [], count: 0 });
      },
    })
    .tags.count();
  return seen!;
}
