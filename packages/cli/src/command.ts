import type { ResolvedConfig } from "better-supabase/config";

import {
  type ArgsDef,
  type CommandDef,
  type CommandMeta,
  defineCommand,
  type ParsedArgs,
  parseArgs,
  type SubCommandsDef,
} from "citty";

import type { CliIo, CommandResult } from "./io.ts";

/** What `run()` hands every command next to its parsed arguments. */
export interface CliContext {
  readonly cwd: string;
  readonly config: ResolvedConfig;
  readonly io: CliIo;
  readonly env: Readonly<Record<string, string | undefined>>;
  readonly signal: AbortSignal | undefined;
}

/** Options every command accepts; `run()` reads them before the command starts. */
export const GLOBAL_ARGS = {
  cwd: {
    type: "string",
    description: "Project directory",
    valueHint: "dir",
  },
  config: {
    type: "string",
    description: "Config file, relative to --cwd",
    valueHint: "file",
  },
} as const;

export type CliArgs<T extends ArgsDef> = ParsedArgs<T & typeof GLOBAL_ARGS>;

export interface CliCommandDef<T extends ArgsDef> {
  readonly meta: CommandMeta & { readonly name: string };
  readonly args: T;
  /** String options that take a list: comma-separated, repeated, or both. */
  readonly lists?: readonly (keyof T & string)[];
  readonly run: (
    args: CliArgs<T>,
    context: CliContext,
  ) => Promise<CommandResult>;
}

/** Any citty command, whatever its arguments. */
export type AnyCommand = Exclude<
  SubCommandsDef[string],
  Promise<unknown> | (() => unknown)
>;

const LISTS = new WeakMap<object, readonly string[]>();

/** A citty command that receives the `CliContext` and returns a `CommandResult`. */
export function defineCliCommand<const T extends ArgsDef>(
  def: CliCommandDef<T>,
): AnyCommand {
  const command = defineCommand<T & typeof GLOBAL_ARGS>({
    meta: def.meta,
    args: { ...def.args, ...GLOBAL_ARGS },
    run: ({ args, data }) => def.run(args, cliContext(data)),
  });
  LISTS.set(command, def.lists ?? []);
  return command;
}

/** The list options a command declared through `defineCliCommand`. */
export function listArgs<T extends ArgsDef>(
  command: CommandDef<T>,
): readonly string[] {
  return LISTS.get(command) ?? [];
}

/** Splits a comma-separated option into its trimmed, non-empty parts. */
export function list(value: string | undefined): string[] {
  return (value ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

/**
 * Joins repeated list options (`--only a --only b`) into one comma-separated
 * value, because citty keeps only the last occurrence.
 */
export function joinRepeated(
  argv: readonly string[],
  names: readonly string[],
): string[] {
  if (names.length === 0) return [...argv];
  const lists = new Set(names);
  const values = new Map<string, string[]>();
  const rest: string[] = [];
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index]!;
    if (token === "--") {
      rest.push(...argv.slice(index));
      break;
    }
    const match = /^--([^=]+)(?:=(.*))?$/.exec(token);
    const name = match?.[1];
    if (name === undefined || !lists.has(name)) {
      rest.push(token);
      continue;
    }
    let value = match?.[2];
    if (value === undefined) {
      const next = argv[index + 1];
      if (next === undefined || next.startsWith("-")) continue;
      value = next;
      index += 1;
    }
    values.set(name, [...(values.get(name) ?? []), value]);
  }
  return [
    ...[...values].map(([name, parts]) => `--${name}=${parts.join(",")}`),
    ...rest,
  ];
}

/** Parses `argv` the way `run()` does, for tests and programmatic callers. */
export function parseCommandArgs<T extends ArgsDef>(
  command: CommandDef<T>,
  argv: readonly string[],
): ParsedArgs<T> {
  const args = command.args;
  if (typeof args !== "object" || args instanceof Promise)
    throw new TypeError("parseCommandArgs needs a command with static args");
  return parseArgs<T>(joinRepeated(argv, listArgs(command)), args);
}

function isCliContext(value: unknown): value is CliContext {
  return (
    typeof value === "object" &&
    value !== null &&
    "config" in value &&
    "io" in value &&
    "env" in value
  );
}

export function cliContext(data: unknown): CliContext {
  if (!isCliContext(data))
    throw new TypeError(
      "better-supabase commands run through run() from @better-supabase/cli",
    );
  return data;
}
