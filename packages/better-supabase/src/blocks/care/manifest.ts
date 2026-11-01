import type { BlockContext } from "../create-blocks.ts";
import type { BlockOf, CompositeOptions } from "../define-block.ts";

import { CARE_SETTINGS } from "../../preset/preset-blocks.ts";
import { acknowledgementsBlock } from "../acknowledgements/manifest.ts";
import { activitiesBlock } from "../activities/manifest.ts";
import { approvalsBlock } from "../approvals/manifest.ts";
import { attachmentsBlock } from "../attachments/manifest.ts";
import { bookingsBlock } from "../bookings/manifest.ts";
import { calendarBlock } from "../calendar/manifest.ts";
import { carePlansBlock } from "../care-plans/manifest.ts";
import { casesBlock } from "../cases/manifest.ts";
import { consentsBlock } from "../consents/manifest.ts";
import { contactsBlock } from "../contacts/manifest.ts";
import { coursesBlock } from "../courses/manifest.ts";
import { dataLifecycleBlock } from "../data-lifecycle/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { driveBlock } from "../drive/manifest.ts";
import { fieldEncryptionBlock } from "../field-encryption/manifest.ts";
import { formsBlock } from "../forms/manifest.ts";
import { fundingBlock } from "../funding/manifest.ts";
import { guestsBlock } from "../guests/manifest.ts";
import { medicationsBlock } from "../medications/manifest.ts";
import { numberingBlock } from "../numbering/manifest.ts";
import { observationsBlock } from "../observations/manifest.ts";
import { qualificationsBlock } from "../qualifications/manifest.ts";
import { remindersBlock } from "../reminders/manifest.ts";
import { shiftsBlock } from "../shifts/manifest.ts";
import { signaturesBlock } from "../signatures/manifest.ts";
import { stateMachineBlock } from "../state-machine/manifest.ts";
import { timeTrackingBlock } from "../time-tracking/manifest.ts";
import { versionsBlock } from "../versions/manifest.ts";

/** The blocks `care` is made of, by block name. */
export const careParts: {
  readonly contacts: typeof contactsBlock;
  readonly guests: typeof guestsBlock;
  readonly "field-encryption": typeof fieldEncryptionBlock;
  readonly "data-lifecycle": typeof dataLifecycleBlock;
  readonly consents: typeof consentsBlock;
  readonly activities: typeof activitiesBlock;
  readonly "care-plans": typeof carePlansBlock;
  readonly observations: typeof observationsBlock;
  readonly medications: typeof medicationsBlock;
  readonly forms: typeof formsBlock;
  readonly bookings: typeof bookingsBlock;
  readonly calendar: typeof calendarBlock;
  readonly reminders: typeof remindersBlock;
  readonly "time-tracking": typeof timeTrackingBlock;
  readonly funding: typeof fundingBlock;
  readonly shifts: typeof shiftsBlock;
  readonly qualifications: typeof qualificationsBlock;
  readonly courses: typeof coursesBlock;
  readonly cases: typeof casesBlock;
  readonly acknowledgements: typeof acknowledgementsBlock;
  readonly drive: typeof driveBlock;
  readonly attachments: typeof attachmentsBlock;
  readonly versions: typeof versionsBlock;
  readonly approvals: typeof approvalsBlock;
  readonly "state-machine": typeof stateMachineBlock;
  readonly numbering: typeof numberingBlock;
  readonly signatures: typeof signaturesBlock;
} = {
  contacts: contactsBlock,
  guests: guestsBlock,
  "field-encryption": fieldEncryptionBlock,
  "data-lifecycle": dataLifecycleBlock,
  consents: consentsBlock,
  activities: activitiesBlock,
  "care-plans": carePlansBlock,
  observations: observationsBlock,
  medications: medicationsBlock,
  forms: formsBlock,
  bookings: bookingsBlock,
  calendar: calendarBlock,
  reminders: remindersBlock,
  "time-tracking": timeTrackingBlock,
  funding: fundingBlock,
  shifts: shiftsBlock,
  qualifications: qualificationsBlock,
  courses: coursesBlock,
  cases: casesBlock,
  acknowledgements: acknowledgementsBlock,
  drive: driveBlock,
  attachments: attachmentsBlock,
  versions: versionsBlock,
  approvals: approvalsBlock,
  "state-machine": stateMachineBlock,
  numbering: numberingBlock,
  signatures: signaturesBlock,
};

export type CareParts = typeof careParts;

/**
 * The `care` composite (ADR 0177): the client record with its team and read
 * log, clinical blocks, funding, staffing and quality. It installs its parts
 * and sets their defaults; the parts stay ordinary blocks in the config.
 */
export const careBlock: BlockOf<
  "care",
  (options: BlockContext & CompositeOptions<CareParts>) => undefined
> = defineBlock({
  name: "care",
  composes: careParts,
  defaults: CARE_SETTINGS,
  category: "people",
});
