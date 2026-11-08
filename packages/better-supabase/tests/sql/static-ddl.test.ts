import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { splitStatements } from "../../src/sql/pipeline/split.ts";

/**
 * The `do` blocks left in the schema files the library generates for this
 * repository and the validation fixtures (ADR 0251, ADR 0400). A schema diff
 * can't see what a top-level `do` block builds at run time, so each count may
 * go down and never up. `UPDATE_PRACTICES=1` rewrites the baseline after a
 * count dropped.
 */
const root = join(import.meta.dirname, "../../../..");
const baselineFile = join(import.meta.dirname, "static-ddl-baseline.json");

const FOLDERS = [
  "supabase/schemas/_better_supabase",
  ...readdirSync(join(root, "tests"))
    .filter((name) => name.startsWith("validation-"))
    .toSorted()
    .map((name) => `tests/${name}/supabase/schemas`),
];

interface Counts {
  readonly doBlocks: number;
  readonly withExecute: number;
}

const DO_BLOCK = /^do\s+(?:\$|language\b)/i;

/**
 * Dynamic SQL: `execute format(...)` or `execute '...'`, not `execute
 * function`.
 */
const EXECUTES = /\bexecute\s+(?:(?:pg_catalog\.)?format\s*\(|')/i;

function measure(): Record<string, Counts> {
  const result: Record<string, Counts> = {};

  for (const folder of FOLDERS) {
    let names: string[];

    try {
      names = readdirSync(join(root, folder)).filter(
        (name) =>
          name.startsWith("900_better_supabase_") && name.endsWith(".sql"),
      );
    } catch {
      continue;
    }

    for (const name of names.toSorted()) {
      const blocks = splitStatements(
        readFileSync(join(root, folder, name), "utf-8"),
      )
        .map((statement) => statement.text.replaceAll(/\s+/g, " "))
        .filter((statement) => DO_BLOCK.test(statement));

      if (blocks.length > 0) {
        result[`${folder}/${name}`] = {
          doBlocks: blocks.length,
          withExecute: blocks.filter((block) => EXECUTES.test(block)).length,
        };
      }
    }
  }

  return result;
}

describe("static DDL in the generated schema files", () => {
  const now = measure();

  if (process.env["UPDATE_PRACTICES"] === "1") {
    writeFileSync(baselineFile, `${JSON.stringify(now, null, 2)}\n`);
  }

  // SAFETY: the baseline is this test's own file, written by `measure`.
  const baseline = JSON.parse(readFileSync(baselineFile, "utf-8")) as Record<
    string,
    Counts
  >;

  it.each(["doBlocks", "withExecute"] as const)(
    "%s never grows in a file",
    (key) => {
      const grown = Object.entries(now)
        .filter(([file, counts]) => counts[key] > (baseline[file]?.[key] ?? 0))
        .map(
          ([file, counts]) =>
            `${file}: ${String(counts[key])} (baseline ${String(baseline[file]?.[key] ?? 0)})`,
        );

      expect(grown).toEqual([]);
    },
  );

  it("lists a file only while it still has the findings", () => {
    const stale = Object.entries(baseline)
      .filter(
        ([file, counts]) =>
          (now[file]?.doBlocks ?? 0) < counts.doBlocks ||
          (now[file]?.withExecute ?? 0) < counts.withExecute,
      )
      .map(([file]) => file);

    // A count dropped: run `UPDATE_PRACTICES=1 vitest run tests/sql/static-ddl.test.ts`.
    expect(stale).toEqual([]);
  });
});
