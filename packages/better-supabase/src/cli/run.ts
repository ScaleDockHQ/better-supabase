import {
  type CommandDef,
  defineCommand,
  parseArgs,
  renderUsage,
  runCommand,
} from "citty";
import { resolve } from "node:path";
import { stripVTControlCharacters } from "node:util";

import type { ResolvedConfig } from "../config/index.ts";
import type { CliEntry } from "./builtin-commands.ts";
import type { CliIo, CommandResult, RunResult } from "./io.ts";

import { builtinCommands } from "./builtin-commands.ts";
import {
  type AnyCommand,
  type CliContext,
  GLOBAL_ARGS,
  joinRepeated,
  listArgs,
} from "./command.ts";
import { CliError, type CliErrorCode, toCliError } from "./errors.ts";
import { type Command, legacyCommand } from "./legacy.ts";
import { type Rendered, renderError, renderResult } from "./output.ts";
import { painter } from "./style.ts";
import { VERSION } from "./version.ts";

export interface RunOptions {
  /** Directory `--cwd` is relative to. */
  readonly cwd?: string;
  /** Environment variables. Empty unless passed; the bin passes `process.env`. */
  readonly env?: Readonly<Record<string, string | undefined>>;
  readonly io?: CliIo;
  readonly signal?: AbortSignal;
}

export interface CreateCliOptions {
  /** The commands the CLI dispatches, by name. `createCli` copies the map. */
  readonly commands: ReadonlyMap<string, CliEntry>;
}

export interface Cli {
  /** Runs the CLI. Never exits the process; returns the exit code and output. */
  run(argv: readonly string[], options?: RunOptions): Promise<RunResult>;
  /** The usage text for the CLI, or for one command; plain unless `color` is set. */
  help(command?: string, color?: boolean): Promise<string>;
  /** The names `run()` dispatches, registered commands included. */
  commandNames(): string[];
  /** The root usage's description of each lazily loaded command, for checking against the command. */
  commandDescriptions(): ReadonlyMap<string, string>;
  /** Adds a command that is already loaded. */
  register(name: string, command: AnyCommand): void;
}

/** Global options that take a value, so the command name is the token after them. */
const GLOBAL_VALUE_FLAGS: ReadonlySet<string> = new Set(
  Object.entries(GLOBAL_ARGS).flatMap(([name, definition]) =>
    definition.type === "string" ? [`--${name}`] : [],
  ),
);

/** The index of the command name: the first token that is not an option or an option's value. */
function commandIndex(argv: readonly string[]): number {
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index]!;

    if (token === "--") {
      return -1;
    }

    if (!token.startsWith("-")) {
      return index;
    }

    if (GLOBAL_VALUE_FLAGS.has(token)) {
      index += 1;
    }
  }

  return -1;
}

function isCommandResult(value: unknown): value is CommandResult {
  return (
    typeof value === "object" &&
    value !== null &&
    "code" in value &&
    typeof value.code === "number"
  );
}

const SHOWS_USAGE = new Set<CliErrorCode>(["usage", "unknown_command"]);

function withoutPrompts(io: CliIo): CliIo {
  const { prompts: _prompts, ...rest } = io;

  return rest;
}

/** The registered command closest to a mistyped one, if it is close enough to be a typo. */
async function suggestCommand(
  name: string,
  names: readonly string[],
): Promise<string | undefined> {
  if (names.length === 0) {
    return undefined;
  }

  const { closest, distance } = await import("fastest-levenshtein");
  const candidate = closest(name, [...names]);

  return distance(name, candidate) <= Math.max(2, Math.floor(name.length / 3))
    ? candidate
    : undefined;
}

