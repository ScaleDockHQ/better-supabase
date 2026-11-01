"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { FileSignatureIcon, TriangleAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useRouter } from "next/navigation";
import { createContext, use, useMemo, useTransition } from "react";

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

import type { Loaded, PrescriptionRow } from "../prescriptions-queries";

import { cancelPrescription, signPrescription } from "../prescriptions-actions";

type PrescriptionCell = CellContext<DataGridFeatures, PrescriptionRow>;

function StatusCell({ row }: PrescriptionCell) {
  const t = useExtracted("prescriptions");

  switch (row.original.status) {
    case "draft": {
      return <Badge variant="warning-light">{t("Draft")}</Badge>;
    }

    case "signed": {
      return <Badge variant="info-light">{t("Signed")}</Badge>;
    }

    case "sent": {
      return <Badge variant="info-light">{t("Sent")}</Badge>;
    }

    case "dispensed": {
      return <Badge variant="success-light">{t("Dispensed")}</Badge>;
    }

    case "cancelled": {
      return <Badge variant="secondary">{t("Cancelled")}</Badge>;
    }

    default: {
      const never: never = row.original.status;

      return never;
    }
  }
}

function MedicationCell({ row }: PrescriptionCell) {
  const t = useExtracted("prescriptions");

  return (
    <span className="font-medium">
      {row.original.medication ?? t("Not signed yet")}
    </span>
  );
}

function SubjectCell({ row }: PrescriptionCell) {
  return <span className="text-muted-foreground">{row.original.subject}</span>;
}

interface RowActionsState {
  readonly canSign: boolean;
  readonly canCancel: boolean;
  readonly pending: boolean;
  readonly onSign: (prescriptionId: string) => void;
  readonly onCancel: (prescriptionId: string) => void;
}

const RowActionsContext = createContext<RowActionsState | null>(null);

function ActionsCell({ row }: PrescriptionCell) {
  const t = useExtracted("prescriptions");
  const actions = use(RowActionsContext);
  const { id, status } = row.original;

  if (actions === null || status !== "draft") {
    return null;
  }

  const { canSign, canCancel, pending, onSign, onCancel } = actions;

  return (
    <div className="flex gap-2">
      {canSign ? (
        <Button
          size="sm"
          variant="outline"
          type="button"
          disabled={pending}
          onClick={() => {
            onSign(id);
          }}
        >
          {t("Sign")}
        </Button>
      ) : null}
      {canCancel ? (
        <Button
          size="sm"
          variant="ghost"
          type="button"
          disabled={pending}
          onClick={() => {
            onCancel(id);
          }}
        >
          {t("Cancel")}
        </Button>
      ) : null}
    </div>
  );
}

function PrescriptionGrid({
  prescriptions,
  canSign,
  canCancel,
  pending,
  onSign,
  onCancel,
}: {
  prescriptions: readonly PrescriptionRow[];
  canSign: boolean;
  canCancel: boolean;
  pending: boolean;
  onSign: (prescriptionId: string) => void;
  onCancel: (prescriptionId: string) => void;
}) {
  const t = useExtracted("prescriptions");

  const actions = useMemo(
    () => ({ canSign, canCancel, pending, onSign, onCancel }),
    [canSign, canCancel, pending, onSign, onCancel],
  );

  const columns: ColumnDef<DataGridFeatures, PrescriptionRow>[] = [
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 130 },
    {
      accessorKey: "medication",
      header: t("Medication"),
      cell: MedicationCell,
      size: 280,
    },
    {
      accessorKey: "subject",
      header: t("Record"),
      cell: SubjectCell,
      size: 160,
    },
    { id: "actions", header: "", size: 180, cell: ActionsCell },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...prescriptions],
    getRowId: (row) => row.id,
  });

  return (
    <RowActionsContext value={actions}>
      <DataGrid
        table={table}
        recordCount={prescriptions.length}
        tableLayout={{ dense: true }}
      >
        <DataGridContainer>
          <DataGridScrollArea>
            <DataGridTable />
          </DataGridScrollArea>
        </DataGridContainer>
      </DataGrid>
    </RowActionsContext>
  );
}

/**
 * The organization's prescriptions with Sign for the prescriber's drafts and
 * Cancel for drafts. Delivery runs through the app's `PrescriptionGateway`.
 */
export function Prescriptions({
  state,
  canSign,
  canCancel,
}: {
  state: Loaded<readonly PrescriptionRow[]>;
  canSign: boolean;
  canCancel: boolean;
}) {
  const t = useExtracted("prescriptions");
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

  const sign = (prescriptionId: string) => {
    startTransition(async () => {
      await signPrescription({ prescriptionId });
      router.refresh();
    });
  };

  const cancel = (prescriptionId: string) => {
    startTransition(async () => {
      await cancelPrescription({ prescriptionId });
      router.refresh();
    });
  };

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Prescriptions")}</FrameTitle>
        <FrameDescription>
          {t(
            "Only the prescriber signs a draft. A signed prescription freezes the order.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The prescriptions didn't load")}</AlertTitle>
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
                <FileSignatureIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No prescriptions")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Draft a prescription from an active medication order, then sign it.",
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
                href="https://bettersupabase.com/docs/blocks/e-prescribing"
              >
                {t("Read the e-prescribing guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <PrescriptionGrid
            prescriptions={state.data}
            canSign={canSign}
            canCancel={canCancel}
            pending={pending}
            onSign={sign}
            onCancel={cancel}
          />
        )}
      </FramePanel>
    </Frame>
  );
}

export function PrescriptionsSkeleton() {
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
