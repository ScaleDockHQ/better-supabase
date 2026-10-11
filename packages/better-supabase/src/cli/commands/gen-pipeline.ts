import { existsSync } from "node:fs";
import { resolve } from "node:path";

import type { GenTask, ResolvedConfig } from "../../config/index.ts";
import type { CliEnv } from "../env.ts";
import type { CommandResult } from "../io.ts";
import type { Paint } from "../style.ts";

import { GEN_TASKS, isGenTask } from "../names.ts";
import { envStep } from "./env.ts";
import { scaffoldStep } from "./scaffold.ts";
import { seedStep } from "./seed.ts";
import { runSpec } from "./spec.ts";
import { syncSql } from "./sql.ts";

/** One task's result in a `gen` run. */
export interface TaskResult {
  readonly task: GenTask;
  readonly result: CommandResult;
}

export interface StepOptions {
  readonly config: ResolvedConfig;
  readonly env: CliEnv;
  readonly check: boolean;
  readonly paint: Paint;
}

/** Tasks run in this order whatever order the config lists them in. */
const ORDER: ReadonlyMap<GenTask, number> = new Map(
  GEN_TASKS.map((task, index) => [task, index]),
);

/** Checks `--tasks` names. Returns an error message for an unknown one. */
export function parseTasks(
  names: readonly string[],
): readonly GenTask[] | string {
  const unknown = names.filter((task) => !isGenTask(task));
  if (unknown.length > 0)
    return `Unknown gen task ${unknown.map((task) => `"${task}"`).join(", ")}. Tasks: ${GEN_TASKS.join(", ")}.`;
  return names.filter(isGenTask);
}

/**
 * The tasks `gen` runs, in pipeline order: `--tasks`, then `gen.tasks`, then
 * every task the config sets up.
 */
export function selectTasks(
  config: ResolvedConfig,
  requested: readonly GenTask[] | undefined,
): readonly GenTask[] {
  const named = requested ?? config.gen.tasks;
  if (named === undefined) return configuredTasks(config);
  return [...new Set(named)].toSorted(
    (a, b) => (ORDER.get(a) ?? 0) - (ORDER.get(b) ?? 0),
  );
}

/** Every task the config sets up. `env` runs only when a task list names it. */
export function configuredTasks(config: ResolvedConfig): readonly GenTask[] {
  const exists = (path: string): boolean =>
    existsSync(resolve(config.root, path));
  const configured: Readonly<Record<GenTask, () => boolean>> = {
    types: () => true,
    sql: () =>
      config.sql.moduleNames.length > 0 ||
      config.realtime.policies !== undefined,
    spec: () => exists(config.specs.entry),
    seed: () => exists(config.seed.entry),
    scaffold: () => config.scaffold.api !== undefined,
    env: () => false,
  };
  return GEN_TASKS.filter((task) => configured[task]());
}

/** Files the steps after `types` read, so `gen --watch` reruns them when one changes. */
export function stepInputs(
  config: ResolvedConfig,
  tasks: readonly GenTask[],
): string[] {
  const at = (path: string): string => resolve(config.root, path);
  const inputs: Readonly<Record<GenTask, () => readonly string[]>> = {
    types: () => [],
    sql: () => [],
    spec: () => [
      at(config.specs.entry),
      ...config.specs.outputs.flatMap((output) =>
        (output.overlays ?? []).map(at),
      ),
    ],
    seed: () => [at(config.seed.entry)],
    scaffold: () => [],
    env: () => [],
  };
  return tasks.flatMap((task) => inputs[task]());
}

const STEPS: Readonly<
  Record<
    Exclude<GenTask, "types">,
    (options: StepOptions) => Promise<CommandResult>
  >
> = {
  sql: ({ config, check, paint }) => syncSql(config, check, paint),
  spec: ({ config, check }) =>
    runSpec({
      config,
      action: check ? "check" : "emit",
      filter: {},
      failOn: config.specs.failOn,
      cache: true,
      ...(config.specs.manifest === undefined
        ? {}
        : { manifest: config.specs.manifest }),
    }),
  seed: ({ config, check, env }) => seedStep(config, check, env),
  scaffold: ({ config, check }) => scaffoldStep(config, check),
  env: async ({ config, check, env }) =>
    check
      ? {
          code: 0,
          output: "Skipped: env writes local keys, so --check leaves it out.",
        }
      : envStep(config, env),
};

/**
 * Runs the steps after `types`, in order. A write run stops at the first
 * failure, since later steps read what earlier ones wrote; `--check` runs
 * every step so it reports everything that is out of date.
 */
export async function runSteps(
  tasks: readonly GenTask[],
  options: StepOptions,
  previous: readonly TaskResult[] = [],
): Promise<TaskResult[]> {
  const results = [...previous];
  for (const task of tasks) {
    if (task === "types") continue;
    if (!options.check && results.some(({ result }) => result.code !== 0))
      break;
    const result = await STEPS[task](options).catch(
      (cause: unknown): CommandResult => ({
        code: 1,
        error: cause instanceof Error ? cause.message : String(cause),
      }),
    );
    results.push({ task, result });
  }
  return results;
}

const indent = (text: string): string =>
  text
    .split("\n")
    .map((line) => (line === "" ? line : `  ${line}`))
    .join("\n");

/**
 * One result for the run. A single task returns its own result unchanged;
 * several tasks get a section each, the first failing exit code and every
 * error.
 */
export function combineResults(results: readonly TaskResult[]): CommandResult {
  const [only] = results;
  if (results.length === 1 && only) return only.result;
  const output = results
    .flatMap(({ task, result }) =>
      result.output
        ? [`[${task}]\n${indent(result.output)}`]
        : [`[${task}] done`],
    )
    .join("\n");
  const errors = results.flatMap(({ task, result }) =>
    result.error ? [`[${task}] ${result.error}`] : [],
  );
  const failed = results.find(({ result }) => result.code !== 0);
  return {
    code: failed?.result.code ?? 0,
    output,
    ...(errors.length > 0 ? { error: errors.join("\n") } : {}),
    data: {
      tasks: Object.fromEntries(
        results.map(({ task, result }) => [
          task,
          {
            code: result.code,
            ...(result.data === undefined ? {} : { data: result.data }),
          },
        ]),
      ),
    },
  };
}
