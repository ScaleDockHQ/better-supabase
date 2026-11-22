import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const EXTENSIONS = [
  "",
  ".ts",
  ".mts",
  ".cts",
  ".js",
  ".mjs",
  ".cjs",
  ".json",
  "/index.ts",
  "/index.js",
] as const;

/** `from "./x"`, `import("./x")` and `import "./x"`, for a relative specifier. */
const SPECIFIER = /(?:\bfrom\s*|\bimport\s*\(?\s*)["'](\.{1,2}\/[^"']+)["']/gu;

/** The files a config file reads when it loads, and the keys they hash to. */
const keys = new Map<string, string>();

async function resolveSpecifier(
  from: string,
  specifier: string,
): Promise<{ path: string; text: string } | undefined> {
  const candidates = [
    ...EXTENSIONS.map((extension) => `${specifier}${extension}`),
    // TypeScript sources import `./x.js` for `./x.ts`.
    ...(specifier.endsWith(".js") ? [`${specifier.slice(0, -3)}.ts`] : []),
  ];

  for (const candidate of candidates) {
    const path = resolve(dirname(from), candidate);

    // A directory or a missing file fails the read, so the next form is tried.
    const text = await readFile(path, "utf-8").catch(() => undefined);

    if (text !== undefined) {
      return { path, text };
    }
  }

  return undefined;
}

/**
 * A hash of the config file and the project files it imports, directly or
 * through each other (relative specifiers only: a package is covered by the
 * lockfile and the CLI version). A render or a generator may call a function
 * the config imports, and the cache holds the result of that call, so a change
 * in an imported helper has to change the key. Each file is read once; a file
 * that cannot be read is left out, which only makes the key coarser.
 */
export async function configImportsHash(file: string): Promise<string> {
  const seen = new Map<string, string>();
  const queue = [file];

  while (queue.length > 0) {
    const path = queue.pop();

    if (path === undefined || seen.has(path)) {
      continue;
    }

    const text = await readFile(path, "utf-8").catch(() => undefined);

    if (text === undefined) {
      continue;
    }

    seen.set(path, text);

    const found = await Promise.all(
      [...text.matchAll(SPECIFIER)].map(async ([, specifier]) =>
        specifier === undefined ? undefined : resolveSpecifier(path, specifier),
      ),
    );

    for (const entry of found) {
      if (entry !== undefined && !seen.has(entry.path)) {
        queue.push(entry.path);
      }
    }
  }

  const hash = createHash("sha256");

  for (const [path, text] of [...seen].toSorted(([a], [b]) =>
    a.localeCompare(b),
  )) {
    hash.update(`${path}\n${text}\n`);
  }

  return hash.digest("hex");
}

/** Records the imports hash of the config loaded for `root`. */
export function rememberConfigImports(root: string, hash: string): void {
  keys.set(root, hash);
}

/** The hash `loadConfig` recorded for `root`, or `""` for a config with no file. */
export function configImportsKey(root: string): string {
  return keys.get(root) ?? "";
}
