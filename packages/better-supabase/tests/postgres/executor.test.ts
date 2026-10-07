import { describe, expect, it } from "vitest";

import type { ExecuteContext } from "../../src/core/executor.ts";
import type {
  DeleteOp,
  InsertOp,
  SelectOp,
  UpdateOp,
} from "../../src/ir/types.ts";

import { dbError } from "../../src/core/errors.ts";
import { IrBuilder } from "../../src/ir/build.ts";
import {
  fromPgError,
  postgresExecutor,
  type SqlClient,
} from "../../src/postgres/executor.ts";
import { fakeSql, pgError } from "../fixtures/fake-sql.ts";
import { schema } from "../fixtures/generated-camel.ts";

const builder = new IrBuilder(schema.meta);
const customers = builder.table("customers");
const context: ExecuteContext = { errorMappers: [] };

function select(overrides: Partial<SelectOp> = {}): SelectOp {
  return {
    kind: "select",
    table: customers,
    selection: builder.selection(customers, ["id", "name"], undefined),
    where: builder.where(customers, { name: "Acme" }),
    orderBy: [],
    limit: undefined,
    offset: undefined,
    count: undefined,
    head: false,
    single: undefined,
    ...overrides,
  };
}

function insert(overrides: Partial<InsertOp> = {}): InsertOp {
  return {
    kind: "insert",
    table: customers,
    rows: [{ name: "Acme", kvk: "1001" }],
    returning: builder.selection(customers, ["id"], undefined),
    onConflict: undefined,
    defaultToNull: false,
    ...overrides,
  };
}

const update = (overrides: Partial<UpdateOp> = {}): UpdateOp => ({
  kind: "update",
  table: customers,
  set: { status: "active" },
  where: builder.where(customers, { kvk: "1001" }),
  returning: undefined,
  ...overrides,
});

const remove = (overrides: Partial<DeleteOp> = {}): DeleteOp => ({
  kind: "delete",
  table: customers,
  where: builder.where(customers, { kvk: "1001" }),
  returning: builder.selection(customers, ["id"], undefined),
  ...overrides,
});

const rowsOf = (...rows: Record<string, unknown>[]) =>
  rows.map((row) => ({ row }));

