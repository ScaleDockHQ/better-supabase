import type { ArgDef, ArgsDef } from "citty";

import type { Paint } from "../style.ts";
import type { CommandNode } from "./parse.ts";

import { GLOBAL_ARGS, listArgs } from "./command.ts";
import {
  type CommandEffect,
  type CommandExample,
  type CommandGroup,
  DOCS_ORIGIN,
  GROUPS,
} from "./manifest.ts";
import { commandArgs, isVariadic } from "./parse.ts";

const COMMANDS_SCHEMA_URL =
  "https://unpkg.com/better-supabase/schemas/cli-commands-v1.json";

export interface HelpOptions {
  /** The name the CLI was called with. */
  readonly bin: string;
  readonly version: string;
  readonly description: string;
  readonly paint: Paint;
}

/** Help-only flags `run()` answers itself, listed with the global options. */
const HELP_ARGS: ArgsDef = {
  help: { type: "boolean", alias: "h", description: "Show help" },
};

const ROOT_ARGS: ArgsDef = {
  version: { type: "boolean", description: "Print the version" },
};

/** Two columns, the first padded to its widest cell, with no trailing spaces. */
function table(rows: readonly (readonly [string, string])[]): string[] {
  const width = Math.max(0, ...rows.map(([left]) => left.length));

  return rows.map(([left, right]) =>
    `  ${left.padEnd(width)}  ${right}`.trimEnd(),
  );
}

function section(
  title: string,
  lines: readonly string[],
  paint: Paint,
): string[] {
  return lines.length === 0 ? [] : ["", paint("bold", title), ...lines];
}

const docsUrl = (path: string): string => `${DOCS_ORIGIN}${path}`;

/** A list option's hint ends in `,...`, unless the command already wrote it. */
const listHint = (hint: string, list: boolean): string =>
  list && !hint.endsWith("...") ? `${hint},...` : hint;

function optionName(name: string, definition: ArgDef, list: boolean): string {
  const aliases =
    "alias" in definition
      ? [definition.alias]
          .flat()
          .map((alias) => (alias.length === 1 ? `-${alias}` : `--${alias}`))
      : [];

  const hint =
    definition.type === "enum" && definition.options
      ? `<${definition.options.join("|")}>`
      : definition.type === "string"
        ? `<${listHint(definition.valueHint ?? name, list)}>`
        : "";

  const flag = negated(definition) ? `no-${name}` : name;

  return [...aliases, `--${flag}${hint ? ` ${hint}` : ""}`].join(", ");
}

/** A boolean that is on by default, so the flag a person types is `--no-<name>`. */
const negated = (definition: ArgDef): boolean =>
  definition.type === "boolean" && definition.default === true;

function optionDescription(definition: ArgDef): string {
  const fallback =
    definition.default === undefined ||
    definition.default === false ||
    negated(definition)
      ? ""
      : ` (default: ${String(definition.default)})`;

  const description =
    negated(definition) && "negativeDescription" in definition
      ? definition.negativeDescription
      : definition.description;

  return `${description ?? ""}${fallback}`;
}

function optionRows(
  args: ArgsDef,
  lists: ReadonlySet<string>,
): (readonly [string, string])[] {
  return Object.entries(args).flatMap(([name, definition]) =>
    definition.type === "positional"
      ? []
      : [
          [
            optionName(name, definition, lists.has(name)),
            optionDescription(definition),
          ] as const,
        ],
  );
}

/** citty requires a positional unless it is `required: false` or has a default. */
const isRequired = (definition: ArgDef): boolean =>
  definition.required !== false && definition.default === undefined;

function positionalName(name: string, definition: ArgDef): string {
  const label = `${name}${isVariadic(definition) ? "..." : ""}`;

  return isRequired(definition) ? `<${label}>` : `[${label}]`;
}

function ownArgs(args: ArgsDef): ArgsDef {
  return Object.fromEntries(
    Object.entries(args).filter(([name]) => !(name in GLOBAL_ARGS)),
  );
}

