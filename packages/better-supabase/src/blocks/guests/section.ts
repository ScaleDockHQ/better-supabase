import type { Section, SectionRowInput, SectionWrite } from "../sections.ts";
import type { GuestGrant, Guests, RecordGuestGrant } from "./guests.ts";
import type { GuestSectionGrantInput } from "./schemas.ts";

import { defineSection, sectionRowInput } from "../sections.ts";
import { guestSectionGrantSchema } from "./schemas.ts";

/** The writes of the guests section. */
export type GuestsWrites = {
  /** Lets a guest reach the record. */
  readonly grant: SectionWrite<Guests, GuestSectionGrantInput, GuestGrant>;
  /** Takes one guest's access to the record away. */
  readonly revoke: SectionWrite<Guests, SectionRowInput, boolean>;
};

/** The guests who reach a record: a sharing panel. */
export const guestsSection: Section<
  Guests,
  readonly RecordGuestGrant[],
  undefined,
  never,
  GuestsWrites
> = defineSection({
  permissions: { read: "read", write: "manage" },
  module: "guests",
  load: (client: Guests, subject) => client.grants(subject),
  events: ["guest_grant.*", "guest.revoked"],
  writes: {
    grant: {
      input: guestSectionGrantSchema,
      run: (
        client: Guests,
        subject,
        { guestId, ...input }: GuestSectionGrantInput,
      ) => client.grant(guestId, subject, input),
    },
    revoke: {
      input: sectionRowInput,
      run: (client: Guests, _subject, { id }: SectionRowInput) =>
        client.revokeGrant(id),
    },
  },
});
