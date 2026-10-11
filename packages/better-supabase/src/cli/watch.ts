import { stat } from "node:fs/promises";
import { setTimeout as delay } from "node:timers/promises";

import { CONFIG_DEFAULTS } from "../config/index.ts";

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
