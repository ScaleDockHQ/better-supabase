import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

const PACKAGE = resolve(import.meta.dirname, "../../packages/better-supabase");
const CLI_DIST = join(PACKAGE, "dist/cli");
const IMPORT_SPECIFIER = /(?:\bfrom\s*|\bimport\(\s*|\bimport\s*)"([^"]+)"/g;

/** The names `deps.onlyBundle` lists for the CLI build in `tsdown.config.ts`. */
async function inlinedPackages(): Promise<string[]> {
  const config = await readFile(join(PACKAGE, "tsdown.config.ts"), "utf-8");
  const list = /onlyBundle:\s*\[([^\]]*)\]/.exec(config)?.[1] ?? "";

  return [...list.matchAll(/"([^"]+)"/g)].map((match) => match[1]!);
}

async function files(dir: string): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true });

  const nested = await Promise.all(
    entries.map(async (entry) =>
      entry.isDirectory()
        ? files(join(dir, entry.name))
        : [join(dir, entry.name)],
    ),
  );

  return nested.flat().filter((file) => file.endsWith(".js"));
}

describe.skipIf(!existsSync(CLI_DIST))("the built CLI", () => {
  it("imports none of the packages the build inlines", async () => {
    const inlined = await inlinedPackages();
    const found: string[] = [];

    for (const file of await files(CLI_DIST)) {
      const text = await readFile(file, "utf-8");

      for (const match of text.matchAll(IMPORT_SPECIFIER)) {
        const specifier = match[1]!;

        if (
          inlined.some(
            (name) => specifier === name || specifier.startsWith(`${name}/`),
          )
        ) {
          found.push(`${file.slice(PACKAGE.length + 1)}: ${specifier}`);
        }
      }
    }

    expect(inlined).toContain("valibot");
    expect(found).toEqual([]);
  });
});
