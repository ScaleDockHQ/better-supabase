"use client";

import type { CellContext } from "@tanstack/react-table";

import { PackageSearchIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { useBlockListState } from "@/components/record-list/use-block-list-state";
import { Link } from "@/i18n/navigation";

import type { LotRow } from "../inventory-list";

import { LOT_EXPIRY_VALUES, lotList } from "../inventory-list";
import { ExpiryBadge, useExpiryLabel } from "./inventory-status";

type LotCell = CellContext<ReadOnlyGridFeatures, LotRow>;

function CodeCell({ row }: LotCell) {
  return <span className="font-mono">{row.original.code}</span>;
}

function ProductCell({ row }: LotCell) {
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

function ExpiresCell({ row }: LotCell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground">
      {format.dateTime(new Date(`${row.original.expiresOn}T00:00:00`), {
        dateStyle: "medium",
      })}
    </span>
  );
}

function OnHandCell({ row }: LotCell) {
  return <span className="tabular-nums">{row.original.onHand}</span>;
}

function ExpiryCell({ row }: LotCell) {
  return <ExpiryBadge expiry={row.original.expiry} />;
}

/** The lots with stock and an expiry date on the list kit. */
export function LotRecordList({
  initial,
  locations,
}: {
  initial: RecordListPage<LotRow>;
  locations: readonly { readonly id: string; readonly name: string }[];
}) {
  const t = useExtracted("inventory");
  const expiryLabel = useExpiryLabel();
  const list = useBlockListState(lotList);
  const locationName = new Map(locations.map((row) => [row.id, row.name]));

  const columns: RecordListColumns<LotRow> = [
    { id: "code", header: t("Lot"), size: 150, cell: CodeCell },
    { id: "product", header: t("Product"), size: 240, cell: ProductCell },
    { accessorKey: "locationName", header: t("Location"), size: 170 },
    { id: "expiresOn", header: t("Expires"), size: 140, cell: ExpiresCell },
    { id: "onHand", header: t("On hand"), size: 100, cell: OnHandCell },
    { id: "expiry", header: t("Status"), size: 190, cell: ExpiryCell },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/inventory/lots/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "expiry",
          label: t("Status"),
          valueLabel: expiryLabel,
          values: LOT_EXPIRY_VALUES,
        },
        {
          key: "location",
          label: t("Location"),
          valueLabel: (value) => locationName.get(value) ?? value,
          values: locations.map((row) => row.id),
        },
      ]}
      sorts={[
        { value: "expires", label: t("Expires soonest") },
        { value: "on_hand", label: t("Most on hand first") },
        { value: "code", label: t("Lot code") },
      ]}
      searchLabel={t("Search lots")}
      emptyIcon={<PackageSearchIcon />}
      emptyTitle={t("No lots found")}
      emptyDescription={t("Lots with an expiry date and stock show up here.")}
    />
  );
}
