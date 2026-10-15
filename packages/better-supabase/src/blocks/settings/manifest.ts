import type { BlockContext } from "../create-blocks.ts";
import type { Block } from "../define-block.ts";
import type { SettingsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { settingsEvents } from "./events.ts";

/** The `settings` block's manifest (ADR 0029). */
export const settingsBlock: Block<
  "settings",
  BlockContext,
  unknown,
  SettingsEvents
> = defineBlock({
  name: "settings",
  sql: ["settings"],
  options: {
    settings: optionKeys(["schemas", "platform"]),
  },
  events: settingsEvents,
  category: "foundation",
  recipes: ["settings-layout"],
});
