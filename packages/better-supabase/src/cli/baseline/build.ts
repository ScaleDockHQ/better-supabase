import type { Pool } from "pg";

import {
  mkdir,
  readdir,
  readFile,
  rename,
  rm,
  writeFile,
} from "node:fs/promises";
import { dirname, join } from "node:path";

import type { PgQueryable } from "../db.ts";
import type { TableRef } from "./catalog.ts";
import type { BaselineManifest, BaselineVersions, HashedFile } from "./key.ts";
import type { BaselineContext, ScratchStack } from "./stack.ts";

import { connect } from "../db.ts";
import { loadPgDelta, migrationFiles, openPgPool } from "../in-stack-diff.ts";
import { readSupabaseConfig, supabaseDir } from "../supabase-config.ts";
import { VERSION } from "../version.ts";
import { artifactFiles, baselineRoot, readManifest } from "./artifact.ts";
import {
  catalogFingerprint,
  changedTables,
  extensionTables,
  extractCatalog,
  pgmqQueues,
  planSql,
  queueSql,
  queueTriggers,
  quoted,
  rowCounts,
  sequenceSql,
  serverVersion,
  isQueueTable,
  leaveAlone,
  tableKey,
  tableSignatures,
  tablesToClear,
  xidSql,
} from "./catalog.ts";
import {
  BASELINE_FORMAT,
  hashFiles,
  matchBaseline,
  schemaKey,
  seedKey,
} from "./key.ts";
import { packBuckets, runSeedFiles, seedSources } from "./seeds.ts";
import {
  EMPTY_START_ENV,
  MIGRATIONS_ONLY_ENV,
  cliVersion,
  runPg,
  startScratch,
  stepTimer,
} from "./stack.ts";
import { verifyBaseline } from "./verify.ts";

export interface BuildOptions {
  readonly withSeed: boolean;
  /**
   * The folder that holds one folder per key; defaults to the cache under
   * node_modules.
   */
  readonly out?: string | undefined;
  readonly force: boolean;
  /** Restore the new artifact into a fresh stack and compare it with the build. */
  readonly verify: boolean;
}

export interface BuildResult {
  readonly key: string;
  readonly dir: string;
  readonly cached: boolean;
  readonly withSeed: boolean;
  /** Milliseconds per step. */
  readonly timings: Readonly<Record<string, number>>;
  readonly tables: number;
  readonly seedTables: number;
  readonly objects: number;
  readonly verified: boolean;
}

const EMPTY_STACK = "bsb-baseline-empty";
const BUILD_STACK = "bsb-baseline-build";

/**
 * Writes `schema.sql`'s companion: the rows of the changed tables, after a
 * `delete` for each table that already held rows, then the transaction ids
 * moved back (`xidSql`) and the sequence values. `session_replication_role =
 * replica` keeps triggers and foreign keys out of the restore, as `supabase db
 * dump` does.
 */
async function writeData(
  ctx: BaselineContext,
  url: string,
  file: string,
  changed: readonly TableRef[],
  clear: readonly TableRef[],
  sequences: string,
): Promise<void> {
  // pg_dump leaves out the rows of tables an extension owns, such as pgmq queues; COPY reads them.
  const copied = changed.filter((table) => isQueueTable(tableKey(table)));
  const dumped = changed.filter((table) => !isQueueTable(tableKey(table)));

  const parts = [
    // The restore connects as the stack's superuser; the schema file switches to postgres, as the migrations ran.
    "reset role;\nset session_replication_role = replica;\n",
    ...clear.map((table) => `delete from ${quoted(table)};\n`),
  ];

  if (dumped.length > 0) {
    const raw = `${file}.dump`;

    await runPg(ctx, "pg_dump", [
      "--data-only",
      "--no-owner",
      "--no-privileges",
      ...dumped.flatMap((table) => ["-t", quoted(table)]),
      "-f",
      raw,
      url,
    ]);

    parts.push(await readFile(raw, "utf-8"));
    await rm(raw, { force: true });
  }

  for (const table of copied) {
    const rows = await runPg(ctx, "psql", [
      "--no-psqlrc",
      "--quiet",
      "-c",
      `copy ${quoted(table)} to stdout`,
      url,
    ]);

    parts.push(`copy ${quoted(table)} from stdin;\n${rows}\\.\n`);
  }

  parts.push(`\n${xidSql(changed)}\n${sequences}\n`);
  await writeFile(file, parts.join(""));
}

async function withClient<T>(
  url: string,
  run: (client: PgQueryable) => Promise<T>,
): Promise<T> {
  const { client, close } = await connect(url);

  try {
    return await run(client);
  } finally {
    await close();
  }
}