function effectText(effect: CommandEffect): string {
  const base = ((): string => {
    switch (effect.kind) {
      case "files": {
        return "writes files";
      }

      case "database": {
        return effect.access === "read"
          ? "reads the database"
          : "writes to the database";
      }

      case "network": {
        switch (effect.target) {
          case "supabase-api": {
            return "calls the Supabase Management API";
          }

          case "github": {
            return "downloads from GitHub";
          }

          default: {
            const never: never = effect.target;

            return never;
          }
        }
      }

      default: {
        const never: never = effect;

        return never;
      }
    }
  })();

  return effect.when ? `${base} with ${effect.when}` : base;
}

/** The Side effects line: "Writes files, reads the database." */
function effectsLine(effects: readonly CommandEffect[]): string {
  if (effects.length === 0) {
    return "None.";
  }

  const text = effects.map(effectText).join(", ");

  return `${text.charAt(0).toUpperCase()}${text.slice(1)}.`;
}

function exampleLines(
  examples: readonly CommandExample[] | undefined,
  options: HelpOptions,
): string[] {
  return (examples ?? []).flatMap((example) => [
    `  ${options.paint("dim", `# ${example.description}`)}`,
    `  $ ${example.command.replace(/^better-supabase\b/, options.bin)}`,
  ]);
}

const GLOBAL_ROWS = (): (readonly [string, string])[] =>
  optionRows({ ...GLOBAL_ARGS, ...HELP_ARGS }, new Set());

/** The root usage: the commands by group, then the global options. */
export function rootHelp(
  tree: ReadonlyMap<string, CommandNode>,
  options: HelpOptions,
): string {
  const { bin, paint } = options;
  const nodes = [...tree.values()];

  const groups: (readonly [CommandGroup | undefined, string])[] = [
    ...GROUPS,
    [undefined, "Other commands"],
  ];

  const lines = [
    `${paint("bold", bin)} ${paint("dim", `v${options.version}`)}`,
    options.description,
    "",
    `${paint("bold", "Usage:")} ${bin} <command> [options]`,
    ...groups.flatMap(([group, title]) =>
      section(
        title,
        table(
          nodes
            .filter((node) => node.spec.group === group)
            .map((node) => [node.spec.name, node.spec.description] as const),
        ),
        paint,
      ),
    ),
    ...section(
      "Global options",
      table([...GLOBAL_ROWS(), ...optionRows(ROOT_ARGS, new Set())]),
      paint,
    ),
    "",
    `Run ${bin} <command> --help for a command's options.`,
    `Docs: ${docsUrl("/docs/cli")}`,
  ];

  return `${lines.join("\n")}\n`;
}

/** One command's usage: its arguments, options, the global options, examples and the docs link. */
export async function commandHelp(
  node: CommandNode,
  options: HelpOptions,
): Promise<string> {
  const { bin, paint } = options;
  const name = [bin, ...node.path].join(" ");
  const command = node.load ? await node.load() : undefined;
  const args = command ? ownArgs(await commandArgs(command)) : {};
  const lists = new Set(command ? listArgs(command) : []);

  const positionals = Object.entries(args).filter(
    ([, definition]) => definition.type === "positional",
  );

  const subcommands = [...node.children.values()];

  const usage = [
    name,
    ...(subcommands.length > 0 ? [command ? "[command]" : "<command>"] : []),
    "[options]",
    ...positionals.map(([arg, definition]) => positionalName(arg, definition)),
  ].join(" ");

  const lines: string[] = [
    `${paint("bold", "Usage:")} ${usage}`,
    "",
    node.spec.description,
    ...section(
      "Commands",
      table(
        subcommands.map((child) => [child.spec.name, child.spec.description]),
      ),
      paint,
    ),
    ...section(
      "Arguments",
      table(
        positionals.map(([arg, definition]) => [
          positionalName(arg, definition),
          definition.description ?? "",
        ]),
      ),
      paint,
    ),
    ...section("Options", table(optionRows(args, lists)), paint),
    ...section("Global options", table(GLOBAL_ROWS()), paint),
    ...section("Examples", exampleLines(node.spec.examples, options), paint),
  ];

  const footer = [
    ...(command && node.spec.effects
      ? [`Side effects: ${effectsLine(node.spec.effects)}`]
      : []),
    ...(node.spec.docs ? [`Docs: ${docsUrl(node.spec.docs)}`] : []),
  ];

  if (footer.length > 0) {
    lines.push("", ...footer);
  }

  return `${lines.join("\n")}\n`;
}

