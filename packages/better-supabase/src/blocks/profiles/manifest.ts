import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { profilesSqlOptions } from "./options.ts";
import { createProfiles } from "./profiles.ts";

/** The `profiles` block's manifest (ADR 0029). */
export const profilesBlock: BlockOf<"profiles", typeof createProfiles> =
  defineBlock({
    name: "profiles",
    sql: ["profiles"],
    options: {
      profiles: profilesSqlOptions,
    },
    create: createProfiles,
    category: "foundation",
  });
