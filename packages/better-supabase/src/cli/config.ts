import { loadConfig as loadC12Config } from "c12";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

import type { CliEnv } from "./env.ts";

import {
  type BetterSupabaseConfig,
  type ResolvedConfig,
  resolveConfig,
} from "../config/index.ts";
import { configIssues } from "./config-schema.ts";
import { CliError } from "./errors.ts";
import { type CliIo, display } from "./io.ts";
import { findUp, readSupabaseToml, tomlNumber } from "./supabase-toml.ts";

const CONFIG_FILES = [
  "better-supabase.config.ts",
  "better-supabase.config.mts",
  "better-supabase.config.js",
  "better-supabase.config.mjs",
  "better-supabase.config.json",
] as const;

function configIn(dir: string): string | undefined {
  for (const name of CONFIG_FILES) {
    const path = join(dir, name);
    if (existsSync(path)) return path;
  }
  return undefined;
}

export function findConfig(cwd: string, explicit?: string): string | undefined {
  if (explicit) return resolve(cwd, explicit);
  return configIn(cwd);
}

/**
 * `--config`, else the first `better-supabase.config.*` at or above `cwd`,
 * within the same `.git` boundary as the Supabase project search.
 */
export function discoverConfig(
  cwd: string,
  explicit?: string,
): string | undefined {
  if (explicit) return resolve(cwd, explicit);
  const dir = findUp(cwd, (candidate) => configIn(candidate) !== undefined);
  return dir === undefined ? undefined : configIn(dir);
}

/** Imports a project module fresh, so watch loops and tests see edits. */
export async function importModule(
  path: string,
): Promise<Record<string, unknown>> {
  // SAFETY: an ES module namespace is an object of its exports.
  return (await import(
    `${pathToFileURL(path).href}?t=${Date.now()}`
  )) as Record<string, unknown>;
}

/** The named export, then `default`, of a project module. */
export async function importExport(
  path: string,
  name: string,
): Promise<unknown> {
  if (!existsSync(path)) throw new Error(`Module not found: ${path}`);
  const loaded = await importModule(path);
  return loaded[name] ?? loaded["default"];
}

function isConfig(value: unknown): value is BetterSupabaseConfig {
  return configIssues(value).length === 0;
}

/**
 * Loads `better-supabase.config.*` with c12 and checks it against the config
 * schema. c12 imports `.ts` natively (Node 24 strips the types), so no
 * loader is needed; rc files, `package.json`, env overrides and `extends`
 * are off so the one file is the whole config. A discovered file sets the
 * project root to its own directory; `--config` keeps `cwd` as the root.
 */
export async function loadConfig(
  cwd: string,
  explicit?: string,
): Promise<ResolvedConfig> {
  const path = discoverConfig(cwd, explicit);
  if (!path) return resolveConfig({}, cwd);
  if (!existsSync(path)) {
    throw new CliError("config_not_found", `Config file not found: ${path}`);
  }
  const { config } = await loadC12Config({
    cwd,
    configFile: path,
    rcFile: false,
    globalRc: false,
    packageJson: false,
    dotenv: false,
    envName: false,
    extend: false,
    giget: false,
  });
  if (!isConfig(config)) {
    const issues = configIssues(config);
    throw new CliError(
      "config_invalid",
      `${display(cwd, path)} is not a valid config:\n${issues.map((issue) => `  ${issue}`).join("\n")}`,
      { issues },
    );
  }
  return resolveConfig(config, explicit ? cwd : dirname(path));
}

/** `[db] port` or `[api] port` from `supabase/config.toml`. */
export async function readSupabasePort(
  root: string,
  section: "db" | "api",
): Promise<number | undefined> {
  const toml = await readSupabaseToml(root);
  return toml ? tomlNumber(toml.document, [section, "port"]) : undefined;
}

/** The connection string piped in for `--db-url-stdin`, when it was passed. */
export async function stdinDatabaseUrl(
  enabled: boolean | undefined,
  io: CliIo,
): Promise<string | undefined> {
  if (enabled !== true) return undefined;
  const url = (await io.stdin?.())?.trim();
  if (!url) {
    throw new CliError(
      "missing_value",
      '--db-url-stdin read nothing from stdin. Pipe the connection string: printf %s "$URL" | better-supabase <command> --db-url-stdin',
      { flag: "--db-url-stdin" },
    );
  }
  return url;
}

/** Connection string: stdin, config, `$DATABASE_URL`, then the local stack. */
export async function databaseUrl(
  config: ResolvedConfig,
  env: CliEnv,
  fromStdin?: string,
): Promise<string> {
  if (fromStdin) return fromStdin;
  if (config.source.dbUrl) return config.source.dbUrl;
  if (env.DATABASE_URL) return env.DATABASE_URL;
  const port = (await readSupabasePort(config.root, "db")) ?? 54322;
  return `postgresql://postgres:postgres@127.0.0.1:${port}/postgres`;
}
