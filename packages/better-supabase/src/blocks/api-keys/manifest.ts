import type { BlockOf } from "../define-block.ts";
import type { ApiKeysEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createApiKeys } from "./api-keys.ts";
import { apiKeysEvents } from "./events.ts";

/** The `api-keys` block's manifest (ADR 0029). */
export const apiKeysBlock: BlockOf<
  "api-keys",
  typeof createApiKeys,
  ApiKeysEvents
> = defineBlock({
  name: "api-keys",
  sql: ["api-keys"],
  options: {
    "api-keys": optionKeys(["scopes", "touchInterval", "prefix"]),
  },
  events: apiKeysEvents,
  create: createApiKeys,
  category: "platform",
  recipes: ["api-keys-table"],
});
