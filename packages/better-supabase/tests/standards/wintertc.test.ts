import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { builtinModules } from "node:module";
import { dirname, relative, resolve } from "node:path";
import { describe, expect, it } from "vitest";

// WinterTC (Ecma TC55) Minimum Common Web API: runtime entries may use only
// web-platform globals and modules, so they load on Node, Deno, Bun, workerd
// and edge runtimes. Node-only entries are listed in AGENTS.md invariant 6.
const SRC = resolve(import.meta.dirname, "../../src");
const NODE_ENTRIES = new Set([
  "postgres/index",
  "testing/index",
  "workflow-sdk/world/index",
]);
const BUILTINS = new Set([
  ...builtinModules,
  ...builtinModules.map((name) => `node:${name}`),
]);
const NODE_ONLY = new Set([...BUILTINS, "pg"]);
/** Node globals with no WinterTC equivalent. */
const NODE_GLOBALS =
  /\b(?:Buffer\.|__dirname|__filename|require\(|process\.(?:cwd|exit|argv|stdout|stderr|on)\b)/;

/** Value imports only: `import type` and `export type` vanish at build time. */
const SPECIFIER =
  /^\s*(?:import|export)(?!\s+type\b)\b[^;]*?\bfrom\s+["']([^"']+)["']|^\s*import\s+["']([^"']+)["']|\bimport\(\s*["']([^"']+)["']\s*\)/gm;

async function entries(): Promise<string[]> {
  const config = await readFile(resolve(SRC, "../tsdown.config.ts"), "utf8");
  const list = /const entries = \[([^\]]+)\]/.exec(config)![1]!;
  return [...list.matchAll(/"([^"]+)"/g)].map((match) => match[1]!);
}

async function closure(entry: string) {
  const files = new Set<string>();
  const externals = new Map<string, string>();
  const visit = async (file: string): Promise<void> => {
    if (files.has(file)) return;
    files.add(file);
    const source = await readFile(file, "utf8");
    for (const match of source.matchAll(SPECIFIER)) {
      const specifier = (match[1] ?? match[2] ?? match[3])!;
      if (specifier.startsWith(".")) {
        const target = resolve(
          dirname(file),
          specifier.replace(/\.js$/, ".ts"),
        );
        // Relative specifiers that don't resolve are inside generated-code templates.
        if (existsSync(target)) await visit(target);
      } else if (!externals.has(specifier))
        externals.set(specifier, relative(SRC, file));
    }
  };
  await visit(resolve(SRC, `${entry}.ts`));
  return { files, externals };
}

describe("WinterTC runtime entries", async () => {
  const all = await entries();
  const runtime = all.filter((entry) => !NODE_ENTRIES.has(entry));

  it("lists the Node-only entries that exist", () => {
    for (const entry of NODE_ENTRIES) expect(all).toContain(entry);
  });

  it.each(runtime)("%s imports no Node built-in or pg", async (entry) => {
    const { externals } = await closure(entry);
    const offenders = [...externals]
      .filter(([name]) => NODE_ONLY.has(name))
      .map(([name, file]) => `${file} imports ${name}`);
    expect(offenders).toEqual([]);
  });

  it.each(runtime)("%s uses no Node-only global", async (entry) => {
    const { files } = await closure(entry);
    const offenders: string[] = [];
    for (const file of files) {
      const code = (await readFile(file, "utf8")).replaceAll(
        /\/\/.*$|\/\*[^]*?\*\//gm,
        "",
      );
      const hit = NODE_GLOBALS.exec(code);
      if (hit) offenders.push(`${relative(SRC, file)}: ${hit[0]}`);
    }
    expect(offenders).toEqual([]);
  });

  it("testing does use Node built-ins, so the walk sees them", async () => {
    const { externals } = await closure("testing/index");
    expect([...externals.keys()].some((name) => BUILTINS.has(name))).toBe(true);
  });
});
