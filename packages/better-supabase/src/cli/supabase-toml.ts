import { existsSync, readdirSync } from "node:fs";
import { glob, readFile } from "node:fs/promises";
import { dirname, join, posix, relative } from "node:path";
import { parse } from "smol-toml";

import type { SqlWorkflow } from "../config/index.ts";

export type TomlValue =
  | string
  | number
  | boolean
  | readonly TomlValue[]
  | TomlTable;

export interface TomlTable {
  readonly [key: string]: TomlValue;
}

/** `supabase/config.toml`, parsed. */
export interface SupabaseToml {
  /** Relative to the project root (`../../supabase/config.toml` in a monorepo package). */
  readonly path: string;
  /** The `supabase` directory, relative to the project root. */
  readonly dir: string;
  readonly text: string;
  /** The keys present in the file (snake_case, as written), after `env()` interpolation when parsed by `@supabase/config`. */
  readonly document: TomlTable;
  readonly parser: "@supabase/config" | "smol-toml";
}

const CONFIG_TOML = "supabase/config.toml";

/**
 * The nearest directory at or above `start` where `found` is true. The search
 * stops after the first directory with `.git`, so a checkout never picks up a
 * project outside it.
 */
export function findUp(
  start: string,
  found: (dir: string) => boolean,
): string | undefined {
  let dir = start;
  for (;;) {
    if (found(dir)) return dir;
    const parent = dirname(dir);
    if (parent === dir || existsSync(join(dir, ".git"))) return undefined;
    dir = parent;
  }
}

/**
 * The nearest directory at or above `start` that has `supabase/config.toml`,
 * like the Supabase CLI's search, within the same `.git` boundary.
 */
export function findSupabaseRoot(start: string): string | undefined {
  return findUp(start, (dir) => existsSync(join(dir, CONFIG_TOML)));
}

/** The repository root for `start`: the directory with `.git`, else the Supabase project root, else `start`. */
export function findRepoRoot(start: string): string {
  let dir = start;
  for (;;) {
    if (existsSync(join(dir, ".git"))) return dir;
    const parent = dirname(dir);
    if (parent === dir) return findSupabaseRoot(start) ?? start;
    dir = parent;
  }
}

/** The `supabase` directory relative to `root`: the one `findSupabaseRoot` finds, or `supabase`. */
export function supabaseDir(root: string): string {
  const found = findSupabaseRoot(root);
  return found === undefined
    ? "supabase"
    : relativePath(root, join(found, "supabase"));
}

/** `path` under `from`, with forward slashes. */
function relativePath(from: string, path: string): string {
  return relative(from, path).replaceAll("\\", "/") || ".";
}

interface SupabaseConfigIo {
  loadCliConfig(
    cwd: string,
    options: { readonly tomlOnly: boolean; readonly search: boolean },
  ): Promise<{ readonly document?: Record<string, unknown> } | null>;
}

/**
 * `@supabase/config` is an optional peer (it needs `effect` and
 * `@effect/platform-node`), so it is imported lazily through a variable:
 * projects without it get smol-toml instead of a load error.
 */
async function loadSupabaseConfig(): Promise<SupabaseConfigIo | undefined> {
  const specifier = "@supabase/config/io";
  try {
    // SAFETY: @supabase/config/io exports this interface; the catch falls back
    // when it is missing.
    return (await import(specifier)) as SupabaseConfigIo;
  } catch {
    return undefined;
  }
}

function toTomlValue(value: unknown): TomlValue {
  if (Array.isArray(value)) return value.map(toTomlValue);
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "bigint") return Number(value);
  if (typeof value === "object" && value !== null) {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, toTomlValue(item)]),
    );
  }
  if (
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
  )
    return value;
  return String(value);
}

/** `text` as TOML, with dates as ISO strings; an empty table when it does not parse. */
export function parseToml(text: string): TomlTable {
  try {
    return Object.fromEntries(
      Object.entries(parse(text)).map(([key, value]) => [
        key,
        toTomlValue(value),
      ]),
    );
  } catch {
    return {};
  }
}

const parsed = new Map<
  string,
  { readonly text: string; readonly toml: Promise<SupabaseToml> }
