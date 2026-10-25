import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { SqlClient } from "../../src/postgres/executor.ts";

import { blockFields, extraFieldsArg } from "../../src/core/block-fields.ts";
import {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../src/core/block-transport.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { postgrestExecutor } from "../../src/core/postgrest-executor.ts";
import { ok } from "../../src/core/result.ts";
import { loadLite } from "../../src/lite/runtime.ts";
import { postgresExecutor } from "../../src/postgres/executor.ts";
import { createPostgres } from "../../src/postgres/pool.ts";
import { capturingClient } from "../fixtures/client.ts";
import { fakePgPool } from "../fixtures/fake-pg-pool.ts";
import { schema } from "../fixtures/generated-camel.ts";

const AT = Temporal.Instant.from("2026-01-02T00:00:00Z");

/** Every kind of value a function argument can carry. */
const ARGS = {
  at: AT,
  zoned: Temporal.ZonedDateTime.from(
    "2026-01-02T01:00:00+01:00[Europe/Amsterdam]",
  ),
  day: Temporal.PlainDate.from("2026-01-02"),
  length: Temporal.Duration.from({ hours: 1, minutes: 30 }),
  ats: [AT, AT.add({ hours: 1 })],
  doc: { total: 9_007_199_254_740_993n, nested: { at: AT } },
  skipped: undefined,
};

/** What `ARGS` looks like on the wire. */
const WIRE = {
  at: "2026-01-02T00:00:00Z",
  zoned: "2026-01-02T00:00:00Z",
  day: "2026-01-02",
  length: "PT1H30M",
  ats: ["2026-01-02T00:00:00Z", "2026-01-02T01:00:00Z"],
  doc: { total: "9007199254740993", nested: { at: "2026-01-02T00:00:00Z" } },
};

/** `{a,b}`, how supabase-js puts an array in a GET query string. */
const listOf = (text: string): string[] => text.slice(1, -1).split(",");

describe("function arguments over PostgREST", () => {
  it.each<[string, () => Promise<unknown>]>([
    [
      "db.$rpc",
      async () => {
        const { client, last } = capturingClient(() => ({ body: null }));
        await defineSupabase(schema)
          .connect(postgrestExecutor(client))
          .$rpc("echo_args" as never, ARGS as never)
          .orThrow();

        return last().body;
      },
    ],
    [
      "the executor's GET call",
      async () => {
        const { client, last } = capturingClient(() => ({ body: null }));
        await postgrestExecutor(client).rpc!("echo_args", ARGS, {
          schema: "public",
          errorMappers: [],
          get: true,
        });
        const { params } = last();

        return {
          at: params.get("at"),
          zoned: params.get("zoned"),
          day: params.get("day"),
          length: params.get("length"),
          ats: listOf(params.get("ats") ?? ""),
          doc: JSON.parse(params.get("doc") ?? "null"),
        };
      },
    ],
    [
      "rpcTransport",
      async () => {
        const { client, last } = capturingClient(() => ({ body: null }));
        await rpcTransport(client).call("api", "echo_args", ARGS);

        return last().body;
      },
    ],
    [
      "dbTransport",
      async () => {
        const { client, last } = capturingClient(() => ({ body: null }));
        await dbTransport({ $executor: postgrestExecutor(client) }).call(
          "api",
          "echo_args",
          ARGS,
        );

        return last().body;
      },
    ],
  ])("encodes Temporal values and bigints through %s", async (_path, send) => {
    expect(await send()).toEqual(WIRE);
  });
});

describe("function arguments as parameters", () => {
  it("encodes queryRaw parameters on a pool", async () => {
    const values: (readonly unknown[])[] = [];

    const fake = fakePgPool((_text, params) => {
      values.push(params);

      return [];
    });

    await createPostgres({ pool: fake.pool }).admin.queryRaw(
      "select $1, $2, $3, $4, $5, $6",
      [ARGS.at, ARGS.zoned, ARGS.day, ARGS.length, ARGS.ats, ARGS.doc],
    );

    expect(values[0]).toEqual([
      WIRE.at,
      WIRE.zoned,
      WIRE.day,
      WIRE.length,
      WIRE.ats,
      WIRE.doc,
    ]);
  });

  it("encodes the extra fields a block writes", async () => {
    const fields = blockFields(undefined, "fields");
    const { at, doc } = ARGS;

    expect(await fields.args({ at, doc })).toEqual(
      ok({ at: WIRE.at, doc: WIRE.doc }),
    );
    expect(await extraFieldsArg(fields, { at })).toEqual(
      ok({ fields: { at: WIRE.at } }),
    );
  });
});

const ECHO = `
create function public.echo_args(
  at timestamptz,
  zoned timestamptz,
  day date,
  length interval,
  ats timestamptz[],
  doc jsonb
) returns jsonb
language sql
as $$
  select jsonb_build_object(
    'at', to_char(at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'zoned', to_char(zoned at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'day', day::text,
    'minutes', extract(epoch from length) / 60,
    'ats', array_length(ats, 1),
    'doc', doc
  )
$$;
`;

const ECHOED = {
  at: WIRE.at,
  zoned: WIRE.zoned,
  day: WIRE.day,
  minutes: 90,
  ats: 2,
  doc: WIRE.doc,
};

describe("function arguments on Postgres (PGlite)", { timeout: 60_000 }, () => {
  let close: (() => Promise<unknown>) | undefined;
  let sql: SqlClient;

  beforeAll(async () => {
    const lite = await loadLite();

    if (!lite) {
      throw new Error("@supabase/lite is a devDependency of these tests");
    }

    const { driver } = await lite.createPgliteConnection();

    // SAFETY: PGlite's query takes parameters; the runtime type leaves them out.
    const pglite = driver as unknown as {
      query(text: string, params?: unknown[]): Promise<{ rows: unknown[] }>;
      exec(text: string): Promise<unknown>;
      close(): Promise<unknown>;
    };

    await pglite.exec(ECHO);
    close = () => pglite.close();

    sql = {
      queryRaw: async <R>(text: string, params?: unknown[]) =>
        // SAFETY: each caller names the row type its statement selects.
        (await pglite.query(text, params)).rows as R[],
      transaction: (fn) => fn(sql),
    };
  });

  afterAll(async () => {
    await close?.();
  });

  it.each<[string, () => Promise<unknown>]>([
    [
      "the Postgres executor",
      async () => {
        const result = await postgresExecutor(sql).rpc!("echo_args", ARGS, {
          schema: "public",
          errorMappers: [],
        });

        return result.ok ? result.data : result.error;
      },
    ],
    ["sqlTransport", () => sqlTransport(sql).call("public", "echo_args", ARGS)],
    [
      "dbTransport",
      () =>
        dbTransport({ $executor: postgresExecutor(sql) }).call(
          "public",
          "echo_args",
          ARGS,
        ),
    ],
  ])("Postgres reads the arguments %s sends", async (_path, send) => {
    expect(await send()).toEqual(ECHOED);
  });
});