describe("postgresExecutor", () => {
  it("names itself and honors function sources", () => {
    const executor = postgresExecutor(fakeSql().sql);
    expect(executor.name).toBe("postgres");
    expect(executor.functionSources).toBe(true);
  });

  it("unwraps the row column of a select and leaves count null", async () => {
    const fake = fakeSql([[/^select /, rowsOf({ id: "c1", name: "Acme" })]]);
    const result = await postgresExecutor(fake.sql).execute(select(), context);
    expect(result.ok && result.data).toEqual({
      rows: [{ id: "c1", name: "Acme" }],
      count: null,
    });
    expect(fake.calls).toHaveLength(1);
    expect(fake.calls[0]!.text).toMatch(
      /^select .* as row from "public"\."customers" as \w+ where /,
    );
    expect(fake.calls[0]!.values).toEqual(["Acme"]);
  });

  it("runs a separate count query when the select asks for a count", async () => {
    const fake = fakeSql([
      ["count(*)::int as count", [{ count: 42 }]],
      [/ as row from /, rowsOf({ id: "c1", name: "Acme" })],
    ]);
    const result = await postgresExecutor(fake.sql).execute(
      select({ count: "exact" }),
      context,
    );
    expect(result.ok && result.data).toEqual({
      rows: [{ id: "c1", name: "Acme" }],
      count: 42,
    });
    expect(fake.calls[1]!.text).toMatch(
      /^select count\(\*\)::int as count from "public"\."customers"/,
    );
    expect(fake.calls[1]!.values).toEqual(["Acme"]);
  });

  it("counts zero when the count query returns no row, and head selects no rows", async () => {
    const fake = fakeSql();
    const result = await postgresExecutor(fake.sql).execute(
      select({ head: true, count: "exact" }),
      context,
    );
    expect(result.ok && result.data).toEqual({ rows: [], count: 0 });
    expect(fake.texts()).toHaveLength(1);
    expect(fake.texts()[0]).toMatch(/^select count\(\*\)::int as count/);
  });

  it("inserts with RETURNING and counts the returned rows", async () => {
    const fake = fakeSql([
      [/^insert into/, rowsOf({ id: "c1" }, { id: "c2" })],
    ]);
    const result = await postgresExecutor(fake.sql).execute(
      insert({ rows: [{ name: "A" }, { name: "B" }] }),
      context,
    );
    expect(result.ok && result.data).toEqual({
      rows: [{ id: "c1" }, { id: "c2" }],
      count: 2,
    });
    expect(fake.calls[0]!.text).toMatch(
      /^insert into "public"\."customers" as \w+ \("name"\) values \(\$1\), \(\$2\) returning /,
    );
    expect(fake.calls[0]!.values).toEqual(["A", "B"]);
  });

  it("counts an insert without RETURNING through a CTE", async () => {
    const fake = fakeSql([[/^with m as \(insert/, [{ count: 1 }]]]);
    const result = await postgresExecutor(fake.sql).execute(
      insert({ returning: undefined }),
      context,
    );
    expect(result.ok && result.data).toEqual({ rows: [], count: 1 });
    expect(fake.calls[0]!.text).toMatch(
      /select count\(\*\)::int as count from m$/,
    );
  });

  it("updates without RETURNING and deletes with RETURNING", async () => {
    const fake = fakeSql([
      [/^with m as \(update/, [{ count: 3 }]],
      [/^delete from/, rowsOf({ id: "c9" })],
    ]);
    const executor = postgresExecutor(fake.sql);
    const updated = await executor.execute(update(), context);
    expect(updated.ok && updated.data).toEqual({ rows: [], count: 3 });
    expect(fake.calls[0]!.text).toContain('set "status" = $1');
    expect(fake.calls[0]!.values).toEqual(["active", "1001"]);

    const deleted = await executor.execute(remove(), context);
    expect(deleted.ok && deleted.data).toEqual({
      rows: [{ id: "c9" }],
      count: 1,
    });
  });

  it("returns no rows without querying when nothing can match", async () => {
    const fake = fakeSql();
    const result = await postgresExecutor(fake.sql).execute(
      insert({ rows: [] }),
      context,
    );
    expect(result.ok && result.data).toEqual({ rows: [], count: 0 });
    expect(fake.calls).toHaveLength(0);
  });

  it("returns a compile error as a result instead of throwing", async () => {
    const fake = fakeSql();
    const result = await postgresExecutor(fake.sql).execute(
      update({ set: {} }),
      context,
    );
    expect(result.error).toMatchObject({
      kind: "invalid_request",
      message: 'Update on "customers" sets no columns',
    });
    expect(fake.calls).toHaveLength(0);
  });

  it("returns aborted before it queries when the signal has fired", async () => {
    const fake = fakeSql();
    const result = await postgresExecutor(fake.sql).execute(select(), {
      ...context,
      signal: AbortSignal.abort(),
    });
    expect(result.error).toMatchObject({
      kind: "aborted",
      message: "The request was aborted",
    });
    expect(fake.calls).toHaveLength(0);
  });

  it("maps a pg error, with the detail fields, through the error mappers", async () => {
    const fake = fakeSql([
      [
        /^insert/,
        {
          throws: pgError("23505", "duplicate key value", {
            constraint: "customers_organization_id_kvk_key",
            detail: "Key (organization_id, kvk)=(o1, 1001) already exists.",
            table: "customers",
          }),
        },
      ],
    ]);
    const executor = postgresExecutor(fake.sql);
    const plain = await executor.execute(insert(), context);
    expect(plain.error).toMatchObject({
      kind: "conflict",
      constraint: "customers_organization_id_kvk_key",
    });

    const mapped = await executor.execute(insert(), {
      errorMappers: [
        (raw, fallback) =>
          raw.constraint === "customers_organization_id_kvk_key"
            ? dbError("validation", "KvK already used", {
                issues: [{ message: fallback.message, path: ["kvk"] }],
              })
            : undefined,
      ],
    });
    expect(mapped.error).toMatchObject({
      kind: "validation",
      message: "KvK already used",
      issues: [{ message: "duplicate key value", path: ["kvk"] }],
    });
  });

  it("returns a thrown non-pg error as unexpected", async () => {
    const fake = fakeSql([
      [/^select/, { throws: new Error("socket hang up") }],
    ]);
    const result = await postgresExecutor(fake.sql).execute(select(), context);
    expect(result.error).toMatchObject({
      kind: "unexpected",
      message: "socket hang up",
    });
  });

  describe("single rows", () => {
    it("fails with multiple_rows when more than one row comes back", async () => {
      const fake = fakeSql([[/^select/, rowsOf({ id: "a" }, { id: "b" })]]);
      const executor = postgresExecutor(fake.sql);
      for (const single of ["one", "maybe"] as const) {
        const result = await executor.execute(select({ single }), context);
        expect(result.error).toMatchObject({
          kind: "multiple_rows",
          message: "Expected one customers row",
        });
      }
    });

    it("fails with not_found for one, and allows none for maybe", async () => {
      const executor = postgresExecutor(fakeSql().sql);
      const one = await executor.execute(select({ single: "one" }), context);
      expect(one.error).toMatchObject({
        kind: "not_found",
        message: "No customers row matched",
      });
      const maybe = await executor.execute(
        select({ single: "maybe" }),
        context,
      );
      expect(maybe.ok && maybe.data).toEqual({ rows: [], count: null });
    });

    it("returns the single row when exactly one matches", async () => {
      const fake = fakeSql([[/^select/, rowsOf({ id: "a" })]]);
      const result = await postgresExecutor(fake.sql).execute(
        select({ single: "one" }),
        context,
      );
      expect(result.ok && result.data.rows).toEqual([{ id: "a" }]);
    });
  });

  describe("split inserts", () => {
    const many = Array.from({ length: 40_000 }, (_, index) => ({
      name: `c${index}`,
      kvk: String(index),
    }));

    it("runs every chunk in one transaction and adds up the rows", async () => {
      const fake = fakeSql([[/^insert/, rowsOf({ id: "a" })]]);
      const result = await postgresExecutor(fake.sql).execute(
        insert({ rows: many }),
        context,
      );
      expect(result.ok && result.data).toEqual({
        rows: [{ id: "a" }, { id: "a" }],
        count: 2,
      });
      expect(fake.transactions).toBe(1);
      expect(fake.calls).toHaveLength(2);
    });

    it("adds up counts without returning, and runs in order without transactions", async () => {
      const fake = fakeSql([[/^with m as \(insert/, [{ count: 3 }]]]);
      const result = await postgresExecutor({
        queryRaw: (text, params) => fake.sql.queryRaw(text, params),
      }).execute(insert({ rows: many, returning: undefined }), context);
      expect(result.ok && result.data).toEqual({ rows: [], count: 6 });
      expect(fake.transactions).toBe(0);
    });
  });

  describe("batch", () => {
    it("runs the operations separately when the client has no transactions", async () => {
      const fake = fakeSql([[/^select/, rowsOf({ id: "a" })]]);
      const results = await postgresExecutor({
        queryRaw: (text, params) => fake.sql.queryRaw(text, params),
      }).batch!([select(), select({ head: true })], context);
      expect(results.map((result) => result.ok && result.data)).toEqual([
        { rows: [{ id: "a" }], count: null },
        { rows: [], count: 0 },
      ]);
      expect(fake.transactions).toBe(0);
    });

    it("runs every operation in one transaction", async () => {
      const fake = fakeSql([[/^select/, rowsOf({ id: "a" })]]);
      const results = await postgresExecutor(fake.sql).batch!(
        [select(), select()],
        context,
      );
      expect(results.every((result) => result.ok)).toBe(true);
      expect(fake.transactions).toBe(1);
      expect(fake.calls).toHaveLength(2);
    });

    it("reruns each operation on its own when one fails, so each gets its result", async () => {
      const fake = fakeSql([
        [
          /^with m as \(update/,
          { throws: pgError("57014", "canceling statement") },
        ],
        [/^select/, rowsOf({ id: "a" })],
      ]);
      const results = await postgresExecutor(fake.sql).batch!(
        [select(), update(), select()],
        context,
      );
      expect(results.map((result) => result.ok)).toEqual([true, false, true]);
      expect(results[1]!.error?.kind).toBe("timeout");
      expect(fake.transactions).toBe(1);
      // two statements in the aborted transaction, then all three again
      expect(fake.calls).toHaveLength(5);
    });

    it("rethrows a transaction failure that is not an operation error", async () => {
      const fake = fakeSql();
      const broken: SqlClient = {
        queryRaw: (text, params) => fake.sql.queryRaw(text, params),
        transaction: () => Promise.reject(new Error("could not begin")),
      };
      await expect(
        postgresExecutor(broken).batch!([select()], context),
      ).rejects.toThrow("could not begin");
    });
  });
});

describe("postgresExecutor maxAffected", () => {
  it("maps the guard's cast error to max_affected with the limit", async () => {
    const fake = fakeSql([
      [
        /^with m as \(update/,
        {
          throws: pgError(
            "22P02",
            'invalid input syntax for type integer: "better_supabase:max_affected:4"',
          ),
        },
      ],
    ]);
    const result = await postgresExecutor(fake.sql).execute(
      update({ maxAffected: 3 }),
      context,
    );
    expect(result).toMatchObject({
      ok: false,
      error: {
        kind: "max_affected",
        status: 400,
        code: "22P02",
        maxAffected: 3,
        message: "The write affects 4 rows, more than maxAffected allows",
      },
    });
  });

  it("returns the guarded rows of a delete within the limit", async () => {
    const fake = fakeSql([[/^with m as \(delete/, rowsOf({ id: "a" })]]);
    const result = await postgresExecutor(fake.sql).execute(
      remove({ maxAffected: 1 }),
      context,
    );
    expect(result.ok && result.data).toEqual({
      rows: [{ id: "a" }],
      count: 1,
    });
    expect(fake.calls[0]!.text).toMatch(
      /select m\.row from m cross join c where c\.n >= 0$/,
    );
  });

  it("keeps other invalid input errors as invalid_input", async () => {
    const fake = fakeSql([
      [/^with m as \(update/, { throws: pgError("22P02", "invalid input") }],
    ]);
    const result = await postgresExecutor(fake.sql).execute(update(), context);
    expect(result).toMatchObject({
      ok: false,
      error: { kind: "invalid_input" },
    });
  });
});

describe("fromPgError", () => {
  it("copies the node-postgres fields to the shape mapDbError reads", () => {
    expect(
      fromPgError(
        pgError("23503", "violates foreign key", {
          detail: "Key is not present",
          hint: "Insert the parent first",
          constraint: "notes_customer_id_fkey",
          column: "customer_id",
          table: "notes",
        }),
      ),
    ).toEqual({
      code: "23503",
      message: "violates foreign key",
      details: "Key is not present",
      hint: "Insert the parent first",
      constraint: "notes_customer_id_fkey",
      column: "customer_id",
      table: "notes",
    });
  });

  it("keeps only the fields that are present", () => {
    expect(fromPgError({ code: "42501" })).toEqual({ code: "42501" });
  });

  it("returns undefined for values without a string code", () => {
    expect(fromPgError(new Error("plain"))).toBeUndefined();
    expect(fromPgError({ code: 42 })).toBeUndefined();
    expect(fromPgError(null)).toBeUndefined();
    expect(fromPgError("23505")).toBeUndefined();
  });
});

describe("postgresExecutor rpc", () => {
  const fn = schema.meta.functions["rs_workspace_summary"]!;

  it("calls the function by schema and named arguments, as json for json types", async () => {
    const fake = fakeSql([["to_json(bs_call)", [{ value: { ok: true } }]]]);
    const executor = postgresExecutor(fake.sql);
    const result = await executor.rpc!(
      "rs_workspace_summary",
      { p: [1, 2], skipped: undefined },
      { schema: "public", errorMappers: [], function: fn },
    );
    expect(result).toMatchObject({ ok: true, data: { ok: true } });
    expect(fake.calls).toEqual([
      {
        text: 'select to_json(bs_call) as value from "public"."rs_workspace_summary"("p" => $1) as bs_call',
        values: ["[1,2]"],
      },
    ]);
  });

  it("sends objects as json, Temporal values as text and bigints as strings", async () => {
    const fake = fakeSql([
      ["pg_proc", [{ returns_set: true, returns_void: false }]],
      ["to_json(bs_call)", [{ value: 1 }, { value: 2 }]],
    ]);
    const at = Temporal.Instant.from("2026-01-02T03:04:05Z");
    const result = await postgresExecutor(fake.sql).rpc!(
      "probe",
      { a: { b: 1 }, at, n: 9007199254740993n, ids: ["x", "y"], none: null },
      { schema: "app", errorMappers: [] },
    );
    expect(result).toMatchObject({ ok: true, data: [1, 2] });
    expect(fake.calls[0]!.values).toEqual(["app", "probe"]);
    expect(fake.calls[1]).toEqual({
      text: 'select to_json(bs_call) as value from "app"."probe"("a" => $1, "at" => $2, "n" => $3, "ids" => $4, "none" => $5) as bs_call',
      values: [
        '{"b":1}',
        "2026-01-02T03:04:05Z",
        "9007199254740993",
        ["x", "y"],
        null,
      ],
    });
  });

  it("returns null for void, maps errors and reports a missing function", async () => {
    const fake = fakeSql([
      [
        /pg_proc.*/,
        (call) =>
          call.values[1] === "gone"
            ? []
            : [{ returns_set: false, returns_void: call.values[1] === "noop" }],
      ],
      ['"noop"', []],
      ['"boom"', { throws: pgError("P0001", "Nope", { hint: "PROBE" }) }],
    ]);
    const executor = postgresExecutor(fake.sql);
    const call = (name: string) =>
      executor.rpc!(name, {}, { schema: "public", errorMappers: [] });
    expect(await call("noop")).toMatchObject({ ok: true, data: null });
    expect(fake.texts()).toContain('select "public"."noop"()');
    expect(await call("boom")).toMatchObject({
      ok: false,
      error: { kind: "raised", hint: "PROBE" },
    });
    expect(await call("gone")).toMatchObject({
      ok: false,
      error: { kind: "invalid_request", code: "PGRST202" },
    });
    const aborted = new AbortController();
    aborted.abort();
    expect(
      await executor.rpc!(
        "noop",
        {},
        { schema: "public", errorMappers: [], signal: aborted.signal },
      ),
    ).toMatchObject({ ok: false, error: { kind: "aborted" } });
  });
});
