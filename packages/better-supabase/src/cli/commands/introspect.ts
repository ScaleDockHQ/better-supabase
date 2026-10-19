import type { AnyCommand } from "../core/command.ts";

import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { fileState, writeLine } from "../core/files.ts";
import { commandMeta } from "../core/manifest.ts";
import { fileDiff } from "../diff.ts";
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
  format: {
    type: "string",
    description:
      "snapshot (the default) or generator-metadata (postgrest-typegen's input)",
    valueHint: "snapshot|generator-metadata",
  },
  check: {
    type: "boolean",
    description: "Fail when the file is out of date",
  },
  ...SOURCE_ARGS,
} as const;

export const introspectCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("introspect"),
  args: ARGS,
  run: async (args, { config, env, io, log, paint, signal }) => {
    const format = args.format ?? "snapshot";

    if (format !== "snapshot" && format !== "generator-metadata") {
      throw new CliError(
        "usage",
        '--format must be "snapshot" or "generator-metadata"',
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

    const state = await fileState(config.root, out, contents);

    if (args.check === true) {
      const { file, current, upToDate } = state;

      return upToDate
        ? {
            code: 0,
            output: `${file} is up to date.`,
            data: { file, upToDate: true },
          }
        : {
            code: 1,
            output: fileDiff(file, current, contents, paint),
            error: `${file} is out of date. Run \`better-supabase introspect\`.`,
            errorCode: "check_failed",
            data: { file, upToDate: false },
          };
    }

    const tables = snapshot.extras.tables.length;

    const { wrote, line } = await writeLine(
      state.path,
      contents,
      state.file,
      ` (${tables} tables).`,
    );

    return {
      code: 0,
      output: line,
      data: { file: state.file, written: wrote, tables },
    };
  },
});
