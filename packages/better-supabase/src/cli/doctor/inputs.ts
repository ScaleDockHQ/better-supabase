import { existsSync } from "node:fs";
import { glob, readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig, SqlWorkflow } from "../../config/index.ts";
import type { TextFile } from "../doctor/rules.ts";

import { byCodePoint } from "../compare.ts";
import { schemaPaths, type SupabaseToml } from "../supabase-toml.ts";

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
        .sort()
        .reverse()
        .map((name) => `${migrationsPath}/${name}`)
    : [];

  return [...schemas, ...(await Promise.all(migrations.map(read)))];
}

/** Files matching `doctor.sources`, skipping dependencies and build output. */
export async function sourceFiles(config: ResolvedConfig): Promise<TextFile[]> {
  const files: TextFile[] = [];

  for await (const path of glob([...config.doctor.sources], {
    cwd: config.root,
    exclude: (name) => name === "node_modules" || name === ".next",
  })) {
    files.push({
      path,
      text: await readFile(resolve(config.root, path), "utf-8"),
    });
  }

  return files.sort((a, b) => byCodePoint(a.path, b.path));
}
