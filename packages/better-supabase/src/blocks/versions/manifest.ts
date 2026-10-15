import type { BlockOf } from "../define-block.ts";
import type { VersionsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { versionsEvents } from "./events.ts";
import { createVersions } from "./versions.ts";

/** The `versions` block's manifest (ADR 0029). */
export const versionsBlock: BlockOf<
  "versions",
  typeof createVersions,
  VersionsEvents
> = defineBlock({
  name: "versions",
  sql: ["versions"],
  options: {
    versions: optionKeys(["subjects", "keep", "debounce"]),
  },
  events: versionsEvents,
  create: createVersions,
  category: "content",
});
