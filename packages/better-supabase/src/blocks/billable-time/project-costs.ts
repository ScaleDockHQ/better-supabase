import type { Money } from "../../commerce/money.ts";

import { moneyOf, optionalMoneyOf } from "../money-codec.ts";
import { optionalText, recordOf, recordsOf, textOf } from "../shared.ts";

/** A project's costs and earnings in one currency. */
export interface ProjectCostTotals {
  readonly currency: string;
  /** Its time at the rate card's cost. */
  readonly timeCost: Money;
  /** Its time billed on invoices, at the billed rate. */
  readonly billed: Money;
  /** Posted expense lines on its `project` dimension, with accounting. */
  readonly expenses: Money;
  /** Posted income lines on its `project` dimension, with accounting. */
  readonly income: Money;
  /** `billed` and `income` less `timeCost` and `expenses`. */
  readonly margin: Money;
}

/** What `projectCosts` returns. */
export interface ProjectCosts {
  readonly projectId: string;
  readonly organizationId: string;
  /** The finished time on the project and its work items. */
  readonly hours: number;
  /** The hours no rate card cost applies to, left out of `timeCost`. */
  readonly uncostedHours: number;
  readonly budget?: Money;
  readonly budgetHours?: number;
  /** Per currency, in currency order. */
  readonly totals: readonly ProjectCostTotals[];
  /**
   * The share of the budget used: `hours` of `budgetHours`, and the time cost
   * and expenses in the budget's currency of `budget`. 1 is all of it.
   */
  readonly budgetUsed: { readonly hours?: number; readonly amount?: number };
}

const FN = "project_costs";

function totalsOf(value: unknown): ProjectCostTotals {
  const row = recordOf(value, FN);
  const currency = textOf(row["currency"]);
  const amount = (key: string): Money => moneyOf(row[key], currency, key);

  return {
    currency,
    timeCost: amount("timeCost"),
    billed: amount("billed"),
    expenses: amount("expenses"),
    income: amount("income"),
    margin: amount("margin"),
  };
}

const share = (used: number, of: number | undefined): number | undefined =>
  of === undefined || of === 0 ? undefined : used / of;

/** The `project_costs` result, with the budget use worked out. */
export function projectCostsOf(value: unknown): ProjectCosts {
  const row = recordOf(value, FN);
  const hours = Number(row["hours"] ?? 0);

  const budgetHours =
    row["budgetHours"] === null || row["budgetHours"] === undefined
      ? undefined
      : Number(row["budgetHours"]);

  const budgetCurrency = optionalText(row["budgetCurrency"]);

  const budget =
    budgetCurrency === undefined
      ? undefined
      : optionalMoneyOf(row["budgetAmount"], budgetCurrency, "budgetAmount");

  const totals = recordsOf(row["totals"] ?? [], FN).map(totalsOf);
  const spent = totals.find((item) => item.currency === budgetCurrency);

  const used =
    spent === undefined
      ? 0
      : Number(spent.timeCost.amount + spent.expenses.amount);

  const hoursUsed = share(hours, budgetHours);

  const amountUsed = share(
    used,
    budget === undefined ? undefined : Number(budget.amount),
  );

  return {
    projectId: textOf(row["projectId"]),
    organizationId: textOf(row["organizationId"]),
    hours,
    uncostedHours: Number(row["uncostedHours"] ?? 0),
    totals,
    budgetUsed: {
      ...(hoursUsed === undefined ? {} : { hours: hoursUsed }),
      ...(amountUsed === undefined ? {} : { amount: amountUsed }),
    },
    ...(budget === undefined ? {} : { budget }),
    ...(budgetHours === undefined ? {} : { budgetHours }),
  };
}
