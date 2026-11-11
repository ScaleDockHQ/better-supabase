"use client";

import type { CellContext } from "@tanstack/react-table";

import { PalmtreeIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { useBlockListState } from "@/components/record-list/use-block-list-state";
import { Link } from "@/i18n/navigation";

import type { LeaveRow } from "../leave-list";

import { leaveList } from "../leave-list";
import { LeaveStatusBadge, useLeaveStatusLabel } from "./leave-status";

type LeaveCell = CellContext<ReadOnlyGridFeatures, LeaveRow>;

function WhoCell({ row }: LeaveCell) {
  return (
    <Link
      href={`/people/leave/${row.original.id}`}
      className="font-medium hover:underline"
    >
      {row.original.who}
    </Link>
  );
}

function DatesCell({ row }: LeaveCell) {
  const format = useFormatter();
  const { startsOn, endsOn } = row.original;

  const show = (value: string) =>
    format.dateTime(new Date(`${value}T00:00:00`), { dateStyle: "medium" });

  return (
    <span className="text-muted-foreground">
      {startsOn === endsOn
        ? show(startsOn)
        : `${show(startsOn)} – ${show(endsOn)}`}
    </span>
  );
}

function AmountCell({ row }: LeaveCell) {
  const t = useExtracted("people");
  const { amount, unit } = row.original;

  return (
    <span className="tabular-nums">
      {unit === "hours"
        ? t("{amount} h", { amount: String(amount) })
        : t("{amount} d", { amount: String(amount) })}
    </span>
  );
}

function StatusCell({ row }: LeaveCell) {
  return <LeaveStatusBadge status={row.original.status} />;
}

/**
 * The leave overview on the list kit: the URL holds the search, the status and
 * type filters, the sort and the page; the list route serves every state but
 * the default, which the server renders.
 */
export function LeaveRecordList({
  initial,
  types,
}: {
  initial: RecordListPage<LeaveRow>;
  types: readonly { readonly id: string; readonly name: string }[];
}) {
  const t = useExtracted("people");
  const statusLabel = useLeaveStatusLabel();
  const list = useBlockListState(leaveList);
  const typeName = new Map(types.map((type) => [type.id, type.name]));

  const columns: RecordListColumns<LeaveRow> = [
    { accessorKey: "who", header: t("Who"), size: 220, cell: WhoCell },
    { accessorKey: "typeName", header: t("Type"), size: 160 },
    { id: "dates", header: t("Dates"), size: 260, cell: DatesCell },
    { id: "amount", header: t("Amount"), size: 100, cell: AmountCell },
    { accessorKey: "status", header: t("Status"), size: 140, cell: StatusCell },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/leave/list"
      initial={initial}
      columns={columns}
      facets={[
        { key: "status", label: t("Status"), valueLabel: statusLabel },
        {
          key: "type",
          label: t("Type"),
          valueLabel: (value) => typeName.get(value) ?? value,
        },
      ]}
      sorts={[
        { value: "start", label: t("Latest start") },
        { value: "newest", label: t("Latest end") },
        { value: "name", label: t("Name") },
      ]}
      searchLabel={t("Search leave")}
      emptyIcon={<PalmtreeIcon />}
      emptyTitle={t("No leave found")}
      emptyDescription={t("Request leave, or change the filters.")}
    />
  );
}
