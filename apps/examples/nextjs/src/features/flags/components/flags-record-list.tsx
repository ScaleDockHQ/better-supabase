"use client";

import { FlagIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";

import { Badge } from "@/components/reui/badge";
import { dateCell } from "@/features/admin-lists/admin-cells";
import { AdminRecordList } from "@/features/admin-lists/admin-record-list";

import type { FlagRow } from "../flags-list";

import { flagList } from "../flags-list";

function RolloutCell({ row }: { row: { original: FlagRow } }) {
  const { rollout } = row.original;

  return (
    <span className="text-xs text-muted-foreground">
      {rollout === null ? "–" : `${String(rollout)}%`}
    </span>
  );
}

function StateCell({ row }: { row: { original: FlagRow } }) {
  const t = useExtracted("flagAdmin");
  const { state } = row.original;

  return (
    <Badge variant={state === "on" ? "success-light" : "secondary"}>
      {state === "on" ? t("On") : state === "off" ? t("Off") : t("Archived")}
    </Badge>
  );
}

/** Flags on the list kit. */
export function FlagRecordList({
  initial,
}: {
  initial: RecordListPage<FlagRow>;
}) {
  const t = useExtracted("flagAdmin");

  const columns: RecordListColumns<FlagRow> = [
    { accessorKey: "key", header: t("Key"), size: 220 },
    { accessorKey: "description", header: t("Description"), size: 300 },
    { accessorKey: "defaultVariant", header: t("Default variant"), size: 140 },
    { id: "rollout", header: t("Rollout"), size: 100, cell: RolloutCell },
    { id: "state", header: t("State"), size: 110, cell: StateCell },
    {
      id: "created",
      header: t("Created"),
      size: 180,
      cell: dateCell<FlagRow>((row) => row.createdAt),
    },
  ];

  const labels = new Map([
    ["on", t("On")],
    ["off", t("Off")],
    ["archived", t("Archived")],
  ]);

  return (
    <AdminRecordList
      list={flagList}
      endpoint="/api/flags/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "state",
          label: t("State"),
          valueLabel: (value) => labels.get(value) ?? value,
        },
      ]}
      searchLabel={t("Search flags")}
      emptyIcon={<FlagIcon />}
      emptyTitle={t("No flags found")}
      emptyDescription={t(
        "Platform staff define flags in the database; change the filters to see more.",
      )}
    />
  );
}
