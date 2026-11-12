import type { BlockOf } from "../define-block.ts";
import type { SecurityEventsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { securityEventsEvents } from "./events.ts";
import { securityEventsSqlOptions } from "./options.ts";
import { createSecurityEvents } from "./security-events.ts";

/** The `security-events` block's manifest (ADR 0029). */
export const securityEventsBlock: BlockOf<
  "security-events",
  typeof createSecurityEvents,
  SecurityEventsEvents
> = defineBlock({
  name: "security-events",
  sql: ["security-events"],
  options: { "security-events": securityEventsSqlOptions },
  events: securityEventsEvents,
  create: createSecurityEvents,
  category: "developer",
  entities: {
    ssf_stream: {
      mutability: "editable",
      emits: { create: true, update: false, delete: true },
    },
  },
  description:
    "OpenID Shared Signals streams: stream configuration and status per receiver, push delivery through a webhooks-out endpoint with format 'set' (RFC 8935), a poll queue (RFC 8936), SETs held while a stream is paused, and a receiver replay table. Only the service role calls it; createSsfTransmitter() and createSsfReceiver() in better-supabase/blocks/security-events mint and verify the SETs.",
});
