import { fileURLToPath } from "node:url";
import { format } from "oxfmt";
import { Pool } from "pg";
import { describe, expect, it } from "vitest";

import { supabaseCli } from "../../../src/cli/exec.ts";
import { introspect } from "../../../src/cli/introspect/index.ts";
import { pgSource } from "../../../src/cli/introspect/source.ts";
import { generateDatabaseTypes } from "../../../src/cli/introspect/typegen.ts";

const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";
const repoRoot = fileURLToPath(new URL("../../../../../", import.meta.url));

async function reachable(): Promise<boolean> {
  const pool = new Pool({
    connectionString: dbUrl,
    max: 1,
    connectionTimeoutMillis: 1000,
  });
  try {
    await pool.query("select 1");
    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

const live = await reachable();

/**
 * Differences that come from the CLI, not from better-supabase. Since 2.118
 * the CLI prints the typegen output unformatted, so both sides go through
 * the typegen's formatter settings first. Older CLIs bundle an older
 * postgres-meta: `--local` omits `__InternalSupabase`, newer typegen writes
 * `NonNullable<Json>` for non-null json columns.
 */
async function normalize(source: string): Promise<string> {
  const { code, errors } = await format("database.types.ts", source, {
    semi: false,
    printWidth: 80,
  });
  expect(errors).toEqual([]);
  return code
    .replace(
      /\n {2}\/\/ Allows to automatically[^\n]*\n[^\n]*\n {2}__InternalSupabase: \{\n[^\n]*\n {2}\}\n/,
      "\n",
    )
    .replaceAll("NonNullable<Json>", "Json")
    .trimEnd();
}

describe.skipIf(!live)("database.types.ts parity", () => {
  it("matches `supabase gen types --local` for the fixture database", async () => {
    const cli = await supabaseCli(
      ["gen", "types", "typescript", "--local", "--schema", "public"],
      repoRoot,
      process.env,
    );
    expect({ code: cli.code, stderr: cli.stderr }).toMatchObject({ code: 0 });

    const db = await pgSource(dbUrl);
    let ours: string;
    try {
      const snapshot = await introspect(db.queryable, ["public"]);
      ours = await generateDatabaseTypes(snapshot.generator, {
        schemas: ["public"],
        postgrestVersion: "13",
      });
    } finally {
      await db.close();
    }
    expect(await normalize(ours)).toBe(await normalize(cli.stdout));
  }, 120_000);
});
