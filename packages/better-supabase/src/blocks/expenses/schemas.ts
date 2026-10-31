import type { EntitySchema } from "../entity-schema.ts";
import type {
  ExpenseCategoryInput,
  ExpenseLineInput,
  ExpenseReportInput,
} from "./expenses.ts";

import { entitySchema, moneyField } from "../entity-schema.ts";

/** What `create` takes. */
export const expenseReportInputSchema: EntitySchema<ExpenseReportInput> =
  entitySchema<ExpenseReportInput>({
    title: "ExpenseReportInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 200 },
      currency: {
        kind: "string",
        minLength: 3,
        maxLength: 3,
        description: "A three-letter currency code; every line is in it.",
      },
      note: { kind: "string", optional: true, maxLength: 2000 },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns to set.",
      },
    },
  });

/** What `addLine` takes, with the bounds the SQL checks. */
export const expenseLineInputSchema: EntitySchema<ExpenseLineInput> =
  entitySchema<ExpenseLineInput>({
    title: "ExpenseLineInput",
    fields: {
      categoryId: { kind: "uuid" },
      spentOn: { kind: "plainDate" },
      amount: moneyField,
      description: { kind: "string", minLength: 1, maxLength: 500 },
      merchant: { kind: "string", optional: true, maxLength: 200 },
      dimensions: {
        kind: "json",
        optional: true,
        description:
          'Accounting dimensions of the line: `{ project: "<project id>" }`.',
      },
    },
  });

/** What `saveCategory` takes. */
export const expenseCategoryInputSchema: EntitySchema<ExpenseCategoryInput> =
  entitySchema<ExpenseCategoryInput>({
    title: "ExpenseCategoryInput",
    fields: {
      key: {
        kind: "string",
        minLength: 1,
        maxLength: 63,
        description: "Lowercase letters, digits and underscores.",
      },
      name: { kind: "string", minLength: 1, maxLength: 200 },
      limit: { ...moneyField, optional: true },
      receiptOver: { ...moneyField, optional: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns to set.",
      },
    },
  });
