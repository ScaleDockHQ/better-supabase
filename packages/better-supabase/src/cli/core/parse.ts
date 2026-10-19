import type { ArgDef, ArgsDef, CommandDef } from "citty";

import type { AnyCommand } from "./command.ts";
import type { CommandSpec } from "./manifest.ts";

import { GLOBAL_ARGS } from "./command.ts";
import { CliError } from "./errors.ts";

export type Loader = () => Promise<AnyCommand>;

/** One command in the tree `run()` dispatches: a leaf with a loader, a parent with subcommands, or both. */
export interface CommandNode {
  readonly spec: CommandSpec;
  readonly path: readonly string[];
  readonly load?: Loader;
  readonly children: Map<string, CommandNode>;
}

/** Global options that take a value, so a command name is never the token after them. */
const GLOBAL_VALUE_FLAGS: ReadonlySet<string> = new Set(
  Object.entries(GLOBAL_ARGS).flatMap(([name, definition]) =>
    definition.type === "string" ? [`--${name}`] : [],
  ),
);

/** The tree of `specs`, with each leaf's loader from `loaders` (keyed by its space-separated path). */
export function commandTree(
  specs: readonly CommandSpec[],
  loaders: ReadonlyMap<string, Loader>,
  parent: readonly string[] = [],
): Map<string, CommandNode> {
  return new Map(
    specs.map((spec) => {
      const path = [...parent, spec.name];
      const load = loaders.get(path.join(" "));

      return [
        spec.name,
        {
          spec,
          path,
          ...(load ? { load } : {}),
          children: commandTree(spec.subcommands ?? [], loaders, path),
        },
      ];
    }),
  );
}

/** The index of the next token that is not an option or a global option's value, from `start`. */
export function positionalIndex(argv: readonly string[], start = 0): number {
  for (let index = start; index < argv.length; index += 1) {
    const token = argv[index]!;

    if (token === "--") {
      return -1;
    }

    if (!token.startsWith("-") || token === "-") {
      return index;
    }

    if (GLOBAL_VALUE_FLAGS.has(token)) {
      index += 1;
    }
  }

  return -1;
}

export type Resolution =
  | { readonly kind: "root"; readonly rest: readonly string[] }
  | {
      readonly kind: "command";
      readonly node: CommandNode;
      /** `argv` without the command names. */
      readonly rest: readonly string[];
    }
  | {
      readonly kind: "unknown";
      /** The known part of the path, empty at the top level. */
      readonly parent: readonly string[];
      readonly name: string;
      readonly candidates: readonly string[];
      readonly rest: readonly string[];
    };

/** Walks `argv` down the tree to the deepest command it names. */
export function resolveCommand(
  tree: ReadonlyMap<string, CommandNode>,
  argv: readonly string[],
): Resolution {
  let rest = [...argv];
  let index = positionalIndex(rest);

  if (index === -1) {
    return { kind: "root", rest };
  }

  let level = tree;
  let node: CommandNode | undefined;

  while (index !== -1) {
    const name = rest[index]!;
    const next = level.get(name);

    if (!next) {
      if (node?.load) {
        break;
      }

      return {
        kind: "unknown",
        parent: node?.path ?? [],
        name,
        candidates: [...level.keys()],
        rest: rest.toSpliced(index, 1),
      };
    }

    node = next;
    rest = rest.toSpliced(index, 1);

    if (node.children.size === 0) {
      break;
    }

    level = node.children;
    index = positionalIndex(rest, index);
  }

  // SAFETY: the loop runs at least once, and every pass either sets `node` or returns.
  return { kind: "command", node: node!, rest };
}

/** The flags `run()` reads before it loads a command, before `--`. */
export function globalFlags(argv: readonly string[]): {
  readonly help: boolean;
  readonly json: boolean;
  readonly color: boolean;
  readonly debug: boolean;
} {
  const end = argv.indexOf("--");
  const flags = new Set(end === -1 ? argv : argv.slice(0, end));

  return {
    help: flags.has("--help") || flags.has("-h"),
    json: flags.has("--json"),
    color: !flags.has("--no-color") && !flags.has("--color=false"),
    debug: flags.has("--debug"),
  };
}

/** A command's static `args`, or none. */
export async function commandArgs(command: AnyCommand): Promise<ArgsDef> {
  // SAFETY: citty types a loaded command's args as any; defineCommand only
  // accepts an ArgsDef or a function that resolves to one.
  const declared = command.args as CommandDef["args"];
  const args = typeof declared === "function" ? declared() : declared;

  return (await args) ?? {};
}

