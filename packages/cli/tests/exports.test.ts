import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

/** Type-only exports declared in an entry file: `export type { A }` and `export type * from`. */
function typeExports(source: string): string[] {
  const names = new Set<string>();
  for (const match of source.matchAll(/export\s+type\s*\{([^}]*)\}/g)) {
    for (const part of match[1]!.split(",")) {
      const name = part
        .trim()
        .split(/\s+as\s+/)
        .at(-1);
      if (name) names.add(name);
    }
  }
  for (const match of source.matchAll(
    /export\s+type\s+\*\s+from\s+["']([^"']+)["']/g,
  )) {
    names.add(`* from ${match[1]!}`);
  }
  return [...names].toSorted((a, b) => a.localeCompare(b));
}

describe("public API", () => {
  it("matches the export snapshot", async () => {
    const entry = new URL("../src/index.ts", import.meta.url);
    const module = (await import(entry.href)) as Record<string, unknown>;
    const api = {
      values: Object.keys(module).toSorted((a, b) => a.localeCompare(b)),
      types: typeExports(await readFile(entry, "utf8")),
    };
    await expect(`${JSON.stringify(api, null, 2)}\n`).toMatchFileSnapshot(
      "../api/exports.json",
    );
  });
});
