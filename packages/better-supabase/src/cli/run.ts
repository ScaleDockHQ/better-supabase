import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";

import { flagBool, flagString, type ParsedArgs, parseArgs } from "./args.ts";
import { DOCTOR_HELP, runDoctor } from "./commands/doctor.ts";
import { ENV_HELP, runEnv } from "./commands/env.ts";
import { runGen } from "./commands/gen.ts";
import { ADD_HELP, INIT_HELP, runAdd, runInit } from "./commands/init.ts";
import { KEYS_HELP, runKeys } from "./commands/keys.ts";
import { OPENAPI_HELP, runOpenApi } from "./commands/openapi.ts";
import { runSeed, SEED_HELP } from "./commands/seed.ts";
import { runSkills, SKILLS_HELP } from "./commands/skills.ts";
import {
  loadSnapshot,
  serializeSnapshot,
  type SnapshotSource,
} from "./commands/snapshot.ts";
import { runSql, SQL_HELP } from "./commands/sql.ts";
import { loadConfig } from "./config.ts";
import { restrictSchemas, serializeGenerator } from "./introspect/typegen.ts";
import {
  type CliIo,
  type CommandResult,
  display,
  type RunResult,
  writeIfChanged,
} from "./io.ts";
import { VERSION } from "./version.ts";

export const HELP: string = `better-supabase ${VERSION}

Usage: better-supabase <command> [options]

Setup
  init [--casing camel|snake] [--with <integration...>]
  add <next|hono|orpc|edge|mcp|client|react...>
  env [--out .env.local]            local stack URL and keys from \`supabase status\`
  keys [--rotate]                   ES256 signing key for the local stack
  skills list | install [--agent cursor,claude,agents]

Codegen
  gen [--check] [--watch] [--snapshot <file>] [--db-url <url> | --project-ref <ref>]
  introspect [--out supabase/snapshot.json] [--format snapshot|generator-metadata]
  openapi emit [--check]
  seed [--check] [--apply]

Checks
  doctor [--format text|json|sarif|github] [--strict] [--only BS100,...]

SQL kit
  sql list | add <module...> | sync [--check] | print <module>

Run \`better-supabase <command> --help\` for a command's options.

Global
  --cwd <dir>   --config <file>   --help   --version
`;

export type Command = (context: CommandContext) => Promise<CommandResult>;

export interface CommandContext {
  readonly args: ParsedArgs;
  readonly cwd: string;
  readonly config: ResolvedConfig;
  readonly io: CliIo;
  readonly env: Readonly<Record<string, string | undefined>>;
  readonly signal: AbortSignal | undefined;
}

const COMMANDS = new Map<string, Command>();
const COMMAND_HELP = new Map<string, string>();

/** Registers a command; the built-in commands register themselves below. */
export function registerCommand(
  name: string,
  command: Command,
  help?: string,
): void {
  COMMANDS.set(name, command);
  if (help) COMMAND_HELP.set(name, help);
}

function sourceFlags(args: ParsedArgs): SnapshotSource {
  const snapshotPath = flagString(args.flags, "snapshot");
  const dbUrl = flagString(args.flags, "db-url");
  const projectRef = flagString(args.flags, "project-ref");
  return {
    ...(snapshotPath ? { snapshotPath } : {}),
    ...(dbUrl ? { dbUrl } : {}),
    ...(projectRef ? { projectRef } : {}),
  };
}

registerCommand("gen", async ({ args, config, env, io, signal }) => {
  const options = {
    config,
    env,
    check: flagBool(args.flags, "check"),
    ...sourceFlags(args),
  } as const;

  if (!flagBool(args.flags, "watch")) return runGen(options);

  const interval = Number(flagString(args.flags, "interval") ?? 2000);
  let last = "";
  const aborted = (): boolean => signal?.aborted ?? false;
  while (!aborted()) {
    try {
      const snapshot = await loadSnapshot(config, env, options);
      const fingerprint = JSON.stringify(snapshot);
      if (fingerprint !== last) {
        last = fingerprint;
        const result = await runGen({ ...options, snapshot });
        if (result.output) io.stdout(`${result.output}\n`);
        if (result.error) io.stderr(`${result.error}\n`);
      }
    } catch (cause) {
      io.stderr(`${cause instanceof Error ? cause.message : String(cause)}\n`);
    }
    await sleep(interval, signal);
  }
  return { code: 0 };
});

