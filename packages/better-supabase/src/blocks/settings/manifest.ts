import type { Block } from "../define-block.ts";
import type { SettingsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { settingsEvents } from "./events.ts";

/** The `settings` block's manifest (ADR 0029). */
export const settingsBlock: Block<"settings", never, never, SettingsEvents> =
  defineBlock({
    name: "settings",
    sql: ["settings"],
    options: {
      settings: optionKeys(["schemas", "platform"]),
    },
    events: settingsEvents,
    category: "foundation",
    recipes: ["settings-layout"],
  });
