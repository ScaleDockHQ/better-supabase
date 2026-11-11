import "server-only";
import type { Result } from "better-supabase";
import type { AssetListOptions } from "better-supabase/blocks/assets";
import type { MoneyJson } from "better-supabase/commerce";

import { moneyToJson } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { Temporal } from "temporal-polyfill";

import type { BlockListQuery, Mutable } from "@/lib/block-status-list";
import type { BlockPage } from "@/lib/block-page";

import { pageOverStatuses } from "@/lib/block-page";
import { bsb } from "@/lib/supabase/server";

import type { AssetRow } from "./asset-row";

import { ASSETS_TAG } from "./assets-cache";
import { ASSET_PAGE_SIZE, ASSET_STATUSES, assetList } from "./assets-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

type AssetQuery = BlockListQuery<"newest">;

const isStatus = (value: string): value is AssetRow["status"] =>
  ASSET_STATUSES.some((status) => status === value);

/**
 * One page of the register, filtered in the database: the block matches the
 * search against the name, tag and serial number and pages back from the
 * `createdAt` the cursor holds. The page and `/api/assets/list` share it.
 */
export function loadAssetPage(
  db: Db,
  query: AssetQuery,
): Promise<Result<BlockPage<AssetRow>>> {
  const before =
    query.after === undefined ? undefined : Temporal.Instant.from(query.after);

  return pageOverStatuses({
    statuses: query.facets["status"],
    size: ASSET_PAGE_SIZE,
    fetchPage: (status, take) => {
      const options: Mutable<AssetListOptions> = { pageSize: take };

      if (query.q !== undefined) {
        options.query = query.q;
      }

      if (status !== undefined && isStatus(status)) {
        options.status = status;
      }

      if (before !== undefined) {
        options.before = before;
      }

      return db.assets.assets(options);
    },
    map: (asset): AssetRow => ({
      id: asset.id,
      name: asset.name,
      kind: asset.kind,
      tag: asset.tag ?? null,
      serialNumber: asset.serialNumber ?? null,
      status: asset.status,
      assigned: asset.assignee !== undefined,
      cost: asset.acquisitionCost ? moneyToJson(asset.acquisitionCost) : null,
      createdAt: asset.createdAt.toString(),
    }),
  });
}

/**
 * The first page of the register. The page doesn't read `searchParams`, so it
 * stays in the instant shell; other states go through `/api/assets/list`.
 */
export async function getAssets(): Promise<BlockPage<AssetRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(ASSETS_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const result = await loadAssetPage(db, assetList.defaults);

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  return result.data;
}

export interface AssetDetailData {
  readonly id: string;
  readonly name: string;
  readonly kind: string;
  readonly tag: string | null;
  readonly serialNumber: string | null;
  readonly status: AssetRow["status"];
  readonly assigned: boolean;
  readonly locationPath: readonly string[];
  readonly createdAt: string;
  readonly cost: MoneyJson | null;
  readonly bookValue: MoneyJson | null;
  readonly accumulatedDepreciation: MoneyJson | null;
  readonly acquiredOn: string | null;
  readonly usefulLifeMonths: number | null;
}

/** One asset with its location path and book value; `null` when RLS hides it. */
export async function getAsset(id: string): Promise<AssetDetailData | null> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(ASSETS_TAG);

  const result = await db.assets.asset(id);

  if (!result.ok) {
    if (result.error.code === "not_found") {
      return null;
    }

    throw new Error(result.error.message);
  }

  const asset = result.data;

  return {
    id: asset.id,
    name: asset.name,
    kind: asset.kind,
    tag: asset.tag ?? null,
    serialNumber: asset.serialNumber ?? null,
    status: asset.status,
    assigned: asset.assignee !== undefined,
    locationPath: asset.locationPath.map((step) => step.name),
    createdAt: asset.createdAt.toString(),
    cost: asset.acquisitionCost ? moneyToJson(asset.acquisitionCost) : null,
    bookValue: asset.bookValue ? moneyToJson(asset.bookValue) : null,
    accumulatedDepreciation: asset.accumulatedDepreciation
      ? moneyToJson(asset.accumulatedDepreciation)
      : null,
    acquiredOn: asset.acquiredOn?.toString() ?? null,
    usefulLifeMonths: asset.usefulLifeMonths ?? null,
  };
}

export interface AssetAssignmentRow {
  readonly id: string;
  readonly assigneeType: string;
  readonly assigneeId: string;
  readonly note: string | null;
  readonly assignedAt: string;
  readonly releasedAt: string | null;
}

export interface AssetDepreciationRow {
  readonly id: string;
  readonly periodStart: string;
  readonly amount: MoneyJson;
}

/** Who held the asset, newest first, and the months it depreciated. */
export async function getAssetHistory(id: string) {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(ASSETS_TAG);

  const [assignments, depreciations] = await Promise.all([
    db.assets.assignments({ assetId: id, pageSize: 20 }),
    db.assets.depreciations({ assetId: id, pageSize: 60 }),
  ]);

  if (!assignments.ok) {
    throw new Error(assignments.error.message);
  }

  if (!depreciations.ok) {
    throw new Error(depreciations.error.message);
  }

  return {
    assignments: assignments.data.map((row): AssetAssignmentRow => ({
      id: row.id,
      assigneeType: row.assignee.type,
      assigneeId: row.assignee.id,
      note: row.note ?? null,
      assignedAt: row.assignedAt.toString(),
      releasedAt: row.releasedAt?.toString() ?? null,
    })),
    depreciations: depreciations.data.map((row): AssetDepreciationRow => ({
      id: row.id,
      periodStart: row.periodStart.toString(),
      amount: moneyToJson(row.amount),
    })),
  };
}
