import {
  type CommandDef,
  defineCommand,
  parseArgs,
  renderUsage,
  runCommand,
} from "citty";
import { closest, distance } from "fastest-levenshtein";
import { resolve } from "node:path";
import { stripVTControlCharacters } from "node:util";

import {
  type AnyCommand,
  type CliContext,
  GLOBAL_ARGS,
  joinRepeated,
  listArgs,
} from "./command.ts";
import { loadConfig } from "./config.ts";
import { parseEnv } from "./env.ts";
import { CliError, type CliErrorCode, toCliError } from "./errors.ts";
import { type CliIo, type CommandResult, type RunResult } from "./io.ts";
import { type Command, legacyCommand } from "./legacy.ts";
import { type Rendered, renderError, renderResult } from "./output.ts";
import { painter } from "./style.ts";
import { VERSION } from "./version.ts";

type Loader = () => Promise<AnyCommand>;

const COMMANDS = new Map<string, Loader>([
  ["init", () => import("./commands/init.ts").then((m) => m.initCommand)],
  ["add", () => import("./commands/init.ts").then((m) => m.addCommand)],
  ["env", () => import("./commands/env.ts").then((m) => m.envCommand)],
  ["keys", () => import("./commands/keys.ts").then((m) => m.keysCommand)],
  ["skills", () => import("./commands/skills.ts").then((m) => m.skillsCommand)],
  ["gen", () => import("./commands/gen.ts").then((m) => m.genCommand)],
  [
    "introspect",
    () => import("./commands/introspect.ts").then((m) => m.introspectCommand),
  ],
  [
    "openapi",
    () => import("./commands/openapi.ts").then((m) => m.openapiCommand),
  ],
  ["seed", () => import("./commands/seed.ts").then((m) => m.seedCommand)],
  ["doctor", () => import("./commands/doctor.ts").then((m) => m.doctorCommand)],
  ["sql", () => import("./commands/sql.ts").then((m) => m.sqlCommand)],
]);

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
  const def =
    typeof command === "function"
      ? legacyCommand(name, command, help)
      : command;
  COMMANDS.set(name, () => Promise.resolve(def));
}

const ROOT = defineCommand({
  meta: {
    name: "better-supabase",
    version: VERSION,
    description:
      "Typed Supabase: codegen, doctor, the SQL kit and project setup",
  },
  args: GLOBAL_ARGS,
  subCommands: () =>
    Object.fromEntries([...COMMANDS].map(([name, load]) => [name, load])),
});

/** The usage text for the CLI, or for one command; plain unless `color` is set. */
export async function help(command?: string, color = false): Promise<string> {
  const load = command === undefined ? undefined : COMMANDS.get(command);
  const text = load
    ? await renderUsage(await load(), ROOT)
    : await renderUsage(ROOT);
  return color ? text : stripVTControlCharacters(text);
}

export interface RunOptions {
  /** Directory `--cwd` is relative to. */
  readonly cwd?: string;
  /** Environment variables. Empty unless passed; the bin passes `process.env`. */
  readonly env?: Readonly<Record<string, string | undefined>>;
  readonly io?: CliIo;
  readonly signal?: AbortSignal;
}

/** The index of the command name: the first token that is not an option or an option's value. */
function commandIndex(argv: readonly string[]): number {
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index]!;
    if (token === "--") return -1;
    if (!token.startsWith("-")) return index;
    if (token === "--cwd" || token === "--config") index += 1;
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

/** The names `run()` dispatches, registered commands included. */
export function commandNames(): string[] {
  return [...COMMANDS.keys()];
}

/** The registered command closest to a mistyped one, if it is close enough to be a typo. */
function suggestCommand(name: string): string | undefined {
  const names = [...COMMANDS.keys()];
  if (names.length === 0) return undefined;
  const candidate = closest(name, names);
  return distance(name, candidate) <= Math.max(2, Math.floor(name.length / 3))
    ? candidate
    : undefined;
}

const SHOWS_USAGE = new Set<CliErrorCode>(["usage", "unknown_command"]);

function withoutPrompts(io: CliIo): CliIo {
  const { prompts: _prompts, ...rest } = io;
  return rest;
}

/** Runs the CLI. Never exits the process; returns the exit code and output. */
export async function run(
  argv: readonly string[],
  options: RunOptions = {},
): Promise<RunResult> {
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
    if (options.io) stdout.push(line);
    io.stdout(line);
  };
  const fail = (text: string): void => {
    const line = text.endsWith("\n") ? text : `${text}\n`;
    if (options.io) stderr.push(line);
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
    if (rendered.stdout) out(rendered.stdout);
    if (rendered.stderr) fail(rendered.stderr);
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
  const load = COMMANDS.get(name);
  if (!load) {
    const suggestion = suggestCommand(name);
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
    command = await load();
    const globals = parseArgs<typeof GLOBAL_ARGS>(rest, GLOBAL_ARGS);
    const cwd = resolve(options.cwd ?? ".", globals.cwd ?? ".");
    const env = parseEnv(options.env ?? {});
    const config = await loadConfig(cwd, globals.config).catch(
      (cause: unknown) => {
        throw cause instanceof CliError
          ? cause
          : new CliError("config_invalid", toCliError(cause).message, {
              cause,
            });
      },
    );
    const interactive =
      globals.json !== true && globals.yes !== true && env.CI === undefined;
    context = {
      cwd,
      config,
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
    if (!isCommandResult(result)) return finish(0);
    report(renderResult(result, { json, paint }));
    return finish(result.code);
  } catch (cause) {
    return reportError(cause);
  }
}
