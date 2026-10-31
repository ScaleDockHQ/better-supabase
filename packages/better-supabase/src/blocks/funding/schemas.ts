import type { EntitySchema } from "../entity-schema.ts";
import type { FundingAwardInput } from "./funding.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `createAward` takes. */
export const fundingAwardInputSchema: EntitySchema<FundingAwardInput> =
  entitySchema<FundingAwardInput>({
    title: "FundingAwardInput",
    fields: {
      funderId: { kind: "uuid" },
      productId: { kind: "uuid" },
      units: { kind: "number", minimum: 0 },
      period: { kind: "enum", values: ["week", "month", "total"] },
      startsOn: { kind: "plainDate" },
      endsOn: { kind: "plainDate", optional: true },
      reference: { kind: "string", optional: true, maxLength: 200 },
      status: { kind: "enum", optional: true, values: ["requested", "active"] },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  });
