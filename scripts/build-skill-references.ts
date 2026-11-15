/**
 * Writes the block references of the consumer skill from the block manifests,
 * so an agent reads the blocks, entities, events, ports and names of the
 * installed version and a hand-written list can't drift (ADR 1060). It writes:
 *
 * - `references/catalog-<category>.md` in `skills/better-supabase`, one per block
 *   category of `BLOCK_CATALOG`, with each block's client, entities, permission
 *   keys, events, ports, actions, env keys and providers;
 * - `references/catalog-index.md`: the category, preset and naming tables.
 *
 * `--write` (`pnpm skill-references`) writes them and `--check` (`pnpm
 * skill-references:check`, part of `pnpm verify`) fails when one is stale or
 * the folder holds a `catalog-*.md` file no category writes.
 */
import { readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { argv, exit } from "node:process";
import * as v from "valibot";

import type {
  BlockCatalogEntry,
  PresetCatalogBlock,
  PresetCatalogManifest,
} from "../packages/better-supabase/src/preset/catalog-types.ts";

import { BLOCK_CATALOG } from "../packages/better-supabase/src/preset/block-catalog.generated.ts";
import { PRESET_CATALOG } from "../packages/better-supabase/src/preset/catalog.generated.ts";

const ROOT = join(import.meta.dirname, "..");

const REFERENCES = join(
  ROOT,
  "packages/better-supabase/skills/better-supabase/references",
);

const INDEX_FILE = join(REFERENCES, "catalog-index.md");
const NAMING_FILE = join(ROOT, "packages/better-supabase/api/naming.json");
const SITE = "https://bettersupabase.com";

const NamingSchema = v.object({ words: v.record(v.string(), v.string()) });

const slug = (category: string): string =>
  category
    .toLowerCase()
    .replaceAll("&", "and")
    .replaceAll(/[^a-z0-9]+/g, "-")
    .replaceAll(/^-|-$/g, "");

/** The file name of a category's reference. */
export const categoryFile = (category: string): string =>
  `catalog-${slug(category)}.md`;

const code = (names: readonly string[]): string =>
  names.map((name) => `\`${name}\``).join(", ");

const oneLine = (text: string): string => text.replaceAll(/\s+/g, " ").trim();

const manifestOf = (
  block: BlockCatalogEntry,
): PresetCatalogManifest | undefined =>
  PRESET_CATALOG.manifests.find((manifest) => manifest.name === block.name);

const moduleOf = (block: BlockCatalogEntry): PresetCatalogBlock | undefined =>
  PRESET_CATALOG.blocks.find((module) => module.name === block.name);

const ports = (manifest: PresetCatalogManifest): string[] => {
  const consumes = Object.entries(manifest.consumes).map(
    ([port, need]) => `${port} (${need})`,
  );

  return [
    ...(consumes.length > 0 ? [`- Consumes: ${code(consumes)}`] : []),
    ...(manifest.provides.length > 0
      ? [`- Provides: ${code(manifest.provides)}`]
      : []),
  ];
};

const blockSection = (block: BlockCatalogEntry): string => {
  const manifest = manifestOf(block);
  const module = moduleOf(block);
  const lines = [`## ${block.name}`, "", oneLine(block.description), ""];

  lines.push(`- Title: ${block.title}`, `- Docs: ${SITE}${block.docs}`);

  if (block.subpath) {
    const exported = manifest?.client?.export;

    lines.push(
      `- Client: ${exported ? `\`${exported}\` from ` : ""}\`${block.subpath}\``,
    );
  }

  lines.push(`- Modes: ${code(block.modes)}`);

  if (block.requires.length > 0) {
    lines.push(`- Requires: ${code(block.requires)}`);
  }

  if (block.integrates.length > 0) {
    lines.push(`- Works with: ${code(block.integrates)}`);
  }

  if (manifest?.composes?.length) {
    lines.push(`- Composes: ${code(manifest.composes)}`);
  }

  const entities = Object.keys(module?.entities?.specs ?? {});

  if (entities.length > 0) {
    lines.push(`- Entities: ${code(entities)}`);
  }

  const tables = Object.values(module?.entities?.tables ?? {}).map(
    (table) => table.name,
  );

  if (tables.length > 0) {
    lines.push(`- Tables: ${code(tables)}`);
  }

  const keys = Object.values(module?.entities?.keys ?? {});

  if (keys.length > 0) {
    lines.push(`- Permission keys: ${code([...new Set(keys)])}`);
  }

  if (block.events.length > 0) {
    lines.push(
      `- Events${manifest?.events ? ` (\`${manifest.events.type}\`)` : ""}: ${code(block.events)}`,
    );
  }

  if (manifest) {
    lines.push(...ports(manifest));

    if (manifest.actions?.length) {
      lines.push(`- Actions: ${code(manifest.actions.map((a) => a.kind))}`);
    }

    if (manifest.env?.length) {
      lines.push(`- Env keys: ${code(manifest.env.map((entry) => entry.key))}`);
    }

    if (manifest.providers?.length) {
      lines.push(
        `- Providers: ${code(manifest.providers.map((provider) => `${provider.option}: ${provider.type}`))}`,
      );
    }
  }

  return lines.join("\n");
};

/** One category's reference file. */
export function categoryReference(category: string): string {
  const blocks = BLOCK_CATALOG.blocks.filter(
    (block) => block.category === category,
  );

  return `${[
    `# ${category} blocks`,
    "",
    "<!-- Generated by scripts/build-skill-references.ts from the block manifests. -->",
    "",
    `The ${category} blocks of this version of better-supabase, from the block manifests. Install one with \`npx better-supabase add <block>\`; the docs page of each block has the method signatures. Entity names are the defaults; an app can rename them under \`blocks.<name>.names\`.`,
    "",
    ...blocks.flatMap((block) => [blockSection(block), ""]),
  ]
    .join("\n")
    .replaceAll(/\n{3,}/g, "\n\n")
    .trimEnd()}\n`;
}

/** The category, preset and naming tables, as `catalog-index.md`. */
export function indexReference(): string {
  const naming = v.parse(
    NamingSchema,
    JSON.parse(readFileSync(NAMING_FILE, "utf-8")),
  );

  const categories = BLOCK_CATALOG.categories.map((category) => {
    const count = BLOCK_CATALOG.blocks.filter(
      (block) => block.category === category,
    ).length;

    return `| [${category}](${categoryFile(category)}) | ${count} |`;
  });

  const presets = BLOCK_CATALOG.presets.map(
    (preset) =>
      `| \`${preset.name}\` | ${preset.groupTitle} | ${oneLine(preset.description)} |`,
  );

  const words = Object.entries(naming.words).map(
    ([word, meaning]) => `| ${word} | ${oneLine(meaning)} |`,
  );

  return [
    "# Block catalog index",
    "",
    "<!-- Generated by scripts/build-skill-references.ts from the block catalog. -->",
    "",
    "## Blocks by category",
    "",
    "Each file lists the blocks of one category with their client, entities, permission keys, events and ports.",
    "",
    "| Category | Blocks |",
    "| --- | --- |",
    ...categories,
    "",
    "## Named presets",
    "",
    "| Preset | Group | What it covers |",
    "| --- | --- | --- |",
    ...presets,
    "",
    "## Words",
    "",
    "| Word | Meaning |",
    "| --- | --- |",
    ...words,
    "",
  ].join("\n");
}

/** Every file the generator writes, by path. */
export function outputs(): Map<string, string> {
  const files = new Map<string, string>();

  for (const category of BLOCK_CATALOG.categories) {
    files.set(
      join(REFERENCES, categoryFile(category)),
      categoryReference(category),
    );
  }

  files.set(INDEX_FILE, indexReference());

  return files;
}

const orphans = (files: ReadonlyMap<string, string>): string[] =>
  readdirSync(REFERENCES)
    .filter((name) => name.startsWith("catalog-"))
    .map((name) => join(REFERENCES, name))
    .filter((file) => !files.has(file));

if (import.meta.main) {
  const files = outputs();

  if (argv.includes("--write")) {
    for (const file of orphans(files)) {
      rmSync(file);
    }

    for (const [file, contents] of files) {
      writeFileSync(file, contents);
    }
  }

  if (argv.includes("--check")) {
    const stale = [
      ...[...files]
        .filter(([file, contents]) => {
          try {
            return readFileSync(file, "utf-8") !== contents;
          } catch {
            return true;
          }
        })
        .map(([file]) => file),
      ...orphans(files),
    ].map((file) => relative(ROOT, file));

    if (stale.length > 0) {
      console.error(
        `build-skill-references: ${stale.join(", ")} ${stale.length === 1 ? "is" : "are"} stale. Run \`pnpm skill-references\`.`,
      );
      exit(1);
    }
  }
}
