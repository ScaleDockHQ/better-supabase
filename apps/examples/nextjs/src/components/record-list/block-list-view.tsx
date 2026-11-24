"use client";

import type { CellContext } from "@tanstack/react-table";

import { useExtracted } from "next-intl";
import { useQueryStates } from "nuqs";
import { useMemo, useTransition } from "react";

import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Link, toAppHref } from "@/i18n/navigation";
import { blockOverviewParsers } from "@/lib/block-overview-params";

import type { RecordListColumns } from "./record-list-grid";
import type { RecordListSort } from "./record-list-types";

import { RecordListGrid } from "./record-list-grid";
import { RecordListToolbar } from "./record-list-toolbar";

type BadgeTone =
  | "secondary"
  | "success-light"
  | "warning-light"
  | "destructive-light"
  | "info-light"
  | "primary-light";

/**
 * One column, as data, so a server component can describe a grid without
 * passing functions across the client boundary.
 */
export interface BlockColumn {
  readonly key: string;
  readonly header: string;
  readonly kind: "text" | "link" | "number" | "badge" | "muted" | "money";
  /** The width in pixels. */
  readonly size?: number;
  /**
   * For `money`: the row's cell is the amount already formatted for the page's
   * locale (`withMoneyCells`), so this client file never loads the money code.
   */
  /** For `link`: the path with `{id}` for the row's id. */
  readonly href?: string;
  /** For `badge`: the label of each value; a value without one shows as is. */
  readonly labels?: Readonly<Record<string, string>>;
  /** For `badge`: the tone of each value; others are `secondary`. */
  readonly tones?: Readonly<Record<string, BadgeTone>>;
}

export type BlockRow = { readonly id: string } & Readonly<
  Record<string, string | number | boolean | null>
>;

export interface BlockFacetOption {
  readonly value: string;
  readonly label: string;
  readonly count: number;
}

type RowCell = CellContext<ReadOnlyGridFeatures, BlockRow>;

function textOf(value: BlockRow[string]): string {
  return value === null ? "" : String(value);
}

function cellOf(column: BlockColumn): (context: RowCell) => React.ReactNode {
  return function Cell({ row }) {
    const raw = row.original[column.key] ?? null;
    const text = textOf(raw);

    switch (column.kind) {
      case "link": {
        return (
          <Link
            href={toAppHref(
              (column.href ?? "/").replace("{id}", row.original.id),
            )}
            className="font-medium hover:underline"
          >
            {text === "" ? "–" : text}
          </Link>
        );
      }

      case "badge": {
        return text === "" ? (
          "–"
        ) : (
          <Badge variant={column.tones?.[text] ?? "secondary"}>
            {column.labels?.[text] ?? text}
          </Badge>
        );
      }

      case "money":
      case "number": {
        return <span className="tabular-nums">{text === "" ? "–" : text}</span>;
      }

      case "muted": {
        return (
          <span className="text-muted-foreground">
            {text === "" ? "–" : text}
          </span>
        );
      }

      case "text": {
        return text === "" ? "–" : text;
      }

      default: {
        const never: never = column.kind;

        return never;
      }
    }
  };
}

const ALL = "__all__";

/**
 * An overview over a block's `page` method: the search, one facet filter, the
 * sort and the keyset cursor (`after`) live in the URL, the database filters,
 * sorts and pages the rows (`pageEntityRows`), and a change runs in a
 * transition that keeps the grid and dims it while the next page renders. Each
 * next page is a history entry, so the browser's back button returns to the
 * page before.
 */
export function BlockListView({
  rows,
  columns,
  facetKey,
  facetLabel,
  facetOptions,
  sorts,
  searchLabel,
  nextCursor,
  emptyIcon,
  emptyTitle,
  emptyDescription,
  emptyAction,
}: {
  rows: readonly BlockRow[];
  columns: readonly BlockColumn[];
  /** The facet's label, with `facetOptions`; omit both for no filter. */
  facetKey?: string;
  facetLabel?: string;
  facetOptions?: readonly BlockFacetOption[];
  sorts: readonly RecordListSort[];
  /** Omit it for a list the block cannot search. */
  searchLabel?: string | undefined;
  /** The cursor of the next page, `null` on the last one. */
  nextCursor: string | null;
  emptyIcon: React.ReactNode;
  emptyTitle: string;
  emptyDescription: string;
  emptyAction?: React.ReactNode;
}) {
  const t = useExtracted("recordList");
  const [pending, startTransition] = useTransition();

  const [state, setState] = useQueryStates(blockOverviewParsers, {
    shallow: false,
    startTransition,
    clearOnDefault: true,
  });

  const gridColumns = useMemo<RecordListColumns<BlockRow>>(
    () =>
      columns.map((column) => ({
        id: column.key,
        accessorKey: column.key,
        header: column.header,
        size: column.size ?? 160,
        cell: cellOf(column),
      })),
    [columns],
  );

  const filtered = state.q !== "" || state.f !== "";
  const options = facetOptions ?? [];

  const items = [
    { value: ALL, label: facetLabel ?? "" },
    ...options.map((option) => ({
      value: option.value,
      label: `${option.label} (${option.count})`,
    })),
  ];

  return (
    <div className="flex flex-col gap-4" data-testid="record-list">
      <RecordListToolbar
        q={state.q}
        searchLabel={searchLabel}
        sort={state.sort === "" ? (sorts[0]?.value ?? "") : state.sort}
        sorts={sorts}
        filters={
          facetKey && options.length > 0 ? (
            <Select
              value={state.f === "" ? ALL : state.f}
              items={items}
              onValueChange={(value) => {
                if (value !== null) {
                  void setState({
                    f: value === ALL ? null : value,
                    after: null,
                  });
                }
              }}
            >
              <SelectTrigger className="w-48" aria-label={facetLabel}>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {items.map((item) => (
                  <SelectItem key={item.value} value={item.value}>
                    {item.value === ALL ? t("All") : item.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          ) : null
        }
        onSearch={(value) => {
          void setState({ q: value === "" ? null : value, after: null });
        }}
        onSort={(value) => {
          void setState({ sort: value, after: null });
        }}
      />
      <RecordListGrid
        rows={rows}
        columns={gridColumns}
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
                  void setState({ q: null, f: null, after: null });
                }}
              >
                {t("Reset filters")}
              </Button>
            ) : null}
            {emptyAction}
          </div>
        }
        onRetry={() => {
          void setState({ after: null });
        }}
      />
      {state.after !== "" || nextCursor !== null ? (
        <div className="flex items-center justify-end gap-2">
          <Button
            size="sm"
            variant="outline"
            disabled={pending || state.after === ""}
            onClick={() => {
              void setState({ after: null });
            }}
          >
            {t("First page")}
          </Button>
          <Button
            size="sm"
            variant="outline"
            disabled={pending || nextCursor === null}
            onClick={() => {
              void setState({ after: nextCursor }, { history: "push" });
            }}
          >
            {t("Next page")}
          </Button>
        </div>
      ) : null}
    </div>
  );
}
