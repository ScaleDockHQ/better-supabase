import type { GenTask } from "../../config/index.ts";
import type { AnyCommand, CliContext } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { IntrospectionSource } from "../introspect/source.ts";
import type { Snapshot } from "../introspect/types.ts";

import { defineCliCommand, list } from "../core/command.ts";
import { failedResult, CliError } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";
import { checkMetadataFlags, EMITS, runMetadataGen } from "../gen/metadata.ts";
import { type GenOptions, runGen } from "../gen/run.ts";
import { catalogFingerprint } from "../introspect/fingerprint.ts";
import { GEN_TASKS } from "../names.ts";
import { plain } from "../style.ts";
import { parseInterval, stampFiles, watchLoop } from "../watch.ts";
import {
  combineResults,
  runSteps,
  parseTasks,
  selectTasks,
  stepInputs,
} from "./gen-pipeline.ts";
import { loadSnapshot, openSource, snapshotFile } from "./snapshot.ts";
import { SOURCE_ARGS, sourceArgs, sourceFlags } from "./source-args.ts";

const ARGS = {
  metadata: {
    type: "string",
    description:
      "Read a GeneratorMetadata document (- for stdin) and print one file on stdout",
    valueHint: "path|-",
  },
  emit: {
    type: "string",
    description: `With --metadata, the file to print: ${EMITS.join(", ")}. Defaults to schema`,
    valueHint: "file",
  },
  "out-dir": {
    type: "string",
    description:
      "With --metadata, write every generated file into this directory instead of printing one",
    valueHint: "dir",
  },
  only: {
    type: "string",
    description: `Tasks to run: ${GEN_TASKS.join(", ")}. Defaults to gen.tasks, or every task the config sets up`,
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
  watch: {
    type: "boolean",
    description:
      "Run again whenever the schema, the config file or a task's input changes",
  },
  interval: {
    type: "string",
    description:
      "Milliseconds between checks in --watch. Defaults to gen.watchInterval, then 2000",
    valueHint: "ms",
  },
  ...SOURCE_ARGS,
} as const;

/**
 * Reads the schema when it may have changed. Returns the new change marker (the
 * catalog fingerprint, or the snapshot itself when the source has none) and the
 * snapshot, or no snapshot when the fingerprint still matches `last`.
 */
async function poll(
  options: GenOptions,
  db: IntrospectionSource | undefined,
  last: string,
): Promise<{ marker: string; snapshot?: Snapshot }> {
  const fingerprint = db
    ? await catalogFingerprint(db.queryable).catch(() => undefined)
    : undefined;

  if (fingerprint !== undefined && fingerprint === last) {
    return { marker: last };
  }

  const snapshot = await loadSnapshot(
    options.config,
    options.env,
    options,
    undefined,
    db ? () => Promise.resolve(db) : undefined,
  );

  const marker = fingerprint ?? JSON.stringify(snapshot);

  return marker === last ? { marker } : { marker, snapshot };
}

/**
 * Runs `tasks`: `types` through `runGen`, then the steps after it. Without
 * `types` in the list, `snapshot` is unused.
 */
async function runTasks(
  tasks: readonly GenTask[],
  options: GenOptions,
): Promise<CommandResult> {
  const types = tasks.includes("types")
    ? [
        {
          task: "types" as const,
          result: await runGen(options).catch(failedResult),
        },
      ]
    : [];

  return combineResults(
    await runSteps(
      tasks,
      {
        config: options.config,
        env: options.env,
        check: options.check,
        dryRun: options.dryRun === true,
        paint: options.paint ?? plain,
      },
      types,
    ),
  );
}

/**
 * Runs the tasks again whenever the schema, the config file or a task's input
 * (the spec entry and its overlays, the seed entry) changes. A database source
 * keeps one connection open and polls the catalog fingerprint, so an unchanged
 * schema costs one small query per interval; a source without a fingerprint is
 * introspected each time and compared. The schema is read only when `types`
 * runs. A changed config file is loaded again and forces a run; a changed input
 * reruns the steps after `types`. A failed run is retried every interval until
 * it succeeds.
 */
async function watch(
  initial: GenOptions,
  requested: readonly GenTask[] | undefined,
  interval: number,
  context: CliContext,
): Promise<CommandResult> {
  let options = initial;
  let last = "";
  let inputs = "";
  let db: IntrospectionSource | undefined;

  const closeDb = async (): Promise<void> => {
    await db?.close().catch(() => undefined);
    db = undefined;
  };

  const tick = async (): Promise<CommandResult | undefined> => {
    const tasks = selectTasks(options.config, requested);
    const current = await stampFiles(stepInputs(options.config, tasks));
    let polled: { marker: string; snapshot?: Snapshot } | undefined;

    if (tasks.includes("types")) {
      try {
        db ??=
          snapshotFile(options.config, options) === undefined
            ? await openSource(options.config, options.env, options)
            : undefined;
        polled = await poll(options, db, last);
      } catch (cause) {
        await closeDb();
        throw cause;
      }
    }

    const run: readonly GenTask[] | undefined = polled?.snapshot
      ? tasks
      : current === inputs
        ? undefined
        : tasks.filter((task) => task !== "types");

    if (!run || run.length === 0) {
      return undefined;
    }

    const result = await runTasks(run, {
      ...options,
      ...(polled?.snapshot ? { snapshot: polled.snapshot } : {}),
    });

    if (result.code === 0) {
      last = polled?.marker ?? last;
      inputs = current;
    }

    return result;
  };

  try {
    return await watchLoop({
      interval,
      context,
      reload: async (config) => {
        options = { ...options, config };
        last = "";
        inputs = "";
        await closeDb();
      },
      tick,
    });
  } finally {
    await closeDb();
  }
}

export const genCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("gen"),
  args: ARGS,
  lists: ["only"],
  completions: { only: () => GEN_TASKS },
  run: async (args, context) => {
    checkMetadataFlags({
      ...(args.metadata === undefined ? {} : { metadata: args.metadata }),
      ...(args.emit === undefined ? {} : { emit: args.emit }),
      ...(args["out-dir"] === undefined ? {} : { out: args["out-dir"] }),
      check: args.check === true,
      json: context.json,
      conflicting: [
        ...(args.watch === true ? ["--watch"] : []),
        ...sourceFlags(args),
      ],
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
        ...(args.emit === undefined ? {} : { emit: args.emit }),
        ...(args["out-dir"] === undefined ? {} : { out: args["out-dir"] }),
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
      env: context.env,
      check: args.check === true,
      dryRun: args["dry-run"] === true,
      force: args.force === true,
      paint: context.paint,
      ...(await sourceArgs(args, context.io)),
      ...(context.signal ? { signal: context.signal } : {}),
      cache: true,
    };

    const interval = parseInterval(
      args.interval,
      context.config.gen.watchInterval,
    );

    if (typeof interval === "string") {
      throw new CliError("usage", interval);
    }

    return args.watch === true
      ? watch(options, requested, interval, context)
      : context.log.progress("Generating from the schema", () =>
          runTasks(tasks, options),
        );
  },
});
