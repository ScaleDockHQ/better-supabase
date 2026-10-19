import type { BlockCategory } from "../../blocks/index.ts";
import type { AnyCommand } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";

import {
  glueCommand,
  PRESET_CATALOG,
  type PresetCatalogBlock,
} from "../../preset/index.ts";
import { SQL_MODULES } from "../../sql/index.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";

const CATEGORIES: readonly BlockCategory[] = [
  "identity",
  "tenancy",
  "collaboration",
  "messaging",
  "growth",
  "crm",
  "work",
  "people",
  "commerce",
  "scheduling",
  "content",
  "ai",
  "automation",
  "developer",
  "admin",
  "database",
];

const LIST_ARGS = {
  category: {
    type: "string",
    description:
      "One category: identity, tenancy, collaboration, messaging, growth, crm, work, people, commerce, scheduling, content, ai, automation, developer, admin or database",
    valueHint: "name",
  },
} as const;

const VIEW_ARGS = {
  block: {
    type: "positional",
    required: false,
    description: "The block to show",
  },
} as const;

const SEARCH_ARGS = {
  text: {
    type: "positional",
    required: false,
    variadic: true,
    description: "Words to find in block names, titles and descriptions",
  },
} as const;

interface BlockEntry {
  readonly name: string;
  readonly title: string;
  readonly description: string;
  readonly category: BlockCategory;
  readonly requires: readonly string[];
  readonly integrates: readonly string[];
  readonly modes: readonly string[];
  readonly client: string | null;
  readonly page: string;
}

function entryOf(block: PresetCatalogBlock): BlockEntry {
  const module = SQL_MODULES[block.name];

  const manifest = PRESET_CATALOG.manifests.find(
    (each) => each.name === block.manifest,
  );

  return {
    name: block.name,
    title: block.title,
    description: module?.description ?? "",
    category: block.category,
    requires: block.requires,
    integrates: block.integrates,
    modes: module?.modes ?? ["managed"],
    client: manifest?.client?.subpath ?? null,
    page: `https://bettersupabase.com/blocks/${block.name}`,
  };
}

const ENTRIES: readonly BlockEntry[] = PRESET_CATALOG.blocks.map(entryOf);

function listing(entries: readonly BlockEntry[]): string[] {
  const width = Math.max(0, ...entries.map((entry) => entry.name.length));

  return CATEGORIES.flatMap((category) => {
    const rows = entries.filter((entry) => entry.category === category);

    if (rows.length === 0) {
      return [];
    }

    return [
      "",
      `${category}:`,
      ...rows.map((entry) => `  ${entry.name.padEnd(width)}  ${entry.title}`),
    ];
  }).slice(1);
}

export function listBlocks(category: string | undefined): CommandResult {
  if (category !== undefined && !CATEGORIES.some((each) => each === category)) {
    throw new CliError(
      "usage",
      `Unknown category "${category}". Categories: ${CATEGORIES.join(", ")}`,
    );
  }

  const entries = ENTRIES.filter(
    (entry) => category === undefined || entry.category === category,
  );

  return {
    code: 0,
    output: listing(entries).join("\n"),
    data: { blocks: entries },
  };
}

export function viewBlock(name: string | undefined): CommandResult {
  if (name === undefined) {
    throw new CliError("usage", `Name a block.`);
  }

  const entry = ENTRIES.find((each) => each.name === name);

  if (entry === undefined) {
    throw new CliError(
      "usage",
      `Unknown block "${name}". Run \`better-supabase blocks search ${name}\`.`,
    );
  }

  const glue = PRESET_CATALOG.glue.filter(
    (item) => item.preset === undefined && item.blocks.includes(name),
  );

  const lines = [
    `${entry.title} (${entry.name}, ${entry.category})`,
    "",
    entry.description,
    "",
    `Requires:   ${entry.requires.join(", ") || "nothing"}`,
    `Works with: ${entry.integrates.join(", ") || "nothing"}`,
    `Modes:      ${entry.modes.join(", ")}`,
    ...(entry.client === null ? [] : [`Client:     ${entry.client}`]),
    "",
    `Install: better-supabase add ${entry.name}`,
    ...glue.map(
      (item) => `Glue (${item.frameworks.join(", ")}): ${glueCommand([item])}`,
    ),
    `More: ${entry.page}`,
  ];

  return { code: 0, output: lines.join("\n"), data: { block: entry, glue } };
}

export function searchBlocks(text: string | undefined): CommandResult {
  if (text === undefined || text.trim() === "") {
    throw new CliError("usage", `Pass the text to search for.`);
  }

  const query = text.toLowerCase();

  const found = ENTRIES.filter((entry) =>
    [entry.name, entry.title, entry.description].some((field) =>
      field.toLowerCase().includes(query),
    ),
  );

  return {
    code: 0,
    output:
      found.length === 0
        ? `No block matches "${text}". Run \`better-supabase blocks list\`.`
        : listing(found).join("\n"),
    data: { blocks: found },
  };
}

export const blocksListCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("blocks list"),
  args: LIST_ARGS,
  run: (args) => Promise.resolve(listBlocks(args.category)),
});

export const blocksViewCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("blocks view"),
  args: VIEW_ARGS,
  run: (args) => Promise.resolve(viewBlock(args.block)),
});

export const blocksSearchCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("blocks search"),
  args: SEARCH_ARGS,
  run: (args) => Promise.resolve(searchBlocks(args._.join(" "))),
});
