import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

/** An optional peer of better-supabase and the version the app has installed. */
export interface PeerVersion {
  readonly name: string;
  /** The range better-supabase declares in `peerDependencies`. */
  readonly range: string;
  /** The installed version, `undefined` when the app doesn't have it. */
  readonly installed: string | undefined;
}

type Version = readonly [number, number, number, readonly string[]];

const VERSION =
  /^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/;

function parseVersion(text: string): Version | undefined {
  const match = VERSION.exec(text.trim());

  if (!match) {
    return undefined;
  }

  return [
    Number(match[1]),
    Number(match[2] ?? 0),
    Number(match[3] ?? 0),
    match[4] === undefined ? [] : match[4].split("."),
  ];
}

const NUMERIC = /^\d+$/;

function compareIdentifiers(a: string, b: string): number {
  const numeric = NUMERIC.test(a);

  if (numeric !== NUMERIC.test(b)) {
    return numeric ? -1 : 1;
  }

  if (numeric) {
    return Number(a) - Number(b);
  }

  return a < b ? -1 : a > b ? 1 : 0;
}

function compare(a: Version, b: Version): number {
  for (const index of [0, 1, 2] as const) {
    if (a[index] !== b[index]) {
      return a[index] - b[index];
    }
  }

  const [, , , left] = a;
  const [, , , right] = b;

  if (left.length === 0 || right.length === 0) {
    return right.length - left.length;
  }

  for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
    const x = left[index];
    const y = right[index];

    if (x === undefined) {
      return -1;
    }

    if (y === undefined) {
      return 1;
    }

    const order = compareIdentifiers(x, y);

    if (order !== 0) {
      return order;
    }
  }

  return 0;
}

const sameRelease = (a: Version, b: Version): boolean =>
  a[0] === b[0] && a[1] === b[1] && a[2] === b[2];

type Operator = ">=" | ">" | "<=" | "<" | "=";

interface Comparator {
  readonly operator: Operator;
  readonly version: Version;
}

const COMPARATOR = /^(>=|<=|>|<|=|\^)?\s*(\S+)$/;

/** The next version a caret range excludes: `^1.2` is below 2, `^0.4` below 0.5. */
function caretCeiling([major, minor, patch]: Version): Version {
  if (major > 0) {
    return [major + 1, 0, 0, []];
  }

  if (minor > 0) {
    return [0, minor + 1, 0, []];
  }

  return [0, 0, patch + 1, []];
}

function comparators(range: string): Comparator[] | undefined {
  const parts = range
    .trim()
    .replaceAll(/(>=|<=|>|<|=|\^)\s+/g, "$1")
    .split(/\s+/)
    .filter((part) => part.length > 0);

  const result: Comparator[] = [];

  for (const part of parts) {
    const match = COMPARATOR.exec(part);
    const version = match ? parseVersion(match[2]!) : undefined;

    if (!match || !version) {
      return undefined;
    }

    const operator = match[1] ?? "=";

    if (operator === "^") {
      result.push(
        { operator: ">=", version },
        { operator: "<", version: caretCeiling(version) },
      );
    } else {
      // SAFETY: COMPARATOR only captures these operators besides "^".
      result.push({ operator: operator as Operator, version });
    }
  }

  return result;
}

function holds(
  version: Version,
  { operator, version: bound }: Comparator,
): boolean {
  const order = compare(version, bound);

  switch (operator) {
    case ">=": {
      return order >= 0;
    }

    case ">": {
      return order > 0;
    }

    case "<=": {
      return order <= 0;
    }

    case "<": {
      return order < 0;
    }

    case "=": {
      return order === 0;
    }

    default: {
      const unreachable: never = operator;

      return unreachable;
    }
  }
}

/**
 * Whether `version` is in `range`, for the ranges better-supabase declares:
 * `||` alternatives of space-separated comparators (`>=`, `>`, `<=`, `<`,
 * exact) and caret ranges. As in npm, a prerelease only matches a set with a
 * comparator on the same release that has a prerelease too. `undefined` when
 * either can't be parsed.
 */
export function satisfies(version: string, range: string): boolean | undefined {
  const parsed = parseVersion(version);

  if (!parsed) {
    return undefined;
  }

  const sets = range.split("||").map(comparators);

  if (sets.some((set) => set === undefined)) {
    return undefined;
  }

  return sets.some(
    (set) =>
      set !== undefined &&
      set.every((comparator) => holds(parsed, comparator)) &&
      (parsed[3].length === 0 ||
        set.some(
          ({ version: bound }) =>
            bound[3].length > 0 && sameRelease(bound, parsed),
        )),
  );
}

async function readManifest(
  path: string,
): Promise<Record<string, unknown> | undefined> {
  try {
    const data: unknown = JSON.parse(await readFile(path, "utf-8"));

    // SAFETY: a package.json is a JSON object; callers check each field.
    return typeof data === "object" && data !== null
      ? (data as Record<string, unknown>)
      : undefined;
  } catch {
    return undefined;
  }
}

/**
 * The version of `name` that `root` resolves, looking in `node_modules` up to
 * the file system root.
 */
export async function installedVersion(
  name: string,
  root: string,
): Promise<string | undefined> {
  let dir = root;

  for (;;) {
    const manifest = await readManifest(
      join(dir, "node_modules", name, "package.json"),
    );

    if (typeof manifest?.["version"] === "string") {
      return manifest["version"];
    }

    const parent = dirname(dir);

    if (parent === dir) {
      return undefined;
    }

    dir = parent;
  }
}

/** The version in the nearest `package.json` above a resolved module file. */
export async function versionAt(file: string): Promise<string | undefined> {
  let dir = dirname(file);

  for (;;) {
    const manifest = await readManifest(join(dir, "package.json"));

    if (manifest && typeof manifest["version"] === "string") {
      return manifest["version"];
    }

    const parent = dirname(dir);

    if (parent === dir) {
      return undefined;
    }

    dir = parent;
  }
}

/** The `peerDependencies` of the better-supabase package this CLI ships in. */
export async function declaredPeers(): Promise<Record<string, string>> {
  const manifest = await readManifest(
    fileURLToPath(import.meta.resolve("better-supabase/package.json")),
  );

  const peers = manifest?.["peerDependencies"];

  if (typeof peers !== "object" || peers === null) {
    return {};
  }

  return Object.fromEntries(
    Object.entries(peers).filter(
      (entry): entry is [string, string] => typeof entry[1] === "string",
    ),
  );
}

/** Every declared peer with the version `root` resolves. */
export async function peerVersions(root: string): Promise<PeerVersion[]> {
  const peers = await declaredPeers();

  return Promise.all(
    Object.entries(peers).map(async ([name, range]) => ({
      name,
      range,
      installed: await installedVersion(name, root),
    })),
  );
}
