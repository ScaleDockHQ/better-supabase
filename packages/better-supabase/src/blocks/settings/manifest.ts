import type { BlockOf } from "../define-block.ts";
import type { SettingsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { settingsEvents } from "./events.ts";
import { settingsSqlOptions } from "./options.ts";
import { createSettings } from "./settings.ts";

/**
 * The `settings` block's manifest (ADR 0029). Pass the app's settings with
 * `settingsBlock.using((options) => createSettings({ ...options, settings
 * }))`.
 */
export const settingsBlock: BlockOf<
  "settings",
  typeof createSettings,
  SettingsEvents
> = defineBlock({
  name: "settings",
  sql: ["settings"],
  options: { settings: settingsSqlOptions },
  events: settingsEvents,
  create: createSettings,
  category: "tenancy",
  recipes: ["settings-layout"],
});
