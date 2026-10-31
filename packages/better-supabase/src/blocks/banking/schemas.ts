import type { EntitySchema } from "../entity-schema.ts";
import type {
  BankAccountInput,
  BankMatchInput,
  BankRuleInput,
} from "./banking.ts";

import { MATCH_TARGETS } from "../../sql/modules/banking-sql.ts";
import { entitySchema, moneyField } from "../entity-schema.ts";

/** What `saveAccount` takes, with the bounds the SQL checks. */
export const bankAccountInputSchema: EntitySchema<BankAccountInput> =
  entitySchema<BankAccountInput>({
    title: "BankAccountInput",
    fields: {
      name: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      iban: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 42,
        description:
          "Checked against its ISO 13616 check digits; spaces are dropped.",
      },
      bic: { kind: "string", optional: true, nullable: true, maxLength: 11 },
      currency: { kind: "string", optional: true, minLength: 3, maxLength: 3 },
      journalId: {
        kind: "uuid",
        optional: true,
        nullable: true,
        description: "An accounting journal of type bank or cash.",
      },
      archived: { kind: "boolean", optional: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  });

/** One entry of what `match` takes. */
export const bankMatchInputSchema: EntitySchema<BankMatchInput> =
  entitySchema<BankMatchInput>({
    title: "BankMatchInput",
    fields: {
      targetType: { kind: "enum", values: MATCH_TARGETS },
      targetId: { kind: "uuid" },
      amount: { ...moneyField, optional: true },
    },
  });

/** What `saveRule` takes. */
export const bankRuleInputSchema: EntitySchema<BankRuleInput> =
  entitySchema<BankRuleInput>({
    title: "BankRuleInput",
    fields: {
      name: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      conditions: {
        kind: "json",
        optional: true,
        description:
          "A filter tree over the transaction: accountId, bookedOn, valueOn, amount, direction, currency, counterpartyName, counterpartyIban, remittance, structuredReference, endToEndId.",
      },
      accountId: {
        kind: "uuid",
        optional: true,
        nullable: true,
        description:
          "The ledger account to book the other side to; none ignores the match.",
      },
      partyId: { kind: "uuid", optional: true, nullable: true },
      dimensions: { kind: "json", optional: true },
      priority: { kind: "integer", optional: true },
      active: { kind: "boolean", optional: true },
    },
  });
