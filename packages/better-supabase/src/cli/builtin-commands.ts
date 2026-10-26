import type { Loader } from "./core/parse.ts";
import type { CommandTreeInit } from "./core/run.ts";

import { COMMANDS } from "./core/manifest.ts";

/**
 * The module behind each built-in command, by its path in the manifest. Each
 * loads on demand, so `--version` and `--help` import no command.
 */
const LOADERS: readonly (readonly [string, Loader])[] = [
  ["init", () => import("./commands/init.ts").then((m) => m.initCommand)],
  ["add", () => import("./commands/add.ts").then((m) => m.addCommand)],
  ["remove", () => import("./commands/remove.ts").then((m) => m.removeCommand)],
  [
    "upgrade",
    () => import("./commands/upgrade.ts").then((m) => m.upgradeCommand),
  ],
  ["table", () => import("./commands/table.ts").then((m) => m.tableCommand)],
  ["gen", () => import("./commands/gen.ts").then((m) => m.genCommand)],
  ["doctor", () => import("./commands/doctor.ts").then((m) => m.doctorCommand)],
  ["db query", () => import("./commands/db.ts").then((m) => m.dbQueryCommand)],
  ["db diff", () => import("./commands/db.ts").then((m) => m.dbDiffCommand)],
  ["db seed", () => import("./commands/seed.ts").then((m) => m.seedCommand)],
  [
    "db backfill",
    () => import("./commands/backfill.ts").then((m) => m.dbBackfillCommand),
  ],
  ["dev env", () => import("./commands/env.ts").then((m) => m.envCommand)],
  ["dev run", () => import("./commands/run.ts").then((m) => m.runCommand)],
  ["dev keys", () => import("./commands/keys.ts").then((m) => m.keysCommand)],
  [
    "dev stack ls",
    () => import("./commands/stack.ts").then((m) => m.stackLsCommand),
  ],
  [
    "dev stack prune",
    () => import("./commands/stack.ts").then((m) => m.stackPruneCommand),
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
    "powersync streams",
    () =>
      import("./commands/powersync.ts").then((m) => m.powersyncStreamsCommand),
  ],
  [
    "spec emit",
    () => import("./commands/spec.ts").then((m) => m.specEmitCommand),
  ],
  [
    "spec validate",
    () => import("./commands/spec.ts").then((m) => m.specValidateCommand),
  ],
  ["mcp", () => import("./commands/mcp.ts").then((m) => m.mcpCommand)],
  [
    "skills list",
    () => import("./commands/skills.ts").then((m) => m.skillsListCommand),
  ],
  [
    "skills install",
    () => import("./commands/skills.ts").then((m) => m.skillsInstallCommand),
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
  [
    "codemod 0.11",
    () => import("./commands/codemod.ts").then((m) => m.codemodCommand("0.11")),
  ],
  [
    "codemod 0.15",
    () => import("./commands/codemod.ts").then((m) => m.codemodCommand("0.15")),
  ],
  [
    "completion",
    () => import("./commands/completion.ts").then((m) => m.completionCommand),
  ],
  ["config", () => import("./commands/config.ts").then((m) => m.configCommand)],
];

/** The built-in commands, for `createCli`. */
export function builtinCommands(): CommandTreeInit {
  return { commands: COMMANDS, loaders: new Map(LOADERS) };
}
