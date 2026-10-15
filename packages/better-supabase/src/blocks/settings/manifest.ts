import type { BlockContext } from "../create-blocks.ts";
import type { Block } from "../define-block.ts";
import type { SettingsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { settingsEvents } from "./events.ts";
import { settingsSqlOptions } from "./options.ts";

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
    settings: settingsSqlOptions,
  },
  events: settingsEvents,
  category: "foundation",
  recipes: ["settings-layout"],
});
