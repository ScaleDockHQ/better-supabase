import { posix } from "node:path";

import type { BlockNaming, GeneratedBlock } from "../../blocks/index.ts";
import type { GeneratedFile, ResolvedConfig } from "../../config/index.ts";

import { PRESET_CATALOG } from "../../preset/index.ts";
import {
  appTableEventTypes,
  BLOCK_OPTION_SCHEMAS,
  resolveModule,
  resolveModules,
} from "../../sql/index.ts";
import { GENERATED_HEADER } from "./emit.ts";
import { prop, q } from "./shared.ts";

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

/**
 * How `sql.naming` and the modules' `blocks.<module>.functions` rename the
 * block's functions, or undefined when nothing does.
 * `blocks.access.functions` is the custom model's templates, not renames.
 */
function namingOf(
  config: Pick<ResolvedConfig, "blocks" | "sql">,
  modules: readonly string[],
): BlockNaming | undefined {
  const functions = Object.fromEntries(
    modules.flatMap((module) =>
      module === "access"
        ? []
        : Object.entries(resolveModule(config.blocks[module]).functions),
    ),
  );

  const tenant = config.sql.naming?.tenant;
  const renames = Object.keys(functions).length > 0;

  if (tenant === undefined && !renames) {
    return undefined;
  }

  return {
    ...(tenant === undefined ? {} : { tenant }),
    ...(renames ? { functions } : {}),
  };
}

/**
 * The generated config of every installed block: its schema, its API
 * schema, and the options marked `client` with the configured value or the
 * module's default. Blocks without a creator get an entry too, since
 * `block.using(...)` builds them with these options.
 */
export function blockConfigEntries(
  config: Pick<ResolvedConfig, "blocks" | "blockNames" | "sql">,
): Readonly<Record<string, GeneratedBlock>> {
  const installed = new Set(
    resolveModules(config.blockNames, {
      modules: config.blocks,
      ...(config.sql.scope === undefined ? {} : { scope: config.sql.scope }),
    }).map((module) => module.name),
  );

  const entries: [string, GeneratedBlock][] = [];

  for (const manifest of PRESET_CATALOG.manifests) {
    const modules = manifest.sql.filter((module) => installed.has(module));
    const [main] = modules;

    if (main === undefined) {
      continue;
    }

    const resolved = resolveModule(config.blocks[main]);
    const options: Record<string, unknown> = {};

    for (const module of modules) {
      if (!hasSchema(module)) {
        continue;
      }

      const configured = resolveModule(config.blocks[module]).options;

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

    const naming = namingOf(config, modules);
    entries.push([
      manifest.name,
      {
        schema: resolved.schema,
        ...(resolved.api === undefined ? {} : { api: resolved.api.schema }),
        options,
        ...(naming === undefined ? {} : { naming }),
      },
    ]);
  }

  return Object.fromEntries(entries);
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

/** `appTableEvents` and `appTableEventSchemas`, for app tables that set `events`. */
function appTableEventLines(types: readonly string[]): string[] {
  if (types.length === 0) {
    return [];
  }

  return [
    "",
    "/**",
    " * The events `appTables.<table>.events` writes to the outbox, for `onBlockEvent` and the sinks.",
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

/**
 * `blocks.generated.ts`: each installed block's schema, API schema and the
 * options its TypeScript side reads, for `defineBlocks(blockConfig, ...)`,
 * and the app table events. `undefined` when the config installs no blocks.
 */
export function emitBlockConfig(
  config: Pick<
    ResolvedConfig,
    "appTables" | "blocks" | "blockNames" | "output" | "sql"
  >,
  options: { readonly runtimeImport?: string } = {},
): GeneratedFile | undefined {
  if (config.blockNames.length === 0) {
    return undefined;
  }

  const entries = blockConfigEntries(config);
  const events = appTableEvents(config);
  const runtime = options.runtimeImport ?? "better-supabase";

  return {
    path: blockConfigPath(config),
    contents: [
      GENERATED_HEADER,
      "",
      events.length === 0
        ? `import type { GeneratedBlocks } from ${q(`${runtime}/blocks`)};`
        : `import {\n  type AppTableEventData,\n  defineEvents,\n  event,\n  type GeneratedBlocks,\n} from ${q(`${runtime}/blocks`)};`,
      "",
      "/**",
      " * The installed blocks' settings from the `blocks` config, for",
      " * `defineBlocks(blockConfig, { ... })`: each block's schema, API schema",
      " * and the options its SQL and TypeScript halves share.",
      " */",
      `export const blockConfig = ${literal(entries, "")} as const satisfies GeneratedBlocks;`,
      ...appTableEventLines(events),
      "",
    ].join("\n"),
  };
}
