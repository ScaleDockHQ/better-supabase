import type { EntitySchema } from "../entity-schema.ts";
import type { ConsentPurposeInput } from "./consents.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `savePurpose` takes, with the bounds the SQL checks. */
export const consentPurposeInputSchema: EntitySchema<ConsentPurposeInput> =
  entitySchema<ConsentPurposeInput>({
    title: "ConsentPurposeInput",
    fields: {
      key: {
        kind: "string",
        minLength: 1,
        maxLength: 63,
        description:
          "Lowercase letters, digits, `_`, `-` and `.`, such as `marketing.email`.",
      },
      title: { kind: "string", minLength: 1, maxLength: 200 },
      version: {
        kind: "string",
        optional: true,
        minLength: 1,
        maxLength: 40,
        description: "Default `1`. A new version asks every record again.",
      },
      description: { kind: "string", optional: true, maxLength: 4000 },
      legalBasis: {
        kind: "enum",
        optional: true,
        values: [
          "consent",
          "contract",
          "legal_obligation",
          "vital_interest",
          "public_task",
          "legitimate_interest",
        ],
      },
      requiresSignature: { kind: "boolean", optional: true },
      validMonths: {
        kind: "integer",
        optional: true,
        minimum: 1,
        maximum: 1200,
      },
      system: {
        kind: "boolean",
        optional: true,
        description:
          "A system purpose every organization uses; service role only.",
      },
    },
  });
