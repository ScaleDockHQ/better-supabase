import { type CommandDef, defineCommand } from "citty";

import type { ResolvedConfig } from "../config/index.ts";
import type { CommandResult, CliIo } from "./io.ts";

import { cliContext } from "./command.ts";

type FlagValue = string | boolean | readonly string[];

/** The arguments of a `(context) => CommandResult` command, parsed the 0.2 way. */
export interface ParsedArgs {
  readonly command: string | undefined;
  readonly rest: readonly string[];
  readonly flags: Readonly<Record<string, FlagValue>>;
}

const ARRAY_FLAGS = new Set([
  "schema",
  "only",
  "ignore",
  "agent",
  "block",
  "with",
  "explain",
]);
const BOOLEAN_FLAGS = new Set([
  "check",
  "watch",
  "json",
  "strict",
  "help",
  "version",
  "force",
  "dry-run",
  "no-color",
  "yes",
  "local",
  "rotate",
  "apply",
  "print",
  "global",
  "stats",
  "fix-grants",
]);

function parseArgs(argv: readonly string[]): ParsedArgs {
  const flags: Record<string, FlagValue> = {};
  const positionals: string[] = [];
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === undefined) continue;
    if (token === "--") {
      positionals.push(...argv.slice(index + 1));
      break;
    }
    if (token === "-h") {
      flags["help"] = true;
      continue;
    }
    if (token.startsWith("--")) {
      const body = token.slice(2);
      const eq = body.indexOf("=");
      if (eq !== -1) {
        setFlag(flags, body.slice(0, eq), body.slice(eq + 1));
        continue;
      }
      const next = argv[index + 1];
      if (
        !BOOLEAN_FLAGS.has(body) &&
        next !== undefined &&
        !next.startsWith("-")
      ) {
        setFlag(flags, body, next);
        index += 1;
        continue;
      }
      flags[body] = true;
      continue;
    }
    positionals.push(token);
  }
  return { command: positionals[0], rest: positionals.slice(1), flags };
}

function setFlag(
  flags: Record<string, FlagValue>,
  name: string,
  value: string,
): void {
  if (ARRAY_FLAGS.has(name)) {
    const current = flags[name];
    const pieces = value
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
    flags[name] =
      typeof current === "object" ? [...current, ...pieces] : pieces;
    return;
  }
  flags[name] = value;
}

/** What a `(context) => CommandResult` command receives. */
export interface CommandContext {
  readonly args: ParsedArgs;
  readonly cwd: string;
  readonly config: ResolvedConfig;
  readonly io: CliIo;
  readonly env: Readonly<Record<string, string | undefined>>;
  readonly signal: AbortSignal | undefined;
}

/** The command shape before 0.3; `registerCommand` still accepts it, deprecated. */
export type Command = (context: CommandContext) => Promise<CommandResult>;

/**
 * Wraps a `(context) => CommandResult` command as a citty command. Its flags
 * are parsed the way 0.2 parsed them, because it declares no citty args.
 */
export function legacyCommand(
  name: string,
  command: Command,
  help?: string,
): CommandDef {
  return defineCommand({
    meta: { name, description: help ?? "" },
    run: ({ rawArgs, data }) => {
      const parsed = parseArgs([name, ...rawArgs]);
      const context = cliContext(data);
      return command({ ...context, env: { ...context.env }, args: parsed });
    },
  });
}
