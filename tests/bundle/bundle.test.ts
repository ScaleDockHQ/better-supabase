import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { builtinModules } from "node:module";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { promisify } from "node:util";
import { gzipSync } from "node:zlib";
import { rolldown } from "rolldown";
import { beforeAll, describe, expect, it } from "vitest";

const PACKAGE = resolve(import.meta.dirname, "../../packages/better-supabase");
const CLI_BIN = resolve(PACKAGE, "dist/cli/bin.js");
/** The CLI's startup cost: what `better-supabase --version` loads before any command. */
const CLI_STARTUP = "better-supabase CLI (startup)";
const BASELINE = resolve(import.meta.dirname, "baseline.json");
const SHIPPED_BASELINE = resolve(import.meta.dirname, "baseline-shipped.json");
const WORK = resolve(import.meta.dirname, "tmp");
/**
 * App-shaped imports, bundled and minified the way an app's bundler would.
 * The closure sizes above gzip each unminified file on its own and count every
 * export of an entry, so they run several times larger than what these ship.
 * Each one imports the fixture schema's metadata, as an app imports its own.
 */
const CONSUMERS = {
  "next + client": `
import { defineSchema, defineSupabase } from "better-supabase";
import { createClient } from "better-supabase/client";
import { createNext } from "better-supabase/next";
import meta from "./generated.meta.js";
const betterSupabase = defineSupabase(defineSchema(meta));
export const next = createNext(betterSupabase);
export const customers = () =>
  createClient(betterSupabase).db.customers.findMany({ where: { name: "Acme" } });
`,
  hono: `
import { defineSchema, defineSupabase } from "better-supabase";
import { createHono } from "better-supabase/hono";
import meta from "./generated.meta.js";
export const hono = createHono(defineSupabase(defineSchema(meta)));
`,
  "react + query": `
import { defineSchema, defineSupabase } from "better-supabase";
import { createClient } from "better-supabase/client";
import { createQueries, invalidateOnMutation } from "better-supabase/query";
import { BetterSupabaseProvider, createHooks } from "better-supabase/react";
import meta from "./generated.meta.js";
const betterSupabase = defineSupabase(defineSchema(meta));
const client = createClient(betterSupabase);
export const hooks = createHooks();
export const queries = createQueries(betterSupabase, client.db);
export { BetterSupabaseProvider, invalidateOnMutation };
`,
} satisfies Readonly<Record<string, string>>;
/** Growth allowed before the size check fails: 5% or 256 bytes, whichever is larger. */
const TOLERANCE = { ratio: 0.05, bytes: 256 };
/** Entries that may use Node built-ins. Everything else must run on any WinterTC runtime. */
const NODE_ENTRIES = new Set([
  "./cli",
  "./postgres",
  "./testing",
  "./workflow-sdk/world",
  "./eve",
]);

const BUILTINS = new Set([
  ...builtinModules,
  ...builtinModules.map((name) => `node:${name}`),
]);
/** Rolldown emits static imports at the start of a line and double-quoted specifiers. */
const SPECIFIER =
  /^(?:import|export)\b[^;]*?["']([^"']+)["'];|\bimport\("([^"]+)"\)/gm;

interface Closure {
  readonly files: readonly string[];
  readonly externals: readonly string[];
  readonly gzip: number;
}

async function closure(entry: string, dynamic = true): Promise<Closure> {
  const files = new Set<string>();
  const externals = new Set<string>();
  const visit = async (file: string): Promise<void> => {
    if (files.has(file)) return;
    files.add(file);
    const source = await readFile(file, "utf8");
    for (const [, fromClause, lazy] of source.matchAll(SPECIFIER)) {
      if (lazy !== undefined && !dynamic) continue;
      const specifier = (fromClause ?? lazy)!;
      if (!specifier.startsWith(".")) externals.add(specifier);
      else if (
        specifier.endsWith(".js") &&
        existsSync(resolve(dirname(file), specifier))
      ) {
        await visit(resolve(dirname(file), specifier));
      }
    }
  };
  await visit(entry);
  let gzip = 0;
  for (const file of files)
    gzip += gzipSync(await readFile(file), { level: 9 }).length;
  return { files: [...files], externals: [...externals].toSorted(), gzip };
}

