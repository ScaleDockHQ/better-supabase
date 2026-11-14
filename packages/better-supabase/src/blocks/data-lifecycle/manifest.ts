import type { BlockOf } from "../define-block.ts";
import type { DataLifecycleEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDataLifecycle } from "./data-lifecycle.ts";
import { dataLifecycleEvents } from "./events.ts";
import { dataLifecycleSqlOptions } from "./options.ts";

/** The `data-lifecycle` block's manifest (ADR 0029). */
export const dataLifecycleBlock: BlockOf<
  "data-lifecycle",
  typeof createDataLifecycle,
  DataLifecycleEvents
> = defineBlock({
  name: "data-lifecycle",
  sql: ["data-lifecycle"],
  options: { "data-lifecycle": dataLifecycleSqlOptions },
  events: dataLifecycleEvents,
  create: createDataLifecycle,
  category: "admin",
  entities: {
    data_export: { mutability: "state-machine", emits: { create: false } },
    organization: { mutability: "state-machine" },
    legal_hold: { mutability: "state-machine" },
    data_subject_request: {
      mutability: "state-machine",
      emits: { create: false },
      personalData: ["requester", "details"],
      subjectColumn: "subjectId",
      erase: "keep",
      retention: "audit",
      legalHold: true,
    },
  },
  description:
    "Data exports per user or organization from every installed module's tables and the app's, written to a private bucket by the app's export job, and organization deletion with a grace period that disables the tenant before a purge job deletes its rows.",
  recipes: ["data-export-delete"],
});