interface OptionJson {
  readonly name: string;
  readonly aliases?: readonly string[];
  readonly type: "boolean" | "string" | "enum";
  readonly description?: string;
  readonly valueHint?: string;
  readonly default?: string | boolean;
  readonly choices?: readonly string[];
  readonly list?: true;
}

interface ArgumentJson {
  readonly name: string;
  readonly description?: string;
  readonly required: boolean;
  readonly variadic: boolean;
}

interface CommandJson {
  readonly name: string;
  readonly path: string;
  readonly description: string;
  readonly group?: CommandGroup;
  readonly docs?: string;
  readonly examples?: readonly CommandExample[];
  readonly effects?: readonly CommandEffect[];
  readonly arguments: readonly ArgumentJson[];
  readonly options: readonly OptionJson[];
  readonly commands?: readonly CommandJson[];
}

export interface CommandsJson {
  readonly $schema: string;
  readonly name: string;
  readonly version: string;
  readonly options: readonly OptionJson[];
  readonly commands: readonly CommandJson[];
}

function optionJson(
  name: string,
  definition: ArgDef,
  list: boolean,
): OptionJson | undefined {
  if (definition.type === "positional") {
    return undefined;
  }

  const aliases = "alias" in definition ? [definition.alias].flat() : [];

  return {
    name,
    ...(aliases.length > 0 ? { aliases } : {}),
    type: definition.type ?? "boolean",
    ...(definition.description ? { description: definition.description } : {}),
    ...(definition.valueHint ? { valueHint: definition.valueHint } : {}),
    ...(definition.default === undefined
      ? {}
      : { default: definition.default }),
    ...(definition.type === "enum" && definition.options
      ? { choices: definition.options }
      : {}),
    ...(list ? { list: true as const } : {}),
  };
}

function optionsJson(args: ArgsDef, lists: ReadonlySet<string>): OptionJson[] {
  return Object.entries(args).flatMap(([name, definition]) => {
    const option = optionJson(name, definition, lists.has(name));

    return option ? [option] : [];
  });
}

/** One command and its subcommands as `cli-commands-v1.json` describes them. Loads every leaf. */
async function commandJson(node: CommandNode): Promise<CommandJson> {
  const command = node.load ? await node.load() : undefined;
  const args = command ? ownArgs(await commandArgs(command)) : {};
  const lists = new Set(command ? listArgs(command) : []);

  const children = await Promise.all(
    [...node.children.values()].map(commandJson),
  );

  return {
    name: node.spec.name,
    path: node.path.join(" "),
    description: node.spec.description,
    ...(node.spec.group ? { group: node.spec.group } : {}),
    ...(node.spec.docs ? { docs: docsUrl(node.spec.docs) } : {}),
    ...(node.spec.examples ? { examples: node.spec.examples } : {}),
    ...(node.spec.effects ? { effects: node.spec.effects } : {}),
    arguments: Object.entries(args).flatMap(([name, definition]) =>
      definition.type === "positional"
        ? [
            {
              name,
              ...(definition.description
                ? { description: definition.description }
                : {}),
              required: isRequired(definition),
              variadic: isVariadic(definition),
            },
          ]
        : [],
    ),
    options: optionsJson(args, lists),
    ...(children.length > 0 ? { commands: children } : {}),
  };
}

/** The whole command tree for `--help --json`. */
export async function treeJson(
  tree: ReadonlyMap<string, CommandNode>,
  version: string,
): Promise<CommandsJson> {
  return {
    $schema: COMMANDS_SCHEMA_URL,
    name: "better-supabase",
    version,
    options: optionsJson(
      { ...GLOBAL_ARGS, ...HELP_ARGS, ...ROOT_ARGS },
      new Set(),
    ),
    commands: await Promise.all([...tree.values()].map(commandJson)),
  };
}
