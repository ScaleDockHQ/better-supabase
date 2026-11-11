"use client";

import type { RowData } from "@tanstack/react-table";

import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";

import type { RecordListColumns } from "./record-list-grid";
import type {
  RecordListFacet,
  RecordListPage,
  RecordListSort,
  RecordListUrl,
} from "./record-list-types";

import { RecordListFacets } from "./record-list-facets";
import { RecordListGrid } from "./record-list-grid";
import { RecordListToolbar } from "./record-list-toolbar";
import { useRecordListPage } from "./use-record-list-page";

/**
 * The overview kit: a toolbar, a read-only grid and cursor paging over one list
 * query. All state lives in the URL (`useRecordListState`), so a link carries
 * the search, the filters, the sort and the page. A feature supplies the URL
 * state, the columns, the list route and the first page.
 */
export function RecordListView<Row extends RowData & { readonly id: string }>({
  list,
  endpoint,
  initial,
  columns,
  facets,
  sorts,
  searchLabel,
  emptyIcon,
  emptyTitle,
  emptyDescription,
  emptyAction,
}: {
  list: RecordListUrl;
  /** The list route, such as `/api/customers/list`. */
  endpoint: string;
  initial: RecordListPage<Row>;
  columns: RecordListColumns<Row>;
  facets: readonly RecordListFacet[];
  sorts: readonly RecordListSort[];
  searchLabel: string;
  emptyIcon: React.ReactNode;
  emptyTitle: string;
  emptyDescription: string;
  /** Shown beside Reset when the filters match nothing; omit for Reset alone. */
  emptyAction?: React.ReactNode;
}) {
  const t = useExtracted("recordList");

  const search = list.searchParams.toString();

  const { page, pending, failed, retry } = useRecordListPage<Row>({
    endpoint,
    search,
    initial,
  });

  const rows = page?.items ?? [];
  const filtered = search !== "";

  return (
    <div className="flex flex-col gap-4" data-testid="record-list">
      <RecordListToolbar
        q={list.query.q ?? ""}
        searchLabel={searchLabel}
        sort={list.query.sort}
        sorts={sorts}
        filters={
          facets.length > 0 ? (
            <RecordListFacets
              facets={facets}
              selected={list.query.facets}
              counts={page?.facetCounts}
              capped={page?.facetCountsCapped === true}
              onChange={(patch) => {
                list.set(patch);
              }}
            />
          ) : null
        }
        onSearch={(value) => {
          list.set({ q: value === "" ? null : value });
        }}
        onSort={(value) => {
          list.set({ sort: value });
        }}
      />
      <RecordListGrid
        rows={rows}
        columns={columns}
        failed={failed}
        pending={pending}
        emptyIcon={emptyIcon}
        emptyTitle={emptyTitle}
        emptyDescription={emptyDescription}
        emptyAction={
          <div className="flex items-center gap-2">
            {filtered ? (
              <Button
                size="sm"
                variant="outline"
                onClick={() => {
                  list.reset();
                }}
              >
                {t("Reset filters")}
              </Button>
            ) : null}
            {emptyAction}
          </div>
        }
        onRetry={retry}
      />
      {list.query.after !== undefined || page?.nextCursor ? (
        <div className="flex items-center justify-end gap-2">
          {list.query.after === undefined ? null : (
            <Button
              size="sm"
              variant="outline"
              onClick={() => {
                list.setPage(null);
              }}
            >
              {t("First page")}
            </Button>
          )}
          {page?.nextCursor ? (
            <Button
              size="sm"
              variant="outline"
              disabled={pending}
              onClick={() => {
                list.setPage(page.nextCursor ?? null);
              }}
            >
              {t("Next page")}
            </Button>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
