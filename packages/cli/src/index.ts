// oxlint-disable-next-line typescript/no-deprecated -- only registerCommand's legacy overload is deprecated.
export { help, run, registerCommand } from "./run.ts";
export type { RunOptions } from "./run.ts";
export { defineCliCommand, list } from "./command.ts";
export type { CliArgs, CliCommandDef, CliContext } from "./command.ts";
export type { Command, CommandContext, ParsedArgs } from "./legacy.ts";
export type { CliIo, CommandResult, RunResult } from "./io.ts";
export { renderFiles, runGen } from "./commands/gen.ts";
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
