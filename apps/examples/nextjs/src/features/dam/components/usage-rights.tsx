"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { ImagesIcon, TriangleAlertIcon } from "lucide-react";
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

import type { Loaded, UsageRightRow } from "../dam-queries";

import { revokeUsageRight } from "../dam-actions";

type RightCell = CellContext<DataGridFeatures, UsageRightRow>;

function LicenseeCell({ row }: RightCell) {
  return <span className="font-medium">{row.original.licensee}</span>;
}

function ScopeCell({ row }: RightCell) {
  const t = useExtracted("dam");
  const { territory, channel } = row.original;

  return (
    <span className="text-muted-foreground">
      {territory ?? t("Everywhere")} / {channel ?? t("Every channel")}
    </span>
  );
}

function ExpiresCell({ row }: RightCell) {
  const format = useFormatter();
  const { expiresOn } = row.original;

  return (
    <span className="text-muted-foreground tabular-nums">
      {expiresOn === null
        ? "–"
        : format.dateTime(new Date(expiresOn), { dateStyle: "medium" })}
    </span>
  );
}

function StatusCell({ row }: RightCell) {
  const t = useExtracted("dam");

  switch (row.original.status) {
    case "active": {
      return <Badge variant="success-light">{t("Active")}</Badge>;
    }

    case "upcoming": {
      return <Badge variant="info-light">{t("Upcoming")}</Badge>;
    }

    case "expired": {
      return <Badge variant="warning-light">{t("Expired")}</Badge>;
    }

    case "revoked": {
      return <Badge variant="outline">{t("Revoked")}</Badge>;
    }

    default: {
      const never: never = row.original.status;

      return never;
    }
  }
}

function RightGrid({ rights }: { rights: readonly UsageRightRow[] }) {
  const t = useExtracted("dam");

  const columns: ColumnDef<DataGridFeatures, UsageRightRow>[] = [
    {
      accessorKey: "licensee",
      header: t("Licensee"),
      cell: LicenseeCell,
      size: 240,
    },
    {
      id: "scope",
      header: t("Territory and channel"),
      cell: ScopeCell,
      size: 240,
    },
    {
      accessorKey: "expiresOn",
      header: t("Expires"),
      cell: ExpiresCell,
      size: 160,
    },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 140 },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...rights],
    getRowId: (row) => row.id,
  });

  return (
    <DataGrid
      table={table}
      recordCount={rights.length}
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
 * The organization's usage rights in a data grid, the soonest to expire first.
 * Revoke ends the first active right on the list.
 */
export function UsageRights({
  state,
  canWrite,
}: {
  state: Loaded<readonly UsageRightRow[]>;
  canWrite: boolean;
}) {
  const t = useExtracted("dam");
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

  const next =
    state.kind === "ok"
      ? state.data.find((right) => right.status === "active")
      : undefined;

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Usage rights")}</FrameTitle>
        <FrameDescription>
          {t("Each right names a licensee, where it applies and when it ends.")}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The usage rights didn't load")}</AlertTitle>
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
                <ImagesIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No usage rights yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Grant a right on a file with a licensee, a territory and an expiry date, and the member who granted it is reminded before it ends.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/dam"
              >
                {t("Read the asset management guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <div className="flex flex-col gap-3">
            {canWrite && next !== undefined ? (
              <div className="flex justify-end">
                <Button
                  size="sm"
                  variant="outline"
                  type="button"
                  disabled={pending}
                  onClick={() => {
                    startTransition(async () => {
                      await revokeUsageRight({ id: next.id });
                      router.refresh();
                    });
                  }}
                >
                  {t("Revoke the next active right")}
                </Button>
              </div>
            ) : null}
            <RightGrid rights={state.data} />
          </div>
        )}
      </FramePanel>
    </Frame>
  );
}

export function UsageRightsSkeleton() {
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
