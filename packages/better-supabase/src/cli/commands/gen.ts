import { existsSync } from "node:fs";
import { readFile, rm, stat } from "node:fs/promises";
import { basename, isAbsolute, relative, resolve, sep } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

import type {
  GeneratedFile,
  GeneratorModel,
  ResolvedConfig,
} from "../../config/index.ts";
import type { AnyCommand, CliArgs, CliContext } from "../command.ts";
import type { CliEnv } from "../env.ts";
import type { IntrospectionSource } from "../introspect/source.ts";
import type { Snapshot } from "../introspect/types.ts";

import {
  type ModuleFile,
  moduleLayout,
  renderModules,
  sameModuleFile,
} from "../../sql/index.ts";
import { defineCliCommand } from "../command.ts";
import { stdinDatabaseUrl } from "../config.ts";
import { fileDiff } from "../diff.ts";
import { configuredPermdockKeys } from "../doctor/permdock.ts";
import { emitMeta, emitModule, metaPaths } from "../gen/emit.ts";
import { buildModel, generatorModel } from "../gen/model.ts";
import { CACHE_DIR, writeAtomic } from "../introspect/cache.ts";
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
import { readPermdock, unsafeKey } from "../permdock.ts";
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

export interface RenderOptions {
  /** Where the generated module imports the runtime from. Defaults to `better-supabase`. */
  readonly runtimeImport?: string;
}

export interface Rendered {
  readonly files: GeneratedFile[];
  /** Config entries that matched nothing in the schema. */
  readonly warnings: readonly string[];
}

/**
 * Renders every generated file for a snapshot, without touching disk:
 * `database.types.ts` (what `supabase gen types` prints), the main module,
 * then each configured generator's files.
 */
export async function renderFiles(
  config: ResolvedConfig,
  snapshot: Snapshot,
  options: RenderOptions = {},
): Promise<GeneratedFile[]> {
  return (await render(config, snapshot, options)).files;
}

export async function render(
  config: ResolvedConfig,
  snapshot: Snapshot,
  options: RenderOptions = {},
): Promise<Rendered> {
  const model = buildModel(snapshot, config);
  const runtime = options.runtimeImport
    ? { runtimeImport: options.runtimeImport }
    : {};
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
    ...runtime,
  });
  const meta = emitMeta(model, {
    types: `./${basename(metaFiles.dts)}`,
    ...runtime,
  });
  const files: GeneratedFile[] = [
    { path: config.databaseTypesOutput, contents: databaseTypes },
    { path: config.output, contents: main },
    { path: metaFiles.js, contents: meta.js },
    { path: metaFiles.dts, contents: meta.dts },
  ];
  const owners = new Map(
    files.map((file) => [resolve(config.root, file.path), "gen"]),
  );
  let view: GeneratorModel | undefined;
  for (const generator of config.generators) {
    let extra: readonly GeneratedFile[];
    try {
      extra = await generator.generate({
        meta: model.meta,
        introspection: model.introspection,
        extras: snapshot.extras,
        config,
        output,
        importPath: (from, to) =>
          importPath(resolve(config.root, from), resolve(config.root, to)),
        model: (view ??= generatorModel(model)),
      });
    } catch (cause) {
      throw new Error(
        `generator "${generator.name}" failed: ${cause instanceof Error ? cause.message : String(cause)}`,
        { cause },
      );
    }
    for (const file of extra) {
      const path = resolve(config.root, file.path);
      const inside = relative(config.root, path);
      if (inside === "" || inside.startsWith("..") || isAbsolute(inside)) {
        throw new Error(
          `generator "${generator.name}" wrote ${file.path}, which is outside the project root`,
        );
      }
      const owner = owners.get(path);
      if (owner !== undefined) {
        throw new Error(
          `generator "${generator.name}" wrote ${file.path}, which ${owner === "gen" ? "better-supabase gen writes" : `generator "${owner}" also writes`}`,
        );
      }
      owners.set(path, generator.name);
      files.push(file);
    }
  }
  return { files, warnings: model.warnings };
}

