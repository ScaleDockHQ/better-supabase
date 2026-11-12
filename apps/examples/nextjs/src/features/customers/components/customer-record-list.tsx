"use client";

import type { CellContext } from "@tanstack/react-table";

import { UsersIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import Image from "next/image";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { Badge } from "@/components/reui/badge";
import { Link } from "@/i18n/navigation";
import { initials } from "@/lib/initials";

import type { CustomerRow } from "../customer-row";

import { useCustomerListState } from "../use-customer-list-state";
import { useStatusLabel } from "../use-status-label";

type CustomerCell = CellContext<ReadOnlyGridFeatures, CustomerRow>;

function NameCell({ row }: CustomerCell) {
  const { id, logoUrl, name } = row.original;

  return (
    // The detail reads `params`, which the shared App Shell can't carry; a
    // per-link prefetch resolves its cached reads.
    <Link
      href={`/customers/${id}`}
      prefetch
      className="flex items-center gap-3 font-medium hover:underline"
    >
      {logoUrl ? (
        <Image
          src={logoUrl}
          width={28}
          height={28}
          alt=""
          className="rounded-md"
        />
      ) : (
        <span className="flex size-7 items-center justify-center rounded-md bg-muted text-xs font-semibold text-muted-foreground">
          {initials(name, null)}
        </span>
      )}
      {name}
    </Link>
  );
}

function StatusCell({ row }: CustomerCell) {
  const statusLabel = useStatusLabel();
  const { status } = row.original;

  return (
    <Badge variant={status === "active" ? "success-light" : "secondary"}>
      {statusLabel(status)}
    </Badge>
  );
}

function NotesCell({ row }: CustomerCell) {
  return <span className="tabular-nums">{row.original.notes}</span>;
}

function LastNoteCell({ row }: CustomerCell) {
  const format = useFormatter();
  const { lastNoteAt } = row.original;

  return (
    <span className="text-muted-foreground">
      {lastNoteAt
        ? format.dateTime(new Date(lastNoteAt), { dateStyle: "medium" })
        : "–"}
    </span>
  );
}

/**
 * The customers overview on the list kit: the URL holds the search, the status
 * filter, the sort and the page, and the list route serves every state but the
 * default, which the server renders.
 */
export function CustomerRecordList({
  initial,
  canWrite,
}: {
  initial: RecordListPage<CustomerRow>;
  canWrite: boolean;
}) {
  const t = useExtracted("customers");
  const statusLabel = useStatusLabel();
  const list = useCustomerListState();

  const columns: RecordListColumns<CustomerRow> = [
    { accessorKey: "name", header: t("Name"), size: 320, cell: NameCell },
    { accessorKey: "status", header: t("Status"), size: 140, cell: StatusCell },
    { accessorKey: "notes", header: t("Notes"), size: 100, cell: NotesCell },
    {
      accessorKey: "lastNoteAt",
      header: t("Last note"),
      size: 160,
      cell: LastNoteCell,
    },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/customers/list"
      initial={initial}
      columns={columns}
      facets={[{ key: "status", label: t("Status"), valueLabel: statusLabel }]}
      sorts={[
        { value: "name", label: t("Name") },
        { value: "newest", label: t("Newest first") },
      ]}
      searchLabel={t("Search customers")}
      emptyIcon={<UsersIcon />}
      emptyTitle={t("No customers found")}
      emptyDescription={
        canWrite
          ? t("Add a customer, or change the filters.")
          : t("Change the filters to see more.")
      }
    />
  );
}