/** A positional that takes the rest of the arguments (`add <block...>`). */
export function isVariadic(definition: ArgDef): boolean {
  return (
    definition.type === "positional" &&
    "variadic" in definition &&
    definition.variadic === true
  );
}

const kebab = (name: string): string =>
  name.replaceAll(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);

/** The registered name closest to a mistyped one, if it is close enough to be a typo. */
export async function closestName(
  name: string,
  names: readonly string[],
): Promise<string | undefined> {
  if (names.length === 0) {
    return undefined;
  }

  // Loaded only to suggest a fix for a typo, so a correct run never pays for it.
  const { closest, distance } = await import("fastest-levenshtein");
  const candidate = closest(name, [...names]);

  return distance(name, candidate) <= Math.max(2, Math.floor(name.length / 3))
    ? candidate
    : undefined;
}

/**
 * Rejects what citty would ignore: unknown options, values outside an enum,
 * and positionals the command doesn't declare.
 */
export async function checkArgs(
  args: ArgsDef,
  argv: readonly string[],
  usage: string,
): Promise<void> {
  const definitions: ArgsDef = { ...args, ...GLOBAL_ARGS };
  const long = new Map<string, readonly [string, ArgDef]>();
  const short = new Map<string, readonly [string, ArgDef]>();
  const positionals: ArgDef[] = [];

  for (const [name, definition] of Object.entries(definitions)) {
    if (definition.type === "positional") {
      positionals.push(definition);
      continue;
    }

    long.set(kebab(name), [name, definition]);

    const aliases = "alias" in definition ? [definition.alias].flat() : [];

    for (const alias of aliases) {
      (alias.length === 1 ? short : long).set(alias, [name, definition]);
    }
  }

  const takesValue = (definition: ArgDef): boolean =>
    definition.type === "string" || definition.type === "enum";

  const unknownOption = async (option: string): Promise<never> => {
    const suggestion = await closestName(option, [...long.keys()]);

    throw new CliError(
      "usage",
      `Unknown option --${option} for ${usage}.${suggestion ? ` Did you mean --${suggestion}?` : ""}`,
      {
        flag: `--${option}`,
        ...(suggestion ? { suggestion: `--${suggestion}` } : {}),
      },
    );
  };

  const checkValue = (
    name: string,
    definition: ArgDef,
    value: string | undefined,
  ): void => {
    if (
      definition.type !== "enum" ||
      value === undefined ||
      !definition.options ||
      definition.options.includes(value)
    ) {
      return;
    }

    throw new CliError(
      "usage",
      `--${name} takes ${definition.options.join(", ")}, not "${value}".`,
      { flag: `--${name}` },
    );
  };

  let count = 0;

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index]!;

    if (token === "--") {
      break;
    }

    if (token.startsWith("--")) {
      const [raw = "", inline] = token.slice(2).split(/[=](.*)/s, 2);
      const option = kebab(raw);

      const found =
        long.get(option) ??
        (option.startsWith("no-") ? long.get(option.slice(3)) : undefined);

      if (!found || (found !== long.get(option) && takesValue(found[1]))) {
        await unknownOption(option);
      }

      const [name, definition] = found!;

      if (takesValue(definition) && inline === undefined) {
        const value = argv[index + 1];

        if (value !== undefined && (value === "-" || !value.startsWith("-"))) {
          checkValue(name, definition, value);
          index += 1;
        }
      } else {
        checkValue(name, definition, inline);
      }

      continue;
    }

    if (token.startsWith("-") && token !== "-") {
      for (const letter of token.slice(1)) {
        const found = short.get(letter);

        if (!found) {
          throw new CliError(
            "usage",
            `Unknown option -${letter} for ${usage}.`,
            { flag: `-${letter}` },
          );
        }

        if (takesValue(found[1])) {
          index += 1;
          break;
        }
      }

      continue;
    }

    count += 1;

    const last = positionals.at(-1);

    if (count > positionals.length && !(last && isVariadic(last))) {
      const takes =
        positionals.length === 0
          ? "takes no arguments"
          : `takes ${positionals.length} argument${positionals.length === 1 ? "" : "s"}`;

      throw new CliError(
        "usage",
        `${usage} ${takes}, and got "${token}".${token === "help" ? ` Run ${usage} --help.` : ""}`,
        token === "help" ? { suggestion: `${usage} --help` } : {},
      );
    }
  }
}
