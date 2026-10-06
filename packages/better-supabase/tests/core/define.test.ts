import { describe, expect, it, onTestFinished, vi } from "vitest";

import type {
  ExecuteContext,
  ExecuteResult,
  Executor,
  RpcContext,
} from "../../src/core/executor.ts";
import type { AnyPlugin } from "../../src/core/plugin.ts";
import type { StandardSchemaV1 } from "../../src/core/standard.ts";
import type { Operation } from "../../src/ir/types.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { defineReadSet } from "../../src/core/read-set.ts";
import { err, ok, type Result } from "../../src/core/result.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);
const timeout = dbError("timeout", "slow");

interface Fake extends Executor {
  readonly ops: Operation[];
  readonly contexts: ExecuteContext[];
  readonly calls: { name: string; args: unknown; context: RpcContext }[];
}

function fake(
  options: {
    answer?: (op: Operation) => Result<ExecuteResult>;
    rpc?: (name: string, args: unknown) => Result<unknown>;
    functionSources?: boolean;
  } = {},
): Fake {
  const ops: Operation[] = [];
  const contexts: ExecuteContext[] = [];
  const calls: Fake["calls"] = [];
  return {
    name: "fake",
    ops,
    contexts,
    calls,
    ...(options.functionSources ? { functionSources: true } : {}),
    async execute(op, context) {
      ops.push(op);
      contexts.push(context);
      return options.answer ? options.answer(op) : ok({ rows: [], count: 0 });
    },
    ...(options.rpc
      ? {
          rpc: async (
            name: string,
            args: Readonly<Record<string, unknown>>,
            context: RpcContext,
          ) => {
            calls.push({ name, args, context });
            return options.rpc?.(name, args) ?? ok(null);
          },
        }
      : {}),
  };
}

const numberSchema: StandardSchemaV1<unknown, number> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) =>
      typeof value === "number"
        ? { value }
        : { issues: [{ message: "Expected a number" }] },
  },
};

describe("use", () => {
  it("rejects a plugin for another API version", () => {
    const plugin = { apiVersion: 2, name: "future" } as unknown as AnyPlugin;
    expect(() => betterSupabase.use(plugin)).toThrow(
      'better-supabase: plugin "future" targets plugin API v2; this version supports v1',
    );
  });

  it("rejects a plugin installed twice", () => {
    const plugin: AnyPlugin = { apiVersion: 1, name: "twice" };
    expect(() => betterSupabase.use(plugin).use(plugin)).toThrow(
      'better-supabase: plugin "twice" is already installed',
    );
  });

  it("rejects a plugin method that redefines a repository method", () => {
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "clash",
      repository: () => ({ findMany: () => 1 }),
    };
    const db = betterSupabase.use(plugin).connect(fake());
    expect(() => db.customers).toThrow(
      'better-supabase: plugin "clash" redefines "customers.findMany"',
    );
  });
});

describe("connect", () => {
  it("hands the configured clock and plugin error mappers to the runtime", async () => {
    const now = Temporal.Instant.from("2026-05-01T00:00:00Z");
    const seen: Temporal.Instant[] = [];
    const mapError = () => undefined;
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "clock",
      mapError,
      transformQuery: (op, args) => {
        seen.push(args.now());
        return op;
      },
    };
    const executor = fake();
    await defineSupabase(schema, { now: () => now })
      .use(plugin)
      .connect(executor)
      .tags.count();
    expect(seen).toEqual([now]);
    expect(executor.contexts[0]?.errorMappers).toEqual([mapError]);
  });

  it("defaults the clock to the current time", async () => {
    const now = Temporal.Instant.from("2026-05-01T12:00:00Z");
    vi.useFakeTimers({ now: now.epochMilliseconds });
    onTestFinished(() => {
      vi.useRealTimers();
    });
    const seen: Temporal.Instant[] = [];
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "clock",
      transformQuery: (op, args) => {
        seen.push(args.now());
        return op;
      },
    };
    await betterSupabase.use(plugin).connect(fake()).tags.count();
    expect(seen).toEqual([now]);
  });

  it("rejects an unknown table in $table", () => {
    const db = betterSupabase.connect(fake());
    expect(db.$table("tags")).toBe(db.tags);
    expect(() => db.$table("nope" as never)).toThrow(
      /^better-supabase: unknown table "nope"\. Known: contacts, customerTags, customers/,
    );
  });

  it("extends a repository with methods built on it", async () => {
    const db = betterSupabase.connect(
      fake({ answer: () => ok({ rows: [], count: 9 }) }),
    );
    const extended = db.tags.extend((base) => ({
      total: () => base.count(),
    }));
    expect(await extended.total()).toEqual(ok(9));
    expect(typeof extended.findMany).toBe("function");
  });

  it("leaves plugin methods that return plain values alone under mapError", () => {
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "plain",
      repository: () => ({ label: () => "tags" }),
    };
    const db = betterSupabase
      .use(plugin)
      .mapError(() => new Error("mapped"))
      .connect(fake()) as unknown as { tags: { label: () => string } };
    expect(db.tags.label()).toBe("tags");
  });
});

