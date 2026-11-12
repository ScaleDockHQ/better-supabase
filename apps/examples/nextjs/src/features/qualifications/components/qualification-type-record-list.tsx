"use client";

import type { CellContext } from "@tanstack/react-table";

import { BadgeCheckIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { useBlockListState } from "@/components/record-list/use-block-list-state";
import { Badge } from "@/components/reui/badge";
import { Link } from "@/i18n/navigation";

import type { QualificationTypeRow } from "../qualifications-types-list";

import { qualificationTypeList } from "../qualifications-types-list";

type TypeCell = CellContext<ReadOnlyGridFeatures, QualificationTypeRow>;

function NameCell({ row }: TypeCell) {
  return (
    <Link
      href={`/qualifications/${row.original.id}`}
      className="font-medium hover:underline"
    >
      {row.original.name}
    </Link>
  );
}

function ValidityCell({ row }: TypeCell) {
  const t = useExtracted("qualifications");
  const months = row.original.validForMonths;

  return (
    <span className="text-muted-foreground tabular-nums">
      {months === null
        ? t("Never expires")
        : t("{months} months", { months: String(months) })}
    </span>
  );
}

function StateCell({ row }: TypeCell) {
  const t = useExtracted("qualifications");

  return row.original.archived ? (
    <Badge variant="secondary">{t("Archived")}</Badge>
  ) : (
    <Badge variant="success-light">{t("Active")}</Badge>
  );
}

/** Qualification types on the list kit, filtered by expiry and state. */
export function QualificationTypeRecordList({
  initial,
}: {
  initial: RecordListPage<QualificationTypeRow>;
}) {
  const t = useExtracted("qualifications");
  const list = useBlockListState(qualificationTypeList);

  const columns: RecordListColumns<QualificationTypeRow> = [
    { accessorKey: "name", header: t("Name"), size: 240, cell: NameCell },
    { accessorKey: "key", header: t("Key"), size: 160 },
    { id: "validity", header: t("Valid for"), size: 160, cell: ValidityCell },
    { id: "state", header: t("State"), size: 120, cell: StateCell },
  ];

  const valueLabel = (value: string): string => {
    switch (value) {
      case "expires": {
        return t("Expires");
      }

      case "never": {
        return t("Never expires");
      }

      case "active": {
        return t("Active");
      }

      case "archived": {
        return t("Archived");
      }

      default: {
        return value;
      }
    }
  };

  return (
    <RecordListView
      list={list}
      endpoint="/api/qualifications/list"
      initial={initial}
      columns={columns}
      facets={[
        { key: "expiry", label: t("Validity"), valueLabel },
        { key: "state", label: t("State"), valueLabel },
      ]}
      sorts={[
        { value: "name", label: t("Name") },
        { value: "key", label: t("Key") },
      ]}
      searchLabel={t("Search qualification types")}
      emptyIcon={<BadgeCheckIcon />}
      emptyTitle={t("No qualification types found")}
      emptyDescription={t("Change the search or the filters.")}
    />
  );
}
