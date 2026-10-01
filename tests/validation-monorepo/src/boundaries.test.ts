import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const DOMAINS = ["crm", "commerce"];
const IMPORT = /^\s*import\s[^"']*["']([^"']+)["']/gmu;

async function importsOf(domain: string): Promise<Map<string, string[]>> {
  const dir = join(import.meta.dirname, domain);
  const out = new Map<string, string[]>();
  for (const file of await readdir(dir)) {
    const source = await readFile(join(dir, file), "utf8");
    out.set(
      `${domain}/${file}`,
      [...source.matchAll(IMPORT)].map((match) => match[1] ?? ""),
    );
  }
  return out;
}

describe("domain packages", () => {
  it("import the runtime only, never the generated client", async () => {
    for (const domain of DOMAINS) {
      for (const [file, specifiers] of await importsOf(domain)) {
        expect({ file, specifiers }).toEqual({
          file,
          specifiers: ["../runtime/index.ts"],
        });
      }
    }
  });
});
