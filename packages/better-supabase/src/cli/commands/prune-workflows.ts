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

const TERMINAL = ["completed", "failed", "cancelled"] as const;
const TERMINAL_SET: ReadonlySet<string> = new Set(TERMINAL);
const DEFAULT_BATCH = 500;

const ARGS = {
  "older-than": {
    type: "string",
    description:
      "Delete runs that ended longer ago than this: 30d, 12h, or a Postgres interval (default 30d)",
    valueHint: "age",
  },
  status: {
    type: "string",
    description:
      "The ended statuses to delete, comma-separated (default completed,failed,cancelled)",
    valueHint: "list",
  },
  "batch-size": {
    type: "string",
    description: "Runs to delete per statement, 1 to 10000 (default 500)",
    valueHint: "n",
  },
  "dry-run": {
    type: "boolean",
    description: "Count the runs it would delete, and change nothing",
  },
} as const;

export type PruneWorkflowsFlags = CliOptions<
  typeof ARGS & typeof DB_URL_STDIN_ARG & typeof STACK_ARG
>;

const AGE = /^(\d{1,4})\s*(d|h|days?|hours?)$/iu;

/** `30d`, `12h`, `30 days` or `12 hours` as a Postgres interval. */
export function parseAge(value: string): string {
  const match = AGE.exec(value.trim());

  if (match === null) {
    throw new CliError(
      "invalid_value",
      `--older-than takes an age such as 30d, 12h or "30 days", got "${value}".`,
      { flag: "--older-than" },
    );
  }

  const unit = match[2]!.toLowerCase().startsWith("d") ? "days" : "hours";

  return `${match[1]!} ${unit}`;
}

function parseStatuses(value: string | undefined): readonly string[] {
  if (value === undefined) {
    return TERMINAL;
  }

  const list = value
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);

  const bad = list.filter((status) => !TERMINAL_SET.has(status));

  if (list.length === 0 || bad.length > 0) {
    throw new CliError(
      "invalid_value",
      `--status takes ${TERMINAL.join(", ")}; got "${value}". Only ended runs can be deleted.`,
      { flag: "--status" },
    );
  }

  return list;
}

export interface PruneWorkflowsDeps {
  readonly open: typeof connect;
  readonly log: (line: string) => void;
  readonly requireConsent: (request: ConsentRequest) => void;
}

const DEFAULT_DEPS: PruneWorkflowsDeps = {
  open: connect,
  log: () => {},
  requireConsent: () => {},
};

const runsText = (count: number): string =>
  `${String(count)} run${count === 1 ? "" : "s"}`;

/**
 * Deletes the ended workflow runs older than `--older-than`, with their events,
 * steps, waits, stream chunks and hooks, in batches through
 * `workflow_purge_runs`.
 */
export async function runPruneWorkflows(
  config: ResolvedConfig,
  args: PruneWorkflowsFlags,
  env: CliEnv,
  deps: Partial<PruneWorkflowsDeps> = {},
  dbUrl?: string,
): Promise<CommandResult> {
  const { open, log, requireConsent } = { ...DEFAULT_DEPS, ...deps };
  const olderThan = parseAge(args["older-than"] ?? "30d");
  const statuses = parseStatuses(args.status);

  const batch =
    args["batch-size"] === undefined
      ? DEFAULT_BATCH
      : Number(args["batch-size"]);

  const dryRun = args["dry-run"] === true;

  if (!Number.isInteger(batch) || batch < 1 || batch > 10_000) {
    throw new CliError(
      "invalid_value",
      `--batch-size takes a whole number from 1 to 10000, got "${args["batch-size"] ?? ""}".`,
      { flag: "--batch-size" },
    );
  }

  const url = await databaseUrl(
    config,
    env,
    dbUrl,
    args.stack ?? env.BSB_STACK,
  );

  if (!dryRun && !isLocalDatabaseUrl(url)) {
    requireConsent({
      effect: "database-write",
      detail: `db prune-workflows deletes ${statuses.join(", ")} runs older than ${olderThan} on ${databaseHost(url)}`,
    });
  }

  const { client, close } = await open(url);

  try {
    const { rows: found } = await client.query<{ schema: string }>(
      `select n.nspname as schema from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
where p.proname = 'workflow_purge_runs'
limit 1`,
    );

    const schema = found[0]?.schema;

    if (schema === undefined) {
      throw new CliError(
        "not_found",
        "The database has no workflow_purge_runs function. Add the workflow-sdk block (version 3 or later) and apply its migration.",
      );
    }

    const data = { olderThan, statuses: [...statuses], dryRun };

    if (dryRun) {
      const { rows } = await client.query<{ count: string }>(
        `select count(*)::bigint::text as count from workflow.workflow_runs
where status::text = any($1::text[])
  and coalesce(completed_at, updated_at) < (now() at time zone 'UTC') - $2::interval`,
        [[...statuses], olderThan],
      );

      const pending = Number(rows[0]?.count ?? 0);

      return {
        code: 0,
        output: `Would delete ${runsText(pending)} that ended more than ${olderThan} ago.`,
        data: { ...data, pending, deleted: 0 },
      };
    }

    let deleted = 0;

    for (;;) {
      const { rows } = await client.query<{ deleted: number }>(
        `select ${sqlIdent(schema)}.workflow_purge_runs($1::interval, $2::text[], $3::integer) as deleted`,
        [olderThan, [...statuses], batch],
      );

      const done = rows[0]?.deleted ?? 0;

      deleted += done;

      if (done > 0) {
        log(`Deleted ${runsText(deleted)}.`);
      }

      if (done < batch) {
        break;
      }
    }

    return {
      code: 0,
      output:
        deleted === 0
          ? `No runs ended more than ${olderThan} ago.`
          : `Deleted ${runsText(deleted)} that ended more than ${olderThan} ago.`,
      data: { ...data, deleted },
    };
  } catch (cause) {
    if (cause instanceof CliError) {
      throw cause;
    }

    return {
      code: 1,
      errorCode: "failed",
      error: `db prune-workflows failed: ${errorText(cause)}`,
    };
  } finally {
    await close();
  }
}

export const dbPruneWorkflowsCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("db prune-workflows"),
  args: { ...ARGS, ...DB_URL_STDIN_ARG, ...STACK_ARG },
  run: async (args, { config, env, io, log, requireConsent }) => {
    const dbUrl = await stdinDatabaseUrl(args["db-url-stdin"], io);

    return runPruneWorkflows(
      config,
      args,
      env,
      { open: connect, log: log.info, requireConsent },
      dbUrl,
    );
  },
});