/** A CLI over its own command registry, so tests and embedders don't share state through the module. */
export function createCli(init: CreateCliOptions): Cli {
  const commands = new Map(init.commands);

  const root = defineCommand({
    meta: {
      name: "better-supabase",
      version: VERSION,
      description:
        "Typed Supabase: codegen, doctor, the SQL modules and project setup",
    },
    args: GLOBAL_ARGS,
    subCommands: () =>
      Object.fromEntries(
        [...commands].map(([name, entry]) => [
          name,
          "command" in entry
            ? entry.command
            : defineCommand({
                meta: { name, description: entry.description },
              }),
        ]),
      ),
  });

  const help = async (command?: string, color = false): Promise<string> => {
    const load =
      command === undefined ? undefined : commands.get(command)?.load;

    const text = load
      ? await renderUsage(await load(), root)
      : await renderUsage(root);

    return color ? text : stripVTControlCharacters(text);
  };

  const run = async (
    argv: readonly string[],
    options: RunOptions = {},
  ): Promise<RunResult> => {
    const stdout: string[] = [];
    const stderr: string[] = [];

    const io: CliIo = options.io ?? {
      stdout: (text) => {
        stdout.push(text);
      },
      stderr: (text) => {
        stderr.push(text);
      },
    };

    const out = (text: string): void => {
      const line = text.endsWith("\n") ? text : `${text}\n`;

      if (options.io) {
        stdout.push(line);
      }

      io.stdout(line);
    };

    const fail = (text: string): void => {
      const line = text.endsWith("\n") ? text : `${text}\n`;

      if (options.io) {
        stderr.push(line);
      }

      io.stderr(line);
    };

    const paint = painter(io.color);

    const usage = (command?: string): Promise<string> =>
      help(command, io.color === true);

    const finish = (code: number): RunResult => ({
      code,
      stdout: stdout.join(""),
      stderr: stderr.join(""),
    });

    const index = commandIndex(argv);
    const name = index === -1 ? undefined : argv[index];
    const rest = index === -1 ? [...argv] : argv.toSpliced(index, 1);

    const flags = new Set(
      rest.slice(0, rest.includes("--") ? rest.indexOf("--") : undefined),
    );

    const wantsHelp = flags.has("--help") || flags.has("-h");
    const json = flags.has("--json");

    const report = (rendered: Rendered): void => {
      if (rendered.stdout) {
        out(rendered.stdout);
      }

      if (rendered.stderr) {
        fail(rendered.stderr);
      }
    };

    const reportError = async (cause: unknown): Promise<RunResult> => {
      const error = toCliError(cause);

      const shown =
        error.code === "usage"
          ? new CliError("usage", stripVTControlCharacters(error.message))
          : error;

      report(
        renderError(shown, {
          json,
          paint,
          ...(SHOWS_USAGE.has(error.code)
            ? { usage: await usage(error.code === "usage" ? name : undefined) }
            : {}),
        }),
      );

      return finish(error.exitCode);
    };

    if (flags.has("--version") || name === "version") {
      out(json ? JSON.stringify({ version: VERSION }) : VERSION);

      return finish(0);
    }

    if (name === undefined) {
      (wantsHelp ? out : fail)(await usage());

      return finish(wantsHelp ? 0 : 2);
    }

    if (name === "help") {
      const topic = rest.find((token) => !token.startsWith("-"));
      out(await usage(topic));

      return finish(0);
    }

    const load = commands.get(name)?.load;

    if (!load) {
      const suggestion = await suggestCommand(name, [...commands.keys()]);

      return reportError(
        new CliError(
          "unknown_command",
          `Unknown command "${name}".${suggestion ? ` Did you mean "${suggestion}"?` : ""}`,
          suggestion ? { suggestion } : {},
        ),
      );
    }

    if (wantsHelp) {
      out(await usage(name));

      return finish(0);
    }

    let context: CliContext;
    let command: CommandDef;

    try {
      // Config loading (c12) and env validation (valibot) stay out of `--version` and `--help`.
      const [
        loaded,
        { discoverConfig, loadConfig },
        { configEnvironment, parseEnv },
      ] = await Promise.all([
        load(),
        import("./config.ts"),
        import("./env.ts"),
      ]);

      command = loaded;
      const globals = parseArgs<typeof GLOBAL_ARGS>(rest, GLOBAL_ARGS);
      const cwd = resolve(options.cwd ?? ".", globals.cwd ?? ".");
      const env = parseEnv(options.env ?? {});
      const environment = configEnvironment(globals.env, env);

      const reloadConfig = (): Promise<ResolvedConfig> =>
        loadConfig(cwd, globals.config, environment).catch((cause: unknown) => {
          throw cause instanceof CliError
            ? cause
            : new CliError("config_invalid", toCliError(cause).message, {
                cause,
              });
        });

      const config = await reloadConfig();
      const configFile = discoverConfig(cwd, globals.config);

      const interactive =
        globals.json !== true && globals.yes !== true && env.CI === undefined;

      context = {
        cwd,
        config,
        ...(configFile ? { configFile } : {}),
        reloadConfig,
        io: interactive ? io : withoutPrompts(io),
        env,
        json: globals.json === true,
        signal: options.signal,
      };
    } catch (cause) {
      return reportError(cause);
    }

    try {
      const { result } = await runCommand(command, {
        rawArgs: joinRepeated(rest, listArgs(command)),
        data: context,
      });

      if (!isCommandResult(result)) {
        return finish(0);
      }

      report(renderResult(result, { json, paint }));

      return finish(result.code);
    } catch (cause) {
      return reportError(cause);
    }
  };

  return {
    run,
    help,
    commandNames: () => [...commands.keys()],
    commandDescriptions: () =>
      new Map(
        [...commands].flatMap(([name, entry]) =>
          "description" in entry ? [[name, entry.description] as const] : [],
        ),
      ),
    register: (name, command) => {
      commands.set(name, {
        load: () => Promise.resolve(command),
        command,
      });
    },
  };
}

/** The CLI the `better-supabase` bin runs, with every built-in command. */
const defaultCli: Cli = createCli({ commands: builtinCommands() });

export const run: Cli["run"] = (argv, options) => defaultCli.run(argv, options);

export const help: Cli["help"] = (command, color) =>
  defaultCli.help(command, color);

/** The names `run()` dispatches, registered commands included. */
export const commandNames: Cli["commandNames"] = () =>
  defaultCli.commandNames();

/** The root usage's description of each built-in command, for checking against the command. */
export const commandDescriptions: Cli["commandDescriptions"] = () =>
  defaultCli.commandDescriptions();

/** Registers a citty command; `defineCliCommand` gives it the `CliContext`. */
export function registerCommand(name: string, command: AnyCommand): void;
/** @deprecated Pass a citty `CommandDef` from `defineCliCommand` instead. */
export function registerCommand(
  name: string,
  command: Command,
  help?: string,
): void;
export function registerCommand(
  name: string,
  command: AnyCommand | Command,
  help?: string,
): void {
  defaultCli.register(
    name,
    typeof command === "function"
      ? legacyCommand(name, command, help)
      : command,
  );
}
