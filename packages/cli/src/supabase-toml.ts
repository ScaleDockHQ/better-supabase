import { existsSync } from "node:fs";
import { glob, readFile } from "node:fs/promises";
import { join, posix } from "node:path";
import { parse } from "smol-toml";

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
  /** Relative to the project root. */
  readonly path: string;
  readonly text: string;
  /** The keys present in the file (snake_case, as written), after `env()` interpolation when parsed by `@supabase/config`. */
  readonly document: TomlTable;
  readonly parser: "@supabase/config" | "smol-toml";
}

const CONFIG_TOML = "supabase/config.toml";

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

/**
 * Reads `supabase/config.toml` with `@supabase/config` when it is installed,
 * otherwise with smol-toml.
 */
export async function readSupabaseToml(
  root: string,
): Promise<SupabaseToml | undefined> {
  const absolute = join(root, CONFIG_TOML);
  if (!existsSync(absolute)) return undefined;
  const text = await readFile(absolute, "utf8");
  const io = await loadSupabaseConfig();
  if (io) {
    try {
      const loaded = await io.loadCliConfig(root, {
        tomlOnly: true,
        search: false,
      });
      if (loaded?.document) {
        // SAFETY: @supabase/config parses config.toml into plain TOML values.
        return {
          path: CONFIG_TOML,
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
    path: CONFIG_TOML,
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

/** The declarative schema files, in the order `supabase db diff` applies them. */
export interface SchemaPaths {
  /** Relative to the project root. */
  readonly files: readonly string[];
  /** Files under `supabase/schemas` that no `schema_paths` entry matches, so the diff skips them. */
  readonly unlisted: readonly string[];
  /** Whether `[db.migrations] schema_paths` lists any entries. */
  readonly configured: boolean;
}

const SCHEMAS_DIR = "supabase/schemas";

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
 */
export async function schemaPaths(
  root: string,
  toml?: SupabaseToml,
): Promise<SchemaPaths> {
  const supabase = join(root, "supabase");
  const all = existsSync(join(root, SCHEMAS_DIR))
    ? (await expand(supabase, "schemas/**/*.sql")).map((path) =>
        posix.join("supabase", path),
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
      listed.add(posix.join("supabase", path));
  const unlisted = all.filter((path) => !listed.has(path));
  return { files: [...listed, ...unlisted], unlisted, configured: true };
}
