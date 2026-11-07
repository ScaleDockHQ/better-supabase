import { existsSync } from "node:fs";
import { readdir, readFile, writeFile } from "node:fs/promises";
import { join, relative, resolve } from "node:path";
import { brotliCompressSync, constants, gzipSync } from "node:zlib";
import { describe, expect, it } from "vitest";

const APP = resolve(import.meta.dirname, "../../apps/examples/nextjs");
const NEXT = join(APP, ".next");
const BASELINE = resolve(import.meta.dirname, "baseline.json");

/**
 * The three sizes a visitor pays for: minified, gzip and brotli (Vercel serves
 * brotli).
 */
interface Size {
  readonly raw: number;
  readonly gzip: number;
  readonly brotli: number;
}

type Baseline = Record<string, Size>;

interface BuildManifest {
  readonly rootMainFiles: readonly string[];
  readonly polyfillFiles: readonly string[];
}

interface ClientManifest {
  readonly entryJSFiles: Readonly<Record<string, readonly string[]>>;
}

/** Entries every route carries that do not belong to the route's own tree. */
const SHARED_ENTRIES = /\/(?:not-found|global-error)$/;

const MANIFEST_FILE = "page_client-reference-manifest.js";

async function files(dir: string): Promise<string[]> {
  const found: string[] = [];

  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);

    if (entry.isDirectory()) {
      found.push(...(await files(path)));
    } else {
      found.push(path);
    }
  }

  return found;
}

/** The route's own manifest: `globalThis.__RSC_MANIFEST[route] = {...}`. */
async function clientManifest(
  file: string,
): Promise<{ route: string; manifest: ClientManifest }> {
  const source = await readFile(file, "utf-8");
  const match = /__RSC_MANIFEST\["([^"]+)"\]\s*=\s*/.exec(source);

  if (!match?.[1]) {
    throw new Error(`${file} has no __RSC_MANIFEST entry`);
  }

  const body = source.slice(match.index + match[0].length).trim();
  const json = body.replace(/;?\s*$/, "");

  // SAFETY: Next writes this file as one JSON object literal.
  return { route: match[1], manifest: JSON.parse(json) as ClientManifest };
}

/** Chunks are shared across routes, so each one is compressed once. */
const chunkSizes = new Map<string, Promise<Size>>();

function chunkSize(chunk: string): Promise<Size> {
  let size = chunkSizes.get(chunk);

  if (size === undefined) {
    size = readFile(join(NEXT, chunk)).then((bytes) => ({
      raw: bytes.length,
      gzip: gzipSync(bytes, { level: 9 }).length,
      brotli: brotliCompressSync(bytes, {
        params: { [constants.BROTLI_PARAM_QUALITY]: 11 },
      }).length,
    }));

    chunkSizes.set(chunk, size);
  }

  return size;
}

async function measure(chunks: ReadonlySet<string>): Promise<Size> {
  const sizes = await Promise.all([...chunks].map(chunkSize));

  return {
    raw: sum(sizes, "raw"),
    gzip: sum(sizes, "gzip"),
    brotli: sum(sizes, "brotli"),
  };
}

function sum(sizes: readonly Size[], key: keyof Size): number {
  return sizes.reduce((total, size) => total + size[key], 0);
}

/**
 * First Load JS per route: the root chunks every page loads, plus the chunks of
 * the layouts and the page the route renders.
 */
async function firstLoad(): Promise<Baseline> {
  const build = JSON.parse(
    await readFile(join(NEXT, "build-manifest.json"), "utf-8"),
  ) as BuildManifest;

  const shared = [...build.rootMainFiles, ...build.polyfillFiles];
  const result: Baseline = {};

  const manifests = (await files(join(NEXT, "server/app")))
    .filter((file) => file.endsWith(MANIFEST_FILE))
    .toSorted();

  for (const file of manifests) {
    const { route, manifest } = await clientManifest(file);
    const chunks = new Set(shared);

    for (const [entry, list] of Object.entries(manifest.entryJSFiles)) {
      if (!SHARED_ENTRIES.test(entry)) {
        for (const chunk of list) {
          chunks.add(chunk);
        }
      }
    }

    result[route] = await measure(chunks);
  }

  return result;
}

const SIZES = ["raw", "gzip", "brotli"] as const;
const UPDATE = Boolean(process.env["NEXT_BUILD_UPDATE"]);

async function readBaseline(): Promise<Baseline> {
  // SAFETY: the file is written by the update below.
  return JSON.parse(await readFile(BASELINE, "utf-8")) as Baseline;
}

function sizeOf(sizes: Baseline, route: string): Size {
  const size = sizes[route];

  if (size === undefined) {
    throw new Error(`no size for ${route}`);
  }

  return size;
}

describe("the Next.js example's first-load JavaScript", () => {
  it("has a build to measure", () => {
    expect(
      existsSync(join(NEXT, "build-manifest.json")),
      `${relative(process.cwd(), NEXT)} is missing; run \`pnpm --filter @better-supabase/example-nextjs build\``,
    ).toBe(true);
  });

  it.skipIf(UPDATE)(
    "never grows past the baseline of any route",
    async () => {
      const current = await firstLoad();
      const baseline = await readBaseline();

      expect(
        Object.keys(current).filter((route) => !(route in baseline)),
        "a new route needs a baseline: run `pnpm --filter @better-supabase/next-build update`",
      ).toEqual([]);

      expect(
        Object.keys(baseline).filter((route) => !(route in current)),
        "a removed route leaves the baseline: run update",
      ).toEqual([]);

      const grown = Object.entries(current).flatMap(([route, size]) =>
        SIZES.flatMap((key) => {
          const allowed = sizeOf(baseline, route)[key];

          return size[key] > allowed
            ? [`${route} ${key}: ${allowed} -> ${size[key]}`]
            : [];
        }),
      );

      expect(grown, "First Load JS grew").toEqual([]);
    },
    120_000,
  );

  // The update lowers a number or adds a route. It never raises one.
  it.runIf(UPDATE)(
    "lowers the baseline",
    async () => {
      const current = await firstLoad();
      const previous = existsSync(BASELINE) ? await readBaseline() : {};
      const next: Baseline = {};
      const grown: string[] = [];

      for (const route of Object.keys(current).toSorted()) {
        const now = sizeOf(current, route);
        const before = previous[route];

        if (before === undefined) {
          next[route] = now;
          continue;
        }

        const kept = { ...before };

        for (const size of SIZES) {
          if (now[size] > before[size]) {
            grown.push(`${route} ${size}: ${before[size]} -> ${now[size]}`);
          } else {
            kept[size] = now[size];
          }
        }

        next[route] = kept;
      }

      await writeFile(BASELINE, `${JSON.stringify(next, null, 2)}\n`);
      expect(grown, "the update never raises a baseline").toEqual([]);
    },
    120_000,
  );
});
