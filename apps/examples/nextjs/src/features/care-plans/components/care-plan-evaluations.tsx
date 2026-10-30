// #region recipe:care-plan-evaluations
"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { ListChecksIcon, TriangleAlertIcon } from "lucide-react";
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

import type {
  CarePlanEvaluationRow,
  CarePlanState,
  Loaded,
} from "../care-plans-queries";

import { GoalStatusBadge } from "./care-plan-editor";

type EvaluationCell = CellContext<DataGridFeatures, CarePlanEvaluationRow>;

function DateCell({ row }: EvaluationCell) {
  const format = useFormatter();

  return (
    <span className="tabular-nums">
      {format.dateTime(new Date(row.original.evaluatedAt), {
        dateStyle: "medium",
      })}
    </span>
  );
}

function GoalCell({ row }: EvaluationCell) {
  return <span className="font-medium">{row.original.goal}</span>;
}

function StatusCell({ row }: EvaluationCell) {
  return <GoalStatusBadge status={row.original.status} />;
}

function OutcomeCell({ row }: EvaluationCell) {
  return row.original.outcome === null ? (
    <span className="text-muted-foreground">–</span>
  ) : (
    <span className="line-clamp-2">{row.original.outcome}</span>
  );
}

function EvaluationGrid({
  evaluations,
}: {
  evaluations: readonly CarePlanEvaluationRow[];
}) {
  const t = useExtracted("care-plans");

  const columns: ColumnDef<DataGridFeatures, CarePlanEvaluationRow>[] = [
    {
      accessorKey: "evaluatedAt",
      header: t("Date"),
      cell: DateCell,
      size: 130,
    },
    { accessorKey: "goal", header: t("Goal"), cell: GoalCell, size: 240 },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 140 },
    {
      accessorKey: "outcome",
      header: t("Outcome"),
      cell: OutcomeCell,
      size: 320,
    },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...evaluations],
    getRowId: (row) => row.id,
  });

  return (
    <DataGrid
      table={table}
      recordCount={evaluations.length}
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
 * The evaluations of a care plan's goals, the newest first, with the goal
 * status each one found.
 */
export function CarePlanEvaluations({
  state,
}: {
  state: Loaded<CarePlanState>;
}) {
  const t = useExtracted("care-plans");
  const router = useRouter();
  const [retrying, startRetry] = useTransition();

  if (state.kind === "no-organization") {
    return null;
  }

  const evaluations =
    state.kind === "ok" && "evaluations" in state.data
      ? state.data.evaluations
      : [];

  return (
    <Frame spacing="sm" data-recipe="care-plan-evaluations">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Evaluations")}</FrameTitle>
        <FrameDescription>
          {t(
            "What each evaluation found for a goal. A new status becomes the goal's status.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The evaluations didn't load")}</AlertTitle>
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
        ) : evaluations.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ListChecksIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No evaluations yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Evaluate a goal of the active plan to record what it reached.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/care-plans#evaluations-and-reviews"
              >
                {t("Read about evaluations")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <EvaluationGrid evaluations={evaluations} />
        )}
      </FramePanel>
    </Frame>
  );
}

export function CarePlanEvaluationsSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-28" />
        <Skeleton className="h-4 w-80" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-40" />
      </FramePanel>
    </Frame>
  );
}
// #endregion recipe:care-plan-evaluations
