import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { CliEnv } from "../env.ts";
import type { IntrospectionSource } from "../introspect/source.ts";
import type { Snapshot } from "../introspect/types.ts";

import { resolveShares } from "../../config/shares.ts";
import { databaseUrl } from "../config.ts";
import { accessToken } from "../core/credentials.ts";
import { CliError, errorText } from "../core/errors.ts";
import { connect } from "../db.ts";
import { apiTypeSchemas } from "../gen/api-schemas.ts";
import { bootstrapFunctionNames } from "../gen/bootstrap-tables.ts";
import { cachedIntrospect } from "../introspect/cache.ts";
import { introspect } from "../introspect/index.ts";
import { liteDriverOf, liteSource } from "../introspect/lite.ts";
import { managementSource, pgSource } from "../introspect/source.ts";
import {
  TypegenMissingError,
  validateGeneratorMetadata,
} from "../introspect/typegen.ts";
import { pgFunctionHooks, readSupabaseConfig } from "../supabase-config.ts";

const SNAPSHOT_SCHEMA_URL =
  "https://unpkg.com/better-supabase/schemas/snapshot-v3.json";

/** Where `gen --save-snapshot` writes when `database.source.snapshot` is unset. */
export const DEFAULT_SNAPSHOT_PATH = "supabase/snapshot.json";

/** Schemas that are always read, for doctor checks on helper functions. */
const EXTRA_SCHEMAS = ["better_supabase"];

/**
 * Schemas of schema-qualified `authorization.tables` names. An unqualified name
 * uses `config.schemas`, so it adds nothing here.
 */
export function declaredTableSchemas(
  config: ResolvedConfig,
): readonly string[] {
  const schemas = new Set<string>();

  for (const name of Object.keys(resolveShares(config).tables)) {
    const dot = name.indexOf(".");

    if (dot > 0) {
      schemas.add(name.slice(0, dot));
    }
  }

  return [...schemas];
}

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
  /**
   * Schemas to read on top of the config. Doctor passes the schemas named by
   * `authorization.tables`, which may sit outside `schemas`.
   */
  readonly extraSchemas?: readonly string[];
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
  if (source.dbUrl) {
    return undefined;
  }

  const projectRef =
    source.projectRef ??
    (config.source.dbUrl ? undefined : config.source.projectRef);

  if (!projectRef) {
    return undefined;
  }

  const token = accessToken(config, env);

  if (!token) {
    throw new CliError(
      "auth_required",
      `Reading project ${projectRef} needs a Supabase access token. Set SUPABASE_ACCESS_TOKEN to a token scoped to this project (https://supabase.com/dashboard/account/tokens), or read the database with $DATABASE_URL, $SUPABASE_DB_URL or --db-url-stdin.`,
      { flag: "SUPABASE_ACCESS_TOKEN" },
    );
  }

  return {
    projectRef,
    accessToken: token.value,
    ...(env.SUPABASE_API_URL ? { apiUrl: env.SUPABASE_API_URL } : {}),
  };
}

/**
 * Where to read the schema from: `--db-url-stdin`, `--project-ref`, then the
 * config's `source.dbUrl` / `source.projectRef`, a Supabase Lite project's
 * `[db] driver`, `$DATABASE_URL`, `$SUPABASE_DB_URL`, and finally the local
 * stack.
 */
export async function openSource(
  config: ResolvedConfig,
  env: Env,
  source: SnapshotSource,
  open: typeof connect = connect,
): Promise<IntrospectionSource> {
  if (source.dbUrl) {
    return pgSource(source.dbUrl, open, source.signal);
  }

  const target = managementTarget(config, env, source);

  if (target) {
    return managementSource({
      ...target,
      ...(source.signal ? { signal: source.signal } : {}),
    });
  }

  if (!config.source.dbUrl && config.source.lite !== false) {
    const toml = await readSupabaseConfig(config.root);

    const driver =
      liteDriverOf(toml) ??
      (config.source.lite === true ? "sqlite-postgres" : undefined);

    if (driver) {
      return liteSource(config.root, toml, driver, open);
    }
  }

  return pgSource(await databaseUrl(config, env), open, source.signal);
}

