import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { ModuleFile } from "../../sql/index.ts";
import type { SnapshotSource } from "../commands/snapshot.ts";
import type { FileChange, FilePlan } from "../core/files.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";
import type { Snapshot } from "../introspect/types.ts";
import type { Paint } from "../style.ts";

import {
  moduleLayout,
  renderModules,
  sameModuleFile,
} from "../../sql/index.ts";
import { providerLabel, unsafeKey } from "../authorization.ts";
import { loadSnapshot } from "../commands/snapshot.ts";
import {
  applyPlan,
  hasConflicts,
  changedFiles,
  changeLines,
} from "../core/files.ts";
import { display, sameText } from "../core/io.ts";
import { fileDiff } from "../diff.ts";
import { providerBucketKeys } from "../doctor/authorization.ts";
import { compiledReadSets } from "../read-sets.ts";
import { migrationsDir } from "../sql-layout.ts";
import {
  latestMigration,
  READ_SETS_SUFFIX,
  sameModuleMigration,
  writeLatestMigration,
  writesMigrations,
} from "../sql/module-migration.ts";
import { leftoverFiles, manifestPath, writeManifest } from "./manifest.ts";
import { generationNotices } from "./notices.ts";
import { render } from "./render.ts";

export interface GenOptions extends SnapshotSource {
  readonly config: ResolvedConfig;
  readonly env: CliEnv;
  readonly check: boolean;
  /** Prints what would change and writes nothing. */
  readonly dryRun?: boolean;
  /** Overwrites generated paths that hold a file the CLI did not write. */
  readonly force?: boolean;
  /** Colors the `--check` diffs. */
  readonly paint?: Paint;
  /** Pre-loaded snapshot (tests, watch mode). */
  readonly snapshot?: Snapshot;
  /**
   * Writes only the generated files (`gen --metadata --out-dir`): no read-set
   * SQL module, and the manifest that removes files an earlier run wrote is
   * neither read nor written.
   */
  readonly isolated?: boolean;
}

/** The `read-sets` SQL module file for `config.readSets`, if any are configured. */
async function readSetFile(
  config: ResolvedConfig,
): Promise<ModuleFile | undefined> {
  if (config.readSets.length === 0) {
    return undefined;
  }

  const readSets = await compiledReadSets(config);

  // `sql sync` writes the app tables; rendering them here would check their
  // scope against a module list that holds only `read-sets`.
  const { appTables: _appTables, ...layout } = moduleLayout(
    config,
    config.sql.testsDir,
    readSets,
  );

  return renderModules(["read-sets"], layout)[0];
}

/**
 * `buckets` keys that reach the authorization provider's functions but aren't
 * marked `sqlComplete: true` in `authorization.permissions`, as error lines.
 */
function rowConditionedBuckets(config: ResolvedConfig): string[] {
  const provider = config.authorization;

  if (!provider) {
    return [];
  }

  return providerBucketKeys(config).flatMap(({ bucket, keys }) =>
    keys.flatMap((key) => {
      const problem = unsafeKey(provider, key);

      return problem
        ? [`  buckets.${bucket}: "${key}" ${problem.reason}. ${problem.fix}`]
        : [];
    }),
  );
}

/**
 * The exit `gen` stops with when bucket keys aren't fully answered by the
 * provider's SQL functions.
 */
export function refuseRowConditionedBuckets(
  config: ResolvedConfig,
): CommandResult | undefined {
  const refused = rowConditionedBuckets(config);

  return refused.length === 0 || !config.authorization
    ? undefined
    : {
        code: 1,
        error: `The SQL functions of ${providerLabel(config.authorization)} decide by role and scope only, so these bucket policies could grant every object in the scope:\n${refused.join("\n")}\nSee doctor BS214.`,
      };
}

