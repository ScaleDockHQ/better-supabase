import type { PresetCatalog, PresetGlueItem } from "./catalog-types.ts";
import type { presetConfig } from "./config.ts";
import type { ResolvedPreset } from "./resolve.ts";

import { groupEntries } from "../config/groups.ts";
import { PRESET_CATALOG } from "./catalog.generated.ts";

/** The comment a config with the provider access model gets above `blocks`. */
export const PROVIDER_COMMENT: readonly string[] = [
  "  // The provider access model reads roles from your authorization",
  "  // library: set `auth.authorization` to its adapter.",
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

/** The flat keys `configSource` writes: `presetConfig`. */
export type ConfigSourceKeys = ReturnType<typeof presetConfig>;

/**
 * `better-supabase.config.ts` with these keys: every block with its reason and
 * the conventions, under a comment with the `/create` URL. A design's tables
 * are SQL files that `init --preset` writes, so they are not in the config.
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

  const grouped = groupEntries(config);
  const blocks = grouped["blocks"];

  for (const group of ["database", "gen", "adapters"]) {
    if (grouped[group] !== undefined) {
      lines.push(`  ${group}: ${literal(grouped[group])},`);
    }
  }

  if (resolved.preset.access === "provider") {
    lines.push(...PROVIDER_COMMENT);
  }

  lines.push("  blocks: {");

  const entries: [string, unknown][] =
    typeof blocks === "object" && blocks !== null ? Object.entries(blocks) : [];

  for (const block of resolved.blocks) {
    const entry = entries.find(([name]) => name === block.name)?.[1] ?? {};
    const note = block.selected ? "" : ` // ${block.reason}`;
    lines.push(`    ${key(block.name)}: ${literal(entry)},${note}`);
  }

  const listed = new Set(resolved.blocks.map((block) => block.name));

  for (const [name, entry] of entries) {
    if (!listed.has(name)) {
      lines.push(`    ${key(name)}: ${literal(entry)},`);
    }
  }

  lines.push("  },", "});", "");

  return lines.join("\n");
}

/**
 * `lib/blocks.ts`: the blocks with a TypeScript client, wired with
 * `defineBlocks` over the Data API as the caller. Each block's schema (the API
 * schema when `sql.api` is set) and shared options come from `blockConfig`,
 * which `better-supabase gen` writes to `blocks.generated.ts`;
 * `blockConfigImport` is its import path.
 */
export function presetBlocksSource(
  resolved: ResolvedPreset,
  blockConfigImport = "./supabase/blocks.generated",
  catalog: PresetCatalog = PRESET_CATALOG,
): string {
  const blocks = resolved.manifests.flatMap((manifest) =>
    manifest.client === null
      ? []
      : [{ name: manifest.name, ...manifest.client }],
  );

  const instances = Object.entries(resolved.preset.instances ?? {}).flatMap(
    ([name, instance]) => {
      const block = catalog.blocks.find(
        (each) => each.name === (instance.block ?? name),
      );

      const client = catalog.manifests.find(
        (manifest) => manifest.name === block?.manifest,
      )?.client;

      return block === undefined ||
        block.name === name ||
        client === null ||
        client === undefined
        ? []
        : [{ name, ...client }];
    },
  );

  const clients = [...blocks, ...instances];

  const imports = [
    ...new Map(clients.map((client) => [client.export, client])).values(),
  ];

  return [
    "import {",
    "  type RpcClient,",
    "  defineBlocks,",
    "  rpcTransport,",
    '} from "better-supabase/blocks";',
    ...imports.map(
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
 * The registry glue for the preset's framework and platforms: each item whose
 * blocks are all installed, except bundles and items that write
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
