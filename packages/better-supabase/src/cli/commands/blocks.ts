import type { BlockCategory } from "../../blocks/index.ts";
import type { PresetCatalogBlock } from "../../preset/index.ts";
import type { AnyCommand } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";

import { BLOCK_CATEGORIES } from "../../blocks/index.ts";
import {
  glueCommand,
  PRESET_CATALOG,
  PRESET_NAMES,
} from "../../preset/index.ts";
import { SQL_MODULES, renamedBlock } from "../../sql/index.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";
import { SQL_ARGS } from "../sql/args.ts";
import { listModules } from "../sql/list.ts";
import { printModule } from "../sql/print.ts";
import { decodePresetInput } from "./preset.ts";

const LIST_ARGS = {
  category: {
    type: "string",
    description: `One category: ${BLOCK_CATEGORIES.join(", ")}`,
    valueHint: "name",
  },
  installed: {
    type: "boolean",
    description:
      "Every block's SQL with whether this project installed it and lists it in blocks",
  },
  preset: {
    type: "string",
    description:
      "The blocks and conventions of a preset name, a design code or a /create URL",
    valueHint: "name|code|url",
  },
  "tests-dir": SQL_ARGS["tests-dir"],
} as const;

const VIEW_ARGS = {
  block: {
    type: "positional",
    required: true,
    description: "The block to show",
  },
  sql: {
    type: "boolean",
    description:
      "Print the block's SQL as this project's config renders it, instead of its summary",
  },
  "tests-dir": SQL_ARGS["tests-dir"],
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

/** Every block name, for completion. */
export const blockNames = (): readonly string[] =>
  ENTRIES.map((entry) => entry.name);

function listing(entries: readonly BlockEntry[]): string[] {
  const width = Math.max(0, ...entries.map((entry) => entry.name.length));

  return BLOCK_CATEGORIES.flatMap((category) => {
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
  if (
    category !== undefined &&
    !BLOCK_CATEGORIES.some((each) => each === category)
  ) {
    throw new CliError(
      "usage",
      `Unknown category "${category}". Categories: ${BLOCK_CATEGORIES.join(", ")}`,
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
    throw new CliError("input_required", "Name a block.", {
      missing: ["<block>"],
      choices: { "<block>": ENTRIES.map((each) => each.name) },
    });
  }

  const entry = ENTRIES.find((each) => each.name === name);

  if (entry === undefined) {
    const renamed = renamedBlock(name);

    throw new CliError(
      "usage",
      renamed === undefined
        ? `Unknown block "${name}". Run \`better-supabase blocks search ${name}\`.`
        : `The "${name}" block is named "${renamed}" since 0.15. Run \`better-supabase blocks view ${renamed}\`.`,
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
  completions: { category: () => BLOCK_CATEGORIES, preset: () => PRESET_NAMES },
  run: (args, { config }) => {
    if (args.preset !== undefined && args.installed === true) {
      throw new CliError("usage", "Pass --preset or --installed, not both.");
    }

    if (args.preset !== undefined) {
      return decodePresetInput(args.preset);
    }

    return args.installed === true
      ? listModules(config, args)
      : Promise.resolve(listBlocks(args.category));
  },
});

export const blocksViewCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("blocks view"),
  args: VIEW_ARGS,
  completions: { block: blockNames },
  run: (args, { config }) =>
    args.sql === true
      ? printModule(config, args, [args.block])
      : Promise.resolve(viewBlock(args.block)),
});

export const blocksSearchCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("blocks search"),
  args: SEARCH_ARGS,
  run: (args) => Promise.resolve(searchBlocks(args._.join(" "))),
});
