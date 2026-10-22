import type { ResolvedConfig } from "../../config/index.ts";
import type { CommandResult } from "../core/io.ts";
import type { SqlFlags } from "../sql/args.ts";
import type { Now } from "../sql/migrations.ts";
import type { Paint } from "../style.ts";

import { CliError } from "../core/errors.ts";
import { migrationsDir } from "../sql-layout.ts";
import { addModules } from "../sql/add.ts";
import { listModules } from "../sql/list.ts";
import { dataMigration } from "../sql/migrations.ts";
import { printModule } from "../sql/print.ts";
import { syncModules } from "../sql/sync.ts";
import { upgrade } from "../sql/upgrade.ts";
import { plain } from "../style.ts";

export { migrationsDir };

export type { SqlFlags } from "../sql/args.ts";

/** What `runSql` reads from outside: the clock behind the migration stamps. */
export interface SqlDeps {
  readonly now: Now;
  /** The config file `add` lists new modules in, when there is one. */
  readonly configFile?: string;
}

const SYSTEM_DEPS: SqlDeps = { now: () => new Date() };

/**
 * Runs one SQL engine step: `args._` is the step name, then its arguments. The
 * commands reach these through `add`, `upgrade`, `blocks` and `gen`.
 */
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
