import type { EntitySchema } from "../entity-schema.ts";
import type { PrepareTaxReturnInput, TaxCodeInput } from "./tax.ts";

import { TAX_CODE_TYPES } from "../../sql/modules/tax-sql.ts";
import { entitySchema } from "../entity-schema.ts";

/** What `saveCode` takes, with the bounds the SQL checks. */
export const taxCodeInputSchema: EntitySchema<TaxCodeInput> =
  entitySchema<TaxCodeInput>({
    title: "TaxCodeInput",
    fields: {
      code: { kind: "string", optional: true, minLength: 1, maxLength: 40 },
      name: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      type: { kind: "enum", optional: true, values: TAX_CODE_TYPES },
      legalEntityId: { kind: "uuid", optional: true, nullable: true },
      salesAccountId: { kind: "uuid", optional: true, nullable: true },
      purchaseAccountId: { kind: "uuid", optional: true, nullable: true },
      returnBoxes: {
        kind: "string",
        array: true,
        optional: true,
        description: "The tax return boxes the code reports in.",
      },
      archived: { kind: "boolean", optional: true },
      rateBps: { kind: "integer", optional: true, minimum: 0, maximum: 10_000 },
      validFrom: { kind: "string", optional: true },
    },
  });

/** What `prepareReturn` takes. */
export const prepareTaxReturnInputSchema: EntitySchema<PrepareTaxReturnInput> =
  entitySchema<PrepareTaxReturnInput>({
    title: "PrepareTaxReturnInput",
    fields: {
      since: { kind: "string" },
      until: { kind: "string" },
      legalEntityId: { kind: "uuid", optional: true },
      period: { kind: "string", optional: true, maxLength: 60 },
      currency: { kind: "string", optional: true, minLength: 3, maxLength: 3 },
    },
  });
