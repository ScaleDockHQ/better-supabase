import { posix } from "node:path";

import type { BlockNaming, GeneratedBlock } from "../../blocks/index.ts";
import type {
  GeneratedFile,
  GeneratorBlock,
  ResolvedConfig,
} from "../../config/index.ts";
import type {
  PresetCatalog,
  PresetCatalogManifest,
} from "../../preset/index.ts";

import { entityNames } from "../../blocks/index.ts";
import {
  blockEntities,
  blockEntityRenames,
  blockEventRenames,
  blockFormerFunctions,
  tenantNameOf,
} from "../../config/index.ts";
import { PRESET_CATALOG } from "../../preset/index.ts";
import {
  appTableEventTypes,
  BLOCK_OPTION_SCHEMAS,
  instanceFunctions,
  resolveBlock,
  resolveBlocks,
  SQL_MODULES,
} from "../../sql/index.ts";
import { nameConstantLines } from "./block-names.ts";
import { GENERATED_HEADER } from "./emit.ts";
import { prop, q, runtimeSubpath } from "./shared.ts";

/** `blocks.generated.ts`, next to the main generated module. */
export function blockConfigPath(
  config: Pick<ResolvedConfig, "output">,
): string {
  return posix.join(posix.dirname(config.output), "blocks.generated.ts");
}

function hasSchema(
  module: string,
): module is keyof typeof BLOCK_OPTION_SCHEMAS {
  return module in BLOCK_OPTION_SCHEMAS;
}

const DEFAULT_TENANT_COLUMN = "tenant_id";

function tenantColumnOf(
  config: Pick<ResolvedConfig, "blocks" | "sql">,
  modules: readonly string[],
): string | undefined {
  const names = new Set<string>();
  const others = new Set<string>();

  for (const module of modules) {
    const resolved = resolveBlock(config.blocks[module]);

    for (const [table, spec] of Object.entries(
      SQL_MODULES[module]?.names?.tables ?? {},
    )) {
      if (resolved.tables[table] === null) {
        continue;
      }

      for (const [logical, name] of Object.entries(spec.columns)) {
        if (name !== DEFAULT_TENANT_COLUMN) {
          others.add(name);
          continue;
        }

        const mapped = resolved.columns[table]?.[logical];

        if (mapped !== null) {
          names.add(mapped ?? config.sql.tenantColumn ?? name);
        }
      }
    }
  }

  const [name] = names;

  return names.size === 1 &&
    name !== undefined &&
    name !== DEFAULT_TENANT_COLUMN &&
    !others.has(name)
    ? name
    : undefined;
}

/**
 * The tenant columns `blocks.<module>.columns` renames, as database name to
 * default name. A name another column of the block has by default is left out,
 * since mapping it back would rename that column too.
 */
function tenantColumnsOf(
  config: Pick<ResolvedConfig, "blocks">,
  modules: readonly string[],
): Record<string, string> {
  const tables = modules.flatMap((module) =>
    Object.entries(SQL_MODULES[module]?.names?.tables ?? {}).map(
      ([table, spec]) =>
        [spec, resolveBlock(config.blocks[module]).columns[table]] as const,
    ),
  );

  const defaults = new Set(
    tables.flatMap(([spec]) =>
      Object.entries(spec.columns)
        .filter(([logical]) => logical !== "tenant")
        .map(([, name]) => name),
    ),
  );

  return Object.fromEntries(
    tables.flatMap(([spec, columns]) => {
      const fallback = spec.columns["tenant"];
      const name = columns?.["tenant"];

      return fallback === undefined ||
        typeof name !== "string" ||
        name === fallback ||
        defaults.has(name)
        ? []
        : [[name, fallback]];
    }),
  );
}

/**
 * How the tenant rename, the modules' renamed entities and their
 * `blocks.<module>.functions` rename the block's functions and payload keys, or
 * undefined when nothing does. `blocks.permissions.functions` is the custom
 * model's templates, not renames.
 */
