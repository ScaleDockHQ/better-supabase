import type { EntitySchema } from "../entity-schema.ts";
import type {
  ContractChanges,
  ContractInput,
  ObligationInput,
} from "./contracts.ts";

import { entitySchema, moneyField } from "../entity-schema.ts";

const subject = {
  kind: "json",
  optional: true,
  description: "The counterparty, a registered subject: `{ type, id }`.",
} as const;

const fields = {
  kind: "json",
  optional: true,
  description: "The extra columns, keyed by database name.",
} as const;

/** What `create` takes. */
export const contractInputSchema: EntitySchema<ContractInput> =
  entitySchema<ContractInput>({
    title: "ContractInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 200 },
      description: { kind: "string", optional: true, maxLength: 10_000 },
      counterparty: subject,
      ownerId: { kind: "uuid", optional: true },
      value: { ...moneyField, optional: true },
      startsOn: { kind: "plainDate", optional: true },
      endsOn: { kind: "plainDate", optional: true },
      autoRenew: { kind: "boolean", optional: true },
      renewalMonths: {
        kind: "integer",
        optional: true,
        minimum: 1,
        maximum: 120,
      },
      noticeDays: {
        kind: "integer",
        optional: true,
        minimum: 0,
        maximum: 3650,
      },
      fields,
    },
  });

/** What `update` takes: a key left out keeps its value. */
export const contractChangesSchema: EntitySchema<ContractChanges> =
  entitySchema<ContractChanges>({
    title: "ContractChanges",
    fields: {
      title: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      description: { kind: "string", optional: true, maxLength: 10_000 },
      counterparty: subject,
      ownerId: { kind: "uuid", optional: true },
      value: { ...moneyField, optional: true },
      startsOn: { kind: "plainDate", optional: true },
      endsOn: { kind: "plainDate", optional: true },
      autoRenew: { kind: "boolean", optional: true },
      renewalMonths: {
        kind: "integer",
        optional: true,
        minimum: 1,
        maximum: 120,
      },
      noticeDays: {
        kind: "integer",
        optional: true,
        minimum: 0,
        maximum: 3650,
      },
      fields,
    },
  });

/** What `saveObligation` takes. */
export const obligationInputSchema: EntitySchema<ObligationInput> =
  entitySchema<ObligationInput>({
    title: "ObligationInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 200 },
      description: { kind: "string", optional: true, maxLength: 4000 },
      dueOn: { kind: "plainDate", optional: true },
      ownerId: { kind: "uuid", optional: true },
      obligationId: { kind: "uuid", optional: true },
    },
  });
