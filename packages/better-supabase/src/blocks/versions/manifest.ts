import type { BlockOf } from "../define-block.ts";
import type { VersionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { versionsEvents } from "./events.ts";
import { versionsSqlOptions } from "./options.ts";
import { versionsBinding } from "./record-binding.ts";
import { createVersions } from "./versions.ts";

/** The `versions` block's manifest (ADR 0029). */
export const versionsBlock: BlockOf<
  "versions",
  typeof createVersions,
  VersionsEvents,
  Record<never, never>,
  never,
  typeof versionsBinding
> = defineBlock({
  name: "versions",
  sql: ["versions"],
  options: { versions: versionsSqlOptions },
  events: versionsEvents,
  create: createVersions,
  record: versionsBinding,
  category: "database",
  entities: {
    version: {
      mutability: "state-machine",
      emits: { create: true, delete: true },
    },
  },
  description:
    "Numbered snapshots of a subject's content: manual, debounced auto and frozen snapshots, restore through columns or an apply function, and retention.",
  recipes: ["version-history", "record-history", "subject-timeline"],
});
