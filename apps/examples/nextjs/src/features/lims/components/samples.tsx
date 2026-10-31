"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { FlaskConicalIcon, TriangleAlertIcon } from "lucide-react";
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

import type { Loaded, SampleRow } from "../lims-queries";

import { registerSample } from "../lims-actions";

type SampleCell = CellContext<DataGridFeatures, SampleRow>;

function NumberCell({ row }: SampleCell) {
  return (
    <span className="font-medium tabular-nums">{row.original.number}</span>
  );
}

function TitleCell({ row }: SampleCell) {
  const { title, lot } = row.original;

  return (
    <span>
      {title}
      {lot === null ? null : (
        <span className="text-muted-foreground"> ({lot})</span>
      )}
    </span>
  );
}

function ReceivedCell({ row }: SampleCell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground tabular-nums">
      {format.dateTime(new Date(row.original.receivedOn), {
        dateStyle: "medium",
      })}
    </span>
  );
}

function StatusCell({ row }: SampleCell) {
  const t = useExtracted("lims");

  switch (row.original.status) {
    case "registered": {
      return <Badge variant="info-light">{t("Registered")}</Badge>;
    }

    case "in_testing": {
      return <Badge variant="warning-light">{t("In testing")}</Badge>;
    }

    case "completed": {
      return <Badge variant="primary-light">{t("Completed")}</Badge>;
    }

    case "released": {
      return <Badge variant="success-light">{t("Released")}</Badge>;
    }

    case "rejected": {
      return <Badge variant="destructive-light">{t("Rejected")}</Badge>;
    }

    default: {
      const never: never = row.original.status;

      return never;
    }
  }
}

function SampleGrid({ samples }: { samples: readonly SampleRow[] }) {
  const t = useExtracted("lims");

  const columns: ColumnDef<DataGridFeatures, SampleRow>[] = [
    { accessorKey: "number", header: t("Number"), cell: NumberCell, size: 120 },
    { accessorKey: "title", header: t("Sample"), cell: TitleCell, size: 280 },
    {
      accessorKey: "receivedOn",
      header: t("Received"),
      cell: ReceivedCell,
      size: 160,
    },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 140 },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...samples],
    getRowId: (row) => row.id,
  });

  return (
    <DataGrid
      table={table}
      recordCount={samples.length}
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
 * The organization's laboratory samples in a data grid. Register adds a sample
 * with the next SMP number.
 */
export function Samples({
  state,
  canWrite,
}: {
  state: Loaded<readonly SampleRow[]>;
  canWrite: boolean;
}) {
  const t = useExtracted("lims");
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

  const register = () => {
    startTransition(async () => {
      await registerSample({ title: t("New sample") });
      router.refresh();
    });
  };

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Samples")}</FrameTitle>
        <FrameDescription>
          {t(
            "A result outside a method's limits opens a nonconformity and holds the release.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The samples didn't load")}</AlertTitle>
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
                <FlaskConicalIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No samples yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Register a sample, then record results against a method's limits.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              {canWrite ? (
                <Button
                  size="sm"
                  type="button"
                  disabled={pending}
                  onClick={register}
                >
                  {t("Register a sample")}
                </Button>
              ) : null}
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/lims"
              >
                {t("Read the laboratory guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <div className="flex flex-col gap-3">
            {canWrite ? (
              <div className="flex justify-end">
                <Button
                  size="sm"
                  variant="outline"
                  type="button"
                  disabled={pending}
                  onClick={register}
                >
                  {t("Register a sample")}
                </Button>
              </div>
            ) : null}
            <SampleGrid samples={state.data} />
          </div>
        )}
      </FramePanel>
    </Frame>
  );
}

export function SamplesSkeleton() {
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
