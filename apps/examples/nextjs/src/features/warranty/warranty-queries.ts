import "server-only";
import type { Result } from "better-supabase";
import type { WarrantyClaimListOptions } from "better-supabase/blocks/warranty";

import { ok } from "better-supabase";
import { money, moneyToJson } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { BlockPage } from "@/lib/block-page";
import type { BlockListQuery, Mutable } from "@/lib/block-status-list";

import { bsb } from "@/lib/supabase/server";

import type { ClaimRow } from "./claim-row";

import { WARRANTY_TAG } from "./warranty-cache";
import { CLAIM_PAGE_SIZE, CLAIM_STATUSES, claimList } from "./warranty-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

const isStatus = (value: string): value is ClaimRow["status"] =>
  CLAIM_STATUSES.some((status) => status === value);

/** The names of the assets the claims cover, in one request. */
async function assetNames(db: Db): Promise<ReadonlyMap<string, string>> {
  const assets = await db.assets.assets({ pageSize: 100 });

  return new Map(assets.ok ? assets.data.map((row) => [row.id, row.name]) : []);
}

/**
 * The claims of the selected statuses, one block call per status in parallel.
 * Shared by the page and `/api/warranty/list`.
 */
export async function loadClaimPage(
  db: Db,
  query: BlockListQuery<"newest">,
): Promise<Result<BlockPage<ClaimRow>>> {
  const wanted = (query.facets["status"] ?? []).filter(isStatus);
  const statuses = wanted.length > 0 ? wanted : [undefined];

  const [results, names] = await Promise.all([
    Promise.all(
      statuses.map((status) => {
        const options: Mutable<WarrantyClaimListOptions> = {
          limit: CLAIM_PAGE_SIZE,
        };

        if (status !== undefined) {
          options.status = status;
        }

        return db.warranty.list(options);
      }),
    ),
    assetNames(db),
  ]);

  const items: ClaimRow[] = [];

  for (const result of results) {
    if (!result.ok) {
      return result;
    }

    for (const claim of result.data) {
      items.push({
        id: claim.id,
        title: claim.title,
        asset: names.get(claim.assetId) ?? claim.assetId.slice(0, 8),
        status: claim.status,
        amount: moneyToJson(money(claim.amount, claim.currency)),
        claimant: claim.manufacturer ?? null,
      });
    }
  }

  return ok({ nextCursor: null, items });
}

/** The first page of claims, for the instant shell. */
export async function getClaims(): Promise<BlockPage<ClaimRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(WARRANTY_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const result = await loadClaimPage(db, claimList.defaults);

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  return result.data;
}

export interface ClaimDetailData extends ClaimRow {
  readonly decision: string | null;
  readonly decidedAt: string | null;
}

/** One claim; `null` when it does not exist or RLS hides it. */
export async function getClaim(id: string): Promise<ClaimDetailData | null> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(WARRANTY_TAG);

  const result = await db.warranty.list({ limit: CLAIM_PAGE_SIZE });

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  const claim = result.data.find((row) => row.id === id);

  if (claim === undefined) {
    return null;
  }

  const names = await assetNames(db);

  return {
    id: claim.id,
    title: claim.title,
    asset: names.get(claim.assetId) ?? claim.assetId.slice(0, 8),
    status: claim.status,
    amount: moneyToJson(money(claim.amount, claim.currency)),
    claimant: claim.manufacturer ?? null,
    decision: claim.decision ?? null,
    decidedAt: claim.decidedAt?.toString() ?? null,
  };
}

export interface ClaimFormOptions {
  readonly assets: readonly { readonly id: string; readonly name: string }[];
}

/** The assets a claim can cover. */
export async function getClaimFormOptions(): Promise<ClaimFormOptions> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(WARRANTY_TAG);

  const assets = await db.assets.assets({ status: "active", pageSize: 100 });

  if (!assets.ok) {
    throw new Error(assets.error.message);
  }

  return {
    assets: assets.data.map((asset) => ({ id: asset.id, name: asset.name })),
  };
}
