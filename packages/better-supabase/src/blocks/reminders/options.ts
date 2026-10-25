import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.reminders.options`. */
export type RemindersSqlOptions = {
  readonly ruleFormat?: string;
  readonly extraColumns?: ExtraColumns;
};

export const remindersSqlOptions: BlockOptionsSchema<RemindersSqlOptions> =
  blockOptions<RemindersSqlOptions>({
    ruleFormat: option.string({ default: "rrule" }),
    extraColumns: option.extraColumns(),
  });
