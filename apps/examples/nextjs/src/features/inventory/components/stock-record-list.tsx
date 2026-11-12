"use client";

import type { CellContext } from "@tanstack/react-table";

import { BoxesIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { useBlockListState } from "@/components/record-list/use-block-list-state";
import { Link } from "@/i18n/navigation";

import type { StockRow } from "../inventory-list";

import { STOCK_STATUS_VALUES, stockList } from "../inventory-list";
import { StockStatusBadge, useStockStatusLabel } from "./inventory-status";

type StockCell = CellContext<ReadOnlyGridFeatures, StockRow>;

function ProductCell({ row }: StockCell) {
  const { variantId, productTitle, sku } = row.original;

  return (
    <div className="flex flex-col">
      <Link
        href={`/shop/inventory/${variantId}`}
        className="font-medium hover:underline"
      >
        {productTitle}
      </Link>
      <span className="font-mono text-xs text-muted-foreground">{sku}</span>
    </div>
  );
}

const number = (key: "onHand" | "reserved" | "available" | "incoming") =>
  function NumberCell({ row }: StockCell) {
    return <span className="tabular-nums">{row.original[key]}</span>;
  };

function StatusCell({ row }: StockCell) {
  return <StockStatusBadge status={row.original.status} />;
}

/**
 * The stock levels on the list kit: the URL holds the search, the status and
 * location filters and the sort; the list route serves every state but the
 * default, which the server renders.
 */
export function StockRecordList({
  initial,
  locations,
}: {
  initial: RecordListPage<StockRow>;
  locations: readonly { readonly id: string; readonly name: string }[];
}) {
  const t = useExtracted("inventory");
  const statusLabel = useStockStatusLabel();
  const list = useBlockListState(stockList);
  const locationName = new Map(locations.map((row) => [row.id, row.name]));

  const columns: RecordListColumns<StockRow> = [
    { id: "product", header: t("Product"), size: 260, cell: ProductCell },
    { accessorKey: "locationName", header: t("Location"), size: 180 },
    { id: "onHand", header: t("On hand"), size: 100, cell: number("onHand") },
    {
      id: "reserved",
      header: t("Reserved"),
      size: 100,
      cell: number("reserved"),
    },
    {
      id: "available",
      header: t("Available"),
      size: 110,
      cell: number("available"),
    },
    {
      id: "incoming",
      header: t("Incoming"),
      size: 100,
      cell: number("incoming"),
    },
    { id: "status", header: t("Status"), size: 130, cell: StatusCell },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/inventory/levels/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "status",
          label: t("Status"),
          valueLabel: statusLabel,
          values: STOCK_STATUS_VALUES,
        },
        {
          key: "location",
          label: t("Location"),
          valueLabel: (value) => locationName.get(value) ?? value,
          values: locations.map((row) => row.id),
        },
      ]}
      sorts={[
        { value: "product", label: t("Product") },
        { value: "available", label: t("Lowest available first") },
        { value: "on_hand", label: t("Most on hand first") },
      ]}
      searchLabel={t("Search by product, SKU or location")}
      emptyIcon={<BoxesIcon />}
      emptyTitle={t("No stock levels found")}
      emptyDescription={t("Change the search or the filters.")}
    />
  );
}
