import type { EntitySchema } from "../entity-schema.ts";
import type { Section, SectionWrite } from "../sections.ts";
import type { Sla, SlaClock } from "./sla.ts";

import { entitySchema } from "../entity-schema.ts";
import { defineSection } from "../sections.ts";

/** What starting a record's clocks takes. */
export interface SlaStartInput {
  readonly priority?: string;
}

/** The input schema of the SLA section's `start`. */
export const slaStartInput: EntitySchema<SlaStartInput> =
  entitySchema<SlaStartInput>({
    title: "SlaStartInput",
    fields: { priority: { kind: "string", optional: true, minLength: 1 } },
  });

/** The writes of the SLA section. */
export type SlaWrites = {
  /** Starts the record's clocks, or recomputes them for a new priority. */
  readonly start: SectionWrite<Sla, SlaStartInput, SlaClock[]>;
};

/** A record's response and resolution clocks. */
export const slaSection: Section<Sla, SlaClock[], never, never, SlaWrites> =
  defineSection({
    permissions: { read: "read", write: "manage" },
    module: "sla",
    load: (client: Sla, subject) => client.clocks(subject),
    events: ["sla.*"],
    writes: {
      start: {
        input: slaStartInput,
        run: (client: Sla, subject, input: SlaStartInput) =>
          client.start(subject, input.priority),
      },
    },
  });
