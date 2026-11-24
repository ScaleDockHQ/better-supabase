"use client";

import type { RowData } from "@tanstack/react-table";

import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";

import type { ExportColumn } from "./record-export-button";
import type { RecordListColumns, RecordListSorting } from "./record-list-grid";
import type {
  RecordListFacet,
  RecordListPage,
  RecordListSort,
  RecordListUrl,
} from "./record-list-types";

import { RecordBulkBar } from "./record-bulk-bar";
import { RecordExportButton } from "./record-export-button";
import { RecordListFacetsLazy } from "./record-list-facets-lazy";
import { RecordListGrid } from "./record-list-grid";
import { RecordListToolbar } from "./record-list-toolbar";
import { RecordSelectionProvider, selectColumn } from "./record-select-column";
import { SavedViews } from "./saved-views";
import { useRecordListPage } from "./use-record-list-page";
import { useRecordSelection } from "./use-record-selection";

/**
 * The column the first term of a `sort` value names (`number:asc,title` is
 * `number`).
 */
function firstSortOf(sort: string): string {
  return sort.split(",")[0]?.split(":")[0] ?? sort;
}

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
  sorting,
  savedViewsScope,
  exportColumns,
  exportName,
  bulkActions,
}: {
  list: RecordListUrl;
  /** The list route, such as `/api/customers/list`. */
  endpoint: string;
  initial: RecordListPage<Row>;
  columns: RecordListColumns<Row>;
  facets: readonly RecordListFacet[];
  sorts: readonly RecordListSort[];
  /** Omit it for a list the block cannot search. */
  searchLabel?: string;
  emptyIcon: React.ReactNode;
  emptyTitle: string;
  emptyDescription: string;
  /** Shown beside Reset when the filters match nothing; omit for Reset alone. */
  emptyAction?: React.ReactNode;
  /** Header sorting; the toolbar select then follows the first term. */
  sorting?: RecordListSorting;
  /** Turns on saved views (kept in this browser) under this list key. */
  savedViewsScope?: string;
  /** Turns on the CSV export of the rows on screen (or the ticked ones). */
  exportColumns?: readonly ExportColumn<Row>[];
  exportName?: string;
  /** Turns on row selection and the bulk bar; receives the ticked ids. */
  bulkActions?: (ids: readonly string[], clear: () => void) => React.ReactNode;
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
  const selection = useRecordSelection();

  const gridColumns: RecordListColumns<Row> =
    bulkActions === undefined ? columns : [selectColumn<Row>(), ...columns];

  const exported =
    selection.count > 0 ? rows.filter((row) => selection.has(row.id)) : rows;

  const scope = { selection, ids: rows.map((row) => row.id) };

  return (
    <RecordSelectionProvider value={scope}>
      <div className="flex flex-col gap-4" data-testid="record-list">
        <RecordListToolbar
          q={list.query.q ?? ""}
          searchLabel={searchLabel}
          sort={firstSortOf(list.query.sort)}
          sorts={sorts}
          filters={
            facets.length > 0 ? (
              <RecordListFacetsLazy
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
          extras={
            <>
              {savedViewsScope === undefined ? null : (
                <SavedViews scope={savedViewsScope} search={search} />
              )}
              {exportColumns === undefined ? null : (
                <RecordExportButton
                  rows={exported}
                  columns={exportColumns}
                  filename={exportName ?? savedViewsScope ?? "export"}
                />
              )}
            </>
          }
          onSearch={(value) => {
            list.set({ q: value === "" ? null : value });
          }}
          onSort={(value) => {
            list.set({ sort: value });
          }}
        />
        {bulkActions === undefined ? null : (
          <RecordBulkBar count={selection.count} onClear={selection.clear}>
            {bulkActions([...selection.selected], selection.clear)}
          </RecordBulkBar>
        )}
        <RecordListGrid
          rows={rows}
          columns={gridColumns}
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
          sorting={sorting}
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
    </RecordSelectionProvider>
  );
}
