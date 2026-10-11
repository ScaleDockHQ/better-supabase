import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { connect } from "../db.ts";
import type { LiveDatabase } from "../doctor/live.ts";
import type { CliEnv } from "../env.ts";
import type { IntrospectionSource } from "../introspect/source.ts";

import {
  managementTarget,
  openSource,
  type SnapshotSource,
  snapshotFile,
} from "../commands/snapshot.ts";
import {
  type AdvisorSource,
  apiSchemas,
  managementAdvisors,
  splinterAdvisors,
} from "../doctor/advisors.ts";
import { type DoctorContext } from "../doctor/rules.ts";
import { CACHE_DIR } from "../introspect/cache.ts";
import { readSupabaseToml } from "../supabase-toml.ts";

/** Checks that read the database itself rather than the snapshot. */
export const LIVE_CODES: ReadonlySet<string> = new Set([
  "BS100",
  "BS200",
  "BS208",
  "BS209",
  "BS212",
]);

type Env = CliEnv;

export interface OpenLive {
  readonly advisors: DoctorContext["advisors"];
  readonly database: DoctorContext["database"];
  /** The connection the live checks use, opened on first use; introspection shares it. */
  readonly open?: () => Promise<IntrospectionSource>;
  close(): Promise<void>;
}

/**
 * The database doctor reads, for advisors and live checks: the Management
 * API for hosted projects, one lazily opened connection otherwise (splinter
 * runs over it). Saved snapshots skip both.
 */
export function openLive(
  config: ResolvedConfig,
  env: Env,
  source: SnapshotSource,
  pg: typeof connect,
): OpenLive {
  const none = { close: () => Promise.resolve() };
  const file = snapshotFile(config, source);
  if (file) {
    const skipped = `reading the saved snapshot ${file}; set $DATABASE_URL or $SUPABASE_DB_URL, or pass --db-url-stdin or --project-ref, to check a database.`;
    return { ...none, advisors: { skipped }, database: { skipped } };
  }
  let opened: Promise<IntrospectionSource> | undefined;
  const open = (): Promise<IntrospectionSource> =>
    (opened ??= openSource(config, env, source, pg));
  const target = managementTarget(config, env, source);
  const database: LiveDatabase = {
    describe: target
      ? `project ${target.projectRef} (Management API)`
      : "database",
    session: !target,
    async query<R>(sql: string) {
      const result = await (await open()).queryable.query(sql);
      // SAFETY: R is the row type the caller declares for its query.
      return result.rows as R[];
    },
  };
  const close = async (): Promise<void> => {
    if (opened) await (await opened).close();
  };
  if (target)
    return { advisors: managementAdvisors(target), database, open, close };
  let splinter: Promise<AdvisorSource> | undefined;
  const cacheDir = resolve(config.root, CACHE_DIR);
  const advisors: AdvisorSource = {
    describe: "database (splinter)",
    async lints(category) {
      splinter ??= Promise.all([
        open(),
        readSupabaseToml(config.root).catch(() => undefined),
      ]).then(([db, toml]) =>
        splinterAdvisors(db.queryable, db.describe, {
          cacheDir,
          schemas: apiSchemas(toml?.document),
        }),
      );
      return (await splinter).lints(category);
    },
  };
  return { advisors, database, open, close };
}