describe("$run", () => {
  it("rejects a value that is not a spec", async () => {
    expect(
      await betterSupabase.connect(fake()).$run({ v: 1 } as never),
    ).toEqual(
      err(
        dbError(
          "invalid_request",
          "db.$run() expects a QuerySpec from betterSupabase.spec",
        ),
      ),
    );
  });

  it("rejects a spec for an unknown table", async () => {
    const spec = { v: 1, table: "nope", method: "findMany", args: [] };
    expect(await betterSupabase.connect(fake()).$run(spec as never)).toEqual(
      err(dbError("invalid_request", 'Unknown table "nope" in QuerySpec')),
    );
  });

  it("rejects a read-set spec that still holds placeholders", async () => {
    const set = defineReadSet(
      betterSupabase,
      "by_organization",
      { params: { organizationId: "uuid" } },
      (s, p) => ({
        tags: s.tags.count({ where: { organizationId: p.organizationId } }),
      }),
    );
    const result = await betterSupabase.connect(fake()).$run(set.specs.tags);
    expect(result.error?.message).toBe(
      "This spec comes from a read set and still holds placeholders; run it with db.$many(readSet, params)",
    );
  });

  it.each([
    ["findById", betterSupabase.spec.tags.findById("t1")],
    ["findMany", betterSupabase.spec.tags.findMany({ select: ["id"] })],
  ] as const)(
    "passes the signal into the options of %s",
    async (_name, spec) => {
      const executor = fake({
        answer: () => ok({ rows: [{ id: "t1" }], count: null }),
      });
      const controller = new AbortController();
      await betterSupabase
        .connect(executor)
        .$run(spec, { signal: controller.signal });
      expect(executor.contexts[0]?.signal).toBe(controller.signal);
    },
  );
});

describe("$many", () => {
  it("rejects a value that is neither a list nor a read set", async () => {
    expect(await betterSupabase.connect(fake()).$many("tags" as never)).toEqual(
      err(
        dbError(
          "invalid_request",
          "db.$many() expects an array of specs or a read set",
        ),
      ),
    );
  });

  it("names the first entry that is not a spec", async () => {
    expect(
      await betterSupabase
        .connect(fake())
        .$many([betterSupabase.spec.tags.count(), {} as never]),
    ).toEqual(
      err(
        dbError(
          "invalid_request",
          "db.$many() entry 1 is not a QuerySpec from betterSupabase.spec",
        ),
      ),
    );
  });

  it("returns the first failing entry", async () => {
    const executor = fake({
      answer: (op) =>
        op.table.key === "notes" ? err(timeout) : ok({ rows: [], count: 1 }),
    });
    const result = await betterSupabase
      .connect(executor)
      .$many([
        betterSupabase.spec.tags.count(),
        betterSupabase.spec.notes.count(),
      ]);
    expect(result.error).toEqual({ ...timeout, table: "notes" });
  });

  it("runs a single spec through the connected plugins", async () => {
    const seen: string[] = [];
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "spy",
      transformQuery: (op) => {
        seen.push(op.table.key);
        return op;
      },
    };
    const result = await betterSupabase
      .use(plugin)
      .connect(fake())
      .$many([betterSupabase.spec.tags.count()]);
    expect(result).toEqual(ok([0]));
    expect(seen).toEqual(["tags"]);
  });
});

