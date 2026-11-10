import type { Loader } from "./core/parse.ts";
import type { CommandTreeInit } from "./core/run.ts";

import { COMMANDS } from "./core/manifest.ts";

/**
 * The module behind each built-in command, by its path in the manifest. Each
 * loads on demand, so `--version` and `--help` import no command.
 */
const LOADERS: readonly (readonly [string, Loader])[] = [
  ["login", () => import("./commands/account.ts").then((m) => m.loginCommand)],
  [
    "logout",
    () => import("./commands/account.ts").then((m) => m.logoutCommand),
  ],
  [
    "whoami",
    () => import("./commands/account.ts").then((m) => m.whoamiCommand),
  ],
  ["init", () => import("./commands/init.ts").then((m) => m.initCommand)],
  ["add", () => import("./commands/add.ts").then((m) => m.addCommand)],
  ["remove", () => import("./commands/remove.ts").then((m) => m.removeCommand)],
  [
    "upgrade",
    () => import("./commands/upgrade.ts").then((m) => m.upgradeCommand),
  ],
  ["table", () => import("./commands/table.ts").then((m) => m.tableCommand)],
  [
    "migrate schema-first",
    () =>
      import("./commands/migrate.ts").then((m) => m.migrateSchemaFirstCommand),
  ],
  ["gen", () => import("./commands/gen.ts").then((m) => m.genCommand)],
  ["doctor", () => import("./commands/doctor.ts").then((m) => m.doctorCommand)],
  ["codes", () => import("./commands/codes.ts").then((m) => m.codesCommand)],
  ["db query", () => import("./commands/db.ts").then((m) => m.dbQueryCommand)],
  ["db diff", () => import("./commands/db.ts").then((m) => m.dbDiffCommand)],
  ["db seed", () => import("./commands/seed.ts").then((m) => m.seedCommand)],
  [
    "db backfill",
    () => import("./commands/backfill.ts").then((m) => m.dbBackfillCommand),
  ],
  [
    "db partition",
    () => import("./commands/partition.ts").then((m) => m.dbPartitionCommand),
  ],
  [
    "workflows prune",
    () =>
      import("./commands/prune-workflows.ts").then(
        (m) => m.workflowsPruneCommand,
      ),
  ],
  ["dev", () => import("./commands/dev.ts").then((m) => m.devCommand)],
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
    "automations list",
    () =>
      import("./commands/automations.ts").then((m) => m.automationsListCommand),
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
    "codemod naming",
    () =>
      import("./commands/codemod.ts").then((m) => m.codemodCommand("naming")),
  ],
  [
    "codemod extra-columns",
    () =>
      import("./commands/codemod.ts").then((m) =>
        m.codemodCommand("extra-columns"),
      ),
  ],
  [
    "codemod owned-columns",
    () =>
      import("./commands/codemod.ts").then((m) =>
        m.codemodCommand("owned-columns"),
      ),
  ],
  [
    "codemod config",
    () =>
      import("./commands/codemod.ts").then((m) => m.codemodCommand("config")),
  ],
  [
    "codemod table-modules",
    () =>
      import("./commands/codemod.ts").then((m) =>
        m.codemodCommand("table-modules"),
      ),
  ],
  [
    "codemod account-calls",
    () =>
      import("./commands/codemod.ts").then((m) =>
        m.codemodCommand("account-calls"),
      ),
  ],
  [
    "codemod server-imports",
    () =>
      import("./commands/codemod.ts").then((m) =>
        m.codemodCommand("server-imports"),
      ),
  ],
  [
    "codemod generators",
    () =>
      import("./commands/codemod.ts").then((m) =>
        m.codemodCommand("generators"),
      ),
  ],
  [
    "codemod read-many",
    () =>
      import("./commands/codemod.ts").then((m) =>
        m.codemodCommand("read-many"),
      ),
  ],
  [
    "completion",
    () => import("./commands/completion.ts").then((m) => m.completionCommand),
  ],
  [
    "cache purge",
    () => import("./commands/cache.ts").then((m) => m.cachePurgeCommand),
  ],
  ["config", () => import("./commands/config.ts").then((m) => m.configCommand)],
];

/** The built-in commands, for `createCli`. */
export function builtinCommands(): CommandTreeInit {
  return { commands: COMMANDS, loaders: new Map(LOADERS) };
}
