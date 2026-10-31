import "server-only";
import type { MoneyJson } from "better-supabase/commerce";

import { moneyToJson } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";

import type { Loaded } from "@/features/shop/shop-queries";

import { SHOP_CURRENCY } from "@/features/shop/shop-currency";
import { settle } from "@/features/shop/shop-queries";
import { bsb } from "@/lib/supabase/server";

/** What the organization owes its suppliers, by days past due, serializable. */
export interface PayablesAging {
  readonly asOf: string;
  readonly current: MoneyJson;
  readonly days1To30: MoneyJson;
  readonly days31To60: MoneyJson;
  readonly days61To90: MoneyJson;
  readonly over90: MoneyJson;
  readonly outstanding: MoneyJson;
  readonly overdueCount: number;
}

async function loadPayables(): Promise<PayablesAging | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const asOf = Temporal.Now.plainDateISO("UTC");

  const aging = await db.invoices
    .aging(tenant, SHOP_CURRENCY, asOf, "purchase")
    .orThrow();

  return {
    asOf: asOf.toString(),
    current: moneyToJson(aging.current),
    days1To30: moneyToJson(aging.days1To30),
    days31To60: moneyToJson(aging.days31To60),
    days61To90: moneyToJson(aging.days61To90),
    over90: moneyToJson(aging.over90),
    outstanding: moneyToJson(aging.outstanding),
    overdueCount: aging.overdueCount,
  };
}

/** The open purchase bills in the shop's currency, by days past due. */
export function getPayablesAging(): Promise<Loaded<PayablesAging>> {
  return settle(loadPayables);
}
