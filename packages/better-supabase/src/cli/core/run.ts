import { parseArgs, runCommand } from "citty";
import { subscribe, unsubscribe } from "node:diagnostics_channel";
import { statSync } from "node:fs";
import { resolve } from "node:path";
import { stripVTControlCharacters } from "node:util";

import type { ResolvedConfig } from "../../config/index.ts";
import type { ConsentRequest } from "./agent.ts";
import type { CliIo, CommandResult, RunResult } from "./io.ts";
import type { CommandSpec } from "./manifest.ts";

import { builtinCommands } from "../builtin-commands.ts";
import { painter } from "../style.ts";
import { VERSION } from "../version.ts";
import { checkConsent, missingInputNext, resolveAgent } from "./agent.ts";
import {
  type AnyCommand,
  type CliCommand,
  type CliContext,
  GLOBAL_ARGS,
  joinRepeated,
  listArgs,
  runsWithInvalidConfig,
} from "./command.ts";
import { CliError, type CliErrorCode, toCliError } from "./errors.ts";
import { commandHelp, rootHelp, treeJson } from "./help.ts";
import { createLog, milliseconds } from "./log.ts";
import { COMPLETE_COMMAND, RESERVED_NAMES } from "./manifest.ts";
import { movedCommand, movedFlag } from "./moved.ts";
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
  globalFlags,
  type Loader,
  resolveCommand,
} from "./parse.ts";
import {
  EXEC_CHANNEL,
  type ExecEvent,
  HTTP_CHANNEL,
  type HttpEvent,
} from "./trace.ts";

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

export interface CommandTreeInit {
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
  /** The top-level names `run()` dispatches, your own commands included. */
  commandNames(): string[];
}

export interface CreateCliOptions {
  /** Commands from `defineCliCommand` to add next to the built-in ones, keyed by name. */
  readonly commands?: Readonly<Record<string, CliCommand>>;
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

const SHOWS_USAGE = new Set<CliErrorCode>([
  "usage",
  "unknown_command",
  "unknown_flag",
  "invalid_value",
]);

/** The stack of `cause` and of each error in its `cause` chain, for `--debug`. */
function stackText(cause: unknown): string {
  const stacks: string[] = [];
  let current = cause;

  while (current instanceof Error && stacks.length < 10) {
    stacks.push(current.stack ?? `${current.name}: ${current.message}`);
    current = current.cause;
  }

  return stacks.length === 0 ? String(cause) : stacks.join("\nCaused by: ");
}

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
    throw new CliError("invalid_value", `--cwd ${flag} is not a directory.`, {
      flag: "--cwd",
    });
  }

  return directory;
}

