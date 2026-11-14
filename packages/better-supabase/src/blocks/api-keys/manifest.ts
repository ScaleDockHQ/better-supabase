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
  entities: {
    api_key: { mutability: "state-machine", emits: { create: true } },
  },
  concerns: ["lifecycle"],
  limits: { create: { meter: "api_keys_created" } },
  meters: { create: { meter: "api_keys_created" } },
  description:
    "Hashed API keys for tenants and users with scopes, expiry, rotation with a grace period, a per-key rate limit and throttled last-used tracking. verify_api_key() backs apiKeyResolver; has_scope() and api_key_tenant() go in policies.",
  recipes: ["api-keys-table"],
});
