import type { BlockOf } from "../define-block.ts";
import type { SegmentsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { segmentsEvents } from "./events.ts";
import { segmentsSqlOptions } from "./options.ts";
import { segmentInputSchema } from "./schemas.ts";
import { createSegments } from "./segments.ts";

/** The `segments` block's manifest (ADR 0029). */
export const segmentsBlock: BlockOf<
  "segments",
  typeof createSegments,
  SegmentsEvents
> = defineBlock({
  name: "segments",
  sql: ["segments"],
  options: { segments: segmentsSqlOptions },
  events: segmentsEvents,
  schemas: { segment: { input: segmentInputSchema } },
  create: createSegments,
  category: "crm",
  entities: {
    segment: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
  },
  concerns: ["lifecycle"],
  description:
    "Saved filters over a subject type, such as companies in a region or deals over a size: the matching records materialized as members, refreshed on demand or from a cron, with an event when a record enters or leaves.",
});
