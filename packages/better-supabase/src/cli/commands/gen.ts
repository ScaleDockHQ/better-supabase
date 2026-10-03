import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { basename, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

import type { GeneratedFile, ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs, CliContext } from "../command.ts";
import type { CliEnv } from "../env.ts";
import type { IntrospectionSource } from "../introspect/source.ts";
import type { Snapshot } from "../introspect/types.ts";

import {
  type KitFile,
  kitLayout,
  renderKit,
  sameKitFile,
} from "../../sql/index.ts";
import { defineCliCommand } from "../command.ts";
import { stdinDatabaseUrl } from "../config.ts";
import { fileDiff } from "../diff.ts";
import { configuredPermdockKeys, unsafeKey } from "../doctor/permdock.ts";
import { emitMeta, emitModule, metaPaths } from "../gen/emit.ts";
import { buildModel } from "../gen/model.ts";
import { catalogFingerprint } from "../introspect/fingerprint.ts";
import {
  generateDatabaseTypes,
  oxfmtInstalled,
} from "../introspect/typegen.ts";
import {
  type CliIo,
  type CommandResult,
  display,
  importPath,
  writeIfChanged,
} from "../io.ts";
import { readPermdock } from "../permdock.ts";
import { withSpinner } from "../prompts.ts";
import { compiledReadSets } from "../read-sets.ts";
import { type Paint, painter } from "../style.ts";
import {
  loadSnapshot,
  openSource,
  snapshotFile,
  type SnapshotSource,
} from "./snapshot.ts";

export interface GenOptions extends SnapshotSource {
  readonly config: ResolvedConfig;
  readonly env: CliEnv;
  readonly check: boolean;
  /** Colors the `--check` diffs. */
  readonly paint?: Paint;
  /** Pre-loaded snapshot (tests, watch mode). */
  readonly snapshot?: Snapshot;
}

/**
 * Renders every generated file for a snapshot, without touching disk:
 * `database.types.ts` (what `supabase gen types` prints), the main module,
 * then each configured generator's files.
 */
export async function renderFiles(
  config: ResolvedConfig,
  snapshot: Snapshot,
): Promise<GeneratedFile[]> {
  const model = buildModel(snapshot, config);
  const output = resolve(config.root, config.output);
  const databaseTypes = await generateDatabaseTypes(snapshot.generator, {
    schemas: config.schemas,
    postgrestVersion: config.postgrestVersion,
  });
  const metaFiles = metaPaths(config.output);
  const main = emitModule(model, {
    databaseTypesImport: importPath(
      output,
      resolve(config.root, config.databaseTypesOutput),
    ),
    importPathFor: (from) => importPath(output, resolve(config.root, from)),
    metaImport: `./${basename(metaFiles.js)}`,
  });
  const meta = emitMeta(model, { types: `./${basename(metaFiles.dts)}` });
  const files: GeneratedFile[] = [
    { path: config.databaseTypesOutput, contents: databaseTypes },
    { path: config.output, contents: main },
    { path: metaFiles.js, contents: meta.js },
    { path: metaFiles.dts, contents: meta.dts },
  ];
  for (const generator of config.generators) {
    const extra = await generator.generate({
      meta: model.meta,
      introspection: model.introspection,
      extras: snapshot.extras,
      config,
      output,
      importPath: (from, to) =>
        importPath(resolve(config.root, from), resolve(config.root, to)),
    });
    files.push(...extra);
  }
  return files;
}

/** The `read-sets` SQL kit file for `config.readSets`, if any are configured. */
async function readSetFile(
  config: ResolvedConfig,
): Promise<KitFile | undefined> {
  if (config.readSets.length === 0) return undefined;
  const readSets = await compiledReadSets(config);
  return renderKit(
    ["read-sets"],
    kitLayout(config, config.sql.testsDir, readSets),
  )[0];
}

/**
 * `buckets` keys the catalog doesn't mark `rowConditions: false`, as error
 * lines. Without a readable catalog every PermDock bucket is refused, since
 * whether its keys have row conditions is unknown.
 */
async function rowConditionedBuckets(
  config: ResolvedConfig,
): Promise<string[]> {
  const configured = configuredPermdockKeys({ config });
  if (configured.length === 0) return [];
  const project = await readPermdock(config.root, config.permdock);
  const catalog = project?.catalog;
  if (!catalog) {
    const path = project?.catalogPath ?? config.permdock.catalog;
    const problem = project?.problems.find((entry) => entry.startsWith(path));
    return [
      `  ${configured.map(({ bucket }) => `buckets.${bucket}`).join(", ")}: ${problem ? `could not read PermDock's catalog (${problem})` : `there is no ${path}`}, so whether the keys have row conditions is unknown. Run \`permdock catalog\`, or set permdock.catalog in the config.`,
    ];
  }
  return configured.flatMap(({ bucket, keys }) =>
    keys.flatMap((key) => {
      const problem = unsafeKey(catalog, key, project.catalogPath);
      return problem
        ? [`  buckets.${bucket}: "${key}" ${problem.reason}. ${problem.fix}`]
        : [];
    }),
  );
}

const UNFORMATTED =
  'oxfmt is not installed, so database.types.ts is not formatted like `supabase gen types` output. Install the version @supabase/postgrest-typegen pins: pnpm add -D oxfmt@0.66.0. To use a newer oxfmt, allow it in pnpm-workspace.yaml under peerDependencyRules.allowedVersions, keyed "@supabase/postgrest-typegen>oxfmt".';

export async function runGen(options: GenOptions): Promise<CommandResult> {
  const { config } = options;
  const refused = await rowConditionedBuckets(config);
  if (refused.length > 0) {
    return {
      code: 1,
      error: `PermDock's SQL helpers don't check row conditions, so these bucket policies could grant every object in the scope:\n${refused.join("\n")}\nSee doctor BS214.`,
    };
  }
  const snapshot =
    options.snapshot ?? (await loadSnapshot(config, options.env, options));
  const files = await renderFiles(config, snapshot);
  const notice = (await oxfmtInstalled()) ? "" : `\n${UNFORMATTED}`;

  if (options.check) {
    const stale: string[] = [];
    const diffs: string[] = [];
    const compare = (
      file: { readonly path: string; readonly contents: string },
      current: string | undefined,
    ): void => {
      const shown = display(config.root, file.path);
      stale.push(shown);
      diffs.push(fileDiff(shown, current, file.contents, options.paint));
    };
    for (const file of files) {
      const path = resolve(config.root, file.path);
      const current = existsSync(path)
        ? await readFile(path, "utf8")
        : undefined;
      if (current !== file.contents) compare(file, current);
    }
    const readSets = await readSetFile(config);
    if (readSets) {
      const path = resolve(config.root, readSets.path);
      const current = existsSync(path)
        ? await readFile(path, "utf8")
        : undefined;
      if (!sameKitFile(current, readSets.contents)) compare(readSets, current);
    }
    if (stale.length > 0) {
      return {
        code: 1,
        output: diffs.join("\n\n"),
        error: `Generated files are out of date:\n${stale.map((path) => `  ${path}`).join("\n")}\nRun \`better-supabase gen\`.`,
        data: { upToDate: false, stale },
      };
    }
    return {
      code: 0,
      output: `Generated files are up to date (${files.length + (readSets ? 1 : 0)}).${notice}`,
      data: { upToDate: true, stale: [] },
    };
  }

  const written: string[] = [];
  for (const file of files) {
    if (await writeIfChanged(resolve(config.root, file.path), file.contents)) {
      written.push(display(config.root, file.path));
    }
  }
  // Read-set modules import the generated module, so they load after it is written.
  const readSets = await readSetFile(config);
  if (
    readSets &&
    (await writeIfChanged(
      resolve(config.root, readSets.path),
      readSets.contents,
    ))
  ) {
    written.push(display(config.root, readSets.path));
  }
  const tables = snapshot.extras.tables.filter((table) =>
    config.schemas.includes(table.schema),
  ).length;
  return {
    code: 0,
    output:
      written.length === 0
        ? `No changes (${tables} tables).`
        : `Generated ${tables} tables:\n${written.map((path) => `  ${path}`).join("\n")}${notice}`,
    data: { tables, written },
  };
}

/** Where to read the schema from, shared by gen, introspect and doctor. */
export const SOURCE_ARGS = {
  snapshot: {
    type: "string",
    description: "Read a saved snapshot instead of the database",
    valueHint: "file",
  },
  "db-url-stdin": {
    type: "boolean",
    description:
      "Read the connection string from stdin instead of $DATABASE_URL or the config",
  },
  "project-ref": {
    type: "string",
    description: "Read a hosted project through the Management API",
    valueHint: "ref",
  },
} as const;

export async function sourceArgs(
  args: CliArgs<typeof SOURCE_ARGS>,
  io: CliIo,
): Promise<SnapshotSource> {
  const snapshotPath = args.snapshot;
  const dbUrl = await stdinDatabaseUrl(args["db-url-stdin"], io);
  const projectRef = args["project-ref"];
  return {
    ...(snapshotPath ? { snapshotPath } : {}),
    ...(dbUrl ? { dbUrl } : {}),
    ...(projectRef ? { projectRef } : {}),
  };
}

const ARGS = {
  check: {
    type: "boolean",
    description: "Fail when a generated file is out of date",
  },
  watch: {
    type: "boolean",
    description: "Regenerate whenever the schema changes",
  },
  interval: {
    type: "string",
    description: "Milliseconds between checks in --watch. Defaults to 2000",
    valueHint: "ms",
  },
  ...SOURCE_ARGS,
} as const;

const sleep = (ms: number, signal: AbortSignal | undefined): Promise<void> =>
  delay(ms, undefined, signal ? { signal } : {}).catch(() => undefined);

/**
 * Regenerates whenever the schema changes. A database source keeps one
 * connection open and polls the catalog fingerprint, so an unchanged schema
 * costs one small query per interval; a source without a fingerprint is
 * introspected each time and compared.
 */
/**
 * Reads the schema when it may have changed. Returns the new change marker (the
 * catalog fingerprint, or the snapshot itself when the source has none) and
 * the snapshot, or no snapshot when the fingerprint still matches `last`.
 */
async function poll(
  options: GenOptions,
  db: IntrospectionSource | undefined,
  last: string,
): Promise<{ marker: string; snapshot?: Snapshot }> {
  const fingerprint = db
    ? await catalogFingerprint(db.queryable).catch(() => undefined)
    : undefined;
  if (fingerprint !== undefined && fingerprint === last)
    return { marker: last };
  const snapshot = await loadSnapshot(
    options.config,
    options.env,
    options,
    undefined,
    db ? () => Promise.resolve(db) : undefined,
  );
  const marker = fingerprint ?? JSON.stringify(snapshot);
  return marker === last ? { marker } : { marker, snapshot };
}

/**
 * Regenerates whenever the schema changes. A database source keeps one
 * connection open and polls the catalog fingerprint, so an unchanged schema
 * costs one small query per interval.
 */
async function watch(
  options: GenOptions,
  interval: number,
  { io, signal }: CliContext,
): Promise<CommandResult> {
  let last = "";
  let db: IntrospectionSource | undefined;
  const aborted = (): boolean => signal?.aborted ?? false;
  const fromFile = snapshotFile(options.config, options) !== undefined;
  try {
    while (!aborted()) {
      try {
        db ??= fromFile
          ? undefined
          : await openSource(options.config, options.env, options);
        const { marker, snapshot } = await poll(options, db, last);
        last = marker;
        const result = snapshot
          ? await runGen({ ...options, snapshot })
          : undefined;
        if (result?.output) io.stdout(`${result.output}\n`);
        if (result?.error) io.stderr(`${result.error}\n`);
      } catch (cause) {
        io.stderr(
          `${cause instanceof Error ? cause.message : String(cause)}\n`,
        );
        await db?.close().catch(() => undefined);
        db = undefined;
      }
      await sleep(interval, signal);
    }
  } finally {
    await db?.close().catch(() => undefined);
  }
  return { code: 0 };
}

export const genCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "gen",
    description:
      "Writes database.types.ts, generated.ts and its metadata module from the database",
  },
  args: ARGS,
  run: async (args, context) => {
    const options: GenOptions = {
      config: context.config,
      env: context.env,
      check: args.check === true,
      paint: painter(context.io.color),
      ...(await sourceArgs(args, context.io)),
      ...(context.signal ? { signal: context.signal } : {}),
      cache: true,
    };
    return args.watch === true
      ? watch(options, Number(args.interval ?? 2000), context)
      : withSpinner(context.io.prompts, "Generating from the schema", () =>
          runGen(options),
        );
  },
});
