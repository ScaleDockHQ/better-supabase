import type { Loader } from "./core/parse.ts";
import type { CreateCliOptions } from "./core/run.ts";

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
  ["preset", () => import("./commands/preset.ts").then((m) => m.presetCommand)],
  ["blocks", () => import("./commands/blocks.ts").then((m) => m.blocksCommand)],
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
  ["spec", () => import("./commands/spec.ts").then((m) => m.specCommand)],
  [
    "scaffold",
    () => import("./commands/scaffold.ts").then((m) => m.scaffoldCommand),
  ],
  ["seed", () => import("./commands/seed.ts").then((m) => m.seedCommand)],
  ["doctor", () => import("./commands/doctor.ts").then((m) => m.doctorCommand)],
  ["sql", () => import("./commands/sql.ts").then((m) => m.sqlCommand)],
  ["config", () => import("./commands/config.ts").then((m) => m.configCommand)],
  [
    "codemod",
    () => import("./commands/codemod.ts").then((m) => m.codemodCommand),
  ],
];

/** The built-in commands, for `createCli`. */
export function builtinCommands(): CreateCliOptions {
  return { commands: COMMANDS, loaders: new Map(LOADERS) };
}
