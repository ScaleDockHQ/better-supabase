"use client";

import type { CellContext } from "@tanstack/react-table";

import { ArrowLeftRightIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { useBlockListState } from "@/components/record-list/use-block-list-state";
import { Badge } from "@/components/reui/badge";
import { Link } from "@/i18n/navigation";

import type { MovementRow } from "../inventory-list";

import { MOVEMENT_KIND_VALUES, movementList } from "../inventory-list";
import { useMovementKindLabel } from "./inventory-status";

type MovementCell = CellContext<ReadOnlyGridFeatures, MovementRow>;

function WhenCell({ row }: MovementCell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground">
      {format.dateTime(new Date(row.original.effectiveAt), {
        dateStyle: "medium",
        timeStyle: "short",
      })}
    </span>
  );
}

function ProductCell({ row }: MovementCell) {
  const { variantId, productTitle, sku } = row.original;

  return (
    <div className="flex flex-col">
      {variantId === null ? (
        <span className="font-medium">{productTitle}</span>
      ) : (
        <Link
          href={`/shop/inventory/${variantId}`}
          className="font-medium hover:underline"
        >
          {productTitle}
        </Link>
      )}
      <span className="font-mono text-xs text-muted-foreground">{sku}</span>
    </div>
  );
}

function KindCell({ row }: MovementCell) {
  const label = useMovementKindLabel();

  return <Badge variant="outline">{label(row.original.kind)}</Badge>;
}

function QuantityCell({ row }: MovementCell) {
  const { quantity } = row.original;

  return (
    <span
      className={
        quantity < 0
          ? "text-destructive tabular-nums"
          : "text-success tabular-nums"
      }
    >
      {quantity > 0 ? `+${quantity}` : quantity}
    </span>
  );
}

/** The ledger movements on the list kit, newest first. */
export function MovementRecordList({
  initial,
  locations,
}: {
  initial: RecordListPage<MovementRow>;
  locations: readonly { readonly id: string; readonly name: string }[];
}) {
  const t = useExtracted("inventory");
  const kindLabel = useMovementKindLabel();
  const list = useBlockListState(movementList);
  const locationName = new Map(locations.map((row) => [row.id, row.name]));

  const columns: RecordListColumns<MovementRow> = [
    { id: "when", header: t("When"), size: 190, cell: WhenCell },
    { id: "product", header: t("Product"), size: 240, cell: ProductCell },
    { accessorKey: "locationName", header: t("Location"), size: 170 },
    { id: "kind", header: t("Kind"), size: 140, cell: KindCell },
    { id: "quantity", header: t("Quantity"), size: 100, cell: QuantityCell },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/inventory/movements/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "kind",
          label: t("Kind"),
          valueLabel: kindLabel,
          values: MOVEMENT_KIND_VALUES,
        },
        {
          key: "location",
          label: t("Location"),
          valueLabel: (value) => locationName.get(value) ?? value,
          values: locations.map((row) => row.id),
        },
      ]}
      sorts={[
        { value: "newest", label: t("Newest first") },
        { value: "oldest", label: t("Oldest first") },
        { value: "quantity", label: t("Largest change first") },
      ]}
      searchLabel={t("Search movements")}
      emptyIcon={<ArrowLeftRightIcon />}
      emptyTitle={t("No movements found")}
      emptyDescription={t("Change the search or the filters.")}
    />
  );
}
