"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { ShieldAlertIcon, TriangleAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";
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

import type { CareAlertRow, Loaded } from "../care-alerts-queries";

import { acknowledgeCareAlert } from "../care-alerts-actions";

type AlertCell = CellContext<DataGridFeatures, CareAlertRow>;

function SeverityCell({ row }: AlertCell) {
  const t = useExtracted("care-alerts");

  switch (row.original.severity) {
    case "critical": {
      return <Badge variant="destructive-light">{t("Critical")}</Badge>;
    }

    case "warning": {
      return <Badge variant="warning-light">{t("Warning")}</Badge>;
    }

    case "info": {
      return <Badge variant="info-light">{t("Info")}</Badge>;
    }

    default: {
      const never: never = row.original.severity;

      return never;
    }
  }
}

function StatusCell({ row }: AlertCell) {
  const t = useExtracted("care-alerts");

  switch (row.original.status) {
    case "open": {
      return <Badge variant="warning-light">{t("Open")}</Badge>;
    }

    case "acknowledged": {
      return <Badge variant="success-light">{t("Acknowledged")}</Badge>;
    }

    case "overridden": {
      return <Badge variant="info-light">{t("Overridden")}</Badge>;
    }

    case "resolved": {
      return <Badge variant="success-light">{t("Resolved")}</Badge>;
    }

    default: {
      const never: never = row.original.status;

      return never;
    }
  }
}

function MessageCell({ row }: AlertCell) {
  return <span className="font-medium">{row.original.message}</span>;
}

function SubjectCell({ row }: AlertCell) {
  return <span className="text-muted-foreground">{row.original.subject}</span>;
}

function acknowledgeAction({
  alert,
  canDecide,
  pending,
  label,
  onAcknowledge,
}: {
  alert: CareAlertRow;
  canDecide: boolean;
  pending: boolean;
  label: string;
  onAcknowledge: (alertId: string) => void;
}) {
  if (!canDecide || alert.status !== "open" || alert.severity === "critical") {
    return null;
  }

  return (
    <Button
      size="sm"
      variant="outline"
      type="button"
      disabled={pending}
      onClick={() => {
        onAcknowledge(alert.id);
      }}
    >
      {label}
    </Button>
  );
}

function AlertGrid({
  alerts,
  canDecide,
  pending,
  onAcknowledge,
}: {
  alerts: readonly CareAlertRow[];
  canDecide: boolean;
  pending: boolean;
  onAcknowledge: (alertId: string) => void;
}) {
  const t = useExtracted("care-alerts");

  const columns: ColumnDef<DataGridFeatures, CareAlertRow>[] = [
    {
      accessorKey: "severity",
      header: t("Severity"),
      cell: SeverityCell,
      size: 120,
    },
    {
      accessorKey: "message",
      header: t("Alert"),
      cell: MessageCell,
      size: 380,
    },
    {
      accessorKey: "subject",
      header: t("Record"),
      cell: SubjectCell,
      size: 160,
    },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 140 },
    {
      id: "actions",
      header: "",
      size: 140,
      cell: ({ row }: AlertCell) =>
        acknowledgeAction({
          alert: row.original,
          canDecide,
          pending,
          label: t("Acknowledge"),
          onAcknowledge,
        }),
    },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...alerts],
    getRowId: (row) => row.id,
  });

  return (
    <DataGrid
      table={table}
      recordCount={alerts.length}
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
 * The care alerts that dose range, duplicate therapy and interaction rules
 * raised on medication orders, with Acknowledge for the ones that don't need a
 * reason.
 */
export function CareAlerts({
  state,
  canDecide,
}: {
  state: Loaded<readonly CareAlertRow[]>;
  canDecide: boolean;
}) {
  const t = useExtracted("care-alerts");
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

  const acknowledge = (alertId: string) => {
    startTransition(async () => {
      await acknowledgeCareAlert({ alertId });
      router.refresh();
    });
  };

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Alerts")}</FrameTitle>
        <FrameDescription>
          {t(
            "Evaluating a record checks its active medication orders. Critical alerts need an override reason.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The alerts didn't load")}</AlertTitle>
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
                <ShieldAlertIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No alerts")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Add dose range, duplicate therapy or interaction rules, then evaluate a record after prescribing.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Button
                size="sm"
                variant="outline"
                type="button"
                onClick={refresh}
              >
                {t("Check again")}
              </Button>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/clinical-decision-support"
              >
                {t("Read the decision support guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <AlertGrid
            alerts={state.data}
            canDecide={canDecide}
            pending={pending}
            onAcknowledge={acknowledge}
          />
        )}
      </FramePanel>
    </Frame>
  );
}

export function CareAlertsSkeleton() {
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
