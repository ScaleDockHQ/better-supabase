import type { Money } from "../commerce/money.ts";

import { moneyOf, optionalMoneyOf } from "./money-codec.ts";
import { optionalText, recordOf, recordsOf, textOf } from "./shared.ts";

/** The forecast call for one currency. */
export interface DealForecast {
  readonly currency: string;
  readonly won: Money;
  readonly commit: Money;
  readonly bestCase: Money;
  readonly pipeline: Money;
  readonly notCalled: Money;
  readonly omit: Money;
  /** Open deals that close after the period. */
  readonly later: Money;
  readonly target?: Money;
  /** Won plus commit over the target. */
  readonly attainment?: number;
  readonly gap?: Money;
  readonly owners: readonly (Omit<
    DealForecast,
    "owners" | "currency" | "target" | "attainment" | "gap"
  > & { readonly ownerId?: string })[];
}

function sums(
  row: Readonly<Record<string, unknown>>,
  currency: string,
  fn: string,
) {
  const at = (key: string): Money =>
    moneyOf(row[key], currency, `${fn} ${key}`);

  return {
    won: at("won"),
    commit: at("commit"),
    bestCase: at("bestCase"),
    pipeline: at("pipeline"),
    notCalled: at("notCalled"),
    omit: at("omit"),
    later: at("later"),
  };
}

/** Decodes `deal_forecast`'s totals; `fn` names the function in errors. */
export function forecastOf(value: unknown, fn = "deal_forecast"): DealForecast {
  const row = recordOf(value, fn);
  const currency = textOf(row["currency"]);
  const target = optionalMoneyOf(row["target"], currency, `${fn} target`);
  const gap = optionalMoneyOf(row["gap"], currency, `${fn} gap`);
  const attainment = row["attainment"];

  return {
    currency,
    ...sums(row, currency, fn),
    ...(target === undefined ? {} : { target }),
    ...(typeof attainment === "number" ? { attainment } : {}),
    ...(gap === undefined ? {} : { gap }),
    owners: recordsOf(row["owners"], `${fn} owners`).map((owner) => {
      const ownerId = optionalText(owner["ownerId"]);

      return {
        ...(ownerId === undefined ? {} : { ownerId }),
        ...sums(owner, currency, fn),
      };
    }),
  };
}
