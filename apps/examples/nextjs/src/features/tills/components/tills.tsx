"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { formatMoney, money } from "better-supabase/commerce";
import { CoinsIcon, TriangleAlertIcon } from "lucide-react";
import { useExtracted, useFormatter, useLocale } from "next-intl";
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

import type { Loaded, TillSessionRow } from "../tills-queries";

import { createTill } from "../tills-actions";

type SessionCell = CellContext<DataGridFeatures, TillSessionRow>;

function TillCell({ row }: SessionCell) {
  return <span className="font-medium">{row.original.till}</span>;
}

function OpenedCell({ row }: SessionCell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground tabular-nums">
      {format.dateTime(new Date(row.original.openedAt), {
        dateStyle: "medium",
        timeStyle: "short",
      })}
    </span>
  );
}

function ExpectedCell({ row }: SessionCell) {
  const locale = useLocale();
  const { expected, currency } = row.original;

  return (
    <span className="tabular-nums">
      {formatMoney(money(BigInt(expected), currency), locale)}
    </span>
  );
}

function StatusCell({ row }: SessionCell) {
  const t = useExtracted("tills");

  switch (row.original.status) {
    case "open": {
      return <Badge variant="info-light">{t("Open")}</Badge>;
    }

    case "closed": {
      return <Badge variant="success-light">{t("Closed")}</Badge>;
    }

    default: {
      const never: never = row.original.status;

      return never;
    }
  }
}

function SessionGrid({ sessions }: { sessions: readonly TillSessionRow[] }) {
  const t = useExtracted("tills");

  const columns: ColumnDef<DataGridFeatures, TillSessionRow>[] = [
    { accessorKey: "till", header: t("Till"), cell: TillCell, size: 220 },
    {
      accessorKey: "openedAt",
      header: t("Opened"),
      cell: OpenedCell,
      size: 200,
    },
    {
      accessorKey: "expected",
      header: t("Expected cash"),
      cell: ExpectedCell,
      size: 160,
    },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 140 },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...sessions],
    getRowId: (row) => row.id,
  });

  return (
    <DataGrid
      table={table}
      recordCount={sessions.length}
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
 * The organization's till sessions in a data grid. Add a till creates a euro
 * till without a cash account.
 */
export function Tills({
  state,
  canManage,
}: {
  state: Loaded<readonly TillSessionRow[]>;
  canManage: boolean;
}) {
  const t = useExtracted("tills");
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
      await createTill({ name: t("Front counter") });
      router.refresh();
    });
  };

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Sessions")}</FrameTitle>
        <FrameDescription>
          {t(
            "Each shift starts with a float, and the closing count books any difference.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The sessions didn't load")}</AlertTitle>
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
                <CoinsIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No sessions yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Add a till, open a session with its float, then count the drawer at the end of the day.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              {canManage ? (
                <Button
                  size="sm"
                  type="button"
                  disabled={pending}
                  onClick={register}
                >
                  {t("Add a till")}
                </Button>
              ) : null}
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/tills"
              >
                {t("Read the tills guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <div className="flex flex-col gap-3">
            {canManage ? (
              <div className="flex justify-end">
                <Button
                  size="sm"
                  variant="outline"
                  type="button"
                  disabled={pending}
                  onClick={register}
                >
                  {t("Add a till")}
                </Button>
              </div>
            ) : null}
            <SessionGrid sessions={state.data} />
          </div>
        )}
      </FramePanel>
    </Frame>
  );
}

export function TillsSkeleton() {
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
