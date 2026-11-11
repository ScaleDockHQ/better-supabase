"use client";

import type { CellContext } from "@tanstack/react-table";

import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { KeyRoundIcon } from "lucide-react";
import { useExtracted, useFormatter, useLocale } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { Link } from "@/i18n/navigation";

import type { LeaseRow } from "../lease-row";
import type { LeaseFormOptions } from "../leases-queries";

import { LEASE_STATUSES } from "../leases-list";
import { useLeaseListState } from "../use-lease-list-state";
import { CreateLeaseDialog } from "./create-lease-dialog";
import { LeaseStatusBadge, useLeaseStatusLabel } from "./lease-status";

type LeaseCell = CellContext<ReadOnlyGridFeatures, LeaseRow>;

function TitleCell({ row }: LeaseCell) {
  const { id, title } = row.original;

  return (
    <Link
      href={`/property/leases/${id}`}
      className="font-medium hover:underline"
    >
      {title}
    </Link>
  );
}

function StatusCell({ row }: LeaseCell) {
  return <LeaseStatusBadge status={row.original.status} />;
}

function RentCell({ row }: LeaseCell) {
  const locale = useLocale();
  const t = useExtracted("leases");
  const { rent, frequency } = row.original;

  const every = {
    weekly: t("a week"),
    monthly: t("a month"),
    quarterly: t("a quarter"),
    yearly: t("a year"),
  }[frequency];

  return (
    <span className="tabular-nums">
      {formatMoney(moneyFromJson(rent), locale)}{" "}
      <span className="text-muted-foreground">{every}</span>
    </span>
  );
}

function BalanceCell({ row }: LeaseCell) {
  const locale = useLocale();

  return (
    <span className="tabular-nums">
      {formatMoney(moneyFromJson(row.original.balanceDue), locale)}
    </span>
  );
}

function PeriodCell({ row }: LeaseCell) {
  const format = useFormatter();
  const { startsOn, endsOn } = row.original;

  const date = (value: string) =>
    format.dateTime(new Date(value), { dateStyle: "medium" });

  return (
    <span className="text-muted-foreground">
      {date(startsOn)}
      {endsOn === null ? "" : ` – ${date(endsOn)}`}
    </span>
  );
}

/**
 * The leases overview on the list kit. The URL holds the status filter; the
 * leases block has no text search, so the toolbar shows none.
 */
export function LeaseRecordList({
  initial,
  canManage,
  options,
}: {
  initial: RecordListPage<LeaseRow>;
  canManage: boolean;
  options: LeaseFormOptions | null;
}) {
  const t = useExtracted("leases");
  const statusLabel = useLeaseStatusLabel();
  const list = useLeaseListState();

  const columns: RecordListColumns<LeaseRow> = [
    { accessorKey: "title", header: t("Lease"), size: 260, cell: TitleCell },
    { accessorKey: "status", header: t("Status"), size: 130, cell: StatusCell },
    { accessorKey: "rent", header: t("Rent"), size: 170, cell: RentCell },
    {
      accessorKey: "balanceDue",
      header: t("Balance due"),
      size: 140,
      cell: BalanceCell,
    },
    { accessorKey: "startsOn", header: t("Term"), size: 220, cell: PeriodCell },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/leases/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "status",
          label: t("Status"),
          valueLabel: statusLabel,
          values: LEASE_STATUSES,
        },
      ]}
      sorts={[{ value: "newest", label: t("Newest first") }]}
      emptyIcon={<KeyRoundIcon />}
      emptyTitle={t("No leases found")}
      emptyDescription={
        canManage
          ? t("Draft a lease, or change the filters.")
          : t("Change the filters to see more.")
      }
      emptyAction={
        canManage && options ? <CreateLeaseDialog options={options} /> : null
      }
    />
  );
}