describe("$many with a read set", () => {
  const set = defineReadSet(
    betterSupabase,
    "chrome",
    { params: { organizationId: "uuid" } },
    (s, p) => ({
      tags: s.tags.findMany({
        select: ["id"],
        where: { organizationId: p.organizationId },
      }),
      tag: s.tags.findById(p.organizationId, { select: ["id"] }),
    }),
  );
  const params = { organizationId: "o1" };

  it("calls the read-set function with the parameters", async () => {
    const executor = fake({
      rpc: () =>
        ok({
          tags: { rows: [{ id: "t1" }] },
          tag: { rows: [{ id: "t1" }], count: null },
        }),
    });
    const controller = new AbortController();
    expect(
      await betterSupabase
        .connect(executor)
        .$many(set, params, { signal: controller.signal }),
    ).toEqual(ok({ tags: [{ id: "t1" }], tag: { id: "t1" } }));
    expect(executor.calls).toEqual([
      {
        name: "rs_chrome",
        args: { p: params },
        context: {
          schema: "public",
          get: true,
          errorMappers: [],
          signal: controller.signal,
        },
      },
    ]);
  });

  it("passes a failed call through", async () => {
    const executor = fake({ rpc: () => err(timeout) });
    expect(await betterSupabase.connect(executor).$many(set, params)).toEqual(
      err(timeout),
    );
  });

  it.each<[string, unknown, string]>([
    [
      "a missing entry",
      { tags: { rows: [] } },
      'rs_chrome() returned no "tag". Run `better-supabase gen` and migrate.',
    ],
    [
      "nothing at all",
      null,
      'rs_chrome() returned no "tags". Run `better-supabase gen` and migrate.',
    ],
  ])("reports %s as unexpected", async (_name, payload, message) => {
    const executor = fake({ rpc: () => ok(payload) });
    expect(await betterSupabase.connect(executor).$many(set, params)).toEqual(
      err(dbError("unexpected", message)),
    );
  });

  it("returns an entry's own error, like findById without a row", async () => {
    const executor = fake({
      rpc: () => ok({ tags: { rows: null }, tag: { rows: [] } }),
    });
    const result = await betterSupabase.connect(executor).$many(set, params);
    expect(result.error).toMatchObject({ kind: "not_found", table: "tags" });
  });

  it("runs the bound specs when the executor has no rpc", async () => {
    const executor = fake({ answer: () => err(timeout) });
    const result = await betterSupabase.connect(executor).$many(set, params);
    expect(result.error).toEqual({ ...timeout, table: "tags" });
    expect(executor.ops.map((op) => op.table.key)).toEqual(["tags", "tags"]);
  });
});

