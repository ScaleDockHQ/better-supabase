/**
 * What a fresh process pays to load each better-supabase entry a Next.js page
 * imports: the evaluation time of `import()` in a new Node process (the median
 * over `runs`), and the files and gzip bytes of the closure it loads before any
 * lazy import runs. Build the package first.
 *
 *     node scripts/measure-cold-entry.ts [runs] [--json]
 */
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { gzipSync } from "node:zlib";

const ROOT = resolve(import.meta.dirname, "..");
const PACKAGE = join(ROOT, "packages/better-supabase");
const EXAMPLE = join(ROOT, "apps/examples/nextjs/src/lib/supabase");

const args = process.argv.slice(2);
const json = args.includes("--json");
const runs = Number(args.find((arg) => !arg.startsWith("--")) ?? 15);

interface Entry {
  readonly name: string;
  readonly file: string;
  /** A dist file whose static closure is measured; app files are TypeScript. */
  readonly traced: boolean;
}

const ENTRIES: readonly Entry[] = [
  {
    name: "better-supabase",
    file: join(PACKAGE, "dist/index.js"),
    traced: true,
  },
  {
    name: "better-supabase/server",
    file: join(PACKAGE, "dist/server/index.js"),
    traced: true,
  },
  {
    name: "better-supabase/next",
    file: join(PACKAGE, "dist/next/index.js"),
    traced: true,
  },
  {
    name: "better-supabase/next/instrumentation",
    file: join(PACKAGE, "dist/next/instrumentation/index.js"),
    traced: true,
  },
  {
    name: "generated schema (example)",
    file: join(EXAMPLE, "generated-schema.ts"),
    traced: false,
  },
];

/** Rolldown emits static imports at the start of a line. */
const STATIC = /^(?:import|export)\b[^;]*?["']([^"']+)["'];/gm;

interface Closure {
  readonly files: number;
  readonly gzip: number;
}

const closureOf = (entry: string): Closure => {
  const seen = new Set<string>();

  const visit = (file: string): void => {
    if (seen.has(file)) {
      return;
    }

    seen.add(file);

    for (const [, specifier] of readFileSync(file, "utf-8").matchAll(STATIC)) {
      if (specifier?.startsWith(".") && specifier.endsWith(".js")) {
        const next = resolve(dirname(file), specifier);

        if (existsSync(next)) {
          visit(next);
        }
      }
    }
  };

  visit(entry);

  let gzip = 0;

  for (const file of seen) {
    gzip += gzipSync(readFileSync(file), { level: 9 }).length;
  }

  return { files: seen.size, gzip };
};

const probe = (file: string): number => {
  const script = `const start = performance.now();
await import(${JSON.stringify(pathToFileURL(file).href)});
process.stdout.write(String(performance.now() - start));`;

  const out = execFileSync(
    process.execPath,
    ["--input-type=module", "--eval", script],
    {
      cwd: dirname(file),
      encoding: "utf-8",
      env: { ...process.env, NODE_ENV: "production" },
    },
  );

  return Number(out);
};

const median = (values: readonly number[]): number => {
  const sorted = values.toSorted((a, b) => a - b);

  return sorted[Math.floor(sorted.length / 2)] ?? 0;
};

const rows = ENTRIES.map((entry) => {
  const times = Array.from({ length: runs }, () => probe(entry.file));
  const traced = entry.traced ? closureOf(entry.file) : undefined;

  return {
    entry: entry.name,
    evalMs: Number(median(times).toFixed(1)),
    files: traced?.files ?? null,
    gzip: traced?.gzip ?? null,
  };
});

if (json) {
  console.log(JSON.stringify(rows, null, 2));
} else {
  console.log("| Entry | Evaluation (median) | Files loaded | Gzip loaded |");
  console.log("| --- | --- | --- | --- |");

  for (const row of rows) {
    console.log(
      `| \`${row.entry}\` | ${row.evalMs.toFixed(1)} ms | ${row.files ?? "-"} | ${row.gzip === null ? "-" : `${(row.gzip / 1024).toFixed(1)} KB`} |`,
    );
  }
}
