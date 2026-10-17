import type { GenTask } from "../../config/index.ts";
import type { AnyCommand, CliContext } from "../command.ts";
import type { IntrospectionSource } from "../introspect/source.ts";
import type { Snapshot } from "../introspect/types.ts";
import type { CommandResult } from "../io.ts";

import { defineCliCommand, list } from "../command.ts";
import { errorText, failedResult } from "../errors.ts";
import { runMetadataGen, EMITS } from "../gen/metadata.ts";
import { type GenOptions, runGen } from "../gen/run.ts";
import { catalogFingerprint } from "../introspect/fingerprint.ts";
import { GEN_TASKS } from "../names.ts";
import { withSpinner } from "../prompts.ts";
import { painter, plain } from "../style.ts";
import {
  modifiedTime,
  onceReporter,
  parseInterval,
  sleep,
  stampFiles,
} from "../watch.ts";
import {
  combineResults,
  runSteps,
  parseTasks,
  selectTasks,
  stepInputs,
} from "./gen-pipeline.ts";
import { loadSnapshot, openSource, snapshotFile } from "./snapshot.ts";
import { SOURCE_ARGS, sourceArgs } from "./source-args.ts";

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
  out: {
    type: "string",
    description:
      "With --metadata, write every generated file into this directory instead of printing one",
    valueHint: "dir",
  },
  tasks: {
    type: "string",
    description: `Tasks to run: ${GEN_TASKS.join(", ")}. Defaults to gen.tasks, or every task the config sets up`,
    valueHint: "list",
  },
  check: {
    type: "boolean",
    description: "Fail when a generated file is out of date",
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
 * catalog fingerprint, or the snapshot itself when the source has none) and
 * the snapshot, or no snapshot when the fingerprint still matches `last`.
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
        paint: options.paint ?? plain,
      },
      types,
    ),
  );
}

/**
 * Runs the tasks again whenever the schema, the config file or a task's
 * input (the spec entry and its overlays, the seed entry) changes. A
 * database source keeps one connection open and polls the catalog
 * fingerprint, so an unchanged schema costs one small query per interval; a
 * source without a fingerprint is introspected each time and compared. The
 * schema is read only when `types` runs. A changed config file is loaded
 * again and forces a run; a changed input reruns the steps after `types`. A
 * failed run is retried every interval until it succeeds, and the same
 * error is printed once.
 */
async function watch(
  initial: GenOptions,
  requested: readonly GenTask[] | undefined,
  interval: number,
  { io, signal, configFile, reloadConfig }: CliContext,
): Promise<CommandResult> {
  let options = initial;
  let last = "";
  let inputs = "";
  const fresh = onceReporter();
  let stamp = await modifiedTime(configFile);
  let db: IntrospectionSource | undefined;
  const aborted = (): boolean => signal?.aborted ?? false;

  const report = (message: string): void => {
    if (fresh(message)) {
      io.stderr(`${message}\n`);
    }
  };

  const closeDb = async (): Promise<void> => {
    await db?.close().catch(() => undefined);
    db = undefined;
  };

  try {
    while (!aborted()) {
      const changed = await modifiedTime(configFile);

      if (reloadConfig && changed !== stamp) {
        try {
          options = { ...options, config: await reloadConfig() };
          stamp = changed;
          last = "";
          inputs = "";
          await closeDb();
        } catch (cause) {
          report(errorText(cause));
          await sleep(interval, signal);
          continue;
        }
      }

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
          report(errorText(cause));
          await closeDb();
          await sleep(interval, signal);
          continue;
        }
      }

      const run: readonly GenTask[] | undefined = polled?.snapshot
        ? tasks
        : current === inputs
          ? undefined
          : tasks.filter((task) => task !== "types");

      const result =
        run && run.length > 0
          ? await runTasks(run, {
              ...options,
              ...(polled?.snapshot ? { snapshot: polled.snapshot } : {}),
            })
          : undefined;

      if (result && result.code !== 0) {
        report(result.error ?? `gen exited with code ${result.code}`);
      } else {
        if (result?.output) {
          io.stdout(`${result.output}\n`);
        }

        if (polled) {
          last = polled.marker;
        }

        inputs = current;
        fresh("");
      }

      await sleep(interval, signal);
    }
  } finally {
    await closeDb();
  }

  return { code: 0 };
}

export const genCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "gen",
    description:
      "Writes the typed client from the database, then every other generated file the config sets up",
  },
  args: ARGS,
  lists: ["tasks"],
  run: async (args, context) => {
    if (args.metadata !== undefined) {
      const conflicting = [
        ...(args.watch === true ? ["--watch"] : []),
        ...(args.snapshot === undefined ? [] : ["--snapshot"]),
        ...(args["db-url-stdin"] === true ? ["--db-url-stdin"] : []),
        ...(args["project-ref"] === undefined ? [] : ["--project-ref"]),
      ];

      if (conflicting.length > 0) {
        return {
          code: 2,
          error: `--metadata reads the schema from the document, so it can't be combined with ${conflicting.join(", ")}`,
        };
      }

      return runMetadataGen({
        config: context.config,
        env: context.env,
        cwd: context.cwd,
        io: context.io,
        metadata: args.metadata,
        check: args.check === true,
        json: context.json,
        paint: painter(context.io.color),
        ...(args.emit === undefined ? {} : { emit: args.emit }),
        ...(args.out === undefined ? {} : { out: args.out }),
      });
    }

    if (args.emit !== undefined || args.out !== undefined) {
      return {
        code: 2,
        error: `${args.emit === undefined ? "--out" : "--emit"} only applies with --metadata`,
      };
    }

    const requested =
      args.tasks === undefined ? undefined : parseTasks(list(args.tasks));

    if (typeof requested === "string") {
      return { code: 2, error: requested };
    }

    const tasks = selectTasks(context.config, requested);

    if (tasks.length === 0) {
      return { code: 2, error: "--tasks names no task." };
    }

    const options: GenOptions = {
      config: context.config,
      env: context.env,
      check: args.check === true,
      paint: painter(context.io.color),
      ...(await sourceArgs(args, context.io)),
      ...(context.signal ? { signal: context.signal } : {}),
      cache: true,
    };

    const interval = parseInterval(
      args.interval,
      context.config.gen.watchInterval,
    );

    if (typeof interval === "string") {
      return { code: 2, error: interval };
    }

    return args.watch === true
      ? watch(options, requested, interval, context)
      : withSpinner(context.io.prompts, "Generating from the schema", () =>
          runTasks(tasks, options),
        );
  },
});
