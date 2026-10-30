import { existsSync } from "node:fs";
import { glob, readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig, SqlWorkflow } from "../../config/index.ts";
import type { TextFile } from "../doctor/rules.ts";
import type { SupabaseToml } from "../supabase-toml.ts";

import { CONFIG_DEFAULTS } from "../../config/index.ts";
import { byCodePoint } from "../compare.ts";
import { detectWorkspace } from "../project/workspace.ts";
import { schemaPaths } from "../supabase-toml.ts";

export const ENV_FILES: readonly string[] = [
  ".env",
  ".env.local",
  ".env.example",
  ".env.development",
  ".env.development.local",
  ".env.production",
  ".env.production.local",
];

export async function readText(
  root: string,
  path: string,
): Promise<TextFile | undefined> {
  const absolute = resolve(root, path);

  return existsSync(absolute)
    ? { path, text: await readFile(absolute, "utf-8") }
    : undefined;
}

/**
 * The declarative schemas in the diff engine's order, then the migrations
 * newest first.
 */
export async function sqlFiles(
  root: string,
  toml: SupabaseToml | undefined,
  workflow?: SqlWorkflow,
): Promise<TextFile[]> {
  const read = async (path: string): Promise<TextFile> => ({
    path,
    text: await readFile(resolve(root, path), "utf-8"),
  });

  const schemas = await Promise.all(
    (await schemaPaths(root, toml, workflow)).files.map(read),
  );

  const migrationsPath = `${toml?.dir ?? "supabase"}/migrations`;
  const migrationsDir = resolve(root, migrationsPath);

  const migrations = existsSync(migrationsDir)
    ? (await readdir(migrationsDir))
        .filter((name) => name.endsWith(".sql"))
        .toSorted()
        .toReversed()
        .map((name) => `${migrationsPath}/${name}`)
    : [];

  return [...schemas, ...(await Promise.all(migrations.map(read)))];
}

/**
 * The `doctor.sources` globs. Left at the default in a workspace root, they
 * also cover each package's `src`.
 */
export async function sourceGlobs(
  config: ResolvedConfig,
): Promise<readonly string[]> {
  const { sources } = config.doctor;

  if (sources !== CONFIG_DEFAULTS.doctor.sources) {
    return sources;
  }

  const workspace = await detectWorkspace(config.root);

  if (workspace === undefined) {
    return sources;
  }

  return [
    ...new Set([
      ...sources,
      ...workspace.packages
        .filter((pkg) => pkg.dir !== "" && pkg.dir !== ".")
        .flatMap((pkg) => sources.map((glob) => `${pkg.dir}/${glob}`)),
    ]),
  ];
}

/** Files matching `doctor.sources`, skipping dependencies and build output. */
export async function sourceFiles(config: ResolvedConfig): Promise<TextFile[]> {
  const files: TextFile[] = [];
  const seen = new Set<string>();

  for await (const path of glob([...(await sourceGlobs(config))], {
    cwd: config.root,
    exclude: (name) => name === "node_modules" || name === ".next",
  })) {
    if (seen.has(path)) {
      continue;
    }

    seen.add(path);
    files.push({
      path,
      text: await readFile(resolve(config.root, path), "utf-8"),
    });
  }

  return files.toSorted((a, b) => byCodePoint(a.path, b.path));
}
