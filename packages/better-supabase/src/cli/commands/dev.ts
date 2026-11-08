import { readdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import type { GenTask } from "../../config/index.ts";
import type { AnyCommand, CliContext } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { GenOptions } from "../gen/run.ts";
import type { IntrospectionSource } from "../introspect/source.ts";
import type { Snapshot } from "../introspect/types.ts";

import { defineCliCommand, list } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";
import { GEN_TASKS } from "../names.ts";
import { fileWaker, parseInterval, stampFiles, watchLoop } from "../watch.ts";
import { parseTasks, selectTasks, stepInputs } from "./gen-pipeline.ts";
import { poll, runTasks } from "./gen-tasks.ts";
import { openSource, snapshotFile } from "./snapshot.ts";
import { SOURCE_ARGS, sourceArgs } from "./source-args.ts";

const ARGS = {
  only: {
    type: "string",
    description: `Tasks to run: ${GEN_TASKS.join(", ")}. Defaults to gen.tasks, or every task the config sets up`,
    valueHint: "list",
  },
  force: {
    type: "boolean",
    description:
      "Overwrite a file at a generated path that the CLI did not write",
  },
  interval: {
    type: "string",
    description:
      "Milliseconds between checks when no file event arrives. Defaults to gen.watchInterval, then 2000",
    valueHint: "ms",
  },
  ...SOURCE_ARGS,
} as const;

/**
 * The module files better-supabase writes; the loop never reacts to its own
 * output.
 */
const OWN_FILE = /(?:^|\/)900_better_supabase_/u;

/**
 * A stamp of the app's schema files (`supabase/schemas/**.sql`), so an edit to
 * one reruns the SQL task. Module files are left out: the run writes them.
 */
async function schemaStamp(root: string): Promise<string> {
  const folder = resolve(root, "supabase", "schemas");

  const names = await readdir(folder, { recursive: true }).catch(
    (): string[] => [],
  );

  return stampFiles(
    names
      .filter((name) => name.endsWith(".sql") && !OWN_FILE.test(name))
      .toSorted()
      .map((name) => resolve(folder, name)),
  );
}

/** What a change in one of these places can affect, for the waker. */
function watchedPaths(
  options: GenOptions,
  tasks: readonly GenTask[],
  configFile: string | undefined,
): string[] {
  return [
    ...(configFile ? [configFile] : []),
    resolve(options.config.root, "supabase", "schemas"),
    ...stepInputs(options.config, tasks).map((file) => dirname(file)),
  ];
}

/**
 * Runs the tasks again whenever something they read changes, and prints `Ready`
 * on stderr once the first run has finished. A file event starts the next round
 * at once, and the interval is the fallback for a platform or a database source
 * that raises none. A database source keeps one connection open and polls the
 * catalog fingerprint, so an unchanged schema costs one small query; the schema
 * is read only when `types` runs. A changed config file is loaded again and
 * forces a full run. A changed schema file or task input runs the steps after
 * `types`, which render only what the caches miss. A failed run is reported
 * once and retried every interval until it succeeds.
 */
async function develop(
  initial: GenOptions,
  requested: readonly GenTask[] | undefined,
  interval: number,
  context: CliContext,
): Promise<CommandResult> {
  let options = initial;
  let last = "";
  let inputs = "";
  let db: IntrospectionSource | undefined;
  let ready = false;

  const closeDb = async (): Promise<void> => {
    await db?.close().catch(() => undefined);
    db = undefined;
  };

  const waker = fileWaker(
    watchedPaths(
      options,
      selectTasks(options.config, requested),
      context.configFile,
    ),
    context.signal,
  );

  const tick = async (): Promise<CommandResult | undefined> => {
    const tasks = selectTasks(options.config, requested);

    const current = JSON.stringify([
      await stampFiles(stepInputs(options.config, tasks)),
      await schemaStamp(options.config.root),
    ]);

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

      if (!ready) {
        ready = true;
        context.log.info("Ready");
      }
    }

    return result;
  };

  try {
    return await watchLoop({
      interval,
      context,
      wait: (ms) => waker.wait(ms),
      reload: async (config) => {
        options = { ...options, config };
        last = "";
        inputs = "";
        await closeDb();
      },
      tick,
    });
  } finally {
    waker.close();
    await closeDb();
  }
}

export const devCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("dev"),
  args: ARGS,
  lists: ["only"],
  completions: { only: () => GEN_TASKS },
  run: async (args, context) => {
    const requested =
      args.only === undefined ? undefined : parseTasks(list(args.only));

    if (typeof requested === "string") {
      throw new CliError("usage", requested);
    }

    if (selectTasks(context.config, requested).length === 0) {
      throw new CliError("usage", "--only names no task.");
    }

    const interval = parseInterval(
      args.interval,
      context.config.gen.watchInterval,
    );

    if (typeof interval === "string") {
      throw new CliError("usage", interval);
    }

    const options: GenOptions = {
      config: context.config,
      ...(context.configFile ? { configFile: context.configFile } : {}),
      env: context.env,
      check: false,
      dryRun: false,
      force: args.force === true,
      paint: context.paint,
      ...(await sourceArgs(args, context.io)),
      ...(context.signal ? { signal: context.signal } : {}),
      cache: true,
    };

    return develop(options, requested, interval, context);
  },
});
