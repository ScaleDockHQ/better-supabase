import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { GeneratedFile, ResolvedConfig } from "../../config/index.ts";
import type { Snapshot } from "../introspect/types.ts";

import { type KitFile, renderKit, sameKitFile } from "../../sql/kit.ts";
import { emitModule } from "../gen/emit.ts";
import { buildModel } from "../gen/model.ts";
import { generateDatabaseTypes } from "../introspect/typegen.ts";
import {
  type CommandResult,
  display,
  importPath,
  writeIfChanged,
} from "../io.ts";
import { compiledReadSets } from "../read-sets.ts";
import { loadSnapshot, type SnapshotSource } from "./snapshot.ts";
import { kitLayout } from "./sql.ts";

export interface GenOptions extends SnapshotSource {
  readonly config: ResolvedConfig;
  readonly env: Readonly<Record<string, string | undefined>>;
  readonly check: boolean;
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
  const main = emitModule(model, {
    databaseTypesImport: importPath(
      output,
      resolve(config.root, config.databaseTypesOutput),
    ),
    importPathFor: (from) => importPath(output, resolve(config.root, from)),
  });
  const files: GeneratedFile[] = [
    { path: config.databaseTypesOutput, contents: databaseTypes },
    { path: config.output, contents: main },
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

export async function runGen(options: GenOptions): Promise<CommandResult> {
  const { config } = options;
  const snapshot =
    options.snapshot ?? (await loadSnapshot(config, options.env, options));
  const files = await renderFiles(config, snapshot);

  if (options.check) {
    const stale: string[] = [];
    for (const file of files) {
      const path = resolve(config.root, file.path);
      const current = existsSync(path)
        ? await readFile(path, "utf8")
        : undefined;
      if (current !== file.contents)
        stale.push(display(config.root, file.path));
    }
    const readSets = await readSetFile(config);
    if (readSets) {
      const path = resolve(config.root, readSets.path);
      const current = existsSync(path)
        ? await readFile(path, "utf8")
        : undefined;
      if (!sameKitFile(current, readSets.contents))
        stale.push(display(config.root, readSets.path));
    }
    if (stale.length > 0) {
      return {
        code: 1,
        error: `Generated files are out of date:\n${stale.map((path) => `  ${path}`).join("\n")}\nRun \`better-supabase gen\`.`,
      };
    }
    return {
      code: 0,
      output: `Generated files are up to date (${files.length + (readSets ? 1 : 0)}).`,
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
        : `Generated ${tables} tables:\n${written.map((path) => `  ${path}`).join("\n")}`,
  };
}
