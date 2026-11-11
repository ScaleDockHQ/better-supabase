import "server-only";
import type { Result } from "better-supabase";
import type { LeaseListOptions } from "better-supabase/blocks/leases";
import type { MoneyJson } from "better-supabase/commerce";

import { ok } from "better-supabase";
import { moneyToJson } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { BlockListQuery, Mutable } from "@/lib/block-status-list";
import type { BlockPage } from "@/lib/block-page";

import { bsb } from "@/lib/supabase/server";

import type { LeaseRow } from "./lease-row";

import { LEASES_TAG } from "./leases-cache";
import { LEASE_PAGE_SIZE, LEASE_STATUSES, leaseList } from "./leases-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

const isStatus = (value: string): value is LeaseRow["status"] =>
  LEASE_STATUSES.some((status) => status === value);

/**
 * The leases of the selected statuses, one block call per status in parallel,
 * newest start first. Shared by the page and `/api/leases/list`.
 */
export async function loadLeasePage(
  db: Db,
  query: BlockListQuery<"newest">,
): Promise<Result<BlockPage<LeaseRow>>> {
  const wanted = (query.facets["status"] ?? []).filter(isStatus);
  const statuses = wanted.length > 0 ? wanted : [undefined];

  const results = await Promise.all(
    statuses.map((status) => {
      const options: Mutable<LeaseListOptions> = { pageSize: LEASE_PAGE_SIZE };

      if (status !== undefined) {
        options.status = status;
      }

      return db.leases.list(options);
    }),
  );

  const rows: LeaseRow[] = [];

  for (const result of results) {
    if (!result.ok) {
      return result;
    }

    for (const lease of result.data) {
      rows.push({
        id: lease.id,
        title: lease.title,
        status: lease.status,
        startsOn: lease.startsOn.toString(),
        endsOn: lease.endsOn?.toString() ?? null,
        rent: moneyToJson(lease.rent),
        frequency: lease.frequency,
        balanceDue: moneyToJson(lease.balanceDue),
      });
    }
  }

  rows.sort((a, b) => b.startsOn.localeCompare(a.startsOn));

  return ok({ items: rows, nextCursor: null });
}

/** The first page of leases, for the instant shell. */
export async function getLeases(): Promise<BlockPage<LeaseRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(LEASES_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const result = await loadLeasePage(db, leaseList.defaults);

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  return result.data;
}

export interface LeaseDetailData extends LeaseRow {
  readonly unitId: string;
  readonly partyType: string;
  readonly partyId: string;
  readonly deposit: MoneyJson;
  readonly depositHeld: MoneyJson;
  readonly terminatedOn: string | null;
  readonly terminationReason: string | null;
}

/** One lease; `null` when RLS hides it. */
export async function getLease(id: string): Promise<LeaseDetailData | null> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(LEASES_TAG);

  const result = await db.leases.get(id);

  if (!result.ok) {
    if (result.error.code === "not_found") {
      return null;
    }

    throw new Error(result.error.message);
  }

  const lease = result.data;

  return {
    id: lease.id,
    title: lease.title,
    status: lease.status,
    startsOn: lease.startsOn.toString(),
    endsOn: lease.endsOn?.toString() ?? null,
    rent: moneyToJson(lease.rent),
    frequency: lease.frequency,
    balanceDue: moneyToJson(lease.balanceDue),
    unitId: lease.unitId,
    partyType: lease.party.type,
    partyId: lease.party.id,
    deposit: moneyToJson(lease.deposit),
    depositHeld: moneyToJson(lease.depositHeld),
    terminatedOn: lease.terminatedOn?.toString() ?? null,
    terminationReason: lease.terminationReason ?? null,
  };
}

export interface LeaseChargeRow {
  readonly id: string;
  readonly periodStart: string;
  readonly periodEnd: string;
  readonly amount: MoneyJson;
}

/** The rent periods posted, newest first. */
export async function getLeaseCharges(
  id: string,
): Promise<readonly LeaseChargeRow[]> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(LEASES_TAG);

  const result = await db.leases.charges({ leaseId: id, pageSize: 36 });

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  return result.data.map((charge) => ({
    id: charge.id,
    periodStart: charge.periodStart.toString(),
    periodEnd: charge.periodEnd.toString(),
    amount: moneyToJson(charge.amount),
  }));
}

export interface LeaseFormOptions {
  readonly units: readonly { readonly id: string; readonly name: string }[];
  readonly parties: readonly { readonly id: string; readonly name: string }[];
}

/** The assets a lease can rent out and the customers who can rent them. */
export async function getLeaseFormOptions(): Promise<LeaseFormOptions> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(LEASES_TAG);

  const [units, parties] = await Promise.all([
    db.assets.assets({ status: "active", pageSize: 100 }),
    db.customers.list({
      orderBy: { name: "asc" },
      limit: 100,
      select: ["id", "name"],
    }),
  ]);

  if (!units.ok) {
    throw new Error(units.error.message);
  }

  if (!parties.ok) {
    throw new Error(parties.error.message);
  }

  return {
    units: units.data.map((asset) => ({ id: asset.id, name: asset.name })),
    parties: parties.data.map((customer) => ({
      id: customer.id,
      name: customer.name,
    })),
  };
}