/** Min+gzip of a consumer's entry chunk and the chunks it imports statically. */
async function shipped(name: string, source: string): Promise<number> {
  const file = join(WORK, `${name.replaceAll(/\W+/g, "-")}.js`);
  await writeFile(file, source);
  const bundle = await rolldown({
    input: file,
    platform: "neutral",
    logLevel: "silent",
    external: (id) =>
      !id.startsWith(".") &&
      !id.startsWith("/") &&
      !id.startsWith("better-supabase"),
  });
  const { output } = await bundle.generate({ format: "esm", minify: true });
  await bundle.close();
  const chunks = new Map(
    output.flatMap((item) =>
      item.type === "chunk" ? [[item.fileName, item] as const] : [],
    ),
  );
  const entry = [...chunks.values()].find((chunk) => chunk.isEntry)!;
  const seen = new Set<string>();
  const visit = (name: string): number => {
    if (seen.has(name)) return 0;
    seen.add(name);
    const chunk = chunks.get(name);
    if (!chunk) return 0;
    return chunk.imports.reduce(
      (total, imported) => total + visit(imported),
      gzipSync(chunk.code, { level: 9 }).length,
    );
  };
  return visit(entry.fileName);
}

function overBaseline(
  sizes: Readonly<Record<string, number>>,
  baseline: Readonly<Record<string, number>>,
): string[] {
  return Object.entries(sizes).flatMap(([name, size]) => {
    const limit =
      baseline[name]! +
      Math.max(TOLERANCE.bytes, baseline[name]! * TOLERANCE.ratio);
    return size > limit
      ? [`${name}: ${size} B gzip, baseline ${baseline[name]} B`]
      : [];
  });
}

const NODE_LOADED = ["./next", "./next/client", "./next/image"];

type ExportTarget =
  | string
  | null
  | readonly ExportTarget[]
  | { readonly [condition: string]: ExportTarget };

interface Manifest {
  readonly exports?: Exclude<ExportTarget, null>;
}

function exportsSubpath(
  exports: Exclude<ExportTarget, null>,
  subpath: string,
): boolean {
  const keys = Object.keys(exports);
  if (!keys.some((key) => key.startsWith("."))) return subpath === ".";
  return keys.some((key) => {
    const star = key.indexOf("*");
    if (star === -1) return key === subpath;
    return (
      subpath.startsWith(key.slice(0, star)) &&
      subpath.endsWith(key.slice(star + 1))
    );
  });
}

async function nodeResolvable(specifier: string): Promise<boolean> {
  const parts = specifier.split("/");
  const size = specifier.startsWith("@") ? 2 : 1;
  if (parts.length <= size) return true;
  const name = parts.slice(0, size).join("/");
  const root =
    name === "better-supabase" ? PACKAGE : join(PACKAGE, "node_modules", name);
  const manifest = JSON.parse(
    await readFile(join(root, "package.json"), "utf8"),
  ) as Manifest;
  const rest = parts.slice(size).join("/");
  return manifest.exports === undefined
    ? existsSync(join(root, rest))
    : exportsSubpath(manifest.exports, `./${rest}`);
}

const subpaths = async (): Promise<Map<string, string>> => {
  const manifest = JSON.parse(
    await readFile(join(PACKAGE, "package.json"), "utf8"),
  ) as {
    exports: Record<string, string | { default: string }>;
  };
  const entries = new Map<string, string>();
  for (const [subpath, target] of Object.entries(manifest.exports)) {
    if (!(target instanceof Object)) continue;
    entries.set(subpath, join(PACKAGE, target.default));
  }
  return entries;
};