>();

/**
 * Reads `supabase/config.toml` from `root` or the nearest parent that has
 * one (`findSupabaseRoot`). A file with `env()` values goes through
 * `@supabase/config` when it is installed, which resolves them; any other
 * file, or a project without it, is parsed with smol-toml, since loading
 * `@supabase/config` costs hundreds of milliseconds. Parses are reused while
 * the file's text is unchanged.
 */
export async function readSupabaseToml(
  root: string,
): Promise<SupabaseToml | undefined> {
  const found = findSupabaseRoot(root);
  if (found === undefined) return undefined;
  const absolute = join(found, CONFIG_TOML);
  const text = await readFile(absolute, "utf8");
  const key = `${root}\0${absolute}`;
  const cached = parsed.get(key);
  if (cached?.text === text) return cached.toml;
  const toml = parseSupabaseToml(found, text, {
    path: relativePath(root, absolute),
    dir: relativePath(root, join(found, "supabase")),
  });
  parsed.set(key, { text, toml });
  return toml;
}

async function parseSupabaseToml(
  found: string,
  text: string,
  location: { readonly path: string; readonly dir: string },
): Promise<SupabaseToml> {
  const io = text.includes("env(") ? await loadSupabaseConfig() : undefined;
  if (io) {
    try {
      const loaded = await io.loadCliConfig(found, {
        tomlOnly: true,
        search: false,
      });
      if (loaded?.document) {
        // SAFETY: @supabase/config parses config.toml into plain TOML values.
        return {
          ...location,
          text,
          document: loaded.document as TomlTable,
          parser: "@supabase/config",
        };
      }
    } catch {
      // An invalid file for @supabase/config's schema still has readable keys.
    }
  }
  return {
    ...location,
    text,
    document: parseToml(text),
    parser: "smol-toml",
  };
}

/** The value at `path` (`['auth', 'jwt_expiry']`), if present. */
export function tomlGet(
  document: TomlTable,
  path: readonly string[],
): TomlValue | undefined {
  let value: TomlValue | undefined = document;
  for (const key of path) {
    if (typeof value !== "object" || Array.isArray(value)) return undefined;
    // SAFETY: the check above narrows value to a TOML table.
    value = (value as TomlTable)[key];
  }
  return value;
}

export function tomlNumber(
  document: TomlTable,
  path: readonly string[],
): number | undefined {
  const value = tomlGet(document, path);
  if (typeof value === "number") return value;
  if (
    typeof value === "string" &&
    value.trim() !== "" &&
    Number.isFinite(Number(value))
  )
    return Number(value);
  return undefined;
}

/** An enabled `[auth.hook.<hook>]` backed by a Postgres function. */
export interface PgFunctionHook {
  readonly hook: string;
  readonly uri: string;
  readonly schema: string;
  readonly name: string;
}

