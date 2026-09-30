import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { Snapshot } from "../introspect/types.ts";

import { databaseUrl } from "../config.ts";
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
}

type Env = Readonly<Record<string, string | undefined>>;

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
  const accessToken =
    config.source.accessToken ?? env["SUPABASE_ACCESS_TOKEN"] ?? undefined;
  if (!accessToken) {
    throw new Error(
      `Reading project ${projectRef} needs a Supabase access token. Set SUPABASE_ACCESS_TOKEN (https://supabase.com/dashboard/account/tokens) or pass --db-url.`,
    );
  }
  return {
    projectRef,
    accessToken,
    ...(env["SUPABASE_API_URL"] ? { apiUrl: env["SUPABASE_API_URL"] } : {}),
  };
}

/**
 * Where to read the schema from: `--db-url`, `--project-ref`, then the
 * config's `source.dbUrl` / `source.projectRef`, `$DATABASE_URL`, and finally
 * the local stack.
 */
export async function openSource(
  config: ResolvedConfig,
  env: Env,
  source: SnapshotSource,
): Promise<IntrospectionSource> {
  if (source.dbUrl) return pgSource(source.dbUrl);
  const target = managementTarget(config, env, source);
  if (target) return managementSource(target);
  return pgSource(await databaseUrl(config, env));
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

/** Loads a saved snapshot or introspects the database. */
export async function loadSnapshot(
  config: ResolvedConfig,
  env: Env,
  source: SnapshotSource,
): Promise<Snapshot> {
  const path = snapshotFile(config, source);
  if (path) return readSnapshotFile(resolve(config.root, path), path);
  const toml = await readSupabaseToml(config.root);
  const hooks = toml ? pgFunctionHooks(toml.document) : [];
  const db = await openSource(config, env, source);
  try {
    return await introspect(
      db.queryable,
      [...config.schemas, ...EXTRA_SCHEMAS],
      { hooks },
    );
  } finally {
    await db.close();
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
export function parseSnapshot(
  data: unknown,
  label: string = "snapshot",
): Snapshot {
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
    generator = validateGeneratorMetadata(doc.generator);
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
