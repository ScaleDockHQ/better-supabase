import "server-only";
import type { Result } from "better-supabase";
import type { GiftListOptions } from "better-supabase/blocks/donations";

import { ok } from "better-supabase";
import { moneyToJson } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { BlockListQuery, Mutable } from "@/lib/block-status-list";
import type { BlockPage } from "@/lib/block-page";

import { bsb } from "@/lib/supabase/server";

import type { GiftRow } from "./gift-row";

import { DONATIONS_TAG } from "./donations-cache";
import { GIFT_PAGE_SIZE, GIFT_STATUSES, giftList } from "./donations-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

const isStatus = (value: string): value is GiftRow["status"] =>
  GIFT_STATUSES.some((status) => status === value);

/** The names of the customers who gave, in one request. */
async function donorNames(
  db: Db,
  ids: readonly string[],
): Promise<ReadonlyMap<string, string>> {
  if (ids.length === 0) {
    return new Map();
  }

  const customers = await db.customers.list({
    where: { id: { in: [...ids] } },
    select: ["id", "name"],
    limit: ids.length,
  });

  return new Map(
    customers.ok ? customers.data.map((row) => [row.id, row.name]) : [],
  );
}

/**
 * The gifts of the selected statuses, one block call per status in parallel,
 * newest first. Shared by the page and `/api/donations/list`.
 */
export async function loadGiftPage(
  db: Db,
  query: BlockListQuery<"newest">,
): Promise<Result<BlockPage<GiftRow>>> {
  const wanted = (query.facets["status"] ?? []).filter(isStatus);
  const statuses = wanted.length > 0 ? wanted : [undefined];

  const results = await Promise.all(
    statuses.map((status) => {
      const options: Mutable<GiftListOptions> = { pageSize: GIFT_PAGE_SIZE };

      if (status !== undefined) {
        options.status = status;
      }

      return db.donations.gifts(options);
    }),
  );

  const gifts = [];

  for (const result of results) {
    if (!result.ok) {
      return result;
    }

    gifts.push(...result.data);
  }

  gifts.sort((a, b) =>
    b.receivedOn.toString().localeCompare(a.receivedOn.toString()),
  );

  const names = await donorNames(
    db,
    gifts
      .filter((gift) => gift.donor.type === "customer")
      .map((gift) => gift.donor.id),
  );

  return ok({
    nextCursor: null,
    items: gifts.map((gift): GiftRow => ({
      id: gift.id,
      donor: names.get(gift.donor.id) ?? gift.donor.id.slice(0, 8),
      status: gift.status,
      amount: moneyToJson(gift.amount),
      receivedOn: gift.receivedOn.toString(),
      hasReceipt: gift.receiptId !== undefined,
    })),
  });
}

/** The first page of gifts, for the instant shell. */
export async function getGifts(): Promise<BlockPage<GiftRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(DONATIONS_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const result = await loadGiftPage(db, giftList.defaults);

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  return result.data;
}

export interface GiftDetailData extends GiftRow {
  readonly fund: string | null;
  readonly method: string | null;
  readonly note: string | null;
  readonly receiptNumber: string | null;
}

/** One gift with its fund and receipt; `null` when RLS hides it. */
export async function getGift(id: string): Promise<GiftDetailData | null> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(DONATIONS_TAG);

  const result = await db.donations.getGift(id);

  if (!result.ok) {
    if (result.error.code === "not_found") {
      return null;
    }

    throw new Error(result.error.message);
  }

  const gift = result.data;

  const [names, funds, receipts] = await Promise.all([
    donorNames(db, gift.donor.type === "customer" ? [gift.donor.id] : []),
    db.donations.funds(),
    gift.receiptId === undefined
      ? Promise.resolve(null)
      : db.donations.receipts({ pageSize: 100 }),
  ]);

  const fund = funds.ok
    ? funds.data.find((row) => row.id === gift.fundId)?.name
    : undefined;

  const receipt = receipts?.ok
    ? receipts.data.find((row) => row.id === gift.receiptId)
    : undefined;

  return {
    id: gift.id,
    donor: names.get(gift.donor.id) ?? gift.donor.id.slice(0, 8),
    status: gift.status,
    amount: moneyToJson(gift.amount),
    receivedOn: gift.receivedOn.toString(),
    hasReceipt: gift.receiptId !== undefined,
    fund: fund ?? null,
    method: gift.method ?? null,
    note: gift.note ?? null,
    receiptNumber: receipt?.number ?? null,
  };
}

export interface GiftFormOptions {
  readonly donors: readonly { readonly id: string; readonly name: string }[];
  readonly funds: readonly { readonly id: string; readonly name: string }[];
}

/** The customers who can give and the open funds. */
export async function getGiftFormOptions(): Promise<GiftFormOptions> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(DONATIONS_TAG);

  const [donors, funds] = await Promise.all([
    db.customers.list({
      orderBy: { name: "asc" },
      limit: 100,
      select: ["id", "name"],
    }),
    db.donations.funds(),
  ]);

  if (!donors.ok) {
    throw new Error(donors.error.message);
  }

  if (!funds.ok) {
    throw new Error(funds.error.message);
  }

  return {
    donors: donors.data.map((row) => ({ id: row.id, name: row.name })),
    funds: funds.data.map((row) => ({ id: row.id, name: row.name })),
  };
}
