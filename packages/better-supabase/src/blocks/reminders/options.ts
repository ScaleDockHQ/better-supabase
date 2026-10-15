import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.reminders.options`. */
export type RemindersSqlOptions = {
  readonly ruleFormat?: string;
};

export const remindersSqlOptions: BlockOptionsSchema<RemindersSqlOptions> =
  blockOptions<RemindersSqlOptions>({
    ruleFormat: option.string({ default: "rrule" }),
  });
