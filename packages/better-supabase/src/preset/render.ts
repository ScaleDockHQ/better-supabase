import type { ResolvedPreset } from "./resolve.ts";

import { encodePreset } from "./code.ts";
import { presetConfig } from "./config.ts";

const CREATE_URL = "https://bettersupabase.com/create";

const key = (name: string): string =>
  /^[a-z_$][a-z0-9_$]*$/i.test(name) ? name : JSON.stringify(name);

const camel = (name: string): string =>
  name.replaceAll(/-([a-z0-9])/g, (_, letter: string) => letter.toUpperCase());

/** A JSON value as a TypeScript literal, one line. */
function literal(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(literal).join(", ")}]`;
  if (typeof value === "object" && value !== null) {
    const entries = Object.entries(value);
    if (entries.length === 0) return "{}";
    return `{ ${entries.map(([name, each]) => `${key(name)}: ${literal(each)}`).join(", ")} }`;
  }
  return JSON.stringify(value);
}

/**
 * `better-supabase.config.ts` for a resolved preset: every block with its
 * reason, and the conventions that differ from the defaults.
 */
export function presetConfigSource(resolved: ResolvedPreset): string {
  const config = presetConfig(resolved);
  const lines = [
    'import { defineConfig } from "better-supabase/config";',
    "",
    `// ${CREATE_URL}?preset=${encodePreset(resolved.preset)}`,
    "export default defineConfig({",
  ];
  if (config.casing !== undefined)
    lines.push(`  casing: ${literal(config.casing)},`);
  if (config.sql !== undefined) lines.push(`  sql: ${literal(config.sql)},`);
  if (config.integrations !== undefined) {
    lines.push(`  integrations: ${literal(config.integrations)},`);
  }
  if (resolved.preset.access === "provider") {
    lines.push(
      "  // The provider access model reads roles from your authorization",
      "  // library: set `authorization` to its adapter.",
    );
  }
  lines.push("  blocks: {");
  const entries = Object.entries(config.blocks);
  for (const block of resolved.blocks) {
    const entry = entries.find(([name]) => name === block.name)?.[1] ?? {};
    const note = block.selected ? "" : ` // ${block.reason}`;
    lines.push(`    ${key(block.name)}: ${literal(entry)},${note}`);
  }
  lines.push("  },", "});", "");
  return lines.join("\n");
}

/**
 * `lib/blocks.ts`: the blocks with a TypeScript client, wired with
 * `createBlocks` over the Data API as the caller.
 */
export function presetBlocksSource(resolved: ResolvedPreset): string {
  const clients = resolved.manifests.flatMap((manifest) =>
    manifest.client === null
      ? []
      : [{ name: manifest.name, ...manifest.client }],
  );
  const api = resolved.preset.api === "none" ? undefined : resolved.preset.api;
  const lines = [
    "import {",
    "  type RpcClient,",
    "  createBlocks,",
    "  rpcTransport,",
    '} from "better-supabase/blocks";',
    ...clients.map(
      (client) => `import { ${client.export} } from "${client.subpath}";`,
    ),
    "",
  ];
  if (api !== undefined) {
    lines.push(
      "/** The schema the blocks expose through the Data API (`sql.api` in the config). */",
      `export const API_SCHEMA = ${JSON.stringify(api)};`,
      "",
    );
  }
  lines.push(
    "/**",
    " * The blocks as typed clients, acting as the caller of `supabase`: its",
    " * token, so RLS and each function's checks apply.",
    " */",
    "export function blocks(supabase: RpcClient) {",
    "  return createBlocks(",
    api === undefined
      ? "    { transport: rpcTransport(supabase) },"
      : "    {\n      transport: rpcTransport(supabase, { schema: API_SCHEMA }),\n      schema: API_SCHEMA,\n    },",
    "    {",
    ...clients.map(
      (client) => `      ${camel(client.name)}: ${client.export},`,
    ),
    "    },",
    "  );",
    "}",
    "",
  );
  return lines.join("\n");
}

/** The command that installs the preset's blocks today: `sql add` with the selected blocks. */
export function presetInstallCommand(resolved: ResolvedPreset): string {
  const selected = resolved.blocks
    .filter((block) => block.selected)
    .map((block) => block.name);
  return `npx better-supabase sql add ${selected.join(" ")}`;
}
