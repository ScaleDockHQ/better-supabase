"use client";

import type { RowData } from "@tanstack/react-table";

import { useExtracted } from "next-intl";
import { useQueryStates } from "nuqs";
import { useTransition } from "react";

import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

import type { RecordListColumns } from "../record-list/record-list-grid";
import type { RecordListSort } from "../record-list/record-list-types";

import { RecordListGrid } from "../record-list/record-list-grid";
import { RecordListToolbar } from "../record-list/record-list-toolbar";
import { opsListParams } from "./ops-list-params";

const ALL = "all";

export interface OpsListFilter {
  readonly label: string;
  readonly options: readonly RecordListSort[];
}

/**
 * The overview of a block list: the kit's toolbar and read-only grid, driven by
 * the URL. The server already filtered, sorted and paged `rows`; a change here
 * writes the URL in a transition, and the grid keeps its frame while the rows
 * stream in.
 */
export function OpsList<Row extends RowData & { readonly id: string }>({
  rows,
  columns,
  nextCursor,
  filter,
  sorts,
  searchLabel,
  emptyIcon,
  emptyTitle,
  emptyDescription,
  emptyAction,
}: {
  rows: readonly Row[];
  columns: RecordListColumns<Row>;
  /** The cursor of the next page; `null` on the last one. */
  nextCursor: string | null;
  filter?: OpsListFilter;
  sorts: readonly RecordListSort[];
  searchLabel: string;
  emptyIcon: React.ReactNode;
  emptyTitle: string;
  emptyDescription: string;
  emptyAction?: React.ReactNode;
}) {
  const t = useExtracted("opsList");
  const [pending, startTransition] = useTransition();

  const [state, setState] = useQueryStates(opsListParams, {
    shallow: false,
    startTransition,
  });

  const filterItems =
    filter === undefined
      ? []
      : [{ value: ALL, label: filter.label }, ...filter.options];

  const filtered = state.q !== "" || state.filter !== null;

  return (
    <div className="flex flex-col gap-4" data-testid="ops-list">
      <RecordListToolbar
        q={state.q}
        searchLabel={searchLabel}
        sort={state.sort ?? sorts[0]?.value ?? ""}
        sorts={sorts}
        filters={
          filter === undefined ? null : (
            <Select
              value={state.filter ?? ALL}
              items={filterItems}
              onValueChange={(value) => {
                void setState({
                  filter: value === null || value === ALL ? null : value,
                  cursor: null,
                });
              }}
            >
              <SelectTrigger
                size="sm"
                className="w-44"
                aria-label={filter.label}
              >
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {filterItems.map((item) => (
                  <SelectItem key={item.value} value={item.value}>
                    {item.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )
        }
        onSearch={(value) => {
          void setState({ q: value, cursor: null });
        }}
        onSort={(value) => {
          void setState({ sort: value, cursor: null });
        }}
      />
      <RecordListGrid
        rows={rows}
        columns={columns}
        failed={false}
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
                  void setState({ q: "", filter: null, cursor: null });
                }}
              >
                {t("Reset filters")}
              </Button>
            ) : null}
            {emptyAction}
          </div>
        }
        onRetry={() => {
          void setState({ cursor: state.cursor });
        }}
      />
      {state.cursor !== null || nextCursor !== null ? (
        <div className="flex items-center justify-end gap-2">
          {state.cursor === null ? null : (
            <Button
              size="sm"
              variant="outline"
              onClick={() => {
                void setState({ cursor: null });
              }}
            >
              {t("First page")}
            </Button>
          )}
          {nextCursor === null ? null : (
            <Button
              size="sm"
              variant="outline"
              disabled={pending}
              onClick={() => {
                void setState({ cursor: nextCursor });
              }}
            >
              {t("Next page")}
            </Button>
          )}
        </div>
      ) : null}
    </div>
  );
}
