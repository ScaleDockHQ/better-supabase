import type {
  RecordBinding,
  RecordRowInput,
  RecordBindingWrite,
} from "../record-bindings.ts";
import type { IssuedPass, Pass, Passes } from "./passes.ts";
import type { PassSectionInput } from "./schemas.ts";

import { defineRecordBinding, recordRowInput } from "../record-bindings.ts";
import { passSectionInputSchema } from "./schemas.ts";

/** The writes of the passes binding. */
export type PassesWrites = {
  /** Issues a pass for the record, such as a ticket for an event. */
  readonly issue: RecordBindingWrite<Passes, PassSectionInput, IssuedPass>;
  /** Revokes one of the record's passes. */
  readonly revoke: RecordBindingWrite<Passes, RecordRowInput, Pass>;
};

/** The passes issued for a record: an event's tickets, a member's cards. */
export const passesBinding: RecordBinding<
  Passes,
  readonly Pass[],
  undefined,
  never,
  PassesWrites
> = defineRecordBinding({
  permissions: { read: "read", write: "manage" },
  module: "passes",
  load: (client: Passes, subject) => client.list({ subject }),
  events: ["pass.*"],
  writes: {
    issue: {
      input: passSectionInputSchema,
      run: (client: Passes, subject, input: PassSectionInput) =>
        client.issue({ ...input, subject }),
    },
    revoke: {
      input: recordRowInput,
      run: (client: Passes, _subject, { id }: RecordRowInput) =>
        client.revoke(id),
    },
  },
});
