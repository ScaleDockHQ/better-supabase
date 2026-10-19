import { stat } from "node:fs/promises";
import { setTimeout as delay } from "node:timers/promises";

import type { ResolvedConfig } from "../config/index.ts";
import type { CliContext } from "./core/command.ts";
import type { CommandResult } from "./core/io.ts";

import { CONFIG_DEFAULTS } from "../config/index.ts";
import { errorText } from "./core/errors.ts";

/** Waits `ms`, and returns early without an error when `signal` aborts. */
export const sleep = (
  ms: number,
  signal: AbortSignal | undefined,
): Promise<void> =>
  delay(ms, undefined, signal ? { signal } : {}).catch(() => undefined);

/** The modification time of `file`, or `undefined` when it is unset or unreadable. */
export const modifiedTime = (
  file: string | undefined,
): Promise<number | undefined> =>
  file
    ? stat(file).then(
        (stats) => stats.mtimeMs,
        () => undefined,
      )
    : Promise.resolve(undefined);

/** One string that changes when any of `files` is added, removed or modified. */
export const stampFiles = async (files: readonly string[]): Promise<string> =>
  JSON.stringify([files, await Promise.all(files.map(modifiedTime))]);

/**
 * A positive number of milliseconds from `--interval`, `gen.watchInterval`
 * or the default, or an error message to print.
 */
export function parseInterval(
  flag: string | number | undefined,
  configured: number | undefined,
): number | string {
  const interval = Number(
    flag ?? configured ?? CONFIG_DEFAULTS.gen.watchInterval,
  );

  return Number.isFinite(interval) && interval > 0
    ? interval
    : `--interval must be a positive number of milliseconds, got "${flag ?? configured}".`;
}

/** Returns `true` the first time it sees `message` after a different one, so a repeating failure prints once. */
export function onceReporter(): (message: string) => boolean {
  let reported = "";

  return (message) => {
    const fresh = message !== "" && message !== reported;
    reported = message;

    return fresh;
  };
}

export interface WatchLoopOptions {
  readonly interval: number;
  readonly context: Pick<
    CliContext,
    "configFile" | "emit" | "reloadConfig" | "signal"
  >;
  /**
   * Takes the config after its file changed and loaded again. A config that
   * fails to load is reported, and loading is retried the next interval.
   */
  readonly reload: (config: ResolvedConfig) => Promise<void> | void;
  /** One round: the result of a run, or `undefined` when nothing changed. A thrown error counts as a failed run. */
  readonly tick: () => Promise<CommandResult | undefined>;
}

/**
 * Runs `tick` every `interval` until the signal aborts, and prints each
 * result through `emit`: the text output, or one NDJSON envelope per run
 * under `--json`. The same failure in a row is printed once.
 */
export async function watchLoop(
  options: WatchLoopOptions,
): Promise<CommandResult> {
  const { interval, context, reload, tick } = options;
  const { configFile, emit, reloadConfig, signal } = context;
  const fresh = onceReporter();
  let stamp = await modifiedTime(configFile);

  const failed = (cause: unknown): CommandResult => ({
    code: 1,
    error: errorText(cause),
  });

  const report = (result: CommandResult): void => {
    if (result.code === 0) {
      fresh("");
      emit(result);
    } else if (fresh(result.error ?? `exited with code ${result.code}`)) {
      emit(result);
    }
  };

  const aborted = (): boolean => signal?.aborted === true;

  while (!aborted()) {
    const changed = await modifiedTime(configFile);

    if (reloadConfig && changed !== stamp) {
      try {
        await reload(await reloadConfig());
        stamp = changed;
      } catch (cause) {
        report(failed(cause));
        await sleep(interval, signal);
        continue;
      }
    }

    const result = await tick().catch(failed);

    if (result) {
      report(result);
    }

    await sleep(interval, signal);
  }

  return { code: 0, streamed: true };
}
