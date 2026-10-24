import {
  basename,
  dirname,
  isAbsolute,
  join,
  relative,
  resolve,
} from "node:path";

import type {
  GeneratedFile,
  GeneratorModel,
  ResolvedConfig,
} from "../../config/index.ts";
import type { Snapshot } from "../introspect/types.ts";

import { CliError, errorText } from "../core/errors.ts";
import { importPath } from "../core/io.ts";
import {
  cachedDatabaseTypes,
  cachedTypesModule,
  typesModuleKey,
} from "../introspect/cache.ts";
import {
  generateDatabaseTypes,
  oxfmtInstalled,
} from "../introspect/typegen.ts";
import {
  emitBlockConfig,
  generatorBlocks,
  schemaExtensions,
} from "./blocks.ts";
import { emitMeta, emitModule, emitRuntime, metaPaths } from "./emit.ts";
import { emitHooks } from "./hooks.ts";
import { buildModel, generatorModel } from "./model.ts";
import { emitRecords } from "./records.ts";

export interface RenderOptions {
  /**
   * Where the generated module imports the runtime from. Defaults to
   * `better-supabase`.
   */
  readonly runtimeImport?: string;
  /** Writes the metadata into the main module, so it stands alone on stdout. */
  readonly inlineMeta?: boolean;
  /**
   * Whether the schema carries the installed blocks' repository extensions and
   * the `validation` extension. `false` emits a bare `defineSchema(meta)`, for
   * code that installs them with `.use()` itself. Defaults to `true`.
   */
  readonly extensions?: boolean;
  /**
   * Also renders the module the content mapper serves for `schema.bsb`, in
   * `typesModule`. Mapper mode (`gen.contentMapper`) always renders it.
   */
  readonly typesModule?: boolean;
}

/** The file the content mapper serves the schema types for. */
export const MAPPER_FILE = "schema.bsb";

/** Where `schema.bsb` sits: next to the generated module. */
export function mapperFilePath(config: ResolvedConfig): string {
  return join(dirname(config.output), MAPPER_FILE);
}

export const MAPPER_FILE_CONTENTS: string = `// The better-supabase content mapper serves the schema types for this file.
// Its contents are ignored. Run \`better-supabase gen\` after a config change.
`;

export interface Rendered {
  readonly files: GeneratedFile[];
  /** Config entries that matched nothing in the schema. */
  readonly warnings: readonly string[];
  /** Hints about the schema, printed as they are. */
  readonly notices: readonly string[];
  /** The module the content mapper serves, when `typesModule` asked for it. */
  readonly typesModule?: string;
}

/**
 * Renders every generated file for a snapshot, without touching disk:
 * `database.types.ts` (what `supabase gen types` prints), the main module,
 * `blocks.generated.ts` when the config installs blocks, the record features in
 * `features/`, then each configured generator's files.
 */
export async function renderFiles(
  config: ResolvedConfig,
  snapshot: Snapshot,
  options: RenderOptions = {},
): Promise<GeneratedFile[]> {
  return (await render(config, snapshot, options)).files;
}

/**
 * The module the content mapper serves for `schema.bsb`: the full generated
 * module with `database.types.ts` inlined, from the cache when the CLI and
 * typegen versions, the config (and `configText`, its file) and the snapshot
 * match the last render.
 */
export async function renderTypesModule(
  config: ResolvedConfig,
  snapshot: Snapshot,
  configText: string | undefined,
): Promise<string> {
  return cachedTypesModule(
    config.root,
    config.output,
    typesModuleKey(config, configText, snapshot),
    async () =>
      (await render(config, snapshot, { typesModule: true })).typesModule ?? "",
  );
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

  const emitOptions = {
    databaseTypesImport: importPath(
      output,
      resolve(config.root, config.databaseTypesOutput),
    ),
    importPathFor: (from: string) =>
      importPath(output, resolve(config.root, from)),
    metaImport: `./${basename(metaFiles.js)}`,
    extensions: options.extensions === false ? [] : schemaExtensions(config),
    ...(options.inlineMeta ? { inlineMeta: true } : {}),
    ...runtime,
  };

  const meta = emitMeta(model, {
    types: `./${basename(metaFiles.dts)}`,
    ...runtime,
  });

  const mapper = config.gen.contentMapper === true;

  const files: GeneratedFile[] = [
    { path: config.output, contents: "" },
    { path: metaFiles.js, contents: meta.js },
    { path: metaFiles.dts, contents: meta.dts },
  ];

  files.splice(
    mapper ? 1 : 0,
    0,
    mapper
      ? { path: mapperFilePath(config), contents: MAPPER_FILE_CONTENTS }
      : { path: config.databaseTypesOutput, contents: databaseTypes },
  );

  const main = mapper ? 0 : 1;

  const blockConfig = emitBlockConfig(config, runtime);

  if (blockConfig) {
    files.push(blockConfig);
  }

  files.push(...emitRecords(config));

  const hooks = emitHooks(config, Object.keys(model.meta.tables), runtime);

  if (hooks) {
    files.push(hooks);
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

  const validators =
    options.extensions === false
      ? undefined
      : files.find((file) => file.validators === true);

  const withValidators = {
    ...emitOptions,
    ...(validators === undefined
      ? {}
      : {
          validatorsImport: importPath(
            output,
            resolve(config.root, validators.path),
          ),
        }),
  };

  files[main] = {
    path: config.output,
    contents: mapper
      ? emitRuntime(model, {
          ...withValidators,
          typesImport: `./${MAPPER_FILE}`,
        })
      : emitModule(model, withValidators),
  };

  const typesModule =
    mapper || options.typesModule === true
      ? emitModule(model, {
          ...withValidators,
          databaseTypes,
          declareMeta: true,
        })
      : undefined;

  return {
    files,
    warnings: model.warnings,
    notices: model.notices,
    ...(typesModule === undefined ? {} : { typesModule }),
  };
}
