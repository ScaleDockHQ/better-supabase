// Picks the library unit tests a change can reach, with a reason for each file.
// Usage: node scripts/select-tests.ts [base-ref] [--files a,b]   (default base: origin/main)
// Prints `full` when the change is one the selector can't map to tests, otherwise `files <n>` and
// one test path per line, relative to packages/better-supabase. The reasons go to stderr.
// Widening beats guessing: a path that no import and no rule explains selects the full suite.
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { argv, exit } from "node:process";

const PACKAGE = "packages/better-supabase";

export interface Selection {
  readonly mode: "full" | "files";
  readonly tests: readonly string[];
  readonly reasons: readonly string[];
}

/** A change to one of these can alter any test, so the full suite runs. */
const FULL = [
  /^package\.json$/,
  /^pnpm-lock\.yaml$/,
  /^pnpm-workspace\.yaml$/,
  /^turbo\.json$/,
  /^tsconfig\.json$/,
  /^\.node-version$/,
  /^packages\/typescript-config\//,
  /^packages\/better-supabase\/(?:package|tsconfig[^/]*|turbo|tsdown\.config|vitest\.config)\.[a-z.]+$/,
  /^packages\/better-supabase\/tests\/setup\//,
  /^scripts\/select-tests\.ts$/,
  /^\.github\/workflows\/(?:ci|verify|release)\.yml$/,
];

/**
 * Files outside the module graph that tests read from disk. `readers` matches
 * the text of a test file that reads them; every such test runs when the path
 * changes.
 */
