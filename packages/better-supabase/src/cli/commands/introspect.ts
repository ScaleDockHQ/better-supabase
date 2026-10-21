import type { AnyCommand } from "../core/command.ts";
import type { FilePlan } from "../core/files.ts";

import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { applyPlan, insideRoot, PLAN_ARGS, planResult } from "../core/files.ts";
import { commandMeta } from "../core/manifest.ts";
import { restrictSchemas, serializeGenerator } from "../introspect/typegen.ts";
import { loadSnapshot, serializeSnapshot } from "./snapshot.ts";
import { SOURCE_ARGS, sourceArgs } from "./source-args.ts";

const ARGS = {
  out: {
    type: "string",
    description:
      "Defaults to source.snapshot, supabase/snapshot.json, or supabase/generator-metadata.json",
    valueHint: "file",
  },
  kind: {
    type: "string",
    description:
      "snapshot (the default) or generator-metadata (postgrest-typegen's input)",
    valueHint: "snapshot|generator-metadata",
  },
  check: PLAN_ARGS.check,
  "dry-run": PLAN_ARGS["dry-run"],
  ...SOURCE_ARGS,
} as const;

export const introspectCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("introspect"),
  args: ARGS,
  run: async (args, { config, env, io, log, paint, signal }) => {
    const format = args.kind ?? "snapshot";

    if (format !== "snapshot" && format !== "generator-metadata") {
      throw new CliError(
        "usage",
        '--kind must be "snapshot" or "generator-metadata"',
      );
    }

    const source = await sourceArgs(args, io);

    // `--snapshot` converts a saved file; without it, introspect always reads
    // the database, even when the config names a snapshot.
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
      regenerate: "better-supabase introspect",
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
  },
});
