import type { EntitySchema } from "../entity-schema.ts";
import type { PayrollRunInput } from "./payroll-export.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `create` takes, with the bounds the SQL checks. */
export const payrollRunInputSchema: EntitySchema<PayrollRunInput> =
  entitySchema<PayrollRunInput>({
    title: "PayrollRunInput",
    fields: {
      from: { kind: "plainDate", description: "The first day." },
      to: {
        kind: "plainDate",
        description: "The last day; at most 400 days after from.",
      },
      label: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
    },
  });
