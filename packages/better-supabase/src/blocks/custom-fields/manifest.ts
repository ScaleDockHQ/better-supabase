import type { BlockOf } from "../define-block.ts";
import type { CustomFieldsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCustomFields } from "./custom-fields.ts";
import { customFieldsEvents } from "./events.ts";
import { customFieldsSqlOptions } from "./options.ts";

/** The `custom-fields` block's manifest (ADR 0029). */
export const customFieldsBlock: BlockOf<
  "custom-fields",
  typeof createCustomFields,
  CustomFieldsEvents
> = defineBlock({
  name: "custom-fields",
  sql: ["custom-fields"],
  options: { "custom-fields": customFieldsSqlOptions },
  events: customFieldsEvents,
  create: createCustomFields,
  category: "work",
  recipes: ["custom-fields-editor", "entity-form"],
});
