import type { Section, SectionRowInput, SectionWrite } from "../sections.ts";
import type { IssuedPass, Pass, Passes } from "./passes.ts";
import type { PassSectionInput } from "./schemas.ts";

import { defineSection, sectionRowInput } from "../sections.ts";
import { passSectionInputSchema } from "./schemas.ts";

/** The writes of the passes section. */
export type PassesWrites = {
  /** Issues a pass for the record, such as a ticket for an event. */
  readonly issue: SectionWrite<Passes, PassSectionInput, IssuedPass>;
  /** Revokes one of the record's passes. */
  readonly revoke: SectionWrite<Passes, SectionRowInput, Pass>;
};

/** The passes issued for a record: an event's tickets, a member's cards. */
export const passesSection: Section<
  Passes,
  readonly Pass[],
  undefined,
  never,
  PassesWrites
> = defineSection({
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
      input: sectionRowInput,
      run: (client: Passes, _subject, { id }: SectionRowInput) =>
        client.revoke(id),
    },
  },
});
