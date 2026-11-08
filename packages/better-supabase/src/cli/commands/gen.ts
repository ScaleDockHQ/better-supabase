import type { AnyCommand } from "../core/command.ts";
import type { GenOptions } from "../gen/run.ts";

import { defineCliCommand, list } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";
import { checkMetadataFlags, EMITS, runMetadataGen } from "../gen/metadata.ts";
import { GEN_TASKS } from "../names.ts";
import { parseTasks, selectTasks } from "./gen-pipeline.ts";
import { runTasks } from "./gen-tasks.ts";
import { SAVE_SNAPSHOT_ARGS, saveSnapshot } from "./save-snapshot.ts";
import { SOURCE_ARGS, sourceArgs, sourceFlags } from "./source-args.ts";

const ARGS = {
  metadata: {
    type: "string",
    description:
      "Read a GeneratorMetadata document (- for stdin) and print one file on stdout",
    valueHint: "path|-",
  },
  only: {
    type: "string",
    description: `Tasks to run: ${GEN_TASKS.join(", ")}. Defaults to gen.tasks, or every task the config sets up. With --metadata, the one file to print: ${EMITS.join(", ")}`,
    valueHint: "list",
  },
  check: {
    type: "boolean",
    description: "Fail when a generated file is out of date",
  },
  "dry-run": {
    type: "boolean",
    description: "Print what would change and write nothing",
  },
  force: {
    type: "boolean",
    description:
      "Overwrite a file at a generated path that the CLI did not write",
  },
  ...SAVE_SNAPSHOT_ARGS,
  ...SOURCE_ARGS,
} as const;

export const genCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("gen"),
  args: ARGS,
  lists: ["only"],
  completions: { only: () => GEN_TASKS },
  run: async (args, context) => {
    if (args["save-snapshot"] === true) {
      const generating = [
        ["--metadata", args.metadata],
        ["--only", args.only],
        ["--force", args.force],
      ].find(([, value]) => value !== undefined && value !== false);

      if (generating !== undefined) {
        throw new CliError(
          "usage",
          `--save-snapshot writes a snapshot and generates nothing, so it takes no ${String(generating[0])}.`,
        );
      }

      return saveSnapshot(args, context);
    }

    const snapshotOnly =
      args.metadata === undefined ? (args.out ?? args.kind) : args.kind;

    if (snapshotOnly !== undefined) {
      throw new CliError(
        "usage",
        args.out === undefined || args.metadata !== undefined
          ? "--kind works with --save-snapshot."
          : "--out works with --save-snapshot or --metadata.",
      );
    }

    const emit = args.metadata === undefined ? undefined : args.only;

    checkMetadataFlags({
      ...(args.metadata === undefined ? {} : { metadata: args.metadata }),
      ...(emit === undefined ? {} : { emit }),
      ...(args.metadata === undefined || args.out === undefined
        ? {}
        : { out: args.out }),
      check: args.check === true,
      json: context.json,
      conflicting: sourceFlags(args),
    });

    if (args.metadata !== undefined) {
      return runMetadataGen({
        config: context.config,
        env: context.env,
        cwd: context.cwd,
        io: context.io,
        log: context.log,
        metadata: args.metadata,
        check: args.check === true,
        paint: context.paint,
        ...(emit === undefined ? {} : { emit }),
        ...(args.out === undefined ? {} : { out: args.out }),
      });
    }

    const requested =
      args.only === undefined ? undefined : parseTasks(list(args.only));

    if (typeof requested === "string") {
      throw new CliError("usage", requested);
    }

    const tasks = selectTasks(context.config, requested);

    if (tasks.length === 0) {
      throw new CliError("usage", "--only names no task.");
    }

    const options: GenOptions = {
      config: context.config,
      ...(context.configFile ? { configFile: context.configFile } : {}),
      env: context.env,
      check: args.check === true,
      dryRun: args["dry-run"] === true,
      force: args.force === true,
      paint: context.paint,
      ...(await sourceArgs(args, context.io)),
      ...(context.signal ? { signal: context.signal } : {}),
      cache: true,
    };

    return context.log.progress("Generating from the schema", () =>
      runTasks(tasks, options),
    );
  },
});
