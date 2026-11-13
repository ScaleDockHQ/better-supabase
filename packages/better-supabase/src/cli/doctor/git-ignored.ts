import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, join, relative, resolve, sep } from "node:path";

import type { CliEnv } from "../env.ts";
import type { RunProcess } from "../exec.ts";

import { runProcess } from "../exec.ts";

/** One `.gitignore` line as a regular expression, with its negation. */
interface IgnoreRule {
  readonly negated: boolean;
  readonly pattern: RegExp;
}

const SPECIAL = /[.+^${}()|[\]\\]/g;

/**
 * A `.gitignore` line as a rule for file paths relative to its folder: `*`
 * stays inside a segment, `**` crosses them, and a pattern without an inner
 * slash matches at any depth. Directory-only patterns (`dir/`) match the files
 * below the folder.
 */
function ruleOf(line: string): IgnoreRule | undefined {
  const trimmed = line.trim();

  if (trimmed.length === 0 || trimmed.startsWith("#")) {
    return undefined;
  }

  const negated = trimmed.startsWith("!");
  const body = negated ? trimmed.slice(1) : trimmed;
  const directory = body.endsWith("/");
  const bare = directory ? body.slice(0, -1) : body;
  const anchored = bare.startsWith("/") || bare.slice(0, -1).includes("/");
  const path = bare.replace(/^\//, "");

  const source = path
    .replaceAll(SPECIAL, "\\$&")
    .replaceAll("**", "\u0000")
    .replaceAll("*", "[^/]*")
    .replaceAll("?", "[^/]")
    .replaceAll("\u0000", ".*");

  const prefix = anchored ? "^" : "^(?:.*/)?";
  const suffix = directory ? "/.*$" : "(?:/.*)?$";

  return { negated, pattern: new RegExp(`${prefix}${source}${suffix}`) };
}

/** Whether `rules` ignore `path`; the last matching rule decides. */
export function ignoredBy(
  rules: readonly string[],
  path: string,
): boolean | undefined {
  let decided: boolean | undefined;

  for (const rule of rules.map(ruleOf)) {
    if (rule?.pattern.test(path) === true) {
      decided = !rule.negated;
    }
  }

  return decided;
}

/** The folders from `root` up to the one with `.git`, or the filesystem root. */
function foldersUp(root: string): readonly string[] {
  const folders: string[] = [];

  for (let folder = resolve(root); ; folder = dirname(folder)) {
    folders.push(folder);

    if (existsSync(join(folder, ".git")) || dirname(folder) === folder) {
      return folders;
    }
  }
}

/**
 * The paths of `paths` the `.gitignore` files from `root` up to the repository
 * root ignore. A deeper file overrides a shallower one, as in git.
 */
async function ignoredByFiles(
  root: string,
  paths: readonly string[],
): Promise<ReadonlySet<string>> {
  const folders = foldersUp(root).toReversed();

  const files = await Promise.all(
    folders.map(async (folder) => ({
      folder,
      lines: await readFile(join(folder, ".gitignore"), "utf-8")
        .then((text) => text.split("\n"))
        .catch(() => []),
    })),
  );

  return new Set(
    paths.filter((path) => {
      const absolute = resolve(root, path);
      let ignored = false;

      for (const { folder, lines } of files) {
        const inside = relative(folder, absolute).split(sep).join("/");
        ignored = ignoredBy(lines, inside) ?? ignored;
      }

      return ignored;
    }),
  );
}

/**
 * The paths of `paths` (relative to `root`) that git ignores. In a work tree
 * `git check-ignore` decides, with every `.gitignore`, `.git/info/exclude` and
 * the global excludes, and a tracked file never counts as ignored. Without git
 * or a work tree, the `.gitignore` files from `root` up to the repository root
 * decide.
 */
export async function gitIgnored(
  root: string,
  paths: readonly string[],
  env: CliEnv,
  run: RunProcess = runProcess,
): Promise<ReadonlySet<string>> {
  if (paths.length === 0) {
    return new Set();
  }

  const result = await run(
    "git",
    ["check-ignore", "--", ...paths],
    root,
    env,
  ).catch(() => undefined);

  // 0: some are ignored, 1: none are; anything else means no work tree or no git.
  if (result !== undefined && (result.code === 0 || result.code === 1)) {
    const listed = new Set(
      result.stdout
        .split("\n")
        .map((line) => line.trim())
        .filter((line) => line.length > 0),
    );

    return new Set(paths.filter((path) => listed.has(path)));
  }

  return ignoredByFiles(root, paths);
}