function namingOf(
  config: Pick<ResolvedConfig, "blocks" | "sql">,
  modules: readonly string[],
  instanceFunctionNames: Readonly<Record<string, string>> = {},
): BlockNaming | undefined {
  const functions = Object.fromEntries([
    ...modules.flatMap((module) =>
      Object.entries(blockFormerFunctions(module, config.blocks)),
    ),
    ...modules.flatMap((module) =>
      module === "permissions"
        ? []
        : Object.entries(resolveBlock(config.blocks[module]).functions),
    ),
    ...Object.entries(instanceFunctionNames),
  ]);

  const entities = modules.flatMap((module) =>
    blockEntityRenames(module, config.blocks),
  );

  const events = modules.flatMap((module) =>
    blockEventRenames(module, config.blocks),
  );

  const tenant = tenantNameOf(config.blocks);
  const renames = Object.keys(functions).length > 0;
  const tenantColumn = tenantColumnOf(config, modules);

  const columns = Object.fromEntries(
    Object.entries(tenantColumnsOf(config, modules)).filter(
      ([name]) => name !== tenantColumn,
    ),
  );

  const moved = Object.keys(columns).length > 0;

  if (
    tenant === undefined &&
    !renames &&
    entities.length === 0 &&
    tenantColumn === undefined &&
    !moved
  ) {
    return undefined;
  }

  return {
    ...(tenant === undefined ? {} : { tenant }),
    ...(tenantColumn === undefined ? {} : { tenantColumn }),
    ...(renames ? { functions } : {}),
    ...(entities.length === 0 ? {} : { entities }),
    ...(events.length === 0 ? {} : { events }),
    ...(moved ? { columns } : {}),
  };
}

/**
 * The generated config of every installed block: its schema, its API schema,
 * and the options marked `client` with the configured value or the module's
 * default. Blocks without a creator get an entry too, since `block.using(...)`
 * builds them with these options.
 */
export function blockConfigEntries(
  config: Pick<
    ResolvedConfig,
    "blocks" | "blockNames" | "instances" | "sql" | "subjects"
  >,
  catalog: PresetCatalog = PRESET_CATALOG,
): Readonly<Record<string, GeneratedBlock>> {
  const installed = resolveBlocks(config.blockNames, {
    modules: config.blocks,
    ...(config.sql.scope === undefined ? {} : { scope: config.sql.scope }),
  }).map((module) => module.name);

  const entries: [string, GeneratedBlock][] = [];

  for (const manifest of catalog.manifests) {
    const modules = manifest.sql.filter((module) => installed.includes(module));
    const [main] = modules;

    if (
      main === undefined &&
      compositeInstalled(manifest, catalog, installed)
    ) {
      entries.push([manifest.name, compositeEntry(config, manifest, catalog)]);
      continue;
    }

    const others = Object.values(config.instances).filter(
      (instance) => instance.block === main,
    );

    if (
      main !== undefined &&
      (others.length === 0 || others.some((each) => each.name === main))
    ) {
      entries.push([manifest.name, generatedEntry(config, modules)]);
    }

    for (const instance of others) {
      if (main === undefined || instance.name === main) {
        continue;
      }

      const layout = {
        modules: config.blocks,
        instances: config.instances,
        subjects: config.subjects,
        ...(config.sql.scope === undefined ? {} : { scope: config.sql.scope }),
      };

      const entry = generatedEntry(
        { ...config, blocks: { ...config.blocks, [main]: instance.config } },
        modules,
        instanceFunctions(layout, installed, instance.name),
      );

      entries.push([
        instance.name,
        {
          ...entry,
          block: manifest.name,
          ...(Object.keys(instance.uses).length === 0
            ? {}
            : { uses: instance.uses }),
        },
      ]);
    }
  }

  return Object.fromEntries(entries);
}

/**
 * One instance's generated config: the schema of its main module, the client
 * options of `modules` and its naming.
 */
/**
 * Whether a composite without a glue module of its own is installed: it
 * composes at least one part and every part is, recursively (ADR 0177).
 */
function compositeInstalled(
  manifest: PresetCatalogManifest,
  catalog: PresetCatalog,
  installed: readonly string[],
): boolean {
  const parts = manifest.composes;

  if (parts === undefined || parts.length === 0 || manifest.sql.length > 0) {
    return false;
  }

  return parts.every((part) => {
    const partManifest = catalog.manifests.find((each) => each.name === part);

    if (partManifest === undefined) {
      return false;
    }

    return partManifest.composes === undefined
      ? partManifest.sql.length > 0 &&
          partManifest.sql.every((module) => installed.includes(module))
      : compositeInstalled(partManifest, catalog, installed);
  });
}

/**
 * The generated entry of a composite without glue SQL: the schema of its first
 * part (or `sql.schema`) and no options, so the composite shows up in
 * `blockConfig` and `defineBlocks` builds it over its parts.
 */
