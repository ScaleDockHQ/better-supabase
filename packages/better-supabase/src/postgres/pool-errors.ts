import type { EventHub } from "../core/events.ts";

import { mapDbError } from "../core/errors.ts";
import { errorEvent } from "../core/events.ts";
import { consoleLogger, type Logger } from "../core/logger.ts";
import { toDbError } from "../core/result.ts";
import { fromPgError } from "./pg-error.ts";

/** A pool that reports errors of its idle connections, as `pg.Pool` does. */
export interface PoolErrorSource {
  on?(event: "error", listener: (error: Error) => void): unknown;
}

export interface PoolErrorOptions {
  /** `betterSupabase.events`: idle-connection errors arrive as `error` events. */
  readonly events?: EventHub;
  /** Where the error goes without `error` handlers. Defaults to the console. */
  readonly logger?: Logger;
}

/**
 * Listens for errors on idle pooled connections, such as a server restart or
 * an ended session. `pg.Pool` emits them as an `error` event, and Node exits
 * on an `error` event nobody listens to. The listener reports the error and
 * never throws.
 */
export function watchPoolErrors(
  pool: PoolErrorSource,
  options: PoolErrorOptions,
): void {
  pool.on?.("error", (cause) => {
    try {
      const raw = fromPgError(cause);
      const error = raw ? mapDbError(raw, []) : toDbError(cause);

      if (options.events?.has("error")) {
        options.events.emit("error", errorEvent(error));

        return;
      }

      (options.logger ?? options.events?.logger ?? consoleLogger).error(
        "an idle Postgres connection failed",
        { error },
      );
    } catch {
      // A logger that throws must not turn the pool's error into a crash.
    }
  });
}
