"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { ClipboardListIcon, TriangleAlertIcon } from "lucide-react";
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

import type { Loaded, PickListRow } from "../warehouse-queries";

import { completePickList, optimizePickRoute } from "../warehouse-actions";

type GridRow = PickListRow & { readonly canComplete: boolean };

type PickCell = CellContext<DataGridFeatures, GridRow>;

function DocumentCell({ row }: PickCell) {
  return (
    <span className="font-medium">
      {row.original.documentType.replaceAll("_", " ")} {row.original.documentId}
    </span>
  );
}

function ProgressCell({ row }: PickCell) {
  return (
    <span className="text-muted-foreground tabular-nums">
      {row.original.picked} / {row.original.lines}
    </span>
  );
}

function StatusCell({ row }: PickCell) {
  const t = useExtracted("warehouse");

  switch (row.original.status) {
    case "open": {
      return <Badge variant="info-light">{t("Open")}</Badge>;
    }

    case "picked": {
      return <Badge variant="success-light">{t("Picked")}</Badge>;
    }

    case "cancelled": {
      return <Badge variant="secondary">{t("Cancelled")}</Badge>;
    }

    default: {
      const unreachable: never = row.original.status;

      return unreachable;
    }
  }
}

function CompleteCell({ row }: PickCell) {
  const t = useExtracted("warehouse");
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const { id, canComplete } = row.original;

  if (!canComplete) {
    return null;
  }

  return (
    <div className="flex gap-2">
      <Button
        size="sm"
        variant="ghost"
        type="button"
        disabled={pending}
        onClick={() => {
          startTransition(async () => {
            await optimizePickRoute({ pickListId: id });
            router.refresh();
          });
        }}
      >
        {t("Plan route")}
      </Button>
      <Button
        size="sm"
        variant="outline"
        type="button"
        disabled={pending}
        onClick={() => {
          startTransition(async () => {
            await completePickList({ pickListId: id });
            router.refresh();
          });
        }}
      >
        {t("Complete")}
      </Button>
    </div>
  );
}

function Grid({
  rows,
  canPick,
}: {
  rows: readonly PickListRow[];
  canPick: boolean;
}) {
  const t = useExtracted("warehouse");

  const columns: ColumnDef<DataGridFeatures, GridRow>[] = [
    {
      accessorKey: "documentId",
      header: t("Document"),
      cell: DocumentCell,
      size: 240,
    },
    { id: "progress", header: t("Lines"), cell: ProgressCell, size: 120 },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 160 },
    { id: "actions", header: "", cell: CompleteCell, size: 220 },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: rows.map((row) => ({
      ...row,
      canComplete: canPick && row.status === "open",
    })),
    getRowId: (row) => row.id,
  });

  return (
    <DataGrid
      table={table}
      recordCount={rows.length}
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
 * The pick lists the caller reads in a data grid. A picker completes an open
 * list; lines with less picked than asked for become short.
 */
export function PickListGrid({
  state,
  canPick,
}: {
  state: Loaded<readonly PickListRow[]>;
  canPick: boolean;
}) {
  const t = useExtracted("warehouse");
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  if (state.kind === "no-organization") {
    return null;
  }

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Pick lists")}</FrameTitle>
        <FrameDescription>
          {t(
            "One list per document with allocated stock, with how many lines are picked.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The pick lists didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <Button
                size="sm"
                variant="outline"
                type="button"
                disabled={pending}
                onClick={() => {
                  startTransition(() => {
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
                <ClipboardListIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No pick lists yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Allocate stock to a document, then make a pick list from it to give a picker the lines and bins.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/warehouse"
              >
                {t("Read the warehouse guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <Grid rows={state.data} canPick={canPick} />
        )}
      </FramePanel>
    </Frame>
  );
}

export function PickListGridSkeleton() {
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
