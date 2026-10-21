import type { BlockOf } from "../define-block.ts";
import type { VersionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { versionsEvents } from "./events.ts";
import { versionsSqlOptions } from "./options.ts";
import { versionsSection } from "./section.ts";
import { createVersions } from "./versions.ts";

/** The `versions` block's manifest (ADR 0029). */
export const versionsBlock: BlockOf<
  "versions",
  typeof createVersions,
  VersionsEvents,
  Record<never, never>,
  never,
  { readonly versions: typeof versionsSection }
> = defineBlock({
  name: "versions",
  sql: ["versions"],
  options: { versions: versionsSqlOptions },
  events: versionsEvents,
  create: createVersions,
  sections: { versions: versionsSection },
  category: "content",
  recipes: ["version-history", "record-history", "subject-timeline"],
});
