import { loadConfig as loadC12Config } from "c12";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

import type { CliEnv } from "./env.ts";

import {
  type BetterSupabaseConfig,
  type EnvironmentConfig,
  type ResolvedConfig,
  resolveConfig,
} from "../config/index.ts";
import { configIssues } from "./config-schema.ts";
import { databaseUrlCredential } from "./core/credentials.ts";
import { CliError } from "./core/errors.ts";
import { type CliIo, display, readStdin } from "./core/io.ts";
import { importFresh } from "./fresh-import.ts";
import { readStackStatus } from "./stack-status.ts";
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

    if (existsSync(path)) {
      return path;
    }
  }

  return undefined;
}

export function findConfig(cwd: string, explicit?: string): string | undefined {
  if (explicit) {
    return resolve(cwd, explicit);
  }

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
  if (explicit) {
    return resolve(cwd, explicit);
  }

  const dir = findUp(cwd, (candidate) => configIn(candidate) !== undefined);

  return dir === undefined ? undefined : configIn(dir);
}

/** The named export, then `default`, of a project module. */
export async function importExport(
  path: string,
  name: string,
): Promise<unknown> {
  if (!existsSync(path)) {
    throw new CliError("not_found", `Module not found: ${path}`);
  }

  const loaded = await importFresh(path);

  return loaded[name] ?? loaded["default"];
}

function isConfig(value: unknown): value is BetterSupabaseConfig {
  return configIssues(value).length === 0;
}

const isPlainObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** Objects merge key by key; arrays and every other value replace what `base` had. */
function mergeConfig(
  base: Readonly<Record<string, unknown>>,
  override: Readonly<Record<string, unknown>>,
): Record<string, unknown> {
  const merged: Record<string, unknown> = { ...base };

  for (const [key, value] of Object.entries(override)) {
    if (value === undefined) {
      continue;
    }

    const current = merged[key];
    merged[key] =
      isPlainObject(current) && isPlainObject(value)
        ? mergeConfig(current, value)
        : value;
  }

  return merged;
}

/**
 * The config with the `environment` blocks merged in: `$env.<name>`, then
 * the `$development`, `$production`, `$test` or `$ci` shorthand. Every `$`
 * key is dropped from the result.
 */
export function applyEnvironment(
  config: BetterSupabaseConfig,
  environment: string | undefined,
): BetterSupabaseConfig {
  const {
    $schema: _schema,
    $env,
    $development,
    $production,
    $test,
    $ci,
    ...base
  } = config;

  if (environment === undefined) {
    return base;
  }

  const shorthand = new Map<string, EnvironmentConfig | undefined>([
    ["development", $development],
    ["production", $production],
    ["test", $test],
    ["ci", $ci],
  ]).get(environment);

  let merged: Record<string, unknown> = { ...base };

  for (const block of [$env?.[environment], shorthand]) {
    if (block) {
      merged = mergeConfig(merged, block);
    }
  }

  if (!isConfig(merged)) {
    throw new CliError(
      "config_invalid",
      `The ${environment} environment makes the config invalid:\n${configIssues(
        merged,
      )
        .map((issue) => `  ${issue}`)
        .join("\n")}`,
    );
  }

  return merged;
}

export function defaultConfig(
  cwd: string,
  explicit?: string,
  environment?: string,
  path: string | undefined = discoverConfig(cwd, explicit),
): ResolvedConfig {
  const resolved = resolveConfig({}, !path || explicit ? cwd : dirname(path));

  return environment === undefined ? resolved : { ...resolved, environment };
}

/**
 * Loads `better-supabase.config.*` with c12 and checks it against the config
 * schema. c12 imports `.ts` natively (Node 24 strips the types), so no
 * loader is needed; rc files, `package.json`, env overrides and `extends`
 * are off so the one file is the whole config. `environment` merges its
 * blocks in (`applyEnvironment`); c12's own `envName` is off because it
 * concatenates arrays. A discovered file sets the project root to its own
 * directory; `--config` keeps `cwd` as the root. `path` is the file
 * `discoverConfig` found, for callers that already looked it up.
 */
export async function loadConfig(
  cwd: string,
  explicit?: string,
  environment?: string,
  path: string | undefined = discoverConfig(cwd, explicit),
): Promise<ResolvedConfig> {
  const withEnvironment = (resolved: ResolvedConfig): ResolvedConfig =>
    environment === undefined ? resolved : { ...resolved, environment };

  if (!path) {
    return withEnvironment(resolveConfig({}, cwd));
  }

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

  return withEnvironment(
    resolveConfig(
      applyEnvironment(config, environment),
      explicit ? cwd : dirname(path),
    ),
  );
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
  if (enabled !== true) {
    return undefined;
  }

  const url = (await readStdin(io, "--db-url-stdin")).trim();

  if (!url) {
    throw new CliError(
      "missing_value",
      '--db-url-stdin read nothing from stdin. Pipe the connection string: printf %s "$URL" | better-supabase <command> --db-url-stdin',
      { flag: "--db-url-stdin" },
    );
  }

  return url;
}

/**
 * Connection string: stdin, config, `$DATABASE_URL`, `$SUPABASE_DB_URL`, then the
 * local stack: the `[db] port` in `config.toml`, else the running stack's
 * `DB_URL`, else port 54322.
 */
export async function databaseUrl(
  config: ResolvedConfig,
  env: CliEnv,
  fromStdin?: string,
): Promise<string> {
  const given = databaseUrlCredential(config, env, fromStdin);

  if (given) {
    return given.value;
  }

  let resolved = localUrls.get(config);

  if (!resolved) {
    resolved = localDatabaseUrl(config.root, env);
    localUrls.set(config, resolved);
  }

  return resolved;
}

/** One lookup per loaded config, so a run asks `supabase status` at most once. */
const localUrls = new WeakMap<ResolvedConfig, Promise<string>>();

async function localDatabaseUrl(root: string, env: CliEnv): Promise<string> {
  const port = await readSupabasePort(root, "db");

  if (port === undefined && (await readSupabaseToml(root))) {
    // The stack engine (`[experimental] stack`) picks the ports per checkout,
    // so only its status knows them.
    const stack = await readStackStatus(root, env).catch(() => undefined);
    const url = stack?.ok ? stack.status["DB_URL"] : undefined;

    if (typeof url === "string" && url.length > 0) {
      return url;
    }
  }

  return `postgresql://postgres:postgres@127.0.0.1:${port ?? 54_322}/postgres`;
}
