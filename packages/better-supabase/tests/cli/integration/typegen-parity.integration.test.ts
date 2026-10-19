import { fileURLToPath } from "node:url";
import { format } from "oxfmt";
import { Pool } from "pg";
import { describe, expect, it } from "vitest";

import { parseEnv } from "../../../src/cli/env.ts";
import { supabaseCli } from "../../../src/cli/exec.ts";
import { introspect } from "../../../src/cli/introspect/index.ts";
import { pgSource } from "../../../src/cli/introspect/source.ts";
import { generateDatabaseTypes } from "../../../src/cli/introspect/typegen.ts";
import { stackDbUrl } from "../../integration/stack-env.ts";

const dbUrl = stackDbUrl();
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
 * the typegen's formatter settings first, and `--local` omits
 * `__InternalSupabase`. postgrest-typegen 0.6 marks a view column not null
 * when Postgres can prove it, and the postgres-meta in CLI 2.121 types every
 * view column as nullable, so `| null` inside `Views` is left out on both
 * sides.
 */
const VIEWS = /\n {4}Views: \{\n[\s\S]*?\n {4}\}\n/g;

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
    .replace(VIEWS, (views) => views.replaceAll(" | null\n", "\n"))
    .trimEnd();
}

describe.skipIf(!live)("database.types.ts parity", () => {
  it("matches `supabase gen types --local` for the fixture database", async () => {
    const cli = await supabaseCli(
      ["gen", "types", "typescript", "--local", "--schema", "public"],
      repoRoot,
      parseEnv(process.env),
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
