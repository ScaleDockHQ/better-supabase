import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";
import * as v from "valibot";

import type { FinanceEntityKey, FinanceListQuery } from "@/lib/finance-list";
import type { RecordListPage } from "@/components/record-list/record-list-types";

import { BANKING_TAG } from "@/features/banking/banking-cache";
import { BILLING_TAG } from "@/features/billing/billing-cache";
import { SHOP_TAG } from "@/features/shop/shop-cache";
import {
  defineFinanceList,
  financeFixedFacets,
  financeSqlEntity,
} from "@/lib/finance-list";
import { bsbCore } from "@/lib/supabase/server-core";

import type { FinanceRecord, FinanceRow } from "./finance-records-types";

import { FINANCE_RECORDS_TAG } from "./finance-records-cache";

const PAGE_SIZE = 50;

const Page = v.object({
  items: v.array(v.looseObject({ id: v.string() })),
  nextCursor: v.nullable(v.string()),
  facetCounts: v.nullish(v.record(v.string(), v.record(v.string(), v.number()))),
  facetCountsCapped: v.nullish(v.boolean()),
});

const RecordRow = v.nullable(v.record(v.string(), v.unknown()));

type CoreDb = Awaited<ReturnType<typeof bsbCore.cached>>["db"];

/**
 * One page of an entity through `api.finance_list`. The fixed facets of an
 * entity (payables are purchase invoices) override the URL's.
 */
export async function runFinanceList(
  db: CoreDb,
  tenant: string,
  entity: FinanceEntityKey,
  query: FinanceListQuery,
): Promise<RecordListPage<FinanceRow>> {
  const page = await db
    .$api(
      "finance_list",
      {
        entity: financeSqlEntity(entity),
        tenant,
        q: query.q ?? null,
        filters: { ...query.facets, ...financeFixedFacets(entity) },
        sort: query.sort,
        after: query.after ?? null,
        lim: PAGE_SIZE,
      },
      { returns: Page },
    )
    .orThrow();

  return {
    items: page.items,
    nextCursor: page.nextCursor,
    ...(page.facetCounts
      ? {
          facetCounts: page.facetCounts,
          facetCountsCapped: page.facetCountsCapped === true,
        }
      : {}),
  };
}

/**
 * The first page of an entity, for the server render of its overview. The page
 * doesn't read `searchParams`, so it stays in the instant App Shell; every other
 * URL state goes through the entity's list route.
 */
async function readFirstPage(
  entity: FinanceEntityKey,
): Promise<RecordListPage<FinanceRow> | null> {
  "use cache: private";
  const { session, db } = await bsbCore.cached();
  cacheTag(FINANCE_RECORDS_TAG, BILLING_TAG, BANKING_TAG, SHOP_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  return runFinanceList(db, tenant, entity, defineFinanceList(entity).defaults);
}

export type FinanceLoaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
async function settle<T>(load: () => Promise<T | null>): Promise<FinanceLoaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

/** The first page of an entity's overview, or why there is none. */
export function getFinanceFirstPage(
  entity: FinanceEntityKey,
): Promise<FinanceLoaded<RecordListPage<FinanceRow>>> {
  return settle(() => readFirstPage(entity));
}

async function readRecord(
  entity: FinanceEntityKey,
  id: string,
): Promise<FinanceRecord | null> {
  "use cache: private";
  const { session, db } = await bsbCore.cached();
  cacheTag(FINANCE_RECORDS_TAG, BILLING_TAG, BANKING_TAG, SHOP_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  return db
    .$api(
      "finance_detail",
      { entity: financeSqlEntity(entity), tenant, id },
      { returns: RecordRow },
    )
    .orThrow();
}

/** One record with its child rows, or why there is none. */
export function getFinanceRecord(
  entity: FinanceEntityKey,
  id: string,
): Promise<FinanceLoaded<FinanceRecord>> {
  return settle(() => readRecord(entity, id));
}