const OWNERS: readonly { readonly path: RegExp; readonly readers: RegExp }[] = [
  {
    path: /^apps\/docs\/content\//,
    readers: /apps\/docs|docs\/content|content\/docs/,
  },
  { path: /^AGENTS\.md$/, readers: /AGENTS\.md/ },
  {
    path: /^supabase\//,
    readers:
      /supabase\/(?:schemas|snapshot|migrations|tests|seed)|["'/]supabase["'/]/,
  },
  { path: /^scripts\/recipes\//, readers: /scripts\/recipes|recipes/ },
  { path: /^\.cursor-plugin\//, readers: /cursor-plugin/ },
  { path: /^tests\/init-fixture\//, readers: /init-fixture/ },
  { path: /^packages\/registry\//, readers: /packages\/registry|registry/ },
  {
    path: /^packages\/better-supabase\/tests\/.*__golden__\//,
    readers: /__golden__/,
  },
  { path: /^packages\/better-supabase\/skills\//, readers: /skills/ },
  { path: /^packages\/better-supabase\/schemas\//, readers: /schemas/ },
  {
    path: /^packages\/better-supabase\/api\//,
    readers: /api\/(?:exports|naming)|exports\.json|naming\.json/,
  },
  {
    path: /^packages\/better-supabase\/bin\//,
    readers: /bin\/better-supabase|bin\//,
  },
  {
    path: /^docs\/(?:decisions|agents)\//,
    readers: /docs\/(?:decisions|agents)|decisions|agents/,
  },
];

/**
 * A path that no test can read: documentation of the package and the other
 * apps.
 */
const INERT = [
  /^apps\/(?:marketing)\//,
  /^apps\/examples\//,
  /^tests\/(?!init-fixture\/)[^/]+\//,
  /^\.(?:cursor|claude|agents|changeset|vscode)\//,
  /\.(?:md|mdx)$/,
  /^packages\/better-supabase\/(?:CHANGELOG|README|LICENSE)/,
  /^\.github\//,
  /^scripts\/(?!recipes\/)/,
];

const SOURCE = /\.(?:ts|tsx|mts|cts)$/;

const IMPORT =
  /(?:\bfrom\s*|\bimport\s*\(\s*|\bimport\s+|\brequire\s*\(\s*)["'`]([^"'`\n]+)["'`]/g;

function walk(dir: string, out: string[]): string[] {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name === "__golden__") {
      continue;
    }

    const full = join(dir, entry.name);

    if (entry.isDirectory()) {
      walk(full, out);
    } else if (SOURCE.test(entry.name)) {
      out.push(full);
    }
  }

  return out;
}

function resolveImport(from: string, specifier: string): string | undefined {
  const base = resolve(dirname(from), specifier);
  const stripped = base.replace(/\.(?:js|jsx|mjs)$/, "");

  const candidates = [
    base,
    `${stripped}.ts`,
    `${stripped}.tsx`,
    `${base}.ts`,
    `${base}.tsx`,
    join(base, "index.ts"),
    join(base, "index.tsx"),
  ];

  return candidates.find((candidate) => {
    try {
      return statSync(candidate).isFile() && SOURCE.test(candidate);
    } catch {
      return false;
    }
  });
}

interface Graph {
  readonly importers: Map<string, Set<string>>;
  readonly texts: Map<string, string>;
  readonly selfImporters: Set<string>;
}

/**
 * Reads every source and test file of the package once: static and dynamic
 * literal imports.
 */
export function buildGraph(root: string): Graph {
  const pkg = join(root, PACKAGE);

  const files = [
    ...walk(join(pkg, "src"), []),
    ...walk(join(pkg, "tests"), []),
  ];

  const importers = new Map<string, Set<string>>();
  const texts = new Map<string, string>();
  const selfImporters = new Set<string>();

  for (const file of files) {
    const text = readFileSync(file, "utf-8");

    texts.set(file, text);

    for (const match of text.matchAll(IMPORT)) {
      const specifier = match[1] ?? "";

      if (
        specifier === "better-supabase" ||
        specifier.startsWith("better-supabase/")
      ) {
        // The package's own name resolves to its build output: any source change reaches it.
        selfImporters.add(file);
      }

      if (!specifier.startsWith(".")) {
        continue;
      }

      const target = resolveImport(file, specifier);

      if (target !== undefined) {
        const set = importers.get(target) ?? new Set<string>();

        set.add(file);
        importers.set(target, set);
      }
    }
  }

  return { importers, texts, selfImporters };
}

const TEST_FILE = /\.test(?:-d)?\.(?:ts|tsx)$/;
// A test that lists the files under src checks every one of them, so any src change runs it.

const SCANS_SOURCE =
  /(?:readdirSync|readdir|globSync|glob\()[\s\S]{0,300}?(?:["'`/]src["'`/]|\.\.\/src)/;

export function select(
  changed: readonly string[],
  root: string,
  graph: Graph = buildGraph(root),
): Selection {
  const pkg = join(root, PACKAGE);
  const tests = new Set<string>();
  const reasons: string[] = [];
  const seen = new Set<string>();
  const pending: string[] = [];

  const full = (reason: string): Selection => ({
    mode: "full",
    tests: [],
    reasons: [...reasons, `full suite: ${reason}`],
  });

  const readersOf = (pattern: RegExp): string[] =>
    [...graph.texts.entries()]
      .filter(([file, text]) => TEST_FILE.test(file) && pattern.test(text))
      .map(([file]) => file);

  for (const path of changed) {
    if (FULL.some((pattern) => pattern.test(path))) {
      return full(`${path} can change every test`);
    }

    const absolute = join(root, path);

    if (
      graph.texts.has(absolute) ||
      (SOURCE.test(path) && path.startsWith(`${PACKAGE}/`))
    ) {
      if (!existsSync(absolute)) {
        // A deleted file: whoever imported it is changed too, and a deleted test selects nothing.
        if (!TEST_FILE.test(path)) {
          return full(`${path} was deleted`);
        }

        continue;
      }

      if (!seen.has(absolute)) {
        seen.add(absolute);
        pending.push(absolute);
        reasons.push(`${path}: changed`);
      }

      // Source files: scanners that read src as text (entries, WinterTC, lazy imports).
      if (path.startsWith(`${PACKAGE}/src/`)) {
        for (const reader of readersOf(SCANS_SOURCE)) {
          if (!tests.has(reader)) {
            tests.add(reader);
            reasons.push(
              `${relative(pkg, reader)}: reads src as text (${path})`,
            );
          }
        }

        for (const importer of graph.selfImporters) {
          if (TEST_FILE.test(importer) && !tests.has(importer)) {
            tests.add(importer);
            reasons.push(
              `${relative(pkg, importer)}: imports the built package (${path})`,
            );
          }
        }
      }

      continue;
    }

    const owner = OWNERS.find((entry) => entry.path.test(path));

    if (owner !== undefined) {
      for (const reader of readersOf(owner.readers)) {
        if (!tests.has(reader)) {
          tests.add(reader);
          reasons.push(`${relative(pkg, reader)}: reads ${path}`);
        }
      }

      continue;
    }

    if (INERT.some((pattern) => pattern.test(path))) {
      continue;
    }

    if (path.startsWith(`${PACKAGE}/`) || !path.includes("/")) {
      return full(`${path} has no rule`);
    }
  }

  while (pending.length > 0) {
    const current = pending.pop();

    if (current === undefined) {
      break;
    }

    if (TEST_FILE.test(current) && !tests.has(current)) {
      tests.add(current);
    }

    for (const importer of graph.importers.get(current) ?? []) {
      if (!seen.has(importer)) {
        seen.add(importer);
        pending.push(importer);

        if (TEST_FILE.test(importer)) {
          reasons.push(
            `${relative(pkg, importer)}: imports ${relative(root, current)}`,
          );
        }
      }
    }
  }

  const list = [...tests]
    .filter(
      (file) =>
        file.startsWith(join(pkg, "tests")) && !file.includes(".integration."),
    )
    .map((file) => relative(pkg, file))
    .toSorted((a, b) => a.localeCompare(b));

  return { mode: "files", tests: list, reasons };
}

function changedSince(root: string, base: string): string[] | undefined {
  const result = spawnSync(
    "git",
    ["diff", "--name-only", "--diff-filter=ACDMR", `${base}...HEAD`],
    { cwd: root, encoding: "utf-8" },
  );

  if (result.status !== 0) {
    return undefined;
  }

  const dirty = spawnSync("git", ["status", "--porcelain"], {
    cwd: root,
    encoding: "utf-8",
  });

  const local = dirty.stdout
    .split("\n")
    .filter((line) => line.length > 3)
    .map((line) => line.slice(3));

  return [...new Set([...result.stdout.split("\n"), ...local])].filter(
    (line) => line !== "",
  );
}

if (import.meta.main) {
  const root = resolve(import.meta.dirname, "..");
  const flag = argv.indexOf("--files");

  const base =
    argv[2] !== undefined && !argv[2].startsWith("--")
      ? argv[2]
      : "origin/main";

  const given =
    flag === -1
      ? undefined
      : (argv[flag + 1] ?? "").split(",").filter((file) => file !== "");

  const changed = given ?? changedSince(root, base);

  if (changed === undefined) {
    console.error(`No diff against ${base}.`);
    console.log("full");
    exit(0);
  }

  const selection = select(changed, root);

  for (const reason of selection.reasons) {
    console.error(reason);
  }

  if (selection.mode === "full") {
    console.log("full");
  } else {
    console.log(`files ${selection.tests.length}`);

    for (const test of selection.tests) {
      console.log(test);
    }
  }
}
