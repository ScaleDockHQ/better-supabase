"use client";

import type { CellContext } from "@tanstack/react-table";

import { UserRoundCheckIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { useBlockListState } from "@/components/record-list/use-block-list-state";
import { Link } from "@/i18n/navigation";

import type { OnboardingRow } from "../onboarding-list";

import { onboardingList } from "../onboarding-list";
import {
  OnboardingStatusBadge,
  useOnboardingStatusLabel,
} from "./onboarding-status";

type OnboardingCell = CellContext<ReadOnlyGridFeatures, OnboardingRow>;

function WhoCell({ row }: OnboardingCell) {
  const { employeeId, who } = row.original;

  return (
    <Link
      href={`/people/${employeeId}`}
      className="font-medium hover:underline"
    >
      {who}
    </Link>
  );
}

function ProgressCell({ row }: OnboardingCell) {
  const t = useExtracted("people");
  const { completed, total } = row.original;

  return (
    <span className="tabular-nums">
      {t("{done} of {total} steps", {
        done: String(completed),
        total: String(total),
      })}
    </span>
  );
}

function StatusCell({ row }: OnboardingCell) {
  return <OnboardingStatusBadge status={row.original.status} />;
}

/** Employee onboarding runs on the list kit, filtered by status and program. */
export function OnboardingRecordList({
  initial,
  programs,
}: {
  initial: RecordListPage<OnboardingRow>;
  programs: readonly { readonly key: string; readonly name: string }[];
}) {
  const t = useExtracted("people");
  const statusLabel = useOnboardingStatusLabel();
  const list = useBlockListState(onboardingList);
  const programName = new Map(programs.map((p) => [p.key, p.name]));

  const columns: RecordListColumns<OnboardingRow> = [
    { accessorKey: "who", header: t("Employee"), size: 220, cell: WhoCell },
    { accessorKey: "programName", header: t("Program"), size: 180 },
    { id: "progress", header: t("Progress"), size: 160, cell: ProgressCell },
    { accessorKey: "startsAt", header: t("Starts"), size: 140 },
    { accessorKey: "status", header: t("Status"), size: 140, cell: StatusCell },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/onboarding/list"
      initial={initial}
      columns={columns}
      facets={[
        { key: "status", label: t("Status"), valueLabel: statusLabel },
        {
          key: "program",
          label: t("Program"),
          valueLabel: (value) => programName.get(value) ?? value,
        },
      ]}
      sorts={[
        { value: "newest", label: t("Newest") },
        { value: "progress", label: t("Least done") },
        { value: "name", label: t("Name") },
      ]}
      searchLabel={t("Search onboarding")}
      emptyIcon={<UserRoundCheckIcon />}
      emptyTitle={t("No onboarding runs found")}
      emptyDescription={t("Enroll an employee, or change the filters.")}
    />
  );
}