/** The `read-sets` SQL module file for `config.readSets`, if any are configured. */
async function readSetFile(
  config: ResolvedConfig,
): Promise<ModuleFile | undefined> {
  if (config.readSets.length === 0) return undefined;
  const readSets = await compiledReadSets(config);
  return renderModules(
    ["read-sets"],
    moduleLayout(config, config.sql.testsDir, readSets),
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

/** The files the last `gen` wrote, so the next one can remove those it no longer writes. */
const MANIFEST = `${CACHE_DIR}/gen-manifest.json`;

const manifestPath = (root: string, path: string): string =>
  relative(root, resolve(root, path)).split(sep).join("/");

async function readManifest(root: string): Promise<readonly string[]> {
  const parsed: unknown = await readFile(resolve(root, MANIFEST), "utf8")
    .then((text): unknown => JSON.parse(text))
    .catch(() => undefined);
  if (
    typeof parsed !== "object" ||
    parsed === null ||
    !("version" in parsed) ||
    parsed.version !== 1 ||
    !("files" in parsed) ||
    !Array.isArray(parsed.files)
  ) {
    return [];
  }
  return parsed.files.filter(
    (path): path is string => typeof path === "string",
  );
}

/** Files in the last manifest that this run doesn't generate and that still exist inside the root. */
async function leftoverFiles(
  root: string,
  generated: readonly string[],
): Promise<string[]> {
  const current = new Set(generated);
  return (await readManifest(root)).filter((path) => {
    const inside = relative(root, resolve(root, path));
    return (
      !current.has(path) &&
      inside !== "" &&
      !inside.startsWith("..") &&
      !isAbsolute(inside) &&
      existsSync(resolve(root, path))
    );
  });
}

const writeManifest = (root: string, files: readonly string[]): Promise<void> =>
  writeAtomic(
    resolve(root, MANIFEST),
    `${JSON.stringify({ version: 1, files: [...files].sort() }, null, 2)}\n`,
  ).catch(() => undefined);

const UNFORMATTED =
  'oxfmt is not installed, so database.types.ts is not formatted like `supabase gen types` output. Install it: pnpm add -D oxfmt. @supabase/postgrest-typegen pins oxfmt 0.66.0 as its peer; to allow a newer one, add it to peerDependencyRules.allowedVersions in pnpm-workspace.yaml, keyed "@supabase/postgrest-typegen>oxfmt".';

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
  const { files, warnings } = await render(config, snapshot);
  const pathsOf = (readSets: ModuleFile | undefined): string[] =>
    [...files, ...(readSets ? [readSets] : [])].map((file) =>
      manifestPath(config.root, file.path),
    );
  const notice = `${(await oxfmtInstalled()) ? "" : `\n${UNFORMATTED}`}${warnings.map((warning) => `\nWarning: ${warning}`).join("")}`;

  if (options.check) {
    const readSets = await readSetFile(config);
    const generated = pathsOf(readSets);
    const leftovers = await leftoverFiles(config.root, generated);
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
    if (readSets) {
      const path = resolve(config.root, readSets.path);
      const current = existsSync(path)
        ? await readFile(path, "utf8")
        : undefined;
      if (!sameModuleFile(current, readSets.contents))
        compare(readSets, current);
    }
    if (stale.length > 0 || leftovers.length > 0) {
      const lines = [
        ...stale.map((path) => `  ${path}`),
        ...leftovers.map((path) => `  ${path} (no longer generated)`),
      ];
      return {
        code: 1,
        output: `${diffs.join("\n\n")}${notice}`,
        error: `Generated files are out of date:\n${lines.join("\n")}\nRun \`better-supabase gen\`.`,
        data: { upToDate: false, stale, leftovers, warnings },
      };
    }
    return {
      code: 0,
      output: `Generated files are up to date (${generated.length}).${notice}`,
      data: { upToDate: true, stale: [], leftovers: [], warnings },
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
  const generated = pathsOf(readSets);
  const removed: string[] = [];
  for (const path of await leftoverFiles(config.root, generated)) {
    await rm(resolve(config.root, path), { force: true });
    removed.push(path);
  }
  await writeManifest(config.root, generated);
  const tables = snapshot.extras.tables.filter((table) =>
    config.schemas.includes(table.schema),
  ).length;
  const changes = [
    ...written.map((path) => `  ${path}`),
    ...removed.map((path) => `  ${path} (removed, no longer generated)`),
  ];
  return {
    code: 0,
    output: `${
      changes.length === 0
        ? `No changes (${tables} tables).`
        : `Generated ${tables} tables:\n${changes.join("\n")}`
    }${notice}`,
    data: { tables, written, removed, warnings },
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
    description: "Regenerate whenever the schema or the config file changes",
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

const regenerate = (
  options: GenOptions,
  snapshot: Snapshot,
): Promise<CommandResult> =>
  runGen({ ...options, snapshot }).catch((cause: unknown): CommandResult => ({
    code: 1,
    error: cause instanceof Error ? cause.message : String(cause),
  }));

const modified = (file: string | undefined): Promise<number | undefined> =>
  file
    ? stat(file).then(
        (stats) => stats.mtimeMs,
        () => undefined,
      )
    : Promise.resolve(undefined);

/**
 * Regenerates whenever the schema or the config file changes. A database
 * source keeps one connection open and polls the catalog fingerprint, so an
 * unchanged schema costs one small query per interval; a source without a
 * fingerprint is introspected each time and compared. A changed config file
 * is loaded again and forces a run. A failed run is retried every interval
 * until it succeeds, and the same error is printed once.
 */
async function watch(
  initial: GenOptions,
  interval: number,
  { io, signal, configFile, reloadConfig }: CliContext,
): Promise<CommandResult> {
  let options = initial;
  let last = "";
  let reported = "";
  let stamp = await modified(configFile);
  let db: IntrospectionSource | undefined;
  const aborted = (): boolean => signal?.aborted ?? false;
  const report = (message: string): void => {
    if (message !== reported) io.stderr(`${message}\n`);
    reported = message;
  };
  const closeDb = async (): Promise<void> => {
    await db?.close().catch(() => undefined);
    db = undefined;
  };
  try {
    while (!aborted()) {
      const changed = await modified(configFile);
      if (reloadConfig && changed !== stamp) {
        try {
          options = { ...options, config: await reloadConfig() };
          stamp = changed;
          last = "";
          await closeDb();
        } catch (cause) {
          report(cause instanceof Error ? cause.message : String(cause));
          await sleep(interval, signal);
          continue;
        }
      }
      let polled: { marker: string; snapshot?: Snapshot } | undefined;
      try {
        db ??=
          snapshotFile(options.config, options) === undefined
            ? await openSource(options.config, options.env, options)
            : undefined;
        polled = await poll(options, db, last);
      } catch (cause) {
        report(cause instanceof Error ? cause.message : String(cause));
        await closeDb();
      }
      const result = polled?.snapshot
        ? await regenerate(options, polled.snapshot)
        : undefined;
      if (result && result.code !== 0) {
        report(result.error ?? `gen exited with code ${result.code}`);
      } else if (polled) {
        if (result?.output) io.stdout(`${result.output}\n`);
        last = polled.marker;
        reported = "";
      }
      await sleep(interval, signal);
    }
  } finally {
    await closeDb();
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
    const interval = Number(args.interval ?? 2000);
    if (!Number.isFinite(interval) || interval <= 0) {
      return {
        code: 2,
        error: `--interval must be a positive number of milliseconds, got "${args.interval}"`,
      };
    }
    return args.watch === true
      ? watch(options, interval, context)
      : withSpinner(context.io.prompts, "Generating from the schema", () =>
          runGen(options),
        );
  },
});
