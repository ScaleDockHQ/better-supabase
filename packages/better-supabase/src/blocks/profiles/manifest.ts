import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { profilesSqlOptions } from "./options.ts";
import { createProfiles } from "./profiles.ts";

/** The `profiles` block's manifest (ADR 0029). */
export const profilesBlock: BlockOf<"profiles", typeof createProfiles> =
  defineBlock({
    name: "profiles",
    sql: ["profiles"],
    options: { profiles: profilesSqlOptions },
    create: createProfiles,
    category: "tenancy",
    entities: { profile: { mutability: "read-only", offline: true } },
    description:
      "A profile per user, created on sign-up from auth metadata with a unique username, an email mirror, column-level update grants and a guard on columns the service owns.",
    recipes: ["profile-form"],
  });
