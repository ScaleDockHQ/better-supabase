import type { ResolvedConfig } from "../../config/index.ts";
import type { ConsentRequest } from "../core/agent.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";

import { databaseUrl, stdinDatabaseUrl } from "../config.ts";
import { databaseHost, isLocalDatabaseUrl } from "../core/agent.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError, errorText } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";
import { connect } from "../db.ts";
import { ident as sqlIdent } from "../doctor/live.ts";
import { DB_URL_STDIN_ARG, STACK_ARG } from "./source-args.ts";

const DEFAULT_BATCH = 50_000;

const PROCEDURE = "convert_audit_log_to_partitioned";

const ARGS = {
  target: {
    type: "positional",
    required: true,
    description: "What to partition: audit",
  },
  "batch-size": {
    type: "string",
    description: "Rows to copy per transaction (default 50000)",
    valueHint: "n",
  },
  "drop-old": {
    type: "boolean",
    description:
      "Drop the unpartitioned copy once the swap is done (it stays as <name>_unpartitioned otherwise)",
  },
  "dry-run": {
    type: "boolean",
    description: "Check that the procedure exists and change nothing",
  },
} as const;

export type PartitionFlags = CliOptions<
  typeof ARGS & typeof DB_URL_STDIN_ARG & typeof STACK_ARG
>;

export interface PartitionDeps {
  readonly open: typeof connect;
  readonly log: (line: string) => void;
  readonly requireConsent: (request: ConsentRequest) => void;
}

const DEFAULT_DEPS: PartitionDeps = {
  open: connect,
  log: () => {},
  requireConsent: () => {},
};

/** The batch size flag as a positive integer. */
function batchSize(value: string | undefined): number {
  if (value === undefined) {
    return DEFAULT_BATCH;
  }

  const size = Number(value);

  if (!Number.isInteger(size) || size < 1) {
    throw new CliError(
      "invalid_value",
      `--batch-size takes a positive integer, got "${value}".`,
      { flag: "--batch-size" },
    );
  }

  return size;
}

/**
 * Moves an audit log created before `options.partitioned` onto monthly
 * partitions with the generated procedure, which commits between batches, so
 * the log keeps taking writes. Run it again after a failure; it resumes.
 */
export async function runPartition(
  config: ResolvedConfig,
  args: PartitionFlags,
  env: CliEnv,
  deps: Partial<PartitionDeps> = {},
  dbUrl?: string,
): Promise<CommandResult> {
  const { open, log, requireConsent } = { ...DEFAULT_DEPS, ...deps };

  if (args.target !== "audit") {
    throw new CliError(
      "invalid_value",
      `db partition takes audit, got "${args.target}".`,
    );
  }

  const size = batchSize(args["batch-size"]);
  const dryRun = args["dry-run"] === true;
  const dropOld = args["drop-old"] === true;

  const url = await databaseUrl(
    config,
    env,
    dbUrl,
    args.stack ?? env.BETTER_SUPABASE_STACK,
  );

  if (!dryRun && !isLocalDatabaseUrl(url)) {
    requireConsent({
      effect: "database-write",
      detail: `db partition audit moves the audit log onto monthly partitions on ${databaseHost(url)}`,
    });
  }

  const { client, close } = await open(url);

  try {
    const found = await client.query<{ schema: string }>(
      `select n.nspname as schema from pg_catalog.pg_proc p
       join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where p.proname = '${PROCEDURE}' and p.prokind = 'p'`,
    );

    const schema = found.rows[0]?.schema;

    if (schema === undefined) {
      throw new CliError(
        "not_found",
        `The database has no ${PROCEDURE} procedure. Set the audit block's options.partitioned, run \`better-supabase gen\`, and apply the migration first.`,
      );
    }

    if (dryRun) {
      return {
        code: 0,
        output: `Would call ${schema}.${PROCEDURE}(${String(size)}, ${String(dropOld)}).`,
        data: { schema, batchSize: size, dropOld, dryRun: true },
      };
    }

    log(`Partitioning the audit log in batches of ${String(size)}.`);

    // A procedure that commits can't run inside a transaction block, and the
    // connection sends this statement on its own.
    await client.query(
      `call ${sqlIdent(schema)}.${sqlIdent(PROCEDURE)}(${String(size)}, ${String(dropOld)})`,
    );

    return {
      code: 0,
      output: dropOld
        ? "The audit log is partitioned by month and the unpartitioned copy is dropped."
        : "The audit log is partitioned by month. The old table stays as <name>_unpartitioned; run again with --drop-old to drop it.",
      data: { schema, batchSize: size, dropOld, dryRun: false },
    };
  } catch (cause) {
    if (cause instanceof CliError) {
      throw cause;
    }

    return {
      code: 1,
      errorCode: "failed",
      error: `db partition audit failed: ${errorText(cause)}`,
    };
  } finally {
    await close();
  }
}

export const dbPartitionCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("db partition"),
  args: { ...ARGS, ...DB_URL_STDIN_ARG, ...STACK_ARG },
  run: async (args, { config, env, io, log, requireConsent }) => {
    const dbUrl = await stdinDatabaseUrl(args["db-url-stdin"], io);

    return runPartition(
      config,
      args,
      env,
      { open: connect, log: log.info, requireConsent },
      dbUrl,
    );
  },
});
