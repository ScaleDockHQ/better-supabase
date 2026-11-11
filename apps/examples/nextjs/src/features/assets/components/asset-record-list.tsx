"use client";

import type { CellContext } from "@tanstack/react-table";

import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { BoxesIcon } from "lucide-react";
import { useExtracted, useFormatter, useLocale } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { Link } from "@/i18n/navigation";

import type { AssetRow } from "../asset-row";

import { ASSET_STATUSES } from "../assets-list";
import { useAssetListState } from "../use-asset-list-state";
import { AssetStatusBadge, useAssetStatusLabel } from "./asset-status";
import { CreateAssetDialog } from "./create-asset-dialog";

type AssetCell = CellContext<ReadOnlyGridFeatures, AssetRow>;

function NameCell({ row }: AssetCell) {
  const { id, name, tag } = row.original;

  return (
    <Link
      href={`/assets/${id}`}
      className="flex flex-col font-medium hover:underline"
    >
      {name}
      {tag ? (
        <span className="text-xs font-normal text-muted-foreground">{tag}</span>
      ) : null}
    </Link>
  );
}

function StatusCell({ row }: AssetCell) {
  return <AssetStatusBadge status={row.original.status} />;
}

function CostCell({ row }: AssetCell) {
  const locale = useLocale();
  const { cost } = row.original;

  return (
    <span className="tabular-nums">
      {cost ? formatMoney(moneyFromJson(cost), locale) : "–"}
    </span>
  );
}

function AddedCell({ row }: AssetCell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground">
      {format.dateTime(new Date(row.original.createdAt), {
        dateStyle: "medium",
      })}
    </span>
  );
}

/**
 * The asset register on the list kit. The URL holds the search and the status
 * filter; the assets block filters in the database, and `/api/assets/list`
 * serves every state but the default page.
 */
export function AssetRecordList({
  initial,
  canManage,
}: {
  initial: RecordListPage<AssetRow>;
  canManage: boolean;
}) {
  const t = useExtracted("assets");
  const statusLabel = useAssetStatusLabel();
  const list = useAssetListState();

  const columns: RecordListColumns<AssetRow> = [
    { accessorKey: "name", header: t("Asset"), size: 280, cell: NameCell },
    { accessorKey: "kind", header: t("Kind"), size: 140 },
    { accessorKey: "status", header: t("Status"), size: 150, cell: StatusCell },
    { accessorKey: "cost", header: t("Cost"), size: 130, cell: CostCell },
    {
      accessorKey: "createdAt",
      header: t("Added"),
      size: 130,
      cell: AddedCell,
    },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/assets/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "status",
          label: t("Status"),
          valueLabel: statusLabel,
          values: ASSET_STATUSES,
        },
      ]}
      sorts={[{ value: "newest", label: t("Newest first") }]}
      searchLabel={t("Search by name, tag or serial number")}
      emptyIcon={<BoxesIcon />}
      emptyTitle={t("No assets found")}
      emptyDescription={
        canManage
          ? t("Add an asset, or change the filters.")
          : t("Change the filters to see more.")
      }
      emptyAction={canManage ? <CreateAssetDialog /> : null}
    />
  );
}
