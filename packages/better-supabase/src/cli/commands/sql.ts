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
import { type Paint, painter, plain } from "../style.ts";

export { migrationsDir };

export type { SqlArgs, SqlFlags } from "../sql/args.ts";

/** What `runSql` reads from outside: the clock behind the migration stamps. */
export interface SqlDeps {
  readonly now: Now;
  /** The config file `sql add` lists new modules in, when there is one. */
  readonly configFile?: string;
}

const SYSTEM_DEPS: SqlDeps = { now: () => new Date() };

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
      throw new CliError("usage", "Name an action.");
    }

    default: {
      throw new CliError("usage", `Unknown sql action "${action}".`);
    }
  }
}

export const sqlCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("sql"),
  args: SQL_ARGS,
  run: (args, { config, configFile, io }) =>
    runSql(config, args, painter(io.color), {
      ...SYSTEM_DEPS,
      ...(configFile === undefined ? {} : { configFile }),
    }),
});
