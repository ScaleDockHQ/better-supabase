"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { useAction } from "better-supabase/react";
import { useExtracted, useFormatter } from "next-intl";
import { toast } from "sonner";

import type { DataGridFeatures } from "@/components/reui/data-grid/data-grid";

import { Badge } from "@/components/reui/badge";
import {
  DataGrid,
  DataGridContainer,
  dataGridFeatures,
} from "@/components/reui/data-grid/data-grid";
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area";
import { DataGridTable } from "@/components/reui/data-grid/data-grid-table";
import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import type { RequirementRow } from "../manufacturing-queries";

import { createFromRequirements } from "../manufacturing-actions";

type RequirementCell = CellContext<DataGridFeatures, RequirementRow>;

function ProductCell({ row }: RequirementCell) {
  const t = useExtracted("production");

  return (
    <span className="truncate font-medium">
      {row.original.product ?? t("Unknown product")}
    </span>
  );
}

function ActionCell({ row }: RequirementCell) {
  const t = useExtracted("production");
  const { action } = row.original;

  switch (action) {
    case "produce": {
      return <Badge variant="info-light">{t("Produce")}</Badge>;
    }

    case "purchase": {
      return <Badge variant="secondary">{t("Purchase")}</Badge>;
    }

    default: {
      const unknown: never = action;

      return unknown;
    }
  }
}

function Quantity({ value }: { value: number }) {
  const format = useFormatter();

  return <span className="tabular-nums">{format.number(value)}</span>;
}

const shortCell = ({ row }: RequirementCell) => (
  <Quantity value={row.original.quantity} />
);

const availableCell = ({ row }: RequirementCell) => (
  <Quantity value={row.original.available} />
);

const incomingCell = ({ row }: RequirementCell) => (
  <Quantity value={row.original.incoming} />
);

const plannedCell = ({ row }: RequirementCell) => (
  <Quantity value={row.original.planned} />
);

const demandCell = ({ row }: RequirementCell) => (
  <Quantity value={row.original.demand} />
);

/** Each shortage with what covers it: an order to produce or to buy. */
export function MaterialRequirementsGrid({
  requirements,
}: {
  requirements: readonly RequirementRow[];
}) {
  const t = useExtracted("production");

  const columns: ColumnDef<DataGridFeatures, RequirementRow>[] = [
    {
      accessorKey: "product",
      header: t("Product"),
      cell: ProductCell,
      size: 260,
    },
    { accessorKey: "action", header: t("Action"), cell: ActionCell, size: 120 },
    {
      accessorKey: "quantity",
      header: t("Short by"),
      cell: shortCell,
      size: 110,
    },
    {
      accessorKey: "available",
      header: t("Available"),
      cell: availableCell,
      size: 110,
    },
    {
      accessorKey: "incoming",
      header: t("Incoming"),
      cell: incomingCell,
      size: 110,
    },
    {
      accessorKey: "planned",
      header: t("Planned"),
      cell: plannedCell,
      size: 110,
    },
    { accessorKey: "demand", header: t("Demand"), cell: demandCell, size: 110 },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...requirements],
    getRowId: (row) => `${row.variantId}:${row.action}`,
  });

  return (
    <DataGrid
      table={table}
      recordCount={requirements.length}
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

/** Creates the draft orders for every shortage the grid lists. */
export function CreateFromRequirementsButton() {
  const t = useExtracted("production");
  const errorMessage = useErrorMessage();
  const create = useAction(createFromRequirements);

  async function run() {
    const result = await create.run({});

    if (!result.ok) {
      toast.error(errorMessage(result.error));

      return;
    }

    toast.success(
      t(
        "{productionOrders, number} production orders and {purchases, number} purchases created as drafts.",
        result.data,
      ),
    );
  }

  return (
    <Button
      size="sm"
      type="button"
      disabled={create.pending}
      onClick={() => {
        void run();
      }}
    >
      {t("Create orders")}
    </Button>
  );
}
