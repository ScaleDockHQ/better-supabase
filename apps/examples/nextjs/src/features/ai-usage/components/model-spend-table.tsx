"use client";

import type { CellContext } from "@tanstack/react-table";

import { CoinsIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListGrid } from "@/components/record-list/record-list-grid";

import type { ModelSpend } from "../ai-usage-queries";

type SpendCell = CellContext<ReadOnlyGridFeatures, ModelSpend>;

function TokensCell({ row }: SpendCell) {
  const format = useFormatter();
  const { inputTokens, outputTokens } = row.original;

  return (
    <span className="tabular-nums">
      {format.number(inputTokens)} / {format.number(outputTokens)}
    </span>
  );
}

function CostCell({ row }: SpendCell) {
  const format = useFormatter();

  return (
    <span className="tabular-nums">
      {format.number(row.original.costMicroUsd / 1_000_000, {
        style: "currency",
        currency: "USD",
        maximumFractionDigits: 4,
      })}
    </span>
  );
}

function RunsCell({ row }: SpendCell) {
  return <span className="tabular-nums">{row.original.runs}</span>;
}

/** Tokens and cost per model. */
export function ModelSpendTable({ models }: { models: readonly ModelSpend[] }) {
  const t = useExtracted("aiUsage");

  const columns: RecordListColumns<ModelSpend> = [
    { accessorKey: "model", header: t("Model"), size: 280 },
    { accessorKey: "runs", header: t("Runs"), size: 90, cell: RunsCell },
    { id: "tokens", header: t("Tokens in / out"), size: 180, cell: TokensCell },
    {
      accessorKey: "costMicroUsd",
      header: t("Cost"),
      size: 120,
      cell: CostCell,
    },
  ];

  return (
    <RecordListGrid
      rows={models}
      columns={columns}
      failed={false}
      pending={false}
      emptyIcon={<CoinsIcon />}
      emptyTitle={t("No spend yet")}
      emptyDescription={t("Runs appear here after the first answer.")}
      emptyAction={null}
      onRetry={() => undefined}
    />
  );
}
