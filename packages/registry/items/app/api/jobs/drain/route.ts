import "server-only";
import { jobs } from "@/lib/jobs";

/**
 * Enqueues due schedules, then drains each queue in `handlers`. Call it from a
 * cron, such as `{ "path": "/api/jobs/drain", "schedule": "* * * * *" }` in
 * `vercel.json`, which sends `Authorization: Bearer <CRON_SECRET>`.
 */
export const GET = jobs.drainRoute({
  secret: process.env.CRON_SECRET,
  budgetMs: 50_000,
  handlers: {},
  onError: (error, job) => {
    console.error(error.message, job?.id);
  },
});
