import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.meetings.options`. */
export type MeetingsSqlOptions = {
  /**
   * The kinds a meeting takes. Default `meeting`, `board`, `management_review`,
   * `one_on_one` and `toolbox_talk`.
   */
  readonly kinds?: readonly string[];
  /**
   * The name of a calendar (the calendar block) that mirrors planned meetings
   * as events and invites the attendees by their account email. An organization
   * without a calendar of that name gets no events.
   */
  readonly calendar?: string;
  /** Extra columns on the meetings table. */
  readonly extraColumns?: ExtraColumns;
};

export const meetingsSqlOptions: BlockOptionsSchema<MeetingsSqlOptions> =
  blockOptions<MeetingsSqlOptions>({
    kinds: option.strings(),
    calendar: option.string(),
    extraColumns: option.extraColumns(),
  });
