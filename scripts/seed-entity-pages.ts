/**
 * Inserts the demo rows that `better-supabase gen` writes for the entity pages
 * of the Next.js example (`<name>.seed.ts`, ADR 0879) into the Acme
 * organization of the local stack: `pnpm db:seed:pages`. A row goes through the
 * block's own create function, so numbering, triggers and policies run as they
 * do for the app. It skips a row whose title the organization already holds, so
 * a second run adds nothing. It reads the database URL that `pnpm env:local`
 * wrote.
 */
import { readFileSync } from "node:fs";
import { argv } from "node:process";
import { Client } from "pg";

import type { EntitySeed } from "../packages/better-supabase/src/list/entity-ui.ts";

import { workOrdersSeed } from "../apps/examples/nextjs/src/lib/supabase/pages/work-orders.seed.ts";

const ACME = "00000000-0000-4000-8000-000000000001";

export interface SeedTarget {
  readonly seed: EntitySeed;
  /**
   * The call that creates one row. `$1` is the tenant and `$2` the row as
   * jsonb, keyed by database column (`$2::jsonb ->> 'title'`).
   */
  readonly sql: string;
}

export const TARGETS: readonly SeedTarget[] = [
  {
    seed: workOrdersSeed,
    sql: "select better_supabase.create_work_order(tenant => $1::uuid, title => $2::jsonb ->> 'title')",
  },
];

export interface SeedCall {
  readonly sql: string;
  readonly title: string;
  readonly values: readonly [string, string];
}

/** One call per row of a seed, for a tier and a tenant; a row needs a `title`. */
export function seedCalls(
  target: SeedTarget,
  tenant: string,
  tier = "demo",
): readonly SeedCall[] {
  if (!target.seed.tiers.includes(tier)) {
    return [];
  }

  return target.seed.rows.map((row) => {
    if (!("title" in row)) {
      throw new TypeError(`A ${target.seed.entity} seed row needs a title.`);
    }

    return {
      sql: target.sql,
      title: String(row["title"]),
      values: [tenant, JSON.stringify(row)],
    };
  });
}

if (argv[1] === import.meta.filename) {
  const url = /^SUPABASE_DB_URL=(.*)$/m.exec(
    readFileSync(".env.development.local", "utf-8"),
  )?.[1];

  if (!url) {
    throw new Error(
      "Run pnpm supabase:start first: .env.development.local has no SUPABASE_DB_URL.",
    );
  }

  const client = new Client({ connectionString: url });

  await client.connect();

  try {
    for (const target of TARGETS) {
      const { seed } = target;

      if (seed.tenant === undefined) {
        throw new Error(`${seed.entity} has no tenant column.`);
      }

      const calls = seedCalls(target, ACME);

      const held = await client.query<{ title: string }>(
        `select title from ${seed.table} where ${seed.tenant} = $1 and title = any($2::text[])`,
        [ACME, calls.map((call) => call.title)],
      );

      const have = new Set(held.rows.map((row) => row.title));
      let added = 0;

      for (const call of calls.filter((each) => !have.has(each.title))) {
        await client.query(call.sql, [...call.values]);
        added += 1;
      }

      console.log(`${seed.entity}: ${added} rows added to ${seed.table}`);
    }
  } finally {
    await client.end();
  }
}
