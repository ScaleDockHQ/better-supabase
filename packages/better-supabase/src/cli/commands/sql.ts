import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";

import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";
import { migrationsDir } from "../sql-layout.ts";
import { addModules } from "../sql/add.ts";
import { SQL_ARGS, type SqlFlags } from "../sql/args.ts";
import { listModules } from "../sql/list.ts";
import { dataMigration, type Now } from "../sql/migrations.ts";
import { printModule } from "../sql/print.ts";
import { syncModules } from "../sql/sync.ts";
import { upgrade } from "../sql/upgrade.ts";
import { type Paint, plain } from "../style.ts";

export { migrationsDir };

export type { SqlFlags } from "../sql/args.ts";

/** What `runSql` reads from outside: the clock behind the migration stamps. */
export interface SqlDeps {
  readonly now: Now;
  /** The config file `sql add` lists new modules in, when there is one. */
  readonly configFile?: string;
}

const SYSTEM_DEPS: SqlDeps = { now: () => new Date() };

/** Runs one `sql` subcommand: `args._` is the subcommand name, then its arguments. */
export async function runSql(
  config: ResolvedConfig,
  args: SqlFlags,
  paint: Paint = plain,
  deps: SqlDeps = SYSTEM_DEPS,
): Promise<CommandResult> {
  const [action, ...names] = args._ ?? [];

  switch (action) {
    case "list": {
      return listModules(config, args);
    }

    case "add": {
      return addModules(config, args, names, deps);
    }

    case "sync": {
      return syncModules(config, args, paint, deps.now);
    }

    case "upgrade": {
      return upgrade(config, args, paint, deps.now);
    }

    case "data": {
      return dataMigration(config, args, deps.now);
    }

    case "print": {
      return printModule(config, args, names);
    }

    case undefined: {
      throw new CliError("usage", "Name a subcommand.");
    }

    default: {
      throw new CliError("usage", `Unknown sql subcommand "${action}".`);
    }
  }
}

const MODULES_ARG = {
  module: {
    type: "positional",
    required: true,
    variadic: true,
    description: "SQL modules (`better-supabase sql list`)",
  },
} as const;

const MODULE_ARG = {
  module: {
    type: "positional",
    required: true,
    description: "The SQL module to print",
  },
} as const;

const TESTS_DIR = { "tests-dir": SQL_ARGS["tests-dir"] } as const;

export const sqlListCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("sql list"),
  args: TESTS_DIR,
  run: (args, { config }) => runSql(config, { ...args, _: ["list"] }),
});

export const sqlAddCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("sql add"),
  args: {
    ...MODULES_ARG,
    ...TESTS_DIR,
    "dry-run": SQL_ARGS["dry-run"],
    "allow-hook-overlap": SQL_ARGS["allow-hook-overlap"],
  },
  run: (args, { config, configFile, paint }) =>
    runSql(config, { ...args, _: ["add", ...args._] }, paint, {
      ...SYSTEM_DEPS,
      ...(configFile === undefined ? {} : { configFile }),
    }),
});

export const sqlSyncCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("sql sync"),
  args: {
    ...TESTS_DIR,
    check: SQL_ARGS.check,
    "dry-run": SQL_ARGS["dry-run"],
  },
  run: (args, { config, paint }) =>
    runSql(config, { ...args, _: ["sync"] }, paint),
});

export const sqlUpgradeCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("sql upgrade"),
  args: {
    ...TESTS_DIR,
    check: SQL_ARGS.check,
    "dry-run": SQL_ARGS["dry-run"],
  },
  run: (args, { config, paint }) =>
    runSql(config, { ...args, _: ["upgrade"] }, paint),
});

export const sqlDataCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("sql data"),
  args: { ...TESTS_DIR, "dry-run": SQL_ARGS["dry-run"] },
  run: (args, { config }) => runSql(config, { ...args, _: ["data"] }),
});

export const sqlPrintCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("sql print"),
  args: { ...MODULE_ARG, ...TESTS_DIR },
  run: (args, { config }) =>
    runSql(config, { ...args, _: ["print", ...args._] }),
});
