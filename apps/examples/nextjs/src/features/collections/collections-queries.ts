import "server-only";
import type { Result } from "better-supabase";
import type { Collection } from "better-supabase/blocks/collections";

import { ok } from "better-supabase";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { BlockPage } from "@/lib/block-page";
import type { BlockListQuery } from "@/lib/block-status-list";

import { bsb } from "@/lib/supabase/server";

import type { CollectionRow } from "./collection-row";

import { COLLECTIONS_TAG } from "./collections-cache";
import { collectionList } from "./collections-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

function toRow(collection: Collection): CollectionRow {
  return {
    id: collection.id,
    name: collection.name,
    description: collection.description ?? null,
    subjectType: collection.subjectType,
    scope: collection.scope,
    archived: collection.archived,
    createdAt: collection.createdAt.toString(),
  };
}

/** The collections the filters keep, newest first. */
export async function loadCollectionPage(
  db: Db,
  organizationId: string,
  query: BlockListQuery<"newest">,
): Promise<Result<BlockPage<CollectionRow>>> {
  const scopes = query.facets["scope"] ?? [];
  const states = query.facets["state"] ?? [];

  const result = await db.collections.list({
    organizationId,
    includeArchived: states.includes("archived"),
  });

  if (!result.ok) {
    return result;
  }

  const items = result.data
    .map(toRow)
    .filter(
      (row) =>
        (scopes.length === 0 || scopes.includes(row.scope)) &&
        (states.length === 0 ||
          states.includes(row.archived ? "archived" : "active")),
    )
    .toSorted((a, b) => b.createdAt.localeCompare(a.createdAt));

  return ok({ items, nextCursor: null });
}

/** The first page of collections, for the instant shell. */
export async function getCollections(): Promise<BlockPage<CollectionRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(COLLECTIONS_TAG);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const result = await loadCollectionPage(
    db,
    organizationId,
    collectionList.defaults,
  );

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  return result.data;
}

export interface CollectionEntryRow {
  readonly subjectId: string;
  readonly title: string;
}

export interface CollectionDetailData extends CollectionRow {
  readonly entries: readonly CollectionEntryRow[];
  readonly candidates: readonly {
    readonly id: string;
    readonly name: string;
  }[];
}

/** One collection with its entries and the customers it can still take. */
export async function getCollection(
  id: string,
): Promise<CollectionDetailData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(COLLECTIONS_TAG);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [all, entries, customers] = await Promise.all([
    db.collections.list({ organizationId, includeArchived: true }),
    db.collections.entries({ id, limit: 100 }),
    db.customers.list({
      orderBy: { name: "asc" },
      limit: 100,
      select: ["id", "name"],
    }),
  ]);

  if (!all.ok) {
    throw new Error(all.error.message);
  }

  const collection = all.data.find((row) => row.id === id);

  if (collection === undefined) {
    return null;
  }

  if (!entries.ok) {
    throw new Error(entries.error.message);
  }

  const inside = new Set(entries.data.items.map((entry) => entry.subjectId));

  return {
    ...toRow(collection),
    entries: entries.data.items.map((entry) => ({
      subjectId: entry.subjectId,
      title: entry.title ?? entry.subjectId.slice(0, 8),
    })),
    candidates: customers.ok
      ? customers.data
          .filter((row) => !inside.has(row.id))
          .map((row) => ({ id: row.id, name: row.name }))
      : [],
  };
}