/** `--force` on a run that writes: not under `--dry-run` or `--check`. */
function forcesOverwrite(rest: readonly string[]): boolean {
  const end = rest.indexOf("--");
  const options = new Set(end === -1 ? rest : rest.slice(0, end));

  return (
    (options.has("--force") || options.has("--force=true")) &&
    !options.has("--dry-run") &&
    !options.has("--check")
  );
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

/** The tree node for one of the app's own commands, after checking its contract and name. */
function extraCommand(
  tree: ReadonlyMap<string, CommandNode>,
  name: string,
  command: CliCommand,
): CommandNode {
  const version: unknown = command.apiVersion;

  if (version !== 1) {
    throw new CliError(
      "usage",
      `Command "${name}" has no CLI command API version; define it with defineCliCommand.`,
    );
  }

  if (tree.has(name) || RESERVED_NAMES.includes(name)) {
    throw new CliError(
      "usage",
      `Command "${name}" is taken by a better-supabase command; pick another name.`,
    );
  }

  return {
    spec: { name, description: metaDescription(command) },
    path: [name],
    load: () => Promise.resolve(command),
    children: new Map(),
  };
}

/** A CLI over its own command tree, so tests and embedders don't share state through the module. */
export function cliFromTree(
  init: CommandTreeInit,
  extra: Readonly<Record<string, CliCommand>> = {},
): Cli {
  const tree = commandTree(init.commands, init.loaders);

  for (const [name, command] of Object.entries(extra)) {
    tree.set(name, extraCommand(tree, name, command));
  }

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

    if (argv[0] === COMPLETE_COMMAND) {
      const words = argv[1] === "--" ? argv.slice(2) : argv.slice(1);

      // Loaded on demand: only the shell's Tab key runs it. A failed load or
      // lookup offers nothing rather than printing an error into the prompt.
      const lines = await import("./completion.ts")
        .then(async ({ complete, completionLines }) =>
          completionLines(await complete(tree, words)),
        )
        .catch(() => "");

      if (lines !== "") {
        out(lines);
      }

      return { code: 0, stdout: stdout.join(""), stderr: stderr.join("") };
    }

    const flags = globalFlags(argv);
    const { debug, color } = flags;
    let agent: string | undefined;
    let agentError: unknown;

    try {
      agent = resolveAgent(flags.agent, options.env ?? {}, {
        stdoutIsTty: io.stdoutIsTty === true,
        exists: io.exists ?? (() => false),
      });
    } catch (cause) {
      agentError = cause;
    }

    // Agent mode prints JSON unless --no-json; help and --version follow only --json.
    const json = flags.json || (agent !== undefined && !flags.noJson);
    const paint = painter(io.color === true && color);

    const errorPaint = painter((io.stderrColor ?? io.color) === true && color);

    const log = createLog({
      write: fail,
      paint: errorPaint,
      debug,
      ...(io.spinner ? { spinner: io.spinner } : {}),
    });

    const started = performance.now();

    const usage = (path: readonly string[] = []): Promise<string> =>
      helpText(path, bin, io.color === true && color);

    const finish = (code: number): RunResult => {
      log.debug(
        `exit ${code} after ${milliseconds(started, performance.now())}`,
      );

      return {
        code,
        stdout: stdout.join(""),
        stderr: stderr.join(""),
      };
    };

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
    const { help: wantsHelp } = globalFlags(resolution.rest);

    const report = (rendered: Rendered): void => {
      if (rendered.raw !== undefined) {
        if (options.io) {
          stdout.push(rendered.raw);
        }

        io.stdout(rendered.raw);
      }

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
      const thrown = toCliError(cause);

      const {
        type: _type,
        title: _title,
        detail: _detail,
        code: _code,
        ...extensions
      } = thrown.problem;

      const error =
        thrown.code === "input_required" &&
        thrown.next.length === 0 &&
        extensions.missing
          ? new CliError(thrown.code, thrown.message, {
              ...extensions,
              cause: thrown,
              next: [
                missingInputNext(argv, extensions.missing, extensions.choices),
              ],
            })
          : thrown;

      if (debug) {
        log.debug(stackText(cause));
      }

      const shown =
        error.code === "usage"
          ? new CliError("usage", stripVTControlCharacters(error.message), {
              ...(error.problem.flag ? { flag: error.problem.flag } : {}),
              ...(error.problem.suggestion
                ? { suggestion: error.problem.suggestion }
                : {}),
              ...(error.problem.choices
                ? { choices: error.problem.choices }
                : {}),
            })
          : error;

      report(
        renderError(shown, {
          json,
          paint,
          errorPaint,
          ...(SHOWS_USAGE.has(error.code)
            ? { usage: await usage(usagePath) }
            : {}),
        }),
      );

      return finish(error.exitCode);
    };

    const printHelp = async (node?: CommandNode): Promise<RunResult> => {
      if (flags.json) {
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
          flags.json
            ? document(envelope(0, { data: { version: VERSION } }))
            : VERSION,
        );

        return finish(0);
      }

      const moved = movedCommand(argv, bin);

      if (moved) {
        return reportError(moved, parent);
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
          flags.json
            ? document(envelope(0, { data: { version: VERSION } }))
            : VERSION,
        );

        return finish(0);
      }

      if (wantsHelp) {
        return printHelp();
      }

      if (agentError !== undefined) {
        return reportError(agentError);
      }

      if (json) {
        return reportError(
          new CliError("usage", "Name a command.", {
            choices: { "<command>": [...tree.keys()] },
          }),
        );
      }

      fail(await usage());

      return finish(2);
    }

    const { node, rest } = resolution;

    if (wantsHelp) {
      return printHelp(node);
    }

    if (!node.load) {
      const names = [...node.children.keys()];

      return reportError(
        new CliError(
          "usage",
          `Name a ${node.path.join(" ")} subcommand: ${names.join(", ")}.`,
          { choices: { "<command>": names } },
        ),
      );
    }

    const movedOption = movedFlag(node.path, rest, bin);

    if (movedOption) {
      return reportError(movedOption);
    }

    if (agentError !== undefined) {
      return reportError(agentError);
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
        !json && globals.yes !== true && !isCi(env) && agent === undefined;

      const requireConsent = (request: ConsentRequest): void => {
        if (agent !== undefined) {
          checkConsent(argv, request, globals.confirm);
        }
      };

      context = {
        cwd,
        config,
        ...(configFile ? { configFile } : {}),
        reloadConfig,
        io: interactive ? io : withoutPrompts(io),
        env,
        json,
        signal: options.signal,
        log,
        paint,
        emit: (result) => {
          report(
            renderResult(result, { json, paint, errorPaint, compact: true }),
          );
        },
        agent,
        requireConsent,
      };

      if (forcesOverwrite(rest)) {
        requireConsent({
          effect: "overwrite",
          detail: `${node.path.join(" ")} --force overwrites files better-supabase did not write`,
        });
      }
    } catch (cause) {
      return reportError(cause);
    }

    const traceExec = (message: unknown): void => {
      // SAFETY: exec.ts publishes only ExecEvent objects on EXEC_CHANNEL.
      const event = message as ExecEvent;
      log.debug(
        `exec ${[event.command, ...event.args].join(" ")} (in ${event.cwd}): exit ${event.code} after ${event.milliseconds}ms`,
      );
    };

    const traceHttp = (message: unknown): void => {
      // SAFETY: http.ts publishes only HttpEvent objects on HTTP_CHANNEL.
      const event = message as HttpEvent;
      log.debug(
        `http ${event.method} ${event.url}: ${event.status ?? "no response"} after ${event.milliseconds}ms`,
      );
    };

    if (debug) {
      subscribe(EXEC_CHANNEL, traceExec);
      subscribe(HTTP_CHANNEL, traceHttp);
    }

    try {
      const { result } = await runCommand(command, {
        rawArgs,
        data: context,
      });

      if (!isCommandResult(result)) {
        return finish(0);
      }

      report(renderResult(result, { json, paint, errorPaint }));

      return finish(result.code);
    } catch (cause) {
      return await reportError(cause);
    } finally {
      if (debug) {
        unsubscribe(EXEC_CHANNEL, traceExec);
        unsubscribe(HTTP_CHANNEL, traceHttp);
      }
    }
  };

  return {
    run,
    help,
    commandNames: () => [...tree.keys()],
  };
}

/**
 * A CLI with every built-in command plus `options.commands`. Each one has to
 * come from `defineCliCommand` (`apiVersion: 1`) and take a free name.
 */
export function createCli(options: CreateCliOptions = {}): Cli {
  return cliFromTree(builtinCommands(), options.commands);
}

/** The CLI the `better-supabase` bin runs, with every built-in command. */
const defaultCli: Cli = cliFromTree(builtinCommands());

export const run: Cli["run"] = (argv, options) => defaultCli.run(argv, options);

export const help: Cli["help"] = (command, color) =>
  defaultCli.help(command, color);

/** The names `run()` dispatches. */
export const commandNames: Cli["commandNames"] = () =>
  defaultCli.commandNames();