describe("$search", () => {
  const vector = [0.1, 0.2];

  it("rejects an unknown table", async () => {
    expect(
      await betterSupabase
        .connect(fake({ functionSources: true }))
        .$search("nope" as never, { vector }),
    ).toEqual(
      err(dbError("invalid_request", 'db.$search(): unknown table "nope"')),
    );
  });

  it("rejects an executor without function sources", async () => {
    expect(
      await betterSupabase.connect(fake()).$search("notes", { vector }),
    ).toEqual(
      err(
        dbError(
          "invalid_request",
          "db.$search() reads from a function; the fake executor doesn't support that",
          { table: "notes" },
        ),
      ),
    );
  });

  it.each<[string, { vector: number[] | string; k?: number }]>([
    ["an empty vector", { vector: [] }],
    ["a non-finite vector", { vector: [Number.NaN] }],
    ["a malformed vector string", { vector: "0.1,0.2" }],
    ["a zero k", { vector, k: 0 }],
  ])("rejects %s", async (_name, args) => {
    expect(
      (
        await betterSupabase
          .connect(fake({ functionSources: true }))
          .$search("notes", args)
      ).error,
    ).toEqual(
      dbError(
        "invalid_input",
        "db.$search() needs a vector of finite numbers and a positive integer k",
        {
          table: "notes",
        },
      ),
    );
  });

  it("reads from the search function", async () => {
    const executor = fake({
      functionSources: true,
      answer: () => ok({ rows: [{ id: "1" }], count: null }),
    });
    expect(
      await betterSupabase.connect(executor).$search("notes", {
        vector: "[1,2]",
        k: 3,
        select: ["id"],
        where: { kind: "call" },
      }),
    ).toEqual(ok([{ id: "1" }]));
    expect(executor.ops[0]).toMatchObject({
      limit: 3,
      where: { kind: "column", column: "kind", op: "eq", value: "call" },
      source: {
        schema: "public",
        name: "search_notes",
        args: { query: "[1,2]", k: 3 },
      },
    });
  });

  it.each(["PGRST202", "42883"])(
    "hints at vectorSearch when the function is missing (%s)",
    async (code) => {
      const executor = fake({
        functionSources: true,
        answer: () => err(dbError("unexpected", "missing", { code })),
      });
      expect(
        (await betterSupabase.connect(executor).$search("notes", { vector }))
          .error?.hint,
      ).toBe(
        'Add "public.notes" to vectorSearch in better-supabase.config.ts (with prefilter or hybrid for filter and text) and run `better-supabase sql sync`.',
      );
    },
  );

  it("passes other errors through", async () => {
    const executor = fake({
      functionSources: true,
      answer: () => err(timeout),
    });
    expect(
      await betterSupabase.connect(executor).$search("notes", { vector }),
    ).toEqual(err({ ...timeout, table: "notes" }));
  });

  it("passes filter and text to the search function", async () => {
    const executor = fake({ functionSources: true });
    await betterSupabase.connect(executor).$search("notes", {
      vector,
      filter: { kind: ["call", null] },
      text: "renewal",
    });
    expect(executor.ops[0]).toMatchObject({
      source: {
        args: {
          query: "[0.1,0.2]",
          k: 10,
          filter: { kind: ["call", null] },
          text_query: "renewal",
        },
      },
    });
  });

  it("adds $score from the scores function, best first", async () => {
    const executor = fake({
      functionSources: true,
      answer: (op) =>
        op.kind === "select" && op.source?.name === "search_notes_scores"
          ? ok({
              rows: [
                { id: "b", score: 0.9 },
                { id: "a", score: "0.5" },
                { id: "gone", score: 0.4 },
                { id: "c", score: null },
              ],
              count: null,
            })
          : ok({ rows: [{ id: "a" }, { id: "b" }, { id: "x" }], count: null }),
    });
    const rows = await betterSupabase
      .connect(executor)
      .$search("notes", {
        vector,
        k: 3,
        score: true,
        select: ["id"],
        where: { kind: "call" },
      })
      .orThrow();
    expect(rows).toEqual([
      { id: "b", $score: 0.9 },
      { id: "a", $score: 0.5 },
    ]);
    expect(executor.ops[0]).toMatchObject({
      source: {
        schema: "public",
        name: "search_notes_scores",
        args: { query: "[0.1,0.2]", k: 3 },
      },
    });
    expect(executor.ops[1]).toMatchObject({ limit: 3 });
    expect(executor.ops[1]!).not.toHaveProperty("source");
  });

  it("needs a one-column primary key for scores", async () => {
    expect(
      (
        await betterSupabase
          .connect(fake({ functionSources: true }))
          .$search("customerTags", { vector, score: true })
      ).error?.message,
    ).toMatch(/one-column primary key/);
  });

  it("answers an empty list, hints and passes errors through", async () => {
    const empty = fake({ functionSources: true });
    expect(
      await betterSupabase
        .connect(empty)
        .$search("notes", { vector, score: true }),
    ).toEqual(ok([]));
    expect(empty.ops).toHaveLength(1);
    const missing = fake({
      functionSources: true,
      answer: () => err(dbError("unexpected", "missing", { code: "PGRST202" })),
    });
    expect(
      (
        await betterSupabase
          .connect(missing)
          .$search("notes", { vector, score: true })
      ).error?.hint,
    ).toContain("vectorSearch");
    const failing = fake({
      functionSources: true,
      answer: (op) =>
        op.kind === "select" && op.source
          ? ok({ rows: [{ id: "a", score: 1 }], count: null })
          : err(timeout),
    });
    expect(
      (
        await betterSupabase
          .connect(failing)
          .$search("notes", { vector, score: true })
      ).error,
    ).toMatchObject({ kind: timeout.kind });
  });
});

describe("$rpc", () => {
  it("fails on an executor without rpc", async () => {
    expect(
      await betterSupabase
        .connect(fake())
        .$rpc("search_notes" as never, {} as never),
    ).toEqual(
      err(dbError("invalid_request", 'Executor "fake" does not support rpc()')),
    );
  });

  it("calls the function with the schema and signal", async () => {
    const executor = fake({ rpc: () => ok(3) });
    const controller = new AbortController();
    const result = await betterSupabase
      .connect(executor)
      .$rpc("search_notes" as never, { q: 1 } as never, {
        schema: "api",
        signal: controller.signal,
      });
    expect(result).toEqual(ok(3));
    expect(executor.calls).toEqual([
      {
        name: "search_notes",
        args: { q: 1 },
        context: { schema: "api", errorMappers: [], signal: controller.signal },
      },
    ]);
  });

  it("defaults to the public schema and empty arguments", async () => {
    const executor = fake({ rpc: () => ok(null) });
    await betterSupabase
      .connect(executor)
      .$rpc("search_notes" as never, undefined as never);
    expect(executor.calls[0]).toMatchObject({
      args: {},
      context: { schema: "public" },
    });
  });

  it.each<[string, unknown, Result<unknown>]>([
    ["a valid result", 7, ok(7)],
    [
      "an invalid result",
      "seven",
      err(
        dbError("validation", "Invalid search_notes() result", {
          issues: [{ message: "Expected a number" }],
        }),
      ),
    ],
  ])("validates %s with returns", async (_name, value, expected) => {
    const executor = fake({ rpc: () => ok(value) });
    expect(
      await betterSupabase
        .connect(executor)
        .$rpc(
          "search_notes" as never,
          {} as never,
          { returns: numberSchema } as never,
        ),
    ).toEqual(expected);
  });

  it("skips validation when the call fails", async () => {
    const executor = fake({ rpc: () => err(timeout) });
    expect(
      await betterSupabase
        .connect(executor)
        .$rpc(
          "search_notes" as never,
          {} as never,
          { returns: numberSchema } as never,
        ),
    ).toEqual(err(timeout));
  });
});

