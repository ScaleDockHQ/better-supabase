import { existsSync } from "node:fs";
import { readFile, rm } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { CliEnv } from "../env.ts";
import type { Snapshot } from "../introspect/types.ts";

import {
  type ModuleFile,
  moduleLayout,
  renderModules,
  sameModuleFile,
} from "../../sql/index.ts";
import { providerLabel, unsafeKey } from "../authorization.ts";
import { loadSnapshot, type SnapshotSource } from "../commands/snapshot.ts";
import { fileDiff } from "../diff.ts";
import { providerBucketKeys } from "../doctor/authorization.ts";
import {
  type CommandResult,
  display,
  sameText,
  writeIfChanged,
} from "../io.ts";
import { compiledReadSets } from "../read-sets.ts";
import { type Paint } from "../style.ts";
import { leftoverFiles, manifestPath, writeManifest } from "./manifest.ts";
import { generationNotices } from "./notices.ts";
import { render } from "./render.ts";

export interface GenOptions extends SnapshotSource {
  readonly config: ResolvedConfig;
  readonly env: CliEnv;
  readonly check: boolean;
  /** Colors the `--check` diffs. */
  readonly paint?: Paint;
  /** Pre-loaded snapshot (tests, watch mode). */
  readonly snapshot?: Snapshot;
  /**
   * Writes only the generated files (`gen --metadata --out`): no read-set SQL
   * module, and the manifest that removes files an earlier run wrote is
   * neither read nor written.
   */
  readonly isolated?: boolean;
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
 * `buckets` keys that reach the authorization provider's functions but
 * aren't marked `sqlComplete: true` in `authorization.permissions`, as
 * error lines.
 */
function rowConditionedBuckets(config: ResolvedConfig): string[] {
  const provider = config.authorization;
  if (!provider) return [];
  return providerBucketKeys(config).flatMap(({ bucket, keys }) =>
    keys.flatMap((key) => {
      const problem = unsafeKey(provider, key);
      return problem
        ? [`  buckets.${bucket}: "${key}" ${problem.reason}. ${problem.fix}`]
        : [];
    }),
  );
}

/** The exit `gen` stops with when bucket keys aren't fully answered by the provider's SQL functions. */
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
  if (refused) return refused;
  const snapshot =
    options.snapshot ?? (await loadSnapshot(config, options.env, options));
  const { files, warnings } = await render(config, snapshot);
  const pathsOf = (readSets: ModuleFile | undefined): string[] =>
    [...files, ...(readSets ? [readSets] : [])].map((file) =>
      manifestPath(config.root, file.path),
    );
  const notice = (await generationNotices(snapshot, warnings))
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
        ? await readFile(path, "utf8")
        : undefined;
      if (!sameText(current, file.contents)) compare(file, current);
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
  const readSets = await readSetsOf();
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
  for (const path of await leftoversOf(generated)) {
    await rm(resolve(config.root, path), { force: true });
    removed.push(path);
  }
  if (!options.isolated) await writeManifest(config.root, generated);
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
