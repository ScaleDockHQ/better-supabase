import type { EntitySchema } from "../entity-schema.ts";

import { entitySchema } from "../entity-schema.ts";

/** The input of `open`. */
export interface CaseInput {
  readonly title: string;
  readonly description?: string;
  readonly severity?: string;
  readonly source?: string;
  readonly occurredAt?: Temporal.Instant;
  readonly ownerId?: string;
  readonly dueOn?: Temporal.PlainDate;
}

export const caseInputSchema: EntitySchema<CaseInput> = entitySchema<CaseInput>({
  title: "CaseInput",
  fields: {
    title: { kind: "string", minLength: 1, maxLength: 200 },
    description: { kind: "string", optional: true },
    severity: { kind: "string", optional: true },
    source: { kind: "string", optional: true },
    occurredAt: { kind: "instant", optional: true },
    ownerId: { kind: "uuid", optional: true },
    dueOn: { kind: "plainDate", optional: true },
  },
});
