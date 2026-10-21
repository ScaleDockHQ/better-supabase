import "server-only";
import { outbox } from "@/lib/outbox";

/**
 * Relays each registered consumer's events. Call it from a cron, such as `{
 * "path": "/api/outbox", "schedule": "* * * * *" }` in `vercel.json`, which
 * sends `Authorization: Bearer <CRON_SECRET>`.
 */
export const GET = outbox.relayRoute({
  secret: process.env.CRON_SECRET,
  consumers: {
    log: (events) => {
      for (const event of events) {
        console.info(event.type, event.id);
      }
    },
  },
  onError: (error, consumer) => {
    console.error(consumer, error.message);
  },
});
