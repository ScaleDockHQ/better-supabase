import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

import {
  type BetterSupabaseConfig,
  type ResolvedConfig,
  resolveConfig,
} from '../config/index.ts';
import { readSupabaseToml, tomlNumber } from './supabase-toml.ts';

export const CONFIG_FILES = [
  'better-supabase.config.ts',
  'better-supabase.config.mts',
  'better-supabase.config.js',
  'better-supabase.config.mjs',
  'better-supabase.config.json',
] as const;

export function findConfig(cwd: string, explicit?: string): string | undefined {
  if (explicit) return resolve(cwd, explicit);
  for (const name of CONFIG_FILES) {
    const path = join(cwd, name);
    if (existsSync(path)) return path;
  }
  return undefined;
}

/** Imports a project module fresh, so watch loops and tests see edits. */
export async function importModule(
  path: string,
): Promise<Record<string, unknown>> {
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
  return loaded[name] ?? loaded['default'];
}

async function importConfig(path: string): Promise<unknown> {
  const loaded = await importModule(path);
  return loaded['default'] ?? loaded;
}

/**
 * Loads the config with a native `import()`. Node 24 strips types from
 * `.ts` files, so no loader is needed.
 */
export async function loadConfig(
  cwd: string,
  explicit?: string,
): Promise<ResolvedConfig> {
  const path = findConfig(cwd, explicit);
  if (!path) return resolveConfig({}, cwd);
  if (!existsSync(path)) throw new Error(`Config file not found: ${path}`);
  const config = path.endsWith('.json')
    ? (JSON.parse(await readFile(path, 'utf8')) as unknown)
    : await importConfig(path);
  if (typeof config !== 'object' || config === null) {
    throw new Error(
      `${path} must export a config object (export default defineConfig({...}))`,
    );
  }
  return resolveConfig(config as BetterSupabaseConfig, cwd);
}

/** `[db] port` or `[api] port` from `supabase/config.toml`. */
export async function readSupabasePort(
  root: string,
  section: 'db' | 'api',
): Promise<number | undefined> {
  const toml = await readSupabaseToml(root);
  return toml ? tomlNumber(toml.document, [section, 'port']) : undefined;
}

/** Connection string: flag, config, `$DATABASE_URL`, then the local stack. */
export async function databaseUrl(
  config: ResolvedConfig,
  env: Readonly<Record<string, string | undefined>>,
  flag?: string,
): Promise<string> {
  if (flag) return flag;
  if (config.source.dbUrl) return config.source.dbUrl;
  if (env.DATABASE_URL) return env.DATABASE_URL;
  const port = (await readSupabasePort(config.root, 'db')) ?? 54322;
  return `postgresql://postgres:postgres@127.0.0.1:${port}/postgres`;
}
