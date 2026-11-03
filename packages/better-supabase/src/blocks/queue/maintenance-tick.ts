import type { BlockSchedule } from "../../core/automation.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { Result } from "../../core/result.ts";
import type { BlockTickRun, ScheduledBlock } from "./block-schedules.ts";

import { err, ok, toDbError } from "../../core/result.ts";

/** The block name of the maintenance timer in `blockTickHandler` keys. */
export const MAINTENANCE_TIMER_BLOCK = "housekeeping";

/**
 * The timer that runs `better_supabase.maintenance()` from the `block_ticks`
 * queue. Add it to the list you pass to `blockSchedules` when pg_cron is not
 * available, and register `"housekeeping.maintenance": maintenanceTick(...)` in
 * `blockTickHandler`.
 */
export const maintenanceTimer: ScheduledBlock & {
  readonly schedules: readonly BlockSchedule[];
} = {
  name: MAINTENANCE_TIMER_BLOCK,
  schedules: [
    {
      name: "maintenance",
      cron: "*/5 * * * *",
      runs: "maintenance()",
      description:
        "Runs the due purges and expiries when pg_cron does not run them.",
    },
  ],
};

/** What `maintenanceTick` returns when it ran. */
export interface MaintenanceTickResult {
  /** `pg_cron` when pg_cron already runs the dispatcher, so the tick skipped. */
  readonly scheduler: "pg_cron" | "none";
  /** The jobs that ran, as `maintenance()` returned them. */
  readonly jobs: readonly unknown[];
}

/** Options for `maintenanceTick`. */
export interface MaintenanceTickOptions {
  /** The schema of the `housekeeping` module. Defaults to `better_supabase`. */
  readonly schema?: string;
  /** Run the tick even when pg_cron has the dispatcher registered. */
  readonly force?: boolean;
}

/**
 * The `block_ticks` handler that runs `maintenance()` when pg_cron does not. It
 * asks `maintenance_scheduler()` first and skips the run when pg_cron is
 * registered, so a database with both never runs the jobs twice. Call it with a
 * service-role transport, such as `rpcTransport(admin)`.
 */
export function maintenanceTick(
  transport: BlockTransport,
  options: MaintenanceTickOptions = {},
): BlockTickRun {
  const schema = options.schema ?? "better_supabase";

  return async (): Promise<Result<MaintenanceTickResult>> => {
    try {
      const scheduler =
        (await transport.call(schema, "maintenance_scheduler", {})) ===
        "pg_cron"
          ? "pg_cron"
          : "none";

      if (scheduler === "pg_cron" && options.force !== true) {
        return ok({ scheduler, jobs: [] });
      }

      const jobs = await transport.call(schema, "maintenance", {});

      return ok({ scheduler, jobs: Array.isArray(jobs) ? jobs : [] });
    } catch (error) {
      return err(toDbError(error));
    }
  };
}
