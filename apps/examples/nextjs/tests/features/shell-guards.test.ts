import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { describe, expect, it } from "vitest";

const SRC = join(process.cwd(), "src");
const APP = join(SRC, "app");

const walk = (dir: string): string[] =>
  readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);

    return statSync(path).isDirectory() ? walk(path) : [path];
  });

const ALL = walk(SRC).filter((path) => /\.tsx?$/u.test(path));
const text = new Map(ALL.map((path) => [path, readFileSync(path, "utf-8")]));
const read = (path: string): string => text.get(path) ?? "";

const IMPORT = /(?:from|import)\s+["']([^"']+)["']/gu;

const resolve = (from: string, spec: string): string | null => {
  const base = spec.startsWith("@/")
    ? join(SRC, spec.slice(2))
    : spec.startsWith(".")
      ? join(dirname(from), spec)
      : null;

  if (base === null) {
    return null;
  }

  for (const candidate of [
    `${base}.tsx`,
    `${base}.ts`,
    join(base, "index.tsx"),
    join(base, "index.ts"),
  ]) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  return null;
};

/** Every module a layout reaches through static imports. */
const reachable = (entry: string): Set<string> => {
  const seen = new Set<string>();
  const queue = [entry];

  while (queue.length > 0) {
    const file = queue.pop() ?? "";

    if (seen.has(file)) {
      continue;
    }

    seen.add(file);

    for (const match of read(file).matchAll(IMPORT)) {
      const target = resolve(file, match[1] ?? "");

      if (target !== null) {
        queue.push(target);
      }
    }
  }

  return seen;
};

const isClient = (path: string): boolean =>
  /^\s*["']use client["']/u.test(read(path));

const rel = (path: string): string => relative(SRC, path);

describe("layout-reachable client code budget", () => {
  // Client modules the app layout imports statically ship with every page.
  // The numbers are today's: a new shell feature loads on intent or behind a
  // lazy wrapper, or the ratchet is lowered first with a reason.
  const layout = join(APP, "[locale]", "(app)", "layout.tsx");
  const files = [...reachable(layout)].filter(isClient);
  const bytes = files.reduce((sum, path) => sum + read(path).length, 0);

  it("keeps the client modules the app layout reaches in check", () => {
    expect(files.length).toBeLessThanOrEqual(MAX_CLIENT_MODULES);
    expect(bytes).toBeLessThanOrEqual(MAX_CLIENT_BYTES);
  });

  it("does not reach a heavy editor or chart library from the layout", () => {
    const heavy =
      /["'](?:@xyflow\/react|@dnd-kit\/[a-z]+|recharts|streamdown)["']/u;

    expect(
      files.filter((path) => heavy.test(read(path))).map(rel),
    ).toStrictEqual([]);
  });
});

// Set from the first run; see the failure message for the measured value.
// 36: the lazy Assistant button of the header (its panel loads on intent).
const MAX_CLIENT_MODULES = 36;
const MIN_ENSURE_STATIC = 59;

// 110_187: the lazy search wrapper takes the `areas` prop; the area commands
// load with the palette, on intent.
// 110_264: the Change requests menu item (its label case and icon).
// 110_455: AuthzRefresh takes the live authorization version, so the browser
// does not call caller_authz_version() itself (EX-906).
const MAX_CLIENT_BYTES = 110_455;

describe("shell prerender table", () => {
  const exports = (name: string): string[] =>
    walk(APP)
      .filter((path) => /(?:layout|page)\.tsx$/u.test(path))
      .filter((path) =>
        new RegExp(`export const ${name}\\b`, "u").test(read(path)),
      )
      .map((path) => relative(APP, path))
      .toSorted();

  const mode = (path: string): string =>
    /export const ensureStatic = "([a-z]+)"/u.exec(
      read(join(APP, path)),
    )?.[1] ?? "none";

  it("prerenders the shell in the two layouts and two demo pages", () => {
    const shell = exports("ensureStatic").filter(
      (path) => mode(path) === "shell",
    );

    expect(shell).toStrictEqual([
      "[locale]/(app)/assistant/tour/page.tsx",
      "[locale]/(app)/layout.tsx",
      "[locale]/islands/page.tsx",
      "[locale]/layout.tsx",
    ]);
  });

  it("uses only the shell and prefetch modes, and never loses a page", () => {
    const all = exports("ensureStatic");

    for (const path of all) {
      expect(["shell", "prefetch"]).toContain(mode(path));
    }

    // Floor: a page that drops its guarantee is a regression.
    expect(all.length).toBeGreaterThanOrEqual(MIN_ENSURE_STATIC);
  });

  it("gives every instant page a loading shell that is not a page", () => {
    const instant = exports("instant");

    expect(instant.length).toBeGreaterThan(0);

    for (const path of instant) {
      expect(path.endsWith("page.tsx")).toBe(true);
    }
  });
});

describe("cache tag agreement", () => {
  const defined = new Map<string, string>();

  for (const path of ALL.filter((file) => file.endsWith("-cache.ts"))) {
    for (const match of read(path).matchAll(
      /export const ([A-Z][A-Z0-9_]*_TAG)\s*=\s*tagFor\(/gu,
    )) {
      defined.set(match[1] ?? "", rel(path));
    }
  }

  const names = (pattern: RegExp): Set<string> => {
    const out = new Set<string>();

    for (const path of ALL) {
      for (const call of read(path).matchAll(pattern)) {
        for (const tag of (call[1] ?? "").matchAll(/[A-Z][A-Z0-9_]*_TAG\b/gu)) {
          out.add(tag[0]);
        }
      }
    }

    return out;
  };

  const readTags = names(/cacheTag\(([^)]*)\)/gu);
  const written = names(/refreshCaller\(\s*[a-z]+\s*,\s*\[([^\]]*)\]/gu);

  it("expires only tags that a read carries", () => {
    expect(
      [...written].filter((tag) => !readTags.has(tag)).toSorted(),
    ).toStrictEqual([]);
  });

  it("defines every tag a read or a write names", () => {
    const unknown = [...readTags, ...written].filter(
      (tag) => !defined.has(tag) && !PLAIN_TAGS.has(tag),
    );

    expect(unknown.toSorted()).toStrictEqual([]);
  });

  it("has no read tag that no write can expire, beyond today's", () => {
    const idle = [...readTags].filter((tag) => !written.has(tag));

    expect(idle.length).toBeLessThanOrEqual(MAX_IDLE_READ_TAGS);
  });
});

const MAX_IDLE_READ_TAGS = 1000;

// `connectors` and `credits` are plain strings, not `tagFor` tags (finding 1).
const PLAIN_TAGS = new Set(["CONNECTORS_TAG", "CREDITS_TAG"]);
