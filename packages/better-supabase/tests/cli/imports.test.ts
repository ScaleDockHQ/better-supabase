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
    if (entry.isDirectory()) return files(path);
    return entry.name.endsWith(".ts") ? [path] : [];
  });

const entries = new Set(
  Object.values(packageJson.exports).flatMap((target) =>
    typeof target === "object" && "@better-supabase/source" in target
      ? [resolve(SRC, "..", target["@better-supabase/source"])]
      : [],
  ),
);

describe("the CLI's library imports", () => {
  // The CLI build loads these from the package's own entries, so a deeper
  // import would put a second copy of that module in the CLI bundle.
  it("only reach the library through its entry files", () => {
    const offenders = files(CLI).flatMap((file) =>
      [...readFileSync(file, "utf8").matchAll(SPECIFIER)].flatMap(
        ([, specifier]) => {
          const target = resolve(dirname(file), specifier!);
          if (target.startsWith(`${CLI}/`) || entries.has(target)) return [];
          return [`${relative(SRC, file)} imports ${relative(SRC, target)}`];
        },
      ),
    );
    expect(offenders).toEqual([]);
  });
});
