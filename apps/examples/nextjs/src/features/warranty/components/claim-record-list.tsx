"use client";

import type { CellContext } from "@tanstack/react-table";

import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { ShieldCheckIcon } from "lucide-react";
import { useExtracted, useLocale } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { Link } from "@/i18n/navigation";

import type { ClaimRow } from "../claim-row";
import type { ClaimFormOptions } from "../warranty-queries";

import { useClaimListState } from "../use-claim-list-state";
import { CLAIM_STATUSES } from "../warranty-list";
import { ClaimStatusBadge, useClaimStatusLabel } from "./claim-status";
import { CreateClaimDialog } from "./create-claim-dialog";

type ClaimCell = CellContext<ReadOnlyGridFeatures, ClaimRow>;

function TitleCell({ row }: ClaimCell) {
  const { id, title } = row.original;

  return (
    <Link href={`/shop/warranty/${id}`} className="font-medium hover:underline">
      {title}
    </Link>
  );
}

function StatusCell({ row }: ClaimCell) {
  return <ClaimStatusBadge status={row.original.status} />;
}

function AmountCell({ row }: ClaimCell) {
  const locale = useLocale();

  return (
    <span className="tabular-nums">
      {formatMoney(moneyFromJson(row.original.amount), locale)}
    </span>
  );
}

/** The warranty claims overview on the list kit; the URL holds the status. */
export function ClaimRecordList({
  initial,
  canWrite,
  options,
}: {
  initial: RecordListPage<ClaimRow>;
  canWrite: boolean;
  options: ClaimFormOptions | null;
}) {
  const t = useExtracted("warranty");
  const statusLabel = useClaimStatusLabel();
  const list = useClaimListState();

  const columns: RecordListColumns<ClaimRow> = [
    { accessorKey: "title", header: t("Claim"), size: 260, cell: TitleCell },
    { accessorKey: "asset", header: t("Asset"), size: 200 },
    { accessorKey: "status", header: t("Status"), size: 130, cell: StatusCell },
    { accessorKey: "amount", header: t("Amount"), size: 140, cell: AmountCell },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/warranty/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "status",
          label: t("Status"),
          valueLabel: statusLabel,
          values: CLAIM_STATUSES,
        },
      ]}
      sorts={[{ value: "newest", label: t("Newest first") }]}
      emptyIcon={<ShieldCheckIcon />}
      emptyTitle={t("No claims found")}
      emptyDescription={
        canWrite
          ? t("File a claim, or change the filters.")
          : t("Change the filters to see more.")
      }
      emptyAction={
        canWrite && options ? <CreateClaimDialog options={options} /> : null
      }
    />
  );
}
