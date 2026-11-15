"use client";

import type { CellContext } from "@tanstack/react-table";

import { UsersIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListGrid } from "@/components/record-list/record-list-grid";
import { useRouter } from "@/i18n/navigation";

import type { UserSpend } from "../ai-usage-queries";

type SpendCell = CellContext<ReadOnlyGridFeatures, UserSpend>;

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

/** Runs, tokens and cost per member of the organization. */
export function UserSpendTable({
  users,
  failed,
}: {
  users: readonly UserSpend[];
  failed: boolean;
}) {
  const t = useExtracted("aiUsage");
  const router = useRouter();

  const columns: RecordListColumns<UserSpend> = [
    { accessorKey: "name", header: t("Member"), size: 280 },
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
      rows={users}
      columns={columns}
      failed={failed}
      pending={false}
      emptyIcon={<UsersIcon />}
      emptyTitle={t("No member spend yet")}
      emptyDescription={t(
        "Members appear here after their first answer in this range.",
      )}
      emptyAction={null}
      onRetry={() => {
        router.refresh();
      }}
    />
  );
}
