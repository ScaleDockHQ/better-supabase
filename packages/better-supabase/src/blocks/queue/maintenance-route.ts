import type { BlockTransport } from "../../core/block-transport.ts";
import type { CronCaller, CronOverlap } from "../../core/cron-route.ts";
import type { DbError } from "../../core/errors.ts";
import type { ProblemFormat } from "../../core/problem.ts";
import type { SqlClient } from "../../postgres/executor.ts";
import type { LeaseOptions } from "./lease.ts";

import { cronRoute } from "../../core/cron-route.ts";
import { withLease } from "./lease.ts";
import { maintenanceTick } from "./maintenance-tick.ts";

/** Options for `leaseOverlap`. */
export interface LeaseOverlapOptions extends LeaseOptions {
  /** The lease key. Defaults to `cron:overlap`. */
  readonly key?: string;
  /** Called when taking the lease failed. The run is skipped, not retried. */
  readonly onError?: (error: DbError) => void;
}

/**
 * An overlap guard for `cronRoute` built on `withLease`: a run that finds the
 * lease taken is skipped, and the lease is released when the run ends. A run
 * whose lease call fails is skipped too, so a database outage cannot start two
 * runs at once.
 */
export function leaseOverlap(
  source: SqlClient | BlockTransport,
  options: LeaseOverlapOptions = {},
): CronOverlap {
  const { key = "cron:overlap", onError, ...lease } = options;

  return async (run) => {
    const outcome = await withLease(source, key, run, lease);

    if (!outcome.ok) {
      onError?.(outcome.error);

      return null;
    }

    return outcome.data.acquired ? outcome.data.value : null;
  };
}

/** Options for `maintenanceRoute`. */
export interface MaintenanceRouteOptions {
  /** The bearer token the cron caller sends, such as `process.env.CRON_SECRET`. */
  readonly secret: string | undefined;
  /** A service-role transport, such as `rpcTransport(admin)`. */
  readonly transport: BlockTransport;
  /** The schema of the `housekeeping` module. Defaults to `better_supabase`. */
  readonly schema?: string;
  /** Run even when pg_cron has the dispatcher registered. */
  readonly force?: boolean;
  /** Skip a run stamped more than this many seconds ago. Defaults to 600. */
  readonly maxLateSeconds?: number;
  /**
   * Seconds the overlap lease holds. Defaults to 300. `maintenance()` already
   * refuses a second concurrent call in the database, so the lease only saves
   * the round trip. Pass `false` to turn it off.
   */
  readonly leaseSeconds?: number | false;
  readonly caller?: CronCaller;
  readonly problem?: ProblemFormat;
  readonly onError?: (error: DbError) => void;
}

/**
 * A cron route that runs `better_supabase.maintenance()` when pg_cron does not,
 * for Vercel Cron or a Vercel schedule. It skips a run that arrives late and a
 * run that overlaps another one, and answers 500 with the `DbError` when the
 * call fails so the platform retries.
 */
export function maintenanceRoute(
  options: MaintenanceRouteOptions,
): (request: Request) => Promise<Response> {
  const tick = maintenanceTick(options.transport, {
    ...(options.schema === undefined ? {} : { schema: options.schema }),
    ...(options.force === undefined ? {} : { force: options.force }),
  });

  return cronRoute(
    {
      name: "maintenance",
      secret: options.secret,
      problem: options.problem,
      caller: options.caller,
      maxLateSeconds: options.maxLateSeconds ?? 600,
      overlap:
        options.leaseSeconds === false
          ? undefined
          : leaseOverlap(options.transport, {
              key: "maintenance",
              seconds: options.leaseSeconds ?? 300,
              ...(options.schema === undefined
                ? {}
                : { schema: options.schema }),
              ...(options.onError === undefined
                ? {}
                : { onError: options.onError }),
            }),
    },
    async () => {
      const ran = await tick();

      if (!ran.ok) {
        const { error } = ran;

        options.onError?.(error);

        return Response.json({ error }, { status: 500 });
      }

      return Response.json(ran.data);
    },
  );
}
