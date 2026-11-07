import type { GenTask } from "../../config/index.ts";
import type { CommandResult } from "../core/io.ts";
import type { GenOptions } from "../gen/run.ts";
import type { IntrospectionSource } from "../introspect/source.ts";
import type { Snapshot } from "../introspect/types.ts";

import { failedResult } from "../core/errors.ts";
import { runGen } from "../gen/run.ts";
import { catalogFingerprint } from "../introspect/fingerprint.ts";
import { plain } from "../style.ts";
import { combineResults, runSteps } from "./gen-pipeline.ts";
import { loadSnapshot } from "./snapshot.ts";

/**
 * Reads the schema when it may have changed. Returns the new change marker (the
 * catalog fingerprint, or the snapshot itself when the source has none) and the
 * snapshot, or no snapshot when the fingerprint still matches `last`.
 */
export async function poll(
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
export async function runTasks(
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