async function withPool<T>(
  url: string,
  run: (pool: Pool) => Promise<T>,
): Promise<T> {
  const pool = await openPgPool(url);

  try {
    return await run(pool);
  } finally {
    await pool.end();
  }
}

async function cachedArtifact(
  base: string,
  migrations: readonly HashedFile[],
  versions: Omit<BaselineVersions, "postgres" | "engine">,
  wantsSeed: (manifest: BaselineManifest) => boolean,
): Promise<{ key: string; manifest: BaselineManifest } | undefined> {
  for (const key of await readdir(base).catch(() => [])) {
    const manifest = await readManifest(artifactFiles(base, key).manifest);

    if (manifest === undefined) {
      continue;
    }

    const match = matchBaseline(manifest, migrations, {
      ...versions,
      postgres: manifest.versions.postgres,
      engine: manifest.versions.engine,
    });

    if (match.ok && match.pending.length === 0 && wantsSeed(manifest)) {
      return { key, manifest };
    }
  }

  return undefined;
}

/**
 * Replays every migration once on a scratch stack and writes what a fresh stack
 * needs to skip the replay: the pg-delta plan from the empty catalog to the
 * migrated one, the rows the migrations inserted, and with `withSeed` the
 * seeded rows and a tarball of the storage objects.
 */
