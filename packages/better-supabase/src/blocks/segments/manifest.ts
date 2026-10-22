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
});