export async function runGen(options: GenOptions): Promise<CommandResult> {
  const { config } = options;
  const refused = refuseRowConditionedBuckets(config);

  if (refused) {
    return refused;
  }

  const snapshot =
    options.snapshot ?? (await loadSnapshot(config, options.env, options));

  const { files, warnings, notices } = await render(config, snapshot);
  // Under the migrations workflow the read sets go into a migration, which
  // the manifest never lists: a later run must not remove it.
  const migrations = !options.isolated && (await writesMigrations(config));

  const pathsOf = (readSets: ModuleFile | undefined): string[] =>
    [...files, ...(readSets && !migrations ? [readSets] : [])].map((file) =>
      manifestPath(config.root, file.path),
    );

  const notice = (await generationNotices(snapshot, warnings, notices))
    .map((line) => `\n${line}`)
    .join("");

  const readSetsOf = (): Promise<ModuleFile | undefined> =>
    options.isolated ? Promise.resolve(undefined) : readSetFile(config);

  const leftoversOf = (generated: readonly string[]): Promise<string[]> =>
    options.isolated
      ? Promise.resolve([])
      : leftoverFiles(config.root, generated);

  if (options.check) {
    const readSets = await readSetsOf();
    const generated = pathsOf(readSets);
    const leftovers = await leftoversOf(generated);
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
        ? await readFile(path, "utf-8")
        : undefined;

      if (!sameText(current, file.contents)) {
        compare(file, current);
      }
    }

    if (readSets && migrations) {
      const latest = await latestMigration(config, READ_SETS_SUFFIX);

      if (!sameModuleMigration(latest?.text, readSets.contents)) {
        compare(
          {
            path:
              latest?.path ??
              `${migrationsDir(config)}/<stamp>${READ_SETS_SUFFIX}`,
            contents: readSets.contents,
          },
          latest?.text,
        );
      }
    } else if (readSets) {
      const path = resolve(config.root, readSets.path);

      const current = existsSync(path)
        ? await readFile(path, "utf-8")
        : undefined;

      if (!sameModuleFile(current, readSets.contents)) {
        compare(readSets, current);
      }
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
        errorCode: "check_failed",
        data: { upToDate: false, stale, leftovers, warnings },
      };
    }

    return {
      code: 0,
      output: `Generated files are up to date (${generated.length}).${notice}`,
      data: { upToDate: true, stale: [], leftovers: [], warnings },
    };
  }

  const flags = { "dry-run": options.dryRun, force: options.force };

  const plan = (
    entries: readonly ModuleFile[] | typeof files,
    remove: readonly string[] = [],
  ): FilePlan => ({
    root: config.root,
    regenerate: "better-supabase gen",
    files: entries.map((file) => ({
      path: file.path,
      contents: file.contents,
    })),
    remove,
  });

  const changes: FileChange[] = [
    ...(await applyPlan(plan(files), flags)).changes,
  ];

  // Read-set modules import the generated module, so they load after it is written.
  const readSets = await readSetsOf();

  if (readSets && migrations) {
    const migration = await writeLatestMigration(
      config,
      READ_SETS_SUFFIX,
      readSets.contents,
      { now: new Date(), dryRun: options.dryRun === true },
    );

    changes.push({
      file: migration.path,
      outcome: migration.line.startsWith("Unchanged ") ? "unchanged" : "create",
    });
  }

  const generated = pathsOf(readSets);

  changes.push(
    ...(await applyPlan(plan([], await leftoversOf(generated)), flags)).changes,
  );

  // `sql.dir` may sit outside the project, as in a monorepo's shared stack.
  if (readSets && !migrations) {
    const path = resolve(config.root, readSets.path);

    changes.push(
      ...(
        await applyPlan(
          {
            ...plan([{ ...readSets, path }]),
            root: dirname(path),
            base: config.root,
          },
          flags,
        )
      ).changes,
    );
  }

  const applied = {
    mode: options.dryRun === true ? ("dry-run" as const) : ("write" as const),
    changes,
    diffs: [],
    drift: false,
  };

  const written = changedFiles(applied);

  if (!options.isolated && options.dryRun !== true) {
    await writeManifest(config.root, generated);
  }

  const tables = snapshot.extras.tables.filter((table) =>
    config.schemas.includes(table.schema),
  ).length;

  const lines = changeLines(applied).filter(
    (line) => !line.startsWith("Unchanged "),
  );

  const conflict = hasConflicts(applied)
    ? {
        code: 1,
        errorCode: "file_conflict" as const,
        error:
          "Some generated files were written by hand, so gen left them alone. Pass --force to overwrite them.",
      }
    : { code: 0 };

  return {
    ...conflict,
    output: `${
      lines.length === 0
        ? `No changes (${tables} tables).`
        : `${lines.join("\n")}\n${options.dryRun === true ? "Would generate" : "Generated"} ${tables} tables.`
    }${notice}`,
    data: { tables, written, files: changes, warnings },
  };
}