export async function buildBaseline(
  ctx: BaselineContext,
  options: BuildOptions,
): Promise<BuildResult> {
  const { root } = ctx;
  const timer = stepTimer();
  const toml = await readSupabaseConfig(root);
  const dir = supabaseDir(root);
  const base = baselineRoot(root, options.out);
  const migrations = await hashFiles(root, await migrationFiles(root, dir));
  const sources = await seedSources(root, toml);
  const seeds = await hashFiles(root, sources.files);
  const supabaseCli = await cliVersion(ctx);

  const done = (
    key: string,
    manifest: BaselineManifest,
    cached: boolean,
    verified: boolean,
  ): BuildResult => ({
    key,
    dir: artifactFiles(base, key).dir,
    cached,
    withSeed: manifest.seed !== undefined,
    timings: timer.timings,
    tables: Object.keys(manifest.counts).length,
    seedTables: Object.keys(manifest.seed?.counts ?? {}).length,
    objects: manifest.seed?.objects ?? 0,
    verified,
  });

  if (!options.force) {
    const hit = await cachedArtifact(
      base,
      migrations,
      { bsb: VERSION, supabaseCli },
      (manifest) =>
        !options.withSeed ||
        manifest.seed?.key === seedKey(manifest.key, seeds),
    );

    if (hit !== undefined) {
      ctx.log(`Baseline ${hit.key.slice(0, 12)} is already built`);

      return done(hit.key, hit.manifest, true, false);
    }
  }

  const delta = await loadPgDelta();

  // The empty catalog: a stack that skipped migrations and seeds.
  ctx.log("Reading the empty stack");

  const empty = await timer.step("empty stack", () =>
    startScratch(ctx, EMPTY_STACK, EMPTY_START_ENV),
  );

  let before;
  let postgres: string;

  try {
    ({ before, postgres } = await timer.step("empty catalog", async () => {
      const read = await withClient(empty.dbUrl, async (client) => ({
        signatures: await tableSignatures(client),
        postgres: await serverVersion(client),
        extensionOwned: await extensionTables(client),
        queues: await pgmqQueues(client),
      }));

      const catalog = await withPool(empty.dbUrl, (pool) =>
        extractCatalog(delta, pool),
      );

      return { before: { ...read, ...catalog }, postgres: read.postgres };
    }));
  } finally {
    await empty.destroy();
  }

  const versions: BaselineVersions = {
    bsb: VERSION,
    supabaseCli,
    postgres,
    engine: delta.ENGINE_VERSION,
  };

  const key = schemaKey(migrations, versions);
  const files = artifactFiles(base, key);
  const staging = artifactFiles(base, `.${key}.tmp`);
  await rm(staging.dir, { recursive: true, force: true });
  await mkdir(join(staging.dir, "seed"), { recursive: true });

  ctx.log(`Replaying ${String(migrations.length)} migrations`);
  let built: ScratchStack | undefined;

  try {
    built = await timer.step("replay", () =>
      startScratch(ctx, BUILD_STACK, MIGRATIONS_ONLY_ENV),
    );

    const url = built.dbUrl;

    const migrated = await timer.step("migrated catalog", async () => {
      const read = await withClient(url, async (client) => ({
        signatures: await tableSignatures(client),
        sequences: await sequenceSql(client),
        members: await extensionTables(client),
        queues: await pgmqQueues(client),
        queueTriggers: await queueTriggers(client),
        fingerprint: await catalogFingerprint(client),
      }));

      const catalog = await withPool(url, (pool) =>
        extractCatalog(delta, pool),
      );

      return { ...read, ...catalog };
    });

    const schema = planSql(
      delta,
      before.extracted,
      migrated.extracted,
      migrated.planOptions,
    );

    // The restore runs as supabase_admin, and the schema part as postgres like the migrations did.
    // Plan order puts a function after the objects it uses, but not after every function its body calls.
    await writeFile(
      staging.schema,
      `set check_function_bodies = off;\nset local role postgres;\n\n${schema.sql}\n\n${queueSql(before.queues, migrated.queues, migrated.queueTriggers)}\n`,
    );

    await writeFile(
      staging.snapshot,
      delta.serializeSnapshot(migrated.extracted.facts, {
        pgVersion: migrated.extracted.pgVersion,
      }),
    );

    const changed = changedTables(
      before.signatures,
      migrated.signatures,
      leaveAlone(before.extensionOwned, migrated.members),
    );

    await timer.step("dump data", () =>
      writeData(
        ctx,
        url,
        staging.data,
        changed,
        tablesToClear(before.signatures, changed),
        migrated.sequences,
      ),
    );

    let seed: BaselineManifest["seed"];

    if (options.withSeed) {
      await timer.step("seeds", () => runSeedFiles(ctx, url, sources));

      const seeded = await withClient(url, async (client) => ({
        signatures: await tableSignatures(client),
        sequences: await sequenceSql(client),
        members: await extensionTables(client),
        queues: await pgmqQueues(client),
        queueTriggers: await queueTriggers(client),
        fingerprint: await catalogFingerprint(client),
      }));

      const seededCatalog = await withPool(url, (pool) =>
        extractCatalog(delta, pool),
      );

      const seedSchema = planSql(
        delta,
        migrated.extracted,
        seededCatalog.extracted,
        seededCatalog.planOptions,
      );

      await writeFile(
        staging.seedSchema,
        `set check_function_bodies = off;\nset local role postgres;\n\n${seedSchema.sql}\n\n${queueSql(
          migrated.queues,
          seeded.queues,
          seeded.queueTriggers.filter(
            (trigger) => !migrated.queueTriggers.includes(trigger),
          ),
        )}\n`,
      );

      await writeFile(
        staging.seedSnapshot,
        delta.serializeSnapshot(seededCatalog.extracted.facts, {
          pgVersion: seededCatalog.extracted.pgVersion,
        }),
      );

      const seedChanged = changedTables(
        migrated.signatures,
        seeded.signatures,
        leaveAlone(before.extensionOwned, migrated.members, seeded.members),
      );

      await timer.step("dump seed data", () =>
        writeData(
          ctx,
          url,
          staging.seedData,
          seedChanged,
          tablesToClear(migrated.signatures, seedChanged),
          seeded.sequences,
        ),
      );

      if (sources.buckets.length > 0) {
        await packBuckets(ctx, sources.buckets, staging.seedStorage);
      }

      seed = {
        key: seedKey(key, seeds),
        files: seeds,
        counts: rowCounts(seeded.signatures, seedChanged),
        objects: seeds.length - sources.sql.length,
        fingerprint: seeded.fingerprint,
      };
    }

    const manifest: BaselineManifest = {
      format: BASELINE_FORMAT,
      key,
      createdAt: new Date().toISOString(),
      versions,
      migrations,
      counts: rowCounts(migrated.signatures, changed),
      fingerprint: migrated.fingerprint,
      ...(seed === undefined ? {} : { seed }),
    };

    await writeFile(staging.manifest, `${JSON.stringify(manifest, null, 2)}\n`);
    await mkdir(dirname(files.dir), { recursive: true });
    await rm(files.dir, { recursive: true, force: true });
    await rename(staging.dir, files.dir);

    ctx.log(
      `Wrote baseline ${key.slice(0, 12)}: ${String(schema.actions)} schema actions, ${String(changed.length)} tables with rows`,
    );

    let verified = false;

    if (options.verify) {
      await timer.step("verify", () =>
        verifyBaseline(ctx, { out: options.out, withSeed: options.withSeed }),
      );

      verified = true;
    }

    return done(key, manifest, false, verified);
  } finally {
    await built?.destroy();
    await rm(staging.dir, { recursive: true, force: true });
  }
}
