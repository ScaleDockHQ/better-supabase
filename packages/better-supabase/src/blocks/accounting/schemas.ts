import type { EntitySchema } from "../entity-schema.ts";
import type {
  AccountingAccountInput,
  AccountingEntryInput,
  AccountingJournalInput,
} from "./accounting.ts";

import { entitySchema } from "../entity-schema.ts";

const CURRENCY = { kind: "string", minLength: 3, maxLength: 3 } as const;

/** What `saveAccount` takes. */
export const accountingAccountInputSchema: EntitySchema<AccountingAccountInput> =
  entitySchema<AccountingAccountInput>({
    title: "AccountingAccountInput",
    fields: {
      code: { kind: "string", minLength: 1, maxLength: 50 },
      name: { kind: "string", minLength: 1, maxLength: 200 },
      type: {
        kind: "enum",
        values: ["asset", "liability", "equity", "income", "expense"],
      },
      subtype: { kind: "string", optional: true },
      parentId: { kind: "uuid", optional: true },
      currency: { ...CURRENCY, optional: true },
      reconcilable: { kind: "boolean", optional: true },
      normalSide: { kind: "enum", values: ["debit", "credit"], optional: true },
      defaultTaxCodeId: { kind: "uuid", optional: true },
      active: { kind: "boolean", optional: true },
      accountId: { kind: "uuid", optional: true },
    },
  });

/** What `saveJournal` takes. */
export const accountingJournalInputSchema: EntitySchema<AccountingJournalInput> =
  entitySchema<AccountingJournalInput>({
    title: "AccountingJournalInput",
    fields: {
      code: { kind: "string", minLength: 1, maxLength: 16 },
      name: { kind: "string", minLength: 1, maxLength: 200 },
      type: {
        kind: "enum",
        values: ["sales", "purchase", "bank", "cash", "general"],
      },
      defaultAccountId: { kind: "uuid", optional: true },
      contraAccountId: { kind: "uuid", optional: true },
      bankAccountId: { kind: "uuid", optional: true },
      currency: { ...CURRENCY, optional: true },
      journalId: { kind: "uuid", optional: true },
    },
  });

/** What `saveEntry` takes. */
export const accountingEntryInputSchema: EntitySchema<AccountingEntryInput> =
  entitySchema<AccountingEntryInput>({
    title: "AccountingEntryInput",
    fields: {
      journalId: { kind: "uuid" },
      entryDate: { kind: "plainDate" },
      lines: {
        kind: "json",
        array: true,
        description:
          "At least two lines, each with an account (accountId or accountCode) and a debit or a credit in minor units.",
      },
      memo: { kind: "string", optional: true, maxLength: 2000 },
      reference: { kind: "string", optional: true, maxLength: 200 },
      sourceType: { kind: "string", optional: true, maxLength: 63 },
      sourceId: { kind: "string", optional: true },
      entryId: { kind: "uuid", optional: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  });
