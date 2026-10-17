import { Hono } from "hono";

import { outbox } from "@/lib/outbox";

const relay = outbox.relayRoute({
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

/**
 * Relays each registered consumer's events. Mount it with
 * `app.route("/outbox", outboxRoutes)` and call it from a cron that sends
 * `Authorization: Bearer <CRON_SECRET>`.
 */
export const outboxRoutes = new Hono().get("/", (c) => relay(c.req.raw));
