import type { AppTablesConfig } from "../config/types/app-tables.ts";
import type { PresetCatalog, PresetGlueItem } from "./catalog-types.ts";
import type { ResolvedPreset } from "./resolve.ts";

import { PRESET_CATALOG } from "./catalog.generated.ts";
import { encodePreset } from "./code.ts";
import { presetConfig } from "./config.ts";

const CREATE_URL = "https://app.bettersupabase.com/create";

/** The comment a config with the provider access model gets above `blocks`. */
export const PROVIDER_COMMENT: readonly string[] = [
  "  // The provider access model reads roles from your authorization",
  "  // library: set `authorization` to its adapter.",
];

const key = (name: string): string =>
  /^[a-z_$][a-z0-9_$]*$/i.test(name) ? name : JSON.stringify(name);

const camel = (name: string): string =>
  name.replaceAll(/-([a-z0-9])/g, (_, letter: string) => letter.toUpperCase());

/** A JSON value as a TypeScript literal, one line. */
function literal(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(literal).join(", ")}]`;
  }

  if (typeof value === "object" && value !== null) {
    const entries = Object.entries(value);

    if (entries.length === 0) {
      return "{}";
    }

    return `{ ${entries.map(([name, each]) => `${key(name)}: ${literal(each)}`).join(", ")} }`;
  }

  return JSON.stringify(value);
}

/** The keys `configSource` writes: `presetConfig`, and `appTables` for a design. */
export type ConfigSourceKeys = ReturnType<typeof presetConfig> & {
  readonly appTables?: AppTablesConfig;
};

/** The `/create` URL of a preset, with `&design=` when `designCode` isn't empty. */
export function createUrl(resolved: ResolvedPreset, designCode = ""): string {
  const preset = `${CREATE_URL}?preset=${encodePreset(resolved.preset)}`;

  return designCode === "" ? preset : `${preset}&design=${designCode}`;
}

/**
 * `better-supabase.config.ts` with these keys: every block with its reason,
 * the conventions, and the app tables, under a comment with the `/create` URL.
 */
export function configSource(
  resolved: ResolvedPreset,
  config: ConfigSourceKeys,
  url: string,
): string {
  const lines = [
    'import { defineConfig } from "better-supabase/config";',
    "",
    `// ${url}`,
    "export default defineConfig({",
  ];

  if (config.casing !== undefined) {
    lines.push(`  casing: ${literal(config.casing)},`);
  }

  if (config.sql !== undefined) {
    lines.push(`  sql: ${literal(config.sql)},`);
  }

  if (config.integrations !== undefined) {
    lines.push(`  integrations: ${literal(config.integrations)},`);
  }

  if (resolved.preset.access === "provider") {
    lines.push(...PROVIDER_COMMENT);
  }

  lines.push("  blocks: {");
  const entries = Object.entries(config.blocks);

  for (const block of resolved.blocks) {
    const entry = entries.find(([name]) => name === block.name)?.[1] ?? {};
    const note = block.selected ? "" : ` // ${block.reason}`;
    lines.push(`    ${key(block.name)}: ${literal(entry)},${note}`);
  }

  lines.push("  },");

  if (config.appTables !== undefined) {
    lines.push("  appTables: {");

    for (const [name, table] of Object.entries(config.appTables)) {
      lines.push(`    ${key(name)}: ${literal(table)},`);
    }

    lines.push("  },");
  }

  lines.push("});", "");

  return lines.join("\n");
}

/**
 * `better-supabase.config.ts` for a resolved preset: every block with its
 * reason, and the conventions that differ from the defaults.
 */
export function presetConfigSource(resolved: ResolvedPreset): string {
  return configSource(resolved, presetConfig(resolved), createUrl(resolved));
}

/**
 * `lib/blocks.ts`: the blocks with a TypeScript client, wired with
 * `defineBlocks` over the Data API as the caller. Each block's schema (the
 * API schema when `sql.api` is set) and shared options come from
 * `blockConfig`, which `better-supabase gen` writes to
 * `blocks.generated.ts`; `blockConfigImport` is its import path.
 */
export function presetBlocksSource(
  resolved: ResolvedPreset,
  blockConfigImport = "./supabase/blocks.generated",
): string {
  const clients = resolved.manifests.flatMap((manifest) =>
    manifest.client === null
      ? []
      : [{ name: manifest.name, ...manifest.client }],
  );

  return [
    "import {",
    "  type RpcClient,",
    "  defineBlocks,",
    "  rpcTransport,",
    '} from "better-supabase/blocks";',
    ...clients.map(
      (client) => `import { ${client.export} } from "${client.subpath}";`,
    ),
    "",
    `import { blockConfig } from ${JSON.stringify(blockConfigImport)};`,
    "",
    "/** The installed blocks, with the settings `better-supabase gen` writes from the config. */",
    "export const blockSet = defineBlocks(blockConfig, {",
    ...clients.map((client) => `  ${camel(client.name)}: ${client.export},`),
    "});",
    "",
    "/**",
    " * The blocks as typed clients, acting as the caller of `supabase`: its",
    " * token, so RLS and each function's checks apply.",
    " */",
    "export function blocks(supabase: RpcClient) {",
    "  return blockSet.create({ transport: rpcTransport(supabase) });",
    "}",
    "",
  ].join("\n");
}

/** Where `presetBlocksSource` goes, as a shadcn target. */
const WIRING_TARGET = "@lib/blocks.ts";

/**
 * The registry glue for the preset's framework and platforms: each item
 * whose blocks are all installed, except bundles and items that write
 * `lib/blocks.ts`, which the preset writes itself.
 */
export function presetGlue(
  resolved: ResolvedPreset,
  catalog: PresetCatalog = PRESET_CATALOG,
): readonly PresetGlueItem[] {
  const { preset } = resolved;

  const platforms =
    preset.platforms === "both" ? ["web", "native"] : [preset.platforms];

  const installed = new Set(resolved.blocks.map((block) => block.name));

  return catalog.glue.filter(
    (item) =>
      item.preset === undefined &&
      !item.targets.includes(WIRING_TARGET) &&
      item.frameworks.includes(preset.framework) &&
      item.platforms.some((platform) => platforms.includes(platform)) &&
      item.blocks.every((block) => installed.has(block)),
  );
}

/** The shadcn command that copies glue items into the app. */
export function glueCommand(items: readonly PresetGlueItem[]): string {
  return `npx shadcn@latest add ${items.map((item) => `@better-supabase/${item.name}`).join(" ")}`;
}

/** The command that starts a project from the preset. */
export function presetInstallCommand(resolved: ResolvedPreset): string {
  return `npx better-supabase init --preset ${encodePreset(resolved.preset)}`;
}

/** The command that applies the preset to an existing project. */
export function presetApplyCommand(resolved: ResolvedPreset): string {
  return `npx better-supabase apply --preset ${encodePreset(resolved.preset)}`;
}
