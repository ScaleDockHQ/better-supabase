// #region recipe:meeting-agenda
"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { GavelIcon, TriangleAlertIcon } from "lucide-react";
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

import type { Loaded, MeetingRow } from "../meetings-queries";

import { MeetingStatusBadge, useKindLabel } from "./meeting-labels";

type MeetingCell = CellContext<DataGridFeatures, MeetingRow>;

function StartsCell({ row }: MeetingCell) {
  const format = useFormatter();

  return (
    <span className="tabular-nums">
      {format.dateTime(new Date(row.original.startsAt), {
        dateStyle: "medium",
        timeStyle: "short",
      })}
    </span>
  );
}

function TitleCell({ row }: MeetingCell) {
  return (
    <Link
      href={`/meetings?meeting=${row.original.id}`}
      className="font-medium underline-offset-4 transition-colors hover:underline"
    >
      {row.original.title}
    </Link>
  );
}

function KindCell({ row }: MeetingCell) {
  const kind = useKindLabel();

  return <span>{kind(row.original.kind)}</span>;
}

function LocationCell({ row }: MeetingCell) {
  return (
    <span className="text-muted-foreground">
      {row.original.location ?? "–"}
    </span>
  );
}

function StatusCell({ row }: MeetingCell) {
  return <MeetingStatusBadge status={row.original.status} />;
}

function AgendaGrid({ meetings }: { meetings: readonly MeetingRow[] }) {
  const t = useExtracted("meetings");

  const columns: ColumnDef<DataGridFeatures, MeetingRow>[] = [
    {
      accessorKey: "startsAt",
      header: t("Starts"),
      cell: StartsCell,
      size: 180,
    },
    { accessorKey: "title", header: t("Meeting"), cell: TitleCell, size: 260 },
    { accessorKey: "kind", header: t("Kind"), cell: KindCell, size: 160 },
    {
      accessorKey: "location",
      header: t("Location"),
      cell: LocationCell,
      size: 160,
    },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 120 },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...meetings],
    getRowId: (row) => row.id,
  });

  return (
    <DataGrid
      table={table}
      recordCount={meetings.length}
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
 * The organization's meetings in a data grid, the most recent first, each with
 * its kind, place and status. Open one to see its agenda and decisions.
 */
export function MeetingAgenda({
  state,
}: {
  state: Loaded<readonly MeetingRow[]>;
}) {
  const t = useExtracted("meetings");
  const router = useRouter();
  const [retrying, startRetry] = useTransition();

  if (state.kind === "no-organization") {
    return null;
  }

  return (
    <Frame spacing="sm" data-recipe="meeting-agenda">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Meetings")}</FrameTitle>
        <FrameDescription>
          {t("Every meeting, the most recent first. Open one for its minutes.")}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The meetings didn't load")}</AlertTitle>
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
                <GavelIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No meetings yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Plan a meeting with its attendees and agenda, then record the minutes and decisions while it runs.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/meetings"
              >
                {t("Read the meetings guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <AgendaGrid meetings={state.data} />
        )}
      </FramePanel>
    </Frame>
  );
}

export function MeetingAgendaSkeleton() {
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
// #endregion recipe:meeting-agenda
