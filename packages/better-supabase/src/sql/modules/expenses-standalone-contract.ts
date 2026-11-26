import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { extraFieldsArg } from "../shared.ts";
import { ownerIsEmployee } from "./record-owner.ts";

/** The keys the expense reads return next to the extra columns. */
export const EXPENSE_RESERVED = ["fields"] as const;

const FUNCTION = /^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/;

/**
 * Whether an expense row counts as invoiced, so it can't be reopened:
 * `options.invoicedCheck`, an app function `(expense_id uuid) returns boolean`
 * that can look at the invoice's status (a null answer counts as invoiced), or
 * `options.invoicedColumn`, a column that is set once invoiced.
 */
export function invoicedCheck(
  ctx: BlockSqlContext,
): ((row: string) => string) | undefined {
  const column = ctx.text("invoicedColumn", "");
  const check = ctx.text("invoicedCheck", "");

  if (column !== "" && check !== "") {
    throw new TypeError(
      "blocks.expenses.options takes invoicedColumn or invoicedCheck, not both",
    );
  }

  if (column !== "" && !/^[a-z_][a-z0-9_]{0,62}$/.test(column)) {
    throw new TypeError(
      "blocks.expenses.options.invoicedColumn names a column of the expenses table, such as invoice_id",
    );
  }

  if (check !== "" && !FUNCTION.test(check)) {
    throw new TypeError(
      'blocks.expenses.options.invoicedCheck is "schema.function", a function (expense_id uuid) returns boolean',
    );
  }

  if (check !== "") {
    const [schema = "", name = ""] = check.split(".");

    return (row) =>
      `${sqlIdent(schema)}.${sqlIdent(name)}(${row}.${ctx.col("expenses", "id")}) is not false`;
  }

  return column === ""
    ? undefined
    : (row) => `${row}.${sqlIdent(column)} is not null`;
}

export function standaloneContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  const employee = ownerIsEmployee(ctx, "blocks.expenses.options")
    ? ["uuid"]
    : [];

  const company = ctx.flag("companyExpenses", false) ? ["boolean"] : [];

  const extra = extraFieldsArg(
    ctx.extraColumns("expenses", EXPENSE_RESERVED),
  ).contract;

  return [
    {
      name: "upsert_expense_category",
      args: ["{id}", "text", "text", "text", "bigint", "bigint"],
      returns: "jsonb",
    },
    { name: "archive_expense_category", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_expense_categories",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    {
      name: "page_expense_categories",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    { name: "page_expenses", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "create_expense",
      args: [
        "{id}",
        "date",
        "bigint",
        "text",
        "uuid",
        "text",
        "text",
        "uuid",
        ...employee,
        ...company,
        "uuid",
        ...extra,
      ],
      returns: "jsonb",
    },
    {
      name: "update_expense",
      args: [
        "uuid",
        "date",
        "bigint",
        "text",
        "uuid",
        "text",
        "text",
        "text[]",
        ...extra,
      ],
      returns: "jsonb",
    },
    { name: "submit_expense", args: ["uuid"], returns: "jsonb" },
    { name: "withdraw_expense", args: ["uuid"], returns: "jsonb" },
    { name: "purge_expense", args: ["uuid"], returns: "boolean" },
    {
      name: "decide_expense",
      args: ["uuid", "boolean", "text", "uuid"],
      returns: "jsonb",
    },
    { name: "reimburse_expense", args: ["uuid", "text"], returns: "jsonb" },
    { name: "reopen_expense", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "reverse_expense_reimbursement",
      args: ["uuid", "text"],
      returns: "jsonb",
    },
    { name: "expense_self_decides", args: ["uuid"], returns: "boolean" },
    { name: "expense_self_decides_many", args: ["uuid[]"], returns: "uuid[]" },
    { name: "get_expense", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_expenses",
      args: ["{id}", "uuid", "text", "boolean", "integer", ...employee],
      returns: "jsonb",
    },
  ];
}
