import type { ResolvedConfig } from "../../config/index.ts";
import type { CliArgs } from "../core/command.ts";
import type { FilePlan, PLAN_ARGS } from "../core/files.ts";
import type { CliIo, CommandResult } from "../core/io.ts";
import type { CliLog } from "../core/log.ts";
import type { CliEnv } from "../env.ts";
import type { Paint } from "../style.ts";
import type { SOURCE_ARGS } from "./source-args.ts";

import { CliError } from "../core/errors.ts";
import { applyPlan, insideRoot, planResult } from "../core/files.ts";
import { restrictSchemas, serializeGenerator } from "../introspect/typegen.ts";
import { loadSnapshot, serializeSnapshot } from "./snapshot.ts";
import { sourceArgs } from "./source-args.ts";

/** The flags `gen --save-snapshot` reads. */
export const SAVE_SNAPSHOT_ARGS = {
  "save-snapshot": {
    type: "boolean",
    description:
      "Read the database and save the schema as a snapshot file instead of generating",
  },
  out: {
    type: "string",
    description:
      "With --save-snapshot: defaults to database.source.snapshot, supabase/snapshot.json, or supabase/generator-metadata.json",
    valueHint: "file",
  },
  kind: {
    type: "string",
    description:
      "With --save-snapshot: snapshot (the default) or generator-metadata (postgrest-typegen's input)",
    valueHint: "snapshot|generator-metadata",
  },
} as const;

type SaveSnapshotArgs = CliArgs<
  typeof SAVE_SNAPSHOT_ARGS &
    typeof SOURCE_ARGS &
    Pick<typeof PLAN_ARGS, "check" | "dry-run">
>;

/** What `saveSnapshot` reads from the command context. */
export interface SaveSnapshotContext {
  readonly config: ResolvedConfig;
  readonly env: CliEnv;
  readonly io: CliIo;
  readonly log: CliLog;
  readonly paint: Paint;
  readonly signal?: AbortSignal | undefined;
}

/**
 * Reads the database and writes its schema as a snapshot, or as the
 * GeneratorMetadata document postgrest-typegen reads. `--snapshot` converts a
 * saved file instead.
 */
export async function saveSnapshot(
  args: SaveSnapshotArgs,
  { config, env, io, log, paint, signal }: SaveSnapshotContext,
): Promise<CommandResult> {
  const format = args.kind ?? "snapshot";

  if (format !== "snapshot" && format !== "generator-metadata") {
    throw new CliError(
      "usage",
      '--kind must be "snapshot" or "generator-metadata"',
    );
  }

  const source = await sourceArgs(args, io);

  // Without `--snapshot`, the database is read even when the config names a
  // snapshot, since that file is what this writes.
  const snapshot = await log.progress("Reading the schema", () =>
    loadSnapshot(config, env, {
      ...source,
      live: true,
      ...(signal ? { signal } : {}),
    }),
  );

  const out =
    args.out ??
    (format === "snapshot"
      ? (config.source.snapshot ?? "supabase/snapshot.json")
      : "supabase/generator-metadata.json");

  const contents =
    format === "snapshot"
      ? serializeSnapshot(snapshot)
      : `${await serializeGenerator(restrictSchemas(snapshot.generator, config.schemas))}\n`;

  const tables = snapshot.extras.tables.length;

  const plan: FilePlan = {
    root: config.root,
    regenerate: "better-supabase gen --save-snapshot",
    files: [
      {
        path: insideRoot(config.root, out, "--out"),
        contents,
        note: `${tables} tables`,
      },
    ],
  };

  return planResult(plan, await applyPlan(plan, args, paint), {
    data: { tables },
  });
}
