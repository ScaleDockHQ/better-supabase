"use client";

import type { CellContext } from "@tanstack/react-table";

import { ListOrderedIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { Badge } from "@/components/reui/badge";
import { AdminRecordList } from "@/features/admin-lists/admin-record-list";
import { Link } from "@/i18n/navigation";

import type { OptionSetRow } from "../option-sets-list";

import { optionSetList } from "../option-sets-list";
import { EnsurePrioritySetButton } from "./option-set-controls";

type SetCell = CellContext<ReadOnlyGridFeatures, OptionSetRow>;

function NameCell({ row }: SetCell) {
  const t = useExtracted("optionSets");
  const { id, name, isDefault } = row.original;

  return (
    <div className="flex items-center gap-2">
      <Link
        href={`/settings/option-sets/${id}`}
        prefetch
        className="font-medium hover:underline"
      >
        {name}
      </Link>
      {isDefault ? <Badge variant="info-light">{t("Default")}</Badge> : null}
    </div>
  );
}

function StateCell({ row }: SetCell) {
  const t = useExtracted("optionSets");

  return row.original.archived ? (
    <Badge variant="secondary">{t("Archived")}</Badge>
  ) : (
    <Badge variant="success-light">{t("Active")}</Badge>
  );
}

/** The option sets overview on the list kit. */
export function OptionSetRecordList({
  initial,
  canManage,
}: {
  initial: RecordListPage<OptionSetRow>;
  canManage: boolean;
}) {
  const t = useExtracted("optionSets");

  const columns: RecordListColumns<OptionSetRow> = [
    { accessorKey: "name", header: t("Name"), size: 280, cell: NameCell },
    { accessorKey: "subjectType", header: t("Record type"), size: 160 },
    { accessorKey: "field", header: t("Field"), size: 140 },
    { accessorKey: "items", header: t("Options"), size: 100 },
    { accessorKey: "archived", header: t("State"), size: 120, cell: StateCell },
  ];

  return (
    <AdminRecordList
      list={optionSetList}
      endpoint="/api/option-sets/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "state",
          label: t("State"),
          valueLabel: (value) =>
            value === "archived" ? t("Archived") : t("Active"),
        },
      ]}
      searchLabel={t("Search option sets")}
      emptyIcon={<ListOrderedIcon />}
      emptyTitle={t("No option sets found")}
      emptyDescription={
        canManage
          ? t("Create the task priorities, or change the filters.")
          : t("Change the filters to see more.")
      }
      emptyAction={canManage ? <EnsurePrioritySetButton /> : undefined}
    />
  );
}
