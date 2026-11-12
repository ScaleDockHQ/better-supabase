"use client";

import type { CellContext } from "@tanstack/react-table";
import type { MoneyJson } from "better-supabase/commerce";

import { useExtracted, useLocale } from "next-intl";
import { parseAsInteger, parseAsString, useQueryStates } from "nuqs";
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

import type { RecordListColumns } from "./record-list-grid";
import type { RecordListSort } from "./record-list-types";

import { moneyText } from "./money-text";
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
   * For `money`: the cell holds `{ amount, currency }` with the amount in minor
   * units as text (`MoneyJson`), shown in the page's locale.
   */
  /** For `link`: the path with `{id}` for the row's id. */
  readonly href?: string;
  /** For `badge`: the label of each value; a value without one shows as is. */
  readonly labels?: Readonly<Record<string, string>>;
  /** For `badge`: the tone of each value; others are `secondary`. */
  readonly tones?: Readonly<Record<string, BadgeTone>>;
}

export type BlockRow = { readonly id: string } & Readonly<
  Record<string, string | number | boolean | MoneyJson | null>
>;

export interface BlockFacetOption {
  readonly value: string;
  readonly label: string;
  readonly count: number;
}

type RowCell = CellContext<ReadOnlyGridFeatures, BlockRow>;

function textOf(column: BlockColumn, value: BlockRow[string]): string {
  if (value === null || column.kind === "money") {
    return "";
  }

  return String(value);
}

function cellOf(
  column: BlockColumn,
  locale: string,
): (context: RowCell) => React.ReactNode {
  return function Cell({ row }) {
    const raw = row.original[column.key] ?? null;
    const text = textOf(column, raw);

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

      case "number": {
        return <span className="tabular-nums">{text === "" ? "–" : text}</span>;
      }

      case "money": {
        const formatted = moneyText(raw, locale);

        return (
          <span className="tabular-nums">
            {formatted === "" ? "–" : formatted}
          </span>
        );
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
 * An overview over a list a block returns whole: the search, one facet filter,
 * the sort and the page live in the URL, the server filters and pages the rows
 * (`applyBlockList`), and a change runs in a transition that keeps the grid and
 * dims it while the next page renders.
 */
export function BlockListView({
  rows,
  columns,
  facetKey,
  facetLabel,
  facetOptions,
  sorts,
  searchLabel,
  total,
  page,
  pages,
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
  searchLabel: string;
  total: number;
  page: number;
  pages: number;
  emptyIcon: React.ReactNode;
  emptyTitle: string;
  emptyDescription: string;
  emptyAction?: React.ReactNode;
}) {
  const t = useExtracted("recordList");
  const locale = useLocale();
  const [pending, startTransition] = useTransition();

  const [state, setState] = useQueryStates(
    {
      q: parseAsString.withDefault(""),
      f: parseAsString.withDefault(""),
      sort: parseAsString.withDefault(""),
      page: parseAsInteger.withDefault(1),
    },
    { shallow: false, startTransition, clearOnDefault: true },
  );

  const gridColumns = useMemo<RecordListColumns<BlockRow>>(
    () =>
      columns.map((column) => ({
        id: column.key,
        accessorKey: column.key,
        header: column.header,
        size: column.size ?? 160,
        cell: cellOf(column, locale),
      })),
    [columns, locale],
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
                    page: null,
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
          void setState({ q: value === "" ? null : value, page: null });
        }}
        onSort={(value) => {
          void setState({ sort: value, page: null });
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
                  void setState({ q: null, f: null, page: null });
                }}
              >
                {t("Reset filters")}
              </Button>
            ) : null}
            {emptyAction}
          </div>
        }
        onRetry={() => {
          void setState({ page: null });
        }}
      />
      {pages > 1 ? (
        <div className="flex items-center justify-between gap-2 text-sm text-muted-foreground">
          <span>
            {t("Page {page} of {pages}, {total} rows", {
              page: String(page),
              pages: String(pages),
              total: String(total),
            })}
          </span>
          <div className="flex items-center gap-2">
            <Button
              size="sm"
              variant="outline"
              disabled={pending || page <= 1}
              onClick={() => {
                void setState({ page: page - 1 });
              }}
            >
              {t("Previous page")}
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={pending || page >= pages}
              onClick={() => {
                void setState({ page: page + 1 });
              }}
            >
              {t("Next page")}
            </Button>
          </div>
        </div>
      ) : null}
    </div>
  );
}
