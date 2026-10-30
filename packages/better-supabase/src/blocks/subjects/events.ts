import type {
  SubjectAccessedEventData,
  SubjectMemberEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `subjects` block: type to data. */
export type SubjectsEvents = {
  readonly "subject_member.added": SubjectMemberEventData;
  readonly "subject_member.ended": SubjectMemberEventData;
  /**
   * A record of a type with `auditReads` was read; audit only, with the `audit`
   * block.
   */
  readonly "subject.accessed": SubjectAccessedEventData;
};

/** The `subjects` block's event types, for its manifest and `onBlockEvent`. */
export const subjectsEvents: Events<SubjectsEvents> = defineEvents({
  "subject_member.added": event<SubjectMemberEventData>(),
  "subject_member.ended": event<SubjectMemberEventData>(),
  "subject.accessed": event<SubjectAccessedEventData>(),
});
