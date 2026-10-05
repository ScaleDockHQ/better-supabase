import { existsSync } from "node:fs";
import { glob, readFile } from "node:fs/promises";
import { join, posix } from "node:path";

import { detectProject, type Project } from "./project.ts";

/** One package of a pnpm, npm, yarn or bun workspace. */
export interface WorkspacePackage {
  /** Relative to the workspace root, with forward slashes. */
  readonly dir: string;
  readonly project: Project;
}

export interface Workspace {
  /** The file that declares the packages: `pnpm-workspace.yaml` or `package.json`. */
  readonly file: string;
  readonly packages: readonly WorkspacePackage[];
}

const unquote = (value: string): string =>
  value
    .replace(/\s+#.*$/, "")
    .trim()
    .replace(/^(["'])(.*)\1$/, "$2");

/** The `packages` globs of `pnpm-workspace.yaml`, in block or flow style. */
export function pnpmWorkspacePatterns(text: string): string[] {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((line) => /^packages\s*:/.test(line));
  if (start === -1) return [];
  const inline = /^packages\s*:\s*\[(.*)\]\s*(?:#.*)?$/.exec(lines[start]!);
  if (inline) {
    return inline[1]!
      .split(",")
      .map(unquote)
      .filter((entry) => entry !== "");
  }
  const patterns: string[] = [];
  for (const line of lines.slice(start + 1)) {
    if (/^\s*(?:#.*)?$/.test(line)) continue;
    const item = /^\s+-\s*(.+)$/.exec(line);
    if (!item) break;
    patterns.push(unquote(item[1]!));
  }
  return patterns.filter((entry) => entry !== "");
}

function packageJsonPatterns(workspaces: unknown): string[] {
  let list: unknown = workspaces;
  if (
    typeof workspaces === "object" &&
    workspaces !== null &&
    "packages" in workspaces
  )
    list = workspaces.packages;
  return Array.isArray(list)
    ? list.filter((entry): entry is string => typeof entry === "string")
    : [];
}

async function matches(root: string, pattern: string): Promise<string[]> {
  const dirs: string[] = [];
  const base = pattern.replace(/^\.\//, "").replace(/\/$/, "");
  for await (const path of glob(`${base}/package.json`, {
    cwd: root,
    exclude: (name) => name === "node_modules",
  })) {
    dirs.push(posix.dirname(path.replaceAll("\\", "/")));
  }
  return dirs;
}

/**
 * The workspace declared at `root` by `pnpm-workspace.yaml` or the
 * `workspaces` field of `package.json`, with its packages in path order.
 * `undefined` when `root` declares none.
 */
export async function detectWorkspace(
  root: string,
): Promise<Workspace | undefined> {
  let file: string;
  let patterns: string[];
  const yaml = join(root, "pnpm-workspace.yaml");
  if (existsSync(yaml)) {
    file = "pnpm-workspace.yaml";
    patterns = pnpmWorkspacePatterns(await readFile(yaml, "utf8"));
  } else {
    const path = join(root, "package.json");
    if (!existsSync(path)) return undefined;
    let pkg: unknown;
    try {
      pkg = JSON.parse(await readFile(path, "utf8"));
    } catch {
      return undefined;
    }
    if (typeof pkg !== "object" || pkg === null || !("workspaces" in pkg))
      return undefined;
    file = "package.json";
    patterns = packageJsonPatterns(pkg.workspaces);
    if (patterns.length === 0) return undefined;
  }
  const included = new Set<string>();
  const excluded = new Set<string>();
  for (const pattern of patterns) {
    const negated = pattern.startsWith("!");
    for (const dir of await matches(root, negated ? pattern.slice(1) : pattern))
      (negated ? excluded : included).add(dir);
  }
  const dirs = [...included]
    .filter((dir) => dir !== "." && !excluded.has(dir))
    .sort();
  const packages = await Promise.all(
    dirs.map(async (dir) => ({
      dir,
      project: await detectProject(join(root, dir)),
    })),
  );
  return { file, packages };
}

/** The package `init` suggests: one that uses better-supabase, then one with a framework. */
export function suggestedPackage(workspace: Workspace): string | undefined {
  const packages = workspace.packages;
  return (
    packages.find((entry) => "better-supabase" in entry.project.dependencies) ??
    packages.find((entry) => entry.project.frameworks.length > 0) ??
    packages[0]
  )?.dir;
}