function compositeEntry(
  config: Pick<ResolvedConfig, "blocks">,
  manifest: PresetCatalogManifest,
  catalog: PresetCatalog,
): GeneratedBlock {
  const [first] = manifest.composes ?? [];

  const firstModule = catalog.manifests.find((each) => each.name === first)
    ?.sql[0];

  return {
    schema: resolveBlock(config.blocks[firstModule ?? ""]).schema,
    options: {},
  };
}

function generatedEntry(
  config: Pick<ResolvedConfig, "blocks" | "sql">,
  modules: readonly string[],
  instanceFunctionNames?: Readonly<Record<string, string>>,
): GeneratedBlock {
  const resolved = resolveBlock(config.blocks[modules[0] ?? ""]);
  const options: Record<string, unknown> = {};

  for (const module of modules) {
    if (!hasSchema(module)) {
      continue;
    }

    const configured = resolveBlock(config.blocks[module]).options;

    for (const [key, spec] of Object.entries(
      BLOCK_OPTION_SCHEMAS[module].specs,
    )) {
      if (!spec.client) {
        continue;
      }

      const value = configured[key] ?? spec.default;

      if (value !== undefined) {
        options[key] = value;
      }
    }
  }

  const names = namingOf(config, modules, instanceFunctionNames);

  return {
    schema: resolved.schema,
    ...(resolved.api === undefined ? {} : { api: resolved.api.schema }),
    options,
    ...(names === undefined ? {} : { names }),
  };
}

function literal(value: unknown, indent: string): string {
  if (Array.isArray(value)) {
    return `[${value.map((entry) => literal(entry, indent)).join(", ")}]`;
  }

  if (typeof value === "object" && value !== null) {
    const entries = Object.entries(value);

    if (entries.length === 0) {
      return "{}";
    }

    const inner = `${indent}  `;

    return `{\n${entries
      .map(([key, entry]) => `${inner}${prop(key)}: ${literal(entry, inner)},`)
      .join("\n")}\n${indent}}`;
  }

  return JSON.stringify(value);
}

/** Every event type the app tables emit, in config order. */
function appTableEvents(
  config: Pick<ResolvedConfig, "appTables">,
): readonly string[] {
  return Object.entries(config.appTables).flatMap(([name, table]) =>
    appTableEventTypes(name, table),
  );
}

/**
 * `appTableEvents` and `appTableEventSchemas`, for app tables that set
 * `events`.
 */
function appTableEventLines(types: readonly string[]): string[] {
  if (types.length === 0) {
    return [];
  }

  return [
    "",
    "/**",
    " * The events `tables.<table>.events` writes to the outbox, for `onBlockEvent` and the sinks.",
    " * @public",
    " */",
    "export const appTableEvents = defineEvents({",
    ...types.map((type) => `  ${prop(type)}: event<AppTableEventData>(),`),
    "});",
    "",
    "/**",
    " * The app table events with an open payload, for AsyncAPI's `cloudEvents.blocks`.",
    " * @public",
    " */",
    "export const appTableEventSchemas = {",
    ...types.map((type) => `  ${prop(type)}: true,`),
    "} as const;",
  ];
}

interface RenamedLines {
  /** Specifiers the module imports from `better-supabase/blocks`. */
  readonly specifiers: readonly string[];
  readonly imports: readonly string[];
  readonly lines: readonly string[];
  /** The constant each renamed instance's block is exported under. */
  readonly constants: ReadonlyMap<string, string>;
}

const CATALOG_BLOCKS = new Map(
  PRESET_CATALOG.blocks.map((block) => [block.name, block]),
);

const MANIFESTS = new Map(
  PRESET_CATALOG.manifests.map((manifest) => [manifest.name, manifest]),
);

/** A repository extension the generated schema installs. */
export interface SchemaExtension {
  /** The export that builds it, from `subpath`. */
  readonly export: string;
  /** `blocks/<name>`, under the runtime import. */
  readonly subpath: string;
  /** The argument list of the call, `""` for none. */
  readonly args: string;
}

/**
 * The repository extensions of the installed blocks, in block order. The
 * `memberships` one also stands for an app's own tenancy, when
 * `auth.tenant.column` turns it on without the block.
 */