registerCommand("introspect", async ({ args, config, env }) => {
  const format = flagString(args.flags, "format") ?? "snapshot";
  if (format !== "snapshot" && format !== "generator-metadata") {
    return {
      code: 2,
      error: '--format must be "snapshot" or "generator-metadata"',
    };
  }
  const { snapshotPath: _ignored, ...source } = sourceFlags(args);
  const snapshot = await loadSnapshot(config, env, { ...source, live: true });
  const out =
    flagString(args.flags, "out") ??
    (format === "snapshot"
      ? "supabase/snapshot.json"
      : "supabase/generator-metadata.json");
  const contents =
    format === "snapshot"
      ? serializeSnapshot(snapshot)
      : `${serializeGenerator(restrictSchemas(snapshot.generator, config.schemas))}\n`;
  if (flagBool(args.flags, "check")) {
    const current = await readFile(resolve(config.root, out), "utf8").catch(
      () => undefined,
    );
    return current === contents
      ? { code: 0, output: `${display(config.root, out)} is up to date.` }
      : {
          code: 1,
          error: `${display(config.root, out)} is out of date. Run \`better-supabase introspect\`.`,
        };
  }
  const wrote = await writeIfChanged(resolve(config.root, out), contents);
  return {
    code: 0,
    output: `${wrote ? "Wrote" : "Unchanged"} ${display(config.root, out)} (${snapshot.extras.tables.length} tables).`,
  };
});

registerCommand("sql", ({ args, config }) => runSql(config, args), SQL_HELP);
registerCommand("init", ({ args, config }) => runInit(config, args), INIT_HELP);
registerCommand("add", ({ args, config }) => runAdd(config, args), ADD_HELP);
registerCommand(
  "env",
  ({ args, config, env }) => runEnv(config, args, env),
  ENV_HELP,
);
registerCommand("keys", ({ args, config }) => runKeys(config, args), KEYS_HELP);
registerCommand(
  "seed",
  ({ args, config, env }) => runSeed(config, args, env),
  SEED_HELP,
);
registerCommand(
  "openapi",
  ({ args, config }) => runOpenApi(config, args),
  OPENAPI_HELP,
);
registerCommand(
  "skills",
  ({ args, config, env }) => runSkills(config, args, env),
  SKILLS_HELP,
);
registerCommand(
  "doctor",
  ({ args, config, env }) => runDoctor(config, args, env),
  DOCTOR_HELP,
);

function sleep(ms: number, signal: AbortSignal | undefined): Promise<void> {
  return new Promise((done) => {
    const timer = setTimeout(done, ms);
    signal?.addEventListener("abort", () => {
      clearTimeout(timer);
      done();
    });
  });
}

export interface RunOptions {
  readonly cwd?: string;
  readonly io?: CliIo;
  readonly signal?: AbortSignal;
}

/** Runs the CLI. Never exits the process; returns the exit code and output. */
export async function run(
  argv: readonly string[],
  options: RunOptions = {},
): Promise<RunResult> {
  const stdout: string[] = [];
  const stderr: string[] = [];
  const io: CliIo = options.io ?? {
    stdout: (text) => stdout.push(text),
    stderr: (text) => stderr.push(text),
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
  const finish = (code: number): RunResult => ({
    code,
    stdout: stdout.join(""),
    stderr: stderr.join(""),
  });

  const args = parseArgs(argv);
  if (flagBool(args.flags, "version") || args.command === "version") {
    out(VERSION);
    return finish(0);
  }
  const commandHelp = args.command ? COMMAND_HELP.get(args.command) : undefined;
  if (commandHelp && flagBool(args.flags, "help")) {
    out(commandHelp);
    return finish(0);
  }
  if (
    flagBool(args.flags, "help") ||
    args.command === "help" ||
    args.command === undefined
  ) {
    (args.command === undefined && !flagBool(args.flags, "help") ? fail : out)(
      HELP,
    );
    return finish(
      args.command === undefined && !flagBool(args.flags, "help") ? 2 : 0,
    );
  }

  const command = COMMANDS.get(args.command);
  if (!command) {
    fail(`Unknown command "${args.command}".\n\n${HELP}`);
    return finish(2);
  }

  const cwd = resolve(
    options.cwd ?? process.cwd(),
    flagString(args.flags, "cwd") ?? ".",
  );
  const env = io.env ?? process.env;
  let config: ResolvedConfig;
  try {
    config = await loadConfig(cwd, flagString(args.flags, "config"));
  } catch (cause) {
    fail(cause instanceof Error ? cause.message : String(cause));
    return finish(2);
  }

  try {
    const result = await command({
      args,
      cwd,
      config,
      io,
      env,
      signal: options.signal,
    });
    if (result.output) out(result.output);
    if (result.error) fail(result.error);
    return finish(result.code);
  } catch (cause) {
    fail(cause instanceof Error ? cause.message : String(cause));
    return finish(1);
  }
}
