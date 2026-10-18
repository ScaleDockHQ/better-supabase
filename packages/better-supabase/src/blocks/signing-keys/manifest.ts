import type { BlockOf } from "../define-block.ts";
import type { SigningKeysEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { signingKeysEvents } from "./events.ts";
import { signingKeysSqlOptions } from "./options.ts";
import { createSigningKeys } from "./signing-keys.ts";

/** The `signing-keys` block's manifest (ADR 0029). */
export const signingKeysBlock: BlockOf<
  "signing-keys",
  typeof createSigningKeys,
  SigningKeysEvents
> = defineBlock({
  name: "signing-keys",
  sql: ["signing-keys"],
  options: {
    "signing-keys": signingKeysSqlOptions,
  },
  events: signingKeysEvents,
  create: createSigningKeys,
  category: "developer",
});
