import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { describe, expect, it } from "vitest";

import packageJson from "../../package.json" with { type: "json" };

const SRC = resolve(import.meta.dirname, "../../src");
const CLI = join(SRC, "cli");
const SPECIFIER = /(?:\bfrom\s+|\bimport\(\s*)"(\.[^"]+)"/g;

const files = (dir: string): string[] =>
  readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);

    if (entry.isDirectory()) {
      return files(path);
    }

    return entry.name.endsWith(".ts") ? [path] : [];
  });

const entries = new Set(
  Object.values(packageJson.exports).flatMap((target) =>
    typeof target === "object" && "@better-supabase/source" in target
      ? [resolve(SRC, "..", target["@better-supabase/source"])]
      : [],
  ),
);

// The seed guards key on Symbol.for, so the CLI's copy agrees with the entry's,
// and the testing entry would load optional peers (chat) the CLI never needs.
const BUNDLED = new Set([
  join(SRC, "testing/seed.ts"),
  // Data, not a module: the rename table the `naming` codemod and BS260 read.
  resolve(SRC, "../api/naming.json"),
]);

// Pure helpers and types with no module state. The facts readers share the
// text rewriters with the library (ADR 1212). Column mapping is the same
// function `gen` and `result-schema` call, and it keeps no module state.
const PURE = new Set([
  join(SRC, "sql/text-edit.ts"),
  join(SRC, "sql/function-renames.ts"),
  join(SRC, "sql/layout-types.ts"),
  join(SRC, "sql/bsb-tags.ts"),
  join(SRC, "sql/table-facts.ts"),
  join(SRC, "sql/value-maps.ts"),
  join(SRC, "core/column-kind.ts"),
  join(SRC, "config/shares.ts"),
  join(SRC, "sql/row-audit.ts"),
]);

describe("the CLI's library imports", () => {
  // The CLI build loads these from the package's own entries, so a deeper
  // import would put a second copy of that module in the CLI bundle.
  it("only reach the library through its entry files", () => {
    const offenders = files(CLI).flatMap((file) =>
      [...readFileSync(file, "utf-8").matchAll(SPECIFIER)].flatMap(
        ([, specifier]) => {
          const target = resolve(dirname(file), specifier!);

          if (
            target.startsWith(`${CLI}/`) ||
            entries.has(target) ||
            BUNDLED.has(target) ||
            PURE.has(target)
          ) {
            return [];
          }

          return [`${relative(SRC, file)} imports ${relative(SRC, target)}`];
        },
      ),
    );

    expect(offenders).toEqual([]);
  });
});
