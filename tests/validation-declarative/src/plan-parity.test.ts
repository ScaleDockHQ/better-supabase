import { readdir, readFile } from "node:fs/promises";
import { join, relative } from "node:path";
import { Pool } from "pg";
import { describe, expect, it } from "vitest";

import { ROOT } from "./fixture.ts";

// Plans the project's schema files twice against the same local stack with the
// same driver: with the pg-delta the Supabase CLI 3.2.0 bundles (alpha.60, the
// `pg-delta-previous` alias) and with the one better-supabase pins (alpha.61),
// and expects the same statements in the same order (ADR 1251). It needs a
// running stack with the project's migrations applied (`supabase start` and
// `supabase migration up` in this folder), so it runs only with PLAN_PARITY=1.
// PLAN_PARITY_DB_URL names the stack's database.
const url =
  process.env["PLAN_PARITY_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const available = process.env["PLAN_PARITY"] === "1";

/** The statements of a plan, without comments or layout. */
export function statements(sql: readonly string[]): string[] {
  return sql
    .map((statement) =>
      statement
        .split("\n")
        .filter((line) => !line.trimStart().startsWith("--"))
        .join(" ")
        .replaceAll(/\s+/g, " ")
        .replace(/;\s*$/, "")
        .trim()
        .toLowerCase(),
    )
    .filter((statement) => statement !== "");
}

async function schemaFiles(): Promise<{ name: string; sql: string }[]> {
  const base = join(ROOT, "supabase/schemas");

  const names = (await readdir(base, { recursive: true }))
    .filter((name) => name.endsWith(".sql"))
    .toSorted();

  return Promise.all(
    names.map(async (name) => ({
      name: relative(ROOT, join(base, name)),
      sql: await readFile(join(base, name), "utf-8"),
    })),
  );
}

/** What the plan needs of a release, so both releases fit one driver. */
interface Planner<Profile> {
  readonly supabaseProfile: Profile;
  provisionCoLocatedShadow(
    url: string,
  ): Promise<{ readonly url: string; cleanup(): Promise<void> }>;
  planSchemaFiles(
    target: Pool,
    scratch: Pool,
    files: { name: string; sql: string }[],
    options: {
      profile: Profile;
      renames: "prompt";
      seedAssumedSchemas: boolean;
    },
  ): Promise<{
    readonly plan: { readonly actions: readonly { readonly sql: string }[] };
  }>;
}

async function plan<Profile>(delta: Planner<Profile>): Promise<string[]> {
  const files = await schemaFiles();
  const shadow = await delta.provisionCoLocatedShadow(url);
  const target = new Pool({ connectionString: url });
  const scratch = new Pool({ connectionString: shadow.url });

  try {
    const result = await delta.planSchemaFiles(target, scratch, files, {
      profile: delta.supabaseProfile,
      renames: "prompt",
      seedAssumedSchemas: true,
    });

    return statements(result.plan.actions.map((action) => action.sql));
  } finally {
    await Promise.allSettled([target.end(), scratch.end()]);
    await shadow.cleanup();
  }
}

describe("statements", () => {
  it("drops comments, layout, case and the closing semicolon", () => {
    expect(
      statements(["-- note\nCREATE  TABLE a (\n  id int\n);\n", "", "-- x"]),
    ).toEqual(["create table a ( id int )"]);
  });
});

describe.skipIf(!available)("the plan under both pg-delta releases", () => {
  it(
    "has the same statements in the same order",
    { timeout: 600_000 },
    async () => {
      const bundled = await plan(await import("pg-delta-previous"));

      const pinned = await plan(await import("@supabase/pg-delta"));

      expect(pinned).toEqual(bundled);
    },
  );
});