export function schemaExtensions(
  config: Pick<ResolvedConfig, "blockNames" | "extensions"> &
    Partial<Pick<ResolvedConfig, "blocks">>,
): SchemaExtension[] {
  const tenant = config.extensions.tenant;

  const tenantOptions = Object.entries({
    onMissing: tenant?.onMissing,
    header: tenant?.header,
  }).flatMap(([key, value]) =>
    value === undefined ? [] : [`${key}: ${q(value)}`],
  );

  const tenantArgs =
    tenantOptions.length === 0 ? "" : `{ ${tenantOptions.join(", ")} }`;

  const extensions = config.blockNames.flatMap((name): SchemaExtension[] => {
    const manifest = MANIFESTS.get(CATALOG_BLOCKS.get(name)?.manifest ?? "");

    if (manifest?.extension === undefined) {
      return [];
    }

    return [
      {
        export: manifest.extension,
        subpath: `blocks/${manifest.name}`,
        args:
          manifest.name === "memberships"
            ? tenantArgs
            : STAMPED.has(manifest.name)
              ? stampArgs(name, config.blocks?.[name]?.options?.["stamp"])
              : "",
      },
    ];
  });

  if (
    tenant !== undefined &&
    !extensions.some((entry) => entry.subpath === "blocks/memberships")
  ) {
    extensions.push({
      export: "membershipsExtension",
      subpath: "blocks/memberships",
      args: tenantArgs,
    });
  }

  return extensions;
}

const STAMPED: ReadonlySet<string> = new Set(["created-by", "updated-at"]);

function stampArgs(name: string, stamp: unknown): string {
  if (stamp === undefined || stamp === "client") {
    return "";
  }

  if (stamp === "trigger") {
    return '{ stamp: "trigger" }';
  }

  throw new TypeError(
    `blocks.${name}.options.stamp must be "client" or "trigger", got ${JSON.stringify(stamp)}`,
  );
}

/** The installed blocks with their final names, for `GeneratorModel.blocks`. */
export function generatorBlocks(
  config: Pick<
    ResolvedConfig,
    "blocks" | "blockNames" | "instances" | "sql" | "subjects"
  >,
): GeneratorBlock[] {
  // A composite's entry carries no tables of its own; its parts' do.
  const own = Object.entries(blockConfigEntries(config)).filter(
    ([name, entry]) =>
      entry.block === undefined && MANIFESTS.get(name)?.composes === undefined,
  );

  return own.map(([name, entry]) => {
    const manifest = MANIFESTS.get(CATALOG_BLOCKS.get(name)?.manifest ?? "");
    const owned = manifest?.name === name ? manifest : undefined;
    const client = owned?.client ?? undefined;
    const renames = entityNames(entry.names?.entities ?? []);

    return {
      name,
      schema: entry.schema,
      client:
        client === undefined
          ? undefined
          : { export: renames.rename(client.export), subpath: client.subpath },
      entities: blockEntities(name, config.blocks).map((entity) => ({
        key: entity.key,
        from: { ...entity.from },
        to: { ...entity.to },
        primary: entity.primary,
        table: entity.table,
        url: entity.url,
        schemas: owned?.entitySchemas?.[entity.key] ?? {},
      })),
    };
  });
}

/**
 * For each installed block whose entities `blocks.<name>.entities` renames: the
 * block under its renamed constant (`tasksBlock`) and an alias for each type
 * named after one of its entities (`Task<F>`, `TasksEvents`).
 */
