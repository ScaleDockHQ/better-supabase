import type { Loader } from "./core/parse.ts";
import type { CommandTreeInit } from "./core/run.ts";

import { COMMANDS } from "./core/manifest.ts";

/**
 * The module behind each built-in command, by its path in the manifest.
 * Each loads on demand, so `--version` and `--help` import no command.
 */
const LOADERS: readonly (readonly [string, Loader])[] = [
  ["init", () => import("./commands/init.ts").then((m) => m.initCommand)],
  ["add", () => import("./commands/add.ts").then((m) => m.addCommand)],
  ["apply", () => import("./commands/apply.ts").then((m) => m.applyCommand)],
  ["adopt", () => import("./commands/adopt.ts").then((m) => m.adoptCommand)],
  [
    "preset decode",
    () => import("./commands/preset.ts").then((m) => m.presetDecodeCommand),
  ],
  [
    "preset info",
    () => import("./commands/preset.ts").then((m) => m.presetInfoCommand),
  ],
  [
    "blocks list",
    () => import("./commands/blocks.ts").then((m) => m.blocksListCommand),
  ],
  [
    "blocks view",
    () => import("./commands/blocks.ts").then((m) => m.blocksViewCommand),
  ],
  [
    "blocks search",
    () => import("./commands/blocks.ts").then((m) => m.blocksSearchCommand),
  ],
  [
    "skills list",
    () => import("./commands/skills.ts").then((m) => m.skillsListCommand),
  ],
  [
    "skills install",
    () => import("./commands/skills.ts").then((m) => m.skillsInstallCommand),
  ],
  [
    "completion",
    () => import("./commands/completion.ts").then((m) => m.completionCommand),
  ],
  ["env", () => import("./commands/env.ts").then((m) => m.envCommand)],
  ["keys", () => import("./commands/keys.ts").then((m) => m.keysCommand)],
  ["gen", () => import("./commands/gen.ts").then((m) => m.genCommand)],
  [
    "introspect",
    () => import("./commands/introspect.ts").then((m) => m.introspectCommand),
  ],
  [
    "spec emit",
    () => import("./commands/spec.ts").then((m) => m.specEmitCommand),
  ],
  [
    "spec validate",
    () => import("./commands/spec.ts").then((m) => m.specValidateCommand),
  ],
  [
    "scaffold api",
    () => import("./commands/scaffold.ts").then((m) => m.scaffoldApiCommand),
  ],
  [
    "scaffold screens",
    () =>
      import("./commands/scaffold.ts").then((m) => m.scaffoldScreensCommand),
  ],
  ["seed", () => import("./commands/seed.ts").then((m) => m.seedCommand)],
  ["doctor", () => import("./commands/doctor.ts").then((m) => m.doctorCommand)],
  ["config", () => import("./commands/config.ts").then((m) => m.configCommand)],
  ["sql list", () => import("./commands/sql.ts").then((m) => m.sqlListCommand)],
  ["sql add", () => import("./commands/sql.ts").then((m) => m.sqlAddCommand)],
  ["sql sync", () => import("./commands/sql.ts").then((m) => m.sqlSyncCommand)],
  [
    "sql upgrade",
    () => import("./commands/sql.ts").then((m) => m.sqlUpgradeCommand),
  ],
  ["sql data", () => import("./commands/sql.ts").then((m) => m.sqlDataCommand)],
  [
    "sql print",
    () => import("./commands/sql.ts").then((m) => m.sqlPrintCommand),
  ],
  [
    "codemod 0.4",
    () => import("./commands/codemod.ts").then((m) => m.codemodCommand("0.4")),
  ],
  [
    "codemod 0.5",
    () => import("./commands/codemod.ts").then((m) => m.codemodCommand("0.5")),
  ],
  [
    "codemod 0.6",
    () => import("./commands/codemod.ts").then((m) => m.codemodCommand("0.6")),
  ],
  [
    "codemod 0.9",
    () => import("./commands/codemod.ts").then((m) => m.codemodCommand("0.9")),
  ],
];

/** The built-in commands, for `createCli`. */
export function builtinCommands(): CommandTreeInit {
  return { commands: COMMANDS, loaders: new Map(LOADERS) };
}
