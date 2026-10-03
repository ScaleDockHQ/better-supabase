import { existsSync } from "node:fs";
import { readFile, writeFile } from "node:fs/promises";
import { builtinModules } from "node:module";
import { dirname, join, resolve } from "node:path";
import { gzipSync } from "node:zlib";
import { beforeAll, describe, expect, it } from "vitest";

const PACKAGE = resolve(import.meta.dirname, "../../packages/better-supabase");
const CLI_BIN = resolve(PACKAGE, "dist/cli/bin.js");
/** The CLI's startup cost: what `better-supabase --version` loads before any command. */
const CLI_STARTUP = "better-supabase CLI (startup)";
const BASELINE = resolve(import.meta.dirname, "baseline.json");
/** Growth allowed before the size check fails: 5% or 256 bytes, whichever is larger. */
const TOLERANCE = { ratio: 0.05, bytes: 256 };
/** Entries that may use Node built-ins. Everything else must run on any WinterTC runtime. */
const NODE_ENTRIES = new Set(["./cli", "./postgres", "./testing"]);

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

  it('keeps "use client" on the react entry', async () => {
    const source = await readFile(join(PACKAGE, "dist/react/index.js"), "utf8");
    expect(source.startsWith('"use client";')).toBe(true);
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
      "subpaths changed; run `pnpm --filter @better-supabase/bundle update`",
    ).toEqual(Object.keys(baseline).toSorted());
    const grown = Object.entries(sizes).flatMap(([subpath, size]) => {
      const limit =
        baseline[subpath]! +
        Math.max(TOLERANCE.bytes, baseline[subpath]! * TOLERANCE.ratio);
      return size > limit
        ? [`${subpath}: ${size} B gzip, baseline ${baseline[subpath]} B`]
        : [];
    });
    expect(
      grown,
      "grew past the baseline; if intended, run `pnpm --filter @better-supabase/bundle update`",
    ).toEqual([]);
  });
});