function renamedBlockLines(
  entries: Readonly<Record<string, GeneratedBlock>>,
): RenamedLines {
  const imports: string[] = [];
  const lines: string[] = [];
  const exported = new Set<string>();
  const constants = new Map<string, string>();
  let eventRenames = false;

  for (const manifest of PRESET_CATALOG.manifests) {
    const instances = Object.entries(entries).filter(
      ([key, entry]) =>
        (entry.block ?? key) === manifest.name &&
        (entry.names?.entities ?? []).length > 0,
    );

    if (manifest.client === null || instances.length === 0) {
      continue;
    }

    // A block renamed by more than one instance is imported once, under
    // `default*` names, so no instance's renamed name clashes with an import.
    const aliasAll = instances.length > 1;
    const block = manifest.client.export;

    const entityTypes = (manifest.entityTypes ?? []).filter(
      (type) =>
        !(
          type.name.endsWith("Options") &&
          manifest.entityTypes?.some(
            (other) => `${other.name}Options` === type.name,
          )
        ),
    );

    // A block-named events type (`TasksEvents`) carries no entity noun, but
    // its event types do, so it gets a renamed alias under the same name.
    const eventsType = manifest.events?.type;

    const types =
      eventsType === undefined ||
      entityTypes.some((type) => type.name === eventsType)
        ? entityTypes
        : [...entityTypes, { name: eventsType }];

    const [first] = instances;
    const firstNames = entityNames(first?.[1].names?.entities ?? []);

    const localOf = (name: string): string =>
      aliasAll || firstNames.rename(name) === name ? `Default${name}` : name;

    const local =
      aliasAll || firstNames.rename(block) === block
        ? `default${pascal(block)}`
        : block;

    const specifiers = [
      ...types.map((type) =>
        localOf(type.name) === type.name
          ? `  type ${type.name},`
          : `  type ${type.name} as ${localOf(type.name)},`,
      ),
      `  ${local === block ? block : `${block} as ${local}`},`,
    ];

    imports.push(
      ["import {", ...specifiers, `} from ${q(manifest.client.subpath)};`].join(
        "\n",
      ),
    );

    for (const [instance, entry] of instances) {
      const names = entityNames(entry.names?.entities ?? []);
      const alias = `${pascal(camelOf(instance))}Renames`;
      const key = q(instance);

      const wanted =
        instance === manifest.name
          ? names.rename(block)
          : `${camelOf(instance)}Block`;

      const renamed = exported.has(wanted)
        ? `${camelOf(instance)}Block`
        : wanted;

      exported.add(renamed);
      constants.set(instance, renamed);

      const eventAlias =
        (entry.names?.events?.length ?? 0) === 0 ? alias : `${alias}Events`;

      eventRenames ||= eventAlias !== alias;

      lines.push(
        "",
        `type ${alias} = (typeof blockConfig)[${key}]["names"]["entities"];`,
        ...(eventAlias === alias
          ? []
          : [
              `type ${eventAlias} = EventRenamesOf<(typeof blockConfig)[${key}]["names"]>;`,
            ]),
        "",
        "/**",
        ` * The \`${manifest.name}\` block under the names \`blocks.${instance}.entities\` gives it.`,
        " * @public",
        " */",
        `export const ${renamed} = renameBlock(${local}, blockConfig[${key}].names);`,
        ...renamedTypeLines(
          types,
          names,
          localOf,
          alias,
          eventAlias,
          exported,
          {
            block: eventsType,
            instance:
              instance === manifest.name
                ? undefined
                : `${pascal(camelOf(instance))}Events`,
          },
        ),
      );
    }
  }

  return {
    specifiers:
      imports.length === 0
        ? []
        : [
            "renameBlock",
            ...(eventRenames ? ["type EventRenamesOf"] : []),
            "type RenamedEvents",
            "type RenamedType",
          ],
    imports,
    lines,
    constants,
  };
}

/**
 * `blocks`: every installed instance with a client, under its key, for
 * `defineBlocks(blockConfig, blocks)`. A renamed instance uses its renamed
 * constant; the others import their block.
 */
function instanceMapLines(
  entries: Readonly<Record<string, GeneratedBlock>>,
  renamed: ReadonlyMap<string, string>,
  synced: ReadonlySet<string> | undefined,
): { readonly imports: readonly string[]; readonly lines: readonly string[] } {
  const imported = new Map<string, { local: string; subpath: string }>();
  const members: string[] = [];

  for (const [instance, entry] of Object.entries(entries)) {
    const manifest = MANIFESTS.get(entry.block ?? instance);
    const client = manifest?.client;

    if (manifest === undefined || client === undefined || client === null) {
      continue;
    }

    if (synced !== undefined && !synced.has(instance)) {
      members.push("  /** Needs the network on native. */");
    }

    const constant = renamed.get(instance);

    if (constant !== undefined) {
      members.push(`  ${prop(instance)}: ${constant},`);
      continue;
    }

    const local = `${camelOf(manifest.name)}BlockInstance`;
    imported.set(manifest.name, { local, subpath: client.subpath });
    members.push(`  ${prop(instance)}: ${local},`);
  }

  if (members.length === 0) {
    return { imports: [], lines: [] };
  }

  return {
    imports: [...imported].map(([name, { local, subpath }]) => {
      const block = MANIFESTS.get(name)?.client?.export ?? local;

      return `import { ${block} as ${local} } from ${q(subpath)};`;
    }),
    lines: [
      "",
      "/**",
      " * Every installed block instance with a client, under its key, for",
      " * `defineBlocks(blockConfig, { ...blocks, ... })`. Override an entry to give",
      " * a block its ports (`notifications: notificationsBlock.using(...)`).",
      ...(synced === undefined
        ? []
        : [
            " * Instances outside `gen.powersync.instances` call the Data API, so",
            " * their hooks need the network on native.",
          ]),
      " * @public",
      " */",
      "export const blocks = {",
      ...members,
      "} as const;",
    ],
  };
}

