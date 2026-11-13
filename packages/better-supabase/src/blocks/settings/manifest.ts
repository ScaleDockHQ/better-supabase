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
  entities: {
    organization_setting: {
      mutability: "editable",
      emits: { create: false, update: true },
    },
    platform_setting: {
      mutability: "editable",
      emits: { create: false, update: true },
    },
  },
  description:
    "Per-user, per-organization and platform-wide settings as key-value jsonb rows. Users read and write their own; organization settings check settings.read and settings.update; platform settings check a platform permission per key. Keys with a JSON Schema in options.schemas get a pg_jsonschema check.",
  recipes: ["settings-layout"],
});
