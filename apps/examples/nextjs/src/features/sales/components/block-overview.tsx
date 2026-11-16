import type { ReactNode } from "react";

import { getLocale } from "next-intl/server";
import { unstable_rethrow } from "next/navigation";

import type { BlockColumn } from "@/components/record-list/block-list-view";
import type { BlockRowInput } from "@/components/record-list/money-text";
import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";
import type { EntityListMap, EntityPager } from "@/lib/block-entity-page";

import { BlockListView } from "@/components/record-list/block-list-view";
import { withMoneyCells } from "@/components/record-list/money-text";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { pageEntityRows } from "@/lib/block-entity-page";

import type { OverviewContext } from "./overview-support";

import { overviewContext } from "./overview-support";

export type { BlockColumn };

/** The rows an overview shows per page. */
const OVERVIEW_PAGE_SIZE = 25;

/**
 * The server half of a block-backed overview: the URL's search, facet filter,
 * sort and cursor go to the block's `page` and `facets` (`pageEntityRows`), so
 * the database filters, sorts and pages, and the client grid gets one page of
 * plain rows. Render it inside `<Suspense>`.
 */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function BlockOverview<Item>({
  pager,
  map,
  query,
  toRow,
  columns,
  facet,
  sorts,
  searchLabel,
  errorTitle,
  emptyIcon,
  emptyTitle,
  emptyDescription,
  emptyAction,
}: {
  /** The block list with the organization bound. */
  pager: (context: OverviewContext) => EntityPager<Item>;
  /** The URL's sort and facet names on the block's. The facet key is `f`. */
  map: EntityListMap;
  query: RecordListUrlQuery;
  toRow: (item: Item) => BlockRowInput | Promise<BlockRowInput>;
  columns: readonly BlockColumn[];
  facet?: {
    readonly key: string;
    readonly label: string;
    readonly values: Readonly<Record<string, string>>;
  };
  sorts: readonly { readonly value: string; readonly label: string }[];
  /** Omit it for a list the block cannot search. */
  searchLabel?: string;
  errorTitle: string;
  emptyIcon: ReactNode;
  emptyTitle: string;
  emptyDescription: string;
  emptyAction?: ReactNode;
}) {
  const context = await overviewContext();

  if (context === null) {
    return null;
  }

  const locale = await getLocale();

  const defaultSort = sorts[0]?.value ?? "";

  // A block that cannot search or filter refuses `q` and `f`, so a stale
  // `?q=` or `?f=` is dropped.
  const { q: _search, ...unsearched } = query;
  const searchable = searchLabel === undefined ? unsearched : query;

  const scoped =
    facet === undefined ? { ...searchable, facets: {} } : searchable;

  let page: RecordListPage<ReturnType<typeof withMoneyCells>>;

  try {
    page = await pageEntityRows({
      pager: pager(context),
      map,
      query: { ...scoped, sort: query.sort === "" ? defaultSort : query.sort },
      pageSize: OVERVIEW_PAGE_SIZE,
      rowsOf: async (items) =>
        (
          await Promise.all(items.map((item) => Promise.resolve(toRow(item))))
        ).map((row) => withMoneyCells(row, columns, locale)),
    });
  } catch (error) {
    unstable_rethrow(error);

    return <CrmLoadError title={errorTitle} />;
  }

  const selected = query.facets["f"]?.[0];
  const counts = page.facetCounts?.["f"] ?? {};

  const facetOptions = facet
    ? Object.entries(facet.values)
        .map(([value, label]) => ({ value, label, count: counts[value] ?? 0 }))
        .filter((option) => option.count > 0 || option.value === selected)
    : undefined;

  return (
    <BlockListView
      rows={page.items}
      columns={columns}
      {...(facet && facetOptions
        ? { facetKey: facet.key, facetLabel: facet.label, facetOptions }
        : {})}
      sorts={sorts}
      {...(searchLabel === undefined ? {} : { searchLabel })}
      nextCursor={page.nextCursor ?? null}
      emptyIcon={emptyIcon}
      emptyTitle={emptyTitle}
      emptyDescription={emptyDescription}
      emptyAction={emptyAction}
    />
  );
}
