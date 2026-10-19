import { parseArgs, runCommand } from "citty";
import { statSync } from "node:fs";
import { resolve } from "node:path";
import { stripVTControlCharacters } from "node:util";

import type { ResolvedConfig } from "../../config/index.ts";
import type { CliIo, CommandResult, RunResult } from "./io.ts";
import type { CommandSpec } from "./manifest.ts";

import { builtinCommands } from "../builtin-commands.ts";
import { type Command, legacyCommand } from "../legacy.ts";
import { painter } from "../style.ts";
import { VERSION } from "../version.ts";
import {
  type AnyCommand,
  type CliContext,
  GLOBAL_ARGS,
  joinRepeated,
  listArgs,
  runsWithInvalidConfig,
} from "./command.ts";
import { CliError, type CliErrorCode, toCliError } from "./errors.ts";
import { commandHelp, rootHelp, treeJson } from "./help.ts";
import {
  document,
  envelope,
  type Rendered,
  renderError,
  renderResult,
} from "./output.ts";
import {
  checkArgs,
  closestName,
  commandArgs,
  type CommandNode,
  commandTree,
  helpFlags,
  type Loader,
  resolveCommand,
} from "./parse.ts";

export interface RunOptions {
  /** Directory `--cwd` is relative to. */
  readonly cwd?: string;
  /** Environment variables. Empty unless passed; the bin passes `process.env`. */
  readonly env?: Readonly<Record<string, string | undefined>>;
  readonly io?: CliIo;
  readonly signal?: AbortSignal;
  /** The name the CLI was called with, for help and hints. Defaults to `better-supabase`. */
  readonly bin?: string;
}

export interface CreateCliOptions {
  /** The command tree: names, descriptions, groups and subcommands. */
  readonly commands: readonly CommandSpec[];
  /** Loads each leaf in `commands`, keyed by its space-separated path (`"sql add"`). */
  readonly loaders: ReadonlyMap<string, Loader>;
}

export interface Cli {
  /** Runs the CLI. Never exits the process; returns the exit code and output. */
  run(argv: readonly string[], options?: RunOptions): Promise<RunResult>;
  /** The usage text for the CLI, or for one command path (`"sql add"`); plain unless `color` is set. */
  help(command?: string, color?: boolean): Promise<string>;
  /** The top-level names `run()` dispatches, registered commands included. */
  commandNames(): string[];
  /** Adds a command that is already loaded. */
  register(name: string, command: AnyCommand): void;
}

const ROOT_DESCRIPTION =
  "Typed Supabase: codegen, doctor, the SQL modules and project setup";

const DEFAULT_BIN = "better-supabase";

function isCommandResult(value: unknown): value is CommandResult {
  return (
    typeof value === "object" &&
    value !== null &&
    "code" in value &&
    typeof value.code === "number"
  );
}

const SHOWS_USAGE = new Set<CliErrorCode>(["usage", "unknown_command"]);

/** `--cwd` resolved against `base`; it has to name an existing directory. */
function projectDirectory(base: string, flag: string | undefined): string {
  if (flag === undefined) {
    return resolve(base);
  }

  if (flag.trim() === "") {
    throw new CliError("missing_value", "--cwd needs a directory.", {
      flag: "--cwd",
    });
  }

  const directory = resolve(base, flag);

  if (!statSync(directory, { throwIfNoEntry: false })?.isDirectory()) {
    throw new CliError("usage", `--cwd ${flag} is not a directory.`, {
      flag: "--cwd",
    });
  }

  return directory;
}

function withoutPrompts(io: CliIo): CliIo {
  const { prompts: _prompts, ...rest } = io;

  return rest;
}

function metaDescription(command: AnyCommand): string {
  const { meta } = command;

  return typeof meta === "object" && !(meta instanceof Promise)
    ? (meta.description ?? "")
    : "";
}

