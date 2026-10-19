import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";

const repo = join(import.meta.dirname, "../../../..");
const blocksDocs = join(repo, "apps/docs/content/docs/blocks");

const KEY = String.raw`(?:blocks\.([a-z][a-z0-9-]*)\.)?(tables|columns)\.([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_]*))?`;

/** The SQL modules a page's bare `tables.<key>` and `columns.<table>.<key>` refer to. */
function modulesOf(page: string): readonly string[] {
  const manifest = BLOCK_MANIFESTS.find((block) => block.name === page);

  if (manifest !== undefined && manifest.sql.length > 0) {
    return manifest.sql;
  }

  return SQL_MODULES[page] === undefined ? [] : [page];
}

function problemsOf(file: string): string[] {
  const page = file.slice(0, -".mdx".length);
  const text = readFileSync(join(blocksDocs, file), "utf-8");
  const problems: string[] = [];

  for (const [line, content] of text.split("\n").entries()) {
    for (const code of content.matchAll(/`([^`]+)`/g)) {
      const match = new RegExp(`^${KEY}`).exec(code[1] ?? "");

      if (match === null) {
        continue;
      }

      const [, block, kind, table, column] = match;
      const modules = block === undefined ? modulesOf(page) : [block];

      if (modules.length === 0 || table === undefined) {
        continue;
      }

      const specs = modules.flatMap((name) => {
        const tables = SQL_MODULES[name]?.names?.tables;

        return tables === undefined ? [] : [tables];
      });

      const where = `blocks/${file}:${String(line + 1)} \`${code[1] ?? ""}\``;
      const spec = specs.find((tables) => table in tables)?.[table];

      if (spec === undefined) {
        problems.push(
          `${where}: no table "${table}" in ${modules.join(", ")} (${specs.flatMap((tables) => Object.keys(tables)).join(", ")})`,
        );
        continue;
      }

      if (
        kind === "columns" &&
        column !== undefined &&
        !(column in spec.columns)
      ) {
        problems.push(
          `${where}: no column "${table}.${column}" (${Object.keys(spec.columns).join(", ")})`,
        );
      }
    }
  }

  return problems;
}

describe("block docs drift", () => {
  it("names only logical tables and columns the block's SQL modules declare", () => {
    const problems = readdirSync(blocksDocs)
      .filter((file) => file.endsWith(".mdx"))
      .flatMap((file) => problemsOf(file));

    expect(problems).toEqual([]);
  });
});
