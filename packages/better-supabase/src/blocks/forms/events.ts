import type {
  FormEventData,
  FormSubmissionEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `forms` block: type to data. */
export type FormsEvents = {
  readonly "form.created": FormEventData;
  readonly "form_version.published": FormEventData;
  readonly "form_submission.submitted": FormSubmissionEventData;
  readonly "form_submission.reviewed": FormSubmissionEventData;
  readonly "form_submission.deleted": FormSubmissionEventData;
};

/** The `forms` block's event types, for its manifest and `onBlockEvent`. */
export const formsEvents: Events<FormsEvents> = defineEvents({
  "form.created": event<FormEventData>(),
  "form_version.published": event<FormEventData>(),
  "form_submission.submitted": event<FormSubmissionEventData>(),
  "form_submission.reviewed": event<FormSubmissionEventData>(),
  "form_submission.deleted": event<FormSubmissionEventData>(),
});
