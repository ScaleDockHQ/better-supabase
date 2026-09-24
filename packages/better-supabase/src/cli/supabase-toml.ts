import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

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
  readonly parser: '@supabase/config' | 'builtin';
}

export const CONFIG_TOML = 'supabase/config.toml';

interface SupabaseConfigIo {
  loadCliConfig(
    cwd: string,
    options: { readonly tomlOnly: boolean; readonly search: boolean },
  ): Promise<{ readonly document?: Record<string, unknown> } | null>;
}

/**
 * `@supabase/config` is an optional peer (it needs `effect` and
 * `@effect/platform-node`), so it is imported lazily through a variable:
 * projects without it get the built-in parser instead of a load error.
 */
async function loadSupabaseConfig(): Promise<SupabaseConfigIo | undefined> {
  const specifier = '@supabase/config/io';
  try {
    return (await import(specifier)) as SupabaseConfigIo;
  } catch {
    return undefined;
  }
}

function parseScalar(raw: string): TomlValue {
  const value = raw.trim();
  if (value.startsWith('"') || value.startsWith("'")) {
    const quote = value[0]!;
    const end = value.indexOf(quote, 1);
    return value.slice(1, end === -1 ? undefined : end);
  }
  if (value.startsWith('[')) {
    const inner = value.slice(1, value.lastIndexOf(']'));
    return inner
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean)
      .map(parseScalar);
  }
  const bare = value.replace(/\s+#.*$/, '');
  if (bare === 'true') return true;
  if (bare === 'false') return false;
  const number = Number(bare.replaceAll('_', ''));
  return bare !== '' && Number.isFinite(number) ? number : bare;
}

/**
 * Tables, `key = value` pairs, strings, numbers, booleans and one-line arrays:
 * the subset `supabase init` writes. Multi-line values are skipped.
 */
export function parseTomlSubset(text: string): TomlTable {
  const root: Record<string, TomlValue> = {};
  let table = root;
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (line === '' || line.startsWith('#')) continue;
    const header = /^\[([^[\]]+)\]$/.exec(line);
    if (header) {
      table = root;
      for (const part of header[1]!
        .split('.')
        .map((p) => p.trim().replace(/^"(.*)"$/, '$1'))) {
        const next = table[part];
        if (typeof next !== 'object' || next === null || Array.isArray(next)) {
          table[part] = {};
        }
        table = table[part] as Record<string, TomlValue>;
      }
      continue;
    }
    const pair = /^([A-Za-z0-9_-]+)\s*=\s*(.+)$/.exec(line);
    if (pair) table[pair[1]!] = parseScalar(pair[2]!);
  }
  return root;
}

/**
 * Reads `supabase/config.toml` with `@supabase/config` when it is installed,
 * otherwise with the built-in subset parser.
 */
export async function readSupabaseToml(
  root: string,
): Promise<SupabaseToml | undefined> {
  const absolute = join(root, CONFIG_TOML);
  if (!existsSync(absolute)) return undefined;
  const text = await readFile(absolute, 'utf8');
  const io = await loadSupabaseConfig();
  if (io) {
    try {
      const loaded = await io.loadCliConfig(root, {
        tomlOnly: true,
        search: false,
      });
      if (loaded?.document) {
        return {
          path: CONFIG_TOML,
          text,
          document: loaded.document as TomlTable,
          parser: '@supabase/config',
        };
      }
    } catch {
      // An invalid file for @supabase/config's schema still has readable keys.
    }
  }
  return {
    path: CONFIG_TOML,
    text,
    document: parseTomlSubset(text),
    parser: 'builtin',
  };
}

/** The value at `path` (`['auth', 'jwt_expiry']`), if present. */
export function tomlGet(
  document: TomlTable,
  path: readonly string[],
): TomlValue | undefined {
  let value: TomlValue | undefined = document;
  for (const key of path) {
    if (typeof value !== 'object' || value === null || Array.isArray(value))
      return undefined;
    value = (value as TomlTable)[key];
  }
  return value;
}

export function tomlNumber(
  document: TomlTable,
  path: readonly string[],
): number | undefined {
  const value = tomlGet(document, path);
  if (typeof value === 'number') return value;
  if (
    typeof value === 'string' &&
    value.trim() !== '' &&
    Number.isFinite(Number(value))
  )
    return Number(value);
  return undefined;
}
