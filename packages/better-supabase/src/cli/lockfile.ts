import { readFile } from "node:fs/promises";
import { dirname, join, relative } from "node:path";

import { installedVersion } from "./peers.ts";

/** The lockfiles doctor reads, in the order it looks for them in a folder. */
export const LOCKFILES = [
  "pnpm-lock.yaml",
  "package-lock.json",
  "yarn.lock",
  "bun.lock",
] as const;

export type Lockfile = (typeof LOCKFILES)[number];

/** The versions of a package a lockfile resolves. */
export interface LockedVersions {
  /** Relative to the project root, `../../pnpm-lock.yaml` in a workspace. */
  readonly path: string;
  /** The command that installs what the lockfile names. */
  readonly install: string;
  /** Registry versions only; workspace links and file paths are left out. */
  readonly versions: readonly string[];
}

/** The project's better-supabase: what `node_modules` has and what is locked. */
export interface PackageInstall {
  readonly installed: string | undefined;
  readonly lock: LockedVersions | undefined;
}

const INSTALL: Readonly<Record<Lockfile, string>> = {
  "pnpm-lock.yaml": "pnpm install",
  "package-lock.json": "npm install",
  "yarn.lock": "yarn install",
  "bun.lock": "bun install",
};

const escape = (text: string): string =>
  text.replaceAll(/[.*+?^${}()|[\]\\/]/g, String.raw`\$&`);

/** A semver version at the start of a string, without pnpm's peer suffix. */
const VERSION = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?/;

function packageLockVersions(name: string, text: string): string[] {
  let data: unknown;

  try {
    data = JSON.parse(text);
  } catch {
    return [];
  }

  const packages =
    typeof data === "object" && data !== null && "packages" in data
      ? data.packages
      : undefined;

  if (typeof packages !== "object" || packages === null) {
    return [];
  }

  return Object.entries(packages).flatMap(([path, entry]: [string, unknown]) =>
    (path === `node_modules/${name}` ||
      path.endsWith(`/node_modules/${name}`)) &&
    typeof entry === "object" &&
    entry !== null &&
    "version" in entry &&
    typeof entry.version === "string" &&
    !("link" in entry && entry.link === true)
      ? [entry.version]
      : [],
  );
}

/**
 * The registry versions of `name` that `text`, a lockfile of kind `kind`,
 * resolves. Each format names a package by its resolved version:
 * `name@1.2.3(peer@4)` keys in pnpm, `node_modules/name` entries in npm, a
 * `version` line under the `name@range` header in yarn, and `"name@1.2.3"` in
 * bun.
 */
export function lockedVersions(
  kind: Lockfile,
  name: string,
  text: string,
): string[] {
  const at = escape(name);
  let found: string[];

  switch (kind) {
    case "pnpm-lock.yaml": {
      found = [
        ...text.matchAll(
          new RegExp(String.raw`^\s+['"]?/?${at}@([^:'"\s]+)['"]?:`, "gm"),
        ),
      ].map((match) => match[1] ?? "");
      break;
    }

    case "package-lock.json": {
      found = packageLockVersions(name, text);
      break;
    }

    case "yarn.lock": {
      found = [
        ...text.matchAll(
          new RegExp(
            String.raw`^"?${at}@(?!workspace:|link:|portal:|file:)[^\n]*:\n(?:[ \t]+[^\n]*\n)*?[ \t]+version:? "?([^"\n]+)"?`,
            "gm",
          ),
        ),
      ].map((match) => match[1] ?? "");
      break;
    }

    case "bun.lock": {
      found = [
        ...text.matchAll(new RegExp(String.raw`"${at}@([^"]+)"`, "g")),
      ].map((match) => match[1] ?? "");
      break;
    }

    default: {
      const never: never = kind;

      return never;
    }
  }

  return [
    ...new Set(
      found.flatMap((version) => {
        const match = VERSION.exec(version);

        return match ? [match[0]] : [];
      }),
    ),
  ];
}

async function readLockfile(
  dir: string,
): Promise<{ kind: Lockfile; path: string; text: string } | undefined> {
  for (const kind of LOCKFILES) {
    const path = join(dir, kind);
    const text = await readFile(path, "utf-8").catch(() => undefined);

    if (text !== undefined) {
      return { kind, path, text };
    }
  }

  return undefined;
}

/**
 * The versions of `name` in the nearest lockfile at or above `root`, the one
 * the package manager installs from.
 */
export async function lockedPackage(
  name: string,
  root: string,
): Promise<LockedVersions | undefined> {
  let dir = root;

  for (;;) {
    const lockfile = await readLockfile(dir);

    if (lockfile) {
      return {
        path: relative(root, lockfile.path),
        install: INSTALL[lockfile.kind],
        versions: lockedVersions(lockfile.kind, name, lockfile.text),
      };
    }

    const parent = dirname(dir);

    if (parent === dir) {
      return undefined;
    }

    dir = parent;
  }
}

/** The better-supabase that `root` installs, next to the lockfile's (BS607). */
export async function betterSupabaseInstall(
  root: string,
): Promise<PackageInstall> {
  const [installed, lock] = await Promise.all([
    installedVersion("better-supabase", root),
    lockedPackage("better-supabase", root),
  ]);

  return { installed, lock };
}
