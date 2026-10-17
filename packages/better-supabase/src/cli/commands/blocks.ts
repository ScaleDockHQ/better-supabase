import type { BlockCategory } from "../../blocks/index.ts";
import type { AnyCommand, CliOptions } from "../command.ts";
import type { CommandResult } from "../io.ts";

import {
  glueCommand,
  PRESET_CATALOG,
  type PresetCatalogBlock,
} from "../../preset/index.ts";
import { SQL_MODULES } from "../../sql/index.ts";
import { defineCliCommand } from "../command.ts";

const USAGE = `Usage:
  better-supabase blocks list [--category <name>]   Every block, by category
  better-supabase blocks view <name>                One block: what it needs, works with and installs
  better-supabase blocks search <text>              Blocks whose name, title or description match`;

const CATEGORIES: readonly BlockCategory[] = [
  "foundation",
  "collaboration",
  "crm",
  "work",
  "commerce",
  "scheduling",
  "ai",
  "content",
  "operations",
  "platform",
];

const BLOCKS_ARGS = {
  action: {
    type: "positional",
    required: false,
    description: "list, view or search",
  },
  category: {
    type: "string",
    description:
      "With list: one category (foundation, collaboration, crm, work, commerce, scheduling, ai, content, operations or platform)",
    valueHint: "name",
  },
} as const;

type BlocksOptions = CliOptions<typeof BLOCKS_ARGS>;

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

function list(category: string | undefined): CommandResult {
  if (category !== undefined && !CATEGORIES.some((each) => each === category)) {
    return {
      code: 2,
      error: `Unknown category "${category}". Categories: ${CATEGORIES.join(", ")}`,
    };
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

function view(name: string | undefined): CommandResult {
  if (name === undefined) {
    return { code: 2, error: `Name a block.\n${USAGE}` };
  }
  const entry = ENTRIES.find((each) => each.name === name);
  if (entry === undefined) {
    return {
      code: 2,
      error: `Unknown block "${name}". Run \`better-supabase blocks search ${name}\`.`,
    };
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

function search(text: string | undefined): CommandResult {
  if (text === undefined || text.trim() === "") {
    return { code: 2, error: `Pass the text to search for.\n${USAGE}` };
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

export function runBlocks(args: BlocksOptions): CommandResult {
  const [action, ...rest] = args._ ?? [];
  switch (action) {
    case "list": {
      return list(args.category);
    }
    case "view": {
      return view(rest[0]);
    }
    case "search": {
      return search(rest.join(" "));
    }
    case undefined: {
      return { code: 2, error: `Name an action.\n${USAGE}` };
    }
    default: {
      return { code: 2, error: `Unknown blocks action "${action}".\n${USAGE}` };
    }
  }
}

export const blocksCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "blocks",
    description: "Lists, shows and searches the blocks you can add",
  },
  args: BLOCKS_ARGS,
  run: (args) => Promise.resolve(runBlocks(args)),
});
