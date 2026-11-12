"use client";

import type { RowData } from "@tanstack/react-table";

import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type {
  RecordListFacet,
  RecordListPage,
  RecordListSort,
} from "@/components/record-list/record-list-types";
import type { AdminList } from "@/lib/admin-list";

import { RecordListView } from "@/components/record-list/record-list-view";

import { useAdminListState } from "./use-admin-list-state";

/**
 * An admin overview on the list kit: the URL holds the search, the facets, the
 * sort and the page, and the list route serves every state but the default,
 * which the server renders. Every list sorts by `newest` or `oldest`.
 */
export function AdminRecordList<Row extends RowData & { readonly id: string }>({
  list,
  endpoint,
  initial,
  columns,
  facets,
  searchLabel,
  emptyIcon,
  emptyTitle,
  emptyDescription,
  emptyAction,
}: {
  list: AdminList;
  endpoint: string;
  initial: RecordListPage<Row>;
  columns: RecordListColumns<Row>;
  facets: readonly RecordListFacet[];
  searchLabel: string;
  emptyIcon: React.ReactNode;
  emptyTitle: string;
  emptyDescription: string;
  emptyAction?: React.ReactNode;
}) {
  const t = useExtracted("adminLists");
  const state = useAdminListState(list);

  const sorts: readonly RecordListSort[] = [
    { value: "newest", label: t("Newest first") },
    { value: "oldest", label: t("Oldest first") },
  ];

  return (
    <RecordListView
      list={state}
      endpoint={endpoint}
      initial={initial}
      columns={columns}
      facets={facets}
      sorts={sorts}
      searchLabel={searchLabel}
      emptyIcon={emptyIcon}
      emptyTitle={emptyTitle}
      emptyDescription={emptyDescription}
      emptyAction={emptyAction}
    />
  );
}
