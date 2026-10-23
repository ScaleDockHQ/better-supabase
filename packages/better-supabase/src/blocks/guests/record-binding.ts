import type {
  RecordBinding,
  RecordRowInput,
  RecordBindingWrite,
} from "../record-bindings.ts";
import type { GuestGrant, Guests, RecordGuestGrant } from "./guests.ts";
import type { GuestSectionGrantInput } from "./schemas.ts";

import { defineRecordBinding, recordRowInput } from "../record-bindings.ts";
import { guestSectionGrantSchema } from "./schemas.ts";

/** The writes of the guests binding. */
export type GuestsWrites = {
  /** Lets a guest reach the record. */
  readonly grant: RecordBindingWrite<
    Guests,
    GuestSectionGrantInput,
    GuestGrant
  >;
  /** Takes one guest's access to the record away. */
  readonly revoke: RecordBindingWrite<Guests, RecordRowInput, boolean>;
};

/** The guests who reach a record: a sharing panel. */
export const guestsBinding: RecordBinding<
  Guests,
  readonly RecordGuestGrant[],
  undefined,
  never,
  GuestsWrites
> = defineRecordBinding({
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
      input: recordRowInput,
      run: (client: Guests, _subject, { id }: RecordRowInput) =>
        client.revokeGrant(id),
    },
  },
});
