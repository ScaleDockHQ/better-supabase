import type {
  FormEventData,
  FormSubmissionEventData,
  SignatureEventData,
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

/** The events of the `signatures` block: type to data. */
export type SignaturesEvents = {
  readonly "signature.requested": SignatureEventData;
  readonly "signature.signed": SignatureEventData;
  readonly "signature.completed": SignatureEventData;
  readonly "signature.declined": SignatureEventData;
  readonly "signature.cancelled": SignatureEventData;
};

/** The `signatures` block's event types, for its manifest and `onBlockEvent`. */
export const signaturesEvents: Events<SignaturesEvents> = defineEvents({
  "signature.requested": event<SignatureEventData>(),
  "signature.signed": event<SignatureEventData>(),
  "signature.completed": event<SignatureEventData>(),
  "signature.declined": event<SignatureEventData>(),
  "signature.cancelled": event<SignatureEventData>(),
});
