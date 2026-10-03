import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { CliEnv } from "../env.ts";
import type { Snapshot } from "../introspect/types.ts";

import { databaseUrl } from "../config.ts";
import { connect } from "../db.ts";
import { CliError } from "../errors.ts";
import { cachedIntrospect } from "../introspect/cache.ts";
import { introspect } from "../introspect/index.ts";
import {
  type IntrospectionSource,
  managementSource,
  pgSource,
} from "../introspect/source.ts";
import { validateGeneratorMetadata } from "../introspect/typegen.ts";
import { pgFunctionHooks, readSupabaseToml } from "../supabase-toml.ts";

const SNAPSHOT_SCHEMA_URL =
  "https://unpkg.com/better-supabase/schemas/snapshot-v2.json";

/** Schemas that are always read, for doctor checks on helper functions. */
const EXTRA_SCHEMAS = ["better_supabase"];

export interface SnapshotSource {
  readonly snapshotPath?: string;
  readonly dbUrl?: string;
  readonly projectRef?: string;
  /** Ignore `source.snapshot` and read the database. */
  readonly live?: boolean;
  /** Ends the database connection or Management API request (Ctrl-C). */
  readonly signal?: AbortSignal;
  /** Reuses the snapshot cached for an unchanged catalog fingerprint. */
  readonly cache?: boolean;
}

type Env = CliEnv;

export interface ManagementTarget {
  readonly projectRef: string;
  readonly accessToken: string;
  readonly apiUrl?: string;
}

/** The hosted project to read through the Management API, if any. */
export function managementTarget(
  config: ResolvedConfig,
  env: Env,
  source: SnapshotSource,
): ManagementTarget | undefined {
  if (source.dbUrl) return undefined;
  const projectRef =
    source.projectRef ??
    (config.source.dbUrl ? undefined : config.source.projectRef);
  if (!projectRef) return undefined;
  const accessToken = config.source.accessToken ?? env.SUPABASE_ACCESS_TOKEN;
  if (!accessToken) {
    throw new CliError(
      "missing_value",
      `Reading project ${projectRef} needs a Supabase access token. Set SUPABASE_ACCESS_TOKEN to a token scoped to this project (https://supabase.com/dashboard/account/tokens), or read the database with $DATABASE_URL or --db-url-stdin.`,
      { flag: "SUPABASE_ACCESS_TOKEN" },
    );
  }
  return {
    projectRef,
    accessToken,
    ...(env.SUPABASE_API_URL ? { apiUrl: env.SUPABASE_API_URL } : {}),
  };
}

/**
 * Where to read the schema from: `--db-url-stdin`, `--project-ref`, then the
 * config's `source.dbUrl` / `source.projectRef`, `$DATABASE_URL`, and finally
 * the local stack.
 */
export async function openSource(
  config: ResolvedConfig,
  env: Env,
  source: SnapshotSource,
  open: typeof connect = connect,
): Promise<IntrospectionSource> {
  if (source.dbUrl) return pgSource(source.dbUrl, open, source.signal);
  const target = managementTarget(config, env, source);
  if (target)
    return managementSource({
      ...target,
      ...(source.signal ? { signal: source.signal } : {}),
    });
  return pgSource(await databaseUrl(config, env), open, source.signal);
}

/** Whether `loadSnapshot` reads a saved file rather than a database. */
export function snapshotFile(
  config: ResolvedConfig,
  source: SnapshotSource,
): string | undefined {
  return (
    source.snapshotPath ??
    (source.live || source.dbUrl || source.projectRef
      ? undefined
      : config.source.snapshot)
  );
}

/**
 * Loads a saved snapshot or introspects the database. With `shared`, it
 * introspects over that source and leaves closing it to the caller, so later
 * queries reuse the connection.
 */
export async function loadSnapshot(
  config: ResolvedConfig,
  env: Env,
  source: SnapshotSource,
  open: typeof connect = connect,
  shared?: () => Promise<IntrospectionSource>,
): Promise<Snapshot> {
  const path = snapshotFile(config, source);
  if (path) return readSnapshotFile(resolve(config.root, path), path);
  const [toml, db] = await Promise.all([
    readSupabaseToml(config.root),
    shared ? shared() : openSource(config, env, source, open),
  ]);
  const hooks = toml ? pgFunctionHooks(toml.document) : [];
  const schemas = [...config.schemas, ...EXTRA_SCHEMAS];
  try {
    const read = (): Promise<Snapshot> =>
      introspect(db.queryable, schemas, { hooks });
    return await (source.cache
      ? cachedIntrospect(config.root, db, [schemas, hooks], read)
      : read());
  } finally {
    if (!shared) await db.close();
  }
}

async function readSnapshotFile(
  absolute: string,
  label: string = absolute,
): Promise<Snapshot> {
  if (!existsSync(absolute)) throw new Error(`Snapshot not found: ${label}`);
  return parseSnapshot(JSON.parse(await readFile(absolute, "utf8")), label);
}

/** Validates a parsed snapshot document. */
export async function parseSnapshot(
  data: unknown,
  label: string = "snapshot",
): Promise<Snapshot> {
  // SAFETY: every field is checked below before the document is returned as a Snapshot.
  const doc = data as Partial<Snapshot> | null;
  if (!doc || typeof doc !== "object" || doc.version !== 2) {
    throw new Error(
      `${label} is not a version 2 snapshot. Run \`better-supabase introspect\` to refresh it.`,
    );
  }
  if (
    !Array.isArray(doc.schemas) ||
    !doc.extras ||
    !Array.isArray(doc.extras.tables)
  ) {
    throw new Error(`${label} is missing "schemas" or "extras".`);
  }
  let generator;
  try {
    generator = await validateGeneratorMetadata(doc.generator);
  } catch (cause) {
    throw new Error(
      `${label} has invalid "generator" metadata: ${cause instanceof Error ? cause.message : String(cause)}`,
      { cause },
    );
  }
  return {
    version: 2,
    schemas: doc.schemas,
    generator,
    extras: {
      tables: doc.extras.tables,
      // oxlint-disable-next-line typescript/no-unnecessary-condition -- snapshots from older releases have no buckets.
      buckets: doc.extras.buckets ?? [],
      // oxlint-disable-next-line typescript/no-unnecessary-condition -- snapshots from older releases have no realtime.
      realtime: doc.extras.realtime ?? [],
      ...(doc.extras.roleSettings
        ? { roleSettings: doc.extras.roleSettings }
        : {}),
      ...(doc.extras.functions ? { functions: doc.extras.functions } : {}),
      ...(doc.extras.hooks ? { hooks: doc.extras.hooks } : {}),
    },
  };
}

export function serializeSnapshot(snapshot: Snapshot): string {
  const { $schema: _ignored, ...rest } = snapshot;
  return `${JSON.stringify({ $schema: SNAPSHOT_SCHEMA_URL, ...rest }, null, 2)}\n`;
}
