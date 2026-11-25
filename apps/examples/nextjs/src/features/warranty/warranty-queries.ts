import "server-only";
import type { Result } from "better-supabase";

import { ok } from "better-supabase";
import { money, moneyToJson } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { BlockPage } from "@/lib/block-page";
import type { BlockListQuery } from "@/lib/block-status-list";

import { encodeCursor, pageOptionsOf } from "@/lib/block-page";
import { bsb } from "@/lib/supabase/server";

import type { ClaimRow } from "./claim-row";

import { WARRANTY_TAG } from "./warranty-cache";
import { CLAIM_PAGE_SIZE, CLAIM_STATUSES, claimList } from "./warranty-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

const isStatus = (value: string): value is ClaimRow["status"] =>
  CLAIM_STATUSES.some((status) => status === value);

/** The names of the assets the claims cover, in one request. */
async function assetNames(db: Db): Promise<ReadonlyMap<string, string>> {
  const assets = await db.assets.page({ limit: 100 });

  return new Map(
    assets.ok ? assets.data.items.map((row) => [row.id, row.name]) : [],
  );
}

/**
 * One page of claims: the selected statuses go to the block as one list filter,
 * `q` searches the title, and the keyset cursor `after` holds pages on. Shared
 * by the page and `/api/warranty/list`.
 */
export async function getClaimPage(
  db: Db,
  query: BlockListQuery<"newest">,
): Promise<Result<BlockPage<ClaimRow>>> {
  const statuses = (query.facets["status"] ?? []).filter(isStatus);

  const [result, names] = await Promise.all([
    db.warranty.page(
      pageOptionsOf(query, CLAIM_PAGE_SIZE, { status: statuses }),
    ),
    assetNames(db),
  ]);

  if (!result.ok) {
    return result;
  }

  return ok({
    items: result.data.items.map((claim): ClaimRow => ({
      id: claim.id,
      title: claim.title,
      asset: names.get(claim.assetId) ?? claim.assetId.slice(0, 8),
      status: claim.status,
      amount: moneyToJson(money(claim.amount, claim.currency)),
      claimant: claim.manufacturer ?? null,
    })),
    nextCursor: encodeCursor(result.data.nextCursor),
  });
}

/** The first page of claims, for the instant shell. */
export async function getClaims(): Promise<BlockPage<ClaimRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(WARRANTY_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const result = await getClaimPage(db, claimList.defaults);

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

  const result = await db.warranty.get(id);

  if (!result.ok) {
    if (result.error.kind === "not_found") {
      return null;
    }

    throw new Error(result.error.message);
  }

  const claim = result.data;

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

  const assets = await db.assets.page({
    filters: { status: ["active"] },
    limit: 100,
  });

  if (!assets.ok) {
    throw new Error(assets.error.message);
  }

  return {
    assets: assets.data.items.map((asset) => ({
      id: asset.id,
      name: asset.name,
    })),
  };
}