/** Whether `getSnapshot` reads a saved file rather than a database. */
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
export async function getSnapshot(
  config: ResolvedConfig,
  env: Env,
  source: SnapshotSource,
  open: typeof connect = connect,
  shared?: () => Promise<IntrospectionSource>,
): Promise<Snapshot> {
  const path = snapshotFile(config, source);

  if (path) {
    return getSnapshotFile(resolve(config.root, path), path);
  }

  const [tomlRead, opened] = await Promise.allSettled([
    readSupabaseConfig(config.root),
    shared ? shared() : openSource(config, env, source, open),
  ]);

  if (tomlRead.status === "rejected") {
    if (opened.status === "fulfilled" && !shared) {
      await opened.value.close().catch(() => undefined);
    }

    throw tomlRead.reason;
  }

  if (opened.status === "rejected") {
    throw opened.reason;
  }

  const toml = tomlRead.value;
  const db = opened.value;
  const hooks = toml ? pgFunctionHooks(toml.document) : [];
  const functions = bootstrapFunctionNames(config);
  const shareable = config.authorization !== undefined;

  const schemas = [
    ...new Set([
      ...config.schemas,
      ...apiTypeSchemas(config),
      ...EXTRA_SCHEMAS,
      ...(source.extraSchemas ?? []),
    ]),
  ];

  try {
    const read = (): Promise<Snapshot> =>
      introspect(db.queryable, schemas, { hooks, functions, shareable });

    return await (source.cache
      ? cachedIntrospect(
          config.root,
          db,
          [schemas, hooks, functions, shareable],
          read,
        )
      : read());
  } finally {
    if (!shared) {
      await db.close();
    }
  }
}

async function getSnapshotFile(
  absolute: string,
  label: string = absolute,
): Promise<Snapshot> {
  if (!existsSync(absolute)) {
    throw new CliError("not_found", `Snapshot not found: ${label}`);
  }

  return parseSnapshot(JSON.parse(await readFile(absolute, "utf-8")), label);
}

/** Validates a parsed snapshot document. */
export async function parseSnapshot(
  data: unknown,
  label: string = "snapshot",
): Promise<Snapshot> {
  // The CLI's introspection cache stores `{ key, snapshot }`; read the snapshot.
  const unwrapped =
    typeof data === "object" &&
    data !== null &&
    !("version" in data) &&
    "key" in data &&
    "snapshot" in data
      ? data.snapshot
      : data;

  // SAFETY: every field is checked below before the document is returned as a Snapshot.
  const doc = unwrapped as Partial<Snapshot> | null;

  // The type says 3, but a saved file may say 2 and is upgraded below.
  const found: unknown = doc?.version;

  if (!doc || typeof doc !== "object" || (found !== 2 && found !== 3)) {
    throw new CliError(
      "invalid_input",
      `${label} is not a version 2 or 3 snapshot. Run \`better-supabase gen --save-snapshot\` to refresh it.`,
    );
  }

  if (
    !Array.isArray(doc.schemas) ||
    !doc.extras ||
    !Array.isArray(doc.extras.tables)
  ) {
    throw new CliError(
      "invalid_input",
      `${label} is missing "schemas" or "extras".`,
    );
  }

  let generator;

  try {
    generator = await validateGeneratorMetadata(doc.generator);
  } catch (cause) {
    if (cause instanceof TypegenMissingError) {
      throw cause;
    }

    throw new CliError(
      "invalid_input",
      `${label} has invalid "generator" metadata: ${errorText(cause)}`,
      { cause },
    );
  }

  // A version 2 snapshot upgrades as it is: every field version 3 adds is
  // optional, so it reads as a version 3 snapshot that has none of them.
  return {
    version: 3,
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
      ...(doc.extras.functionSources
        ? { functionSources: doc.extras.functionSources }
        : {}),
      ...(doc.extras.hooks ? { hooks: doc.extras.hooks } : {}),
      ...(doc.extras.functionComments
        ? { functionComments: doc.extras.functionComments }
        : {}),
      ...(doc.extras.functionInventory
        ? { functionInventory: doc.extras.functionInventory }
        : {}),
      ...(doc.extras.viewColumnComments
        ? { viewColumnComments: doc.extras.viewColumnComments }
        : {}),
      ...(doc.extras.domains ? { domains: doc.extras.domains } : {}),
    },
  };
}

export function serializeSnapshot(snapshot: Snapshot): string {
  const { $schema: _ignored, ...rest } = snapshot;

  return `${JSON.stringify({ $schema: SNAPSHOT_SCHEMA_URL, ...rest }, null, 2)}\n`;
}
