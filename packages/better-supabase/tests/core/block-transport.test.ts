import { describe, expect, it, vi } from "vitest";

import type { Executor } from "../../src/core/executor.ts";

import { createOrganizations } from "../../src/blocks/organizations/index.ts";
import { toBlockError } from "../../src/core/block-helpers.ts";
import { dbTransport, sqlTransport } from "../../src/core/block-transport.ts";
import { dbError } from "../../src/core/errors.ts";
import { postgrestExecutor } from "../../src/core/postgrest-executor.ts";
import { err } from "../../src/core/result.ts";
import { postgresExecutor } from "../../src/postgres/executor.ts";
import { fakeSql, pgError } from "../fixtures/fake-sql.ts";

const SIGNATURE = [{ returns_set: false, returns_void: false }];

function overPostgres(answer: () => readonly Record<string, unknown>[]) {
  const fake = fakeSql([
    ["pg_catalog.pg_proc", SIGNATURE],
    ["bs_call", () => answer()],
  ]);
  return { fake, db: { $executor: postgresExecutor(fake.sql) } };
}

function overPostgrest(response: { data: unknown; error: unknown }) {
  const rpc = vi.fn(() => Promise.resolve(response));
  const schema = vi.fn(() => ({ rpc }));
  const executor = postgrestExecutor({ from: vi.fn(), schema });
  return { rpc, schema, db: { $executor: executor } };
}

describe("sqlTransport", () => {
  it("sends objects and arrays of objects as JSON, other arrays as they are", async () => {
    const queryRaw = vi.fn(() => Promise.resolve([{ value: true }]));
    const transport = sqlTransport({ queryRaw } as never);
    expect(
      await transport.call("s", "f", {
        lines: [{ lineId: "l1", quantity: 1 }],
        ids: ["a", "b"],
        data: { a: 1 },
        none: null,
        skipped: undefined,
      }),
    ).toBe(true);
    expect(queryRaw).toHaveBeenCalledWith(
      'select "s"."f"("lines" => $1, "ids" => $2, "data" => $3, "none" => $4) as value',
      ['[{"lineId":"l1","quantity":1}]', ["a", "b"], '{"a":1}', null],
    );
  });
});

describe("dbTransport over Postgres", () => {
  it("calls the function with named arguments and returns its value", async () => {
    const { fake, db } = overPostgres(() => [{ value: { id: "org-1" } }]);
    const transport = dbTransport(db);
    expect(
      await transport.call("better_supabase", "create_organization", {
        attrs: { name: "Acme" },
        skipped: undefined,
      }),
    ).toEqual({ id: "org-1" });
    const call = fake.calls.find((entry) => entry.text.includes("bs_call"));
    expect(call?.text).toBe(
      'select to_json(bs_call) as value from "better_supabase"."create_organization"("attrs" => $1) as bs_call',
    );
    expect(call?.values).toEqual(['{"name":"Acme"}']);
  });

  it("sends every call to the schema in the options", async () => {
    const { fake, db } = overPostgres(() => [{ value: true }]);
    await dbTransport(db, { schema: "api" }).call(
      "better_supabase",
      "mark_used",
      {},
    );
    expect(fake.texts().at(-1)).toContain('"api"."mark_used"()');
  });

  it("rejects with the raw pg error, so block mappers see its code and hint", async () => {
    const { db } = overPostgres(() => {
      throw pgError("42501", "nope", { hint: "ORGANIZATION_FORBIDDEN" });
    });
    const organizations = createOrganizations({ transport: dbTransport(db) });
    expect(await organizations.leave("organization")).toMatchObject({
      ok: false,
      error: {
        kind: "forbidden",
        message: "nope",
        code: "42501",
        hint: "ORGANIZATION_FORBIDDEN",
      },
    });
  });

  it("runs the app's mappers on the raw error", async () => {
    const { db } = overPostgres(() => {
      throw pgError("P0001", "gone", { hint: "ORGANIZATION_GONE" });
    });
    const organizations = createOrganizations({
      transport: dbTransport(db),
      mappers: [
        (raw) =>
          raw.hint === "ORGANIZATION_GONE"
            ? dbError("not_found", "No such organization")
            : undefined,
      ],
    });
    expect(await organizations.leave("organization")).toMatchObject({
      ok: false,
      error: { kind: "not_found", message: "No such organization" },
    });
  });
});

describe("dbTransport over PostgREST", () => {
  it("calls rpc on the module schema without undefined arguments", async () => {
    const { db, rpc, schema } = overPostgrest({ data: 3, error: null });
    expect(
      await dbTransport(db).call("better_supabase", "mark_used", {
        organization: "o",
        x: undefined,
      }),
    ).toBe(3);
    expect(schema).toHaveBeenCalledWith("better_supabase");
    expect(rpc).toHaveBeenCalledWith("mark_used", { organization: "o" });
  });

  it("sends every call to the API schema when one is given", async () => {
    const { db, schema } = overPostgrest({ data: 1, error: null });
    await dbTransport(db, { schema: "api" }).call("better_supabase", "f", {});
    expect(schema).toHaveBeenCalledWith("api");
  });

  it("rejects with the PostgREST error's fields", async () => {
    const { db } = overPostgrest({
      data: null,
      error: { message: "nope", code: "42501", hint: "ORGANIZATION_FORBIDDEN" },
    });
    const organizations = createOrganizations({ transport: dbTransport(db) });
    expect(await organizations.leave("organization")).toMatchObject({
      ok: false,
      error: { kind: "forbidden", hint: "ORGANIZATION_FORBIDDEN" },
    });
  });
});

describe("dbTransport errors without a database error", () => {
  it("keeps the executor's own error", async () => {
    const executor: Executor = {
      name: "lite",
      execute: () => Promise.resolve(err(dbError("unsupported", "no"))),
      rpc: () =>
        Promise.resolve(
          err(
            dbError("unsupported", "No functions", { code: "RPC_UNAVAILABLE" }),
          ),
        ),
    };
    const organizations = createOrganizations({
      transport: dbTransport({ $executor: executor }),
    });
    expect(await organizations.leave("organization")).toMatchObject({
      ok: false,
      error: { kind: "unsupported", code: "RPC_UNAVAILABLE" },
    });
  });

  it("fails on an executor without rpc", async () => {
    const executor: Executor = {
      name: "custom",
      execute: () => Promise.resolve(err(dbError("unsupported", "no"))),
    };
    await expect(
      dbTransport({ $executor: executor }).call("s", "f", {}),
    ).rejects.toThrow(/custom executor has none/);
  });

  it("returns a DbError a transport rejected with as it is", () => {
    const error = dbError("timeout", "slow", { code: "57014" });
    expect(toBlockError(error)).toBe(error);
  });
});
