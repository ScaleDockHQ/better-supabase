"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { FileQuestionMarkIcon, TriangleAlertIcon } from "lucide-react";
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

import type { Loaded, RfqRow } from "../rfqs-queries";

import { createRfq } from "../rfqs-actions";

type RfqCell = CellContext<DataGridFeatures, RfqRow>;

function NumberCell({ row }: RfqCell) {
  return (
    <span className="font-medium tabular-nums">{row.original.number}</span>
  );
}

function TitleCell({ row }: RfqCell) {
  return <span>{row.original.title}</span>;
}

function DueCell({ row }: RfqCell) {
  const format = useFormatter();
  const { dueAt } = row.original;

  return (
    <span className="text-muted-foreground tabular-nums">
      {dueAt === null
        ? "-"
        : format.dateTime(new Date(dueAt), { dateStyle: "medium" })}
    </span>
  );
}

function StatusCell({ row }: RfqCell) {
  const t = useExtracted("rfqs");

  switch (row.original.status) {
    case "draft": {
      return <Badge variant="secondary">{t("Draft")}</Badge>;
    }

    case "open": {
      return <Badge variant="info-light">{t("Open")}</Badge>;
    }

    case "closed": {
      return <Badge variant="warning-light">{t("Closed")}</Badge>;
    }

    case "awarded": {
      return <Badge variant="success-light">{t("Awarded")}</Badge>;
    }

    case "cancelled": {
      return <Badge variant="destructive-light">{t("Cancelled")}</Badge>;
    }

    default: {
      const never: never = row.original.status;

      return never;
    }
  }
}

function RfqGrid({ rfqs }: { rfqs: readonly RfqRow[] }) {
  const t = useExtracted("rfqs");

  const columns: ColumnDef<DataGridFeatures, RfqRow>[] = [
    { accessorKey: "number", header: t("Number"), cell: NumberCell, size: 120 },
    { accessorKey: "title", header: t("Request"), cell: TitleCell, size: 280 },
    { accessorKey: "dueAt", header: t("Quotes due"), cell: DueCell, size: 160 },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 140 },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...rfqs],
    getRowId: (row) => row.id,
  });

  return (
    <DataGrid
      table={table}
      recordCount={rfqs.length}
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
 * The organization's requests for quotation in a data grid. Create adds a draft
 * with the next RFQ number.
 */
export function Rfqs({
  state,
  canWrite,
}: {
  state: Loaded<readonly RfqRow[]>;
  canWrite: boolean;
}) {
  const t = useExtracted("rfqs");
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
      await createRfq({ title: t("New request") });
      router.refresh();
    });
  };

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Requests")}</FrameTitle>
        <FrameDescription>
          {t(
            "Suppliers quote the same lines, and an award turns one quote into a purchase order.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The requests didn't load")}</AlertTitle>
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
                <FileQuestionMarkIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No requests yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Create a request, invite suppliers, then compare their quotes and award one.",
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
                  {t("Create a request")}
                </Button>
              ) : null}
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/rfqs"
              >
                {t("Read the requests guide")}
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
                  {t("Create a request")}
                </Button>
              </div>
            ) : null}
            <RfqGrid rfqs={state.data} />
          </div>
        )}
      </FramePanel>
    </Frame>
  );
}

export function RfqsSkeleton() {
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
