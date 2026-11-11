"use client";

import type { CellContext } from "@tanstack/react-table";

import { GlobeIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { Badge } from "@/components/reui/badge";
import { AdminRecordList } from "@/features/admin-lists/admin-record-list";

import type { DomainRow } from "../domains-list";

import { domainList } from "../domains-list";
import {
  AddDomainDialog,
  DomainActions,
  DomainRecord,
} from "./domain-controls";

type DomainCell = CellContext<ReadOnlyGridFeatures, DomainRow>;

function HostnameCell({ row }: DomainCell) {
  const t = useExtracted("domains");
  const { hostname, primary } = row.original;

  return (
    <div className="flex items-center gap-2 font-medium">
      {hostname}
      {primary ? <Badge variant="info-light">{t("Primary")}</Badge> : null}
    </div>
  );
}

function StateCell({ row }: DomainCell) {
  const t = useExtracted("domains");

  return row.original.verified ? (
    <Badge variant="success-light">{t("Verified")}</Badge>
  ) : (
    <Badge variant="warning-light">{t("Pending")}</Badge>
  );
}

function RecordCell({ row }: DomainCell) {
  const { record } = row.original;

  return record ? (
    <DomainRecord name={record.name} value={record.value} />
  ) : (
    <span className="text-muted-foreground">–</span>
  );
}

function AddedCell({ row }: DomainCell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground">
      {format.dateTime(new Date(row.original.createdAt), {
        dateStyle: "medium",
      })}
    </span>
  );
}

function ActionsCell({ row }: DomainCell) {
  const { id, hostname, verified, primary } = row.original;

  return (
    <DomainActions
      id={id}
      hostname={hostname}
      verified={verified}
      primary={primary}
    />
  );
}

/** The domains overview on the list kit. */
export function DomainRecordList({
  initial,
  canManage,
}: {
  initial: RecordListPage<DomainRow>;
  canManage: boolean;
}) {
  const t = useExtracted("domains");

  const columns: RecordListColumns<DomainRow> = [
    {
      accessorKey: "hostname",
      header: t("Hostname"),
      size: 260,
      cell: HostnameCell,
    },
    { accessorKey: "verified", header: t("State"), size: 120, cell: StateCell },
    { accessorKey: "kind", header: t("Kind"), size: 110 },
    { id: "record", header: t("TXT record"), size: 260, cell: RecordCell },
    {
      accessorKey: "createdAt",
      header: t("Added"),
      size: 130,
      cell: AddedCell,
    },
    ...(canManage
      ? [{ id: "actions", header: "", size: 220, cell: ActionsCell }]
      : []),
  ];

  const labels = new Map([
    ["verified", t("Verified")],
    ["pending", t("Pending")],
    ["custom", t("Custom")],
    ["subdomain", t("Subdomain")],
  ]);

  return (
    <AdminRecordList
      list={domainList}
      endpoint="/api/domains/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "state",
          label: t("State"),
          valueLabel: (value) => labels.get(value) ?? value,
        },
        {
          key: "kind",
          label: t("Kind"),
          valueLabel: (value) => labels.get(value) ?? value,
        },
      ]}
      searchLabel={t("Search domains")}
      emptyIcon={<GlobeIcon />}
      emptyTitle={t("No domains found")}
      emptyDescription={
        canManage
          ? t("Add a domain, or change the filters.")
          : t("Change the filters to see more.")
      }
      emptyAction={canManage ? <AddDomainDialog /> : undefined}
    />
  );
}
