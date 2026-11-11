"use client";

import type { CellContext } from "@tanstack/react-table";

import { UsersIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { useBlockListState } from "@/components/record-list/use-block-list-state";
import { Link } from "@/i18n/navigation";

import type { DirectoryEmployee } from "../people-queries";

import { employeeList } from "../employees-list";
import { EmployeeStatusBadge, useEmployeeStatusLabel } from "./employee-status";

type EmployeeCell = CellContext<ReadOnlyGridFeatures, DirectoryEmployee>;

function NameCell({ row }: EmployeeCell) {
  const { id, name, email } = row.original;

  return (
    <div className="flex flex-col">
      <Link href={`/people/${id}`} className="font-medium hover:underline">
        {name}
      </Link>
      {email ? (
        <span className="text-xs text-muted-foreground">{email}</span>
      ) : null}
    </div>
  );
}

function StatusCell({ row }: EmployeeCell) {
  return <EmployeeStatusBadge status={row.original.status} />;
}

/**
 * The employee overview on the list kit: search, status filter, sort and page
 * live in the URL and the list route serves every state but the default.
 */
export function EmployeeRecordList({
  initial,
}: {
  initial: RecordListPage<DirectoryEmployee>;
}) {
  const t = useExtracted("people");
  const statusLabel = useEmployeeStatusLabel();
  const list = useBlockListState(employeeList);

  const columns: RecordListColumns<DirectoryEmployee> = [
    { accessorKey: "name", header: t("Name"), size: 260, cell: NameCell },
    { accessorKey: "jobTitle", header: t("Job title"), size: 200 },
    { accessorKey: "startDate", header: t("Started"), size: 140 },
    { accessorKey: "directReports", header: t("Reports"), size: 100 },
    { accessorKey: "status", header: t("Status"), size: 140, cell: StatusCell },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/employees/list"
      initial={initial}
      columns={columns}
      facets={[{ key: "status", label: t("Status"), valueLabel: statusLabel }]}
      sorts={[
        { value: "name", label: t("Name") },
        { value: "start", label: t("Latest start") },
        { value: "reports", label: t("Most reports") },
      ]}
      searchLabel={t("Search employees")}
      emptyIcon={<UsersIcon />}
      emptyTitle={t("No one matches")}
      emptyDescription={t("Try another name, title or email.")}
    />
  );
}
