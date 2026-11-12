import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createTimeline } from "./timeline.ts";

/** The `timeline` block's manifest (ADR 0029, ADR 0063). */
export const timelineBlock: BlockOf<"timeline", typeof createTimeline> =
  defineBlock({
    name: "timeline",
    sql: ["timeline"],
    create: createTimeline,
    category: "collaboration",
    entities: { timeline_entry: { mutability: "read-only" } },
    description:
      "A timeline_entries feed that activitySink() fills from outbox events, filtered by can_subject and joined with the subject's audit entries, notification deliveries and workflow runs when subjects, audit, notifications and workflows are installed.",
    recipes: [],
  });