describe("$rpc result decoding", () => {
  const row = {
    id: "c1",
    organization_id: "o1",
    primary_contact_id: null,
    created_at: "2026-01-01T00:00:00Z",
  };

  it("returns table rows in the configured casing", async () => {
    const executor = fake({ rpc: () => ok([row]) });
    const rows = await betterSupabase
      .connect(executor)
      .$rpc("customers_by_status", { p_status: "lead" })
      .orThrow();
    expect(rows).toEqual([
      {
        id: "c1",
        organizationId: "o1",
        primaryContactId: null,
        createdAt: "2026-01-01T00:00:00Z",
      },
    ]);
  });

  it("returns record columns in the configured casing and validates after", async () => {
    const executor = fake({
      rpc: () => ok([{ customer_id: "c1", note_count: 2, extra: true }]),
    });
    const seen: unknown[] = [];
    const returns: StandardSchemaV1<unknown, unknown> = {
      "~standard": {
        version: 1,
        vendor: "test",
        validate: (value) => {
          seen.push(value);
          return { value };
        },
      },
    };
    const rows = await betterSupabase
      .connect(executor)
      .$rpc("customer_note_counts", {}, { returns })
      .orThrow();
    expect(rows).toEqual([{ customerId: "c1", noteCount: 2, extra: true }]);
    expect(seen).toEqual([rows]);
  });

  it("leaves raw results, other schemas, scalars and json alone", async () => {
    const executor = fake({ rpc: () => ok([row]) });
    const db = betterSupabase.connect(executor);
    expect(
      await db
        .$rpc("customers_by_status", { p_status: "lead" }, { raw: true })
        .orThrow(),
    ).toEqual([row]);
    expect(
      await db
        .$rpc("customers_by_status", { p_status: "lead" }, { schema: "api" })
        .orThrow(),
    ).toEqual([row]);
    expect(await db.$rpc("rs_workspace_summary", { p: {} }).orThrow()).toEqual([
      row,
    ]);
  });

  it("decodes a single row and passes non-objects through", async () => {
    const executor = fake({ rpc: () => ok(row) });
    expect(
      await betterSupabase
        .connect(executor)
        .$rpc("customers_by_status", { p_status: "lead" })
        .orThrow(),
    ).toMatchObject({ organizationId: "o1" });
    const empty = fake({ rpc: () => ok([null, 3]) });
    expect(
      await betterSupabase
        .connect(empty)
        .$rpc("customers_by_status", { p_status: "lead" })
        .orThrow(),
    ).toEqual([null, 3]);
  });

  it("applies codecs and reports values they can't hold", async () => {
    const coded = defineSupabase(
      defineSchema({
        ...schema.meta,
        functions: {
          ...schema.meta.functions,
          customer_note_counts: {
            ...schema.meta.functions["customer_note_counts"]!,
            result: {
              columns: [
                { db: "note_count", name: "noteCount", codec: "bigint" },
                { db: "last_note_at", name: "lastNoteAt", codec: "instant" },
              ],
            },
          },
        },
      }),
    );
    const ok1 = await coded
      .connect(
        fake({
          rpc: () =>
            ok([{ note_count: 2, last_note_at: "2026-01-01T00:00:00Z" }]),
        }),
      )
      .$rpc("customer_note_counts", {})
      .orThrow();
    expect(ok1).toEqual([
      {
        noteCount: 2n,
        lastNoteAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
      },
    ]);
    const bad = await coded
      .connect(fake({ rpc: () => ok([{ last_note_at: "infinity" }]) }))
      .$rpc("customer_note_counts", {});
    expect(bad.error?.kind).toBe("invalid_value");
  });
});
