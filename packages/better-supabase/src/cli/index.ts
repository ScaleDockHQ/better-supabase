export { commandNames, createCli, help, run } from "./core/run.ts";

export type { Cli, CreateCliOptions, RunOptions } from "./core/run.ts";

export { defineCliCommand, list } from "./core/command.ts";

export type {
  CliArgs,
  CliCommand,
  CliCommandDef,
  CliContext,
} from "./core/command.ts";

export type { CliIo, CommandResult, NextStep, RunResult } from "./core/io.ts";

export type { CliLog } from "./core/log.ts";

export type { Choice, Prompter } from "./prompts.ts";

export type { Format, Paint } from "./style.ts";

export { CLI_ERRORS_URL, CliError } from "./core/errors.ts";

export type {
  CliErrorCode,
  CliErrorOptions,
  CliProblem,
  CliProblemExtensions,
  ExitCode,
} from "./core/errors.ts";

export type { CliEnv } from "./env.ts";

export { renderFiles } from "./gen/render.ts";

export { emitBlockConfig } from "./gen/blocks.ts";

export { runGen } from "./gen/run.ts";

export {
  loadSnapshot,
  parseSnapshot,
  serializeSnapshot,
} from "./commands/snapshot.ts";

export {
  introspect,
  managementSource,
  pgSource,
  toCatalog,
} from "./introspect/index.ts";

export type {
  IntrospectionSource,
  ManagementSourceOptions,
  Queryable,
} from "./introspect/index.ts";

export { fromCatalog } from "./introspect/from-catalog.ts";

export type * from "./introspect/types.ts";

export { buildModel } from "./gen/model.ts";

export { emitModule, GENERATED_HEADER } from "./gen/emit.ts";

export { loadConfig } from "./config.ts";

export { VERSION } from "./version.ts";
