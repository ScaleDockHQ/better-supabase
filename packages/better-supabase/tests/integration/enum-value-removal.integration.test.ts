import * as delta from "@supabase/pg-delta";
import { Pool } from "pg";
import { describe, expect, it } from "vitest";

import { openPgPool } from "../../src/cli/in-stack-diff.ts";
import { dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

/** The table a column of enum type `status` lives in, with every value in use. */
const BEFORE = `create schema bsb_enum_test;
create type bsb_enum_test.status as enum ('draft', 'live', 'archived');
create table bsb_enum_test.items (
  id bigint generated always as identity primary key,
  status bsb_enum_test.status not null default 'draft'
);`;

const REMOVED = BEFORE.replace(", 'archived'", "");
const ADDED = BEFORE.replace("'archived'", "'archived', 'paused'");

const RENAMED = BEFORE.replace("'archived'", "'retired'");

/**
 * The statements pg-delta plans to move a database from `before` to `after`,
 * each in a shadow database of the stack's cluster.
 */
async function plan(before: string, after: string): Promise<string[]> {
  const current = await delta.provisionCoLocatedShadow(dbUrl);
  const wanted = await delta.provisionCoLocatedShadow(dbUrl);
  const from = await openPgPool(current.url);
  const to = await openPgPool(wanted.url);
  const setup = new Pool({ connectionString: current.url, max: 1 });

  try {
    await setup.query(before);

    const result = await delta.planSchemaFiles(
      from,
      to,
      [{ name: "after.sql", sql: after }],
      { profile: delta.supabaseProfile, renames: "prompt" },
    );

    return result.plan.actions
      .map((action) => action.sql)
      .filter((sql) => sql.includes("bsb_enum_test"));
  } finally {
    await Promise.allSettled([from.end(), to.end(), setup.end()]);
    await current.cleanup();
    await wanted.cleanup();
  }
}

// The docs page for removing an enum value (database/enum-values) states what
// pg-delta plans; these tests keep that text true.
describe.skipIf(!live)("pg-delta and enum values", () => {
  it("adds a value with alter type", async () => {
    const statements = await plan(BEFORE, ADDED);

    expect(statements.join("\n")).toMatch(/alter type .*status.* add value/iu);
  });

  it("does not plan a value removal as an alter type", async () => {
    const statements = (await plan(BEFORE, REMOVED)).join("\n");

    // Postgres has no `alter type ... drop value`, so the plan drops the type
    // and creates it again, which fails while a column uses it. That is why the
    // docs ask for the new type, a column rewrite and then the drop.
    expect(statements).not.toMatch(/drop value/iu);
    expect(statements).toMatch(/drop type|create type/iu);
  });

  it("plans a replaced value as a type change, not a rename value", async () => {
    const statements = (await plan(BEFORE, RENAMED)).join("\n");

    expect(statements).not.toMatch(/rename value/iu);
  });
});
