"use client";

import type { CellContext } from "@tanstack/react-table";

import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { HeartHandshakeIcon } from "lucide-react";
import { useExtracted, useFormatter, useLocale } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { Link } from "@/i18n/navigation";

import type { GiftFormOptions } from "../donations-queries";
import type { GiftRow } from "../gift-row";

import { GIFT_STATUSES } from "../donations-list";
import { useGiftListState } from "../use-gift-list-state";
import { GiftStatusBadge, useGiftStatusLabel } from "./gift-status";
import { RecordGiftDialog } from "./record-gift-dialog";

type GiftCell = CellContext<ReadOnlyGridFeatures, GiftRow>;

function DonorCell({ row }: GiftCell) {
  const { id, donor } = row.original;

  return (
    <Link
      href={`/shop/donations/${id}`}
      className="font-medium hover:underline"
    >
      {donor}
    </Link>
  );
}

function StatusCell({ row }: GiftCell) {
  return <GiftStatusBadge status={row.original.status} />;
}

function AmountCell({ row }: GiftCell) {
  const locale = useLocale();

  return (
    <span className="tabular-nums">
      {formatMoney(moneyFromJson(row.original.amount), locale)}
    </span>
  );
}

function ReceivedCell({ row }: GiftCell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground">
      {format.dateTime(new Date(row.original.receivedOn), {
        dateStyle: "medium",
      })}
    </span>
  );
}

/** The gifts overview on the list kit; the URL holds the status filter. */
export function GiftRecordList({
  initial,
  canManage,
  options,
}: {
  initial: RecordListPage<GiftRow>;
  canManage: boolean;
  options: GiftFormOptions | null;
}) {
  const t = useExtracted("donations");
  const statusLabel = useGiftStatusLabel();
  const list = useGiftListState();

  const columns: RecordListColumns<GiftRow> = [
    { accessorKey: "donor", header: t("Donor"), size: 260, cell: DonorCell },
    { accessorKey: "status", header: t("Status"), size: 130, cell: StatusCell },
    { accessorKey: "amount", header: t("Amount"), size: 140, cell: AmountCell },
    {
      accessorKey: "receivedOn",
      header: t("Received"),
      size: 150,
      cell: ReceivedCell,
    },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/donations/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "status",
          label: t("Status"),
          valueLabel: statusLabel,
          values: GIFT_STATUSES,
        },
      ]}
      sorts={[{ value: "newest", label: t("Newest first") }]}
      emptyIcon={<HeartHandshakeIcon />}
      emptyTitle={t("No gifts found")}
      emptyDescription={
        canManage
          ? t("Record a gift, or change the filters.")
          : t("Change the filters to see more.")
      }
      emptyAction={
        canManage && options ? <RecordGiftDialog options={options} /> : null
      }
    />
  );
}