/**
 * An alias for each of `types` under the name an instance's entity renames give
 * it, skipping a name another instance already exports. A renamed instance's
 * block-named events type takes the instance's name (`MaintenanceEvents`).
 */
function renamedTypeLines(
  types: readonly { readonly name: string; readonly fields?: boolean }[],
  names: ReturnType<typeof entityNames>,
  localOf: (name: string) => string,
  alias: string,
  eventAlias: string,
  exported: Set<string>,
  events: {
    readonly block: string | undefined;
    readonly instance: string | undefined;
  },
): string[] {
  return types.flatMap((type) => {
    const name =
      type.name === events.block && events.instance !== undefined
        ? events.instance
        : names.rename(type.name);

    const source = localOf(type.name);

    if (exported.has(name)) {
      return [];
    }

    exported.add(name);

    if (type.name.endsWith("Events")) {
      return [
        "",
        "/** @public */",
        `export type ${name} = RenamedEvents<${source}, ${eventAlias}>;`,
      ];
    }

    return type.fields === true
      ? [
          "",
          "/** @public */",
          `export type ${name}<F extends object = Record<never, never>> = RenamedType<${source}<F>, ${alias}>;`,
        ]
      : [
          "",
          "/** @public */",
          `export type ${name} = RenamedType<${source}, ${alias}>;`,
        ];
  });
}

function camelOf(name: string): string {
  return name.replaceAll(/-([a-z0-9])/g, (_, c: string) => c.toUpperCase());
}

function pascal(name: string): string {
  return name.charAt(0).toUpperCase() + name.slice(1);
}

/**
 * `blocks.generated.ts`: each installed block's schema, API schema and the
 * options its TypeScript side reads, for `defineBlocks(blockConfig, ...)`, and
 * the app table events. `undefined` when the config installs no blocks.
 */
export function emitBlockConfig(
  config: Pick<
    ResolvedConfig,
    | "appTables"
    | "blocks"
    | "blockNames"
    | "buckets"
    | "casing"
    | "instances"
    | "output"
    | "gen"
    | "sql"
    | "subjects"
  >,
  options: { readonly runtimeImport?: string } = {},
): GeneratedFile | undefined {
  if (config.blockNames.length === 0) {
    return undefined;
  }

  const entries = blockConfigEntries(config);
  const events = appTableEvents(config);
  const runtime = options.runtimeImport ?? "better-supabase";
  const renamed = renamedBlockLines(entries);
  const constants = nameConstantLines(config, entries);
  const synced = config.gen.powersync?.instances;

  const instances = instanceMapLines(
    entries,
    renamed.constants,
    synced === undefined ? undefined : new Set(synced),
  );

  const specifiers = [
    ...(events.length === 0
      ? []
      : ["type AppTableEventData", "defineEvents", "event"]),
    "type GeneratedBlocks",
    ...renamed.specifiers,
    ...constants.specifiers,
  ].toSorted((a, b) =>
    a.replace("type ", "").localeCompare(b.replace("type ", "")),
  );

  const blocksImport =
    specifiers.length === 1
      ? `import type { GeneratedBlocks } from ${q(runtimeSubpath(runtime, "blocks"))};`
      : `import {\n${specifiers.map((name) => `  ${name},`).join("\n")}\n} from ${q(runtimeSubpath(runtime, "blocks"))};`;

  return {
    path: blockConfigPath(config),
    contents: [
      GENERATED_HEADER,
      "",
      blocksImport,
      ...renamed.imports,
      ...constants.imports,
      ...instances.imports,
      "",
      "/**",
      " * The installed blocks' settings from the `blocks` config, for",
      " * `defineBlocks(blockConfig, { ... })`: each block's schema, API schema",
      " * and the options its SQL and TypeScript halves share.",
      " */",
      `export const blockConfig = ${literal(entries, "")} as const satisfies GeneratedBlocks;`,
      ...renamed.lines,
      ...instances.lines,
      ...appTableEventLines(events),
      ...constants.lines,
      "",
    ].join("\n"),
  };
}
