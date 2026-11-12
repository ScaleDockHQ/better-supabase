import type { BlockOf } from "../define-block.ts";
import type { TimeEntriesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { timeEntriesEvents } from "./events.ts";
import { timeEntriesSqlOptions } from "./options.ts";
import { createTimeEntries } from "./time-entries.ts";

/** The `time-entries` block's manifest (ADR 0029). */
export const timeEntriesBlock: BlockOf<
  "time-entries",
  typeof createTimeEntries,
  TimeEntriesEvents
> = defineBlock({
  name: "time-entries",
  sql: ["time-entries"],
  options: { "time-entries": timeEntriesSqlOptions },
  events: timeEntriesEvents,
  create: createTimeEntries,
  category: "people",
  entities: {
    time_entry: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
    timesheet: { mutability: "state-machine", emits: { create: false } },
  },
  description:
    "Time entries with one running timer per member and no overlaps, on any record, billable with a rate. Weekly timesheets go through approvals, and a submitted or approved week is locked.",
  recipes: ["timesheet"],
});