/** `pg-functions://postgres/<schema>/<function>` as schema and name. */
function parsePgFunctionUri(
  uri: string,
): { readonly schema: string; readonly name: string } | undefined {
  const match = /^pg-functions:\/\/[^/]+\/([^/]+)\/([^/?#]+)$/.exec(uri.trim());
  return match ? { schema: match[1]!, name: match[2]! } : undefined;
}

/** The enabled Auth hooks with a `pg-functions://` URI, by hook name. */
export function pgFunctionHooks(document: TomlTable): PgFunctionHook[] {
  const hooks = tomlGet(document, ["auth", "hook"]);
  if (typeof hooks !== "object" || Array.isArray(hooks)) return [];
  // SAFETY: the check above narrows hooks to a TOML table.
  return Object.entries(hooks as TomlTable).flatMap(([hook, table]) => {
    if (typeof table !== "object" || Array.isArray(table)) return [];
    // SAFETY: the check above narrows table to a TOML table.
    const { enabled, uri } = table as TomlTable;
    if ((enabled !== true && enabled !== "true") || typeof uri !== "string")
      return [];
    const target = parsePgFunctionUri(uri);
    return target ? [{ hook, uri, ...target }] : [];
  });
}

/** An enabled `[auth.hook.<hook>]` that Auth calls over HTTP. */
export interface HttpHook {
  readonly hook: string;
  readonly uri: URL;
  /** `secrets` as parsed: after `env()` interpolation when `@supabase/config` read the file. */
  readonly secrets: string | undefined;
}

/** The enabled Auth hooks with an `http://` or `https://` URI, by hook name. */
export function httpHooks(document: TomlTable): HttpHook[] {
  const hooks = tomlGet(document, ["auth", "hook"]);
  if (typeof hooks !== "object" || Array.isArray(hooks)) return [];
  // SAFETY: the check above narrows hooks to a TOML table.
  return Object.entries(hooks as TomlTable).flatMap(([hook, table]) => {
    if (typeof table !== "object" || Array.isArray(table)) return [];
    // SAFETY: the check above narrows table to a TOML table.
    const { enabled, uri, secrets } = table as TomlTable;
    if ((enabled !== true && enabled !== "true") || typeof uri !== "string")
      return [];
    if (!/^https?:\/\//i.test(uri.trim()) || !URL.canParse(uri.trim()))
      return [];
    return [
      {
        hook,
        uri: new URL(uri.trim()),
        secrets: typeof secrets === "string" ? secrets : undefined,
      },
    ];
  });
}

/** The Supabase CLI engine that turns `supabase/schemas` into migrations. */
export type DiffEngine = "pg-delta" | "migra";

/**
 * The engine the Supabase CLI runs: pg-delta when `[experimental.pgdelta]
 * enabled = true`, otherwise the legacy migra engine.
 */
export function diffEngine(toml?: SupabaseToml): DiffEngine {
  const enabled = tomlGet(toml?.document ?? {}, [
    "experimental",
    "pgdelta",
    "enabled",
  ]);
  return enabled === true || enabled === "true" ? "pg-delta" : "migra";
}

/** Whether `dir` (or a folder below it) holds a `.sql` file. */
function hasSqlFiles(dir: string): boolean {
  if (!existsSync(dir)) return false;
  try {
    return readdirSync(dir, { recursive: true }).some((name) =>
      String(name).endsWith(".sql"),
    );
  } catch {
    return false;
  }
}

/**
 * The workflow a project without `sql.workflow` follows: pg-delta when
 * `config.toml` enables it, migra when it turns pg-delta off (`enabled =
 * false`), lists `[db.migrations] schema_paths` or already keeps files in
 * `supabase/schemas` without pg-delta, and pg-delta otherwise. `schemaFiles`
 * says whether that folder holds SQL files when the caller already read it.
 */
export function detectWorkflow(
  root: string,
  toml?: SupabaseToml,
  schemaFiles?: boolean,
): Exclude<SqlWorkflow, "migrations"> {
  if (diffEngine(toml) === "pg-delta" || toml === undefined) return "pg-delta";
  if (
    tomlGet(toml.document, ["experimental", "pgdelta", "enabled"]) !== undefined
  )
    return "migra";
  const paths = tomlGet(toml.document, ["db", "migrations", "schema_paths"]);
  if (Array.isArray(paths) && paths.length > 0) return "migra";
  return (schemaFiles ?? hasSqlFiles(join(root, toml.dir, "schemas")))
    ? "migra"
    : "pg-delta";
}

/** `sql.workflow`, or the one `detectWorkflow` reads from `config.toml`. */
export function sqlWorkflow(
  config: {
    readonly root: string;
    readonly sql: { readonly workflow?: SqlWorkflow | undefined };
  },
  toml?: SupabaseToml,
): SqlWorkflow {
  return config.sql.workflow ?? detectWorkflow(config.root, toml);
}

/** The `config.toml` table that turns pg-delta on. */
export const PGDELTA_TABLE = "[experimental.pgdelta]\nenabled = true\n";

/**
 * The command that turns the files into a migration (named `name`, when
 * given). Under the migrations workflow the `sql` commands already wrote
 * it, so the command applies it.
 */
export function migrationCommand(workflow: SqlWorkflow, name?: string): string {
  switch (workflow) {
    case "pg-delta":
      return name === undefined
        ? "supabase db schema declarative sync"
        : `supabase db schema declarative sync -f ${name}`;
    case "migra":
      return name === undefined
        ? "supabase db diff"
        : `supabase db diff -f ${name}`;
    case "migrations":
      return "supabase migration up";
    default: {
      const unreachable: never = workflow;
      return unreachable;
    }
  }
}

/** The declarative schema files, in the order the diff engine reads them. */
export interface SchemaPaths {
  /** Relative to the project root. */
  readonly files: readonly string[];
  /** Files under `supabase/schemas` that no `schema_paths` entry matches, so the diff skips them. */
  readonly unlisted: readonly string[];
  /** Whether `[db.migrations] schema_paths` lists entries that the engine honors (migra only). */
  readonly configured: boolean;
}

/** `experimental.pgdelta.declarative_schema_path` (relative to `supabase/`), or `./schemas`. */
function pgDeltaSchemasDir(toml?: SupabaseToml): string {
  const dir = tomlGet(toml?.document ?? {}, [
    "experimental",
    "pgdelta",
    "declarative_schema_path",
  ]);
  const schemas =
    typeof dir === "string" && dir.trim() !== "" ? dir : "schemas";
  return posix.join(
    toml?.dir ?? "supabase",
    schemas.replace(/^\.\//, "").replace(/\/$/, ""),
  );
}

/**
 * The folder the diff engine loads declarative schema files from, relative
 * to the root: `declarative_schema_path` under pg-delta, `supabase/schemas`
 * otherwise. `workflow` defaults to what `config.toml` turns on.
 */
export function declarativeSchemasDir(
  toml?: SupabaseToml,
  workflow: SqlWorkflow = diffEngine(toml),
): string {
  return workflow === "pg-delta"
    ? pgDeltaSchemasDir(toml)
    : posix.join(toml?.dir ?? "supabase", "schemas");
}

async function expand(cwd: string, pattern: string): Promise<string[]> {
  const matched: string[] = [];
  for await (const path of glob(pattern.replace(/^\.\//, ""), { cwd }))
    if (path.endsWith(".sql")) matched.push(path.replaceAll("\\", "/"));
  return matched.sort();
}

/**
 * `[db.migrations] schema_paths` (relative to `supabase/`) with each glob
 * expanded in name order and the entries kept in their listed order, then
 * the `supabase/schemas` files no entry matches. Without `schema_paths`, the
 * `supabase/schemas` files in name order, as the Supabase CLI reads them.
 * pg-delta ignores `schema_paths` and orders by dependency, so under it every
 * file in its schema directory counts, in name order. The migrations
 * workflow has no declarative schemas. `workflow` defaults to
 * `detectWorkflow`.
 */
export async function schemaPaths(
  root: string,
  toml?: SupabaseToml,
  workflow: SqlWorkflow = detectWorkflow(root, toml),
): Promise<SchemaPaths> {
  if (workflow === "migrations")
    return { files: [], unlisted: [], configured: false };
  if (workflow === "pg-delta") {
    const dir = pgDeltaSchemasDir(toml);
    const files = existsSync(join(root, dir))
      ? await expand(root, `${dir}/**/*.sql`)
      : [];
    return { files, unlisted: [], configured: false };
  }
  const dir = toml?.dir ?? "supabase";
  const supabase = join(root, dir);
  const all = existsSync(join(supabase, "schemas"))
    ? (await expand(supabase, "schemas/**/*.sql")).map((path) =>
        posix.join(dir, path),
      )
    : [];
  const entries = tomlGet(toml?.document ?? {}, [
    "db",
    "migrations",
    "schema_paths",
  ]);
  const patterns = Array.isArray(entries)
    ? entries.filter((entry): entry is string => typeof entry === "string")
    : [];
  if (patterns.length === 0)
    return { files: all, unlisted: [], configured: false };
  const listed = new Set<string>();
  for (const pattern of patterns)
    for (const path of await expand(supabase, pattern))
      listed.add(posix.join(dir, path));
  const unlisted = all.filter((path) => !listed.has(path));
  return { files: [...listed, ...unlisted], unlisted, configured: true };
}
