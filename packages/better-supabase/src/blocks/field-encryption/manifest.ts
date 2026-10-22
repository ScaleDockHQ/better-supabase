import type { Block } from "../define-block.ts";
import type { FieldEncryptionEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { fieldEncryptionEvents } from "./events.ts";

/** The `field-encryption` block's manifest (ADR 0029). */
export const fieldEncryptionBlock: Block<
  "field-encryption",
  never,
  never,
  FieldEncryptionEvents
> = defineBlock({
  name: "field-encryption",
  sql: ["field-encryption"],
  events: fieldEncryptionEvents,
  category: "database",
});
