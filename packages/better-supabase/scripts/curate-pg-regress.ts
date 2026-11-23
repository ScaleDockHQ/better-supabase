import { PgParser } from "@supabase/pg-parser";
/**
 * Writes `tests/cli/schema-reader/fixtures/pg-regress/*.sql`: the statements of
 * a few Postgres regression scripts, as libpg_query ships them, that parse on
 * their own. The scripts mix in psql commands, psql variables and statements
 * that are meant to fail, so each file keeps only what Postgres 17 accepts as
 * syntax. `corpus.test.ts` then reads every file.
 *
 * Each source is pinned by tag and SHA-256 in `SOURCES.md` and in `SOURCES`
 * below, and the script stops when a download doesn't match.
 *
 * `node scripts/curate-pg-regress.ts` downloads and writes the files.
 */
import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import {
  primeStatements,
  rawStatementsOf,
} from "../src/cli/schema-reader/index.ts";

const TAG = "17-6.1.0";
const BASE = `https://raw.githubusercontent.com/pganalyze/libpg_query/${TAG}/test/sql/postgres_regress`;

/** File name and the SHA-256 of the file at `TAG`. */
const SOURCES: readonly (readonly [string, string])[] = [
  [
    "alter_table",
    "35caa7a80fca260bdc004c1055e200ddee78fb8f0920ecfb3401a0d62400b947",
  ],
  [
    "create_function_sql",
    "f4208caa58b82a29768fa759f8959eb2bca000810e18a4886eabb80c79813683",
  ],
  [
    "create_index",
    "d991e99d4b8e1d33c40d656f3eefb349e0bca49f378e8385eae5581ac9047400",
  ],
  [
    "create_schema",
    "a33cdfc52a49c5bf3cf168e6cb927aae3557507ddd8a4077dff7c481c4254492",
  ],
  [
    "create_table",
    "2b1e8bfdbe736ac40ebc995c8e2b31df7668dd2724f6ee438726a4fc0b43520f",
  ],
  [
    "create_type",
    "09684b3556f74942c7694d42bc7c0755bfdbfa594feb0affb737d211c5ee826b",
  ],
  [
    "create_view",
    "2f1353de99bb13ff7994f53c975936b82b20a2cd6212acbee4d51dfed5a42f08",
  ],
  [
    "rowsecurity",
    "cea7b02384c11f303730447b38a39f3028a3e7b7153012b4689b44e8ada29fb1",
  ],
  [
    "triggers",
    "bff8b57a574ee15c719ccd41ed1f6d49474bc245ff686832c22d4abe9b19a57c",
  ],
];

const OUTPUT = new URL(
  "../tests/cli/schema-reader/fixtures/pg-regress/",
  import.meta.url,
);

const parser = new PgParser({ version: 17 });

async function parses(statement: string): Promise<boolean> {
  const parsed = await parser.parse(statement);

  return parsed.error === undefined && (parsed.tree.stmts ?? []).length > 0;
}

/** The statements of `text` that parse alone, one per paragraph. */
export async function curate(text: string): Promise<string> {
  const sql = text
    .split("\n")
    .filter((line) => !line.startsWith("\\"))
    .join("\n");

  await primeStatements([sql]);

  const kept: string[] = [];

  for (const statement of rawStatementsOf(sql)) {
    const trimmed = statement.trim();

    if (trimmed !== "" && (await parses(trimmed))) {
      kept.push(trimmed.endsWith(";") ? trimmed : `${trimmed};`);
    }
  }

  return `${kept.join("\n\n")}\n`;
}

if (import.meta.main) {
  await mkdir(OUTPUT, { recursive: true });

  for (const [name, sha256] of SOURCES) {
    const response = await fetch(`${BASE}/${name}.sql`);

    if (!response.ok) {
      throw new Error(`${name}.sql: HTTP ${response.status}`);
    }

    const text = await response.text();
    const digest = createHash("sha256").update(text).digest("hex");

    if (digest !== sha256) {
      throw new Error(`${name}.sql: expected ${sha256}, got ${digest}`);
    }

    const path = fileURLToPath(new URL(`${name}.sql`, OUTPUT));

    await writeFile(path, await curate(text));
    console.log(`${name}.sql ${digest}`);
  }
}
