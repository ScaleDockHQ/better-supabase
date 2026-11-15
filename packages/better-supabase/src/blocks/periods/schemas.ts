import type { EntitySchema } from "../entity-schema.ts";
import type { CreatePeriodInput } from "./periods.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `createPeriod` takes. */
export const periodInputSchema: EntitySchema<CreatePeriodInput> =
  entitySchema<CreatePeriodInput>({
    title: "CreatePeriodInput",
    fields: {
      kind: {
        kind: "string",
        minLength: 1,
        description: "What the range is for, such as `fiscal_month`.",
      },
      startsOn: { kind: "plainDate" },
      endsOn: {
        kind: "plainDate",
        description: "The last day of the range, inclusive.",
      },
    },
  });
