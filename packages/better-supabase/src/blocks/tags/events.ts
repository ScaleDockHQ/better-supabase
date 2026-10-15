import type {
  Events,
  SaasEventData,
  SaasSubjectEventData,
} from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `tags` block: type to data. */
export type TagsEvents = {
  readonly "tag.created": SaasEventData;
  readonly "tag.updated": SaasEventData;
  readonly "tag.deleted": SaasEventData;
  readonly "subject.tagged": SaasSubjectEventData;
  readonly "subject.untagged": SaasSubjectEventData;
};

/** The `tags` block's event types, for its manifest and `onBlockEvent`. */
export const tagsEvents: Events<TagsEvents> = defineEvents({
  "tag.created": event<SaasEventData>(),
  "tag.updated": event<SaasEventData>(),
  "tag.deleted": event<SaasEventData>(),
  "subject.tagged": event<SaasSubjectEventData>(),
  "subject.untagged": event<SaasSubjectEventData>(),
});
