import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `meeting.*` event carries. */
export interface MeetingEventData {
  readonly organizationId: string;
  /** The meeting. */
  readonly id: string;
  /** One of `options.kinds`. */
  readonly kind: string;
  readonly title: string;
  /** Its status after the change. */
  readonly status: string;
}

/** `meeting.cancelled`. */
export interface MeetingCanceledEventData extends MeetingEventData {
  readonly reason: string | null;
}

/** What every `meeting_decision.*` event carries. */
export interface MeetingDecisionEventData {
  readonly organizationId: string;
  /** The decision. */
  readonly id: string;
  readonly meetingId: string;
  readonly title: string;
  /** Its status after the change. */
  readonly status: string;
}

/** `meeting_action_item.created`: a task was opened from a meeting. */
export interface MeetingActionItemEventData {
  readonly organizationId: string;
  readonly meetingId: string;
  /** The work item the `tasks` block owns. */
  readonly workItemId: string;
  readonly title: string;
}

/** The events of the `meetings` block: type to data. */
export type MeetingsEvents = {
  readonly "meeting.created": MeetingEventData;
  readonly "meeting.updated": MeetingEventData;
  readonly "meeting.started": MeetingEventData;
  readonly "meeting.concluded": MeetingEventData;
  readonly "meeting.cancelled": MeetingCanceledEventData;
  readonly "meeting.deleted": MeetingEventData;
  readonly "meeting_decision.recorded": MeetingDecisionEventData;
  readonly "meeting_decision.decided": MeetingDecisionEventData;
  readonly "meeting_action_item.created": MeetingActionItemEventData;
};

/** The `meetings` block's event types, for its manifest and `onBlockEvent`. */
export const meetingsEvents: Events<MeetingsEvents> = defineEvents({
  "meeting.created": event<MeetingEventData>(),
  "meeting.updated": event<MeetingEventData>(),
  "meeting.started": event<MeetingEventData>(),
  "meeting.concluded": event<MeetingEventData>(),
  "meeting.cancelled": event<MeetingCanceledEventData>(),
  "meeting.deleted": event<MeetingEventData>(),
  "meeting_decision.recorded": event<MeetingDecisionEventData>(),
  "meeting_decision.decided": event<MeetingDecisionEventData>(),
  "meeting_action_item.created": event<MeetingActionItemEventData>(),
});
