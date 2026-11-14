import { BLOCK_TICKS_QUEUE } from "./block-schedules.ts";
import { vercelTopicOf } from "./vercel-queue.ts";
import {
  cronGapBelow,
  vercelCronOf,
  vercelScheduleNameOf,
} from "./vercel-schedules.ts";

/** One static schedule in the `schedules` of `vercel.json`. */
export interface VercelStaticSchedule {
  readonly schedule: string;
  readonly jitter?: number;
  readonly path?: string;
  readonly requestMethod?: "GET" | "POST";
  readonly function?: string;
  readonly topic?: string;
}

/** A route a cron calls, such as a block manifest's `workers` entry. */
export interface VercelScheduledWorker {
  readonly name: string;
  readonly path?: string;
  readonly schedule?: string;
}

/** A timer that publishes to the ticks topic, such as `blockSchedules(blocks)`. */
export interface VercelScheduledTimer {
  readonly name: string;
  readonly cron: string;
}

/** A worker run as a private function instead of a public path. */
export interface VercelPrivateFunction {
  /**
   * The source file `functions` in `vercel.json` keys,
   * `src/app/api/jobs/drain/route.ts`.
   */
  readonly source: string;
  /** Its build output path without `.func`, `app/api/jobs/drain/route`. */
  readonly function: string;
}

export interface VercelScheduleConfigOptions {
  /** Path targets: each worker with a `path` and a `schedule`. */
  readonly workers?: readonly VercelScheduledWorker[];
  /**
   * The method of the path targets. Vercel sends `POST` by default; a route
   * that exports only `GET` needs `"GET"`.
   */
  readonly requestMethod?: "GET" | "POST";
  /** Topic targets on `ticks`, one per timer. */
  readonly timers?: readonly VercelScheduledTimer[];
  /**
   * Workers, by name, that run as private functions with a `schedule/v1beta`
   * trigger, so no secret guards them (`drainRoute({ caller: "vercel-schedule"
   * })`).
   */
  readonly private?: Readonly<Record<string, VercelPrivateFunction>>;
  /**
   * The topic the timers publish to: `block_ticks`, which `vercelQueueRoute`
   * reads on Vercel Queues (the default), or the `bridge` topic of
   * `vercelScheduler` on a Supabase queue.
   */
  readonly ticks?: string;
  /** Minutes Vercel spreads each run over, 1 to 15. */
  readonly jitter?: number;
  /**
   * Check the Hobby limits: no cron more frequent than every 15 minutes, and a
   * jitter of 15 or none.
   */
  readonly hobby?: boolean;
}

export interface VercelScheduleConfig {
  /** The `schedule/v1beta` trigger of each private function. */
  readonly functions: {
    readonly [source: string]: {
      readonly experimentalTriggers: readonly [
        { readonly type: "schedule/v1beta" },
      ];
    };
  };
  readonly schedules: { readonly [name: string]: VercelStaticSchedule };
}

const HOBBY_GAP = 15;

/**
 * The `functions` and `schedules` fragments of `vercel.json` for static Vercel
 * schedules: each worker on its path (or a private function), and each block
 * timer as a topic target on `block_ticks`, named `block:<block>.<timer>` in
 * the encoding of `vercelScheduleNameOf`, so `vercelQueueRoute` and the bridge
 * route map a run back to its timer. Merge them into the file next to
 * `vercelQueueTriggers`. Throws a `TypeError` for a cron Vercel can't run and,
 * with `hobby`, for one more frequent than every 15 minutes.
 */
export async function vercelScheduleConfig(
  options: VercelScheduleConfigOptions,
): Promise<VercelScheduleConfig> {
  if (
    options.hobby === true &&
    options.jitter !== undefined &&
    options.jitter !== HOBBY_GAP
  ) {
    throw new TypeError(
      `Hobby runs every schedule with a 15-minute jitter; leave jitter out or set it to 15, not ${String(options.jitter)}`,
    );
  }

  const cronOf = (name: string, cron: string): string => {
    const expression = vercelCronOf(cron);

    const gap =
      options.hobby === true ? cronGapBelow(expression, HOBBY_GAP) : undefined;

    if (gap !== undefined) {
      throw new TypeError(
        `The schedule "${name}" (${cron}) runs every ${String(gap)} minutes; Hobby runs a schedule at most every 15 minutes`,
      );
    }

    return expression;
  };

  const jitter = options.jitter === undefined ? {} : { jitter: options.jitter };

  const functions: Record<string, VercelScheduleConfig["functions"][string]> =
    {};

  const schedules: Record<string, VercelStaticSchedule> = {};
  const topic = vercelTopicOf(options.ticks ?? BLOCK_TICKS_QUEUE);

  for (const worker of options.workers ?? []) {
    if (worker.path === undefined || worker.schedule === undefined) {
      continue;
    }

    const name = await vercelScheduleNameOf(worker.name);
    const target = options.private?.[worker.name];

    if (target === undefined) {
      schedules[name] = {
        schedule: cronOf(worker.name, worker.schedule),
        ...jitter,
        path: worker.path,
        ...(options.requestMethod === undefined
          ? {}
          : { requestMethod: options.requestMethod }),
      };
    } else {
      functions[target.source] = {
        experimentalTriggers: [{ type: "schedule/v1beta" }],
      };
      schedules[name] = {
        schedule: cronOf(worker.name, worker.schedule),
        ...jitter,
        function: target.function,
      };
    }
  }

  for (const timer of options.timers ?? []) {
    schedules[await vercelScheduleNameOf(timer.name)] = {
      schedule: cronOf(timer.name, timer.cron),
      ...jitter,
      topic,
    };
  }

  return { functions, schedules };
}
