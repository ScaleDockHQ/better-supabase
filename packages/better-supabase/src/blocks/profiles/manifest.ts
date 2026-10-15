import type { BlockOf } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createProfiles } from "./profiles.ts";

/** The `profiles` block's manifest (ADR 0029). */
export const profilesBlock: BlockOf<"profiles", typeof createProfiles> =
  defineBlock({
    name: "profiles",
    sql: ["profiles"],
    options: {
      profiles: optionKeys([
        "columnGrants",
        "extraColumns",
        "metadata",
        "mirrorEmail",
        "readPolicy",
        "reservedUsernames",
        "serviceColumns",
        "splitName",
        "syncTrigger",
        "updatable",
        "username",
        "usernameFrom",
        "usernameMaxLength",
        "usernameMinLength",
      ]),
    },
    create: createProfiles,
    category: "foundation",
  });
