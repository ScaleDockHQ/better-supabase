"use client";

import type { CellContext } from "@tanstack/react-table";

import { TicketIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { Link } from "@/i18n/navigation";

import type { PassRow } from "../pass-row";

import { PASS_STATUSES } from "../passes-list";
import { usePassListState } from "../use-pass-list-state";
import { IssuePassDialog } from "./issue-pass-dialog";
import { PassStatusBadge, usePassStatusLabel } from "./pass-status";

type PassCell = CellContext<ReadOnlyGridFeatures, PassRow>;

function HolderCell({ row }: PassCell) {
  const t = useExtracted("passes");
  const { id, holder, kind } = row.original;

  return (
    <Link
      href={`/shop/passes/${id}`}
      className="flex flex-col font-medium hover:underline"
    >
      {holder ?? t("No holder")}
      <span className="text-xs font-normal text-muted-foreground">{kind}</span>
    </Link>
  );
}

function StatusCell({ row }: PassCell) {
  return <PassStatusBadge status={row.original.status} />;
}

function UsesCell({ row }: PassCell) {
  const { uses, usesAllowed } = row.original;

  return (
    <span className="tabular-nums">
      {usesAllowed === null ? uses : `${uses} / ${usesAllowed}`}
    </span>
  );
}

function ValidCell({ row }: PassCell) {
  const format = useFormatter();
  const t = useExtracted("passes");
  const { validUntil } = row.original;

  return (
    <span className="text-muted-foreground">
      {validUntil === null
        ? t("No end")
        : format.dateTime(new Date(validUntil), { dateStyle: "medium" })}
    </span>
  );
}

/** The passes overview on the list kit; the URL holds the status filter. */
export function PassRecordList({
  initial,
  canManage,
}: {
  initial: RecordListPage<PassRow>;
  canManage: boolean;
}) {
  const t = useExtracted("passes");
  const statusLabel = usePassStatusLabel();
  const list = usePassListState();

  const columns: RecordListColumns<PassRow> = [
    { accessorKey: "holder", header: t("Holder"), size: 260, cell: HolderCell },
    { accessorKey: "status", header: t("Status"), size: 130, cell: StatusCell },
    { accessorKey: "uses", header: t("Uses"), size: 110, cell: UsesCell },
    {
      accessorKey: "validUntil",
      header: t("Valid until"),
      size: 150,
      cell: ValidCell,
    },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/passes/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "status",
          label: t("Status"),
          valueLabel: statusLabel,
          values: PASS_STATUSES,
        },
      ]}
      sorts={[{ value: "newest", label: t("Newest first") }]}
      emptyIcon={<TicketIcon />}
      emptyTitle={t("No passes found")}
      emptyDescription={
        canManage
          ? t("Issue a pass, or change the filters.")
          : t("Change the filters to see more.")
      }
      emptyAction={canManage ? <IssuePassDialog /> : null}
    />
  );
}
