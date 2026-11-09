import { basename, dirname, join, resolve } from "node:path";

import type { GeneratedFile, ResolvedConfig } from "../../config/index.ts";
import type { Snapshot } from "../introspect/types.ts";

import { blockTables } from "../../sql/index.ts";
import { importPath } from "../core/io.ts";
import { runGenerators } from "../generators/run.ts";
import {
  cachedDatabaseTypes,
  cachedTypesModule,
  typesModuleKey,
} from "../introspect/cache.ts";
import {
  generateDatabaseTypes,
  oxfmtInstalled,
} from "../introspect/typegen.ts";
import { appColumnsFor, appSchemaTexts } from "../sql-layout.ts";
import { apiTypeSchemas } from "./api-schemas.ts";
import {
  emitBlockConfig,
  emitBlockConfigModule,
  emitBlockModules,
  emitClientBlocks,
  generatorBlocks,
  schemaExtensions,
} from "./blocks.ts";
import { deprecationWarnings } from "./deprecations.ts";
import {
  emitMeta,
  emitModule,
  emitRuntime,
  emitSchemaModule,
  metaPaths,
  schemaModulePath,
} from "./emit.ts";
import { emitHooks } from "./hooks.ts";
import { buildModel, generatorModel } from "./model.ts";
import { NO_PROJECTED_READS, projectedReads } from "./projected-reads.ts";
import { emitRecords } from "./records.ts";
import { emitServerBlocks } from "./server-blocks.ts";
import { withTableTags } from "./table-tags.ts";
import { emitTableModules, tableModules } from "./tables.ts";

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
const MAPPER_FILE = "schema.bsb";

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
  declared: ResolvedConfig,
  snapshot: Snapshot,
  options: RenderOptions = {},
): Promise<Rendered> {
  const config = withTableTags(declared, snapshot.generator.tables);
  const model = buildModel(snapshot, config);

  const runtime = options.runtimeImport
    ? { runtimeImport: options.runtimeImport }
    : {};

  const output = resolve(config.root, config.output);

  const typegenOptions = {
    schemas: [...config.schemas, ...apiTypeSchemas(config)],
    postgrestVersion: config.postgrestVersion,
  };

  const databaseTypes = await cachedDatabaseTypes(
    config.root,
    [typegenOptions, await oxfmtInstalled(), snapshot.generator],
    () => generateDatabaseTypes(snapshot.generator, typegenOptions),
  );

  const metaFiles = metaPaths(config.output);

  const split =
    config.gen.tableModules !== false &&
    !options.inlineMeta &&
    config.gen.contentMapper !== true;

  const modules = split ? tableModules(model) : undefined;

  const emitOptions = {
    databaseTypesImport: importPath(
      output,
      resolve(config.root, config.databaseTypesOutput),
    ),
    importPathFor: (from: string) =>
      importPath(output, resolve(config.root, from)),
    metaImport: `./${basename(metaFiles.js)}`,
    extensions: options.extensions === false ? [] : schemaExtensions(config),
    ...(modules === undefined ? {} : { tables: modules }),
    ...(options.inlineMeta ? { inlineMeta: true } : {}),
    ...runtime,
  };

  const meta = emitMeta(model, {
    types: `./${basename(metaFiles.dts)}`,
    splitTables: split,
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

  const projected =
    config.blockNames.length === 0
      ? NO_PROJECTED_READS
      : projectedReads(config, model.meta, await appSchemaTexts(config));

  const blockOptions = {
    ...runtime,
    ...(config.blockNames.length === 0
      ? {}
      : {
          appColumns: await appColumnsFor(config),
          ...(projected.viewKeys.size === 0
            ? {}
            : {
                viewFanOut: {
                  views: projected.viewKeys,
                  tables: blockTables(config).byBlock,
                },
              }),
        }),
  };

  const blockConfig = emitBlockConfig(config, blockOptions);

  const blockModule = emitBlockConfigModule(config, blockOptions);

  if (blockConfig && blockModule) {
    files.push(
      blockConfig,
      blockModule,
      ...emitBlockModules(config, blockOptions),
    );

    const clientBlocks = emitClientBlocks(config, blockOptions);

    if (clientBlocks) {
      files.push(clientBlocks);
    }

    files.push(...emitServerBlocks(config, blockOptions));
  }

  files.push(...emitRecords(config));

  if (modules) {
    files.push(...emitTableModules(model, modules, config, runtime));
  }

  // Clients read the app's view over a block table, so no hooks read the table.
  const hooks = emitHooks(
    config,
    Object.keys(model.meta.tables).filter(
      (key) => !projected.baseKeys.has(key),
    ),
    { ...runtime, ...(modules === undefined ? {} : { tables: modules }) },
  );

  if (hooks) {
    files.push(hooks);
  }

  const generated = await runGenerators(
    config.generators,
    {
      meta: model.meta,
      introspection: model.introspection,
      extras: snapshot.extras,
      config: {
        output: config.output,
        databaseTypesOutput: config.databaseTypesOutput,
        casing: config.casing,
        json: config.json,
      },
      imports: { runtime: options.runtimeImport ?? "better-supabase" },
      model: generatorModel(model, generatorBlocks(config)),
    },
    { root: config.root, taken: new Set(files.map((file) => file.path)) },
  );

  files.push(...generated.files.map((entry) => entry.file));

  const validatorsOwner =
    options.extensions === false
      ? undefined
      : generated.capabilities.get("validators");

  const validators =
    validatorsOwner === undefined
      ? undefined
      : generated.files.find((entry) => entry.generator === validatorsOwner)
          ?.file;

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

  if (modules) {
    files.push({
      path: schemaModulePath(config.output),
      contents: emitSchemaModule(model, modules, {
        ...withValidators,
        generated: `./${basename(config.output)}`,
      }),
    });
  }

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
    warnings: [...model.warnings, ...deprecationWarnings(config)],
    notices: model.notices,
    ...(typesModule === undefined ? {} : { typesModule }),
  };
}
