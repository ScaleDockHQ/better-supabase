import type {
  RecordBinding,
  RecordRowInput,
  RecordBindingWrite,
} from "../record-bindings.ts";
import type { IssuedPass, Pass, AdmissionPasses } from "./admission-passes.ts";
import type { PassSectionInput } from "./schemas.ts";

import { defineRecordBinding, recordRowInput } from "../record-bindings.ts";
import { passSectionInputSchema } from "./schemas.ts";

/** The writes of the passes binding. */
export type AdmissionPassesWrites = {
  /** Issues a pass for the record, such as a ticket for an event. */
  readonly issue: RecordBindingWrite<
    AdmissionPasses,
    PassSectionInput,
    IssuedPass
  >;
  /** Revokes one of the record's passes. */
  readonly revoke: RecordBindingWrite<AdmissionPasses, RecordRowInput, Pass>;
};

/** The passes issued for a record: an event's tickets, a member's cards. */
export const admissionPassesBinding: RecordBinding<
  AdmissionPasses,
  readonly Pass[],
  undefined,
  never,
  AdmissionPassesWrites
> = defineRecordBinding({
  permissions: { read: "read", write: "manage" },
  module: "admission-passes",
  load: (client: AdmissionPasses, subject) => client.list({ subject }),
  events: ["pass.*"],
  writes: {
    issue: {
      input: passSectionInputSchema,
      run: (client: AdmissionPasses, subject, input: PassSectionInput) =>
        client.issue({ ...input, subject }),
    },
    revoke: {
      input: recordRowInput,
      run: (client: AdmissionPasses, _subject, { id }: RecordRowInput) =>
        client.revoke(id),
    },
  },
});
