// #region recipe:inspection-program-calendar
"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { ClipboardCheckIcon, TriangleAlertIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useRouter } from "next/navigation";
import { useTransition } from "react";

import type { DataGridFeatures } from "@/components/reui/data-grid/data-grid";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import {
  DataGrid,
  DataGridContainer,
  dataGridFeatures,
} from "@/components/reui/data-grid/data-grid";
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area";
import { DataGridTable } from "@/components/reui/data-grid/data-grid-table";
import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

import type { InspectionRow, Loaded } from "../inspections-queries";

import { InspectionStatusBadge, useKindLabel } from "./inspection-labels";

type InspectionCell = CellContext<DataGridFeatures, InspectionRow>;

function PlannedCell({ row }: InspectionCell) {
  const t = useExtracted("inspections");
  const format = useFormatter();
  const { plannedStart } = row.original;

  return plannedStart === null ? (
    <span className="text-muted-foreground">{t("Not planned")}</span>
  ) : (
    <span className="tabular-nums">
      {format.dateTime(new Date(plannedStart), {
        month: "long",
        year: "numeric",
        timeZone: "UTC",
      })}
    </span>
  );
}

function NumberCell({ row }: InspectionCell) {
  return (
    <span className="font-mono text-xs text-muted-foreground">
      {row.original.number}
    </span>
  );
}

function TitleCell({ row }: InspectionCell) {
  return (
    <Link
      href={`/inspections?inspection=${row.original.id}`}
      className="font-medium underline-offset-4 transition-colors hover:underline"
    >
      {row.original.title}
    </Link>
  );
}

function KindCell({ row }: InspectionCell) {
  const kind = useKindLabel();

  return <span>{kind(row.original.kind)}</span>;
}

function ProgramCell({ row }: InspectionCell) {
  return (
    <span className="text-muted-foreground">{row.original.program ?? "–"}</span>
  );
}

function StatusCell({ row }: InspectionCell) {
  return <InspectionStatusBadge status={row.original.status} />;
}

function CalendarGrid({
  inspections,
}: {
  inspections: readonly InspectionRow[];
}) {
  const t = useExtracted("inspections");

  const columns: ColumnDef<DataGridFeatures, InspectionRow>[] = [
    {
      accessorKey: "plannedStart",
      header: t("Planned"),
      cell: PlannedCell,
      size: 150,
    },
    { accessorKey: "number", header: t("Number"), cell: NumberCell, size: 130 },
    {
      accessorKey: "title",
      header: t("Inspection"),
      cell: TitleCell,
      size: 260,
    },
    { accessorKey: "kind", header: t("Kind"), cell: KindCell, size: 160 },
    {
      accessorKey: "program",
      header: t("Programme"),
      cell: ProgramCell,
      size: 180,
    },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 120 },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...inspections],
    getRowId: (row) => row.id,
  });

  return (
    <DataGrid
      table={table}
      recordCount={inspections.length}
      tableLayout={{ dense: true }}
    >
      <DataGridContainer>
        <DataGridScrollArea>
          <DataGridTable />
        </DataGridScrollArea>
      </DataGridContainer>
    </DataGrid>
  );
}

/**
 * The organization's audit programme as a calendar: each inspection in the
 * month it is planned, with its kind, programme and status.
 */
export function InspectionProgramCalendar({
  state,
}: {
  state: Loaded<readonly InspectionRow[]>;
}) {
  const t = useExtracted("inspections");
  const router = useRouter();
  const [retrying, startRetry] = useTransition();

  if (state.kind === "no-organization") {
    return null;
  }

  return (
    <Frame spacing="sm" data-recipe="inspection-program-calendar">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Audit programme")}</FrameTitle>
        <FrameDescription>
          {t(
            "Every audit and inspection in the month it is planned. Open one to work its findings.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The audit programme didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <Button
                size="sm"
                variant="outline"
                type="button"
                disabled={retrying}
                onClick={() => {
                  startRetry(() => {
                    router.refresh();
                  });
                }}
              >
                {t("Retry")}
              </Button>
            </AlertAction>
          </Alert>
        ) : state.data.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ClipboardCheckIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No inspections planned")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Approve an audit programme for the year, then schedule its audits with a lead and a checklist.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/inspections"
              >
                {t("Read the inspections guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <CalendarGrid inspections={state.data} />
        )}
      </FramePanel>
    </Frame>
  );
}

export function InspectionProgramCalendarSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-36" />
        <Skeleton className="h-4 w-80" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-48" />
      </FramePanel>
    </Frame>
  );
}
// #endregion recipe:inspection-program-calendar
