"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { TriangleAlertIcon, ClipboardCheckIcon } from "lucide-react";
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

import type { Loaded, AppraisalRow } from "../appraisals-queries";

import { signOffAppraisal } from "../appraisals-actions";

type GridRow = AppraisalRow & { readonly canSign: boolean };

type AppraisalCell = CellContext<DataGridFeatures, GridRow>;

function SubjectCell({ row }: AppraisalCell) {
  return (
    <span className="font-medium tabular-nums">
      {row.original.subjectUserId.slice(0, 8)}
    </span>
  );
}

function RatingCell({ row }: AppraisalCell) {
  return (
    <span className="text-muted-foreground tabular-nums">
      {row.original.rating ?? "–"}
    </span>
  );
}

function StatusCell({ row }: AppraisalCell) {
  const t = useExtracted("appraisals");

  switch (row.original.status) {
    case "pending": {
      return <Badge variant="secondary">{t("In review")}</Badge>;
    }

    case "reviewed": {
      return <Badge variant="info-light">{t("Reviewed")}</Badge>;
    }

    case "calibrated": {
      return <Badge variant="info-light">{t("Calibrated")}</Badge>;
    }

    case "awaiting_signoff": {
      return <Badge variant="warning-light">{t("Awaiting sign-off")}</Badge>;
    }

    case "signed_off": {
      return <Badge variant="success-light">{t("Signed off")}</Badge>;
    }

    default: {
      const unreachable: never = row.original.status;

      return unreachable;
    }
  }
}

function SignOffCell({ row }: AppraisalCell) {
  const t = useExtracted("appraisals");
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const { id, canSign } = row.original;

  if (!canSign) {
    return null;
  }

  return (
    <Button
      size="sm"
      variant="outline"
      type="button"
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          await signOffAppraisal({ appraisalId: id });
          router.refresh();
        });
      }}
    >
      {t("Sign off")}
    </Button>
  );
}

function AppraisalGrid({
  rows,
  canManage,
}: {
  rows: readonly AppraisalRow[];
  canManage: boolean;
}) {
  const t = useExtracted("appraisals");

  const columns: ColumnDef<DataGridFeatures, GridRow>[] = [
    {
      accessorKey: "subjectUserId",
      header: t("Person"),
      cell: SubjectCell,
      size: 200,
    },
    { accessorKey: "rating", header: t("Rating"), cell: RatingCell, size: 120 },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 200 },
    { id: "actions", header: "", cell: SignOffCell, size: 120 },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: rows.map((row) => ({
      ...row,
      canSign:
        canManage && (row.status === "reviewed" || row.status === "calibrated"),
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
 * The appraisals the caller reads in a data grid. A manager signs reviewed and
 * calibrated appraisals off; with approvals the sign-off waits for its
 * request.
 */
export function AppraisalList({
  state,
  canManage,
}: {
  state: Loaded<readonly AppraisalRow[]>;
  canManage: boolean;
}) {
  const t = useExtracted("appraisals");
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  if (state.kind === "no-organization") {
    return null;
  }

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Appraisals")}</FrameTitle>
        <FrameDescription>
          {t(
            "One appraisal per person in a review cycle, with its rating and where it stands.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The appraisals didn't load")}</AlertTitle>
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
                <ClipboardCheckIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No appraisals yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Open a review cycle with the people to review, and each gets an appraisal with self, peer and manager reviews.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/appraisals"
              >
                {t("Read the appraisals guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <AppraisalGrid rows={state.data} canManage={canManage} />
        )}
      </FramePanel>
    </Frame>
  );
}

export function AppraisalListSkeleton() {
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
