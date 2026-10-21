import type {
  ArgsDef,
  CommandDef,
  CommandMeta,
  ParsedArgs,
  SubCommandsDef,
} from "citty";

import { defineCommand, parseArgs } from "citty";

import type { ResolvedConfig } from "../../config/index.ts";
import type { CliEnv } from "../env.ts";
import type { Paint } from "../style.ts";
import type { ConsentRequest } from "./agent.ts";
import type { CliIo, CommandResult } from "./io.ts";
import type { CliLog } from "./log.ts";

import { CliError } from "./errors.ts";

/** What `run()` hands every command next to its parsed arguments. */
export interface CliContext {
  readonly cwd: string;
  readonly config: ResolvedConfig;
  /** The config file `config` came from, when there is one. */
  readonly configFile?: string;
  /** Loads the config file again, for commands that run until stopped. */
  readonly reloadConfig?: () => Promise<ResolvedConfig>;
  /** `prompts` is unset in CI, in agent mode and under `--json` or `--yes`. */
  readonly io: CliIo;
  readonly env: CliEnv;
  /** `--json`: return `data`, which `run()` prints as the one JSON document. */
  readonly json: boolean;
  readonly signal: AbortSignal | undefined;
  /** Messages and progress on stderr. */
  readonly log: CliLog;
  /**
   * Colors text for stdout, or leaves it plain under `--no-color` and in a
   * pipe.
   */
  readonly paint: Paint;
  /**
   * Prints one result now, for a command that runs until stopped: the text
   * output, or under `--json` one envelope on its own line (NDJSON).
   */
  readonly emit: (result: CommandResult) => void;
  /** The coding agent running the CLI, in agent mode; `undefined` for a person. */
  readonly agent: string | undefined;
  /**
   * In agent mode, throws `consent_required` until the run passes `--confirm`
   * with this request's token; does nothing for a person.
   */
  readonly requireConsent: (request: ConsentRequest) => void;
}

/** Options every command accepts; `run()` reads them before the command starts. */
export const GLOBAL_ARGS = {
  cwd: { type: "string", description: "Project directory", valueHint: "dir" },
  config: {
    type: "string",
    description: "Config file, relative to --cwd",
    valueHint: "file",
  },
  env: {
    type: "string",
    description:
      "Config environment to apply ($env.<name> or $<name>). Defaults to $BETTER_SUPABASE_ENV, then ci when $CI is set",
    valueHint: "name",
  },
  json: {
    type: "boolean",
    description:
      "Print one JSON document on stdout; errors as Problem Details. On by default in agent mode",
    negativeDescription: "Print text, also in agent mode",
  },
  agent: {
    type: "string",
    description:
      "Agent mode (JSON output, no prompts, consent for destructive work): auto detects a coding agent, yes or no decide. Defaults to $BETTER_SUPABASE_AGENT, then auto",
    valueHint: "auto|yes|no",
  },
  confirm: {
    type: "string",
    description:
      "The token from a consent_required result, passed once the user agreed",
    valueHint: "token",
  },
  yes: {
    type: "boolean",
    alias: "y",
    description: "Ask nothing; use the flags and the defaults",
  },
  color: {
    type: "boolean",
    default: true,
    description: "Color the output on a terminal",
    negativeDescription: "Print no colors, like $NO_COLOR",
  },
  debug: {
    type: "boolean",
    description:
      "Print stack traces, the commands the CLI runs, and timings on stderr",
  },
} as const;

export type CliArgs<T extends ArgsDef> = ParsedArgs<T & typeof GLOBAL_ARGS>;

/**
 * What a runner reads from a command's flags: any subset of them, so another
 * command's runner can call it without parsing argv.
 */
export type CliOptions<T extends ArgsDef> = {
  readonly [K in keyof T | keyof typeof GLOBAL_ARGS]?: CliArgs<T>[K];
} & { readonly _?: readonly string[] };

/**
 * The values a shell offers for one argument, for names it can't know from the
 * arg definition.
 */
export type CompletionValues = () => readonly string[];

export interface CliCommandDef<T extends ArgsDef> {
  /**
   * The command contract; a breaking change to `CliContext` or `CommandResult`
   * ships a new one.
   */
  readonly apiVersion?: 1;
  readonly meta: CommandMeta & { readonly name: string };
  readonly args: T;
  /** String options that take a list: comma-separated, repeated, or both. */
  readonly lists?: readonly (keyof T & string)[];
  /** Values `completion` offers per argument: block, preset or task names. */
  readonly completions?: {
    readonly [K in keyof T & string]?: CompletionValues;
  };
  readonly runsWithInvalidConfig?: boolean;
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

/** A command from `defineCliCommand`, which `createCli` accepts. */
export type CliCommand = AnyCommand & { readonly apiVersion: 1 };

const LISTS = new WeakMap<object, readonly string[]>();

const COMPLETIONS = new WeakMap<
  object,
  Readonly<Partial<Record<string, CompletionValues>>>
>();

const RUNS_WITH_INVALID_CONFIG = new WeakSet<object>();

/** A citty command that receives the `CliContext` and returns a `CommandResult`. */
export function defineCliCommand<const T extends ArgsDef>(
  def: CliCommandDef<T>,
): CliCommand {
  const version: unknown = def.apiVersion ?? 1;

  if (version !== 1) {
    throw new CliError(
      "usage",
      `Command "${def.meta.name}" targets CLI command API v${String(version)}; this version supports v1.`,
    );
  }

  const command = defineCommand<T & typeof GLOBAL_ARGS>({
    meta: def.meta,
    args: { ...def.args, ...GLOBAL_ARGS },
    run: ({ args, data }) => def.run(args, cliContext(data)),
  });

  LISTS.set(command, def.lists ?? []);
  COMPLETIONS.set(command, def.completions ?? {});

  if (def.runsWithInvalidConfig === true) {
    RUNS_WITH_INVALID_CONFIG.add(command);
  }

  return Object.assign(command, { apiVersion: 1 as const });
}

/** The list options a command declared through `defineCliCommand`. */
export function listArgs<T extends ArgsDef>(
  command: CommandDef<T>,
): readonly string[] {
  return LISTS.get(command) ?? [];
}

/**
 * The completion values a command declared through `defineCliCommand`, by
 * argument.
 */
export function completionValues<T extends ArgsDef>(
  command: CommandDef<T>,
): Readonly<Partial<Record<string, CompletionValues>>> {
  return COMPLETIONS.get(command) ?? {};
}

export function runsWithInvalidConfig<T extends ArgsDef>(
  command: CommandDef<T>,
): boolean {
  return RUNS_WITH_INVALID_CONFIG.has(command);
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
  if (names.length === 0) {
    return [...argv];
  }

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

      if (next === undefined || next.startsWith("-")) {
        continue;
      }

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

  if (typeof args !== "object" || args instanceof Promise) {
    throw new TypeError("parseCommandArgs needs a command with static args");
  }

  return parseArgs<T>(joinRepeated(argv, listArgs(command)), args);
}

function isCliContext(value: unknown): value is CliContext {
  return (
    typeof value === "object" &&
    value !== null &&
    "config" in value &&
    "io" in value &&
    "env" in value &&
    "json" in value
  );
}

export function cliContext(data: unknown): CliContext {
  if (!isCliContext(data)) {
    throw new TypeError(
      "better-supabase commands run through run() from better-supabase/cli",
    );
  }

  return data;
}
