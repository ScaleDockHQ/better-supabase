import type { EntitySchema } from "../entity-schema.ts";
import type { LegalEntityInput } from "./legal-entities.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `create` and `update` take, with the bounds the SQL checks. */
export const legalEntityInputSchema: EntitySchema<LegalEntityInput> =
  entitySchema<LegalEntityInput>({
    title: "LegalEntityInput",
    fields: {
      code: { kind: "string", optional: true, minLength: 1, maxLength: 50 },
      name: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      address: { kind: "json", optional: true },
      vatNumber: { kind: "string", optional: true, nullable: true },
      cocNumber: { kind: "string", optional: true, nullable: true },
      iban: { kind: "string", optional: true, nullable: true },
      bic: { kind: "string", optional: true, nullable: true },
      logoAttachmentId: { kind: "uuid", optional: true, nullable: true },
      defaultCurrency: { kind: "string", optional: true, nullable: true },
      fiscal: {
        kind: "json",
        optional: true,
        description:
          "`{ fiscalYearStartMonth: 1 to 12, taxPeriod: 'monthly' | 'quarterly' }`.",
      },
    },
  });
