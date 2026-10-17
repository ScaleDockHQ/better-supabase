import type { CliArgs } from "../command.ts";
import type { CliIo } from "../io.ts";
import type { SnapshotSource } from "./snapshot.ts";

import { stdinDatabaseUrl } from "../config.ts";

/** Where to read the schema from, shared by gen, introspect and doctor. */
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

export async function sourceArgs(
  args: CliArgs<typeof SOURCE_ARGS>,
  io: CliIo,
): Promise<SnapshotSource> {
  const snapshotPath = args.snapshot;
  const dbUrl = await stdinDatabaseUrl(args["db-url-stdin"], io);
  const projectRef = args["project-ref"];
  return {
    ...(snapshotPath ? { snapshotPath } : {}),
    ...(dbUrl ? { dbUrl } : {}),
    ...(projectRef ? { projectRef } : {}),
  };
}
