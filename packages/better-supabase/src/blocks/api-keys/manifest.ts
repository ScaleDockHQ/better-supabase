import type { BlockOf } from "../define-block.ts";
import type { ApiKeysEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createApiKeys } from "./api-keys.ts";
import { apiKeysEvents } from "./events.ts";
import { apiKeysSqlOptions } from "./options.ts";

/** The `api-keys` block's manifest (ADR 0029). */
export const apiKeysBlock: BlockOf<
  "api-keys",
  typeof createApiKeys,
  ApiKeysEvents
> = defineBlock({
  name: "api-keys",
  sql: ["api-keys"],
  options: { "api-keys": apiKeysSqlOptions },
  events: apiKeysEvents,
  create: createApiKeys,
  category: "developer",
  recipes: ["api-keys-table"],
});
