import type { BlockOf } from "../define-block.ts";
import type { MeetingsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { meetingsEvents } from "./events.ts";
import { createMeetings } from "./meetings.ts";
import { meetingsSqlOptions } from "./options.ts";
import {
  meetingAgendaItemInputSchema,
  meetingDecisionInputSchema,
  meetingInputSchema,
} from "./schemas.ts";

/** The `meetings` block's manifest (ADR 0029, ADR 0152). */
export const meetingsBlock: BlockOf<
  "meetings",
  typeof createMeetings,
  MeetingsEvents
> = defineBlock({
  name: "meetings",
  sql: ["meetings"],
  options: { meetings: meetingsSqlOptions },
  events: meetingsEvents,
  schemas: {
    meeting: { input: meetingInputSchema },
    meeting_agenda_item: { input: meetingAgendaItemInputSchema },
    meeting_decision: { input: meetingDecisionInputSchema },
  },
  create: createMeetings,
  recipes: ["meeting-agenda", "meeting-minutes"],
  category: "collaboration",
});
