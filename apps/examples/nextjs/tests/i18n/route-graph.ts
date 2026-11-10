import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";

export const APP = resolve(import.meta.dirname, "../..");
const SRC = join(APP, "src");
const LOCALE = join(SRC, "app", "[locale]");

const ROUTE_FILES =
  /^(?:page|layout|loading|error|template|not-found|default)\.tsx$/;

const EXTENSIONS = [".tsx", ".ts", "/index.tsx", "/index.ts"];
const IMPORT = /(?:from\s+|import\s*\(\s*|import\s+)"([^"]+)"/g;
const USE_EXTRACTED = /useExtracted\(\s*"([^"]+)"/g;
const PROVIDER_NAMESPACES = /<RouteMessages\s+namespaces=\{\[([^\]]*)\]\}/;

function resolveImport(from: string, specifier: string): string | undefined {
  const base = specifier.startsWith("@/")
    ? join(SRC, specifier.slice(2))
    : specifier.startsWith(".")
      ? resolve(dirname(from), specifier)
      : undefined;

  if (!base) {
    return undefined;
  }

  return [base, ...EXTENSIONS.map((extension) => base + extension)].find(
    (candidate) => existsSync(candidate) && statSync(candidate).isFile(),
  );
}

const sources = new Map<string, string>();

function read(file: string): string {
  let source = sources.get(file);

  if (source === undefined) {
    source = readFileSync(file, "utf-8");
    sources.set(file, source);
  }

  return source;
}

function isClient(source: string): boolean {
  return /^\s*(?:\/\*[\s\S]*?\*\/\s*|\/\/.*\n\s*)*["']use client["']/.test(
    source,
  );
}

/**
 * The namespaces the client components reachable from `file` read through
 * `useExtracted`. A server component reads the server's catalog, so only a
 * `"use client"` file and what it imports counts.
 */
export function clientNamespaces(file: string): Set<string> {
  const found = new Set<string>();
  const seen = new Set<string>();

  function visit(path: string, client: boolean): void {
    const key = `${client ? "c" : "s"}:${path}`;

    if (seen.has(key)) {
      return;
    }

    seen.add(key);

    const source = read(path);
    const insideClient = client || isClient(source);

    if (insideClient) {
      for (const match of source.matchAll(USE_EXTRACTED)) {
        found.add(match[1]!);
      }
    }

    for (const match of source.matchAll(IMPORT)) {
      const target = resolveImport(path, match[1]!);

      if (target) {
        visit(target, insideClient);
      }
    }
  }

  visit(file, false);

  return found;
}

/** Every route file under `dir`, including route files in nested folders. */
function routeFiles(dir: string): string[] {
  const found: string[] = [];

  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);

    if (entry.isDirectory()) {
      found.push(...routeFiles(path));
    } else if (ROUTE_FILES.test(entry.name)) {
      found.push(path);
    }
  }

  return found;
}

/** The namespaces a layout hands to its subtree, if it renders a provider. */
function declaredNamespaces(file: string): string[] | undefined {
  const match = PROVIDER_NAMESPACES.exec(read(file));

  if (!match) {
    return undefined;
  }

  return [...(match[1] ?? "").matchAll(/"([^"]+)"/g)].map((m) => m[1]!);
}

export interface ProviderScope {
  readonly from: string;
  readonly namespaces: string[];
}

/**
 * The namespaces the nearest provider at or above `file` hands down. The root
 * layout renders the outermost one.
 */
export function effectiveNamespaces(file: string): ProviderScope {
  let dir = dirname(file);

  while (dir.startsWith(LOCALE)) {
    const layout = join(dir, "layout.tsx");

    if (existsSync(layout)) {
      const declared = declaredNamespaces(layout);

      if (declared) {
        return { from: relative(APP, layout), namespaces: declared };
      }
    }

    dir = dirname(dir);
  }

  throw new Error(`no RouteMessages provider above ${relative(APP, file)}`);
}

/** The route files whose namespaces a provider layout must cover. */
export function allRouteFiles(): string[] {
  return routeFiles(LOCALE);
}

export function sorted(values: Iterable<string>): string[] {
  return [...values].toSorted();
}
