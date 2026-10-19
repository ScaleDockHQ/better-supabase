import type { CliArgs, CliOptions } from "../core/command.ts";
import type { CliIo } from "../core/io.ts";
import type { SnapshotSource } from "./snapshot.ts";

import { stdinDatabaseUrl } from "../config.ts";
import { CliError } from "../core/errors.ts";

/** The connection string from stdin, for commands that connect but read no schema. */
export const DB_URL_STDIN_ARG = {
  "db-url-stdin": {
    type: "boolean",
    description:
      "Read the connection string from stdin instead of the config, $DATABASE_URL or $SUPABASE_DB_URL",
  },
} as const;

/** Where to read the schema from, shared by gen, introspect, doctor, adopt and apply. */
export const SOURCE_ARGS = {
  snapshot: {
    type: "string",
    description: "Read a saved snapshot instead of the database",
    valueHint: "file",
  },
  "db-url-stdin": {
    type: "boolean",
    description:
      "Read the connection string from stdin instead of the config, $DATABASE_URL or $SUPABASE_DB_URL",
  },
  "project-ref": {
    type: "string",
    description: "Read a hosted project through the Management API",
    valueHint: "ref",
  },
} as const;

/** The source flags `args` sets, as typed on the command line. */
export function sourceFlags(args: CliOptions<typeof SOURCE_ARGS>): string[] {
  return [
    ...(args.snapshot === undefined ? [] : ["--snapshot"]),
    ...(args["db-url-stdin"] === true ? ["--db-url-stdin"] : []),
    ...(args["project-ref"] === undefined ? [] : ["--project-ref"]),
  ];
}

export async function sourceArgs(
  args: CliArgs<typeof SOURCE_ARGS>,
  io: CliIo,
): Promise<SnapshotSource> {
  const snapshotPath = args.snapshot;

  const live = (["db-url-stdin", "project-ref"] as const).find(
    (flag) => args[flag] !== undefined && args[flag] !== false,
  );

  if (snapshotPath && live) {
    throw new CliError(
      "usage",
      `--snapshot reads a saved file and --${live} reads a database. Pass one of them.`,
      { flag: "--snapshot" },
    );
  }

  const dbUrl = await stdinDatabaseUrl(args["db-url-stdin"], io);
  const projectRef = args["project-ref"];

  return {
    ...(snapshotPath ? { snapshotPath } : {}),
    ...(dbUrl ? { dbUrl } : {}),
    ...(projectRef ? { projectRef } : {}),
  };
}
