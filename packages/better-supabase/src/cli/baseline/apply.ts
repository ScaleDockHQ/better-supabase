import type { ExecResult } from "../exec.ts";
import type { FoundArtifact } from "./artifact.ts";
import type { BaselineVersions, HashedFile } from "./key.ts";
import type { UploadTarget } from "./seeds.ts";
import type { BaselineContext } from "./stack.ts";

import { CliError, errorText } from "../core/errors.ts";
import { connect } from "../db.ts";
import { migrationFiles } from "../in-stack-diff.ts";
import { readSupabaseConfig, supabaseDir } from "../supabase-config.ts";
import { VERSION } from "../version.ts";
import { baselineRoot, findArtifact } from "./artifact.ts";
import { serverVersion } from "./catalog.ts";
import { hashFiles, matchSeed } from "./key.ts";
import {
  runSeedFiles,
  seedSources,
  unpackBuckets,
  uploadBuckets,
} from "./seeds.ts";
import { cliVersion, loadSql, stepTimer } from "./stack.ts";

/** The database `apply` fills, and how to reach what runs on top of it. */
interface ApplyTarget {
  readonly dbUrl: string;
  /**
   * Storage API for the bucket objects; without it a baseline with objects
   * cannot restore them.
   */
  readonly storage?: UploadTarget | undefined;
  /** Runs the migrations the database lacks (`supabase migration up`). */
  readonly migrate: () => Promise<ExecResult>;
}

export interface ApplyOptions {
  readonly from?: string | undefined;
  readonly withSeed: boolean;
  readonly target: ApplyTarget;
}

type SeedMode = "snapshot" | "files" | "none";

export interface ApplyResult {
  readonly mode: "baseline" | "replay";
  /** Why the baseline was not used. */
  readonly reason?: string;
  readonly key?: string;
  /** Migrations run on top of the baseline, or all of them on a replay. */
  readonly pending: readonly string[];
  readonly seed: SeedMode;
  readonly timings: Readonly<Record<string, number>>;
}

async function migrationsApplied(
  url: string,
): Promise<{ readonly applied: number; readonly postgres: string }> {
  const { client, close } = await connect(url);

  try {
    const table = await client.query<{ found: string | null }>(
      "select to_regclass('supabase_migrations.schema_migrations')::text as found",
    );

    const count =
      table.rows[0]?.found === null || table.rows[0] === undefined
        ? 0
        : Number(
            (
              await client.query<{ n: string }>(
                "select count(*)::text as n from supabase_migrations.schema_migrations",
              )
            ).rows[0]?.n ?? 0,
          );

    return { applied: count, postgres: await serverVersion(client) };
  } finally {
    await close();
  }
}

async function migrate(target: ApplyTarget): Promise<void> {
  const result = await target.migrate();

  if (result.code !== 0) {
    throw new CliError(
      "supabase_cli_failed",
      `supabase migration up failed: ${(result.stderr || result.stdout).trim()}`,
    );
  }
}

function storageTarget(target: ApplyTarget): UploadTarget {
  if (target.storage === undefined) {
    throw new CliError(
      "failed",
      "The seed has storage objects and the stack reports no Storage API URL or service key to upload them to.",
    );
  }

  return target.storage;
}

/**
 * Fills an empty local database from the newest baseline that fits, then runs
 * only the migrations newer than it. When nothing fits, or loading fails (a
 * single transaction, so the database stays empty), it runs every migration the
 * usual way and says why.
 */
export async function applyBaseline(
  ctx: BaselineContext,
  options: ApplyOptions,
): Promise<ApplyResult> {
  const { root } = ctx;
  const timer = stepTimer();
  const { dbUrl } = options.target;
  const state = await timer.step("inspect", () => migrationsApplied(dbUrl));
  const toml = await readSupabaseConfig(root);
  const dir = supabaseDir(root);
  const sources = await seedSources(root, toml);
  const current = await hashFiles(root, await migrationFiles(root, dir));
  const seeds: readonly HashedFile[] = await hashFiles(root, sources.files);

  const versions: BaselineVersions = {
    bsb: VERSION,
    supabaseCli: await cliVersion(ctx),
    postgres: state.postgres,
    engine: "",
  };

  let reason: string | undefined;
  let found: FoundArtifact | undefined;

  if (state.applied > 0) {
    reason = `the database already has ${String(state.applied)} applied migrations`;
  } else {
    const search = await findArtifact(
      baselineRoot(root, options.from),
      current,
      versions,
    );

    found = search.found;
    reason = found === undefined ? search.reason : undefined;
  }

  let used = false;
  let pending: readonly string[] = current.map((file) => file.file);

  if (found !== undefined) {
    try {
      await timer.step("load baseline", () =>
        loadSql(ctx, dbUrl, [found.files.schema, found.files.data]),
      );

      used = true;
      pending = found.match.pending;
    } catch (error) {
      reason = `loading the baseline failed (${errorText(error)})`;
    }
  }

  if (reason !== undefined) {
    ctx.log(`Not using a baseline: ${reason}`);
  }

  if (!used || pending.length > 0) {
    await timer.step("migrations", () => migrate(options.target));
  }

  let seed: SeedMode = "none";

  if (options.withSeed) {
    const skipReason =
      used && found !== undefined
        ? matchSeed(found.manifest, seeds, { ok: true, pending })
        : "no baseline was loaded";

    if (found !== undefined && skipReason === undefined) {
      await timer.step("seed data", () =>
        loadSql(ctx, dbUrl, [found.files.seedSchema, found.files.seedData]),
      );

      if (
        found.manifest.seed !== undefined &&
        found.manifest.seed.objects > 0
      ) {
        const unpacked = await unpackBuckets(ctx, found.files.seedStorage);

        try {
          await timer.step("storage", () =>
            uploadBuckets(unpacked.buckets, storageTarget(options.target)),
          );
        } finally {
          await unpacked.cleanup();
        }
      }

      seed = "snapshot";
    } else {
      ctx.log(`Running the seed files: ${skipReason ?? "no snapshot"}`);
      await timer.step("seed data", () => runSeedFiles(ctx, dbUrl, sources));

      if (sources.buckets.length > 0) {
        await timer.step("storage", () =>
          uploadBuckets(sources.buckets, storageTarget(options.target)),
        );
      }

      seed = "files";
    }
  }

  return {
    mode: used ? "baseline" : "replay",
    ...(reason === undefined ? {} : { reason }),
    ...(found === undefined ? {} : { key: found.manifest.key }),
    pending,
    seed,
    timings: timer.timings,
  };
}
