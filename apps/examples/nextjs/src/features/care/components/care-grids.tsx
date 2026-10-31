"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";
import type { ConsentStatus } from "better-supabase/blocks/consents";

import { useTable } from "@tanstack/react-table";
import { useExtracted, useFormatter } from "next-intl";

import type { DataGridFeatures } from "@/components/reui/data-grid/data-grid";

import { Badge } from "@/components/reui/badge";
import {
  DataGrid,
  DataGridContainer,
  dataGridFeatures,
} from "@/components/reui/data-grid/data-grid";
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area";
import { DataGridTable } from "@/components/reui/data-grid/data-grid-table";
import { useStatusLabel } from "@/features/customers/use-status-label";
import { Link } from "@/i18n/navigation";

import type { AccessRow, ClientRow, ConsentRow } from "../care-queries";

function Grid<T extends { readonly id: string }>({
  rows,
  columns,
}: {
  rows: readonly T[];
  columns: ColumnDef<DataGridFeatures, T>[];
}) {
  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...rows],
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

function ClientNameCell({ row }: CellContext<DataGridFeatures, ClientRow>) {
  return (
    <Link
      href={`/care/${row.original.id}`}
      prefetch
      className="font-medium hover:underline"
    >
      {row.original.name}
    </Link>
  );
}

function ClientStatusCell({ row }: CellContext<DataGridFeatures, ClientRow>) {
  const label = useStatusLabel();
  const { status } = row.original;

  return (
    <Badge variant={status === "active" ? "success-light" : "secondary"}>
      {label(status)}
    </Badge>
  );
}

/** The caller's clients, each linking to their dossier. */
export function ClientsGrid({ clients }: { clients: readonly ClientRow[] }) {
  const t = useExtracted("care");

  return (
    <Grid
      rows={clients}
      columns={[
        {
          accessorKey: "name",
          header: t("Client"),
          cell: ClientNameCell,
          size: 280,
        },
        {
          accessorKey: "status",
          header: t("Status"),
          cell: ClientStatusCell,
          size: 140,
        },
      ]}
    />
  );
}

function useConsentStatusLabel(): (status: ConsentStatus) => string {
  const t = useExtracted("care");

  return (status) => {
    switch (status) {
      case "granted": {
        return t("Granted");
      }

      case "refused": {
        return t("Refused");
      }

      case "withdrawn": {
        return t("Withdrawn");
      }

      case "expired": {
        return t("Expired");
      }

      default: {
        const unknown: never = status;

        return unknown;
      }
    }
  };
}

function ConsentStatusCell({ row }: CellContext<DataGridFeatures, ConsentRow>) {
  const label = useConsentStatusLabel();
  const { status } = row.original;

  return (
    <Badge
      variant={
        status === "granted"
          ? "success-light"
          : status === "refused"
            ? "destructive-light"
            : "secondary"
      }
    >
      {label(status)}
    </Badge>
  );
}

function DateText({ value }: { value: string | null }) {
  const format = useFormatter();

  return value === null ? (
    <span className="text-muted-foreground">-</span>
  ) : (
    <time dateTime={value} className="tabular-nums">
      {format.dateTime(new Date(value), { dateStyle: "medium" })}
    </time>
  );
}

function GrantedCell({ row }: CellContext<DataGridFeatures, ConsentRow>) {
  return <DateText value={row.original.grantedAt} />;
}

function ValidUntilCell({ row }: CellContext<DataGridFeatures, ConsentRow>) {
  return <DateText value={row.original.validUntil} />;
}

/** The client's latest decision per purpose. */
export function ConsentsGrid({
  consents,
}: {
  consents: readonly ConsentRow[];
}) {
  const t = useExtracted("care");

  return (
    <Grid
      rows={consents}
      columns={[
        { accessorKey: "purpose", header: t("Purpose"), size: 220 },
        { accessorKey: "version", header: t("Version"), size: 100 },
        {
          accessorKey: "status",
          header: t("Status"),
          cell: ConsentStatusCell,
          size: 130,
        },
        {
          accessorKey: "grantedAt",
          header: t("Decided"),
          cell: GrantedCell,
          size: 140,
        },
        {
          accessorKey: "validUntil",
          header: t("Valid until"),
          cell: ValidUntilCell,
          size: 140,
        },
      ]}
    />
  );
}

function ReaderCell({ row }: CellContext<DataGridFeatures, AccessRow>) {
  const t = useExtracted("care");
  const { reader, emergency } = row.original;

  return (
    <span className="flex items-center gap-2">
      <span className="font-medium">{reader ?? t("Unknown member")}</span>
      {emergency ? (
        <Badge variant="warning-light">{t("Emergency")}</Badge>
      ) : null}
    </span>
  );
}

function ReadAtCell({ row }: CellContext<DataGridFeatures, AccessRow>) {
  const format = useFormatter();
  const { at } = row.original;

  return (
    <time dateTime={at} className="tabular-nums">
      {format.dateTime(new Date(at), {
        dateStyle: "medium",
        timeStyle: "short",
      })}
    </time>
  );
}

function MutedText({ value }: { value: string | null }) {
  return <span className="text-muted-foreground">{value ?? "-"}</span>;
}

function PurposeCell({ row }: CellContext<DataGridFeatures, AccessRow>) {
  return <MutedText value={row.original.purpose} />;
}

function SourceCell({ row }: CellContext<DataGridFeatures, AccessRow>) {
  return <MutedText value={row.original.source} />;
}

/** Who read the client's record and when, newest first. */
export function AccessLogGrid({ reads }: { reads: readonly AccessRow[] }) {
  const t = useExtracted("care");

  return (
    <Grid
      rows={reads}
      columns={[
        {
          accessorKey: "reader",
          header: t("Read by"),
          cell: ReaderCell,
          size: 220,
        },
        { accessorKey: "at", header: t("When"), cell: ReadAtCell, size: 180 },
        {
          accessorKey: "purpose",
          header: t("Purpose"),
          cell: PurposeCell,
          size: 140,
        },
        {
          accessorKey: "source",
          header: t("Through"),
          cell: SourceCell,
          size: 220,
        },
      ]}
    />
  );
}
