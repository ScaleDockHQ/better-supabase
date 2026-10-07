import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { IntrospectionSource } from "../../../src/cli/introspect/source.ts";

import { emitModule } from "../../../src/cli/gen/emit.ts";
import { buildModel } from "../../../src/cli/gen/model.ts";
import { introspect } from "../../../src/cli/introspect/index.ts";
import { pgSource } from "../../../src/cli/introspect/source.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import {
  createPostgres,
  postgresExecutor,
} from "../../../src/postgres/index.ts";
import { defineSchema } from "../../../src/schema/define.ts";
import { libraryFixture } from "../fixtures/library.ts";

const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";

const SCHEMA = `bs_overloads_${Date.now()}`;

async function open(): Promise<IntrospectionSource | undefined> {
  try {
    const source = await pgSource(dbUrl);
    await source.queryable.query("select 1");
    return source;
  } catch {
    return undefined;
  }
}

const source = await open();

describe.skipIf(!source)("$rpc on an overloaded function", () => {
  const db = source!;
  const postgres = createPostgres({ connectionString: dbUrl, max: 2 });

  beforeAll(async () => {
    await db.queryable.query(`
      create schema ${SCHEMA};
      create function ${SCHEMA}.area() returns text
        language sql as $$ select 'none' $$;
      create function ${SCHEMA}.area(side integer) returns integer
        language sql as $$ select side * side $$;
      create function ${SCHEMA}.area(box jsonb) returns integer
        language sql as $$ select (box->>'w')::int * (box->>'h')::int $$;
      create function ${SCHEMA}.area(label text, scale integer default 1)
        returns table (item_label text, scaled_side integer)
        language sql as $$ select label, s * scale from generate_series(1, 2) s $$;
    `);
  });

  afterAll(async () => {
    await db.queryable.query(`drop schema if exists ${SCHEMA} cascade`);
    await db.close();
    await postgres.end();
  });

  it("generates every overload and calls the one the argument names pick", async () => {
    const snapshot = await introspect(db.queryable, [SCHEMA]);
    const model = buildModel(
      snapshot,
      resolveConfig(
        { schemas: [SCHEMA], casing: "camel" },
        libraryFixture("").pathname,
      ),
    );
    expect(
      model.meta.functions["area"]?.overloads?.map((overload) =>
        overload.args.map((arg) => arg.name),
      ),
    ).toEqual([[], ["box"], ["label", "scale"], ["side"]]);
    expect(emitModule(model, { importPathFor: (from) => from })).toContain(
      "Args: Record<PropertyKey, never>;",
    );

    const sb = defineSupabase(defineSchema(model.meta)).connect(
      postgresExecutor(postgres.admin),
    );
    const call = (args: Record<string, unknown>) =>
      sb.$rpc("area", args, { schema: SCHEMA }).orThrow();
    expect(await call({})).toBe("none");
    expect(await call({ side: 3 })).toBe(9);
    expect(await call({ box: { w: 2, h: 5 } })).toBe(10);
    expect(await call({ label: "x", scale: 10 })).toEqual([
      { itemLabel: "x", scaledSide: 10 },
      { itemLabel: "x", scaledSide: 20 },
    ]);
    expect(await call({ label: "y" })).toEqual([
      { itemLabel: "y", scaledSide: 1 },
      { itemLabel: "y", scaledSide: 2 },
    ]);
  });
});
