"use client";

import type { CellContext } from "@tanstack/react-table";

import { LibraryIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { useBlockListState } from "@/components/record-list/use-block-list-state";
import { Badge } from "@/components/reui/badge";
import { Link } from "@/i18n/navigation";

import type { RegisterRow } from "../document-register-list";

import { registerList } from "../document-register-list";
import { RegisterStatusBadge, useRegisterStatusLabel } from "./register-status";

type RegisterCell = CellContext<ReadOnlyGridFeatures, RegisterRow>;

function NumberCell({ row }: RegisterCell) {
  return (
    <Link
      href={`/documents/register/${row.original.id}`}
      className="font-medium tabular-nums hover:underline"
    >
      {row.original.number}
    </Link>
  );
}

function StatusCell({ row }: RegisterCell) {
  return <RegisterStatusBadge status={row.original.status} />;
}

function VersionCell({ row }: RegisterCell) {
  const t = useExtracted("documents");
  const { effectiveVersion } = row.original;

  return effectiveVersion === null ? (
    <span className="text-muted-foreground">–</span>
  ) : (
    <span className="tabular-nums">
      {t("v{version, number}", { version: effectiveVersion })}
    </span>
  );
}

function ReviewCell({ row }: RegisterCell) {
  const t = useExtracted("documents");
  const format = useFormatter();
  const { nextReviewOn, reviewDue } = row.original;

  if (nextReviewOn === null) {
    return <span className="text-muted-foreground">–</span>;
  }

  return (
    <span className="flex items-center gap-2">
      <span className="tabular-nums">
        {format.dateTime(new Date(nextReviewOn), {
          dateStyle: "medium",
          timeZone: "UTC",
        })}
      </span>
      {reviewDue ? (
        <Badge variant="warning-light">{t("Review due")}</Badge>
      ) : null}
    </span>
  );
}

/**
 * The controlled documents on the list kit, filtered by type, status and
 * review.
 */
export function RegisterRecordList({
  initial,
  types,
}: {
  initial: RecordListPage<RegisterRow>;
  types: readonly string[];
}) {
  const t = useExtracted("documents");
  const statusLabel = useRegisterStatusLabel();
  const list = useBlockListState(registerList);

  const columns: RecordListColumns<RegisterRow> = [
    { accessorKey: "number", header: t("Number"), size: 120, cell: NumberCell },
    { accessorKey: "name", header: t("Document"), size: 260 },
    { accessorKey: "type", header: t("Type"), size: 110 },
    { id: "status", header: t("Status"), size: 130, cell: StatusCell },
    { id: "effective", header: t("Effective"), size: 100, cell: VersionCell },
    { id: "review", header: t("Next review"), size: 220, cell: ReviewCell },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/documents/register/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "type",
          label: t("Type"),
          valueLabel: (value) => value,
          values: types,
        },
        { key: "status", label: t("Status"), valueLabel: statusLabel },
        { key: "review", label: t("Review"), valueLabel: statusLabel },
      ]}
      sorts={[
        { value: "number", label: t("Number") },
        { value: "name", label: t("Name") },
        { value: "review", label: t("Next review") },
      ]}
      searchLabel={t("Search the register")}
      emptyIcon={<LibraryIcon />}
      emptyTitle={t("No controlled documents found")}
      emptyDescription={t(
        "Save a file in the drive as a controlled document, or change the filters.",
      )}
    />
  );
}
