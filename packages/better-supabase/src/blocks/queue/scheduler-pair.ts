import type { QueueProvider, ScheduleProvider } from "./backends.ts";

/** The queue providers whose messages live in the database's pgmq queues. */
const DATABASE_QUEUES = new Set(["sql", "transport", "pgmq_public"]);

/**
 * Throws a `TypeError` for a scheduler that can't deliver to the queue: pg_cron
 * enqueues inside the database, and `vercelScheduler` without a bridge
 * publishes to the job's Vercel Queues topic.
 */
export function checkSchedulerPair(
  queue: QueueProvider,
  scheduler: ScheduleProvider,
  custom: boolean,
): void {
  const inDatabase = !custom || DATABASE_QUEUES.has(queue.name);

  if (scheduler.delivers === "sql" && !inDatabase) {
    throw new TypeError(
      `The scheduler "${scheduler.name}" enqueues each run inside the database with pg_cron, which the "${queue.name}" queue never reads. Set blocks.queue.options.scheduler to "drain", pass sqlScheduler(sql, { mode: "drain" }), and call jobs.schedulesRoute from a clock (blocks.queue.options.httpTick or a Vercel schedule)`,
    );
  }

  if (
    scheduler.delivers === "vercel-queues" &&
    !queue.name.startsWith("vercel-queues")
  ) {
    throw new TypeError(
      `The scheduler "${scheduler.name}" publishes each run to the job's Vercel Queues topic, which the "${queue.name}" queue never reads. Pass vercelScheduler(client, { bridge: "bsb_schedules" }) and serve vercelScheduleBridgeRoute(jobs) on that topic`,
    );
  }
}
