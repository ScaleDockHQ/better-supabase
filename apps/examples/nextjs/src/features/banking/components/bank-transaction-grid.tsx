"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";
import type { BankTransactionStatus } from "better-supabase/blocks/banking";

import { useTable } from "@tanstack/react-table";
import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { useAction } from "better-supabase/react";
import { useExtracted, useFormatter, useLocale } from "next-intl";
import { createContext, use, useCallback, useMemo } from "react";
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

import type { BankTransactionRow } from "../banking-queries";

import {
  ignoreBankTransaction,
  matchBankTransaction,
} from "../banking-actions";

type TransactionCell = CellContext<DataGridFeatures, BankTransactionRow>;

interface Reconcile {
  readonly allowed: boolean;
  readonly pending: boolean;
  match: (transactionId: string, invoiceId: string) => Promise<void>;
  ignore: (transactionId: string) => Promise<void>;
}

const ReconcileContext = createContext<Reconcile | null>(null);

function useReconcile(): Reconcile {
  const reconcile = use(ReconcileContext);

  if (reconcile === null) {
    throw new Error("Render transaction cells inside BankTransactionGrid.");
  }

  return reconcile;
}

function BookedCell({ row }: TransactionCell) {
  const format = useFormatter();

  return (
    <span className="tabular-nums">
      {format.dateTime(new Date(row.original.bookedOn), {
        dateStyle: "medium",
        timeZone: "UTC",
      })}
    </span>
  );
}

function CounterpartyCell({ row }: TransactionCell) {
  const { counterparty, remittance } = row.original;

  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      <span className="truncate font-medium">{counterparty ?? "–"}</span>
      {remittance === null ? null : (
        <span className="truncate text-xs text-muted-foreground">
          {remittance}
        </span>
      )}
    </div>
  );
}

function AmountCell({ row }: TransactionCell) {
  const locale = useLocale();

  return (
    <span className="tabular-nums">
      {formatMoney(moneyFromJson(row.original.amount), locale)}
    </span>
  );
}

function StatusCell({ row }: TransactionCell) {
  const t = useExtracted("banking");
  const status: BankTransactionStatus = row.original.status;

  switch (status) {
    case "unmatched": {
      return <Badge variant="warning-light">{t("Unmatched")}</Badge>;
    }

    case "matched": {
      return <Badge variant="success-light">{t("Matched")}</Badge>;
    }

    case "ignored": {
      return <Badge variant="secondary">{t("Ignored")}</Badge>;
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}

function ActionCell({ row }: TransactionCell) {
  const t = useExtracted("banking");
  const locale = useLocale();
  const { allowed, pending, match, ignore } = useReconcile();
  const { id, status, suggestion } = row.original;

  if (status !== "unmatched") {
    return null;
  }

  if (!allowed) {
    return suggestion === null ? null : (
      <span className="text-xs text-muted-foreground">{suggestion.label}</span>
    );
  }

  return (
    <div className="flex items-center justify-end gap-2">
      {suggestion === null ? null : (
        <Button
          size="sm"
          type="button"
          disabled={pending}
          onClick={() => {
            void match(id, suggestion.targetId);
          }}
        >
          {t("Match {invoice} ({balance})", {
            invoice: suggestion.label,
            balance: formatMoney(moneyFromJson(suggestion.balance), locale),
          })}
        </Button>
      )}
      <Button
        size="sm"
        variant="outline"
        type="button"
        disabled={pending}
        onClick={() => {
          void ignore(id);
        }}
      >
        {t("Ignore")}
      </Button>
    </div>
  );
}

/**
 * The account's latest transactions. An unmatched one offers its best invoice
 * suggestion to match, and can be ignored when there is nothing to book.
 */
export function BankTransactionGrid({
  transactions,
  canReconcile,
}: {
  transactions: readonly BankTransactionRow[];
  canReconcile: boolean;
}) {
  const t = useExtracted("banking");
  const errorMessage = useErrorMessage();

  const matchAction = useAction(matchBankTransaction);
  const ignoreAction = useAction(ignoreBankTransaction);

  const match = useCallback(
    async (transactionId: string, invoiceId: string) => {
      const result = await matchAction.run({ transactionId, invoiceId });

      if (!result.ok) {
        toast.error(errorMessage(result.error));
      }
    },
    [matchAction, errorMessage],
  );

  const ignore = useCallback(
    async (transactionId: string) => {
      const result = await ignoreAction.run({ transactionId });

      if (!result.ok) {
        toast.error(errorMessage(result.error));
      }
    },
    [ignoreAction, errorMessage],
  );

  const reconcile = useMemo(
    (): Reconcile => ({
      allowed: canReconcile,
      pending: matchAction.pending || ignoreAction.pending,
      match,
      ignore,
    }),
    [canReconcile, matchAction.pending, ignoreAction.pending, match, ignore],
  );

  const columns: ColumnDef<DataGridFeatures, BankTransactionRow>[] = [
    {
      accessorKey: "bookedOn",
      header: t("Booked"),
      cell: BookedCell,
      size: 120,
    },
    {
      accessorKey: "counterparty",
      header: t("Counterparty"),
      cell: CounterpartyCell,
      size: 280,
    },
    { accessorKey: "amount", header: t("Amount"), cell: AmountCell, size: 130 },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 120 },
    { id: "actions", header: "", cell: ActionCell, size: 300 },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...transactions],
    getRowId: (row) => row.id,
  });

  return (
    <ReconcileContext value={reconcile}>
      <DataGrid
        table={table}
        recordCount={transactions.length}
        tableLayout={{ dense: true }}
      >
        <DataGridContainer>
          <DataGridScrollArea>
            <DataGridTable />
          </DataGridScrollArea>
        </DataGridContainer>
      </DataGrid>
    </ReconcileContext>
  );
}
