"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { TriangleAlertIcon, WrenchIcon } from "lucide-react";
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
import { Badge } from "@/components/reui/badge";
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

import type { Loaded, MaintenancePlanRow } from "../maintenance-queries";

import { generateWorkOrders } from "../maintenance-actions";

type PlanCell = CellContext<DataGridFeatures, MaintenancePlanRow>;

function TitleCell({ row }: PlanCell) {
  return <span className="font-medium">{row.original.title}</span>;
}

function KindCell({ row }: PlanCell) {
  const t = useExtracted("maintenance");

  return <span>{row.original.kind === "time" ? t("Time") : t("Meter")}</span>;
}

function NextDueCell({ row }: PlanCell) {
  const format = useFormatter();
  const { nextDueAt } = row.original;

  return (
    <span className="text-muted-foreground tabular-nums">
      {nextDueAt === null
        ? "–"
        : format.dateTime(new Date(nextDueAt), { dateStyle: "medium" })}
    </span>
  );
}

function StatusCell({ row }: PlanCell) {
  const t = useExtracted("maintenance");
  const { status, due, hasWorkOrder } = row.original;

  if (status === "paused") {
    return <Badge variant="outline">{t("Paused")}</Badge>;
  }

  if (hasWorkOrder) {
    return <Badge variant="info-light">{t("Work order open")}</Badge>;
  }

  return due ? (
    <Badge variant="warning-light">{t("Due")}</Badge>
  ) : (
    <Badge variant="secondary">{t("Scheduled")}</Badge>
  );
}

function PlanGrid({ plans }: { plans: readonly MaintenancePlanRow[] }) {
  const t = useExtracted("maintenance");

  const columns: ColumnDef<DataGridFeatures, MaintenancePlanRow>[] = [
    { accessorKey: "title", header: t("Plan"), cell: TitleCell, size: 280 },
    { accessorKey: "kind", header: t("Trigger"), cell: KindCell, size: 120 },
    {
      accessorKey: "nextDueAt",
      header: t("Next due"),
      cell: NextDueCell,
      size: 160,
    },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 160 },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...plans],
    getRowId: (row) => row.id,
  });

  return (
    <DataGrid
      table={table}
      recordCount={plans.length}
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
 * The organization's preventive maintenance plans in a data grid, the soonest
 * due first. Generate opens a dispatch work order for every plan that is due.
 */
export function MaintenancePlans({
  state,
  canManage,
}: {
  state: Loaded<readonly MaintenancePlanRow[]>;
  canManage: boolean;
}) {
  const t = useExtracted("maintenance");
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  if (state.kind === "no-organization") {
    return null;
  }

  const refresh = () => {
    startTransition(() => {
      router.refresh();
    });
  };

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Maintenance plans")}</FrameTitle>
        <FrameDescription>
          {t(
            "Plans fall due by time or by meter and open dispatch work orders.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The plans didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <Button
                size="sm"
                variant="outline"
                type="button"
                disabled={pending}
                onClick={refresh}
              >
                {t("Retry")}
              </Button>
            </AlertAction>
          </Alert>
        ) : state.data.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <WrenchIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No maintenance plans yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Create a plan by time or meter, with the spare parts it needs, and work orders open when it falls due.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/maintenance"
              >
                {t("Read the maintenance guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <div className="flex flex-col gap-3">
            {canManage ? (
              <div className="flex justify-end">
                <Button
                  size="sm"
                  type="button"
                  disabled={pending}
                  onClick={() => {
                    startTransition(async () => {
                      await generateWorkOrders({});
                      router.refresh();
                    });
                  }}
                >
                  {t("Generate work orders")}
                </Button>
              </div>
            ) : null}
            <PlanGrid plans={state.data} />
          </div>
        )}
      </FramePanel>
    </Frame>
  );
}

export function MaintenancePlansSkeleton() {
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
