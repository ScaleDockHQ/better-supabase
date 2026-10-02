import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { AnyCommand } from "../command.ts";

import { defineCliCommand } from "../command.ts";
import { fileDiff } from "../diff.ts";
import { restrictSchemas, serializeGenerator } from "../introspect/typegen.ts";
import { display, writeIfChanged } from "../io.ts";
import { withSpinner } from "../prompts.ts";
import { painter } from "../style.ts";
import { SOURCE_ARGS, sourceArgs } from "./gen.ts";
import { loadSnapshot, serializeSnapshot } from "./snapshot.ts";

const ARGS = {
  out: {
    type: "string",
    description:
      "Defaults to supabase/snapshot.json, or supabase/generator-metadata.json",
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
  meta: {
    name: "introspect",
    description: "Saves the database schema as a snapshot for offline gen",
  },
  args: ARGS,
  run: async (args, { config, env, io }) => {
    const format = args.format ?? "snapshot";
    if (format !== "snapshot" && format !== "generator-metadata") {
      return {
        code: 2,
        error: '--format must be "snapshot" or "generator-metadata"',
      };
    }
    const { snapshotPath: _ignored, ...source } = sourceArgs(args);
    const snapshot = await withSpinner(io.prompts, "Reading the schema", () =>
      loadSnapshot(config, env, { ...source, live: true }),
    );
    const out =
      args.out ??
      (format === "snapshot"
        ? "supabase/snapshot.json"
        : "supabase/generator-metadata.json");
    const contents =
      format === "snapshot"
        ? serializeSnapshot(snapshot)
        : `${serializeGenerator(restrictSchemas(snapshot.generator, config.schemas))}\n`;
    if (args.check === true) {
      const current = await readFile(resolve(config.root, out), "utf8").catch(
        () => undefined,
      );
      return current === contents
        ? { code: 0, output: `${display(config.root, out)} is up to date.` }
        : {
            code: 1,
            output: fileDiff(
              display(config.root, out),
              current,
              contents,
              painter(io.color),
            ),
            error: `${display(config.root, out)} is out of date. Run \`better-supabase introspect\`.`,
          };
    }
    const wrote = await writeIfChanged(resolve(config.root, out), contents);
    return {
      code: 0,
      output: `${wrote ? "Wrote" : "Unchanged"} ${display(config.root, out)} (${snapshot.extras.tables.length} tables).`,
    };
  },
});