describe("bundle", () => {
  const closures = new Map<string, Closure>();

  beforeAll(async () => {
    const entries = await subpaths();
    for (const [subpath, file] of entries) {
      if (!existsSync(file))
        throw new Error(`${file} is missing. Run \`pnpm build\` first.`);
      closures.set(subpath, await closure(file));
    }
    if (!existsSync(CLI_BIN))
      throw new Error(`${CLI_BIN} is missing. Run \`pnpm build\` first.`);
    closures.set(CLI_STARTUP, await closure(CLI_BIN, false));
  });

  it("keeps runtime entries free of Node built-ins (WinterTC)", () => {
    const offenders = [...closures]
      .filter(
        ([subpath]) => !NODE_ENTRIES.has(subpath) && subpath !== CLI_STARTUP,
      )
      .flatMap(([subpath, { externals }]) =>
        externals
          .filter((name) => BUILTINS.has(name) || name === "pg")
          .map((name) => `${subpath} imports ${name}`),
      );
    expect(offenders).toEqual([]);
    expect(
      closures.get("./testing")?.externals.some((name) => BUILTINS.has(name)),
    ).toBe(true);
  });

  it("imports package subpaths that Node ESM resolves", async () => {
    const offenders: string[] = [];
    for (const [subpath, { externals }] of closures) {
      for (const specifier of externals) {
        if (BUILTINS.has(specifier)) continue;
        if (!(await nodeResolvable(specifier)))
          offenders.push(`${subpath} imports ${specifier}`);
      }
    }
    expect(offenders).toEqual([]);
  });

  it.each(NODE_LOADED)(
    "loads %s in plain Node",
    { timeout: 30_000 },
    async (subpath) => {
      const file = (await subpaths()).get(subpath)!;
      const { stdout } = await promisify(execFile)(process.execPath, [
        "--input-type=module",
        "--eval",
        `const m = await import(${JSON.stringify(pathToFileURL(file).href)}); console.log(Object.keys(m).length);`,
      ]);
      expect(Number(stdout.trim())).toBeGreaterThan(0);
    },
  );

  it('keeps "use client" on the react and next/client entries', async () => {
    for (const file of ["dist/react/index.js", "dist/next/client/index.js"]) {
      const source = await readFile(join(PACKAGE, file), "utf8");
      expect(source.startsWith('"use client";')).toBe(true);
    }
  });

  it('ships a react-server build without "use client"', async () => {
    const source = await readFile(
      join(PACKAGE, "dist/react/server.js"),
      "utf8",
    );
    expect(source.includes('"use client"')).toBe(false);
  });

  it("renders SessionProvider from the react-server build as a client reference", async () => {
    const server = await readFile(
      join(PACKAGE, "dist/react/server.js"),
      "utf8",
    );
    expect(server).toContain('from "./session.js"');
    const session = await readFile(
      join(PACKAGE, "dist/react/session.js"),
      "utf8",
    );
    expect(session.startsWith('"use client";')).toBe(true);
  });

  it("keeps /query framework-neutral", () => {
    const externals = closures.get("./query")?.externals ?? [];
    expect(
      externals.filter(
        (name) =>
          name === "react" ||
          name.startsWith("react-") ||
          name.includes("react-query"),
      ),
    ).toEqual([]);
  });

  it("keeps /client/native and /powersync free of @supabase/ssr", () => {
    for (const subpath of ["./client/native", "./powersync"]) {
      expect(closures.get(subpath)?.externals ?? []).not.toContain(
        "@supabase/ssr",
      );
    }
  });

  it("never imports postgrest-typegen at runtime outside the CLI", () => {
    const offenders = [...closures]
      .filter(
        ([subpath, { externals }]) =>
          subpath !== "./cli" &&
          subpath !== CLI_STARTUP &&
          externals.some((name) =>
            name.startsWith("@supabase/postgrest-typegen"),
          ),
      )
      .map(([subpath]) => subpath);
    expect(offenders).toEqual([]);
  });

  it("stays within the size baseline", async () => {
    const sizes = Object.fromEntries(
      [...closures].map(([subpath, { gzip }]) => [subpath, gzip]),
    );
    if (process.env["BUNDLE_UPDATE"]) {
      await writeFile(BASELINE, `${JSON.stringify(sizes, null, 2)}\n`);
      return;
    }
    const baseline = JSON.parse(await readFile(BASELINE, "utf8")) as Record<
      string,
      number
    >;
    expect(
      Object.keys(sizes).toSorted(),
      "subpaths changed; run `pnpm --filter @better-supabase/bundle run update`",
    ).toEqual(Object.keys(baseline).toSorted());
    expect(
      overBaseline(sizes, baseline),
      "grew past the baseline; if intended, run `pnpm --filter @better-supabase/bundle run update`",
    ).toEqual([]);
  });

  it("keeps what app bundles ship within the min+gzip baseline", async () => {
    const sizes: Record<string, number> = {};
    await mkdir(WORK, { recursive: true });
    await copyFile(
      join(PACKAGE, "tests/fixtures/generated.meta.js"),
      join(WORK, "generated.meta.js"),
    );
    for (const [name, source] of Object.entries(CONSUMERS))
      sizes[name] = await shipped(name, source);
    if (process.env["BUNDLE_UPDATE"]) {
      await writeFile(SHIPPED_BASELINE, `${JSON.stringify(sizes, null, 2)}\n`);
      return;
    }
    const baseline = JSON.parse(
      await readFile(SHIPPED_BASELINE, "utf8"),
    ) as Record<string, number>;
    expect(Object.keys(sizes).toSorted()).toEqual(
      Object.keys(baseline).toSorted(),
    );
    expect(
      overBaseline(sizes, baseline),
      "grew past the baseline; if intended, run `pnpm --filter @better-supabase/bundle run update`",
    ).toEqual([]);
  });
});