/** A CLI over its own command tree, so tests and embedders don't share state through the module. */
export function createCli(init: CreateCliOptions): Cli {
  const tree = commandTree(init.commands, init.loaders);

  const helpText = async (
    path: readonly string[],
    bin: string,
    color: boolean,
  ): Promise<string> => {
    const paint = painter(color);

    const options = {
      bin,
      version: VERSION,
      description: ROOT_DESCRIPTION,
      paint,
    };

    const resolution = resolveCommand(tree, path);

    return resolution.kind === "command"
      ? commandHelp(resolution.node, options)
      : rootHelp(tree, options);
  };

  const help = async (command?: string, color = false): Promise<string> => {
    const text = await helpText(
      command === undefined ? [] : command.split(" "),
      DEFAULT_BIN,
      color,
    );

    return color ? text : stripVTControlCharacters(text);
  };

  const run = async (
    argv: readonly string[],
    options: RunOptions = {},
  ): Promise<RunResult> => {
    const stdout: string[] = [];
    const stderr: string[] = [];
    const bin = options.bin ?? DEFAULT_BIN;

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

    const usage = (path: readonly string[] = []): Promise<string> =>
      helpText(path, bin, io.color === true);

    const finish = (code: number): RunResult => ({
      code,
      stdout: stdout.join(""),
      stderr: stderr.join(""),
    });

    let resolution = resolveCommand(tree, argv);

    if (
      resolution.kind === "unknown" &&
      resolution.parent.length === 0 &&
      resolution.name === "help"
    ) {
      const topic = resolveCommand(tree, resolution.rest);

      resolution =
        topic.kind === "command"
          ? { ...topic, rest: [...topic.rest, "--help"] }
          : topic.kind === "root"
            ? { kind: "root", rest: ["--help"] }
            : topic;
    }

    const path = resolution.kind === "command" ? resolution.node.path : [];
    const flags = helpFlags(resolution.rest);
    const { json } = flags;

    const report = (rendered: Rendered): void => {
      if (rendered.stdout) {
        out(rendered.stdout);
      }

      if (rendered.stderr) {
        fail(rendered.stderr);
      }
    };

    const reportError = async (
      cause: unknown,
      usagePath: readonly string[] = path,
    ): Promise<RunResult> => {
      const error = toCliError(cause);

      const shown =
        error.code === "usage"
          ? new CliError("usage", stripVTControlCharacters(error.message), {
              ...(error.problem.flag ? { flag: error.problem.flag } : {}),
              ...(error.problem.suggestion
                ? { suggestion: error.problem.suggestion }
                : {}),
            })
          : error;

      report(
        renderError(shown, {
          json,
          paint,
          ...(SHOWS_USAGE.has(error.code)
            ? { usage: await usage(usagePath) }
            : {}),
        }),
      );

      return finish(error.exitCode);
    };

    const printHelp = async (node?: CommandNode): Promise<RunResult> => {
      if (json) {
        const document = await treeJson(
          node ? new Map([[node.spec.name, node]]) : tree,
          VERSION,
        );

        out(JSON.stringify(document, null, 2));
      } else {
        out(await usage(node?.path));
      }

      return finish(0);
    };

    if (resolution.kind === "unknown") {
      const { parent, name, candidates } = resolution;

      if (parent.length === 0 && name === "version") {
        out(
          json
            ? document(envelope(0, { data: { version: VERSION } }))
            : VERSION,
        );

        return finish(0);
      }

      const suggestion = await closestName(name, candidates);
      const full = [...parent, name].join(" ");
      const suggested = suggestion ? [...parent, suggestion].join(" ") : "";

      return reportError(
        new CliError(
          "unknown_command",
          `Unknown command "${full}".${suggestion ? ` Did you mean "${suggested}"?` : ""}`,
          suggestion ? { suggestion: suggested } : {},
        ),
        parent,
      );
    }

    if (resolution.kind === "root") {
      const end = resolution.rest.indexOf("--");

      const before =
        end === -1 ? resolution.rest : resolution.rest.slice(0, end);

      if (before.includes("--version")) {
        out(
          json
            ? document(envelope(0, { data: { version: VERSION } }))
            : VERSION,
        );

        return finish(0);
      }

      if (flags.help) {
        return printHelp();
      }

      fail(await usage());

      return finish(2);
    }

    const { node, rest } = resolution;

    if (flags.help) {
      return printHelp(node);
    }

    if (!node.load) {
      fail(await usage(node.path));

      return finish(2);
    }

    let context: CliContext;
    let command: AnyCommand;
    let rawArgs: string[];

    try {
      // Config loading (c12) and env validation (valibot) stay out of `--version` and `--help`.
      const [
        loaded,
        { defaultConfig, discoverConfig, loadConfig },
        { configEnvironment, isCi, parseEnv },
      ] = await Promise.all([
        node.load(),
        import("../config.ts"),
        import("../env.ts"),
      ]);

      command = loaded;
      rawArgs = joinRepeated(rest, listArgs(command));

      // A command without declared args parses its own argv.
      if (command.args !== undefined) {
        await checkArgs(
          await commandArgs(command),
          rawArgs,
          [bin, ...node.path].join(" "),
        );
      }

      const globals = parseArgs<typeof GLOBAL_ARGS>([...rest], GLOBAL_ARGS);
      const cwd = projectDirectory(options.cwd ?? ".", globals.cwd);
      const env = parseEnv(options.env ?? {});
      const environment = configEnvironment(globals.env, env);
      const configFile = discoverConfig(cwd, globals.config);

      const loadWith = (path?: string): Promise<ResolvedConfig> =>
        loadConfig(cwd, globals.config, environment, path).catch(
          (cause: unknown) => {
            throw cause instanceof CliError
              ? cause
              : new CliError("config_invalid", toCliError(cause).message, {
                  cause,
                });
          },
        );

      // Reloads discover the file again, so a config created under `--watch` is picked up.
      const reloadConfig = (): Promise<ResolvedConfig> => loadWith();

      const config = await loadWith(configFile).catch((cause: unknown) => {
        if (
          runsWithInvalidConfig(command) &&
          toCliError(cause).code === "config_invalid"
        ) {
          return defaultConfig(cwd, globals.config, environment, configFile);
        }

        throw cause;
      });

      const interactive =
        globals.json !== true && globals.yes !== true && !isCi(env);

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
        rawArgs,
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
    commandNames: () => [...tree.keys()],
    register: (name, command) => {
      tree.set(name, {
        spec: { name, description: metaDescription(command) },
        path: [name],
        load: () => Promise.resolve(command),
        children: new Map(),
      });
    },
  };
}

/** The CLI the `better-supabase` bin runs, with every built-in command. */
const defaultCli: Cli = createCli(builtinCommands());

export const run: Cli["run"] = (argv, options) => defaultCli.run(argv, options);

export const help: Cli["help"] = (command, color) =>
  defaultCli.help(command, color);

/** The names `run()` dispatches, registered commands included. */
export const commandNames: Cli["commandNames"] = () =>
  defaultCli.commandNames();

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
