import { basename, isAbsolute, relative, resolve } from "node:path";

import type {
  GeneratedFile,
  GeneratorModel,
  ResolvedConfig,
} from "../../config/index.ts";
import type { Snapshot } from "../introspect/types.ts";

import { CliError, errorText } from "../core/errors.ts";
import { importPath } from "../core/io.ts";
import { cachedDatabaseTypes } from "../introspect/cache.ts";
import {
  generateDatabaseTypes,
  oxfmtInstalled,
} from "../introspect/typegen.ts";
import { emitBlockConfig, generatorBlocks } from "./blocks.ts";
import { emitMeta, emitModule, metaPaths } from "./emit.ts";
import { buildModel, generatorModel } from "./model.ts";

export interface RenderOptions {
  /**
   * Where the generated module imports the runtime from. Defaults to
   * `better-supabase`.
   */
  readonly runtimeImport?: string;
  /** Writes the metadata into the main module, so it stands alone on stdout. */
  readonly inlineMeta?: boolean;
}

export interface Rendered {
  readonly files: GeneratedFile[];
  /** Config entries that matched nothing in the schema. */
  readonly warnings: readonly string[];
  /** Hints about the schema, printed as they are. */
  readonly notices: readonly string[];
}

/**
 * Renders every generated file for a snapshot, without touching disk:
 * `database.types.ts` (what `supabase gen types` prints), the main module,
 * `blocks.generated.ts` when the config installs blocks, then each configured
 * generator's files.
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

  const typegenOptions = {
    schemas: config.schemas,
    postgrestVersion: config.postgrestVersion,
  };

  const databaseTypes = await cachedDatabaseTypes(
    config.root,
    [typegenOptions, await oxfmtInstalled(), snapshot.generator],
    () => generateDatabaseTypes(snapshot.generator, typegenOptions),
  );

  const metaFiles = metaPaths(config.output);

  const main = emitModule(model, {
    databaseTypesImport: importPath(
      output,
      resolve(config.root, config.databaseTypesOutput),
    ),
    importPathFor: (from) => importPath(output, resolve(config.root, from)),
    metaImport: `./${basename(metaFiles.js)}`,
    ...(options.inlineMeta ? { inlineMeta: true } : {}),
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

  const blockConfig = emitBlockConfig(config, runtime);

  if (blockConfig) {
    files.push(blockConfig);
  }

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
        model: (view ??= generatorModel(model, generatorBlocks(config))),
        ...runtime,
      });
    } catch (cause) {
      throw new CliError(
        "generator_failed",
        `generator "${generator.name}" failed: ${errorText(cause)}`,
        { cause },
      );
    }

    for (const file of extra) {
      const path = resolve(config.root, file.path);
      const inside = relative(config.root, path);

      if (inside === "" || inside.startsWith("..") || isAbsolute(inside)) {
        throw new CliError(
          "generator_failed",
          `generator "${generator.name}" wrote ${file.path}, which is outside the project root`,
        );
      }

      const owner = owners.get(path);

      if (owner !== undefined) {
        throw new CliError(
          "generator_failed",
          `generator "${generator.name}" wrote ${file.path}, which ${owner === "gen" ? "better-supabase gen writes" : `generator "${owner}" also writes`}`,
        );
      }

      owners.set(path, generator.name);
      files.push(file);
    }
  }

  return { files, warnings: model.warnings, notices: model.notices };
}
