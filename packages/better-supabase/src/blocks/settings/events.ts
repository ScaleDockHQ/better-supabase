import type { SettingEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `settings` block: type to data. */
export type SettingsEvents = {
  readonly "organization_setting.updated": SettingEventData;
  readonly "organization_setting.reset": SettingEventData;
  readonly "platform_setting.updated": SettingEventData;
  readonly "platform_setting.reset": SettingEventData;
};

/** The `settings` block's event types, for its manifest and `onBlockEvent`. */
export const settingsEvents: Events<SettingsEvents> = defineEvents({
  "organization_setting.updated": event<SettingEventData>(),
  "organization_setting.reset": event<SettingEventData>(),
  "platform_setting.updated": event<SettingEventData>(),
  "platform_setting.reset": event<SettingEventData>(),
});
